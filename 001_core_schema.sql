-- CHORBAKOR ARENA: core schema (Supabase / PostgreSQL)
-- Run in the Supabase SQL editor or via `supabase db push`.
create extension if not exists pgcrypto;

-- ---------- Roles & profiles ----------
create table roles (
  id smallserial primary key,
  name text unique not null check (name in ('customer','staff','admin'))
);
insert into roles(name) values ('customer'),('staff'),('admin');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role_id smallint not null references roles(id) default 1,
  full_name text,
  phone text unique,
  email text unique,
  language text not null default 'bn' check (language in ('bn','en')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p join roles r on r.id = p.role_id
                 where p.id = auth.uid() and r.name in ('staff','admin'));
$$;
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p join roles r on r.id = p.role_id
                 where p.id = auth.uid() and r.name = 'admin');
$$;

-- ---------- Settings ----------
create table site_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
insert into site_settings(key, value) values
 ('slot_price_bdt','2200'), ('advance_amount_bdt','500'),
 ('hold_minutes','10'), ('cancellation_notice_hours','24'),
 ('timezone','"Asia/Dhaka"'), ('currency','"BDT"');

-- ---------- Slot definitions (8 fixed daily slots) ----------
create table booking_slots (
  id smallint primary key,
  start_time time not null,
  end_time time not null,
  label_en text not null,
  label_bn text not null,
  price_bdt integer not null default 2200 check (price_bdt > 0),
  is_active boolean not null default true
);
insert into booking_slots(id,start_time,end_time,label_en,label_bn) values
 (1,'08:00','10:00','08:00 AM – 10:00 AM','সকাল ০৮:০০ – ১০:০০'),
 (2,'10:00','12:00','10:00 AM – 12:00 PM','সকাল ১০:০০ – দুপুর ১২:০০'),
 (3,'12:00','14:00','12:00 PM – 02:00 PM','দুপুর ১২:০০ – ০২:০০'),
 (4,'14:00','16:00','02:00 PM – 04:00 PM','দুপুর ০২:০০ – ০৪:০০'),
 (5,'16:00','18:00','04:00 PM – 06:00 PM','বিকাল ০৪:০০ – ০৬:০০'),
 (6,'18:00','20:00','06:00 PM – 08:00 PM','সন্ধ্যা ০৬:০০ – ০৮:০০'),
 (7,'20:00','22:00','08:00 PM – 10:00 PM','রাত ০৮:০০ – ১০:০০'),
 (8,'22:00','23:59:59','10:00 PM – 12:00 AM','রাত ১০:০০ – ১২:০০');

