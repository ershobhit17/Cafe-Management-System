import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../home/main_nav_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cafeNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _cafeNameController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();

    bool success = false;
    if (_isSignUp) {
      success = await auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        cafeName: _cafeNameController.text.trim(),
      );
    } else {
      success = await auth.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
    }

    if (success && mounted) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavScreen()),
        );
      }
    }
  }

  Future<void> _handleDemoLogin() async {
    final auth = context.read<AuthService>();
    await auth.demoLogin();
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthService>();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand Icon & Header
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7A00).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('☕', style: TextStyle(fontSize: 40)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Cafe Owner Portal',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isSignUp
                        ? 'Register your cafe to manage live orders & tables'
                        : 'Sign in to manage live orders, menu & daily earnings',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Auth Mode Switcher (Sign In vs Sign Up)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isSignUp = false),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !_isSignUp ? const Color(0xFFFF7A00) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Sign In',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: !_isSignUp ? Colors.white : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isSignUp = true),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _isSignUp ? const Color(0xFFFF7A00) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Create New Cafe',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _isSignUp ? Colors.white : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Error Message Banner
                  if (auth.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Text(
                        auth.errorMessage!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Cafe Name Field (Only in Sign Up mode)
                  if (_isSignUp) ...[
                    TextFormField(
                      controller: _cafeNameController,
                      decoration: InputDecoration(
                        labelText: 'Cafe / Restaurant Name *',
                        hintText: 'e.g. Aroma Cafe, The Coffee House',
                        prefixIcon: const Icon(Icons.storefront_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) {
                        if (_isSignUp && (val == null || val.trim().isEmpty)) {
                          return 'Please enter your cafe name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email Address *',
                      hintText: 'owner@example.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Please enter email';
                      if (!val.contains('@')) return 'Please enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      hintText: '••••••••',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Please enter password';
                      if (_isSignUp && val.length < 6) return 'Password must be at least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Helper note
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Color(0xFFFF7A00)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _isSignUp
                              ? 'Each cafe has isolated tables, menu & live orders'
                              : 'Persistent session enabled (Stay logged in)',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Action Button (Sign In / Register)
                  ElevatedButton(
                    onPressed: auth.isLoading ? null : _handleAuth,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: auth.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _isSignUp ? 'Register & Open Cafe' : 'Sign In',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 14),

                  // Live Demo Fast Access
                  OutlinedButton.icon(
                    onPressed: auth.isLoading ? null : _handleDemoLogin,
                    icon: const Icon(Icons.flash_on, color: Color(0xFFFF7A00)),
                    label: const Text('Fast Preview / Demo Cafe Mode'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF7A00),
                      side: const BorderSide(color: Color(0xFFFF7A00)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
