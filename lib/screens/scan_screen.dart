// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
// Scans a QR code (an address or camo: link) with the camera and returns its text. Nothing leaves the phone:
// mobile_scanner decodes on the device.
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            const ScreenHeader('SCAN QR'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ClipRect(
                  child: MobileScanner(
                    controller: _controller,
                    errorBuilder: (context, error) => Center(
                      child: Text('Camera not available: ${error.errorCode.name}.\nAllow camera access in Settings, or paste instead.',
                          textAlign: TextAlign.center, style: Gt.body(14, color: Gc.text2)),
                    ),
                    onDetect: (capture) {
                      final v = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                      if (v == null || _done) return;
                      _done = true;
                      Navigator.pop(context, v.trim());
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text('Point at a CAMO address or camo: payment QR.', style: Gt.body(13, color: Gc.text3)),
            ),
          ]),
        ),
      );
}
