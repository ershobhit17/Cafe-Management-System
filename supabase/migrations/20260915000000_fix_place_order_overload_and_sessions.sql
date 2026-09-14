-- =====================================================================
-- Migration: 20260915000000_fix_place_order_overload_and_sessions.sql
-- Description: Fix PostgreSQL function overloading ambiguity on place_order
--              and resolve ambiguous column reference in get_or_create_table_session
-- =====================================================================

-- 1. DROP ALL PREVIOUS OVERLOADED SIGNATURES OF place_order
DROP FUNCTION IF EXISTS public.place_order(jsonb, uuid, uuid, text);
DROP FUNCTION IF EXISTS public.place_order(uuid, jsonb, text);
DROP FUNCTION IF EXISTS public.place_order(uuid, jsonb);

-- 2. CREATE CANONICAL UNIFIED place_order FUNCTION
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
  -- Identify token (session token preferred, fallback to table qr token)
  v_token := coalesce(p_session_token, p_qr_token);
  IF v_token IS NULL THEN
    RAISE EXCEPTION 'Missing table QR token or session token';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order cart cannot be empty';
  END IF;

  -- 1. First attempt: Match against table_sessions (Anti-fraud session system)
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
    -- 2. Fallback attempt: Match directly against tables.qr_token
    SELECT t.id AS table_id, t.cafe_id, t.table_number,
           coalesce(c.is_suspended, false) AS is_suspended, c.suspended_reason
      INTO v_table
      FROM tables t
      JOIN cafes c ON c.id = t.cafe_id
     WHERE t.qr_token = v_token;

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

  -- 3. Create the order tagged with session_id and notes
  INSERT INTO orders (cafe_id, table_id, session_id, status, total_amount, notes)
  VALUES (v_cafe_id, v_table_id, v_session_id, 'pending', 0, p_notes)
  RETURNING id INTO v_order_id;

  -- 4. Calculate server-side verified pricing and check availability
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity := (v_item->>'quantity')::int;
    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero';
    END IF;

    SELECT id, price, offer_price, is_available, is_deleted, cafe_id, name
      INTO v_menu_item
      FROM menu_items
     WHERE id = (v_item->>'menu_item_id')::uuid;

    IF v_menu_item.id IS NULL OR v_menu_item.cafe_id != v_cafe_id OR v_menu_item.is_deleted = true THEN
      RAISE EXCEPTION 'Menu item is not available: %', (v_item->>'menu_item_id');
    END IF;

    IF v_menu_item.is_available = false THEN
      RAISE EXCEPTION 'Item "%" is currently out of stock', v_menu_item.name;
    END IF;

    v_price := coalesce(v_menu_item.offer_price, v_menu_item.price);
    v_line_total := v_price * v_quantity;
    v_total := v_total + v_line_total;

    INSERT INTO order_items (order_id, menu_item_id, quantity, price_at_order_time)
    VALUES (v_order_id, v_menu_item.id, v_quantity, v_price);
  END LOOP;

  -- 5. Update verified order total
  UPDATE orders SET total_amount = v_total WHERE id = v_order_id;

  RETURN v_order_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.place_order(uuid, jsonb, text, uuid) TO anon, authenticated;


-- 3. RESOLVE TABLE_ID AMBIGUITY IN get_or_create_table_session
CREATE OR REPLACE FUNCTION public.get_or_create_table_session(
  p_qr_token uuid,
  p_session_token uuid DEFAULT NULL::uuid,
  p_force_new boolean DEFAULT false
)
RETURNS TABLE (
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
  -- Lookup table and cafe by QR token
  SELECT t.id AS table_id, t.table_number, t.cafe_id, c.name AS cafe_name,
         coalesce(c.is_suspended, false) AS is_suspended, c.suspended_reason
    INTO v_table
    FROM tables t
    JOIN cafes c ON c.id = t.cafe_id
   WHERE t.qr_token = p_qr_token;

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
