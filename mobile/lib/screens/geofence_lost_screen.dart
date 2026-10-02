import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../services/geofence_monitor.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';

/// Blocks the entire app when a background check finds the device has moved
/// outside the shop's geofence mid-session. Pops itself automatically once
/// [GeofenceMonitor] detects the device is back in range; "Check Now" lets
/// staff force an immediate re-check instead of waiting for the next tick.
class GeofenceLostScreen extends StatefulWidget {
  static const routeName = '/geofence-lost';

  final Map<String, dynamic> result;

  const GeofenceLostScreen({super.key, required this.result});

  @override
  State<GeofenceLostScreen> createState() => _GeofenceLostScreenState();
}

class _GeofenceLostScreenState extends State<GeofenceLostScreen> {
  bool _checking = false;

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    await GeofenceMonitor.instance.checkNow();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _logout() async {
    GeofenceMonitor.instance.stop();
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.brandRed,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_off, size: 72, color: Colors.white),
                    const SizedBox(height: 20),
                    const Text(
                      'You left the service area',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Shop: ${widget.result['shop_name']}\n'
                      'Distance: ${widget.result['distance_meters']} m (limit ${widget.result['radius_meters']} m)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Return to your shop\'s 100m service area to continue. This checks automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.brandRed),
                      onPressed: _checking ? null : _checkNow,
                      icon: _checking
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandRed),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('Check Now'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _logout,
                      child: const Text('Logout', style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
