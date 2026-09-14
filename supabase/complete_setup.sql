-- ==============================================================================
-- Migration: 20260909000000_initial_schema.sql
-- Project: Cafe QR-Based Ordering & Management System
-- ==============================================================================

-- 1. EXTENSIONS
create extension if not exists "pgcrypto";

-- 2. TABLES
create table if not exists cafes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid references auth.users(id),
  created_at timestamptz default now()
);

create table if not exists tables (
  id uuid primary key default gen_random_uuid(),
  cafe_id uuid references cafes(id) on delete cascade not null,
  table_number int not null,
  qr_token uuid unique default gen_random_uuid(),
  created_at timestamptz default now()
);

create table if not exists menu_items (
  id uuid primary key default gen_random_uuid(),
  cafe_id uuid references cafes(id) on delete cascade not null,
  name text not null,
  description text,
  category text not null default 'General',
  price numeric(10,2) not null check (price >= 0),
  offer_price numeric(10,2) check (offer_price is null or (offer_price >= 0 and offer_price < price)),
  image_url text,
  is_available boolean default true,
  created_at timestamptz default now()
);

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  cafe_id uuid references cafes(id) on delete cascade not null,
  table_id uuid references tables(id) on delete restrict not null,
  status text default 'pending' check (status in ('pending','preparing','served','paid')),
  total_amount numeric(10,2) not null default 0,
  created_at timestamptz default now()
);

create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade not null,
  menu_item_id uuid references menu_items(id) on delete restrict not null,
  quantity int not null check (quantity > 0),
  price_at_order_time numeric(10,2) not null check (price_at_order_time >= 0)
);

-- 3. INDEXES FOR PERFORMANCE
create index if not exists idx_tables_qr_token on tables (qr_token);
create index if not exists idx_tables_cafe_id on tables (cafe_id);
create index if not exists idx_menu_items_cafe_id on menu_items (cafe_id);
create index if not exists idx_orders_cafe_created on orders (cafe_id, created_at desc);
create index if not exists idx_orders_cafe_status on orders (cafe_id, status);
create index if not exists idx_order_items_order_id on order_items (order_id);

-- 4. ROW LEVEL SECURITY (RLS)
alter table cafes enable row level security;
alter table tables enable row level security;
alter table menu_items enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;

-- 4.1 POLICIES: CAFES
drop policy if exists "Owner can view own cafe" on cafes;
create policy "Owner can view own cafe"
  on cafes for select
  using (auth.uid() = owner_id or owner_id is null);

drop policy if exists "Owner can insert own cafe" on cafes;
create policy "Owner can insert own cafe"
  on cafes for insert
  with check (auth.uid() = owner_id or owner_id is null);

drop policy if exists "Owner can update own cafe" on cafes;
create policy "Owner can update own cafe"
  on cafes for update
  using (auth.uid() = owner_id or owner_id is null);

-- 4.2 POLICIES: TABLES
drop policy if exists "Public can view tables (needed to resolve QR)" on tables;
create policy "Public can view tables (needed to resolve QR)"
  on tables for select
  using (true);

