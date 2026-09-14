// ==============================================================================
// Customer Ordering Web App - Main Logic (app.js)
// Features:
//   - Anti-Fraud Table Session Management (UUID, 2hr validity, turnover handling)
//   - Dynamic Cafe Name from Database
//   - Filter Active Menu Items (is_deleted = false)
//   - "My Orders" Session Order History & Live Tracking
//   - Order Summary & Clean Printable Receipt
// ==============================================================================

(function () {
  // 1. STATE & CONTEXT
  let allMenuItems = [];
  let activeCategory = "ALL";
  let searchQuery = "";
  let cart = {}; // { [item_id]: { item, quantity } }
  let sessionOrders = [];
  let isSessionActive = true;
  let supabase = null;
  let realtimeOrdersChannel = null;

  function isValidUuid(val) {
    if (!val || typeof val !== "string") return false;
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(val.trim());
  }

  // 1. READ & ISOLATE SESSION CONTEXT (URL PARAMS)
  const urlParams = new URLSearchParams(window.location.search);
  const paramCafe = urlParams.get("cafe");
  const paramTable = urlParams.get("table");
  const paramSession = urlParams.get("session");

  const storedQr = sessionStorage.getItem("qr_token") || localStorage.getItem("qr_token");
  const storedCafe = sessionStorage.getItem("cafe_id") || localStorage.getItem("cafe_id");
  const rawSessionStored = sessionStorage.getItem("session_token") || localStorage.getItem("session_token");
  const hasStaleDemoSession = rawSessionStored && !isValidUuid(rawSessionStored);

  // If a URL parameter specifies a table or cafe that is different from stored session,
  // or if stored session contains invalid demo strings (like "demo-sess-..."), wipe stale tokens and cart
  if (hasStaleDemoSession || (paramTable && storedQr && paramTable !== storedQr) || (paramCafe && storedCafe && paramCafe !== storedCafe)) {
    sessionStorage.clear();
    localStorage.removeItem("session_token");
    localStorage.removeItem("session_id");
    localStorage.removeItem("cart_items");
    localStorage.removeItem("cafe_id");
    localStorage.removeItem("cafe_name");
    localStorage.removeItem("qr_token");
    localStorage.removeItem("table_number");
    cart = {};
  }

  let cafeId = isValidUuid(paramCafe) ? paramCafe.trim() : (isValidUuid(sessionStorage.getItem("cafe_id")) ? sessionStorage.getItem("cafe_id") : null);
  let qrToken = isValidUuid(paramTable) ? paramTable.trim() : (isValidUuid(sessionStorage.getItem("qr_token")) ? sessionStorage.getItem("qr_token") : null);
  let sessionToken = isValidUuid(paramSession) ? paramSession.trim() : (isValidUuid(sessionStorage.getItem("session_token")) ? sessionStorage.getItem("session_token") : (isValidUuid(localStorage.getItem("session_token")) ? localStorage.getItem("session_token") : null));
  let sessionId = isValidUuid(sessionStorage.getItem("session_id")) ? sessionStorage.getItem("session_id") : (isValidUuid(localStorage.getItem("session_id")) ? localStorage.getItem("session_id") : null);
  let currentCafeName = sessionStorage.getItem("cafe_name") || "SnapServe Cafe";
  let currentTableNumber = sessionStorage.getItem("table_number") || 1;

  if (cafeId) sessionStorage.setItem("cafe_id", cafeId);
  if (qrToken) sessionStorage.setItem("qr_token", qrToken);
  if (sessionToken) sessionStorage.setItem("session_token", sessionToken);

  // Restore cart
  try {
    const savedCart = sessionStorage.getItem("cart_items");
    if (savedCart) cart = JSON.parse(savedCart);
  } catch (e) {
    cart = {};
  }

  // 2. THEME SETUP
  const themeToggleBtn = document.getElementById("themeToggleBtn");
  function applyTheme(theme) {
    const isDark = theme === "dark";
    document.body.classList.toggle("dark", isDark);
    if (themeToggleBtn) themeToggleBtn.textContent = isDark ? "☀️" : "🌙";
    localStorage.setItem("cafe_theme", theme);
  }

  const savedTheme = localStorage.getItem("cafe_theme") ||
    (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  applyTheme(savedTheme);

  if (themeToggleBtn) {
    themeToggleBtn.addEventListener("click", () => {
      const nextTheme = document.body.classList.contains("dark") ? "light" : "dark";
      applyTheme(nextTheme);
    });
  }

  // 3. SUPABASE INITIALIZATION
  if (isSupabaseConfigured() && window.supabase) {
    try {
      supabase = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);
      console.log("Supabase client initialized successfully.");
    } catch (err) {
      console.warn("Supabase init error, falling back to Demo Mode:", err);
    }
  }

  // 4. TOAST NOTIFICATIONS
  function showToast(message) {
    const toast = document.getElementById("toast");
    if (!toast) return;
    toast.textContent = message;
    toast.classList.remove("hidden");
    clearTimeout(toast._timeout);
    toast._timeout = setTimeout(() => {
      toast.classList.add("hidden");
    }, 2500);
  }

  // 5. TABLE SESSION INITIALIZATION & ANTI-FRAUD
  async function initTableSession() {
    if (supabase && qrToken) {
      try {
        const cleanSessionToken = isValidUuid(sessionToken) ? sessionToken : null;
        let { data, error } = await supabase.rpc("get_or_create_table_session", {
          p_qr_token: qrToken,
          p_session_token: cleanSessionToken
        });

        // If error occurred and an old session token was passed, retry once with null to start fresh
        if (error && cleanSessionToken) {
          sessionStorage.removeItem("session_token");
          localStorage.removeItem("session_token");
          sessionToken = null;
          const retryRes = await supabase.rpc("get_or_create_table_session", {
            p_qr_token: qrToken,
            p_session_token: null
          });
          data = retryRes.data;
          error = retryRes.error;
        }

        if (!error && data && data.length > 0) {
          const s = data[0];
          sessionToken = s.session_token;
          sessionId = s.session_id;
          isSessionActive = s.is_active === true;
          currentTableNumber = s.table_number;
          if (s.cafe_name) currentCafeName = s.cafe_name;
          if (s.cafe_id) cafeId = s.cafe_id;

          // Persist session tokens
          sessionStorage.setItem("session_token", sessionToken);
          localStorage.setItem("session_token", sessionToken);
          sessionStorage.setItem("session_id", sessionId);
          localStorage.setItem("session_id", sessionId);
          sessionStorage.setItem("cafe_id", cafeId);
          sessionStorage.setItem("cafe_name", currentCafeName);
          sessionStorage.setItem("table_number", currentTableNumber);
          sessionStorage.setItem("qr_token", qrToken);

          updateBrandAndTableUI(currentCafeName, currentTableNumber);
          updateSessionStatusUI(isSessionActive);
          return;
        } else if (error) {
          console.warn("Table session RPC error:", error);
        }
      } catch (err) {
        console.warn("Table session RPC exception:", err);
      }

      // Fallback: Direct table & cafe lookup by qrToken
      try {
        const { data: tableData } = await supabase
          .from("tables")
          .select("table_number, cafe_id, cafes(name)")
          .or(`qr_token.eq.${qrToken},id.eq.${qrToken}`)
          .maybeSingle();

        if (tableData) {
          currentTableNumber = tableData.table_number;
          if (tableData.cafe_id) cafeId = tableData.cafe_id;
          if (tableData.cafes && tableData.cafes.name) currentCafeName = tableData.cafes.name;

          sessionStorage.setItem("cafe_id", cafeId);
          sessionStorage.setItem("cafe_name", currentCafeName);
          sessionStorage.setItem("table_number", currentTableNumber);
          sessionStorage.setItem("qr_token", qrToken);

          updateBrandAndTableUI(currentCafeName, currentTableNumber);
          updateSessionStatusUI(true);
          return;
        }
      } catch (err) {
        console.warn("Direct table lookup failed:", err);
      }
    }

    // Direct cafe lookup if cafeId is known
    if (supabase && cafeId) {
      try {
        const { data: cafeData } = await supabase
          .from("cafes")
          .select("name")
          .eq("id", cafeId)
          .maybeSingle();

        if (cafeData && cafeData.name) {
          currentCafeName = cafeData.name;
          sessionStorage.setItem("cafe_name", currentCafeName);
          updateBrandAndTableUI(currentCafeName, currentTableNumber);
          updateSessionStatusUI(true);
          return;
        }
      } catch (_) {}
    }

    // Demo Mode session handling ONLY when Supabase is completely unavailable
    if (!supabase) {
      if (!sessionToken) {
        sessionToken = "demo-sess-" + Math.random().toString(36).substring(2, 10);
        sessionId = "demo-sid-" + Math.random().toString(36).substring(2, 10);
        sessionStorage.setItem("session_token", sessionToken);
        localStorage.setItem("session_token", sessionToken);
        sessionStorage.setItem("session_id", sessionId);
      }
      isSessionActive = true;
      updateBrandAndTableUI(CONFIG.DEMO_MODE.cafe_name, CONFIG.DEMO_MODE.table_number);
      updateSessionStatusUI(true);
    }
  }

  function updateBrandAndTableUI(cafeName, tableNum) {
    const brandEl = document.getElementById("cafeBrandName");
    const badge = document.getElementById("tableBadge");
    const drawerSub = document.getElementById("cartDrawerSubtitle");
    const ordersSub = document.getElementById("myOrdersSubtitle");

    if (brandEl) brandEl.textContent = cafeName;
    document.title = `${cafeName} - Menu & Ordering`;
    if (badge) badge.textContent = `Table #${tableNum}`;
    if (drawerSub) drawerSub.textContent = `Ordering for Table #${tableNum}`;
    if (ordersSub) ordersSub.textContent = `Table #${tableNum} • Current Session Orders`;
  }

  function updateSessionStatusUI(isActive) {
    const banner = document.getElementById("sessionBanner");
    const placeBtn = document.getElementById("placeOrderBtn");

    if (!isActive) {
      if (banner) banner.classList.remove("hidden");
      if (placeBtn) {
        placeBtn.disabled = true;
        placeBtn.innerHTML = `<span>Session Closed</span> <span>🔒</span>`;
      }
    } else {
      if (banner) banner.classList.add("hidden");
      if (placeBtn && placeBtn.disabled && placeBtn.innerHTML.includes("Session Closed")) {
        placeBtn.disabled = false;
        placeBtn.innerHTML = `<span>Send to Kitchen</span> <span>🚀</span>`;
      }
    }
  }

  // 6. LOAD MENU (EXCLUDING DELETED ITEMS FOR SPECIFIC CAFE ONLY)
  async function loadMenu() {
    if (supabase && cafeId) {
      try {
        const { data, error } = await supabase
          .from("menu_items")
          .select("*")
          .eq("cafe_id", cafeId)
          .eq("is_deleted", false)
          .order("category");

        if (!error && data) {
          allMenuItems = data;
        } else {
          allMenuItems = [];
        }
      } catch (err) {
        console.warn("Menu fetch error for cafe:", err);
        allMenuItems = [];
      }
    } else if (!supabase) {
      allMenuItems = CONFIG.DEMO_MODE.items;
    } else {
      allMenuItems = [];
    }

    renderCategoryPills();
    renderMenu();
    updateCartUI();
  }

  // 7. RENDER CATEGORY PILLS
  function renderCategoryPills() {
    const nav = document.getElementById("categoryNav");
    if (!nav) return;

    const categories = ["ALL", ...new Set(allMenuItems.map(i => i.category || "Other"))];
    nav.innerHTML = "";

    categories.forEach(cat => {
      const btn = document.createElement("button");
      btn.className = "category-pill" + (activeCategory === cat ? " active" : "");
      btn.textContent = cat === "ALL" ? "All Items" : cat;
      btn.addEventListener("click", () => {
        activeCategory = cat;
        document.querySelectorAll(".category-pill").forEach(p => p.classList.remove("active"));
        btn.classList.add("active");
        renderMenu();
      });
      nav.appendChild(btn);
    });
  }

  // 8. RENDER MENU ITEMS
  function renderMenu() {
    const container = document.getElementById("menuContainer");
    if (!container) return;
    container.innerHTML = "";

    let filtered = allMenuItems.filter(item => {
      const matchCat = activeCategory === "ALL" || (item.category || "Other") === activeCategory;
      const matchSearch =
        searchQuery === "" ||
        item.name.toLowerCase().includes(searchQuery) ||
        (item.description && item.description.toLowerCase().includes(searchQuery));
      return matchCat && matchSearch;
    });

    if (filtered.length === 0) {
      const isSearchActive = searchQuery.trim().length > 0;
      container.innerHTML = `
        <div style="text-align: center; padding: 48px 20px; color: var(--color-text-secondary);">
          <div style="font-size: 2.5rem; margin-bottom: 12px;">🍽️</div>
          <p style="font-weight: 700; font-size: 1.05rem; color: var(--color-text-primary); margin-bottom: 4px;">
            ${isSearchActive ? "No items found matching your search" : `Welcome to ${currentCafeName}!`}
          </p>
          <p style="font-size: 0.85rem; color: var(--color-text-muted);">
            ${isSearchActive ? "Try a different keyword or check other categories." : "Menu items will appear here once published by the cafe."}
          </p>
        </div>
      `;
      return;
    }

    if (activeCategory === "ALL" && searchQuery === "") {
      const categories = [...new Set(filtered.map(i => i.category || "Other"))];
      categories.forEach(cat => {
        const heading = document.createElement("h2");
        heading.className = "category-heading";
        heading.textContent = cat;
        container.appendChild(heading);

        const grid = document.createElement("div");
        grid.className = "menu-grid";
        filtered
          .filter(i => (i.category || "Other") === cat)
          .forEach(item => grid.appendChild(createItemCard(item)));
        container.appendChild(grid);
      });
    } else {
      const grid = document.createElement("div");
      grid.className = "menu-grid";
      grid.style.marginTop = "14px";
      filtered.forEach(item => grid.appendChild(createItemCard(item)));
      container.appendChild(grid);
    }
  }

  // 9. CREATE ITEM CARD ELEMENT
  function createItemCard(item) {
    const card = document.createElement("div");
    card.className = "item-card" + (!item.is_available ? " unavailable" : "");
    card.id = `item-card-${item.id}`;

    const hasOffer = item.offer_price && item.offer_price < item.price;
    const effectivePrice = hasOffer ? item.offer_price : item.price;

    let priceHtml = `<span class="item-price">₹${effectivePrice}</span>`;
    if (hasOffer) {
      const discountPct = Math.round(((item.price - item.offer_price) / item.price) * 100);
      priceHtml = `
        <span class="item-price">₹${item.offer_price}</span>
        <span class="item-price-strike">₹${item.price}</span>
        <span class="item-discount-tag">${discountPct}% OFF</span>
      `;
    }

    const fallbackImg = "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=200&auto=format&fit=crop&q=80";

    card.innerHTML = `
      <div class="item-image-wrapper">
        <img class="item-image" src="${item.image_url || fallbackImg}" alt="${item.name}" loading="lazy" onerror="this.onerror=null;this.src='${fallbackImg}'" />
      </div>
      <div class="item-details">
        <div class="item-name">${item.name}</div>
        <div class="item-desc">${item.description || ""}</div>
        <div class="item-price-row">${priceHtml}</div>
      </div>
      <div class="item-action" id="action-${item.id}">
      </div>
    `;

    renderItemActionButton(card.querySelector(`#action-${item.id}`), item);
    return card;
  }

  function renderItemActionButton(actionContainer, item) {
    if (!actionContainer) return;
    actionContainer.innerHTML = "";

    if (!item.is_available) {
      const badge = document.createElement("span");
      badge.className = "badge-out-of-stock";
      badge.textContent = "Out of Stock";
      actionContainer.appendChild(badge);
      return;
    }

    if (!isSessionActive) {
      const lockBtn = document.createElement("button");
      lockBtn.className = "add-btn";
      lockBtn.style.background = "var(--color-strike)";
      lockBtn.style.cursor = "not-allowed";
      lockBtn.innerHTML = `<span>Closed</span> <span>🔒</span>`;
      lockBtn.addEventListener("click", () => {
        showToast("Table session is closed. Please scan QR at table.");
      });
      actionContainer.appendChild(lockBtn);
      return;
    }

    const cartEntry = cart[item.id];
    if (!cartEntry || cartEntry.quantity === 0) {
      const addBtn = document.createElement("button");
      addBtn.className = "add-btn";
      addBtn.innerHTML = `<span>Add</span> <span style="font-size: 1.1rem;">+</span>`;
      addBtn.addEventListener("click", () => {
        modifyCartQuantity(item, 1);
        showToast(`Added ${item.name}`);
      });
      actionContainer.appendChild(addBtn);
    } else {
      const ctrl = document.createElement("div");
      ctrl.className = "qty-control";
      ctrl.innerHTML = `
        <button class="qty-btn" aria-label="Decrease">－</button>
        <span class="qty-text">${cartEntry.quantity}</span>
        <button class="qty-btn" aria-label="Increase">+</button>
      `;

      const [decBtn, , incBtn] = ctrl.children;
      decBtn.addEventListener("click", () => modifyCartQuantity(item, -1));
      incBtn.addEventListener("click", () => modifyCartQuantity(item, 1));
      actionContainer.appendChild(ctrl);
    }
  }

  // 10. CART MANIPULATION
  function modifyCartQuantity(item, delta) {
    if (!isSessionActive) {
      showToast("Session expired or table closed. Please scan QR again.");
      return;
    }

    if (!cart[item.id]) {
      if (delta > 0) cart[item.id] = { item, quantity: delta };
    } else {
      cart[item.id].quantity += delta;
      if (cart[item.id].quantity <= 0) {
        delete cart[item.id];
      }
    }

    sessionStorage.setItem("cart_items", JSON.stringify(cart));
    updateCartUI();

    const actionEl = document.getElementById(`action-${item.id}`);
    if (actionEl) renderItemActionButton(actionEl, item);
  }

  function updateCartUI() {
    const entries = Object.values(cart);
    const count = entries.reduce((acc, curr) => acc + curr.quantity, 0);
    const total = entries.reduce((acc, curr) => {
      const price = curr.item.offer_price || curr.item.price;
      return acc + price * curr.quantity;
    }, 0);

    const cartFab = document.getElementById("cartFab");
    const fabCount = document.getElementById("cartFabCount");
    const fabTotal = document.getElementById("cartFabTotal");
    const billSubtotal = document.getElementById("billSubtotal");
    const billTotal = document.getElementById("billTotal");

    if (fabCount) fabCount.textContent = count;
    if (fabTotal) fabTotal.textContent = total.toFixed(0);
    if (billSubtotal) billSubtotal.textContent = total.toFixed(0);
    if (billTotal) billTotal.textContent = total.toFixed(0);

    if (cartFab) {
      if (count > 0 && isSessionActive) {
        cartFab.classList.remove("hidden");
      } else {
        cartFab.classList.add("hidden");
        closeCartDrawer();
      }
    }

    renderCartDrawerList();
  }

  function renderCartDrawerList() {
    const list = document.getElementById("cartItemsList");
    if (!list) return;
    list.innerHTML = "";

    const entries = Object.values(cart);
    if (entries.length === 0) {
      list.innerHTML = `<div style="text-align: center; color: var(--color-text-muted); padding: 20px;">Your cart is empty</div>`;
      return;
    }

    entries.forEach(({ item, quantity }) => {
      const price = item.offer_price || item.price;
      const row = document.createElement("div");
      row.className = "cart-item-row";
      row.innerHTML = `
        <div class="cart-item-info">
          <div class="cart-item-name">${item.name}</div>
          <div class="cart-item-unit-price">₹${price} each</div>
        </div>
        <div class="qty-control">
          <button class="qty-btn btn-dec">－</button>
          <span class="qty-text">${quantity}</span>
          <button class="qty-btn btn-inc">+</button>
        </div>
        <div class="cart-item-total">₹${(price * quantity).toFixed(0)}</div>
      `;

      row.querySelector(".btn-dec").addEventListener("click", () => modifyCartQuantity(item, -1));
      row.querySelector(".btn-inc").addEventListener("click", () => modifyCartQuantity(item, 1));
      list.appendChild(row);
    });
  }

  // 11. CART DRAWER TOGGLE
  const cartFab = document.getElementById("cartFab");
  const cartDrawer = document.getElementById("cartDrawer");
  const cartBackdrop = document.getElementById("cartBackdrop");
  const closeCartBtn = document.getElementById("closeCartBtn");

  function openCartDrawer() {
    if (cartDrawer) cartDrawer.classList.remove("hidden");
    if (cartBackdrop) cartBackdrop.classList.remove("hidden");
  }

  function closeCartDrawer() {
    if (cartDrawer) cartDrawer.classList.add("hidden");
    if (cartBackdrop) cartBackdrop.classList.add("hidden");
  }

  if (cartFab) cartFab.addEventListener("click", openCartDrawer);
  if (closeCartBtn) closeCartBtn.addEventListener("click", closeCartDrawer);
  if (cartBackdrop) cartBackdrop.addEventListener("click", closeCartDrawer);

  // 12. SEARCH INPUT EVENT
  const searchInput = document.getElementById("searchInput");
  if (searchInput) {
    searchInput.addEventListener("input", (e) => {
      searchQuery = e.target.value.trim().toLowerCase();
      renderMenu();
    });
  }

  // 13. PLACE ORDER (CALLS SECURE SERVER-SIDE RPC WITH SESSION TOKEN)
  const placeOrderBtn = document.getElementById("placeOrderBtn");
  if (placeOrderBtn) {
    placeOrderBtn.addEventListener("click", async () => {
      if (!isSessionActive) {
        showToast("Session expired or table closed. Please scan the QR again.");
        return;
      }

      const items = Object.values(cart).map(({ item, quantity }) => ({
        menu_item_id: item.id,
        quantity: quantity
      }));

      if (items.length === 0) {
        showToast("Please add items to your cart first.");
        return;
      }

      placeOrderBtn.disabled = true;
      placeOrderBtn.innerHTML = `<span>Placing order...</span> ⏳`;

      const notesInput = document.getElementById("orderNotesInput");
      const orderNotes = notesInput ? notesInput.value.trim() : "";

      try {
        let orderId = null;

        if (supabase) {
          // Ensure we have an active valid UUID session token
          if (!isValidUuid(sessionToken)) {
            await initTableSession();
          }

          const cleanSession = isValidUuid(sessionToken) ? sessionToken : null;
          const cleanQr = isValidUuid(qrToken) ? qrToken : null;

          const { data, error } = await supabase.rpc("place_order", {
            p_session_token: cleanSession,
            p_qr_token: cleanQr,
            p_items: items,
            p_notes: orderNotes || null
          });

          if (error) {
            if (error.message && error.message.toLowerCase().includes("session expired")) {
              isSessionActive = false;
              updateSessionStatusUI(false);
              throw new Error("Session expired or table closed. Please scan the QR again.");
            }
            throw error;
          }
          orderId = data;
        } else {
          await new Promise(r => setTimeout(r, 600));
          orderId = "demo-ord-" + Math.random().toString(36).substring(2, 9);
          const orderPayload = {
            id: orderId,
            short_id: orderId.substring(0, 8).toUpperCase(),
            status: "pending",
            notes: orderNotes || null,
            total_amount: Object.values(cart).reduce((s, e) => s + (e.item.offer_price || e.item.price) * e.quantity, 0),
            created_at: new Date().toISOString(),
            items: Object.values(cart).map(e => ({
              id: "item-" + Math.random().toString(36).substring(2, 7),
              name: e.item.name,
              quantity: e.quantity,
              price: e.item.offer_price || e.item.price,
              line_total: (e.item.offer_price || e.item.price) * e.quantity
            }))
          };
          sessionStorage.setItem(`demo_order_${orderId}`, JSON.stringify(orderPayload));
          localStorage.setItem(`demo_order_${orderId}`, JSON.stringify(orderPayload));
        }

        recordSessionOrderId(orderId);

        cart = {};
        sessionStorage.removeItem("cart_items");
        if (notesInput) notesInput.value = "";
        updateCartUI();
        closeCartDrawer();

        showToast("Order placed successfully! Added to My Orders.");

        await loadSessionOrders();
        setTimeout(() => {
          openMyOrdersDrawer();
        }, 400);
      } catch (err) {
        console.error("Order placement error:", err);
        showToast(err.message || "Order could not be placed. Please try again.");
      } finally {
        if (isSessionActive) {
          placeOrderBtn.disabled = false;
          placeOrderBtn.innerHTML = `<span>Send to Kitchen</span> <span>🚀</span>`;
        }
      }
    });
  }

  // 14. SESSION ORDER TRACKING & "MY ORDERS" FEATURE
  function recordSessionOrderId(orderId) {
    let ids = [];
    try {
      const stored = sessionStorage.getItem("my_session_order_ids");
      if (stored) ids = JSON.parse(stored);
    } catch (_) {}
    if (!ids.includes(orderId)) ids.unshift(orderId);
    sessionStorage.setItem("my_session_order_ids", JSON.stringify(ids));
    sessionStorage.setItem("last_order_id", orderId);
  }

  function getLocalSessionOrderIds() {
    try {
      const stored = sessionStorage.getItem("my_session_order_ids");
      return stored ? JSON.parse(stored) : [];
    } catch (_) {
      return [];
    }
  }

  async function loadSessionOrders() {
    if (supabase && sessionToken) {
      try {
        const { data, error } = await supabase.rpc("get_session_orders", {
          p_session_token: sessionToken
        });

        if (!error && data && Array.isArray(data)) {
          sessionOrders = data;
          updateMyOrdersBadge(sessionOrders.length);
          renderMyOrdersList();
          return;
        }
      } catch (err) {
        console.warn("get_session_orders RPC failed, falling back to storage:", err);
      }
    }

    const ids = getLocalSessionOrderIds();
    const loaded = [];
    for (const id of ids) {
      const saved = sessionStorage.getItem(`demo_order_${id}`) || localStorage.getItem(`demo_order_${id}`);
      if (saved) {
        try {
          loaded.push(JSON.parse(saved));
        } catch (_) {}
      }
    }
    sessionOrders = loaded;
    updateMyOrdersBadge(sessionOrders.length);
    renderMyOrdersList();
  }

  function updateMyOrdersBadge(count) {
    const badge = document.getElementById("myOrdersBadge");
    if (!badge) return;
    if (count > 0) {
      badge.textContent = count;
      badge.classList.remove("hidden");
    } else {
      badge.classList.add("hidden");
    }
  }

  function renderMyOrdersList() {
    const container = document.getElementById("myOrdersList");
    if (!container) return;

    if (sessionOrders.length === 0) {
      container.innerHTML = `
        <div style="text-align: center; padding: 40px 20px; color: var(--color-text-secondary);">
          <div style="font-size: 2.2rem; margin-bottom: 10px;">📋</div>
          <p style="font-weight: 700; font-size: 1.05rem;">No orders yet</p>
          <p style="font-size: 0.85rem; color: var(--color-text-muted); margin-top: 4px;">Items you order at Table #${currentTableNumber} will show here.</p>
        </div>
      `;
      return;
    }

    container.innerHTML = "";

    sessionOrders.forEach(ord => {
      const card = document.createElement("div");
      card.className = "session-order-card";
      const shortId = ord.short_id || (ord.id ? ord.id.substring(0, 8).toUpperCase() : "ORD");
      const normStatus = (ord.status || "pending").toLowerCase();
      const statusClass = `status-pill-${normStatus}`;

      const placedDate = ord.created_at ? new Date(ord.created_at) : new Date();
      const timeStr = placedDate.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

      const itemsHtml = (ord.items || []).map(it => `
        <div class="session-order-item-row">
          <span>${it.quantity} × ${it.name}</span>
          <span>₹${(it.line_total || it.price * it.quantity).toFixed(0)}</span>
        </div>
      `).join("");

      card.innerHTML = `
        <div class="session-order-header">
          <div>
            <span class="session-order-id">#${shortId}</span>
            <span class="session-order-time">• ${timeStr}</span>
          </div>
          <span class="order-status-pill ${statusClass}">${normStatus}</span>
        </div>
        <div class="session-order-items">
          ${itemsHtml || '<div style="color: var(--color-text-muted);">Custom Kitchen Order</div>'}
        </div>
        <div class="session-order-footer">
          <div>
            <span style="font-size: 0.8rem; color: var(--color-text-secondary);">Total</span>
            <div class="session-order-total">₹${parseFloat(ord.total_amount || 0).toFixed(0)}</div>
          </div>
          <button class="view-receipt-btn" data-order-id="${ord.id}">View Receipt</button>
        </div>
      `;

      card.querySelector(".view-receipt-btn").addEventListener("click", () => {
        openReceiptModal(ord);
      });

      container.appendChild(card);
    });
  }

  // My Orders Modal Toggle
  const myOrdersBtn = document.getElementById("myOrdersBtn");
  const myOrdersDrawer = document.getElementById("myOrdersDrawer");
  const myOrdersBackdrop = document.getElementById("myOrdersBackdrop");
  const closeMyOrdersBtn = document.getElementById("closeMyOrdersBtn");

  function openMyOrdersDrawer() {
    loadSessionOrders();
    if (myOrdersDrawer) myOrdersDrawer.classList.remove("hidden");
    if (myOrdersBackdrop) myOrdersBackdrop.classList.remove("hidden");
  }

  function closeMyOrdersDrawer() {
    if (myOrdersDrawer) myOrdersDrawer.classList.add("hidden");
    if (myOrdersBackdrop) myOrdersBackdrop.classList.add("hidden");
  }

  if (myOrdersBtn) myOrdersBtn.addEventListener("click", openMyOrdersDrawer);
  if (closeMyOrdersBtn) closeMyOrdersBtn.addEventListener("click", closeMyOrdersDrawer);
  if (myOrdersBackdrop) myOrdersBackdrop.addEventListener("click", closeMyOrdersDrawer);

  // 15. CUSTOMER BILL / EXPENSE SUMMARY RECEIPT & PRINT
  const receiptModal = document.getElementById("receiptModal");
  const receiptModalBackdrop = document.getElementById("receiptModalBackdrop");
  const closeReceiptBtn = document.getElementById("closeReceiptBtn");
  const printReceiptBtn = document.getElementById("printReceiptBtn");

  function openReceiptModal(order) {
    const printable = document.getElementById("printableReceipt");
    if (!printable) return;

    const shortId = order.short_id || (order.id ? order.id.substring(0, 8).toUpperCase() : "ORD");
    const date = order.created_at ? new Date(order.created_at) : new Date();
    const formattedDate = date.toLocaleDateString([], { month: "short", day: "numeric", year: "numeric" });
    const formattedTime = date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    const normStatus = (order.status || "pending").toLowerCase();
    const total = parseFloat(order.total_amount || 0).toFixed(0);

    const rowsHtml = (order.items || []).map(it => `
      <tr>
        <td style="padding: 6px 0;">${it.name}</td>
        <td style="text-align: center; padding: 6px 0;">${it.quantity}</td>
        <td class="text-right" style="padding: 6px 0;">₹${parseFloat(it.price).toFixed(0)}</td>
        <td class="text-right" style="padding: 6px 0; font-weight: 700;">₹${parseFloat(it.line_total || it.price * it.quantity).toFixed(0)}</td>
      </tr>
    `).join("");

    printable.innerHTML = `
      <div class="receipt-header">
        <div class="receipt-cafe-name">${currentCafeName}</div>
        <div class="receipt-subtitle">Order Summary & Customer Receipt</div>
        <div style="font-size: 0.78rem; color: var(--color-text-muted); margin-top: 4px;">Table #${currentTableNumber} • Order #${shortId}</div>
      </div>

      <div class="receipt-meta">
        <span>Date: ${formattedDate}</span>
        <span>Time: ${formattedTime}</span>
      </div>

      <div class="receipt-divider"></div>

      <table class="receipt-items-table">
        <thead>
          <tr>
            <th>Item</th>
            <th style="text-align: center;">Qty</th>
            <th class="text-right">Price</th>
            <th class="text-right">Total</th>
          </tr>
        </thead>
        <tbody>
          ${rowsHtml || '<tr><td colspan="4" style="text-align: center; padding: 8px;">Order Details</td></tr>'}
        </tbody>
      </table>

      <div class="receipt-divider"></div>

      <div class="receipt-total-row">
        <span>Total Amount</span>
        <span>₹${total}</span>
      </div>

      <div class="receipt-status-badge">
        <span class="order-status-pill status-pill-${normStatus}">${normStatus}</span>
      </div>

      <div class="receipt-footer-thanks">
        <p style="font-weight: 700;">Thank you for dining with us!</p>
        <p style="font-size: 0.75rem; color: var(--color-text-muted); margin-top: 2px;">This document serves as an informal dining summary / customer receipt.</p>
      </div>
    `;

    if (receiptModal) receiptModal.classList.remove("hidden");
    if (receiptModalBackdrop) receiptModalBackdrop.classList.remove("hidden");
  }

  function closeReceiptModal() {
    if (receiptModal) receiptModal.classList.add("hidden");
    if (receiptModalBackdrop) receiptModalBackdrop.classList.add("hidden");
  }

  if (closeReceiptBtn) closeReceiptBtn.addEventListener("click", closeReceiptModal);
  if (receiptModalBackdrop) receiptModalBackdrop.addEventListener("click", closeReceiptModal);

  if (printReceiptBtn) {
    printReceiptBtn.addEventListener("click", () => {
      window.print();
    });
  }

  // 16. REALTIME SUBSCRIPTION FOR ORDER UPDATES
  function setupRealtimeOrders() {
    if (!supabase || !sessionId) return;

    try {
      realtimeOrdersChannel = supabase
        .channel(`cust_orders_${sessionId}`)
        .on(
          "postgres_changes",
          {
            event: "UPDATE",
            schema: "public",
            table: "orders",
            filter: `session_id=eq.${sessionId}`
          },
          (payload) => {
            console.log("Realtime order status changed:", payload.new);
            loadSessionOrders();
            showToast(`Order status updated: ${(payload.new.status || "").toUpperCase()}`);
          }
        )
        .subscribe();
    } catch (e) {
      console.warn("Realtime order subscription failed:", e);
    }

    // 8-second polling fallback
    setInterval(() => {
      if (sessionOrders.length > 0) {
        loadSessionOrders();
      }
    }, 8000);
  }

  // 17. INITIALIZE APP
  async function init() {
    await initTableSession();
    await loadMenu();
    await loadSessionOrders();
    setupRealtimeOrders();
  }

  init();
})();
