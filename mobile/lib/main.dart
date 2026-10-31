import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/location_service.dart';
import 'services/voice_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Both take time on slow terminals, so start them before anything is on
  // screen: the backend may need ~50 s to wake, and a POS GPS receiver
  // without Google location services can need minutes for its first lock.
  // Both warm up while staff are typing their login.
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
      // Every app open starts at login (then the GPS check for staff); no
      // session is resumed automatically.
      home: const LoginScreen(),
    );
  }
}