drop policy if exists "Owner can manage own tables" on tables;
create policy "Owner can manage own tables"
  on tables for all
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null))
  with check (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

-- 4.3 POLICIES: MENU_ITEMS
drop policy if exists "Public can view menu" on menu_items;
create policy "Public can view menu"
  on menu_items for select
  using (true);

drop policy if exists "Owner can manage own menu" on menu_items;
create policy "Owner can manage own menu"
  on menu_items for all
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null))
  with check (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

-- 4.4 POLICIES: ORDERS
-- Note: Anonymous users cannot directly INSERT or UPDATE orders table.
-- Order creation MUST go through the place_order RPC (security definer).
drop policy if exists "Owner can view own cafe orders" on orders;
create policy "Owner can view own cafe orders"
  on orders for select
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

drop policy if exists "Owner can update own cafe orders" on orders;
create policy "Owner can update own cafe orders"
  on orders for update
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

-- 4.5 POLICIES: ORDER_ITEMS
drop policy if exists "Owner can view own order items" on order_items;
create policy "Owner can view own order items"
  on order_items for select
  using (
    order_id in (
      select o.id from orders o
      join cafes c on c.id = o.cafe_id
      where c.owner_id = auth.uid() or c.owner_id is null
    )
  );

-- 5. RPC: place_order (TAMPER-PROOF ORDER CREATION)
-- Calculates true prices inside database transaction from menu_items.
create or replace function place_order(
  p_qr_token uuid,
  p_items jsonb  -- e.g. '[{"menu_item_id": "uuid", "quantity": 2}, ...]'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_table record;
  v_order_id uuid;
  v_item jsonb;
  v_menu_item record;
  v_total numeric(10,2) := 0;
  v_line_total numeric(10,2);
  v_price numeric(10,2);
  v_quantity int;
begin
  -- 1. Validate table by QR token
  select id, cafe_id, table_number into v_table
  from tables
  where qr_token = p_qr_token;

  if v_table.id is null then
    raise exception 'Invalid table or QR token';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order cart cannot be empty';
  end if;

  -- 2. Create the initial order shell
  insert into orders (cafe_id, table_id, status, total_amount)
  values (v_table.cafe_id, v_table.id, 'pending', 0)
  returning id into v_order_id;

  -- 3. Iterate through requested items and price them server-side
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := (v_item->>'quantity')::int;
    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Item quantity must be greater than zero';
    end if;

    select id, price, offer_price, is_available, cafe_id, name
      into v_menu_item
      from menu_items
      where id = (v_item->>'menu_item_id')::uuid;

    if v_menu_item.id is null or v_menu_item.cafe_id != v_table.cafe_id then
      raise exception 'Invalid menu item in order: %', (v_item->>'menu_item_id');
    end if;

    if v_menu_item.is_available = false then
      raise exception 'Item "%" is currently out of stock', v_menu_item.name;
    end if;

    -- Apply offer_price if active, else standard price
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

-- Grant execution to anonymous and authenticated users
grant execute on function place_order(uuid, jsonb) to anon, authenticated;

-- 6. RPC: get_order_status
-- Lets customer verify/poll their own order without exposing general orders table
create or replace function get_order_status(p_order_id uuid)
returns table (
  status text,
  total_amount numeric,
  created_at timestamptz,
  table_number int
)
language sql
security definer
set search_path = public
as $$
  select o.status, o.total_amount, o.created_at, t.table_number
  from orders o
  join tables t on t.id = o.table_id
  where o.id = p_order_id;
$$;

grant execute on function get_order_status(uuid) to anon, authenticated;

-- 7. REALTIME PUBLICATION SETUP
-- Add orders table to supabase_realtime publication
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table orders;
  end if;
exception
  when others then null;
end $$;
-- ==============================================================================
-- Migration: 20260912000000_table_sessions_and_features.sql
-- Project: SnapServe Cafe QR-Based Ordering & Management System
-- Description:
--   1. Anti-fraud Table Sessions (UUID token, 2hr validity, turnover invalidation)
--   2. Safe Menu Item Deletion / Archiving (is_deleted column, safe delete RPC)
--   3. End-of-Day Settlement RPC (close_day_and_collect for eligible served orders)
--   4. Session-Scoped Customer Orders RPC (get_session_orders)
--   5. Itemized Order Status RPC (get_order_status)
--   6. Security Defininer place_order with Strict Session Validation
-- ==============================================================================

-- 1. ADD is_deleted COLUMN TO menu_items IF NOT EXISTS
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'menu_items' and column_name = 'is_deleted'
  ) then
    alter table menu_items add column is_deleted boolean default false not null;
  end if;
end $$;

-- 2. CREATE TABLE: table_sessions
create table if not exists table_sessions (
  id uuid primary key default gen_random_uuid(),
  table_id uuid references tables(id) on delete cascade not null,
  cafe_id uuid references cafes(id) on delete cascade not null,
  session_token uuid default gen_random_uuid() not null unique,
  status text default 'active' check (status in ('active', 'closed')),
  created_at timestamptz default now() not null,
  expires_at timestamptz default (now() + interval '2 hours') not null,
  closed_at timestamptz
);

-- Indexes for table_sessions
create index if not exists idx_table_sessions_table on table_sessions (table_id, status);
create index if not exists idx_table_sessions_token on table_sessions (session_token);
create index if not exists idx_table_sessions_cafe on table_sessions (cafe_id);

-- 3. ADD session_id COLUMN TO orders IF NOT EXISTS
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'orders' and column_name = 'session_id'
  ) then
    alter table orders add column session_id uuid references table_sessions(id) on delete set null;
  end if;
end $$;

create index if not exists idx_orders_session_id on orders (session_id);

-- 4. ROW LEVEL SECURITY (RLS) FOR table_sessions
alter table table_sessions enable row level security;

-- Public/anon can resolve active session token for their table
drop policy if exists "Public can view own session token" on table_sessions;
create policy "Public can view own session token"
  on table_sessions for select
  using (true);

