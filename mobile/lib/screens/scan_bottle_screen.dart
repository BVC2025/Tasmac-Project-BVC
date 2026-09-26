import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../theme/app_colors.dart';
import 'payment_screen.dart';
import 'reject_bottle_screen.dart';

enum _Step { scanRefund, busy, scanManufacturing, condition, error, serverUnavailable }

class ScanBottleScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const ScanBottleScreen({super.key, required this.token, required this.user});

  @override
  State<ScanBottleScreen> createState() => _ScanBottleScreenState();
}

class _ScanBottleScreenState extends State<ScanBottleScreen> {
  final _apiService = ApiService();
  final MobileScannerController _controller = MobileScannerController();

  _Step _step = _Step.scanRefund;
  String? _refundQrCode;
  String? _manufacturingQrCode;
  double? _latitude;
  double? _longitude;
  String? _errorMessage;
  bool _offerReject = false;
  String _rejectReasonHint = 'other';

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services are disabled');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to process a return');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  // The scanner stays live across both steps — no stop()/start() cycling,
  // which on some devices leaves the camera preview blank after restart.
  // The `_step` check below is what stops a stray detection mid-verify.
  void _handleDetect(BarcodeCapture capture) {
    if (_step != _Step.scanRefund && _step != _Step.scanManufacturing) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null) return;

    if (_step == _Step.scanRefund) {
      _handleRefundDetect(code);
    } else {
      // The camera is still pointed at the just-verified refund QR — ignore
      // it until the user actually moves to the manufacturing QR.
      if (code == _refundQrCode) return;
      _handleManufacturingDetect(code);
    }
  }

  Future<void> _handleRefundDetect(String code) async {
    setState(() => _step = _Step.busy);

    try {
      final position = await _getCurrentPosition();
      await _apiService.verifyRefundQr(
        widget.token,
        refundQrCode: code,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      setState(() {
        _refundQrCode = code;
        _latitude = position.latitude;
        _longitude = position.longitude;
        _step = _Step.scanManufacturing;
      });
      VoiceService.instance.speak(VoiceMessage.refundVerified);
    } on ServerUnavailableException {
      setState(() => _step = _Step.serverUnavailable);
    } on ApiException catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = e.toString();
        _offerReject = e.toString().toLowerCase().contains('not recognized') ||
            e.toString().toLowerCase().contains('already been');
        _rejectReasonHint =
            e.toString().toLowerCase().contains('already been') ? 'qr_already_used' : 'refund_qr_invalid';
      });
    } catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _offerReject = false;
      });
    }
  }

  Future<void> _handleManufacturingDetect(String code) async {
    setState(() => _step = _Step.busy);

    try {
      await _apiService.verifyManufacturingQr(
        widget.token,
        refundQrCode: _refundQrCode!,
        manufacturingQrCode: code,
      );
      setState(() {
        _manufacturingQrCode = code;
        _step = _Step.condition;
      });
      VoiceService.instance.speak(VoiceMessage.manufacturingVerified);
    } on ServerUnavailableException {
      setState(() => _step = _Step.serverUnavailable);
    } on ApiException catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = e.toString();
        _offerReject = true;
        _rejectReasonHint = 'manufacturing_qr_invalid';
      });
    } catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _offerReject = false;
      });
    }
  }

  void _resetToScanRefund() {
    setState(() {
      _step = _Step.scanRefund;
      _refundQrCode = null;
      _manufacturingQrCode = null;
      _latitude = null;
      _longitude = null;
      _errorMessage = null;
      _offerReject = false;
    });
  }

  void _goodCondition() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PaymentScreen(
              token: widget.token,
              refundQrCode: _refundQrCode!,
              manufacturingQrCode: _manufacturingQrCode!,
              latitude: _latitude!,
              longitude: _longitude!,
              user: widget.user,
            ),
          ),
        )
        .then((_) => _resetToScanRefund());
  }

  void _damagedCondition() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => RejectBottleScreen(
              token: widget.token,
              refundQrCode: _refundQrCode,
              latitude: _latitude,
              longitude: _longitude,
              initialReason: 'bottle_physically_damaged',
            ),
          ),
        )
        .then((_) => _resetToScanRefund());
  }

  void _openReject() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => RejectBottleScreen(
              token: widget.token,
              refundQrCode: _refundQrCode,
              latitude: _latitude,
              longitude: _longitude,
              initialReason: _rejectReasonHint,
            ),
          ),
        )
        .then((_) => _resetToScanRefund());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Bottle to Return')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.scanRefund:
      case _Step.busy:
      case _Step.scanManufacturing:
        return _scannerView();
      case _Step.condition:
        return _conditionView();
      case _Step.error:
        return _errorView();
      case _Step.serverUnavailable:
        return _serverUnavailableView();
    }
  }

  Widget _scannerView() {
    final onManufacturingStep = _step == _Step.scanManufacturing || _refundQrCode != null;
    final instruction = onManufacturingStep
        ? 'Step 2 of 2 — Scan the MANUFACTURING QR code (bottom of bottle)'
        : 'Step 1 of 2 — Scan the REFUND QR code (top of bottle)';

    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _handleDetect),
        if (onManufacturingStep)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(10)),
              child: const Text(
                'Refund QR verified ✓',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (_step == _Step.busy)
          Container(
            color: Colors.black45,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            color: Colors.black54,
            padding: const EdgeInsets.all(20),
            child: Text(
              instruction,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _conditionView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fact_check_outlined, size: 56, color: AppColors.primaryGreen),
              const SizedBox(height: 12),
              const Text('Both QR codes verified ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              const Text(
                'Check the physical bottle condition',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const Text(
                'Broken, cracked, tampered, or otherwise unacceptable?',
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _goodCondition,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Good — Proceed to Refund'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.brandRed),
                onPressed: _damagedCondition,
                icon: const Icon(Icons.report_gmailerrorred_outlined),
                label: const Text('Damaged — Reject'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.brandRed, size: 56),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Something went wrong', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: _resetToScanRefund, child: const Text('Scan Again')),
              if (_offerReject) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.brandRed),
                  onPressed: _openReject,
                  child: const Text('Log Rejection'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _serverUnavailableView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.orange, size: 56),
              const SizedBox(height: 12),
              const Text('Server Unavailable', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Could not reach the server. Nothing has been changed. Check your connection and retry.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _resetToScanRefund, child: const Text('Retry')),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
