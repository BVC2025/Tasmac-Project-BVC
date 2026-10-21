import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'screens/home_screen.dart';
import 'screens/location_gate_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/auth_storage.dart';
import 'services/voice_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

    var user = saved.user;
    try {
      user = await ApiService().getCurrentUser(saved.token);
      await AuthStorage.save(saved.token, user);
    } on ApiException {
      // The backend explicitly rejected the token (expired/invalid) — a
      // fresh login is genuinely required.
      await AuthStorage.clear();
      return const LoginScreen();
    } on ServerUnavailableException {
      // Can't confirm right now — proceed with the cached profile rather
      // than force a surprise logout over a network hiccup.
    }

    final isAdmin = user['role'] == 'admin';
    return isAdmin
        ? HomeScreen(user: user, token: saved.token)
        : LocationGateScreen(user: user, token: saved.token);
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