-- Owner can view and manage sessions for their cafe
drop policy if exists "Owner can manage cafe table sessions" on table_sessions;
create policy "Owner can manage cafe table sessions"
  on table_sessions for all
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null))
  with check (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

-- 5. UPDATE menu_items RLS POLICY TO EXCLUDE DELETED ITEMS FROM PUBLIC VIEW
drop policy if exists "Public can view menu" on menu_items;
create policy "Public can view menu"
  on menu_items for select
  using (is_deleted = false);

drop policy if exists "Owner can manage own menu" on menu_items;
create policy "Owner can manage own menu"
  on menu_items for all
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null))
  with check (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

-- 6. RPC: get_or_create_table_session
-- Purpose:
--   When customer scans table QR, verifies table QR token.
--   If customer supplies an existing session_token that is active and not expired, returns it.
--   If brand new customer, expired session, or forced new session:
--     Gracefully closes any previously active session for that table (turnover invalidation).
--     Creates a new active session valid for 2 hours.
create or replace function get_or_create_table_session(
  p_qr_token uuid,
  p_session_token uuid default null,
  p_force_new boolean default false
)
returns table (
  session_token uuid,
  session_id uuid,
  table_id uuid,
  table_number int,
  cafe_id uuid,
  cafe_name text,
  status text,
  expires_at timestamptz,
  is_active boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_table record;
  v_session record;
  v_new_session_id uuid;
  v_new_token uuid;
begin
  -- Validate table & cafe
  select t.id as table_id, t.table_number, t.cafe_id, c.name as cafe_name
    into v_table
    from tables t
    join cafes c on c.id = t.cafe_id
   where t.qr_token = p_qr_token;

  if v_table.table_id is null then
    raise exception 'Invalid table or QR code';
  end if;

  -- If customer provided an existing session token and not forcing new session, verify it
  if p_session_token is not null and p_force_new is false then
    select s.id, s.session_token, s.status, s.expires_at
      into v_session
      from table_sessions s
     where s.session_token = p_session_token
       and s.table_id = v_table.table_id;

    if v_session.id is not null then
      if v_session.status = 'active' and v_session.expires_at > now() then
        return query select
          v_session.session_token,
          v_session.id as session_id,
          v_table.table_id,
          v_table.table_number,
          v_table.cafe_id,
          v_table.cafe_name,
          v_session.status,
          v_session.expires_at,
          true as is_active;
        return;
      else
        -- Session exists but is expired or closed -> return it as read-only / inactive
        return query select
          v_session.session_token,
          v_session.id as session_id,
          v_table.table_id,
          v_table.table_number,
          v_table.cafe_id,
          v_table.cafe_name,
          v_session.status,
          v_session.expires_at,
          false as is_active;
        return;
      end if;
    end if;
  end if;

  -- TABLE TURNOVER / NEW CUSTOMER ARRIVAL:
  -- Invalidate and close previous active sessions for this table
  update table_sessions
     set status = 'closed',
         closed_at = now()
   where table_id = v_table.table_id
     and status = 'active';

  -- Generate new active session with 2-hour validity
  v_new_token := gen_random_uuid();
  insert into table_sessions (table_id, cafe_id, session_token, status, expires_at)
  values (v_table.table_id, v_table.cafe_id, v_new_token, 'active', now() + interval '2 hours')
  returning id into v_new_session_id;

  return query select
    v_new_token as session_token,
    v_new_session_id as session_id,
    v_table.table_id,
    v_table.table_number,
    v_table.cafe_id,
    v_table.cafe_name,
    'active'::text as status,
    (now() + interval '2 hours')::timestamptz as expires_at,
    true as is_active;
end;
$$;

grant execute on function get_or_create_table_session(uuid, uuid, boolean) to anon, authenticated;

-- 7. ENHANCED RPC: place_order (WITH STRICT SESSION VALIDATION & ANTI-FRAUD LOCK)
drop function if exists place_order(uuid, jsonb);
create or replace function place_order(
  p_session_token uuid,
  p_items jsonb
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
    -- Mark as closed if expired
    update table_sessions set status = 'closed', closed_at = coalesce(closed_at, now()) where id = v_session.session_id;
    raise exception 'Session expired or table closed. Please scan the QR again.';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order cart cannot be empty';
  end if;

  -- 2. Create the order tagged with session_id
  insert into orders (cafe_id, table_id, session_id, status, total_amount)
  values (v_session.cafe_id, v_session.table_id, v_session.session_id, 'pending', 0)
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

grant execute on function place_order(uuid, jsonb) to anon, authenticated;

-- 8. RPC: get_session_orders
-- Purpose:
--   Allows customer to securely retrieve all orders and items created during their session
--   WITHOUT opening the orders table to broad public SELECT.
create or replace function get_session_orders(p_session_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session record;
  v_result jsonb;
begin
  select id, cafe_id into v_session
    from table_sessions
   where session_token = p_session_token;

  if v_session.id is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(ord_json order by ord_json->>'created_at' desc), '[]'::jsonb)
    into v_result
    from (
      select jsonb_build_object(
        'id', o.id,
        'short_id', substring(o.id::text, 1, 8),
        'status', o.status,
        'total_amount', o.total_amount,
        'created_at', o.created_at,
        'items', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'id', oi.id,
            'name', coalesce(mi.name, 'Archived Item'),
            'quantity', oi.quantity,
            'price', oi.price_at_order_time,
            'line_total', (oi.quantity * oi.price_at_order_time)
          )), '[]'::jsonb)
          from order_items oi
          left join menu_items mi on mi.id = oi.menu_item_id
          where oi.order_id = o.id
        )
      ) as ord_json
      from orders o
      where o.session_id = v_session.id
    ) sub;

  return v_result;
