import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'reject_bottle_screen.dart';

enum _PaymentStep { chooseMethod, scanUpi, enterPhone, processing, success, failed, serverUnavailable }

class PaymentScreen extends StatefulWidget {
  final String token;
  final String refundQrCode;
  final String manufacturingQrCode;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> user;

  const PaymentScreen({
    super.key,
    required this.token,
    required this.refundQrCode,
    required this.manufacturingQrCode,
    required this.latitude,
    required this.longitude,
    required this.user,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _apiService = ApiService();
  final _phoneController = TextEditingController();

  _PaymentStep _step = _PaymentStep.chooseMethod;
  int _secondsLeft = 30;
  Timer? _countdownTimer;
  String? _errorMessage;
  Map<String, dynamic>? _result;

  void _startCountdown() {
    _secondsLeft = 30;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) _secondsLeft--;
      });
    });
  }

  Future<void> _pay(String method, String customerIdentifier) async {
    setState(() {
      _step = _PaymentStep.processing;
      _errorMessage = null;
    });
    _startCountdown();

    try {
      final result = await _apiService.completeReturn(
        widget.token,
        refundQrCode: widget.refundQrCode,
        manufacturingQrCode: widget.manufacturingQrCode,
        latitude: widget.latitude,
        longitude: widget.longitude,
        paymentMethod: method,
        customerIdentifier: customerIdentifier,
      );
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _step = _PaymentStep.success;
        _result = result;
      });
      VoiceService.instance.speak(VoiceMessage.paymentSuccess);
    } on ServerUnavailableException {
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() => _step = _PaymentStep.serverUnavailable);
    } catch (e) {
      _countdownTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _step = _PaymentStep.failed;
        _errorMessage = e.toString();
      });
    }
  }

  void _handleUpiScan(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null) return;
    _pay('upi', value);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Refund Payment')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _PaymentStep.chooseMethod:
        return _chooseMethodView();
      case _PaymentStep.scanUpi:
        return Stack(
          children: [
            MobileScanner(onDetect: _handleUpiScan),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Scan the customer\'s UPI QR code', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        );
      case _PaymentStep.enterPhone:
        return _enterPhoneView();
      case _PaymentStep.processing:
        return _processingView();
      case _PaymentStep.success:
        return _successView();
      case _PaymentStep.failed:
        return _failedView();
      case _PaymentStep.serverUnavailable:
        return _serverUnavailableView();
    }
  }

  Widget _chooseMethodView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.currency_rupee, size: 56, color: AppColors.primaryGreen),
              const SizedBox(height: 12),
              const Text(
                '₹10 Refund',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Does the customer have a UPI QR code available?',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _step = _PaymentStep.scanUpi);
                  VoiceService.instance.speak(VoiceMessage.showUpi);
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Yes — Scan Customer UPI QR'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => _step = _PaymentStep.enterPhone),
                icon: const Icon(Icons.phone_android),
                label: const Text('No — Enter Phone Number'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _enterPhoneView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Customer Mobile Number',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final phone = _phoneController.text.trim();
                  if (phone.isEmpty) return;
                  _pay('phone', phone);
                },
                child: const Text('Proceed with Refund'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _processingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: (30 - _secondsLeft) / 30,
                  strokeWidth: 6,
                  color: AppColors.primaryGreen,
                ),
                Text('$_secondsLeft s', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Processing ₹10 refund…', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Please do not close the app', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _successView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text('Refund Successful!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Bottle: ${_result?['qr_code'] ?? ''}'),
              Text('Amount: ₹${_result?['amount'] ?? '10'}'),
              Text('Reference: ${_result?['payment_reference'] ?? ''}'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => HomeScreen(user: widget.user, token: widget.token)),
                    (route) => false,
                  );
                },
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _failedView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.brandRed, size: 64),
              const SizedBox(height: 16),
              const Text('Payment Failed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'The payment could not be completed.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              const Text(
                'The bottle has not been marked as returned.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() => _step = _PaymentStep.chooseMethod),
                child: const Text('Retry'),
              ),
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

  Widget _serverUnavailableView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.orange, size: 64),
              const SizedBox(height: 16),
              const Text('Server Unavailable', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Could not reach the server. The refund has NOT been processed — '
                'no charge, no bottle status change.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() => _step = _PaymentStep.chooseMethod),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RejectBottleScreen(
                        token: widget.token,
                        refundQrCode: widget.refundQrCode,
                        latitude: widget.latitude,
                        longitude: widget.longitude,
                        initialReason: 'other',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Log as rejected instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
