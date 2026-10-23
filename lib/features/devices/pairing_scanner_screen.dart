import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/app_theme.dart';

class PairingScannerScreen extends StatefulWidget {
  const PairingScannerScreen({super.key});
  @override
  State<PairingScannerScreen> createState() => _PairingScannerScreenState();
}

class _PairingScannerScreenState extends State<PairingScannerScreen> {
  bool _handled = false;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Scan pairing QR')), body: Stack(children: [
    MobileScanner(onDetect: (capture) {
      if (_handled) return;
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue;
        if (raw == null) continue;
        final uri = Uri.tryParse(raw);
        if (uri?.scheme == 'pocketcloud' && uri?.host == 'pair' && uri!.pathSegments.isNotEmpty) {
          final code = uri.pathSegments.last.toUpperCase();
          if (RegExp(r'^[A-HJ-NP-Z2-9]{12}$').hasMatch(code)) {
            _handled = true;
            Navigator.of(context).pop(code);
            return;
          }
        }
      }
    }),
    Align(alignment: Alignment.bottomCenter, child: Container(margin: const EdgeInsets.all(22), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: .88), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)), child: const Text('Scan the QR shown on your own server phone. Camera access is used only on this screen.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.white, height: 1.4)))),
  ]));
}