end;
$$;

grant execute on function get_session_orders(uuid) to anon, authenticated;

-- 9. RPC: get_order_status (ENHANCED WITH ITEMIZED DETAILS)
drop function if exists get_order_status(uuid);

create or replace function get_order_status(p_order_id uuid)
returns table (
  status text,
  total_amount numeric,
  created_at timestamptz,
  table_number int,
  items jsonb
)
language sql
security definer
set search_path = public
as $$
  select
    o.status,
    o.total_amount,
    o.created_at,
    t.table_number,
    (
      select coalesce(jsonb_agg(jsonb_build_object(
        'name', coalesce(mi.name, 'Menu Item'),
        'quantity', oi.quantity,
        'price', oi.price_at_order_time,
        'line_total', (oi.quantity * oi.price_at_order_time)
      )), '[]'::jsonb)
      from order_items oi
      left join menu_items mi on mi.id = oi.menu_item_id
      where oi.order_id = o.id
    ) as items
  from orders o
  join tables t on t.id = o.table_id
  where o.id = p_order_id;
$$;

grant execute on function get_order_status(uuid) to anon, authenticated;

-- 10. RPC: delete_or_archive_menu_item
-- Purpose:
--   Safe deletion of a menu item.
--   If referenced in historical order_items, safely archives (is_deleted = true, is_available = false).
--   If never referenced in any order, performs clean hard delete.
create or replace function delete_or_archive_menu_item(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_cafe record;
  v_is_referenced boolean := false;
begin
  -- Check item existence
  select id, cafe_id, name into v_item
    from menu_items
   where id = p_item_id;

  if v_item.id is null then
    return jsonb_build_object('success', false, 'error', 'Menu item not found');
  end if;

  -- Check owner authorization
  select id into v_cafe
    from cafes
   where id = v_item.cafe_id
     and (owner_id = auth.uid() or (owner_id is null and auth.role() = 'authenticated'));

  if v_cafe.id is null then
    return jsonb_build_object('success', false, 'error', 'Unauthorized to modify this menu');
  end if;

  -- Check if referenced in historical order_items
  select exists(
    select 1 from order_items where menu_item_id = p_item_id
  ) into v_is_referenced;

  if v_is_referenced then
    -- Safe soft delete / archive
    update menu_items
       set is_deleted = true,
           is_available = false
     where id = p_item_id;

    return jsonb_build_object('success', true, 'action', 'archived', 'message', 'Menu item archived successfully');
  else
    -- Safe hard delete
    delete from menu_items where id = p_item_id;
    return jsonb_build_object('success', true, 'action', 'deleted', 'message', 'Menu item deleted successfully');
  end if;
end;
$$;

grant execute on function delete_or_archive_menu_item(uuid) to authenticated;

-- 11. RPC: close_day_and_collect
-- Purpose:
--   End-of-day settlement.
--   Finds all served/completed orders that are not yet marked paid for this cafe.
--   Updates them to 'paid'.
--   Safe against double collection (already-paid orders are ignored).
--   Closes all active table sessions for the cafe.
create or replace function close_day_and_collect(p_cafe_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cafe record;
  v_collected_amount numeric(10,2) := 0;
  v_order_count int := 0;
begin
  -- Validate owner authorization
  select id, name into v_cafe
    from cafes
   where id = p_cafe_id
     and (owner_id = auth.uid() or (owner_id is null and auth.role() = 'authenticated'));

  if v_cafe.id is null then
    return jsonb_build_object('success', false, 'error', 'Unauthorized cafe access');
  end if;

  -- Calculate eligible collection (only orders with status = 'served')
  select coalesce(sum(total_amount), 0), count(*)
    into v_collected_amount, v_order_count
    from orders
   where cafe_id = p_cafe_id
     and status = 'served';

  if v_order_count > 0 then
    -- Mark eligible served orders as paid
    update orders
       set status = 'paid'
     where cafe_id = p_cafe_id
       and status = 'served';

    -- Close active table sessions
    update table_sessions
       set status = 'closed',
           closed_at = now()
     where cafe_id = p_cafe_id
       and status = 'active';
  end if;

  return jsonb_build_object(
    'success', true,
    'orders_count', v_order_count,
    'collected_amount', v_collected_amount
  );
end;
$$;

grant execute on function close_day_and_collect(uuid) to authenticated;

-- 12. SUPABASE REALTIME SETUP
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'table_sessions'
  ) then
    alter publication supabase_realtime add table table_sessions;
  end if;
exception
  when others then null;
end $$;
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
  tier text not null check (tier in ('STARTER', 'GROWTH', 'ENTERPRISE')),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'PENDING_VERIFICATION', 'EXPIRED')),
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
  tier text not null check (tier in ('STARTER', 'GROWTH', 'ENTERPRISE')),
  amount numeric(10,2) not null check (amount >= 0),
  status text not null default 'SUCCESS' check (status in ('SUCCESS', 'PENDING_VERIFICATION', 'FAILED')),
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
  v_sub record;
  v_cafe record;
