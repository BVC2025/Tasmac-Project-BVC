import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_navigator.dart';
import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../services/geofence_monitor.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../widgets/centered_scroll_view.dart';
import '../widgets/confirm_logout.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Shown right after staff login. Confirms the device is within the shop's
/// geofence before letting the user reach the rest of the app — there is no
/// way to skip past this screen while out of range.
///
/// Rather than trusting the first GPS reading (which on POS terminals without
/// Google location services can be 100 m+ off), it follows the live GPS
/// stream and only decides once a reading is precise enough: in range with a
/// trusted fix, or out of range even after allowing for the GPS error.
class LocationGateScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String token;

  const LocationGateScreen({super.key, required this.user, required this.token});

  @override
  State<LocationGateScreen> createState() => _LocationGateScreenState();
}

enum _GateState { searching, outOfRange, error }

class _LocationGateScreenState extends State<LocationGateScreen> {
  // After this long, accept an in-range fix that is only moderately precise,
  // so a terminal that never gets better than ±100 m indoors isn't stuck.
  static const _relaxAfter = Duration(seconds: 45);
  static const _relaxedAccuracyMeters = 100.0;
  // Don't ask the server more often than this while readings stream in.
  static const _minCheckGap = Duration(seconds: 4);

  final _apiService = ApiService();
  final _started = DateTime.now();

  _GateState _state = _GateState.searching;
  String? _errorMessage;
  String? _serverNote;
  Map<String, dynamic>? _result;
  Position? _fix;
  StreamSubscription<Position>? _subscription;
  Timer? _ticker;
  DateTime? _lastCheck;
  bool _checking = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() {
      _state = _GateState.searching;
      _errorMessage = null;
      _serverNote = null;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state == _GateState.searching) setState(() {});
    });

    try {
      await LocationService.instance.start();
    } catch (e) {
      _fail(e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    await _subscription?.cancel();
    _subscription = LocationService.instance.positions.listen(_onFix);
    if (LocationService.instance.freshFix case final fix?) _onFix(fix);
  }

  void _fail(String message) {
    _subscription?.cancel();
    _ticker?.cancel();
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _state = _GateState.error;
    });
  }

  Future<void> _onFix(Position fix) async {
    if (!mounted || _done) return;
    setState(() => _fix = fix);

    final waited = DateTime.now().difference(_started);
    final usable = fix.accuracy <= LocationService.trustedAccuracyMeters ||
        (waited >= _relaxAfter && fix.accuracy <= _relaxedAccuracyMeters);
    // Very rough readings can still prove "clearly outside", so they are
    // checked too, just not as often.
    final now = DateTime.now();
    if (_checking || (_lastCheck != null && now.difference(_lastCheck!) < _minCheckGap)) return;
    if (!usable && _lastCheck != null && now.difference(_lastCheck!) < const Duration(seconds: 15)) return;

    _checking = true;
    _lastCheck = now;
    try {
      final result = await _apiService.verifyLocation(widget.token, fix.latitude, fix.longitude);
      if (!mounted || _done) return;
      _serverNote = null;

      final distance = (result['distance_meters'] as num).toDouble();
      final radius = (result['radius_meters'] as num).toDouble();

      if (result['within_range'] == true && usable) {
        _proceed(result);
        return;
      }
      setState(() {
        _result = result;
        // Outside even if the reading is off by its full error margin.
        _state = distance - fix.accuracy > radius ? _GateState.outOfRange : _GateState.searching;
      });
    } on ServerUnavailableException {
      if (mounted) setState(() => _serverNote = 'Connecting to the server… (it can take up to a minute to wake up)');
    } on ApiException catch (e) {
      // Outside service hours, no shop assigned, etc. — not a GPS problem.
      _fail(e.message);
    } finally {
      _checking = false;
    }
  }

  void _proceed(Map<String, dynamic> result) {
    _done = true;
    _subscription?.cancel();
    _ticker?.cancel();
    GeofenceMonitor.instance.start(widget.token, appNavigatorKey);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(user: widget.user, token: widget.token, locationInfo: result),
      ),
    );
  }

  Future<void> _logout() async {
    if (!await confirmLogout(context)) return;
    GeofenceMonitor.instance.stop();
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  String _elapsed() {
    final s = DateTime.now().difference(_started).inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Location'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: _logout),
        ],
      ),
      body: CenteredScrollView(
        maxWidth: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_state == _GateState.error) ..._errorView() else ..._searchView(),
          ],
        ),
      ),
    );
  }

  List<Widget> _searchView() {
    final fix = _fix;
    final outside = _state == _GateState.outOfRange;
    final waited = DateTime.now().difference(_started);

    final String headline;
    if (outside) {
      headline = 'You are outside the shop\'s 100 m service area';
    } else if (fix == null) {
      headline = 'Getting your GPS location…';
    } else if (fix.accuracy > LocationService.trustedAccuracyMeters) {
      headline = 'Improving GPS accuracy…';
    } else {
      headline = 'Checking your location…';
    }

    return [
      if (outside)
        const Icon(Icons.location_off, size: 64, color: AppColors.brandRed)
      else
        const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      const SizedBox(height: 20),
      Text(
        headline,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: outside ? AppColors.brandRed : AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 16),
      _InfoRow(label: 'Time', value: _elapsed()),
      _InfoRow(
        label: 'GPS accuracy',
        value: fix == null ? 'waiting for satellites' : '± ${fix.accuracy.round()} m',
        good: fix != null && fix.accuracy <= LocationService.trustedAccuracyMeters,
      ),
      if (_result != null) ...[
        _InfoRow(label: 'Shop', value: '${_result!['shop_name']}'),
        _InfoRow(
          label: 'Distance',
          value: '${_result!['distance_meters']} m (limit ${_result!['radius_meters']} m)',
          good: _result!['within_range'] == true,
        ),
      ],
      if (_serverNote != null) ...[
        const SizedBox(height: 12),
        Text(_serverNote!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
      ],
      const SizedBox(height: 16),
      Text(
        outside
            ? 'Move inside the shop area — this updates automatically.'
            : waited.inSeconds >= 20
                ? 'POS devices can take a few minutes for the first GPS lock. Stand near the shop entrance or a window — this continues automatically.'
                : 'This continues automatically once the location is precise.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    ];
  }

  List<Widget> _errorView() {
    return [
      const Icon(Icons.error_outline, size: 64, color: AppColors.brandRed),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Text(
          _errorMessage ?? 'Could not verify your location.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red.shade700, fontSize: 14),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _begin,
        icon: const Icon(Icons.my_location),
        label: const Text('Retry'),
      ),
    ];
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool? good;

  const _InfoRow({required this.label, required this.value, this.good});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: good == null ? AppColors.textPrimary : (good! ? Colors.green.shade700 : AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