-- ---------- Bookings ----------
create table bookings (
  id uuid primary key default gen_random_uuid(),
  booking_ref text unique not null
    default 'CA-' || upper(substr(encode(gen_random_bytes(6),'hex'),1,10)),
  user_id uuid references profiles(id),            -- null for guest bookings
  guest_name text, guest_phone text, guest_email text,
  slot_date date not null,
  slot_id smallint not null references booking_slots(id),
  total_bdt integer not null check (total_bdt > 0),
  paid_bdt integer not null default 0 check (paid_bdt >= 0),
  payment_option text not null check (payment_option in ('full','advance')),
  status text not null default 'held'
    check (status in ('held','confirmed','completed','cancelled','expired','no_show')),
  qr_token text unique not null default encode(gen_random_bytes(24),'hex'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (user_id is not null or (guest_name is not null and guest_phone is not null)),
  check (paid_bdt <= total_bdt)
);
-- THE double-booking guard: only one active booking per date+slot, enforced by the DB.
create unique index uq_active_booking_slot
  on bookings (slot_date, slot_id) where status in ('held','confirmed');
create index ix_bookings_user on bookings(user_id);
create index ix_bookings_date on bookings(slot_date, status);

create table booking_holds (
  booking_id uuid primary key references bookings(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index ix_holds_expiry on booking_holds(expires_at);

-- ---------- Blocked slots ----------
create table blocked_slots (
  id uuid primary key default gen_random_uuid(),
  slot_date date not null,
  slot_id smallint references booking_slots(id),   -- null = whole day blocked
  reason text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create unique index uq_blocked on blocked_slots (slot_date, coalesce(slot_id, 0));

-- ---------- Payments ----------
create table payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  provider text not null check (provider in ('bkash','nagad')),
  amount_bdt integer not null check (amount_bdt > 0),
  currency text not null default 'BDT' check (currency = 'BDT'),
  provider_payment_id text,       -- bKash paymentID / Nagad payment ref
  provider_trx_id text,           -- final transaction ID after execute/verify
  status text not null default 'initiated'
    check (status in ('initiated','pending','verified','failed','cancelled','refunded','refund_requested')),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- A provider transaction ID can only ever be recorded once (duplicate-callback protection).
create unique index uq_provider_trx on payments(provider, provider_trx_id) where provider_trx_id is not null;
create unique index uq_provider_payment on payments(provider, provider_payment_id) where provider_payment_id is not null;
create index ix_payments_booking on payments(booking_id);

create table payment_events (               -- append-only log of every callback / API response
  id bigserial primary key,
  payment_id uuid references payments(id),
  event_type text not null,
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create table cancellation_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  requested_by uuid references profiles(id),
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  refund_bdt integer default 0,
  reviewed_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id),
  booking_id uuid references bookings(id),
  channel text not null check (channel in ('email','sms','admin')),
  kind text not null,
  status text not null default 'queued' check (status in ('queued','sent','failed')),
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create table audit_logs (
  id bigserial primary key,
  actor_id uuid references profiles(id),
  action text not null,
  entity text not null,
  entity_id text,
  details jsonb,
  created_at timestamptz not null default now()
);

-- ---------- Atomic RPCs (call from server only, with service role) ----------

-- Reserve a slot and create a hold. The unique index makes this race-safe.
create or replace function create_booking_hold(
  p_date date, p_slot smallint, p_option text,
  p_user uuid, p_name text, p_phone text, p_email text
) returns bookings language plpgsql security definer set search_path = public as $$
declare
  v_price int; v_adv int; v_hold int; v_b bookings;
begin
  if p_option not in ('full','advance') then raise exception 'invalid_option'; end if;
  if p_date < (now() at time zone 'Asia/Dhaka')::date then raise exception 'date_in_past'; end if;
  if exists (select 1 from blocked_slots
             where slot_date = p_date and (slot_id is null or slot_id = p_slot))
    then raise exception 'slot_blocked'; end if;

  perform release_expired_holds();
  select price_bdt into v_price from booking_slots where id = p_slot and is_active;
  if v_price is null then raise exception 'slot_inactive'; end if;
  select (value #>> '{}')::int into v_adv  from site_settings where key='advance_amount_bdt';
  select (value #>> '{}')::int into v_hold from site_settings where key='hold_minutes';

  begin
    insert into bookings(user_id,guest_name,guest_phone,guest_email,slot_date,slot_id,
                         total_bdt,payment_option,status)
    values (p_user,p_name,p_phone,p_email,p_date,p_slot,v_price,p_option,'held')
    returning * into v_b;
  exception when unique_violation then
    raise exception 'slot_unavailable';
  end;

  insert into booking_holds(booking_id, expires_at)
  values (v_b.id, now() + make_interval(mins => v_hold));
  return v_b;
end $$;

create or replace function release_expired_holds() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with exp as (
    delete from booking_holds where expires_at < now() returning booking_id
  )
  update bookings set status='expired', updated_at=now()
  where id in (select booking_id from exp) and status='held';
  get diagnostics n = row_count;
  return n;
end $$;

-- Called ONLY after the server has verified the payment with bKash/Nagad's API.
-- Re-checks amount and currency, is idempotent, and confirms the booking atomically.
create or replace function confirm_verified_payment(
  p_payment uuid, p_trx_id text, p_verified_amount int, p_currency text
) returns bookings language plpgsql security definer set search_path = public as $$
declare pay payments; b bookings; expected int;
begin
  select * into pay from payments where id = p_payment for update;
  if not found then raise exception 'payment_not_found'; end if;
  select * into b from bookings where id = pay.booking_id for update;

  if pay.status = 'verified' then return b; end if;     -- duplicate callback: no-op
  if p_currency <> 'BDT' then raise exception 'currency_mismatch'; end if;
  expected := case when b.payment_option='full' then b.total_bdt
                   else (select (value #>> '{}')::int from site_settings where key='advance_amount_bdt') end;
  if p_verified_amount <> expected or pay.amount_bdt <> expected then
    raise exception 'amount_mismatch'; end if;
  if b.status not in ('held','confirmed') then raise exception 'booking_not_payable'; end if;

  update payments set status='verified', provider_trx_id=p_trx_id,
         verified_at=now(), updated_at=now() where id = pay.id;
  update bookings set status='confirmed', paid_bdt=p_verified_amount, updated_at=now()
         where id = b.id returning * into b;
  delete from booking_holds where booking_id = b.id;
  insert into audit_logs(action,entity,entity_id,details)
  values ('payment_verified','payment',pay.id::text,
          jsonb_build_object('booking',b.booking_ref,'trx',p_trx_id,'amount',p_verified_amount));
  return b;
end $$;

create or replace function process_cancellation(p_request uuid, p_approve boolean, p_refund int)
returns void language plpgsql security definer set search_path = public as $$
declare r cancellation_requests;
begin
  if not is_staff() then raise exception 'forbidden'; end if;
  select * into r from cancellation_requests where id = p_request for update;
  update cancellation_requests set status = case when p_approve then 'approved' else 'rejected' end,
         refund_bdt = case when p_approve then p_refund else 0 end, reviewed_by = auth.uid()
   where id = p_request;
  if p_approve then
    update bookings set status='cancelled', updated_at=now() where id = r.booking_id;
  end if;
  insert into audit_logs(actor_id,action,entity,entity_id)
  values (auth.uid(),'cancellation_processed','cancellation_request',p_request::text);
end $$;

-- Lock RPCs that must never be called from the browser.
revoke execute on function create_booking_hold, release_expired_holds, confirm_verified_payment from public, anon, authenticated;

-- Public-safe availability view (no customer data leaks).
create or replace function get_availability(p_date date)
returns table(slot_id smallint, state text) language sql security definer set search_path = public as $$
  select s.id,
    case when exists (select 1 from blocked_slots b where b.slot_date=p_date and (b.slot_id is null or b.slot_id=s.id)) then 'blocked'
         when exists (select 1 from bookings k where k.slot_date=p_date and k.slot_id=s.id and k.status in ('confirmed','completed')) then 'booked'
         when exists (select 1 from bookings k join booking_holds h on h.booking_id=k.id
                      where k.slot_date=p_date and k.slot_id=s.id and k.status='held' and h.expires_at>now()) then 'held'
         else 'available' end
  from booking_slots s where s.is_active order by s.id;
$$;
grant execute on function get_availability to anon, authenticated;

-- ---------- Row Level Security ----------
alter table profiles enable row level security;
alter table bookings enable row level security;
alter table booking_holds enable row level security;
alter table payments enable row level security;
alter table payment_events enable row level security;
alter table cancellation_requests enable row level security;
alter table notifications enable row level security;
alter table blocked_slots enable row level security;
alter table audit_logs enable row level security;
alter table site_settings enable row level security;
alter table booking_slots enable row level security;
alter table roles enable row level security;

create policy "own profile" on profiles for select using (id = auth.uid() or is_staff());
create policy "update own profile" on profiles for update using (id = auth.uid())
  with check (id = auth.uid() and role_id = (select role_id from profiles where id = auth.uid()));
create policy "own bookings" on bookings for select using (user_id = auth.uid() or is_staff());
create policy "own payments" on payments for select
  using (is_staff() or exists (select 1 from bookings b where b.id = booking_id and b.user_id = auth.uid()));
create policy "own cancellations" on cancellation_requests for select using (requested_by = auth.uid() or is_staff());
create policy "request cancellation" on cancellation_requests for insert
  with check (requested_by = auth.uid() and exists (select 1 from bookings b where b.id = booking_id and b.user_id = auth.uid()));
create policy "own notifications" on notifications for select using (user_id = auth.uid() or is_staff());
create policy "staff view blocks" on blocked_slots for select using (is_staff());
create policy "admin manage blocks" on blocked_slots for all using (is_admin()) with check (is_admin());
create policy "admin audit" on audit_logs for select using (is_admin());
create policy "public settings read" on site_settings for select using (true);
create policy "admin settings write" on site_settings for all using (is_admin()) with check (is_admin());
create policy "public slots read" on booking_slots for select using (true);
create policy "staff payment events" on payment_events for select using (is_staff());
-- No client INSERT/UPDATE policies on bookings, payments, holds: all writes go through server-side RPCs.
