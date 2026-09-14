-- ==============================================================================
-- Migration: 20260914000000_subscriptions_payments_and_kot.sql
-- Project: SnapServe Cafe QR-Based Ordering & Management System
-- Description:
--   1. Tiered Subscription Engine (Starter, Growth, Enterprise)
--   2. Database Triggers for Table & Menu Item Limit Enforcement
--   3. PhonePe Payment Transactions & Idempotent UTR Verification
--   4. Kitchen Order Ticket (KOT) support: notes column & full order lifecycle
-- ==============================================================================

-- 1. ADD notes AND EXPAND status CHECK CONSTRAINT ON orders TABLE
do $$
begin
  -- Add notes / special_instructions column to orders if not exists
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'orders' and column_name = 'notes'
  ) then
    alter table orders add column notes text;
  end if;
end $$;

-- Update orders status check constraint to include full lifecycle:
-- 'placed', 'pending', 'preparing', 'ready', 'served', 'completed', 'cancelled', 'paid'
do $$
begin
  -- Drop existing status check constraints on orders
  alter table orders drop constraint if exists orders_status_check;
  alter table orders add constraint orders_status_check 
    check (status in ('placed', 'pending', 'preparing', 'ready', 'served', 'completed', 'cancelled', 'paid'));
exception
  when others then null;
end $$;

-- 2. CREATE TABLE: subscriptions
create table if not exists subscriptions (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid references cafes(id) on delete cascade not null,
  cafe_id uuid references cafes(id) on delete cascade not null,
  tier text not null check (tier in ('STARTER', 'GROWTH', 'ENTERPRISE', 'TRIAL')),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'PENDING_APPROVAL', 'PENDING_VERIFICATION', 'EXPIRED', 'REJECTED', 'CANCELLED', 'TRIAL', 'ACTIVE_TRIAL')),
  start_date timestamptz default now() not null,
  end_date timestamptz default (now() + interval '30 days') not null,
  utr_number text unique,
  amount_paid numeric(10,2) not null default 0 check (amount_paid >= 0),
  created_at timestamptz default now() not null
);

create index if not exists idx_subscriptions_cafe on subscriptions (cafe_id, status);
create index if not exists idx_subscriptions_restaurant on subscriptions (restaurant_id, status);
create index if not exists idx_subscriptions_utr on subscriptions (utr_number);

-- 3. CREATE TABLE: payment_transactions
create table if not exists payment_transactions (
  id uuid primary key default gen_random_uuid(),
  cafe_id uuid references cafes(id) on delete cascade not null,
  subscription_id uuid references subscriptions(id) on delete set null,
  merchant_transaction_id text unique not null,
  utr_number text unique,
  tier text not null check (tier in ('STARTER', 'GROWTH', 'ENTERPRISE', 'TRIAL')),
  amount numeric(10,2) not null check (amount >= 0),
  status text not null default 'SUCCESS' check (status in ('SUCCESS', 'PENDING_VERIFICATION', 'PENDING_APPROVAL', 'FAILED', 'REJECTED')),
  payment_method text not null default 'PHONEPE_UPI',
  raw_details jsonb default '{}'::jsonb,
  verified_at timestamptz default now(),
  created_at timestamptz default now() not null
);

create index if not exists idx_payment_transactions_cafe on payment_transactions (cafe_id);
create index if not exists idx_payment_transactions_utr on payment_transactions (utr_number);
create index if not exists idx_payment_transactions_merchant on payment_transactions (merchant_transaction_id);

-- 4. ROW LEVEL SECURITY (RLS)
alter table subscriptions enable row level security;
alter table payment_transactions enable row level security;

-- Policies for subscriptions
drop policy if exists "Owner can view own subscriptions" on subscriptions;
create policy "Owner can view own subscriptions"
  on subscriptions for select
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

