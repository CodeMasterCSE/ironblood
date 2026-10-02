import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _keyIsLoggedIn = 'ib_is_logged_in';
  static const String _keyRole = 'ib_user_role'; // 'admin', 'trainer', or 'member'
  static const String _keyMemberData = 'ib_member_data';
  static const String _keyTrainerData = 'ib_trainer_data';
  static const String _keyAdminData = 'ib_admin_data';
  static const String _keyAdminPassword = 'ib_admin_password';

  /// Get local admin password (defaults to 'ADMIN123')
  static Future<String> getAdminPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAdminPassword) ?? 'ADMIN123';
  }

  /// Store local admin password
  static Future<void> setAdminPassword(String newPassword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAdminPassword, newPassword.trim());
  }

  /// Save active Admin session
  static Future<void> saveAdminSession([Map<String, dynamic>? adminData]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyRole, 'admin');
    if (adminData != null && adminData.isNotEmpty) {
      await prefs.setString(_keyAdminData, jsonEncode(adminData));
      if (adminData['password'] != null) {
        await prefs.setString(_keyAdminPassword, adminData['password'].toString().trim());
      }
    }
  }

  /// Get stored admin profile
  static Future<Map<String, dynamic>?> getSavedAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString(_keyAdminData);
    if (dataStr != null && dataStr.isNotEmpty) {
      try {
        return jsonDecode(dataStr) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Save active Trainer session
  static Future<void> saveTrainerSession(Map<String, dynamic> trainerData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyRole, 'trainer');
    await prefs.setString(_keyTrainerData, jsonEncode(trainerData));
  }

  /// Save active Member session
  static Future<void> saveMemberSession(Map<String, dynamic> memberData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyRole, 'member');
    await prefs.setString(_keyMemberData, jsonEncode(memberData));
  }

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  /// Get current role ('admin', 'trainer', 'member', or null)
  static Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
    if (!loggedIn) return null;
    return prefs.getString(_keyRole);
  }

  /// Get stored member profile
  static Future<Map<String, dynamic>?> getSavedMember() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString(_keyMemberData);
    if (dataStr != null && dataStr.isNotEmpty) {
      try {
        return jsonDecode(dataStr) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Get stored trainer profile
  static Future<Map<String, dynamic>?> getSavedTrainer() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString(_keyTrainerData);
    if (dataStr != null && dataStr.isNotEmpty) {
      try {
        return jsonDecode(dataStr) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Clear session (Logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyMemberData);
    await prefs.remove(_keyTrainerData);
    await prefs.remove(_keyAdminData);
  }
}
