-- =====================================================================
-- Migration: 20260915010000_cafe_isolation_and_rls.sql
-- Description: 
--   1. Allow anonymous customers to view cafe names (fixes "Aroma Artisan Cafe" fallback)
--   2. Fix variable ambiguity and support both qr_token and table_id in get_or_create_table_session
--   3. Include cafe_name and cafe_id in get_order_status for direct customer tracking
--   4. Ensure strict cafe isolation during order placement
-- =====================================================================

-- 1. RLS POLICY: ALLOW PUBLIC TO VIEW ACTIVE CAFES
DROP POLICY IF EXISTS "Public can view active cafes" ON public.cafes;
CREATE POLICY "Public can view active cafes"
ON public.cafes
FOR SELECT
TO anon, authenticated
USING (true);

-- 2. ENHANCED get_or_create_table_session
CREATE OR REPLACE FUNCTION public.get_or_create_table_session(
  p_qr_token uuid,
  p_session_token uuid DEFAULT NULL::uuid,
  p_force_new boolean DEFAULT false
)
RETURNS TABLE(
  session_token uuid,
  session_id uuid,
  table_id uuid,
  table_number integer,
  cafe_id uuid,
  cafe_name text,
  status text,
  expires_at timestamp with time zone,
  is_active boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_table record;
  v_session record;
  v_new_token uuid;
  v_new_session_id uuid;
BEGIN
  -- Lookup table and cafe by QR token OR table ID
  SELECT t.id AS table_id, t.table_number, t.cafe_id, c.name AS cafe_name,
         coalesce(c.is_suspended, false) AS is_suspended, c.suspended_reason
    INTO v_table
    FROM tables t
    JOIN cafes c ON c.id = t.cafe_id
   WHERE t.qr_token = p_qr_token OR t.id = p_qr_token
   LIMIT 1;

  IF v_table.table_id IS NULL THEN
    RAISE EXCEPTION 'Invalid table or QR code';
  END IF;

  IF v_table.is_suspended = true THEN
    RAISE EXCEPTION 'CAFE_SUSPENDED: This cafe is temporarily inactive: %', coalesce(v_table.suspended_reason, 'Please contact cafe administration.');
  END IF;

  -- If customer provided an existing session token and not forcing new session, verify it
  IF p_session_token IS NOT NULL AND p_force_new IS false THEN
    SELECT s.id, s.session_token, s.status, s.expires_at
      INTO v_session
      FROM table_sessions s
     WHERE s.session_token = p_session_token
       AND s.table_id = v_table.table_id;

    IF v_session.id IS NOT NULL THEN
      IF v_session.status = 'active' AND v_session.expires_at > now() THEN
        RETURN QUERY SELECT
          v_session.session_token,
          v_session.id AS session_id,
          v_table.table_id,
          v_table.table_number,
          v_table.cafe_id,
          v_table.cafe_name,
          v_session.status,
          v_session.expires_at,
          true AS is_active;
        RETURN;
      ELSE
        -- Session exists but is expired or closed -> return it as read-only / inactive
        RETURN QUERY SELECT
          v_session.session_token,
          v_session.id AS session_id,
          v_table.table_id,
          v_table.table_number,
          v_table.cafe_id,
          v_table.cafe_name,
          v_session.status,
          v_session.expires_at,
          false AS is_active;
        RETURN;
      END IF;
    END IF;
  END IF;

  -- TABLE TURNOVER / NEW CUSTOMER ARRIVAL:
  -- Invalidate and close previous active sessions for this table
  UPDATE table_sessions
     SET status = 'closed',
         closed_at = now()
   WHERE table_sessions.table_id = v_table.table_id
     AND table_sessions.status = 'active';

  -- Generate new active session with 2-hour validity
  v_new_token := gen_random_uuid();
  INSERT INTO table_sessions (table_id, cafe_id, session_token, status, expires_at)
  VALUES (v_table.table_id, v_table.cafe_id, v_new_token, 'active', now() + interval '2 hours')
  RETURNING id INTO v_new_session_id;

  RETURN QUERY SELECT
    v_new_token AS session_token,
    v_new_session_id AS session_id,
    v_table.table_id,
    v_table.table_number,
    v_table.cafe_id,
    v_table.cafe_name,
    'active'::text AS status,
    (now() + interval '2 hours')::timestamptz AS expires_at,
    true AS is_active;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_or_create_table_session(uuid, uuid, boolean) TO anon, authenticated;

-- 3. ENHANCED get_order_status WITH CAFE DETAILS
DROP FUNCTION IF EXISTS public.get_order_status(uuid);

CREATE OR REPLACE FUNCTION public.get_order_status(p_order_id uuid)
RETURNS TABLE(
  status text, 
  total_amount numeric, 
  created_at timestamp with time zone, 
  table_number integer, 
  cafe_name text, 
  cafe_id uuid, 
  items jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select
    o.status,
    o.total_amount,
    o.created_at,
    t.table_number,
    c.name as cafe_name,
    o.cafe_id,
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
  left join cafes c on c.id = o.cafe_id
  where o.id = p_order_id;
$function$;

GRANT EXECUTE ON FUNCTION public.get_order_status(uuid) TO anon, authenticated;

-- 4. STRICT CAFE ISOLATION IN place_order
CREATE OR REPLACE FUNCTION public.place_order(
  p_session_token uuid DEFAULT NULL::uuid,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_notes text DEFAULT NULL::text,
  p_qr_token uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_token uuid;
  v_session record;
  v_table record;
  v_order_id uuid;
  v_item jsonb;
  v_menu_item record;
  v_total numeric(10,2) := 0;
  v_line_total numeric(10,2);
  v_price numeric(10,2);
  v_quantity int;
  v_cafe_id uuid;
  v_table_id uuid;
  v_session_id uuid := null;
BEGIN
  v_token := coalesce(p_session_token, p_qr_token);
  IF v_token IS NULL THEN
    RAISE EXCEPTION 'Missing table QR token or session token';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order cart cannot be empty';
  END IF;

  SELECT s.id AS session_id, s.table_id, s.cafe_id, s.status, s.expires_at, t.table_number,
         coalesce(c.is_suspended, false) AS is_suspended, c.suspended_reason
    INTO v_session
    FROM table_sessions s
    JOIN tables t ON t.id = s.table_id
    JOIN cafes c ON c.id = s.cafe_id
   WHERE s.session_token = v_token;

  IF v_session.session_id IS NOT NULL THEN
    IF v_session.is_suspended = true THEN
      RAISE EXCEPTION 'CAFE_SUSPENDED: This cafe is temporarily inactive: %', coalesce(v_session.suspended_reason, 'Please contact cafe administration.');
    END IF;

    IF v_session.status != 'active' OR v_session.expires_at <= now() THEN
      UPDATE table_sessions SET status = 'closed', closed_at = coalesce(closed_at, now()) WHERE id = v_session.session_id;
      RAISE EXCEPTION 'Session expired or table closed. Please scan the QR again.';
    END IF;

    v_cafe_id := v_session.cafe_id;
    v_table_id := v_session.table_id;
    v_session_id := v_session.session_id;
  ELSE
    SELECT t.id AS table_id, t.cafe_id, t.table_number,
           coalesce(c.is_suspended, false) AS is_suspended, c.suspended_reason
      INTO v_table
      FROM tables t
      JOIN cafes c ON c.id = t.cafe_id
     WHERE t.qr_token = v_token OR t.id = v_token
     LIMIT 1;

    IF v_table.table_id IS NOT NULL THEN
      IF v_table.is_suspended = true THEN
        RAISE EXCEPTION 'CAFE_SUSPENDED: This cafe is temporarily inactive: %', coalesce(v_table.suspended_reason, 'Please contact cafe administration.');
      END IF;

      v_cafe_id := v_table.cafe_id;
      v_table_id := v_table.table_id;
    ELSE
      RAISE EXCEPTION 'Session expired or table closed. Please scan the QR again.';
    END IF;
  END IF;

  INSERT INTO orders (cafe_id, table_id, session_id, status, total_amount, notes)
  VALUES (v_cafe_id, v_table_id, v_session_id, 'pending', 0, p_notes)
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity := (v_item->>'quantity')::int;
    IF v_quantity <= 0 THEN
      CONTINUE;
    END IF;

    SELECT id, price, is_available, is_deleted, cafe_id
      INTO v_menu_item
      FROM menu_items
     WHERE id = (v_item->>'menu_item_id')::uuid;

    IF v_menu_item.id IS NULL OR v_menu_item.is_deleted = true THEN
      RAISE EXCEPTION 'Item not found or no longer available';
    END IF;

    IF v_menu_item.cafe_id != v_cafe_id THEN
      RAISE EXCEPTION 'Item does not belong to this cafe';
    END IF;

    IF v_menu_item.is_available = false THEN
      RAISE EXCEPTION 'Item is currently sold out';
    END IF;

    v_price := v_menu_item.price;
    v_line_total := v_price * v_quantity;
    v_total := v_total + v_line_total;

    INSERT INTO order_items (order_id, menu_item_id, quantity, price_at_order_time)
    VALUES (v_order_id, v_menu_item.id, v_quantity, v_price);
  END LOOP;

  UPDATE orders
     SET total_amount = v_total
   WHERE id = v_order_id;

  RETURN v_order_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.place_order(uuid, jsonb, text, uuid) TO anon, authenticated;
