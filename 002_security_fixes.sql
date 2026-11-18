-- Run AFTER supabase/schema.sql. Fixes: public RPC access, payment amount checks,
-- paid-after-expiry handling, advance balance, blocked slots, payment event log.

alter table public.bookings add column if not exists paid_amount integer not null default 0 check (paid_amount >= 0);
alter table public.payments add column if not exists needs_refund boolean not null default false;

create table if not exists public.payment_events (
  id bigserial primary key,
  payment_id uuid references public.payments(id) on delete set null,
  event_type text not null,
  payload jsonb not null,
  created_at timestamptz not null default now()
);
create table if not exists public.blocked_slots (
  id uuid primary key default gen_random_uuid(),
  blocked_date date not null,
  start_time time,                       -- null = whole day
  reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create unique index if not exists uq_blocked on public.blocked_slots(blocked_date, coalesce(start_time,'00:00'::time), (start_time is null));
create table if not exists public.cancellation_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  requested_by uuid references auth.users(id),
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  refund_amount integer not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.site_settings (key text primary key, value jsonb not null, updated_at timestamptz not null default now());

alter table public.payment_events enable row level security;       -- no client policies: server only
alter table public.blocked_slots enable row level security;
alter table public.cancellation_requests enable row level security;
alter table public.site_settings enable row level security;
create policy "public read settings" on public.site_settings for select using (true);
create policy "own cancellation requests" on public.cancellation_requests for select to authenticated using (requested_by = auth.uid());

-- FIX 1: booking creation is server-only (browser could previously call it with its own price/hold time).
create or replace function public.create_turf_booking(
  p_booking_date date, p_start_time time, p_end_time time,
  p_user_id uuid, p_customer_name text, p_phone text, p_email text,
  p_total_amount integer, p_payable_amount integer, p_payment_type text,
  p_hold_minutes integer default 10
) returns setof public.bookings
language plpgsql security definer set search_path=public as $$
declare v_booking public.bookings; v_hold int := least(greatest(coalesce(p_hold_minutes,10),5),30);
begin
  if exists (select 1 from public.blocked_slots
             where blocked_date = p_booking_date and (start_time is null or start_time = p_start_time))
    then raise exception 'SLOT_NOT_AVAILABLE'; end if;
  update public.bookings set status='expired'
   where booking_date=p_booking_date and start_time=p_start_time
     and status='held' and hold_expires_at < now();
  insert into public.bookings(booking_code,user_id,customer_name,phone,email,booking_date,start_time,end_time,
    total_amount,payable_amount,payment_type,status,hold_expires_at)
  values ('CRA-'||to_char(now() at time zone 'Asia/Dhaka','YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    p_user_id,p_customer_name,p_phone,p_email,p_booking_date,p_start_time,p_end_time,
    p_total_amount,p_payable_amount,p_payment_type,'held',now()+make_interval(mins=>v_hold))
  returning * into v_booking;
  return next v_booking;
exception when unique_violation then raise exception 'SLOT_NOT_AVAILABLE';
end; $$;
revoke all on function public.create_turf_booking(date,time,time,uuid,text,text,text,integer,integer,text,integer) from public, anon, authenticated;
grant execute on function public.create_turf_booking(date,time,time,uuid,text,text,text,integer,integer,text,integer) to service_role;

-- FIX 2-4: verified amount/currency, paid_amount, paid-after-expiry handling.
drop function if exists public.confirm_booking_payment(uuid,text,jsonb);
create or replace function public.confirm_booking_payment(
  p_payment_id uuid, p_provider_transaction_id text, p_provider_payload jsonb,
  p_amount integer, p_currency text
) returns text language plpgsql security definer set search_path=public as $$
declare pay public.payments; b public.bookings;
begin
  select * into pay from public.payments where id=p_payment_id for update;
  if not found then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if pay.status='paid' then return 'already_paid'; end if;          -- duplicate callback
  if p_currency <> 'BDT' or p_amount <> pay.amount then raise exception 'AMOUNT_MISMATCH'; end if;
  select * into b from public.bookings where id=pay.booking_id for update;

  update public.payments set status='paid', provider_transaction_id=p_provider_transaction_id,
         provider_payload=p_provider_payload where id=pay.id;

  if b.status in ('held','expired') then
    begin   -- an expired hold is revived only if nobody else took the slot meanwhile
      update public.bookings set status='confirmed', hold_expires_at=null, paid_amount=pay.amount where id=b.id;
      return 'confirmed';
    exception when unique_violation then
      update public.payments set needs_refund=true where id=pay.id;
      return 'needs_refund';
    end;
  end if;
  update public.payments set needs_refund=true where id=pay.id;     -- cancelled/other state: admin must refund
  return 'needs_refund';
end; $$;
revoke all on function public.confirm_booking_payment(uuid,text,jsonb,integer,text) from public, anon, authenticated;
grant execute on function public.confirm_booking_payment(uuid,text,jsonb,integer,text) to service_role;
