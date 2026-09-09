// ==============================================================================
// Customer Web App Configuration
// ==============================================================================

const CONFIG = {
  // Replace these with your Supabase Project settings (Settings > API)
  SUPABASE_URL: "https://vmhplagbwottgsdpzsxp.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtaHBsYWdid290dGdzZHB6c3hwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg5NDk3NTEsImV4cCI6MjEwNDUyNTc1MX0.Vkik8EA0s-lpcth1NhsyH10Im8OJ19BiC1ev7u9JkQo",

  // Demo Fallback Data: Enables zero-friction local testing before cloud connection
  DEMO_MODE: {
    cafe_id: "a0000000-0000-0000-0000-000000000001",
    cafe_name: "Aroma Artisan Cafe",
    table_number: 3,
    qr_token: "11111111-1111-1111-1111-111111111103",
    items: [
      {
        id: "b0000000-0000-0000-0000-000000000001",
        name: "Caramel Macchiato",
        category: "Hot Beverages",
        price: 240,
        offer_price: 199,
        description: "Rich espresso with steamed milk and vanilla-caramel drizzle.",
        image_url: "https://images.unsplash.com/photo-1485808191679-5f86510681a2?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000002",
        name: "Hazelnut Cappuccino",
        category: "Hot Beverages",
        price: 220,
        offer_price: null,
        description: "Double shot espresso topped with dense micro-foam and hazelnut.",
        image_url: "https://images.unsplash.com/photo-1572442388796-11668a67e53d?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000003",
        name: "Belgian Hot Chocolate",
        category: "Hot Beverages",
        price: 260,
        offer_price: 220,
        description: "Pure melted dark chocolate blended with velvety whole milk.",
        image_url: "https://images.unsplash.com/photo-1542990253-0d0f5be5f0ed?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000004",
        name: "Vanilla Sweet Cream Cold Brew",
        category: "Cold Brews",
        price: 280,
        offer_price: 249,
        description: "Steeped for 18 hours, infused with custom sweet cream float.",
        image_url: "https://images.unsplash.com/photo-1517701550927-30cf4ba1dba5?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000005",
        name: "Passion Fruit Iced Tea",
        category: "Cold Brews",
        price: 190,
        offer_price: null,
        description: "Refreshing black tea with fresh passion fruit pulp and mint leaves.",
        image_url: "https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000006",
        name: "Classic Mango Frappe",
        category: "Cold Brews",
        price: 250,
        offer_price: null,
        description: "Blended chilled milk, fresh Alphonso mangoes and whipped cream.",
        image_url: "https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=400&auto=format&fit=crop&q=80",
        is_available: false
      },
      {
        id: "b0000000-0000-0000-0000-000000000007",
        name: "Pesto Grilled Cheese Sourdough",
        category: "Artisanal Bites",
        price: 320,
        offer_price: 280,
        description: "Aged cheddar, mozzarella, sun-dried tomatoes & basil pesto on toasted sourdough.",
        image_url: "https://images.unsplash.com/photo-1528735602780-2552fd46c7af?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000008",
        name: "Crispy Truffle Fries",
        category: "Artisanal Bites",
        price: 230,
        offer_price: 199,
        description: "Golden skin-on fries tossed in white truffle oil, parmesan & fresh chives.",
        image_url: "https://images.unsplash.com/photo-1576107232684-1279f3908594?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000010",
        name: "Wild Mushroom Penne Alfredo",
        category: "Main Course",
        price: 390,
        offer_price: null,
        description: "Sautéed cremini & shiitake mushrooms in garlic-parmesan cream sauce.",
        image_url: "https://images.unsplash.com/photo-1621996346565-e3d5d62817d2?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000011",
        name: "Artisan Margherita Pizza",
        category: "Main Course",
        price: 440,
        offer_price: 399,
        description: "San Marzano tomato base, fresh buffalo mozzarella, olive oil & basil leaves.",
        image_url: "https://images.unsplash.com/photo-1604382355076-af4b0eb60143?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000014",
        name: "New York Cheesecake",
        category: "Desserts",
        price: 270,
        offer_price: 239,
        description: "Silky baked cheesecake topped with homemade blueberry compote.",
        image_url: "https://images.unsplash.com/photo-1533134242443-d4fd215305ad?w=400&auto=format&fit=crop&q=80",
        is_available: true
      },
      {
        id: "b0000000-0000-0000-0000-000000000015",
        name: "Double Fudge Brownie Sundae",
        category: "Desserts",
        price: 260,
        offer_price: null,
        description: "Gooey dark fudge brownie served warm with vanilla bean gelato & fudge syrup.",
        image_url: "https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=400&auto=format&fit=crop&q=80",
        is_available: true
      }
    ]
  }
};

function isSupabaseConfigured() {
  return (
    CONFIG.SUPABASE_URL &&
    !CONFIG.SUPABASE_URL.includes("YOUR_PROJECT") &&
    CONFIG.SUPABASE_ANON_KEY &&
    !CONFIG.SUPABASE_ANON_KEY.includes("YOUR_ANON")
  );
}
