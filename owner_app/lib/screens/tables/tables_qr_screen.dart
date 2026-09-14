import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../models/table_model.dart';
import '../../services/auth_service.dart';
import '../../services/cafe_service.dart';
import '../../services/subscription_service.dart';
import '../subscription/subscription_plans_screen.dart';

class TablesQrScreen extends StatefulWidget {
  const TablesQrScreen({super.key});

  @override
  State<TablesQrScreen> createState() => _TablesQrScreenState();
}

class _TablesQrScreenState extends State<TablesQrScreen> {
  final _storage = const FlutterSecureStorage();
  static const String _keyCustomBaseUrl = 'custom_customer_web_base_url';

  // Default to live Render deployment so QR codes and browser links work everywhere
  String _baseUrl = SupabaseConfig.customerWebBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadCustomBaseUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTables();
    });
  }

  Future<void> _loadCustomBaseUrl() async {
    try {
      final saved = await _storage.read(key: _keyCustomBaseUrl);
      if (saved != null && saved.trim().isNotEmpty && mounted) {
        setState(() => _baseUrl = saved.trim());
      }
    } catch (_) {}
  }

  void _loadTables() {
    final auth = context.read<AuthService>();
    context.read<CafeService>().fetchTables(auth.currentCafeId, isDemo: auth.isDemoMode);
  }

  Future<void> _launchWebUrl(String url) async {
    if (url.contains('127.0.0.1') || url.contains('localhost')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 4),
            content: Text(
              'Notice: 127.0.0.1 phone me open nahi hota. Render URL use karein.',
            ),
          ),
        );
      }
    }
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url in browser')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching browser: $e')),
        );
      }
    }
  }

  Future<void> _printSingleTable(CafeTable table, String cafeName) async {
    final pdf = pw.Document();
    final qrUrl = table.getCustomerUrl(_baseUrl);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Container(
              width: 320,
              padding: const pw.EdgeInsets.all(24),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.orange700, width: 2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    cafeName.isNotEmpty ? cafeName : 'SnapServe Cafe',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.orange900,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'DINE-IN ORDER SERVICE',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  pw.SizedBox(height: 14),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.orange600,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Text(
                      'TABLE #${table.tableNumber}',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 18),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrUrl,
                    width: 170,
                    height: 170,
                    color: PdfColors.black,
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'SCAN TO VIEW MENU & ORDER',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Point phone camera at QR code • No app download required',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      qrUrl,
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Table_${table.tableNumber}_QR_Standee.pdf',
    );
  }

  Future<void> _printAllTables(List<CafeTable> tables, String cafeName) async {
    if (tables.isEmpty) return;
    final pdf = pw.Document();

    for (final table in tables) {
      final qrUrl = table.getCustomerUrl(_baseUrl);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Container(
                width: 320,
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.orange700, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
                ),
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      cafeName.isNotEmpty ? cafeName : 'SnapServe Cafe',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange900,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'DINE-IN ORDER SERVICE',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    pw.SizedBox(height: 14),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.orange600,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                      child: pw.Text(
                        'TABLE #${table.tableNumber}',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 18),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrUrl,
                      width: 170,
                      height: 170,
                      color: PdfColors.black,
                    ),
                    pw.SizedBox(height: 16),
                    pw.Text(
                      'SCAN TO VIEW MENU & ORDER',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Point phone camera at QR code • No app download required',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        qrUrl,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'All_Tables_QR_Standees.pdf',
    );
  }

  void _showUpgradePlanDialog(BuildContext context, String resourceType, int currentLimit) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.upgrade, color: Color(0xFFFF7A00)),
            SizedBox(width: 8),
            Text('Plan Limit Reached'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have reached the maximum limit of $currentLimit ${resourceType}s allowed on your current plan.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Upgrade to Growth (20 Tables) or Enterprise (Unlimited) to add more dining tables and scale your cafe.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7A00),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.flash_on, size: 16),
            label: const Text('Upgrade Plan'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionPlansScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddTableDialog(BuildContext context, CafeService cafeService, AuthService auth) {
    final subService = context.read<SubscriptionService>();
    if (subService.overview != null && subService.overview!.isTablesLimitReached) {
      _showUpgradePlanDialog(context, 'table', subService.overview!.maxTables);
      return;
    }

    final controller = TextEditingController(
      text: (cafeService.tables.isNotEmpty ? cafeService.tables.last.tableNumber + 1 : 1).toString(),
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Dining Table'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Table Number',
            border: OutlineInputBorder(),
            helperText: 'A unique QR code token will be generated',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7A00), foregroundColor: Colors.white),
            onPressed: () async {
              final num = int.tryParse(controller.text.trim());
              if (num != null && num > 0) {
                final ok = await cafeService.addTable(auth.currentCafeId, num, isDemo: auth.isDemoMode);
                if (context.mounted) {
                  Navigator.pop(context);
                  if (!ok && cafeService.errorMessage != null && cafeService.errorMessage!.contains('LIMIT_EXCEEDED')) {
                    _showUpgradePlanDialog(context, 'table', subService.overview?.maxTables ?? 5);
                  }
                }
              }
            },
            child: const Text('Create Table & QR'),
          ),
        ],
      ),
    );
  }

  void _showQrDetailModal(BuildContext context, CafeTable table, String cafeName) {
    final qrUrl = table.getCustomerUrl(_baseUrl);

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '☕ ${cafeName.isNotEmpty ? cafeName : "SnapServe Cafe"}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF7A00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'TABLE #${table.tableNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF7A00), fontSize: 16),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: qrUrl,
                  version: QrVersions.auto,
                  size: 200.0,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFFFF7A00)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Point smartphone camera to scan menu & place order',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  qrUrl,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 20),

              // ACTION BUTTONS: Print Standee, Open in Browser, Close
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _launchWebUrl(qrUrl),
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('Open in Browser'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _printSingleTable(table, cafeName);
                    },
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('Print Standee'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final cafeService = context.watch<CafeService>();
    final cafeName = auth.currentCafeName.isNotEmpty ? auth.currentCafeName : SupabaseConfig.demoCafeName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cafeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const Text('Tables & QR Codes', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print All QR Standees',
            onPressed: cafeService.tables.isNotEmpty
                ? () => _printAllTables(cafeService.tables, cafeName)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Tables',
            onPressed: _loadTables,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFFF7A00),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Table', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _showAddTableDialog(context, cafeService, auth),
      ),
      body: Column(
        children: [


          // Tables Grid
          Expanded(
            child: cafeService.isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF7A00)))
                : cafeService.tables.isEmpty
                    ? Center(
                        child: Text(
                          'No tables added yet.\nClick "Add Table" to generate your first QR code.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          childAspectRatio: 0.82,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: cafeService.tables.length,
                        itemBuilder: (context, index) {
                          final table = cafeService.tables[index];
                          final qrUrl = table.getCustomerUrl(_baseUrl);

                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 2,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _showQrDetailModal(context, table, cafeName),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Table ${table.tableNumber}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(4),
                                      child: QrImageView(
                                        data: qrUrl,
                                        version: QrVersions.auto,
                                        size: 100.0,
                                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFFFF7A00)),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.print, size: 14, color: Color(0xFFFF7A00)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Print Standee',
                                          style: TextStyle(fontSize: 11, color: Color(0xFFFF7A00), fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
