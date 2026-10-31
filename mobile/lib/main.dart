import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'screens/home_screen.dart';
import 'screens/location_gate_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/auth_storage.dart';
import 'services/geofence_monitor.dart';
import 'services/location_service.dart';
import 'services/voice_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Both take time on slow terminals, so start them before anything is on
  // screen: the backend may need ~50 s to wake, and a POS GPS receiver
  // without Google location services can need minutes for its first lock.
  ApiService().wakeUpServer();
  LocationService.instance.warmUp();
  await VoiceService.instance.loadSavedLanguage();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'TASMAC Bottle Return',
      theme: buildAppTheme(),
      // Android 15+ draws apps edge-to-edge, so without this the system
      // navigation bar covers every screen's bottom button (e.g. the scan
      // summary's payment button).
      builder: (context, child) => ColoredBox(
        color: AppColors.background,
        child: SafeArea(top: false, child: child!),
      ),
      home: const _SessionGate(),
    );
  }
}

/// Restores a saved login on launch so staff/admin aren't sent back to the
/// login screen every time they close and reopen the app — only when they
/// explicitly log out, or the saved token has actually expired.
///
/// The saved profile is used straight away; the token is re-checked in the
/// background. Waiting for that check first made the app take minutes to
/// open whenever the backend was asleep.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<Widget> _destination = _resolve();

  Future<Widget> _resolve() async {
    final saved = await AuthStorage.load();
    if (saved == null) return const LoginScreen();

    _revalidate(saved.token);

    final user = saved.user;
    final isAdmin = user['role'] == 'admin';
    return isAdmin
        ? HomeScreen(user: user, token: saved.token)
        : LocationGateScreen(user: user, token: saved.token);
  }

  Future<void> _revalidate(String token) async {
    try {
      final user = await ApiService().getCurrentUser(token);
      await AuthStorage.save(token, user);
    } on ApiException catch (e) {
      // Only an explicit rejection of the token (expired/invalid/inactive)
      // means a fresh login is genuinely required.
      if (e.statusCode != 401 && e.statusCode != 403) return;
      await AuthStorage.clear();
      GeofenceMonitor.instance.stop();
      appNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on ServerUnavailableException {
      // Can't confirm right now — keep the cached session rather than force
      // a surprise logout over a network hiccup.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destination,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data!;
      },
    );
  }
}
