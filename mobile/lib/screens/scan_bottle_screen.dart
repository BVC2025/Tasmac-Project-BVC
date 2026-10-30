import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../theme/app_colors.dart';
import '../widgets/centered_scroll_view.dart';
import 'batch_payment_screen.dart';
import 'reject_bottle_screen.dart';

/// One bottle's outcome from the batch-scan loop below.
class ScannedBottle {
  final String refundQrCode;
  final String? manufacturingQrCode;
  final bool isValid;
  final String? rejectReason;

  const ScannedBottle({
    required this.refundQrCode,
    this.manufacturingQrCode,
    required this.isValid,
    this.rejectReason,
  });
}

enum _Phase { selectCount, scanning, summary }

// Within the scanning phase, each bottle goes refund QR -> manufacturing QR
// -> condition. A bottle is only valid when BOTH of its QRs verify.
enum _ScanStep { refund, second, condition, busy }

/// Upper bound for one customer's batch; the backend enforces the same limit.
const maxBottlesPerBatch = 20;

/// How long each scanned QR shows "Checking QR…" before its valid/invalid
/// result appears.
const scanResultDelay = Duration(seconds: 5);

class ScanBottleScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const ScanBottleScreen({super.key, required this.token, required this.user});

  @override
  State<ScanBottleScreen> createState() => _ScanBottleScreenState();
}

class _ScanBottleScreenState extends State<ScanBottleScreen> {
  final _apiService = ApiService();
  // Our bottle codes are always QR codes; ignoring every other symbology means
  // product barcodes, price stickers etc. in frame are never even reported.
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  _Phase _phase = _Phase.selectCount;
  int _targetCount = 5;

  _ScanStep _scanStep = _ScanStep.refund;
  String? _pendingRefundCode;
  String? _pendingManufacturingCode;
  String? _lastIgnoredCode;
  double? _latitude;
  double? _longitude;

  final List<ScannedBottle> _results = [];