begin
  -- Check paid subscription strictly in ACTIVE status
  select tier into v_sub
  from subscriptions
  where cafe_id = p_cafe_id
    and status = 'ACTIVE'
    and end_date > now()
  order by end_date desc
  limit 1;

  if v_sub.tier is not null then
    return v_sub.tier;
  end if;

  -- Check 7-day trial from cafe created_at
  select created_at into v_cafe
  from cafes
  where id = p_cafe_id;

  if v_cafe.created_at is not null and now() <= (v_cafe.created_at + interval '7 days') then
    return 'TRIAL';
  end if;

  return 'EXPIRED';
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
  v_cafe record;
  v_active_sub record;
  v_pending_sub record;
  v_tier text;
  v_status text;
  v_start_date timestamptz;
  v_end_date timestamptz;
  v_tables_count int;
  v_max_tables int;
  v_items_count int;
  v_max_items int;
  v_days_left int := 0;
  v_is_trial boolean := false;
  v_trial_end timestamptz;
begin
  select id, name, created_at into v_cafe
  from cafes
  where id = p_cafe_id;

  if v_cafe.id is null then
    return jsonb_build_object('error', 'Cafe not found');
  end if;

  -- 1. Check if there is an active paid subscription
  select * into v_active_sub
  from subscriptions
  where cafe_id = p_cafe_id
    and status = 'ACTIVE'
    and end_date > now()
  order by end_date desc
  limit 1;

  -- 2. Check if there is a pending approval submission
  select * into v_pending_sub
  from subscriptions
  where cafe_id = p_cafe_id
    and status = 'PENDING_APPROVAL'
  order by created_at desc
  limit 1;

  if v_active_sub.id is not null then
    -- Cafe has an approved ACTIVE paid plan
    v_tier := v_active_sub.tier;
    v_status := 'ACTIVE';
    v_start_date := v_active_sub.start_date;
    v_end_date := v_active_sub.end_date;
    v_days_left := greatest(0, ceil(extract(epoch from (v_end_date - now())) / 86400)::int);
    v_is_trial := false;
  else
    -- Fallback to 7-Day Free Trial
    v_trial_end := v_cafe.created_at + interval '7 days';
    v_start_date := v_cafe.created_at;
    v_end_date := v_trial_end;
    
    if now() <= v_trial_end then
      v_tier := 'TRIAL';
      v_status := 'ACTIVE_TRIAL';
      v_days_left := greatest(1, ceil(extract(epoch from (v_trial_end - now())) / 86400)::int);
      v_is_trial := true;
    else
      v_tier := 'TRIAL';
      v_status := 'EXPIRED_TRIAL';
      v_days_left := 0;
      v_is_trial := true;
    end if;
  end if;

  -- Compute resource quotas strictly from the active tier!
  if v_status = 'EXPIRED_TRIAL' then
    v_max_tables := 0;
    v_max_items := 0;
  elsif v_tier = 'ENTERPRISE' then
    v_max_tables := -1;
    v_max_items := -1;
  elsif v_tier = 'GROWTH' then
    v_max_tables := 20;
    v_max_items := 70;
  elsif v_tier = 'STARTER' then
    v_max_tables := 5;
    v_max_items := 30;
  else -- 'TRIAL'
    v_max_tables := 5;
    v_max_items := 30;
  end if;

  select count(*) into v_tables_count from tables where cafe_id = p_cafe_id;
  select count(*) into v_items_count from menu_items where cafe_id = p_cafe_id and is_deleted = false;

  return jsonb_build_object(
    'tier', v_tier,
    'status', v_status,
    'is_trial', v_is_trial,
    'start_date', v_start_date,
    'end_date', v_end_date,
    'days_remaining', v_days_left,
    'tables_used', v_tables_count,
    'max_tables', v_max_tables,
    'items_used', v_items_count,
    'max_items', v_max_items,
    'utr_number', v_active_sub.utr_number,
    'amount_paid', coalesce(v_active_sub.amount_paid, 0),
    'has_pending_approval', (v_pending_sub.id is not null),
    'pending_tier', v_pending_sub.tier,
    'pending_utr', v_pending_sub.utr_number,
    'pending_amount', v_pending_sub.amount_paid
  );
