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
    if (user == null) {
      debugPrint('STREAM ERROR: No user logged in');
      return;
    }
    
    debugPrint('STREAM STARTING: Listening for shop_id: ${user.id}');

    _streamSubscription = Supabase.instance.client
        .from('print_requests')
        .stream(primaryKey: ['id'])
        .eq('shop_id', user.id)
        .order('created_at')
        .listen((data) {
          debugPrint('STREAM UPDATE: Received ${data.length} requests');
          
          if (data.length > _requests.length && _requests.isNotEmpty) {
            _showNewRequestPing();
          }
          
          if (mounted) {
            setState(() {
              _requests = List<Map<String, dynamic>>.from(data)
                ..sort((a, b) => b['created_at'].compareTo(a['created_at']));
            });
          }
        }, onError: (error) {
          debugPrint('STREAM FATAL ERROR: $error');
        });
  }

  void _showNewRequestPing() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.white),
            SizedBox(width: 12),
            Text('New Print Request Received!', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
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

  void _showQrDialog(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final qrData = 'safexerox://shop?id=${user.id}&name=$_ownerName';

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
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF1B5E20).withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.print, color: Color(0xFF1B5E20), size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200, height: 200,
              child: QrImageView(data: qrData, version: QrVersions.auto, size: 200.0, foregroundColor: const Color(0xFF1B5E20)),
            ),
            const SizedBox(height: 24),
            Text(_ownerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.grey))),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing document for printing...')));
      
      final fileResponse = await http.get(Uri.parse(url));
      final bytes = fileResponse.bodyBytes;
      
      final String extension = fileName.toLowerCase();
      final bool isImage = extension.endsWith('.jpg') || 
                           extension.endsWith('.jpeg') || 
                           extension.endsWith('.png');

      Uint8List printBytes;

      if (isImage) {
        // Wrap image in a PDF
        final doc = pw.Document();
        final image = pw.MemoryImage(bytes);
        
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
        printBytes = await doc.save();
      } else {
        // It's already a PDF
        printBytes = bytes;
      }

      await Printing.layoutPdf(
        onLayout: (format) async => printBytes,
        name: fileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not print: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteRequest(Map<String, dynamic> request) async {
    try {
      // Optimistic UI Update: Remove from screen immediately
      if (mounted) {
        setState(() {
          _requests.removeWhere((item) => item['id'] == request['id']);
        });
      }

      // 1. Delete from Storage
      final fileUrl = request['file_url'] as String;
      final uri = Uri.parse(fileUrl);
      final fileName = uri.pathSegments.last;
      final shopId = request['shop_id'];
      final storagePath = 'uploads/$shopId/$fileName';

      await Supabase.instance.client.storage
          .from('print-files')
          .remove([storagePath]);

      // 2. Delete from Database
      await Supabase.instance.client
          .from('print_requests')
          .delete()
          .eq('id', request['id']);

      // No need to fetch manually, the Stream handles it
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request and file deleted permanently')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting request: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Safe Xerox Partner', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF1B5E20), fontSize: 20)),
          Text(_ownerName, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600])),
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
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Requests', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: _initRequestsStream,
                child: const Text('Refresh', style: TextStyle(color: Color(0xFF1B5E20))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _requests.isEmpty 
              ? const Center(child: Text('No requests yet'))
              : ListView.builder(
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final request = _requests[index];
                    final time = DateTime.parse(request['created_at']);
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined, color: Color(0xFF1B5E20)),
                        title: Text(request['file_name'] ?? 'Document'),
                        subtitle: Text('Sent at ${DateFormat('hh:mm a').format(time.toLocal())}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.print, color: Color(0xFF1B5E20)),
                              onPressed: () => _printUploadedFile(
                                request['file_url'],
                                request['file_name'] ?? 'document',
                              ),
                              tooltip: 'Print File',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _deleteRequest(request),
                              tooltip: 'Delete Permanently',
                            ),
                          ],
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
