import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Keeps one GPS session running for the whole staff session and remembers
/// the latest fix, instead of every screen asking for a fresh one-off fix.
///
/// On a normal phone a one-off fix takes seconds (Google's fused location
/// uses Wi-Fi/cell/assisted GPS). POS terminals such as Pine Labs devices
/// have no Google Play Services, so they fall back to raw satellite GPS: the
/// first lock can take minutes and the first readings can be 100 m+ off.
/// Keeping the receiver running means that slow first lock happens once, and
/// every later check (geofence monitor, scanning) reuses a warm, accurate fix.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// A fix at least this accurate is trusted for an in/out-of-range decision.
  static const trustedAccuracyMeters = 50.0;

  /// A fix older than this is not reused.
  static const maxFixAge = Duration(minutes: 2);

  final _positions = StreamController<Position>.broadcast();
  StreamSubscription<Position>? _subscription;
  Position? _latest;

  Stream<Position> get positions => _positions.stream;

  /// The most recent fix, if it is still fresh.
  Position? get freshFix {
    final fix = _latest;
    if (fix == null || DateTime.now().difference(fix.timestamp) > maxFixAge) return null;
    return fix;
  }

  /// The most recent fresh fix that is accurate enough to decide on.
  Position? get trustedFix {
    final fix = freshFix;
    return fix != null && fix.accuracy <= trustedAccuracyMeters ? fix : null;
  }

  /// Throws an [Exception] with a staff-readable message when location can't
  /// be used. Only prompts for permission when [requestIfNeeded] is true.
  Future<void> ensureAvailable({bool requestIfNeeded = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location is turned off. Turn on Location in the device settings.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfNeeded) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission was denied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is permanently denied. Enable it in device settings.');
    }
  }

  /// Starts the GPS session if it isn't running. Safe to call repeatedly.
  Future<void> start({bool requestIfNeeded = true}) async {
    await ensureAvailable(requestIfNeeded: requestIfNeeded);
    if (_subscription != null) return;

    // Seed with the device's last fix so an already-warm GPS answers at once.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _accept(last);
    } catch (_) {}

    _subscription = Geolocator.getPositionStream(locationSettings: _settings()).listen(
      _accept,
      onError: (Object _) {
        // Receiver hiccup — drop the stream so the next start() reopens it.
        _subscription?.cancel();
        _subscription = null;
      },
    );
  }

  /// Starts GPS early (e.g. at app launch) when permission was already given,
  /// so the receiver is warming up while staff log in. Never prompts.
  Future<void> warmUp() async {
    try {
      await start(requestIfNeeded: false);
    } catch (_) {}
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _latest = null;
  }

  /// Waits for a trusted fix, up to [timeout]; returns the best fix seen if
  /// none was trusted in time, or null if there was no fix at all.
  Future<Position?> waitForTrustedFix(Duration timeout) async {
    await start();
    if (trustedFix case final fix?) return fix;

    Position? best = freshFix;
    final completer = Completer<Position?>();
    late final StreamSubscription<Position> sub;
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(best);
    });
    sub = positions.listen((fix) {
      if (best == null || fix.accuracy < best!.accuracy) best = fix;
      if (fix.accuracy <= trustedAccuracyMeters && !completer.isCompleted) completer.complete(fix);
    });
    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  void _accept(Position fix) {
    _latest = fix;
    _positions.add(fix);
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 2),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);
  }
}
