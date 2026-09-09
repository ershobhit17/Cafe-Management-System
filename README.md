# 🧡 Cafe QR-Based Ordering & Management System

A production-ready, full-stack Cafe & Restaurant QR-Code Ordering and Real-time Management System built with:
1. **Supabase Backend**: Postgres database, strict Row Level Security (RLS), tamper-proof server-side pricing calculation (`place_order` RPC), and Realtime notifications.
2. **Customer Web App**: High-performance, zero-build Vanilla HTML5/CSS3/JS mobile-first web app with warm orange styling (`#FF7A00`), dark/light theme, category navigation, search, cart drawer, and live order status tracking (`order-status.html`).
3. **Owner/Staff App (Flutter)**: Multi-platform Flutter app with persistent session auth, live incoming orders dashboard with real-time updates and status buttons, categorized menu management (CRUD, offer prices, instant out-of-stock toggle), table QR code generation (`qr_flutter`), and daily/weekly/monthly earnings analytics with interactive charts (`fl_chart`).

---

## 📁 Repository Structure

```
CafeManagementSytem/
├── supabase/
│   ├── migrations/
│   │   └── 20260909000000_initial_schema.sql  # Full schema, RLS policies & secure RPCs
│   ├── seed.sql                               # Demo cafe, 5 tables with QR tokens, 15+ menu items
│   └── README.md                              # Supabase step-by-step setup guide
├── customer-web/                              # Zero-build Customer Web Application
│   ├── index.html                             # Customer menu, category pills & cart drawer
│   ├── order-status.html                      # Live order tracking with animated stepper
│   ├── style.css                              # Warm orange palette, light & dark modes, responsive
│   ├── app.js                                 # Cart arithmetic, tamper-proof RPC caller & demo mode
│   ├── order-status.js                        # Supabase Realtime channel subscription & status stepper
│   └── config.js                              # Supabase credentials & demo fallback catalog
└── owner_app/                                 # Flutter Owner / Kitchen Management App
    ├── lib/
    │   ├── main.dart                          # App entrypoint, ThemeData (light/dark orange) & routing
    │   ├── config/supabase_config.dart        # Project credentials & demo context
    │   ├── models/                            # Cafe, CafeTable, MenuItem, OrderModel, OrderItemModel
    │   ├── services/                          # AuthService, CafeService, MenuService, OrderService, EarningsService
    │   └── screens/
    │       ├── auth/login_screen.dart         # Email/password login with persistent session
    │       ├── dashboard/live_orders_screen.dart # Realtime kitchen ticket feed & status buttons
    │       ├── menu/menu_management_screen.dart  # Menu item list, stock switch, offer price
    │       ├── menu/edit_menu_item_dialog.dart   # Add/Edit menu item modal
    │       ├── tables/tables_qr_screen.dart   # Table management & scannable QR generation
    │       ├── earnings/earnings_screen.dart  # Daily reset earnings, date ranges & fl_chart
    │       └── home/main_nav_screen.dart      # Bottom navigation hub
    └── pubspec.yaml                           # Dependencies (supabase_flutter, fl_chart, qr_flutter, etc.)
```

---

## 🚀 Quick Start Guide

### 1. Database Setup (Supabase)
1. Open your Supabase project dashboard: [https://supabase.com/dashboard](https://supabase.com/dashboard).
2. Go to **SQL Editor** -> **+ New query**.
3. Copy and run [`supabase/migrations/20260909000000_initial_schema.sql`](./supabase/migrations/20260909000000_initial_schema.sql).
4. (Optional for demo) Copy and run [`supabase/seed.sql`](./supabase/seed.sql).
5. Copy your **Project URL** and **anon/public key** from **Project Settings** -> **API**:
   - Paste into `customer-web/config.js`
   - Paste into `owner_app/lib/config/supabase_config.dart`

---

### 2. Running Customer Web App (HTML/CSS/JS)
The customer app requires zero build tools or dependencies! You can open it directly or serve it with any local web server:

```powershell
# Using Python
python -m http.server 3000 --directory customer-web

# Or using Node npx serve
npx serve customer-web -p 3000
```

Open in browser:
- Direct Menu URL: `http://localhost:3000/index.html?cafe=a0000000-0000-0000-0000-000000000001&table=11111111-1111-1111-1111-111111111103`
- *Note:* If opened without query parameters, it automatically activates the built-in interactive demo mode (Table #3).

---

### 3. Running Owner Flutter App
```powershell
cd owner_app
flutter run
```
You can run it on Windows desktop, Chrome, Android, or iOS!
- If you haven't linked Supabase yet, tap **"Preview / Offline Demo Mode"** on the login screen to immediately test all screens (Live Orders, Stock Toggles, Table QR Codes, and Earnings Charts).

---

## 🔒 Security Highlights

- **Zero-Trust Client Pricing**: The browser only sends `menu_item_id` and `quantity` to the `place_order` Postgres function (`SECURITY DEFINER`). Prices and totals are looked up and computed strictly inside the database. Tampering with JavaScript client-side prices has zero effect.
- **Strict Row Level Security (RLS)**: Anonymous users cannot insert into or update the `orders` or `order_items` tables directly.
- **Unguessable QR Tokens**: Tables use UUID `qr_token`s in the URL rather than predictable integers, protecting against table spoofing.
