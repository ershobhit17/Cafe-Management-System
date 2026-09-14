import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/subscription_service.dart';

class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});

  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingList = [];

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    setState(() => _isLoading = true);
    final subService = context.read<SubscriptionService>();
    final list = await subService.fetchPendingSubscriptions();
    if (mounted) {
      setState(() {
        _pendingList = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _approve(String subId, String cafeName, String tier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Approval'),
        content: Text('Did you verify payment for $cafeName ($tier)? This will activate their 30-day subscription.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & Activate'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final subService = context.read<SubscriptionService>();
    final ok = await subService.approveSubscription(subId);

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text('🎉 $cafeName ($tier) approved and activated!'),
        ),
      );
      _loadPending();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed to approve subscription.'),
        ),
      );
    }
  }

  Future<void> _reject(String subId, String cafeName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Payment?'),
        content: Text('Are you sure you want to reject the payment submission for $cafeName?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final subService = context.read<SubscriptionService>();
    final ok = await subService.rejectSubscription(subId, reason: 'Payment not found in bank');

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment for $cafeName rejected.')),
      );
      _loadPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF7A00);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment Approvals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Review Bank UTRs & Activate Plans', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadPending,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : _pendingList.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_circle_outline, size: 56, color: Colors.green.shade600),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'All Caught Up!',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No pending subscription requests at this moment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pendingList.length,
                  itemBuilder: (ctx, idx) {
                    final item = _pendingList[idx];
                    final subId = item['subscription_id']?.toString() ?? '';
                    final cafeName = item['cafe_name']?.toString() ?? 'Unknown Cafe';
                    final tier = item['tier']?.toString() ?? 'STARTER';
                    final amount = (item['amount_paid'] as num?)?.toDouble() ?? 0.0;
                    final utr = item['utr_number']?.toString() ?? '-';
                    final createdAtStr = item['created_at']?.toString() ?? '';
                    DateTime? dt;
                    if (createdAtStr.isNotEmpty) {
                      dt = DateTime.tryParse(createdAtStr);
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.orange.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cafeName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                      ),
                                      if (dt != null)
                                        Text(
                                          DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal()),
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5F259F).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF5F259F).withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    '$tier • ₹${amount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Color(0xFF5F259F),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Submitted Bank UTR:', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      const SizedBox(height: 2),
                                      SelectableText(
                                        utr,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    tooltip: 'Copy UTR',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: utr));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('UTR copied! Search in PhonePe statement.'), duration: Duration(seconds: 2)),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _reject(subId, cafeName),
                                    icon: const Icon(Icons.close, size: 16),
                                    label: const Text('Reject'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _approve(subId, cafeName, tier),
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Approve & Activate'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
