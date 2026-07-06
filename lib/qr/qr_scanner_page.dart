import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:smart_event_app/participant/participant_service.dart';
import 'package:smart_event_app/services/local_db_service.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class QRScannerPage extends StatefulWidget {
  final String eventId; 

  const QRScannerPage({super.key, required this.eventId});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final service = ParticipantService();
  bool scanned = false;
  bool isOfflineMode = false; // Toggle for local DB scanning

  final MobileScannerController controller = MobileScannerController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _processRawValue(String raw) async {
    if (scanned) return;
    setState(() => scanned = true);

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      _showError("Invalid QR format");
      _resetScan();
      return;
    }

    final guestId = decoded['guestId'];
    if (guestId == null) {
      _showError("Invalid QR data");
      _resetScan();
      return;
    }

    final qrEventId = decoded['eventId']?.toString();
    if (qrEventId == null || qrEventId != widget.eventId) {
      _showError("Wrong Event QR");
      _resetScan();
      return;
    }
    
    await controller.stop();

    try {
      if (isOfflineMode) {
        // Use SQLite database
        await LocalDbService().markAttendanceOffline(guestId, widget.eventId);
      } else {
        // Use Firebase
        await service.markAttendanceByGuestId(guestId, currentEventId: widget.eventId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOfflineMode ? "Attendance Marked (Offline)" : "Attendance Marked (Cloud)", style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceAll("Exception: ", ""));
    }

    // restart scanner
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await controller.start();
    setState(() => scanned = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  void _resetScan() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => scanned = false);
    });
  }

  Future<void> _scanFromImage() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(type: FileType.image);

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final dynamic capture = await controller.analyzeImage(path);
        
        if (capture == true) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Analyzing image... Please wait.")));
        } else if (capture != false && capture != null) {
          final barcodes = capture.barcodes as List;
          if (barcodes.isNotEmpty) {
            final raw = barcodes.first.rawValue;
            if (raw != null && raw.isNotEmpty) {
              await _processRawValue(raw);
            } else {
              _showError("No valid data found in QR");
            }
          } else {
            _showError("No QR code detected in image");
          }
        } else {
          _showError("No QR code detected in image");
        }
      }
    } catch (e) {
      _showError("Failed to analyze image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Scan QR", style: TextStyle(color: isOfflineMode ? Colors.white : AppColors.textPrimary)),
        backgroundColor: isOfflineMode ? AppColors.warning : AppColors.surface,
        iconTheme: IconThemeData(color: isOfflineMode ? Colors.white : AppColors.textPrimary),
        actions: [
          Row(
            children: [
              Text(
                "Offline", 
                style: TextStyle(fontWeight: FontWeight.bold, color: isOfflineMode ? Colors.white : AppColors.textSecondary)
              ),
              Switch(
                value: isOfflineMode,
                activeColor: Colors.white,
                activeTrackColor: AppColors.success,
                onChanged: (val) {
                  setState(() => isOfflineMode = val);
                  if (val) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Switched to Offline Database. Ensure you have downloaded the event list first!"))
                    );
                  }
                },
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.image),
            tooltip: "Upload QR Image",
            onPressed: _scanFromImage,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text("Camera error: ${error.errorCode.name}", style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 8),
                      const Text("Please grant camera permissions or use the Image Upload icon.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              );
            },
            onDetect: (capture) async {
              if (scanned) return;
              final barcodes = capture.barcodes.firstOrNull;
              if (barcodes == null) return;
              final raw = barcodes.rawValue;
              if (raw == null || raw.isEmpty) return;
              await _processRawValue(raw);
            },
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isOfflineMode ? AppColors.warning : Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isOfflineMode 
                    ? "OFFLINE MODE: Scanning against local DB"
                    : "Scan with camera or tap the image icon above",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}