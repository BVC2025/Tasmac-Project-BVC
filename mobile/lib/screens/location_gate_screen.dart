import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Shown right after staff login. Confirms the device is within the shop's
/// geofence before letting the user reach the rest of the app — there is no
/// way to skip past this screen while out of range.
class LocationGateScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String token;

  const LocationGateScreen({super.key, required this.user, required this.token});

  @override
  State<LocationGateScreen> createState() => _LocationGateScreenState();
}

enum _GateState { checking, outOfRange, error }

class _LocationGateScreenState extends State<LocationGateScreen> {
  final _apiService = ApiService();

  _GateState _state = _GateState.checking;
  String? _errorMessage;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    setState(() {
      _state = _GateState.checking;
      _errorMessage = null;
      _result = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled on this device');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission was denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is permanently denied. Enable it in device settings.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final result = await _apiService.verifyLocation(widget.token, position.latitude, position.longitude);
      if (!mounted) return;

      if (result['within_range'] == true) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(user: widget.user, token: widget.token, locationInfo: result),
          ),
        );
        return;
      }

      setState(() {
        _result = result;
        _state = _GateState.outOfRange;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _state = _GateState.error;
      });
    }
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_state == _GateState.checking) ...[
                  const CircularProgressIndicator(color: AppColors.primaryGreen),
                  const SizedBox(height: 24),
                  const Text(
                    'Checking your location…',
                    style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                  ),
                ] else ...[
                  Icon(
                    _state == _GateState.error ? Icons.error_outline : Icons.location_off,
                    size: 64,
                    color: AppColors.brandRed,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You must be within your shop\'s 100m service area to continue.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  if (_state == _GateState.error && _errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  if (_state == _GateState.outOfRange && _result != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'Out of range',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Shop: ${_result!['shop_name']}'),
                            Text(
                              'Distance: ${_result!['distance_meters']} m (limit ${_result!['radius_meters']} m)',
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _checkLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
