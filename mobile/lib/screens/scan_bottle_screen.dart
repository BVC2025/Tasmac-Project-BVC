import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../theme/app_colors.dart';
import 'batch_payment_screen.dart';

/// One bottle's final outcome from the batch-scan loop below.
class ScannedBottle {
  final String refundQrCode;
  final String? manufacturingQrCode;
  final String? productBarcode;
  final bool isValid;
  final String? rejectReason;

  const ScannedBottle({
    required this.refundQrCode,
    this.manufacturingQrCode,
    this.productBarcode,
    required this.isValid,
    this.rejectReason,
  });
}

/// A bottle's mutable working state as it moves through the three scanning
/// rounds below: its refund QR is scanned first (round 1, for every bottle in
/// the batch in one continuous pass), then its manufacturing QR is matched
/// (round 2, also one continuous pass), then finally its physical condition
/// is checked (round 3) before the summary.
class _WorkingBottle {
  final String refundQrCode;
  final bool refundValid;
  String? rejectReason;
  String? manufacturingQrCode;
  String? productBarcode;
  bool manufacturingMatched = false;
  bool? conditionGood;

  _WorkingBottle({
    required this.refundQrCode,
    required this.refundValid,
    this.rejectReason,
  });
}

enum _Phase { selectCount, refundRound, manufacturingRound, conditionRound, summary }

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

  _Phase _phase = _Phase.selectCount;
  int _targetCount = 5;
  bool _busy = false;
  String? _lastIgnoredCode;
  double? _latitude;
  double? _longitude;

  final List<_WorkingBottle> _batch = [];
  List<_WorkingBottle> _conditionQueue = [];
  int _conditionIndex = 0;
  _WorkingBottle? _barcodeTarget;

  List<_WorkingBottle> get _pendingManufacturing =>
      _batch.where((b) => b.refundValid && !b.manufacturingMatched).toList();

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
      _phase = _Phase.refundRound;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _bestEffortReject(String refundQrCode, String reason) async {
    try {
      await _apiService.rejectReturn(
        widget.token,
        reason: reason,
        refundQrCode: refundQrCode,
        latitude: _latitude,
        longitude: _longitude,
      );
    } catch (_) {
      // Logging the rejection is best-effort — the bottle still shows as
      // rejected in this session's summary either way.
    }
  }

  // --- Round 1: refund QR, one continuous pass over the whole batch -------

  void _handleRefundRoundDetect(BarcodeCapture capture) {
    if (_busy) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null) return;
    if (_batch.any((b) => b.refundQrCode == code)) return; // already recorded

    _handleRefundScan(code);
  }

  Future<void> _handleRefundScan(String code) async {
    setState(() => _busy = true);

    try {
      await _ensureLocation();
      await _apiService.verifyRefundQr(
        widget.token,
        refundQrCode: code,
        latitude: _latitude!,
        longitude: _longitude!,
      );
      setState(() {
        _batch.add(_WorkingBottle(refundQrCode: code, refundValid: true));
        _busy = false;
      });
      VoiceService.instance.speak(VoiceMessage.refundVerified);
    } on ServerUnavailableException {
      _showSnack('Server unavailable — try scanning this bottle again.');
      setState(() => _busy = false);
      return;
    } on ApiException catch (e) {
      final message = e.toString();
      final reason = message.toLowerCase().contains('already been') ? 'qr_already_used' : 'refund_qr_invalid';
      setState(() {
        _batch.add(_WorkingBottle(refundQrCode: code, refundValid: false, rejectReason: reason));
        _busy = false;
      });
      await _bestEffortReject(code, reason);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
      return;
    }

    if (_batch.length >= _targetCount) _finishRefundRound();
  }

  void _finishRefundRound() {
    setState(() => _phase = _Phase.manufacturingRound);
    if (_pendingManufacturing.isEmpty) _finishManufacturingRound();
  }

  // --- Round 2: manufacturing QR, matched against round 1's batch ---------

  void _handleManufacturingRoundDetect(BarcodeCapture capture) {
    if (_busy) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null) return;
    if (_batch.any((b) => b.manufacturingQrCode == code)) return; // already matched

    _handleManufacturingScan(code);
  }

  Future<void> _handleManufacturingScan(String code) async {
    if (_barcodeTarget != null) {
      final target = _barcodeTarget!;
      setState(() {
        target.productBarcode = code;
        target.manufacturingMatched = true;
        _barcodeTarget = null;
      });
      if (_pendingManufacturing.isEmpty) _finishManufacturingRound();
      return;
    }

    setState(() => _busy = true);

    try {
      final result = await _apiService.lookupManufacturingQr(widget.token, manufacturingQrCode: code);
      final refundCode = result['refund_qr_code'] as String;

      _WorkingBottle? match;
      for (final b in _batch) {
        if (b.refundQrCode == refundCode && b.refundValid && !b.manufacturingMatched) {
          match = b;
          break;
        }
      }

      if (match == null) {
        setState(() => _busy = false);
        if (code != _lastIgnoredCode) {
          _lastIgnoredCode = code;
          _showSnack("This manufacturing QR doesn't match any pending bottle in this batch.");
        }
        return;
      }

      setState(() {
        match!.manufacturingQrCode = code;
        match.manufacturingMatched = true;
        _busy = false;
        _lastIgnoredCode = null;
      });
      VoiceService.instance.speak(VoiceMessage.manufacturingVerified);
      if (_pendingManufacturing.isEmpty) _finishManufacturingRound();
    } on ServerUnavailableException {
      _showSnack('Server unavailable — try scanning this code again.');
      setState(() => _busy = false);
    } on ApiException {
      setState(() => _busy = false);
      if (code != _lastIgnoredCode) {
        _lastIgnoredCode = code;
        _showSnack('Unrecognized manufacturing QR.');
      }
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
    }
  }

  Future<void> _pickBarcodeTarget() async {
    final pending = _pendingManufacturing;
    final chosen = await showModalBottomSheet<_WorkingBottle>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Which bottle has no manufacturing QR?', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final b in pending)
              ListTile(
                title: Text('Bottle ${_batch.indexOf(b) + 1}'),
                subtitle: Text(b.refundQrCode),
                onTap: () => Navigator.of(context).pop(b),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _barcodeTarget = chosen);
  }

  Future<void> _finishManufacturingRoundEarly() async {
    for (final b in _pendingManufacturing) {
      b.rejectReason = 'manufacturing_qr_invalid';
      await _bestEffortReject(b.refundQrCode, 'manufacturing_qr_invalid');
    }
    _finishManufacturingRound();
  }

  void _finishManufacturingRound() {
    setState(() {
      _conditionQueue = _batch.where((b) => b.refundValid && b.manufacturingMatched).toList();
      _conditionIndex = 0;
      _phase = _Phase.conditionRound;
    });
    if (_conditionQueue.isEmpty) _goToSummary();
  }

  // --- Round 3: physical condition check, one bottle at a time ------------

  Future<void> _condition(bool isGood) async {
    final bottle = _conditionQueue[_conditionIndex];
    bottle.conditionGood = isGood;
    if (!isGood) {
      await _bestEffortReject(bottle.refundQrCode, 'bottle_physically_damaged');
    }
    setState(() => _conditionIndex++);
    if (_conditionIndex >= _conditionQueue.length) _goToSummary();
  }

  void _goToSummary() {
    setState(() => _phase = _Phase.summary);
  }

  List<ScannedBottle> get _results => _batch.map((b) {
        if (!b.refundValid) {
          return ScannedBottle(refundQrCode: b.refundQrCode, isValid: false, rejectReason: b.rejectReason);
        }
        if (!b.manufacturingMatched) {
          return ScannedBottle(refundQrCode: b.refundQrCode, isValid: false, rejectReason: 'manufacturing_qr_invalid');
        }
        if (b.conditionGood == false) {
          return ScannedBottle(refundQrCode: b.refundQrCode, isValid: false, rejectReason: 'bottle_physically_damaged');
        }
        return ScannedBottle(
          refundQrCode: b.refundQrCode,
          manufacturingQrCode: b.manufacturingQrCode,
          productBarcode: b.productBarcode,
          isValid: true,
        );
      }).toList();

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
        _Phase.refundRound => _buildRefundRoundView(),
        _Phase.manufacturingRound => _buildManufacturingRoundView(),
        _Phase.conditionRound => _conditionView(),
        _Phase.summary => _buildSummaryView(),
      },
    );
  }

  String _titleFor(_Phase phase) => switch (phase) {
        _Phase.selectCount => 'Scan Bottle to Return',
        _Phase.refundRound => 'Refund QR — ${_batch.length} of $_targetCount',
        _Phase.manufacturingRound =>
          'Manufacturing QR — ${_batch.where((b) => b.refundValid).length - _pendingManufacturing.length} of ${_batch.where((b) => b.refundValid).length}',
        _Phase.conditionRound => 'Condition Check',
        _Phase.summary => 'Scan Summary',
      };

  Widget _buildRefundRoundView() {
    final valid = _batch.where((b) => b.refundValid).length;
    final rejected = _batch.where((b) => !b.refundValid).length;

    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _handleRefundRoundDetect),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Scanned ${_batch.length} of $_targetCount  •  $valid valid  •  $rejected rejected',
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (_busy)
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Scan the REFUND QR code (top of bottle) — one bottle after another',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                if (_batch.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                    onPressed: _finishRefundRound,
                    child: const Text('Done Scanning Refund QRs'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManufacturingRoundView() {
    final pending = _pendingManufacturing;
    final matched = _batch.where((b) => b.refundValid).length - pending.length;
    final total = _batch.where((b) => b.refundValid).length;

    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _handleManufacturingRoundDetect),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Matched $matched of $total',
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (_busy)
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _barcodeTarget != null
                      ? "Scan Bottle ${_batch.indexOf(_barcodeTarget!) + 1}'s BARCODE"
                      : 'Scan the MANUFACTURING QR — any order',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                if (_barcodeTarget == null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                    onPressed: _pickBarcodeTarget,
                    child: const Text('No Manufacturing QR — Scan Barcode'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                    onPressed: _finishManufacturingRoundEarly,
                    child: const Text('Finish Matching'),
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
    final position = _conditionIndex + 1;
    final total = _conditionQueue.length;
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
              Text(
                'Bottle $position of $total — codes verified ✓',
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
        ),
      ),
    );
  }

  Widget _buildSummaryView() {
    final results = _results;
    final validBottles = results.where((b) => b.isValid).toList();
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
            itemCount: results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final bottle = results[index];
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

  void _set(int value) => setState(() => _count = value.clamp(1, 50));

  @override
  Widget build(BuildContext context) {
    const presets = [1, 3, 5, 10];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
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
        ),
      ),
    );
  }
}
