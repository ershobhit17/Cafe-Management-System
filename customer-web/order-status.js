// ==============================================================================
// Customer Ordering Web App - Live Order Status Logic (order-status.js)
// ==============================================================================

(function () {
  const urlParams = new URLSearchParams(window.location.search);
  const orderId = urlParams.get("order") || sessionStorage.getItem("last_order_id");
  const cafeId = urlParams.get("cafe") || sessionStorage.getItem("cafe_id") || CONFIG.DEMO_MODE.cafe_id;
  const qrToken = urlParams.get("table") || sessionStorage.getItem("qr_token") || CONFIG.DEMO_MODE.qr_token;

  let supabase = null;
  let realtimeChannel = null;

  // 1. BACK / ORDER MORE LINKAGE
  const backUrl = `index.html?cafe=${encodeURIComponent(cafeId)}&table=${encodeURIComponent(qrToken)}`;
  const backLink = document.getElementById("backToMenuLink");
  const orderMoreBtn = document.getElementById("orderMoreBtn");
  if (backLink) backLink.href = backUrl;
  if (orderMoreBtn) {
    orderMoreBtn.addEventListener("click", () => {
      window.location.href = backUrl;
    });
  }

  // 2. THEME SYNC
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

  // 3. UI STATUS UPDATER
  const STATUS_CONFIGS = {
    pending: {
      stepIndex: 1,
      progressWidth: "12%",
      emoji: "⏳",
      title: "Order Received!",
      message: "Your order ticket has arrived in the kitchen. Preparing shortly."
    },
    preparing: {
      stepIndex: 2,
      progressWidth: "40%",
      emoji: "👨‍🍳",
      title: "Kitchen is Preparing!",
      message: "The barista and chef are crafting your food and beverages."
    },
    served: {
      stepIndex: 3,
      progressWidth: "72%",
      emoji: "🍽️",
      title: "Order is Served!",
      message: "Enjoy your fresh meal! Please ask our staff if you need anything."
    },
    paid: {
      stepIndex: 4,
      progressWidth: "100%",
      emoji: "✨",
      title: "Order Completed & Paid",
      message: "Thank you for dining with us at Aroma Artisan Cafe! See you soon."
    }
  };

  function updateStatusUI(statusName, totalAmount, tableNum, createdAt) {
    const normStatus = (statusName || "pending").toLowerCase();
    const config = STATUS_CONFIGS[normStatus] || STATUS_CONFIGS.pending;

    // Elements
    const emojiEl = document.getElementById("statusEmoji");
    const titleEl = document.getElementById("statusTitle");
    const msgEl = document.getElementById("statusMessage");
    const progressEl = document.getElementById("stepperProgress");

    if (emojiEl) emojiEl.textContent = config.emoji;
    if (titleEl) titleEl.textContent = config.title;
    if (msgEl) msgEl.textContent = config.message;
    if (progressEl) progressEl.style.width = config.progressWidth;

    // Update Steps
    const steps = ["pending", "preparing", "served", "paid"];
    steps.forEach((s, idx) => {
      const stepEl = document.getElementById(`step-${s}`);
      if (!stepEl) return;
      stepEl.classList.remove("active", "completed");

      if (idx + 1 < config.stepIndex) {
        stepEl.classList.add("completed");
      } else if (idx + 1 === config.stepIndex) {
        stepEl.classList.add("active");
      }
    });

    // Update Receipt
    const receiptOrderEl = document.getElementById("receiptOrderId");
    const receiptTableEl = document.getElementById("receiptTableNum");
    const orderTableBadge = document.getElementById("orderTableBadge");
    const receiptTotalEl = document.getElementById("receiptTotal");
    const receiptTimeEl = document.getElementById("receiptTime");

    if (receiptOrderEl && orderId) {
      receiptOrderEl.textContent = "#" + (orderId.length > 12 ? orderId.substring(0, 8).toUpperCase() : orderId);
    }
    if (receiptTableEl && tableNum) {
      receiptTableEl.textContent = `Table #${tableNum}`;
    }
    if (orderTableBadge && tableNum) {
      orderTableBadge.textContent = `Table #${tableNum}`;
    }
    if (receiptTotalEl && totalAmount !== undefined) {
      receiptTotalEl.textContent = `₹${parseFloat(totalAmount).toFixed(0)}`;
    }
    if (receiptTimeEl && createdAt) {
      const date = new Date(createdAt);
      receiptTimeEl.textContent = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }
  }

  // 4. SUPABASE LIVE SUBSCRIPTION OR DEMO SIMULATION
  async function initTracking() {
    if (!orderId) {
      updateStatusUI("pending", 0, CONFIG.DEMO_MODE.table_number, new Date());
      return;
    }

    if (isSupabaseConfigured() && window.supabase) {
      try {
        supabase = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);

        // Fetch initial status via secure get_order_status RPC
        const { data, error } = await supabase.rpc("get_order_status", { p_order_id: orderId });
        if (data && data.length > 0) {
          const row = data[0];
          updateStatusUI(row.status, row.total_amount, row.table_number, row.created_at);
        }

        // Realtime Subscription
        realtimeChannel = supabase
          .channel(`order_tracking_${orderId}`)
          .on(
            "postgres_changes",
            {
              event: "UPDATE",
              schema: "public",
              table: "orders",
              filter: `id=eq.${orderId}`
            },
            (payload) => {
              console.log("Realtime order update received:", payload.new);
              if (payload.new && payload.new.status) {
                updateStatusUI(payload.new.status, payload.new.total_amount);
              }
            }
          )
          .subscribe();

        // Polling fallback every 6 seconds
        setInterval(async () => {
          const { data: pollData } = await supabase.rpc("get_order_status", { p_order_id: orderId });
          if (pollData && pollData.length > 0) {
            const row = pollData[0];
            updateStatusUI(row.status, row.total_amount, row.table_number, row.created_at);
          }
        }, 6000);

        return;
      } catch (err) {
        console.warn("Supabase tracking failed, falling back to demo progression:", err);
      }
    }

    // Demo Mode Progression Simulation
    let mockOrder = null;
    try {
      const saved = sessionStorage.getItem(`demo_order_${orderId}`);
      if (saved) mockOrder = JSON.parse(saved);
    } catch (e) {}

    const total = mockOrder ? mockOrder.total : 459;
    const initialStatus = mockOrder ? mockOrder.status : "pending";
    updateStatusUI(initialStatus, total, CONFIG.DEMO_MODE.table_number, new Date());

    // In Demo Mode: Do NOT auto-advance! The order stays in its genuine status.
    // Listen for storage events in case status is updated from another tab / owner console
    window.addEventListener("storage", (e) => {
      if (e.key === `demo_order_${orderId}` && e.newValue) {
        try {
          const updated = JSON.parse(e.newValue);
          updateStatusUI(updated.status, updated.total, CONFIG.DEMO_MODE.table_number, updated.created_at || new Date());
        } catch (err) {}
      }
    });
  }

  initTracking();
})();
