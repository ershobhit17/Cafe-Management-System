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
