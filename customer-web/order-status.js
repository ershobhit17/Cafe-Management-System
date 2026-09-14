// ==============================================================================
// Customer Ordering Web App - Live Order Status Logic (order-status.js)
// ==============================================================================

(function () {
  const urlParams = new URLSearchParams(window.location.search);
  const orderId = urlParams.get("order") || sessionStorage.getItem("last_order_id");
  let cafeId = urlParams.get("cafe") || sessionStorage.getItem("cafe_id");
  let qrToken = urlParams.get("table") || sessionStorage.getItem("qr_token");
  let sessionToken = urlParams.get("session") || sessionStorage.getItem("session_token") || localStorage.getItem("session_token");

  let supabase = null;
  let realtimeChannel = null;
  let currentCafeName = sessionStorage.getItem("cafe_name") || "Snap Serve";

  // 1. BACK / ORDER MORE LINKAGE
  function getBackUrl() {
    const params = new URLSearchParams();
    if (cafeId && cafeId !== CONFIG.DEMO_MODE.cafe_id) params.set("cafe", cafeId);
    if (qrToken && qrToken !== CONFIG.DEMO_MODE.qr_token) params.set("table", qrToken);
    if (sessionToken) params.set("session", sessionToken);
    const qs = params.toString();
    return qs ? `index.html?${qs}` : "index.html";
  }

  function updateBackLinks() {
    const backUrl = getBackUrl();
    const backLink = document.getElementById("backToMenuLink");
    const orderMoreBtn = document.getElementById("orderMoreBtn");
    if (backLink) backLink.href = backUrl;
    if (orderMoreBtn) {
      orderMoreBtn.onclick = () => {
        window.location.href = backUrl;
      };
    }
  }
  updateBackLinks();

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

  // Print button
  const printBtn = document.getElementById("printStatusReceiptBtn");
  if (printBtn) {
    printBtn.addEventListener("click", () => {
      window.print();
    });
  }

  // 3. UI STATUS UPDATER
  const STATUS_CONFIGS = {
    placed: {
      stepIndex: 1,
      progressWidth: "10%",
      emoji: "⏳",
      title: "Order Placed!",
      message: "Your order ticket has arrived in the kitchen. Preparing shortly."
    },
    pending: {
      stepIndex: 1,
      progressWidth: "10%",
      emoji: "⏳",
      title: "Order Received!",
      message: "Your order ticket has arrived in the kitchen. Preparing shortly."
    },
    preparing: {
      stepIndex: 2,
      progressWidth: "35%",
      emoji: "👨‍🍳🔥",
      title: "Kitchen is Preparing!",
      message: "The barista and chef are crafting your food and beverages."
    },
    ready: {
      stepIndex: 3,
      progressWidth: "60%",
      emoji: "🔔🥘",
      title: "Order is Ready!",
      message: "Your order is prepared and on its way to your table!"
    },
    served: {
      stepIndex: 4,
      progressWidth: "82%",
      emoji: "🍽️✨",
      title: "Order is Served!",
      message: "Enjoy your fresh meal! Please ask our staff if you need anything."
    },
    completed: {
      stepIndex: 4,
      progressWidth: "82%",
      emoji: "🍽️✨",
      title: "Order is Served!",
      message: "Enjoy your fresh meal! Please ask our staff if you need anything."
    },
    paid: {
      stepIndex: 5,
      progressWidth: "100%",
      emoji: "✅",
      title: "Order Completed & Paid",
      message: "Thank you for dining with us! See you soon."
    },
    cancelled: {
      stepIndex: 1,
      progressWidth: "0%",
      emoji: "❌",
      title: "Order Cancelled",
      message: "This order was cancelled by the staff."
    }
  };

  function updateStatusUI(statusName, totalAmount, tableNum, createdAt, items) {
    const normStatus = (statusName || "pending").toLowerCase();
    const config = STATUS_CONFIGS[normStatus] || STATUS_CONFIGS.pending;

    const emojiEl = document.getElementById("statusEmoji");
    const titleEl = document.getElementById("statusTitle");
    const msgEl = document.getElementById("statusMessage");
    const progressEl = document.getElementById("stepperProgress");

    if (emojiEl) emojiEl.textContent = config.emoji;
    if (titleEl) titleEl.textContent = config.title;
    if (msgEl) msgEl.textContent = config.message;
    if (progressEl) progressEl.style.width = config.progressWidth;

    const steps = ["pending", "preparing", "ready", "served", "paid"];
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

    const receiptOrderEl = document.getElementById("receiptOrderId");
    const receiptTableEl = document.getElementById("receiptTableNum");
    const orderTableBadge = document.getElementById("orderTableBadge");
    const receiptTotalEl = document.getElementById("receiptTotal");
    const receiptTimeEl = document.getElementById("receiptTime");
    const cafeBrandEl = document.getElementById("statusCafeBrandName");
    const headerCafeBrandEl = document.getElementById("receiptBrandNameHeader");

    if (cafeBrandEl) cafeBrandEl.textContent = currentCafeName;
    if (headerCafeBrandEl) headerCafeBrandEl.textContent = currentCafeName;
    document.title = `Live Order Status - ${currentCafeName}`;

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

    if (items && Array.isArray(items) && items.length > 0) {
      const itemsContainer = document.getElementById("statusReceiptItems");
      if (itemsContainer) {
        itemsContainer.innerHTML = `
          <table class="receipt-items-table" style="width: 100%; border-collapse: collapse; margin: 8px 0;">
            ${items.map(it => `
              <tr>
                <td style="padding: 4px 0;">${it.quantity} × ${it.name}</td>
                <td style="text-align: right; padding: 4px 0; font-weight: 600;">₹${parseFloat(it.line_total || it.price * it.quantity).toFixed(0)}</td>
              </tr>
            `).join("")}
          </table>
        `;
      }
    }
  }

  // 4. SUPABASE LIVE SUBSCRIPTION
  async function initTracking() {
    if (isSupabaseConfigured() && window.supabase) {
      try {
        supabase = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);

        // Fetch cafe name if not known
        if (cafeId) {
          const { data: cafeData } = await supabase.from("cafes").select("name").eq("id", cafeId).maybeSingle();
          if (cafeData && cafeData.name) {
            currentCafeName = cafeData.name;
          }
        }

        // Fetch order details via get_order_status RPC
        if (orderId) {
          const { data, error } = await supabase.rpc("get_order_status", { p_order_id: orderId });
          if (data && data.length > 0) {
            const row = data[0];
            if (row.cafe_name) {
              currentCafeName = row.cafe_name;
              sessionStorage.setItem("cafe_name", currentCafeName);
            }
            if (row.cafe_id) {
              cafeId = row.cafe_id;
              sessionStorage.setItem("cafe_id", cafeId);
              updateBackLinks();
            }
            updateStatusUI(row.status, row.total_amount, row.table_number, row.created_at, row.items);
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
              async (payload) => {
                const { data: pollData } = await supabase.rpc("get_order_status", { p_order_id: orderId });
                if (pollData && pollData.length > 0) {
                  const row = pollData[0];
                  updateStatusUI(row.status, row.total_amount, row.table_number, row.created_at, row.items);
                } else if (payload.new && payload.new.status) {
                  updateStatusUI(payload.new.status, payload.new.total_amount);
                }
              }
            )
            .subscribe();

          // 6-second polling fallback
          setInterval(async () => {
            const { data: pollData } = await supabase.rpc("get_order_status", { p_order_id: orderId });
            if (pollData && pollData.length > 0) {
              const row = pollData[0];
              updateStatusUI(row.status, row.total_amount, row.table_number, row.created_at, row.items);
            }
          }, 6000);
        } else if (cafeId) {
          const { data: cafeData } = await supabase.from("cafes").select("name").eq("id", cafeId).maybeSingle();
          if (cafeData && cafeData.name) {
            currentCafeName = cafeData.name;
            sessionStorage.setItem("cafe_name", currentCafeName);
            updateStatusUI("pending", 0, null, new Date(), []);
          }
        }

        return;
      } catch (err) {
        console.warn("Supabase tracking failed, falling back to demo progression:", err);
      }
    }

    // Demo Mode Progression Simulation
    let mockOrder = null;
    try {
      const saved = sessionStorage.getItem(`demo_order_${orderId}`) || localStorage.getItem(`demo_order_${orderId}`);
      if (saved) mockOrder = JSON.parse(saved);
    } catch (e) {}

    const total = mockOrder ? mockOrder.total_amount || mockOrder.total : 459;
    const initialStatus = mockOrder ? mockOrder.status : "pending";
    const items = mockOrder ? mockOrder.items : [];
    updateStatusUI(initialStatus, total, CONFIG.DEMO_MODE.table_number, new Date(), items);

    window.addEventListener("storage", (e) => {
      if (e.key === `demo_order_${orderId}` && e.newValue) {
        try {
          const updated = JSON.parse(e.newValue);
          updateStatusUI(updated.status, updated.total_amount || updated.total, CONFIG.DEMO_MODE.table_number, updated.created_at || new Date(), updated.items);
        } catch (err) {}
      }
    });
  }

  initTracking();
})();
