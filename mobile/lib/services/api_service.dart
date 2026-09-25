import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Thrown when the backend cannot be reached at all (timeout / no connection).
/// The caller must not assume the operation succeeded or failed — show a
/// "server unavailable" state with a retry option instead.
class ServerUnavailableException implements Exception {
  @override
  String toString() => 'Server unavailable. Check your connection and try again.';
}

class ApiService {
  // Backend runs locally during development, on the dev PC.
  // - Chrome/web/Windows desktop: 127.0.0.1 works (same machine).
  // - Physical Android device over USB: use 127.0.0.1 + `adb reverse tcp:8000 tcp:8000`
  //   (tunnels the phone's localhost:8000 to the PC over the USB cable — avoids
  //   WiFi/firewall/AP-isolation issues entirely).
  // - Physical device over WiFi (same LAN, no AP isolation): use the PC's LAN IP instead.
  // - Android emulator: use 10.0.2.2 instead of 127.0.0.1 to reach the host machine.
  static const String baseUrl = 'http://127.0.0.1:8000';

  static const Duration _defaultTimeout = Duration(seconds: 10);
  // The payment step simulates a gateway call server-side (up to a couple of
  // seconds) inside the 30s on-screen countdown, so give it more headroom.
  static const Duration _paymentTimeout = Duration(seconds: 35);

  Future<http.Response> _send(Future<http.Response> Function() request, {Duration? timeout}) async {
    try {
      return await request().timeout(timeout ?? _defaultTimeout);
    } on TimeoutException {
      throw ServerUnavailableException();
    } on http.ClientException {
      throw ServerUnavailableException();
    }
  }

  Map<String, String> _authHeaders(String token) => {'Authorization': 'Bearer $token'};

