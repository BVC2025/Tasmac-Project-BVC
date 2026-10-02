import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the logged-in session (token + user profile) across app
/// restarts, so staff/admin aren't asked to log in again every time they
/// close and reopen the app — only after an explicit logout, or once the
/// saved token has actually expired.
class AuthStorage {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  static Future<void> save(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<({String token, Map<String, dynamic> user})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (token == null || userJson == null) return null;

    try {
      final user = jsonDecode(userJson) as Map<String, dynamic>;
      return (token: token, user: user);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