end;
$$;

grant execute on function get_cafe_subscription_overview(uuid) to anon, authenticated;

-- 7. RPC: submit_subscription_payment
-- Submits payment details for Super Admin verification without auto-activating or duplicate blocking
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
  v_clean_tier text;
  v_expected_amount numeric(10,2);
  v_new_sub_id uuid;
  v_txn_id text;
begin
  v_clean_utr := trim(p_utr_number);
  v_clean_tier := upper(trim(p_tier));

  if length(v_clean_utr) < 8 or length(v_clean_utr) > 30 then
    return jsonb_build_object(
      'success', false,
      'error', 'INVALID_UTR: Please enter a valid Bank Transaction / UTR Number.'
    );
  end if;

  -- Validate tier and pricing
  if v_clean_tier = 'STARTER' then
    v_expected_amount := 399.00;
  elsif v_clean_tier = 'GROWTH' then
    v_expected_amount := 799.00;
  elsif v_clean_tier = 'ENTERPRISE' then
    v_expected_amount := 1499.00;
  else
    return jsonb_build_object('success', false, 'error', 'INVALID_TIER: Unknown subscription tier.');
  end if;

  if p_amount != v_expected_amount then
    return jsonb_build_object(
      'success', false,
      'error', format('AMOUNT_MISMATCH: Amount paid (₹%s) does not match the %s tier price (₹%s).', p_amount, v_clean_tier, v_expected_amount)
    );
  end if;

  -- Generate transaction id if not supplied
  v_txn_id := coalesce(p_merchant_txn_id, 'TXN_' || substring(gen_random_uuid()::text, 1, 12));

  -- Insert subscription in PENDING_APPROVAL status (NO auto-activation!)
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
    'PENDING_APPROVAL',
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
    v_clean_tier,
    p_amount,
    'PENDING_VERIFICATION',
    'UPI_TRANSFER',
    jsonb_build_object('utr', v_clean_utr, 'amount', p_amount, 'tier', v_clean_tier),
    null
  );

  return jsonb_build_object(
    'success', true,
    'subscription_id', v_new_sub_id,
    'tier', v_clean_tier,
    'status', 'PENDING_APPROVAL',
    'utr_number', v_clean_utr,
    'message', format('Payment submitted for approval! UTR #%s sent to Super Admin. Once verified, your %s plan will be activated.', v_clean_utr, v_clean_tier)
  );
end;
$$;

grant execute on function submit_subscription_payment(uuid, text, text, numeric, text) to authenticated;

