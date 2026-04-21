import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'profile_page.dart';

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({Key? key}) : super(key: key);

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  String _ownerName = 'Loading...';
  List<Map<String, dynamic>> _requests = [];
  StreamSubscription<List<Map<String, dynamic>>>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _initRequestsStream();
  }

  void _initRequestsStream() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    
    _streamSubscription = Supabase.instance.client
        .from('print_requests')
        .stream(primaryKey: ['id'])
        .eq('shop_id', user.id)
        .order('created_at')
        .listen((data) {
          if (data.length > _requests.length && _requests.isNotEmpty) {
            _showNewRequestPing();
          }
          if (mounted) {
            setState(() {
              _requests = List<Map<String, dynamic>>.from(data)
                ..sort((a, b) => b['created_at'].compareTo(a['created_at']));
            });
          }
        });
  }

  void _showNewRequestPing() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.white),
            SizedBox(width: 12),
            Text('New Print Request!', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final data = await Supabase.instance.client.from('profiles').select().eq('id', user.id).single();
        if (mounted) setState(() => _ownerName = data['full_name'] ?? 'Owner');
      } catch (e) {
        if (mounted) setState(() => _ownerName = user.email?.split('@')[0] ?? 'Owner');
      }
    }
  }

  Map<String, List<Map<String, dynamic>>> _getGroupedRequests() {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var request in _requests) {
      String name = request['customer_name'] ?? 'Anonymous';
      if (!grouped.containsKey(name)) {
        grouped[name] = [];
      }
      grouped[name]!.add(request);
    }
    return grouped;
  }

  void _showQrDialog(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final qrData = 'https://safe-xerox-customer.vercel.app/connect?id=${user.id}&name=$_ownerName';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('My Shop QR', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1B5E20))),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _printQrCode(qrData),
                  icon: const Icon(Icons.print, color: Color(0xFF1B5E20)),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(width: 200, height: 200, child: QrImageView(data: qrData, version: QrVersions.auto, size: 200.0, foregroundColor: const Color(0xFF1B5E20))),
            const SizedBox(height: 24),
            Text(_ownerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  Future<void> _printQrCode(String qrData) async {
    final doc = pw.Document();
    doc.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Column(children: [
      pw.Text('SAFE XEROX', style: pw.TextStyle(fontSize: 40, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
      pw.SizedBox(height: 50),
      pw.BarcodeWidget(data: qrData, barcode: pw.Barcode.qrCode(), width: 300, height: 300, color: PdfColors.green900),
      pw.SizedBox(height: 40),
      pw.Text(_ownerName, style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold)),
    ]))));
    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'SafeXerox_QR_$_ownerName');
  }

  Future<void> _printUploadedFile(String url, String fileName) async {
    try {
      final fileResponse = await http.get(Uri.parse(url));
      final bytes = fileResponse.bodyBytes;
      final String extension = fileName.toLowerCase();
      final bool isImage = extension.endsWith('.jpg') || extension.endsWith('.jpeg') || extension.endsWith('.png');

      Uint8List printBytes;
      if (isImage) {
        final doc = pw.Document();
        final image = pw.MemoryImage(bytes);
        doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (pw.Context context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
        printBytes = await doc.save();
      } else {
        printBytes = bytes;
      }
      await Printing.layoutPdf(onLayout: (format) async => printBytes, name: fileName);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteRequest(Map<String, dynamic> request) async {
    try {
      final fileUrl = request['file_url'] as String;
      final fileName = Uri.parse(fileUrl).pathSegments.last;
      await Supabase.instance.client.storage.from('print-files').remove(['uploads/${request['shop_id']}/$fileName']);
      await Supabase.instance.client.from('print_requests').delete().eq('id', request['id']);
    } catch (e) {
      debugPrint('Error deleting: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedRequests = _getGroupedRequests();
    final customerNames = groupedRequests.keys.toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Safe Xerox Partner', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF1B5E20))),
          Text(_ownerName, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          IconButton(onPressed: () => _showQrDialog(context), icon: const Icon(Icons.qr_code, color: Color(0xFF1B5E20))),
          IconButton(onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
            _fetchProfile();
          }, icon: const Icon(Icons.person_outlined, color: Color(0xFF1B5E20))),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Customer Print Requests', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: _requests.isEmpty 
              ? const Center(child: Text('No requests yet'))
              : ListView.builder(
                  itemCount: customerNames.length,
                  itemBuilder: (context, index) {
                    final name = customerNames[index];
                    final files = groupedRequests[name]!;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF1B5E20).withOpacity(0.1),
                            child: const Icon(Icons.person, color: Color(0xFF1B5E20)),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          subtitle: Text(
                            '${files.length} ${files.length == 1 ? 'file' : 'files'} uploaded',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          children: files.map((file) {
                            final time = DateTime.parse(file['created_at']);
                            return ListTile(
                              leading: const Icon(Icons.description_outlined),
                              title: Text(file['file_name'] ?? 'File'),
                              subtitle: Text(DateFormat('hh:mm a').format(time.toLocal())),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.print, color: Color(0xFF1B5E20)), onPressed: () => _printUploadedFile(file['file_url'], file['file_name'])),
                                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteRequest(file)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
  }
}