  // The whole batch is scanned from one spot at the counter, so the GPS fix
  // only needs to happen once per session — every bottle after the first
  // reuses it instead of paying for a fresh (and occasionally slow or
  // indoors-unreliable) high-accuracy fix each time.
  Future<void> _ensureLocation() async {
    if (_latitude != null && _longitude != null) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services are disabled');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to process a return');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      _latitude = position.latitude;
      _longitude = position.longitude;
    } on TimeoutException {
      throw Exception('Could not get a GPS fix — move to an open area and try again');
    }
  }

  void _startScanning(int count) {
    setState(() {
      _targetCount = count;
      _phase = _Phase.scanning;
    });
  }

  /// Runs [verification] but only completes once [scanResultDelay] has passed,
  /// so staff see a steady "Checking QR…" instead of an instant verdict that
  /// can flash past while the bottle is still being positioned.
  Future<T> _holdForResult<T>(Future<T> verification) async {
    final hold = Future<void>.delayed(scanResultDelay);
    try {
      final result = await verification;
      await hold;
      return result;
    } catch (_) {
      await hold;
      rethrow;
    }
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_scanStep == _ScanStep.busy) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null) return;

    if (_scanStep == _ScanStep.refund) {
      _handleRefundDetect(code);
    } else if (_scanStep == _ScanStep.second) {
      if (code == _pendingRefundCode) return; // still the same code in frame
      _handleSecondDetect(code);
    }
  }

  Future<void> _handleRefundDetect(String code) async {
    // Only our own refund QRs count. Any other QR in frame (a manufacturing
    // QR, a UPI sticker, an unrelated code) is ignored — the camera keeps
    // waiting — instead of being sent to the server and rejecting the bottle.
    if (!code.startsWith('TSM-R-')) {
      if (code != _lastIgnoredCode) {
        _lastIgnoredCode = code;
        _showSnack(code.startsWith('TSM-M-')
            ? 'That is the MANUFACTURING QR — scan the REFUND QR (front of bottle) first.'
            : 'Not a TASMAC refund QR — ignored. Scan the REFUND QR on the bottle.');
      }
      return;
    }

    // One QR, one refund: the backend still sees this bottle as unused until
    // the batch is paid, so a repeat scan within the batch must be caught here.
    if (_results.any((b) => b.refundQrCode == code)) {
      if (code != _lastIgnoredCode) {
        _lastIgnoredCode = code;
        _showSnack('This refund QR was already scanned in this batch — scan the next bottle.');
      }
      return;
    }

    setState(() => _scanStep = _ScanStep.busy);

    try {
      await _ensureLocation();

      await _holdForResult(_apiService.verifyRefundQr(
        widget.token,
        refundQrCode: code,
        latitude: _latitude!,
        longitude: _longitude!,
      ));

      setState(() {
        _pendingRefundCode = code;
        _scanStep = _ScanStep.second;
      });
      VoiceService.instance.speak(VoiceMessage.refundVerified);
    } on ServerUnavailableException {
      _showSnack('Server unavailable — try scanning this bottle again.');
      setState(() => _scanStep = _ScanStep.refund);
    } on ApiException catch (e) {
      // Only an unknown (404) or already-used (409) code says anything about
      // the bottle. Anything else — outside service hours, outside the
      // geofence, no shop assigned — is about the staff/shop, so show the
      // real reason and let them scan this same bottle again instead of
      // wrongly marking a genuine QR as invalid.
      if (e.statusCode != 404 && e.statusCode != 409) {
        _showSnack(e.message);
        setState(() => _scanStep = _ScanStep.refund);
        return;
      }
      // Scanning the wrong or an already-used QR is a scan mistake, not a
      // customer decision — it's recorded in this session's summary only,
      // never sent to the backend as a real rejection.
      final reason = e.statusCode == 409 ? 'qr_already_used' : 'refund_qr_invalid';
      _finishBottle(ScannedBottle(refundQrCode: code, isValid: false, rejectReason: reason));
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _scanStep = _ScanStep.refund);
    }
  }

  // Any code not starting with our manufacturing-QR prefix (a stray code
  // from a neighbouring bottle, or a refund QR) is flagged once, not every
  // frame, and the camera keeps waiting for the real one — never silently
  // ignored, so staff who scan the wrong bottle or jump ahead see why nothing
  // happened. A bottle with no manufacturing QR at all is rejected via the
  // "No Manufacturing QR" button, since both QRs are required.
  Future<void> _handleSecondDetect(String code) async {
    if (!code.startsWith('TSM-M-')) {
      if (code != _lastIgnoredCode) {
        _lastIgnoredCode = code;
        _showSnack("That's not this bottle's manufacturing QR. Scan the MANUFACTURING QR of the bottle you just verified — or tap \"No Manufacturing QR — Reject\" below.");
      }
      return;
    }
    _lastIgnoredCode = null;

    setState(() => _scanStep = _ScanStep.busy);

    try {
      await _holdForResult(_apiService.verifyManufacturingQr(
        widget.token,
        refundQrCode: _pendingRefundCode!,
        manufacturingQrCode: code,
      ));
      setState(() {
        _pendingManufacturingCode = code;
        _scanStep = _ScanStep.condition;
      });
      VoiceService.instance.speak(VoiceMessage.manufacturingVerified);
    } on ServerUnavailableException {
      _showSnack('Server unavailable — try scanning this bottle again.');
      setState(() => _scanStep = _ScanStep.second);
    } on ApiException catch (e) {
      if (e.statusCode != 400 && e.statusCode != 404) {
        _showSnack(e.message);
        setState(() => _scanStep = _ScanStep.second);
        return;
      }
      // Same as an invalid refund QR: a mismatched code is a scan mistake,
      // recorded locally only — not sent to the backend as a rejection.
      _finishBottle(ScannedBottle(
        refundQrCode: _pendingRefundCode!,
        isValid: false,
        rejectReason: 'manufacturing_qr_invalid',
      ));
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _scanStep = _ScanStep.second);
    }
  }

  void _rejectMissingManufacturingQr() {
    _finishBottle(ScannedBottle(
      refundQrCode: _pendingRefundCode!,
      isValid: false,
      rejectReason: 'manufacturing_qr_missing',
    ));
  }

  Future<void> _condition(bool isGood) async {
    if (isGood) {
      _finishBottle(ScannedBottle(
        refundQrCode: _pendingRefundCode!,
        manufacturingQrCode: _pendingManufacturingCode,
        isValid: true,
      ));
      return;
    }

    // A physically damaged bottle is a genuine, staff-confirmed rejection —
    // unlike a bad scan, this one needs a reason, remarks, and evidence photo
    // and is submitted straight to the backend from that screen.
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RejectBottleScreen(
          token: widget.token,
          refundQrCode: _pendingRefundCode,
          latitude: _latitude,
          longitude: _longitude,
          initialReason: 'bottle_physically_damaged',
        ),
      ),
    );
    if (submitted != true) return; // staff backed out — stay on this bottle

    _finishBottle(ScannedBottle(
      refundQrCode: _pendingRefundCode!,
      isValid: false,
      rejectReason: 'bottle_physically_damaged',
    ));
  }

  void _finishBottle(ScannedBottle result) {
    setState(() {
      _results.add(result);
      _pendingRefundCode = null;
      _pendingManufacturingCode = null;
      _lastIgnoredCode = null;
      _scanStep = _ScanStep.refund;
    });

    if (_results.length >= _targetCount) {
      _goToSummary();
    }
  }

  void _goToSummary() {
    setState(() => _phase = _Phase.summary);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _proceedToPayment() {
    final validBottles = _results.where((b) => b.isValid).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BatchPaymentScreen(
          token: widget.token,
          bottles: validBottles,
          latitude: _latitude!,
          longitude: _longitude!,
          user: widget.user,
        ),
      ),
    );
    // On success BatchPaymentScreen replaces the whole stack itself; on
    // failure/cancel it just pops back here, to the same summary, to retry.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titleFor(_phase))),
      body: switch (_phase) {
        _Phase.selectCount => _CountSelectView(onStart: _startScanning),
        _Phase.scanning => _buildScanningView(),
        _Phase.summary => _buildSummaryView(),
      },
    );
  }

  String _titleFor(_Phase phase) => switch (phase) {
        _Phase.selectCount => 'Scan Bottle to Return',
        _Phase.scanning => 'Scanning — ${_results.length} of $_targetCount',
        _Phase.summary => 'Scan Summary',
      };

  Widget _buildScanningView() {
    if (_scanStep == _ScanStep.condition) {
      return _conditionView();
    }

    final verifiedBanners = [
      if (_pendingRefundCode != null) 'Refund QR verified ✓',
    ];
    final String instruction;
    if (_scanStep == _ScanStep.second) {
      instruction = 'Scan the MANUFACTURING QR of this same bottle';
    } else {
      instruction = 'Scan the REFUND QR code (top of bottle)';
    }

    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _handleDetect),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  'Bottle ${_results.length + 1} of $_targetCount  •  ${_results.where((b) => b.isValid).length} valid  •  ${_results.where((b) => !b.isValid).length} rejected',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              for (final banner in verifiedBanners)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(10)),
                    child: Text(banner, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
        ),
        if (_scanStep == _ScanStep.busy)
          Container(
            color: Colors.black45,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Checking QR… hold the bottle steady',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            color: Colors.black54,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  instruction,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                if (_scanStep == _ScanStep.second) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                    onPressed: _rejectMissingManufacturingQr,
                    child: const Text('No Manufacturing QR — Reject'),
                  ),
                ],
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                    onPressed: _goToSummary,
                    child: const Text('Finish Now'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _conditionView() {
    return CenteredScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fact_check_outlined, size: 56, color: AppColors.primaryGreen),
          const SizedBox(height: 12),
          Text(
            'Bottle ${_results.length + 1} — codes verified ✓',
            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
          ),
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
            onPressed: () => _condition(true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Good — Add to Refund'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.brandRed),
            onPressed: () => _condition(false),
            icon: const Icon(Icons.report_gmailerrorred_outlined),
            label: const Text('Damaged — Reject'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryView() {
    final validBottles = _results.where((b) => b.isValid).toList();
    final total = validBottles.length * 10;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: _SummaryStat(label: 'VALID BOTTLES', value: '${validBottles.length}', color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryStat(label: 'TOTAL REFUND', value: '₹$total', color: const Color(0xFFA9672B)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final bottle = _results[index];
              return ListTile(
                leading: Icon(
                  bottle.isValid ? Icons.check_circle : Icons.cancel,
                  color: bottle.isValid ? Colors.green : AppColors.brandRed,
                ),
                title: Text('Bottle ${index + 1}'),
                subtitle: Text(
                  bottle.isValid ? bottle.refundQrCode : (bottle.rejectReason ?? 'rejected').replaceAll('_', ' '),
                ),
                trailing: Text(bottle.isValid ? '₹10' : '—'),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: validBottles.isEmpty ? null : _proceedToPayment,
              child: Text(
                validBottles.isEmpty ? 'No valid bottles to pay out' : 'Proceed to Payment — ₹$total',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _CountSelectView extends StatefulWidget {
  final void Function(int count) onStart;

  const _CountSelectView({required this.onStart});

  @override
  State<_CountSelectView> createState() => _CountSelectViewState();
}

class _CountSelectViewState extends State<_CountSelectView> {
  int _count = 1;

  void _set(int value) => setState(() => _count = value.clamp(1, maxBottlesPerBatch));

  @override
  Widget build(BuildContext context) {
    const presets = [1, 5, 10, maxBottlesPerBatch];

    return CenteredScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: AppColors.accentGreen.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.liquor_outlined, color: AppColors.primaryGreen, size: 28),
          ),
          const SizedBox(height: 18),
          const Text('How many bottles?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            "Ask the customer how many empty bottles they're returning today.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Text(
            '$_count',
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.primaryGreen),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filled(onPressed: () => _set(_count - 1), icon: const Icon(Icons.remove)),
              const SizedBox(width: 20),
              IconButton.filled(onPressed: () => _set(_count + 1), icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final preset in presets)
                ChoiceChip(
                  label: Text('$preset'),
                  selected: _count == preset,
                  onSelected: (_) => _set(preset),
                ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onStart(_count),
              child: Text('Start Scanning ($_count)'),
            ),
          ),
        ],
      ),
    );
  }
}
