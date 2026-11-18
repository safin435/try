create extension if not exists pgcrypto;

create type public.app_role as enum ('customer','admin');
create type public.booking_status as enum ('held','confirmed','cancelled','completed','blocked','expired');
create type public.payment_status as enum ('pending','paid','failed','refunded','partial');

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  role public.app_role not null default 'customer',
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  booking_code text not null unique,
  user_id uuid references auth.users(id) on delete set null,
  customer_name text not null,
  phone text not null,
  email text,
  booking_date date not null,
  start_time time not null,
  end_time time not null,
  total_amount integer not null check(total_amount > 0),
  payable_amount integer not null check(payable_amount > 0),
  payment_type text not null check(payment_type in ('full','advance')),
  status public.booking_status not null default 'held',
  hold_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint booking_time_valid check(end_time > start_time)
);

create unique index if not exists one_active_booking_per_slot
on public.bookings(booking_date,start_time)
where status in ('held','confirmed','blocked');

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  provider text not null check(provider in ('bkash','nagad')),
  provider_payment_id text unique,
  provider_transaction_id text unique,
  amount integer not null check(amount > 0),
  currency text not null default 'BDT',
  status public.payment_status not null default 'pending',
  provider_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_audit_logs (
  id bigserial primary key,
  admin_user_id uuid references auth.users(id),
  action text not null,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.bookings enable row level security;
alter table public.payments enable row level security;
alter table public.admin_audit_logs enable row level security;

create policy "profiles read own" on public.profiles for select to authenticated using (id=auth.uid());
create policy "profiles update own name" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy "customers read own bookings" on public.bookings for select to authenticated using (user_id=auth.uid());
create policy "customers read own payments" on public.payments for select to authenticated using (
  exists(select 1 from public.bookings b where b.id=booking_id and b.user_id=auth.uid())
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end; $$;
create trigger bookings_updated_at before update on public.bookings for each row execute function public.set_updated_at();
create trigger payments_updated_at before update on public.payments for each row execute function public.set_updated_at();

create or replace function public.create_turf_booking(
  p_booking_date date, p_start_time time, p_end_time time,
  p_user_id uuid, p_customer_name text, p_phone text, p_email text,
  p_total_amount integer, p_payable_amount integer, p_payment_type text,
  p_hold_minutes integer default 10
) returns setof public.bookings
language plpgsql security definer set search_path=public as $$
declare v_booking public.bookings;
begin
  -- Release expired holds before attempting the unique slot reservation.
  update public.bookings set status='expired'
   where booking_date=p_booking_date and start_time=p_start_time
     and status='held' and hold_expires_at < now();
  insert into public.bookings(
    booking_code,user_id,customer_name,phone,email,booking_date,start_time,end_time,
    total_amount,payable_amount,payment_type,status,hold_expires_at
  ) values (
    'CRA-'||to_char(now() at time zone 'Asia/Dhaka','YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    p_user_id,p_customer_name,p_phone,p_email,p_booking_date,p_start_time,p_end_time,
    p_total_amount,p_payable_amount,p_payment_type,'held',now()+make_interval(mins=>p_hold_minutes)
  ) returning * into v_booking;
  return next v_booking;
exception when unique_violation then
  raise exception 'SLOT_NOT_AVAILABLE';
end; $$;

create or replace function public.confirm_booking_payment(
  p_payment_id uuid, p_provider_transaction_id text, p_provider_payload jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare v_booking_id uuid;
begin
  update public.payments set status='paid',provider_transaction_id=p_provider_transaction_id,
    provider_payload=p_provider_payload,updated_at=now()
    where id=p_payment_id and status='pending' returning booking_id into v_booking_id;
  if v_booking_id is null then
    if exists(select 1 from public.payments where id=p_payment_id and status='paid') then return; end if;
    raise exception 'PAYMENT_NOT_PENDING';
  end if;
  update public.bookings set status='confirmed',hold_expires_at=null,updated_at=now()
    where id=v_booking_id and status='held';
  if not found then raise exception 'BOOKING_NOT_HELD'; end if;
end; $$;

-- Admin role must be assigned manually by the project owner through the SQL editor:
-- update public.profiles set role='admin' where id='AUTH_USER_UUID';
-- Never allow public users to update their own role.
revoke all on function public.create_turf_booking(date,time,time,uuid,text,text,text,integer,integer,text,integer) from public;
grant execute on function public.create_turf_booking(date,time,time,uuid,text,text,text,integer,integer,text,integer) to anon, authenticated;
revoke all on function public.confirm_booking_payment(uuid,text,jsonb) from public;
grant execute on function public.confirm_booking_payment(uuid,text,jsonb) to service_role;
