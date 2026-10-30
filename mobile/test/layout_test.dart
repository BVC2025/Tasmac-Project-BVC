// Renders every screen across a matrix of real-world device sizes, system
// font scales and an open keyboard, failing on any RenderFlex overflow (the
// yellow/black striped "BOTTOM OVERFLOWED BY n PIXELS" bar on a device).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tasmac_bottle_return/screens/add_shop_screen.dart';
import 'package:tasmac_bottle_return/screens/add_staff_screen.dart';
import 'package:tasmac_bottle_return/screens/batch_payment_screen.dart';
import 'package:tasmac_bottle_return/screens/geofence_lost_screen.dart';
import 'package:tasmac_bottle_return/screens/home_screen.dart';
import 'package:tasmac_bottle_return/screens/location_gate_screen.dart';
import 'package:tasmac_bottle_return/screens/login_screen.dart';
import 'package:tasmac_bottle_return/screens/password_requests_screen.dart';
import 'package:tasmac_bottle_return/screens/refund_history_screen.dart';
import 'package:tasmac_bottle_return/screens/reject_bottle_screen.dart';
import 'package:tasmac_bottle_return/screens/reject_history_screen.dart';
import 'package:tasmac_bottle_return/screens/return_detail_screen.dart';
import 'package:tasmac_bottle_return/screens/scan_bottle_screen.dart';
import 'package:tasmac_bottle_return/screens/shop_list_screen.dart';
import 'package:tasmac_bottle_return/screens/staff_list_screen.dart';
import 'package:tasmac_bottle_return/theme/app_theme.dart';

const _devices = <String, Size>{
  'handheld 320x568': Size(320, 568),
  'phone 360x640': Size(360, 640),
  'phone 393x851': Size(393, 851),
  'phone 412x915': Size(412, 915),
  'landscape 640x360': Size(640, 360),
  'tablet 800x1280': Size(800, 1280),
};
const _textScales = [1.0, 1.3, 1.6];

final _staffUser = <String, dynamic>{
  'id': 2,
  'full_name': 'Murugan Selvaraj Krishnamoorthy',
  'user_id': 'STAFF001',
  'role': 'staff',
  'shop_name': 'TASMAC Outlet 4521 — Anna Nagar West Extension',
  'has_photo': false,
};
final _adminUser = <String, dynamic>{..._staffUser, 'id': 1, 'role': 'admin', 'user_id': 'ADMIN'};
final _locationInfo = <String, dynamic>{
  'distance_meters': 42,
  'shop_name': 'TASMAC Outlet 4521 — Anna Nagar West Extension',
};
final _returnItem = <String, dynamic>{
  'id': 7,
  'status': 'rejected',
  'qr_code': 'TSM-R-5327cf65',
  'product_barcode': '8901234567890',
  'created_at': '2026-10-21T10:15:00Z',
  'shop_name': 'TASMAC Outlet 4521 — Anna Nagar West Extension',
  'distance_meters': 12,
  'rejection_reason': 'bottle_broken_cracked',
  'remarks': 'Neck cracked, customer informed and bottle kept aside for disposal.',
  'has_evidence_image': true,
};

http.Client _fakeBackend() => MockClient((request) async {
      final path = request.url.path;
      Object body;
      if (path == '/returns/mine') {
        body = [
          for (var i = 0; i < 12; i++)
            {
              ..._returnItem,
              'id': i,
              'status': i.isEven ? 'verified' : 'rejected',
              'payment_amount': 10,
              // The first few are from today, so the home stats aren't empty.
              if (i < 4) 'created_at': DateTime.now().toUtc().toIso8601String(),
            },
        ];
      } else if (path == '/shops') {
        body = [
          for (var i = 0; i < 8; i++)
            {
              'id': i,
              'name': 'TASMAC Outlet 45$i Anna Nagar West',
              'shop_code': 'TN-CHN-45$i',
              'address': '12, 3rd Main Road, Anna Nagar West Extension, Chennai 600101',
              'is_active': i != 3,
              'service_start_time': '10:00:00',
              'service_end_time': '22:00:00',
            },
        ];
      } else if (path == '/staff/password-reset-requests') {
        body = [
          for (var i = 0; i < 3; i++)
            {
              'staff': {
                'id': i,
                'full_name': 'Murugan Selvaraj Krishnamoorthy $i',
                'user_id': 'STAFF00$i',
                'phone_number': '98765432$i$i',
                'shop_name': 'TASMAC Outlet 4521 — Anna Nagar West Extension',
              },
              'requested_at': '2026-10-21T10:15:00Z',
              'message': 'Forgot my password after the phone was reset, please help.',
            },
        ];
      } else if (path == '/staff') {
        body = [
          for (var i = 0; i < 8; i++)
            {
              'id': i,
              'full_name': 'Murugan Selvaraj Krishnamoorthy $i',
              'user_id': 'STAFF00$i',
              'phone_number': '98765432$i$i',
              'role': i == 0 ? 'admin' : 'staff',
              'is_active': i != 4,
              'has_photo': false,
            },
        ];
      } else {
        return http.Response(jsonEncode({'detail': 'Payment gateway declined the request'}), 400);
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });

class _Case {
  final String name;
  final WidgetBuilder builder;
  final bool keyboard;

  /// Optional interaction to reach a deeper state of the screen.
  final Future<void> Function(WidgetTester tester)? drive;

  const _Case(this.name, this.builder, {this.keyboard = false, this.drive});
}

/// Scrolls [text] into view first — on short screens it may sit below the fold.
Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
}

