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
