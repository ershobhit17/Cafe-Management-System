# Supabase Backend Setup Guide
## Cafe QR-Based Ordering & Management System

This directory contains the database schema, security model (Row Level Security), and seed data for the Cafe Management System.

---

### Quick Setup in Supabase Cloud Dashboard

1. **Log in to Supabase**: Go to [https://supabase.com/dashboard](https://supabase.com/dashboard) and open your project.
2. **Open SQL Editor**: In the left sidebar, click on **SQL Editor** -> **+ New query**.
3. **Run Schema Migration**:
   - Copy the contents of [`migrations/20260909000000_initial_schema.sql`](./migrations/20260909000000_initial_schema.sql).
   - Paste into the SQL editor and click **Run**.
   - This creates the tables (`cafes`, `tables`, `menu_items`, `orders`, `order_items`), enables Row Level Security (RLS) on all tables, and creates the `place_order` and `get_order_status` secure RPC functions.
4. **Run Seed Data (Optional for Demo)**:
   - Copy the contents of [`seed.sql`](./seed.sql).
   - Paste and run. This sets up a demo cafe, 5 tables with deterministic QR UUID tokens, and 15 categorized food/drink items.
5. **Enable Realtime**:
   - Navigate to **Database** -> **Publications** -> **supabase_realtime**.
   - Verify that `orders` table is toggled ON (the migration script attempts to add this automatically).
6. **Get API Credentials**:
   - Navigate to **Project Settings** -> **API**.
   - Copy **Project URL** and the **anon / public** API Key.
   - Add these values to `customer-web/config.js` and `owner_app/lib/config/supabase_config.dart`.

---

### Security Architecture Highlights

- **Strict RLS**: Direct inserts to `orders` and `order_items` from anonymous users are blocked.
- **Tamper-Proof Pricing**: Customers trigger the `place_order(p_qr_token, p_items)` RPC function (`SECURITY DEFINER`). Prices and totals are looked up and computed strictly inside Postgres, making it mathematically impossible for a customer to tamper with prices in browser dev tools.
- **QR Token Obfuscation**: Tables use unguessable UUIDs (`qr_token`) rather than sequential IDs (`table=1`), preventing casual table spoofing.