drop policy if exists "Owner can manage own subscriptions" on subscriptions;
create policy "Owner can manage own subscriptions"
  on subscriptions for all
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null))
  with check (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

-- Policies for payment_transactions
drop policy if exists "Owner can view own transactions" on payment_transactions;
create policy "Owner can view own transactions"
  on payment_transactions for select
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

drop policy if exists "Owner can insert own transactions" on payment_transactions;
create policy "Owner can insert own transactions"
  on payment_transactions for insert
  with check (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

-- 5. TRIGGER FUNCTIONS: ENFORCE TIER LIMITS
-- Tier Limits:
-- STARTER:    Max 5 Tables, Max 30 Menu Items
-- GROWTH:     Max 20 Tables, Max 70 Menu Items
-- ENTERPRISE: Unlimited Tables, Unlimited Menu Items

-- 5.1 Helper function: get current active tier for cafe
create or replace function get_active_subscription_tier(p_cafe_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier text;
begin
  -- Find active subscription that has not expired
  select tier into v_tier
  from subscriptions
  where cafe_id = p_cafe_id
    and status = 'ACTIVE'
    and end_date > now()
  order by end_date desc
  limit 1;

  -- Default to 'STARTER' if no subscription active yet
  return coalesce(v_tier, 'STARTER');
end;
$$;

grant execute on function get_active_subscription_tier(uuid) to anon, authenticated;

-- 5.2 Trigger function: Enforce table limits before INSERT on tables
create or replace function fn_enforce_table_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier text;
  v_current_count int;
  v_max_tables int;
begin
  v_tier := get_active_subscription_tier(new.cafe_id);

  if v_tier = 'ENTERPRISE' then
    return new; -- Unlimited
  elsif v_tier = 'GROWTH' then
    v_max_tables := 20;
  else
    v_max_tables := 5; -- STARTER default
  end if;

  select count(*) into v_current_count
  from tables
  where cafe_id = new.cafe_id;

  if v_current_count >= v_max_tables then
    raise exception 'LIMIT_EXCEEDED: Table limit of % reached for your % plan. Please upgrade your plan to add more tables.',
      v_max_tables, v_tier
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_table_limit on tables;
create trigger trg_enforce_table_limit
  before insert on tables
  for each row
  execute function fn_enforce_table_limit();

-- 5.3 Trigger function: Enforce menu items limits before INSERT on menu_items
create or replace function fn_enforce_menu_item_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier text;
  v_current_count int;
  v_max_items int;
begin
  v_tier := get_active_subscription_tier(new.cafe_id);

  if v_tier = 'ENTERPRISE' then
    return new; -- Unlimited
  elsif v_tier = 'GROWTH' then
    v_max_items := 70;
  else
    v_max_items := 30; -- STARTER default
  end if;

  select count(*) into v_current_count
  from menu_items
  where cafe_id = new.cafe_id
    and is_deleted = false;

  if v_current_count >= v_max_items then
    raise exception 'LIMIT_EXCEEDED: Menu item limit of % reached for your % plan. Please upgrade your plan to add more menu items.',
      v_max_items, v_tier
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_menu_item_limit on menu_items;
create trigger trg_enforce_menu_item_limit
  before insert on menu_items
  for each row
  execute function fn_enforce_menu_item_limit();

-- 6. RPC: get_cafe_subscription_overview
-- Returns current plan, status, renewal date, and quota usage (tables and menu items)
create or replace function get_cafe_subscription_overview(p_cafe_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub record;
  v_tier text;
  v_status text;
  v_end_date timestamptz;
  v_tables_count int;
  v_max_tables int;
  v_items_count int;
  v_max_items int;
  v_days_left int := 30;
begin
  -- Lookup latest subscription
  select * into v_sub
  from subscriptions
  where cafe_id = p_cafe_id
  order by created_at desc
  limit 1;

  if v_sub.id is not null and v_sub.end_date > now() then
    v_tier := v_sub.tier;
    v_status := v_sub.status;
    v_end_date := v_sub.end_date;
    v_days_left := greatest(0, ceil(extract(epoch from (v_end_date - now())) / 86400)::int);
  else
    v_tier := 'STARTER';
    v_status := 'ACTIVE';
    v_end_date := now() + interval '30 days';
    v_days_left := 30;
  end if;

  if v_tier = 'ENTERPRISE' then
    v_max_tables := -1; -- Unlimited
    v_max_items := -1;  -- Unlimited
  elsif v_tier = 'GROWTH' then
    v_max_tables := 20;
    v_max_items := 70;
  else
    v_max_tables := 5;
    v_max_items := 30;
  end if;

  select count(*) into v_tables_count from tables where cafe_id = p_cafe_id;
  select count(*) into v_items_count from menu_items where cafe_id = p_cafe_id and is_deleted = false;

  return jsonb_build_object(
    'tier', v_tier,
    'status', v_status,
    'start_date', coalesce(v_sub.start_date, now()),
    'end_date', v_end_date,
    'days_remaining', v_days_left,
    'tables_used', v_tables_count,
    'max_tables', v_max_tables,
    'items_used', v_items_count,
    'max_items', v_max_items,
    'utr_number', v_sub.utr_number,
    'amount_paid', coalesce(v_sub.amount_paid, 0)
  );
end;
$$;

grant execute on function get_cafe_subscription_overview(uuid) to anon, authenticated;

-- 7. RPC: submit_subscription_payment
-- Atomic idempotent verification & subscription activation
create or replace function submit_subscription_payment(
  p_cafe_id uuid,
  p_tier text,
  p_utr_number text,
  p_amount numeric,
  p_merchant_txn_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clean_utr text;
  v_expected_amount numeric(10,2);
  v_new_sub_id uuid;
  v_txn_id text;
  v_existing_sub record;
begin
  -- Clean UTR input
  v_clean_utr := trim(p_utr_number);

  if length(v_clean_utr) < 10 or length(v_clean_utr) > 20 then
    return jsonb_build_object(
      'success', false,
      'error', 'INVALID_UTR: Please enter a valid 12-digit Bank Transaction / UTR Number.'
    );
  end if;

  -- Validate tier and pricing
  if p_tier = 'STARTER' then
    v_expected_amount := 399.00;
  elsif p_tier = 'GROWTH' then
    v_expected_amount := 799.00;
  elsif p_tier = 'ENTERPRISE' then
    v_expected_amount := 1499.00;
  else
    return jsonb_build_object('success', false, 'error', 'INVALID_TIER: Unknown subscription tier.');
  end if;

  if p_amount != v_expected_amount then
    return jsonb_build_object(
      'success', false,
      'error', format('AMOUNT_MISMATCH: Amount paid (₹%s) does not match the %s tier price (₹%s).', p_amount, p_tier, v_expected_amount)
    );
  end if;

  -- IDEMPOTENCY CHECK: Prevent duplicate submission of the same UTR across ALL cafes
  select * into v_existing_sub
  from subscriptions
  where utr_number = v_clean_utr;

  if v_existing_sub.id is not null then
    return jsonb_build_object(
      'success', false,
      'error', 'DUPLICATE_UTR: This Bank UTR Number has already been submitted or verified for an account.'
    );
  end if;

  -- Generate transaction id if not supplied
  v_txn_id := coalesce(p_merchant_txn_id, 'TXN_' || substring(gen_random_uuid()::text, 1, 12));

  -- Insert active subscription for 30 days
  insert into subscriptions (
    restaurant_id,
    cafe_id,
    tier,
    status,
    start_date,
    end_date,
    utr_number,
    amount_paid
  ) values (
    p_cafe_id,
    p_cafe_id,
    p_tier,
    'ACTIVE',
    now(),
    now() + interval '30 days',
    v_clean_utr,
    p_amount
  ) returning id into v_new_sub_id;

  -- Insert audit transaction
  insert into payment_transactions (
    cafe_id,
    subscription_id,
    merchant_transaction_id,
    utr_number,
    tier,
    amount,
    status,
    payment_method,
    raw_details,
    verified_at
  ) values (
    p_cafe_id,
    v_new_sub_id,
    v_txn_id,
    v_clean_utr,
    p_tier,
    p_amount,
    'SUCCESS',
    'PHONEPE_UPI',
    jsonb_build_object('verified_automatically', true, 'utr', v_clean_utr, 'amount', p_amount),
    now()
  );

  return jsonb_build_object(
    'success', true,
    'subscription_id', v_new_sub_id,
    'tier', p_tier,
    'status', 'ACTIVE',
    'validity_days', 30,
    'message', format('Payment verified! Your %s plan has been activated for 30 days.', p_tier)
  );
end;
$$;

grant execute on function submit_subscription_payment(uuid, text, text, numeric, text) to authenticated;

-- 8. UPDATE place_order TO RECORD SPECIAL INSTRUCTIONS / NOTES
drop function if exists place_order(uuid, jsonb);
drop function if exists place_order(uuid, jsonb, text);
create or replace function place_order(
  p_session_token uuid,
  p_items jsonb,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session record;
  v_order_id uuid;
  v_item jsonb;
  v_menu_item record;
  v_total numeric(10,2) := 0;
  v_line_total numeric(10,2);
  v_price numeric(10,2);
  v_quantity int;
begin
  -- 1. Validate session token and check expiration / table closure
  select s.id as session_id, s.table_id, s.cafe_id, s.status, s.expires_at, t.table_number
    into v_session
    from table_sessions s
    join tables t on t.id = s.table_id
   where s.session_token = p_session_token;

  if v_session.session_id is null then
    raise exception 'Session expired or table closed. Please scan the QR again.';
  end if;

  if v_session.status != 'active' or v_session.expires_at <= now() then
    update table_sessions set status = 'closed', closed_at = coalesce(closed_at, now()) where id = v_session.session_id;
    raise exception 'Session expired or table closed. Please scan the QR again.';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order cart cannot be empty';
  end if;

  -- 2. Create the order tagged with session_id and notes
  insert into orders (cafe_id, table_id, session_id, status, total_amount, notes)
  values (v_session.cafe_id, v_session.table_id, v_session.session_id, 'pending', 0, p_notes)
  returning id into v_order_id;

  -- 3. Calculate server-side prices and verify stock availability & deletion status
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := (v_item->>'quantity')::int;
    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Item quantity must be greater than zero';
    end if;

    select id, price, offer_price, is_available, is_deleted, cafe_id, name
      into v_menu_item
      from menu_items
      where id = (v_item->>'menu_item_id')::uuid;

    if v_menu_item.id is null or v_menu_item.cafe_id != v_session.cafe_id or v_menu_item.is_deleted = true then
      raise exception 'Menu item is not available: %', (v_item->>'menu_item_id');
    end if;

    if v_menu_item.is_available = false then
      raise exception 'Item "%" is currently out of stock', v_menu_item.name;
    end if;

    v_price := coalesce(v_menu_item.offer_price, v_menu_item.price);
    v_line_total := v_price * v_quantity;
    v_total := v_total + v_line_total;

    insert into order_items (order_id, menu_item_id, quantity, price_at_order_time)
    values (v_order_id, v_menu_item.id, v_quantity, v_price);
  end loop;

  -- 4. Update the verified total on the order
  update orders set total_amount = v_total where id = v_order_id;

  return v_order_id;
end;
$$;

grant execute on function place_order(uuid, jsonb, text) to anon, authenticated;

-- 9. REALTIME PUBLICATION
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'subscriptions'
  ) then
    alter publication supabase_realtime add table subscriptions;
  end if;
exception
  when others then null;
end $$;

-- 10. SUPER ADMIN CONSOLE ARCHITECTURE & SECURITY
create table if not exists app_admins (
  email text primary key,
  role text not null default 'admin',
  created_at timestamptz default now()
);

-- Seed root super admin
insert into app_admins (email, role)
values ('ershobhit17@gmail.com', 'super_admin')
on conflict (email) do update set role = 'super_admin';

create or replace function is_super_admin()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  v_email := coalesce(auth.jwt() ->> 'email', '');
  return exists (
    select 1 from app_admins 
    where lower(email) = lower(v_email)
  );
end;
$$;

create or replace function admin_get_platform_metrics()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_cafes int;
  v_pending_approvals int;
  v_total_orders int;
  v_total_revenue numeric;
begin
  if not is_super_admin() then
    return jsonb_build_object('success', false, 'error', 'ACCESS_DENIED: Super Admin privileges required.');
  end if;

  select count(*) into v_total_cafes from cafes;
  select count(*) into v_pending_approvals from subscriptions where status = 'PENDING_APPROVAL';
  select count(*), coalesce(sum(case when status = 'paid' then total_amount else 0 end), 0)
    into v_total_orders, v_total_revenue
  from orders;

  return jsonb_build_object(
    'total_cafes', v_total_cafes,
    'pending_approvals', v_pending_approvals,
    'total_orders', v_total_orders,
    'total_revenue', v_total_revenue
  );
end;
$$;

create or replace function admin_get_all_cafes_overview()
returns table(
  cafe_id uuid,
  cafe_name text,
  owner_id uuid,
  owner_email text,
  is_suspended boolean,
  suspended_reason text,
  created_at timestamptz,
  tier text,
  status text,
  is_trial boolean,
  days_remaining int,
  end_date timestamptz,
  tables_count int,
  max_tables int,
  items_count int,
  max_items int,
  orders_count int,
  total_revenue numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'ACCESS_DENIED: Only platform super admins can access this data.'
      using errcode = '42501';
  end if;

  return query
  select 
    c.id as cafe_id,
    c.name::text as cafe_name,
    c.owner_id,
    coalesce(u.email::text, 'No Email Linked')::text as owner_email,
    coalesce(c.is_suspended, false) as is_suspended,
    c.suspended_reason::text,
    c.created_at,
    coalesce((sub_overview->>'tier')::text, 'TRIAL')::text as tier,
    coalesce((sub_overview->>'status')::text, 'ACTIVE_TRIAL')::text as status,
    coalesce((sub_overview->>'is_trial')::boolean, true) as is_trial,
    coalesce((sub_overview->>'days_remaining')::int, 0) as days_remaining,
    (sub_overview->>'end_date')::timestamptz as end_date,
    coalesce((sub_overview->>'tables_used')::int, 0) as tables_count,
    coalesce((sub_overview->>'max_tables')::int, 5) as max_tables,
    coalesce((sub_overview->>'items_used')::int, 0) as items_count,
    coalesce((sub_overview->>'max_items')::int, 30) as max_items,
    coalesce(ord_stats.orders_count, 0)::int as orders_count,
    coalesce(ord_stats.total_rev, 0)::numeric as total_revenue
  from cafes c
  left join auth.users u on u.id = c.owner_id
  cross join lateral (
    select get_cafe_subscription_overview(c.id) as sub_overview
  ) lateral_sub
  left join lateral (
    select 
      count(*) as orders_count,
      coalesce(sum(case when o.status = 'paid' then o.total_amount else 0 end), 0) as total_rev
    from orders o
    where o.cafe_id = c.id
  ) ord_stats on true
  order by c.created_at desc;
end;
$$;

create or replace function admin_grant_subscription(
  p_cafe_id uuid,
  p_tier text,
  p_days integer default 30,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_sub_id uuid;
  v_clean_tier text;
begin
  if not is_super_admin() then
    return jsonb_build_object('success', false, 'error', 'ACCESS_DENIED');
  end if;

  v_clean_tier := upper(trim(p_tier));
  if v_clean_tier not in ('STARTER', 'GROWTH', 'ENTERPRISE', 'TRIAL') then
    return jsonb_build_object('success', false, 'error', 'INVALID_TIER');
  end if;

  insert into subscriptions (
    restaurant_id,
    cafe_id,
    tier,
    status,
    start_date,
    end_date,
    utr_number,
    amount_paid
  ) values (
    p_cafe_id,
    p_cafe_id,
    v_clean_tier,
    'ACTIVE',
    now(),
    now() + (p_days || ' days')::interval,
    coalesce(p_notes, 'ADMIN_MANUAL_GRANT'),
    case 
      when v_clean_tier = 'STARTER' then 399.00
      when v_clean_tier = 'GROWTH' then 799.00
      when v_clean_tier = 'ENTERPRISE' then 1499.00
      else 0.00
    end
  ) returning id into v_new_sub_id;

  return jsonb_build_object(
    'success', true,
    'subscription_id', v_new_sub_id,
    'tier', v_clean_tier,
    'days_granted', p_days,
    'message', format('Successfully granted %s tier for %s days.', v_clean_tier, p_days)
  );
end;
$$;

create or replace function admin_update_cafe_access(
  p_cafe_id uuid,
  p_is_suspended boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    return jsonb_build_object('success', false, 'error', 'ACCESS_DENIED');
  end if;

  update cafes 
  set is_suspended = p_is_suspended,
      suspended_reason = p_reason
  where id = p_cafe_id;

  return jsonb_build_object(
    'success', true, 
    'is_suspended', p_is_suspended,
    'message', case when p_is_suspended then 'Cafe access suspended.' else 'Cafe access restored.' end
  );
end;
$$;

create or replace function admin_list_admins()
returns table(email text, role text, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'ACCESS_DENIED: Only platform super admins can view admin list.';
  end if;

  return query
  select a.email, a.role, a.created_at
  from app_admins a
  order by a.created_at asc;
end;
$$;

create or replace function admin_add_admin(p_email text, p_role text default 'admin')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clean_email text;
begin
  if not is_super_admin() then
    return jsonb_build_object('success', false, 'error', 'ACCESS_DENIED: Only platform super admins can add admins.');
  end if;

  v_clean_email := lower(trim(p_email));
  if v_clean_email = '' or v_clean_email not like '%@%.%' then
    return jsonb_build_object('success', false, 'error', 'INVALID_EMAIL: Please enter a valid email address.');
  end if;

  insert into app_admins (email, role)
  values (v_clean_email, coalesce(p_role, 'admin'))
  on conflict (email) do update set role = excluded.role;

  return jsonb_build_object('success', true, 'message', format('Admin %s has been granted %s access.', v_clean_email, p_role));
end;
$$;

create or replace function admin_remove_admin(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clean_email text;
begin
  if not is_super_admin() then
    return jsonb_build_object('success', false, 'error', 'ACCESS_DENIED: Only platform super admins can revoke admin access.');
  end if;

  v_clean_email := lower(trim(p_email));
  if v_clean_email = 'ershobhit17@gmail.com' then
    return jsonb_build_object('success', false, 'error', 'PROTECTED: Cannot remove root super admin.');
  end if;

  delete from app_admins where lower(email) = v_clean_email;

  return jsonb_build_object('success', true, 'message', format('Admin access revoked for %s.', v_clean_email));
end;
$$;

grant execute on function is_super_admin() to authenticated, anon;
grant execute on function admin_get_platform_metrics() to authenticated;
grant execute on function admin_get_all_cafes_overview() to authenticated;
grant execute on function admin_grant_subscription(uuid, text, integer, text) to authenticated;
grant execute on function admin_update_cafe_access(uuid, boolean, text) to authenticated;
grant execute on function admin_list_admins() to authenticated;
grant execute on function admin_add_admin(text, text) to authenticated;
grant execute on function admin_remove_admin(text) to authenticated;