final _cases = <_Case>[
  _Case('Login', (_) => const LoginScreen()),
  _Case('Login + keyboard', (_) => const LoginScreen(), keyboard: true),
  _Case('Home (staff)', (_) => HomeScreen(user: _staffUser, token: 't', locationInfo: _locationInfo)),
  _Case('Home (admin)', (_) => HomeScreen(user: _adminUser, token: 't')),
  _Case('Location gate (error)', (_) => LocationGateScreen(user: _staffUser, token: 't')),
  _Case('Geofence lost', (_) => GeofenceLostScreen(result: _locationInfo..['radius_meters'] = 100)),
  _Case('Scan: choose count', (_) => ScanBottleScreen(token: 't', user: _staffUser)),
  _Case(
    'Payment: choose method',
    (_) => BatchPaymentScreen(token: 't', bottles: const [], latitude: 0, longitude: 0, user: _staffUser),
  ),
  _Case(
    'Payment: enter phone + keyboard',
    (_) => BatchPaymentScreen(token: 't', bottles: const [], latitude: 0, longitude: 0, user: _staffUser),
    keyboard: true,
    drive: (tester) async {
      await _tapText(tester, 'No — Enter Phone Number');
      await tester.pumpAndSettle();
    },
  ),
  _Case(
    'Payment: failed',
    (_) => BatchPaymentScreen(token: 't', bottles: const [], latitude: 0, longitude: 0, user: _staffUser),
    drive: (tester) async {
      await _tapText(tester, 'No — Enter Phone Number');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '9876543210');
      await _tapText(tester, 'Proceed with Refund');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    },
  ),
  _Case('Reject bottle', (_) => const RejectBottleScreen(token: 't')),
  _Case('Return detail', (_) => ReturnDetailScreen(item: _returnItem, token: 't')),
  _Case('Refund history', (_) => const RefundHistoryScreen(token: 't')),
  _Case('Reject history', (_) => const RejectHistoryScreen(token: 't')),
  _Case('Shop list', (_) => const ShopListScreen(token: 't')),
  _Case('Staff list', (_) => const StaffListScreen(token: 't')),
  _Case('Password requests', (_) => const PasswordRequestsScreen(token: 't')),
  _Case('Add shop', (_) => const AddShopScreen(token: 't')),
  _Case('Add shop + keyboard', (_) => const AddShopScreen(token: 't'), keyboard: true),
  _Case('Add staff', (_) => const AddStaffScreen(token: 't')),
];

// The test framework's default font draws every glyph as a wide square, which
// reports overflows no real device would show — load the Roboto that Android
// actually renders with, straight from the Flutter SDK.
Future<void> _loadRealFonts() async {
  final fonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    final bytes = File('$fonts/roboto-$weight.ttf').readAsBytesSync();
    roboto.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$fonts/materialicons-regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  setUpAll(_loadRealFonts);

  for (final c in _cases) {
    for (final device in _devices.entries) {
      for (final scale in _textScales) {
        testWidgets('${c.name} — ${device.key} @ ${scale}x text', (tester) async {
          await http.runWithClient(() async {
            final overflows = <String>[];
            final previousOnError = FlutterError.onError;
            FlutterError.onError = (details) {
              final text = details.exceptionAsString();
              if (text.contains('overflowed')) {
                final where = RegExp(r'lib/screens/[\w.]+:\d+').firstMatch(details.toString())?.group(0) ?? '?';
                overflows.add('${text.split('\n').first} ($where)');
              } else {
                previousOnError?.call(details);
              }
            };
            addTearDown(() => FlutterError.onError = previousOnError);

            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = device.value;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            if (c.keyboard) {
              tester.view.viewInsets = FakeViewPadding(bottom: device.value.height * 0.42);
            }
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearAllTestValues);

            await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Builder(builder: c.builder)));
            await tester.pump(const Duration(milliseconds: 100));
            await tester.pump(const Duration(milliseconds: 100));
            if (c.drive != null) await c.drive!(tester);

            FlutterError.onError = previousOnError;
            expect(overflows, isEmpty, reason: overflows.toSet().join('\n'));
          }, _fakeBackend);
        });
      }
    }
  }
}