-- 7.1 RPC: approve_subscription
create or replace function approve_subscription(p_subscription_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_sub record;
begin
  if not is_super_admin() then
    return jsonb_build_object('success', false, 'error', 'ACCESS_DENIED: Super Admin privileges required.');
  end if;

  select * into v_sub from subscriptions where id = p_subscription_id;
  if v_sub.id is null then
    return jsonb_build_object('success', false, 'error', 'Subscription not found');
  end if;

  -- Expire any previous active subscriptions for this cafe
  update subscriptions
  set status = 'EXPIRED'
  where cafe_id = v_sub.cafe_id
    and id != p_subscription_id
    and status = 'ACTIVE';

  -- Activate approved subscription for 30 days
  update subscriptions
  set status = 'ACTIVE',
      start_date = now(),
      end_date = now() + interval '30 days'
  where id = p_subscription_id;

  -- Mark transaction verified and successful
  update payment_transactions
  set status = 'SUCCESS',
      verified_at = now()
  where subscription_id = p_subscription_id
     or (cafe_id = v_sub.cafe_id and utr_number = v_sub.utr_number);

  return jsonb_build_object(
    'success', true,
    'tier', v_sub.tier,
    'message', format('Subscription for %s activated successfully for 30 days!', v_sub.tier)
  );
end;
$$;

grant execute on function approve_subscription(uuid) to authenticated;

-- 7.2 RPC: reject_subscription
create or replace function reject_subscription(p_subscription_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_sub record;
begin
  if not is_super_admin() then
    return jsonb_build_object('success', false, 'error', 'ACCESS_DENIED: Super Admin privileges required.');
  end if;

  select * into v_sub from subscriptions where id = p_subscription_id;
  if v_sub.id is null then
    return jsonb_build_object('success', false, 'error', 'Subscription not found');
  end if;

  update subscriptions
  set status = 'REJECTED'
  where id = p_subscription_id;

  update payment_transactions
  set status = 'FAILED'
  where subscription_id = p_subscription_id
     or (cafe_id = v_sub.cafe_id and utr_number = v_sub.utr_number);

  return jsonb_build_object('success', true, 'message', 'Subscription payment rejected.');
end;
$$;

grant execute on function reject_subscription(uuid, text) to authenticated;

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
-- ==============================================================================
-- Seed: seed.sql
-- Sample data for Cafe QR-Based Ordering & Management System
-- ==============================================================================

-- 1. Ensure owner_id column allows NULL so seed runs before any user registers
alter table cafes alter column owner_id drop not null;

-- 2. Ensure RLS policies allow managing seed cafe before owner is created
drop policy if exists "Owner can view own cafe" on cafes;
create policy "Owner can view own cafe"
  on cafes for select
  using (auth.uid() = owner_id or owner_id is null);

drop policy if exists "Owner can update own cafe" on cafes;
create policy "Owner can update own cafe"
  on cafes for update
  using (auth.uid() = owner_id or owner_id is null);

drop policy if exists "Owner can manage own tables" on tables;
create policy "Owner can manage own tables"
  on tables for all
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null))
  with check (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

drop policy if exists "Owner can manage own menu" on menu_items;
create policy "Owner can manage own menu"
  on menu_items for all
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null))
  with check (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

drop policy if exists "Owner can view own cafe orders" on orders;
create policy "Owner can view own cafe orders"
  on orders for select
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

drop policy if exists "Owner can update own cafe orders" on orders;
create policy "Owner can update own cafe orders"
  on orders for update
  using (cafe_id in (select id from cafes where owner_id = auth.uid() or owner_id is null));

-- 3. INSERT DEMO CAFE & TABLES & MENU ITEMS
do $$
declare
  v_cafe_id uuid := 'a0000000-0000-0000-0000-000000000001';
  v_owner_id uuid;
begin
  -- If a user already signed up in Supabase Auth, attach cafe to them; otherwise leave NULL
  select id into v_owner_id from auth.users order by created_at asc limit 1;

  insert into cafes (id, name, owner_id)
  values (v_cafe_id, 'Aroma Artisan Cafe', v_owner_id)
  on conflict (id) do update set
    name = excluded.name,
    owner_id = coalesce(cafes.owner_id, excluded.owner_id);

  -- 4. INSERT DEMO TABLES WITH FIXED QR TOKENS
  -- These deterministic tokens make it easy to test direct URLs:
  -- Table 1 QR Token: 11111111-1111-1111-1111-111111111101
  -- Table 2 QR Token: 11111111-1111-1111-1111-111111111102
  insert into tables (cafe_id, table_number, qr_token) values
    (v_cafe_id, 1, '11111111-1111-1111-1111-111111111101'),
    (v_cafe_id, 2, '11111111-1111-1111-1111-111111111102'),
    (v_cafe_id, 3, '11111111-1111-1111-1111-111111111103'),
    (v_cafe_id, 4, '11111111-1111-1111-1111-111111111104'),
    (v_cafe_id, 5, '11111111-1111-1111-1111-111111111105')
  on conflict do nothing;

  -- 5. INSERT SAMPLE MENU ITEMS ACROSS CATEGORIES
  insert into menu_items (id, cafe_id, name, description, category, price, offer_price, image_url, is_available) values
    -- Coffee & Hot Beverages
    ('b0000000-0000-0000-0000-000000000001', v_cafe_id, 'Caramel Macchiato', 'Rich espresso with steamed milk and vanilla-caramel drizzle.', 'Hot Beverages', 240.00, 199.00, 'https://images.unsplash.com/photo-1485808191679-5f86510681a2?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000002', v_cafe_id, 'Hazelnut Cappuccino', 'Double shot espresso topped with dense micro-foam and hazelnut.', 'Hot Beverages', 220.00, null, 'https://images.unsplash.com/photo-1572442388796-11668a67e53d?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000003', v_cafe_id, 'Belgian Hot Chocolate', 'Pure melted dark chocolate blended with velvety whole milk.', 'Hot Beverages', 260.00, 220.00, 'https://images.unsplash.com/photo-1542990253-0d0f5be5f0ed?w=300&auto=format&fit=crop&q=80', true),
    
    -- Cold Brews & Refreshers
    ('b0000000-0000-0000-0000-000000000004', v_cafe_id, 'Vanilla Sweet Cream Cold Brew', 'Steeped for 18 hours, infused with custom sweet cream float.', 'Cold Brews', 280.00, 249.00, 'https://images.unsplash.com/photo-1517701550927-30cf4ba1dba5?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000005', v_cafe_id, 'Passion Fruit Iced Tea', 'Refreshing black tea with fresh passion fruit pulp and mint.', 'Cold Brews', 190.00, null, 'https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000006', v_cafe_id, 'Classic Mango Frappe', 'Blended chilled milk, fresh Alphonso mangoes and whipped cream.', 'Cold Brews', 250.00, null, 'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=300&auto=format&fit=crop&q=80', false), -- Out of stock test

    -- Artisanal Sandwiches & Bites
    ('b0000000-0000-0000-0000-000000000007', v_cafe_id, 'Pesto Grilled Cheese Sourdough', 'Aged cheddar, mozzarella, sun-dried tomatoes & basil pesto on toasted sourdough.', 'Artisanal Bites', 320.00, 280.00, 'https://images.unsplash.com/photo-1528735602780-2552fd46c7af?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000008', v_cafe_id, 'Smoked Paprika Paneer Wrap', 'Char-grilled cottage cheese with crunchy bell peppers and herb mayo.', 'Artisanal Bites', 290.00, null, 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000009', v_cafe_id, 'Crispy Truffle Fries', 'Golden skin-on fries tossed in white truffle oil, parmesan & chives.', 'Artisanal Bites', 230.00, 199.00, 'https://images.unsplash.com/photo-1576107232684-1279f3908594?w=300&auto=format&fit=crop&q=80', true),

    -- Main Course
    ('b0000000-0000-0000-0000-000000000010', v_cafe_id, 'Wild Mushroom Penne Alfredo', 'Sautéed cremini & shiitake mushrooms in garlic-parmesan cream sauce.', 'Main Course', 390.00, null, 'https://images.unsplash.com/photo-1621996346565-e3d5d62817d2?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000011', v_cafe_id, 'Artisan Margherita Pizza', 'San Marzano tomato base, fresh buffalo mozzarella, olive oil & basil leaves.', 'Main Course', 440.00, 399.00, 'https://images.unsplash.com/photo-1604382355076-af4b0eb60143?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000012', v_cafe_id, 'Mexican Rice Bowl', 'Spiced brown rice, black beans, guacamole, pico de gallo & sour cream.', 'Main Course', 360.00, null, 'https://images.unsplash.com/photo-1543339308-43e59d6b73a6?w=300&auto=format&fit=crop&q=80', true),

    -- Desserts & Bakery
    ('b0000000-0000-0000-0000-000000000013', v_cafe_id, 'Warm Nutella Croissant', 'Flaky butter croissant filled with warm Nutella and toasted hazelnuts.', 'Desserts', 210.00, null, 'https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000014', v_cafe_id, 'New York Cheesecake', 'Silky baked cheesecake topped with homemade blueberry compote.', 'Desserts', 270.00, 239.00, 'https://images.unsplash.com/photo-1533134242443-d4fd215305ad?w=300&auto=format&fit=crop&q=80', true),
    ('b0000000-0000-0000-0000-000000000015', v_cafe_id, 'Double Fudge Brownie Sundae', 'Gooey dark fudge brownie served warm with vanilla bean gelato & fudge syrup.', 'Desserts', 260.00, null, 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=300&auto=format&fit=crop&q=80', true)
  on conflict (id) do nothing;
end $$;
