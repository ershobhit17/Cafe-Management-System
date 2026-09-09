// ==============================================================================
// Customer Ordering Web App - Main Logic (app.js)
// ==============================================================================

(function () {
  // 1. STATE & CONTEXT
  let allMenuItems = [];
  let activeCategory = "ALL";
  let searchQuery = "";
  let cart = {}; // { [item_id]: { item, quantity } }
  let supabase = null;

  // 2. READ & PERSIST SESSION CONTEXT (URL PARAMS)
  const urlParams = new URLSearchParams(window.location.search);
  let cafeId = urlParams.get("cafe") || sessionStorage.getItem("cafe_id");
  let qrToken = urlParams.get("table") || sessionStorage.getItem("qr_token");

  // Fallback to Demo Mode defaults if accessed without parameters
  if (!cafeId || !qrToken) {
    cafeId = CONFIG.DEMO_MODE.cafe_id;
    qrToken = CONFIG.DEMO_MODE.qr_token;
  }
  sessionStorage.setItem("cafe_id", cafeId);
  sessionStorage.setItem("qr_token", qrToken);

  // Restore existing cart from session if present
  try {
    const savedCart = sessionStorage.getItem("cart_items");
    if (savedCart) cart = JSON.parse(savedCart);
  } catch (e) {
    cart = {};
  }

  // 3. THEME TOGGLE
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

  // 4. SUPABASE INITIALIZATION
  if (isSupabaseConfigured() && window.supabase) {
    try {
      supabase = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);
      console.log("Supabase client initialized successfully.");
    } catch (err) {
      console.warn("Supabase init error, falling back to Demo Mode:", err);
    }
  }

  // 5. TOAST NOTIFICATIONS
  function showToast(message) {
    const toast = document.getElementById("toast");
    if (!toast) return;
    toast.textContent = message;
    toast.classList.remove("hidden");
    clearTimeout(toast._timeout);
    toast._timeout = setTimeout(() => {
      toast.classList.add("hidden");
    }, 2400);
  }

  // 6. LOAD MENU & TABLE DETAILS
  async function loadData() {
    // Resolve Table Number & Cafe Name (Multi-Tenant Isolation)
    if (supabase) {
      try {
        const { data: tableData } = await supabase
          .from("tables")
          .select("table_number, cafe_id, cafes(name)")
          .eq("qr_token", qrToken)
          .maybeSingle();

        if (tableData) {
          updateTableBadge(tableData.table_number);
          if (tableData.cafe_id) {
            cafeId = tableData.cafe_id;
            sessionStorage.setItem("cafe_id", cafeId);
          }
          if (tableData.cafes && tableData.cafes.name) {
            const brandEl = document.getElementById("cafeBrandName");
            if (brandEl) brandEl.textContent = tableData.cafes.name;
            document.title = `${tableData.cafes.name} - Menu & Ordering`;
          }
        } else {
          updateTableBadge(CONFIG.DEMO_MODE.table_number);
        }

        // Fetch Menu Items strictly for this cafe
        const { data: menuData, error: menuErr } = await supabase
          .from("menu_items")
          .select("*")
          .eq("cafe_id", cafeId)
          .order("category");

        if (!menuErr && menuData && menuData.length > 0) {
          allMenuItems = menuData;
        } else {
          allMenuItems = CONFIG.DEMO_MODE.items;
        }
      } catch (err) {
        console.warn("Error fetching Supabase data, using demo data:", err);
        allMenuItems = CONFIG.DEMO_MODE.items;
        updateTableBadge(CONFIG.DEMO_MODE.table_number);
      }
    } else {
      // Demo Mode
      allMenuItems = CONFIG.DEMO_MODE.items;
      updateTableBadge(CONFIG.DEMO_MODE.table_number);
    }

    renderCategoryPills();
    renderMenu();
    updateCartUI();
  }

  function updateTableBadge(tableNum) {
    const badge = document.getElementById("tableBadge");
    const drawerSub = document.getElementById("cartDrawerSubtitle");
    if (badge) badge.textContent = `Table #${tableNum}`;
    if (drawerSub) drawerSub.textContent = `Ordering for Table #${tableNum}`;
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

    // Filter items
    let filtered = allMenuItems.filter(item => {
      const matchCat = activeCategory === "ALL" || (item.category || "Other") === activeCategory;
      const matchSearch =
        searchQuery === "" ||
        item.name.toLowerCase().includes(searchQuery) ||
        (item.description && item.description.toLowerCase().includes(searchQuery));
      return matchCat && matchSearch;
    });

    if (filtered.length === 0) {
      container.innerHTML = `
        <div style="text-align: center; padding: 40px 20px; color: var(--color-text-secondary);">
          <div style="font-size: 2.2rem; margin-bottom: 8px;">🍽️</div>
          <p style="font-weight: 600;">No items found matching your search</p>
          <p style="font-size: 0.85rem; color: var(--color-text-muted);">Try a different keyword or category</p>
        </div>
      `;
      return;
    }

    // Group by category if "ALL" is selected
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
        <!-- Dynamic Add button or Counter injected below -->
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
      // Show +/- control
      const ctrl = document.createElement("div");
      ctrl.className = "qty-control";
      ctrl.innerHTML = `
        <button class="qty-btn" aria-label="Decrease">−</button>
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

    // Update the button on the card if present
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
      if (count > 0) {
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
          <button class="qty-btn btn-dec">−</button>
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

  // 13. PLACE ORDER (CALLS SECURE SERVER-SIDE RPC)
  const placeOrderBtn = document.getElementById("placeOrderBtn");
  if (placeOrderBtn) {
    placeOrderBtn.addEventListener("click", async () => {
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

      try {
        let orderId = null;

        if (supabase) {
          // Call tamper-proof Postgres RPC
          // Server performs price lookup and computing, client only sends item IDs & quantities
          const { data, error } = await supabase.rpc("place_order", {
            p_qr_token: qrToken,
            p_items: items
          });

          if (error) throw error;
          orderId = data;
        } else {
          // Demo fallback order simulation
          await new Promise(r => setTimeout(r, 600));
          orderId = "demo-ord-" + Math.random().toString(36).substring(2, 9);
          // Store mock order state in both sessionStorage & localStorage
          const orderPayload = JSON.stringify({
            id: orderId,
            status: "pending",
            total: Object.values(cart).reduce((s, e) => s + (e.item.offer_price || e.item.price) * e.quantity, 0),
            items: Object.values(cart).map(e => ({ name: e.item.name, quantity: e.quantity, price: e.item.offer_price || e.item.price })),
            created_at: new Date().toISOString()
          });
          sessionStorage.setItem(`demo_order_${orderId}`, orderPayload);
          localStorage.setItem(`demo_order_${orderId}`, orderPayload);
        }

        // Clear local cart
        cart = {};
        sessionStorage.removeItem("cart_items");
        updateCartUI();
        closeCartDrawer();

        showToast("Order placed successfully! Redirecting...");
        setTimeout(() => {
          window.location.href = `order-status.html?order=${orderId}&cafe=${cafeId}&table=${qrToken}`;
        }, 800);
      } catch (err) {
        console.error("Order error:", err);
        showToast("Order failed: " + (err.message || "Please check connection"));
        placeOrderBtn.disabled = false;
        placeOrderBtn.innerHTML = `<span>Send to Kitchen</span> <span>🚀</span>`;
      }
    });
  }

  // 14. INITIALIZE
  loadData();
})();
