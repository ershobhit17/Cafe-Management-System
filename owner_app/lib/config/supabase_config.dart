// ==============================================================================
// Supabase Configuration & Fallback Demo Context
// ==============================================================================

class SupabaseConfig {
  // Replace these with your Supabase project settings (Settings > API)
  static const String supabaseUrl = 'https://vmhplagbwottgsdpzsxp.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZtaHBsYWdid290dGdzZHB6c3hwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg5NDk3NTEsImV4cCI6MjEwNDUyNTc1MX0.Vkik8EA0s-lpcth1NhsyH10Im8OJ19BiC1ev7u9JkQo';

  // Demo Fallback identifiers to enable zero-friction offline preview
  static const String demoCafeId = 'a0000000-0000-0000-0000-000000000001';
  static const String demoCafeName = 'Aroma Artisan Cafe';
  static const String customerWebBaseUrl = 'https://cafe-management-system-nbi5.onrender.com';

  static bool get isConfigured {
    return supabaseUrl.isNotEmpty &&
        !supabaseUrl.contains('YOUR_PROJECT') &&
        supabaseAnonKey.isNotEmpty &&
        !supabaseAnonKey.contains('YOUR_ANON');
  }
}
