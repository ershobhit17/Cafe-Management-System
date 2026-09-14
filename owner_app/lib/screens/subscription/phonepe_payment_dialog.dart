import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../models/subscription_model.dart';
import '../../services/auth_service.dart';
import '../../services/subscription_service.dart';

class PhonePePaymentDialog extends StatefulWidget {
  final SubscriptionTierInfo tier;

  const PhonePePaymentDialog({super.key, required this.tier});

  @override
  State<PhonePePaymentDialog> createState() => _PhonePePaymentDialogState();
}

class _PhonePePaymentDialogState extends State<PhonePePaymentDialog> {
  final _utrController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _inlineError;

  String get _merchantVpa => SupabaseConfig.adminUpiId;
  String get _merchantName => SupabaseConfig.adminPayeeName;

  late final String _txnId;
  late final String _upiUrl;

  @override
  void initState() {
    super.initState();
    _txnId = 'SS${DateTime.now().millisecondsSinceEpoch.toString().substring(3)}';
    final amountStr = widget.tier.price.toStringAsFixed(2);
    _upiUrl = 'upi://pay?pa=$_merchantVpa&pn=${Uri.encodeComponent(_merchantName)}&am=$amountStr&cu=INR&tr=$_txnId&tn=SnapServe+${widget.tier.id}+Plan';
  }

  @override
  void dispose() {
    _utrController.dispose();
    super.dispose();
  }

  Future<void> _launchUpiApp() async {
    final uri = Uri.parse(_upiUrl);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No UPI app found. Please scan the QR code or pay to the UPI ID.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open UPI app: $e')),
        );
      }
    }
  }

  Future<void> _submitUtr() async {
    if (!_formKey.currentState!.validate()) return;

    final utr = _utrController.text.trim();
    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    final auth = context.read<AuthService>();
    final subService = context.read<SubscriptionService>();

    final res = await subService.submitUtrPayment(
      cafeId: auth.currentCafeId,
      tier: widget.tier.id,
      utrNumber: utr,
      amount: widget.tier.price,
      isDemo: auth.isDemoMode,
    );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      Navigator.pop(context, true);
      // Show confirmation dialog to user
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Expanded(child: Text('Payment Submitted!')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your payment details for ${widget.tier.name} (₹${widget.tier.price.toStringAsFixed(0)}) have been sent to Super Admin for verification.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tag, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Submitted Bank UTR:', style: TextStyle(fontSize: 11, color: Colors.black54)),
                          Text(utr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Super Admin will match this UTR with the bank account statement and activate your plan shortly.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A00),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got It'),
            ),
          ],
        ),
      );
    } else {
      String err = res['error']?.toString() ?? 'Verification failed. Please check UTR.';
      if (err.contains('PostgrestException') || err.contains('check constraint')) {
        err = 'Payment could not be processed. Please check your UTR number and retry.';
      }
      setState(() {
        _inlineError = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF7A00);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.rocket_launch, color: primaryColor, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Upgrade to ${widget.tier.name}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Text(
                              'Direct UPI Transfer & Fast Approval',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Amount Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Payable Subscription Amount', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          Text(
                            '₹${widget.tier.price.toStringAsFixed(0)} / month',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified_user, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Secure UPI', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Real QR Code Display
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/images/admin_upi_qr.jpg',
                            width: 220,
                            height: 260,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, stack) => QrImageView(
                              data: _upiUrl,
                              version: QrVersions.auto,
                              size: 180.0,
                              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1E88E5)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Scan to pay with any UPI app (GPay, PhonePe, Paytm)',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Payee Details Strip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(0xFFE3F2FD),
                        child: Icon(Icons.person, size: 16, color: Color(0xFF1976D2)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _merchantName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            Text(
                              _merchantVpa,
                              style: const TextStyle(fontSize: 11, color: Colors.black87, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16, color: Color(0xFF1976D2)),
                        tooltip: 'Copy UPI ID',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _merchantVpa));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('UPI ID copied to clipboard!'), duration: Duration(seconds: 2)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Pay via UPI App deep link button
                OutlinedButton.icon(
                  onPressed: _launchUpiApp,
                  icon: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF1976D2)),
                  label: const Text('Pay via UPI App', style: TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),

                const Divider(),
                const SizedBox(height: 8),

                // Step 2: 12-Digit Bank UTR Submission
                const Text(
                  'Step 2: Enter Bank Reference / UTR Number',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Copy the 12-digit UTR/Ref No. from your UPI payment receipt and submit below. Super Admin will verify with bank payment and activate your plan.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: _utrController,
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    LengthLimitingTextInputFormatter(22),
                  ],
                  decoration: InputDecoration(
                    labelText: '12-Digit Bank UTR / Reference Number',
                    hintText: 'e.g. 425619283741',
                    prefixIcon: const Icon(Icons.tag, color: primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter the 12-digit Bank UTR';
                    }
                    if (val.trim().length < 10) {
                      return 'UTR must be at least 10-12 characters long';
                    }
                    return null;
                  },
                ),

                if (_inlineError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _inlineError!,
                            style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Submit Action Button
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitUtr,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Submit Payment for Approval',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
