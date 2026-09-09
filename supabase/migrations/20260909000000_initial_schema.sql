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