  Map<String, String> _jsonHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> login(String phoneNumber, String password) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone_number': phoneNumber, 'password': password}),
      ),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Login failed');
  }

  Future<Map<String, dynamic>> getCurrentUser(String token) async {
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl/auth/me'), headers: _authHeaders(token)),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException('Could not fetch profile');
  }

  Future<List<dynamic>> listStaff(String token) async {
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl/staff'), headers: _authHeaders(token)),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not load staff list');
  }

  Future<Map<String, dynamic>> createStaff(
    String token, {
    required String fullName,
    required String phoneNumber,
    required String password,
    required String role,
    int? shopId,
  }) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/staff'),
        headers: _jsonHeaders(token),
        body: jsonEncode({
          'full_name': fullName,
          'phone_number': phoneNumber,
          'password': password,
          'role': role,
          'shop_id': shopId,
        }),
      ),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not create staff');
  }

  Future<Map<String, dynamic>> deactivateStaff(String token, int staffId) async {
    final response = await _send(
      () => http.delete(Uri.parse('$baseUrl/staff/$staffId'), headers: _authHeaders(token)),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not deactivate staff');
  }

  Future<List<dynamic>> listShops(String token) async {
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl/shops'), headers: _authHeaders(token)),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not load shop list');
  }

  Future<Map<String, dynamic>> createShop(
    String token, {
    required String name,
    required String shopCode,
    String? address,
    double? latitude,
    double? longitude,
    String? serviceStartTime,
    String? serviceEndTime,
  }) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/shops'),
        headers: _jsonHeaders(token),
        body: jsonEncode({
          'name': name,
          'shop_code': shopCode,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'service_start_time': serviceStartTime,
          'service_end_time': serviceEndTime,
        }),
      ),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not create shop');
  }

  /// Pass `HH:mm` strings for the time fields, or null to clear the restriction.
  Future<Map<String, dynamic>> updateShopServiceWindow(
    String token,
    int shopId, {
    String? serviceStartTime,
    String? serviceEndTime,
  }) async {
    final response = await _send(
      () => http.patch(
        Uri.parse('$baseUrl/shops/$shopId'),
        headers: _jsonHeaders(token),
        body: jsonEncode({
          'service_start_time': serviceStartTime,
          'service_end_time': serviceEndTime,
        }),
      ),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not update shop hours');
  }

  Future<Map<String, dynamic>> deactivateShop(String token, int shopId) async {
    final response = await _send(
      () => http.delete(Uri.parse('$baseUrl/shops/$shopId'), headers: _authHeaders(token)),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not deactivate shop');
  }

  Future<Map<String, dynamic>> verifyLocation(String token, double latitude, double longitude) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/location/verify'),
        headers: _jsonHeaders(token),
        body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
      ),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not verify location');
  }

  Future<List<dynamic>> listBottles(String token) async {
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl/bottles'), headers: _authHeaders(token)),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not load bottle list');
  }

  Future<Map<String, dynamic>> createBottle(String token, {String? brandName}) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/bottles'),
        headers: _jsonHeaders(token),
        body: jsonEncode({'brand_name': brandName}),
      ),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not generate bottle');
  }

  Future<List<dynamic>> createBottlesBulk(String token, {required int count, String? brandName}) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/bottles/bulk'),
        headers: _jsonHeaders(token),
        body: jsonEncode({'count': count, 'brand_name': brandName}),
      ),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not generate bottles');
  }

  Future<Uint8List> getLabelsPdf(String token, {List<int>? ids}) async {
    final query = ids != null && ids.isNotEmpty ? '?ids=${ids.join(',')}' : '';
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl/bottles/labels-pdf$query'), headers: _authHeaders(token)),
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not load labels PDF');
  }

  Future<Uint8List> getRefundQrImage(String token, int bottleId) async {
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl/bottles/$bottleId/qr/refund'), headers: _authHeaders(token)),
    );
    if (response.statusCode == 200) return response.bodyBytes;
    throw ApiException('Could not load refund QR image');
  }

  Future<Uint8List> getManufacturingQrImage(String token, int bottleId) async {
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl/bottles/$bottleId/qr/manufacturing'), headers: _authHeaders(token)),
    );
    if (response.statusCode == 200) return response.bodyBytes;
    throw ApiException('Could not load manufacturing QR image');
  }

  Future<Map<String, dynamic>> verifyRefundQr(
    String token, {
    required String refundQrCode,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/returns/verify-refund-qr'),
        headers: _jsonHeaders(token),
        body: jsonEncode({'refund_qr_code': refundQrCode, 'latitude': latitude, 'longitude': longitude}),
      ),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not verify refund QR');
  }

  Future<Map<String, dynamic>> verifyManufacturingQr(
    String token, {
    required String refundQrCode,
    required String manufacturingQrCode,
  }) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/returns/verify-manufacturing-qr'),
        headers: _jsonHeaders(token),
        body: jsonEncode({'refund_qr_code': refundQrCode, 'manufacturing_qr_code': manufacturingQrCode}),
      ),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not verify manufacturing QR');
  }

  Future<Map<String, dynamic>> completeReturn(
    String token, {
    required String refundQrCode,
    required String manufacturingQrCode,
    required double latitude,
    required double longitude,
    required String paymentMethod,
    required String customerIdentifier,
  }) async {
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/returns/complete'),
        headers: _jsonHeaders(token),
        body: jsonEncode({
          'refund_qr_code': refundQrCode,
          'manufacturing_qr_code': manufacturingQrCode,
          'latitude': latitude,
          'longitude': longitude,
          'payment_method': paymentMethod,
          'customer_identifier': customerIdentifier,
        }),
      ),
      timeout: _paymentTimeout,
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Payment failed. Please retry.');
  }

  Future<Map<String, dynamic>> rejectReturn(
    String token, {
    required String reason,
    String? refundQrCode,
    String? remarks,
    double? latitude,
    double? longitude,
    Uint8List? evidenceImageBytes,
  }) async {
    final uri = Uri.parse('$baseUrl/returns/reject');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['reason'] = reason;

    if (refundQrCode != null) request.fields['refund_qr_code'] = refundQrCode;
    if (remarks != null && remarks.isNotEmpty) request.fields['remarks'] = remarks;
    if (latitude != null) request.fields['latitude'] = latitude.toString();
    if (longitude != null) request.fields['longitude'] = longitude.toString();
    if (evidenceImageBytes != null) {
      request.files.add(http.MultipartFile.fromBytes('evidence_image', evidenceImageBytes, filename: 'evidence.jpg'));
    }

    http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(_defaultTimeout);
    } on TimeoutException {
      throw ServerUnavailableException();
    } on http.ClientException {
      throw ServerUnavailableException();
    }

    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not submit rejection');
  }

  Future<List<dynamic>> listMyReturns(String token) async {
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl/returns/mine'), headers: _authHeaders(token)),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw ApiException(_extractError(response.body) ?? 'Could not load return history');
  }

  String? _extractError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['detail']?.toString();
    } catch (_) {
      return null;
    }
  }
}
