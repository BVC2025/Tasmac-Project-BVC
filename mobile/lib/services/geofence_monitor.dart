import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/geofence_lost_screen.dart';
import 'api_service.dart';

/// Runs for the whole staff session (started once the initial geofence gate
/// is passed) and re-checks the device's distance from the assigned shop on
/// a timer, regardless of which screen is currently showing. If a check
/// comes back out of range, it blocks the entire app behind a full-screen
/// notice until the device is back within range — this is what stops staff
/// from walking away mid-scan and still completing a return.
class GeofenceMonitor {
  GeofenceMonitor._();
  static final GeofenceMonitor instance = GeofenceMonitor._();

  static const _checkInterval = Duration(seconds: 20);

  final _apiService = ApiService();
  Timer? _timer;
  String? _token;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _blocked = false;
  bool _checking = false;

  void start(String token, GlobalKey<NavigatorState> navigatorKey) {
    _token = token;
    _navigatorKey = navigatorKey;
    _blocked = false;
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) => _check());
  }

  /// Triggers an immediate check instead of waiting for the next tick —
  /// used by the blocking screen's manual "Check Now" button.
  Future<void> checkNow() => _check();

  void stop() {
    _timer?.cancel();
    _timer = null;
    _token = null;
    _navigatorKey = null;
    _blocked = false;
  }

  Future<void> _check() async {
    if (_checking || _token == null) return;
    _checking = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      final token = _token;
      if (token == null) return;
      final result = await _apiService.verifyLocation(token, position.latitude, position.longitude);

      final withinRange = result['within_range'] == true;
      final navigator = _navigatorKey?.currentState;
      if (navigator == null) return;

      if (!withinRange && !_blocked) {
        _blocked = true;
        navigator.push(
          MaterialPageRoute(
            builder: (_) => GeofenceLostScreen(result: result),
            settings: const RouteSettings(name: GeofenceLostScreen.routeName),
            fullscreenDialog: true,
          ),
        );
      } else if (withinRange && _blocked) {
        _blocked = false;
        if (navigator.canPop()) navigator.pop();
      }
    } catch (_) {
      // A transient GPS/network hiccup shouldn't block the app on its own —
      // the next periodic check will simply try again.
    } finally {
      _checking = false;
    }
  }
}
