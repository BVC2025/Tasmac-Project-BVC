import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../theme/app_colors.dart';
import '../widgets/centered_scroll_view.dart';
import 'home_screen.dart';
import 'scan_bottle_screen.dart';

enum _PaymentStep { chooseMethod, scanUpi, enterPhone, processing, success, failed, serverUnavailable }

/// One combined payment for every valid bottle from a scan batch (a batch of
/// one is just the ordinary single-bottle case).
class BatchPaymentScreen extends StatefulWidget {
  final String token;
  final List<ScannedBottle> bottles;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> user;

  const BatchPaymentScreen({
    super.key,
    required this.token,
    required this.bottles,
    required this.latitude,
    required this.longitude,
    required this.user,
  });

  @override
  State<BatchPaymentScreen> createState() => _BatchPaymentScreenState();
}

class _BatchPaymentScreenState extends State<BatchPaymentScreen> {
  final _apiService = ApiService();
  final _phoneController = TextEditingController();

  _PaymentStep _step = _PaymentStep.chooseMethod;
  int _secondsLeft = 30;
  Timer? _countdownTimer;
  String? _errorMessage;
  Map<String, dynamic>? _result;
  // Known only when the customer was paid by phone number; for a UPI payment
  // staff are asked for it when they choose to send the SMS.
  String? _customerPhone;
  // Done stays locked until the customer has been sent the refund SMS (or
  // staff explicitly skip it, e.g. the customer has no phone).
  bool _smsDone = false;

  int get _amount => widget.bottles.length * 10;

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
      _customerPhone = method == 'phone' ? customerIdentifier : null;
    });
    _startCountdown();

    try {
      final result = await _apiService.completeReturnBatch(
        widget.token,
        bottles: [
          for (final bottle in widget.bottles)
            {
              'refund_qr_code': bottle.refundQrCode,
              'manufacturing_qr_code': bottle.manufacturingQrCode,
            },
        ],
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
    return CenteredScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.currency_rupee, size: 56, color: AppColors.primaryGreen),
          const SizedBox(height: 12),
          Text(
            '₹$_amount Refund',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.bottles.length} bottle${widget.bottles.length == 1 ? '' : 's'} × ₹10',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
    );
  }

  Widget _enterPhoneView() {
    return CenteredScrollView(
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
    );
  }

  Widget _processingView() {
    return CenteredScrollView(
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
          Text('Processing ₹$_amount refund…', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Please do not close the app', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  /// Opens the device's SMS app with the refund confirmation filled in; staff
  /// tap Send there. No SMS gateway is involved, so nothing is sent silently.
  Future<void> _sendSms() async {
    final phone = _customerPhone ?? await _askCustomerPhone();
    if (phone == null || phone.isEmpty) return;

    final count = _result?['count'] ?? widget.bottles.length;
    final amount = _result?['amount'] ?? _amount;
    final reference = _result?['payment_reference'] ?? '';
    final message = 'TASMAC Bottle Return: Rs.$amount refund for $count bottle${count == 1 ? '' : 's'} '
        'has been processed. Ref: $reference. Thank you for recycling!';

    bool launched;
    try {
      launched = await launchUrl(Uri.parse('sms:$phone?body=${Uri.encodeComponent(message)}'));
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    if (launched) {
      setState(() => _smsDone = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No SMS app found on this device.')));
    }
  }

  Future<String?> _askCustomerPhone() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Customer Mobile Number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _successView() {
    return CenteredScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text('Refund Successful!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Bottles: ${_result?['count'] ?? widget.bottles.length}'),
          Text('Amount: ₹${_result?['amount'] ?? _amount}'),
          Text('Reference: ${_result?['payment_reference'] ?? ''}'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _smsDone
                ? OutlinedButton.icon(
                    onPressed: _sendSms,
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    label: const Text('SMS sent — Send Again'),
                  )
                : FilledButton.icon(
                    onPressed: _sendSms,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Send SMS to Customer'),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _smsDone
                  ? () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => HomeScreen(user: widget.user, token: widget.token)),
                        (route) => false,
                      );
                    }
                  : null,
              child: const Text('Done'),
            ),
          ),
          if (!_smsDone)
            TextButton(
              onPressed: () => setState(() => _smsDone = true),
              child: const Text('Skip SMS (customer has no phone)'),
            ),
        ],
      ),
    );
  }

  Widget _failedView() {
    return CenteredScrollView(
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
            'No bottle has been marked as returned.',
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
    );
  }

  Widget _serverUnavailableView() {
    return CenteredScrollView(
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
        ],
      ),
    );
  }
}
