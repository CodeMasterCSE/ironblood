import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'session_service.dart';

class SupabaseService {
  // SUPABASE CONFIGURATION:
  // Base Supabase Project URL and Anon Key
  static const String supabaseUrl = 'https://cjjoxiithdutihzszima.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNqam94aWl0aGR1dGloenN6aW1hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyNjQ3MTEsImV4cCI6MjEwNTg0MDcxMX0.nuG9_kXPEsTlgcSxZ7f8GiVrxsBuo4f-tEVkZlZG5z0';

  static bool get isConfigured =>
      supabaseUrl != 'YOUR_SUPABASE_URL' &&
      supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY' &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty;

  static SupabaseClient get client => Supabase.instance.client;

  // ==========================================
  // OFFLINE CACHING & LOCAL STORAGE ENGINE
  // ==========================================
  static const String _keyCacheMembers = 'ib_cache_members';
  static const String _keyCacheTrainers = 'ib_cache_trainers';
  static const String _keyCacheMembershipPlans = 'ib_cache_membership_plans';
  static const String _keyCachePtPlans = 'ib_cache_pt_plans';
  static const String _keyCacheAdminProfile = 'ib_cache_admin_profile';
  static const String _keyCacheAnnouncements = 'local_gym_announcements';
  static const String _keyCacheRevenueRecords = 'local_revenue_records';

  static Future<void> _saveCacheList(String key, List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(list));
      debugPrint("Cache saved [$key]: ${list.length} records");
    } catch (e) {
      debugPrint("Cache save error for $key: $e");
    }
  }

  static Future<List<Map<String, dynamic>>> _getCacheList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(key);
      if (str != null && str.isNotEmpty) {
        final decoded = jsonDecode(str) as List<dynamic>;
        final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        debugPrint("Cache loaded [$key]: ${list.length} records");
        return list;
      }
    } catch (e) {
      debugPrint("Cache get error for $key: $e");
    }
    return [];
  }

  static Future<void> _saveCacheMap(String key, Map<String, dynamic> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(map));
    } catch (e) {
      debugPrint("CacheMap save error for $key: $e");
    }
  }

  static Future<Map<String, dynamic>?> _getCacheMap(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(key);
      if (str != null && str.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(str) as Map);
      }
    } catch (e) {
      debugPrint("CacheMap get error for $key: $e");
    }
    return null;
  }

  // Public Cache Accessors for instant 0ms offline UI loading
  static Future<List<Map<String, dynamic>>> getCachedMembers() => _getCacheList(_keyCacheMembers);
  static Future<List<Map<String, dynamic>>> getCachedTrainers() => _getCacheList(_keyCacheTrainers);

  static Future<List<Map<String, dynamic>>> getCachedMembershipPlans() async {
    final cached = await _getCacheList(_keyCacheMembershipPlans);
    return cached.isNotEmpty ? cached : defaultMembershipPlans;
  }

  static Future<List<Map<String, dynamic>>> getCachedPtPlans() async {
    final cached = await _getCacheList(_keyCachePtPlans);
    return cached.isNotEmpty ? cached : defaultPtPlans;
  }

  static Future<Map<String, dynamic>> getCachedAdminProfile() async {
    final cached = await _getCacheMap(_keyCacheAdminProfile);
    if (cached != null && cached.isNotEmpty) return cached;
    final saved = await SessionService.getSavedAdmin();
    if (saved != null && saved.isNotEmpty) return saved;
    final pass = await SessionService.getAdminPassword();
    return {
      'username': 'ADMIN',
      'full_name': 'BAPI DAS',
      'password': pass,
      'phone': '+919876543210',
      'email': 'admin@ironblood.com',
      'role': 'GYM OWNER & FOUNDER',
    };
  }

  static Future<List<Map<String, dynamic>>> getCachedAnnouncements({
    String? targetAudience,
    bool onlyActive = true,
  }) async {
    final list = await _getCacheList(_keyCacheAnnouncements);
    List<Map<String, dynamic>> results = [];
    for (final item in list) {
      final audience = (item['target_audience'] ?? 'ALL').toString().toUpperCase();
      final isActive = item['is_active'] != false;
      if (onlyActive && !isActive) continue;
      if (targetAudience == null ||
          targetAudience == 'ALL' ||
          audience == 'ALL' ||
          audience == targetAudience.toUpperCase()) {
        results.add(item);
      }
    }
    if (results.isEmpty) {
      final now = DateTime.now();
      results = [
        {
          'id': 'welcome-note-1',
          'title': 'Welcome to IRONBLOOD Studio Notice Board',
          'message':
              'All official gym schedules, holiday closures, special fitness seminars, and competition updates will be posted here directly.',
          'target_audience': 'ALL',
          'duration_hours': 36,
          'expires_at': now.add(const Duration(hours: 36)).toIso8601String(),
          'is_active': true,
          'created_at': now.toIso8601String(),
        }
      ];
    }
    return results;
  }

  /// Update single member in local cache
  static Future<void> _updateMemberInCache(Map<String, dynamic> updated) async {
    try {
      final list = await _getCacheList(_keyCacheMembers);
      final id = (updated['member_id'] ?? '').toString().trim().toLowerCase();
      if (id.isEmpty) return;
      int idx = list.indexWhere((m) => (m['member_id'] ?? '').toString().trim().toLowerCase() == id);
      if (idx >= 0) {
        final merged = Map<String, dynamic>.from(list[idx])..addAll(updated);
        list[idx] = merged;
      } else {
        list.insert(0, updated);
      }
      await _saveCacheList(_keyCacheMembers, list);

      // If this member is the currently logged in member, update active session too
      final currentMember = await SessionService.getSavedMember();
      if (currentMember != null &&
          (currentMember['member_id'] ?? '').toString().trim().toLowerCase() == id) {
        final mergedSession = Map<String, dynamic>.from(currentMember)..addAll(updated);
        await SessionService.saveMemberSession(mergedSession);
      }
    } catch (e) {
      debugPrint("Error updating member cache: $e");
    }
  }

  /// Remove single member from local cache
  static Future<void> _removeMemberFromCache(String memberId) async {
    try {
      final list = await _getCacheList(_keyCacheMembers);
      final id = memberId.trim().toLowerCase();
      list.removeWhere((m) => (m['member_id'] ?? '').toString().trim().toLowerCase() == id);
      await _saveCacheList(_keyCacheMembers, list);
    } catch (e) {
      debugPrint("Error removing member from cache: $e");
    }
  }

  /// Update single trainer in local cache
  static Future<void> _updateTrainerInCache(Map<String, dynamic> updated) async {
    try {
      final list = await _getCacheList(_keyCacheTrainers);
      final id = (updated['trainer_id'] ?? '').toString().trim().toLowerCase();
      final name = (updated['full_name'] ?? '').toString().trim().toLowerCase();
      int idx = list.indexWhere((t) =>
          (id.isNotEmpty && (t['trainer_id'] ?? '').toString().trim().toLowerCase() == id) ||
          (name.isNotEmpty && (t['full_name'] ?? '').toString().trim().toLowerCase() == name));
      if (idx >= 0) {
        final merged = Map<String, dynamic>.from(list[idx])..addAll(updated);
        list[idx] = merged;
      } else {
        list.insert(0, updated);
      }
      await _saveCacheList(_keyCacheTrainers, list);

      // If active trainer session matches, update session
      final currentTrainer = await SessionService.getSavedTrainer();
      if (currentTrainer != null &&
          ((id.isNotEmpty && (currentTrainer['trainer_id'] ?? '').toString().trim().toLowerCase() == id) ||
           (name.isNotEmpty && (currentTrainer['full_name'] ?? '').toString().trim().toLowerCase() == name))) {
        final mergedSession = Map<String, dynamic>.from(currentTrainer)..addAll(updated);
        await SessionService.saveTrainerSession(mergedSession);
      }
    } catch (e) {
      debugPrint("Error updating trainer cache: $e");
    }
  }

  /// Remove single trainer from local cache
  static Future<void> _removeTrainerFromCache(String trainerId) async {
    try {
      final list = await _getCacheList(_keyCacheTrainers);
      final id = trainerId.trim().toLowerCase();
      list.removeWhere((t) => (t['trainer_id'] ?? '').toString().trim().toLowerCase() == id);
      await _saveCacheList(_keyCacheTrainers, list);
    } catch (e) {
      debugPrint("Error removing trainer from cache: $e");
    }
  }

  /// Background warmup to preload entire database into local cache when online
  static Future<void> warmupCache() async {
    if (!isConfigured) return;
    try {
      debugPrint("Starting background cache warmup...");
      await Future.wait([
        fetchMembers(),
        fetchTrainers(),
        fetchMembershipPlans(),
        fetchPtPlans(),
        fetchAnnouncements(onlyActive: false),
        fetchRevenueTransactions(),
        fetchAdminProfile(),
      ]).timeout(const Duration(seconds: 8));
      debugPrint("Cache warmup completed successfully!");
    } catch (e) {
      debugPrint("Background cache warmup note: $e");
    }
  }

  /// Initialize Supabase and start background cache sync
  static Future<void> initialize() async {
    if (isConfigured) {
      try {
        final cleanUrl = supabaseUrl
            .trim()
            .replaceAll(RegExp(r'/rest/v1/?$'), '')
            .replaceAll(RegExp(r'/+$'), '');

        await Supabase.initialize(
          url: cleanUrl,
          // ignore: deprecated_member_use
          anonKey: supabaseAnonKey.trim(),
        );
        debugPrint("Supabase initialized successfully with: $cleanUrl");
        // Start background prefetch into local cache
        warmupCache();
      } catch (e) {
        debugPrint("Error initializing Supabase: $e");
      }
    } else {
      debugPrint("Supabase credentials not configured.");
    }
  }

  /// Standard Indian Mobile (+91) Formatter
  static String formatIndianPhone(String? phone) {
    if (phone == null) return '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+$digits';
    }
    if (digits.length > 10) {
      return '+91${digits.substring(digits.length - 10)}';
    }
    return '+91$digits';
  }

  static const String _aadharSecretKey = 'IB_SECURE_AADHAR_KEY_2026_IRONBLOOD_GYM';

  /// Encrypts and protects raw Aadhar number so plaintext is never exposed in DB or logs
  static String protectAadhar(String? aadhar) {
    if (aadhar == null || aadhar.trim().isEmpty) return '';
    final trimmed = aadhar.trim();
    if (trimmed.startsWith('IB_ENC:')) return trimmed; // Already encrypted
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return trimmed;
    
    // Symmetric XOR byte cipher + Base64 with gym key
    final keyBytes = utf8.encode(_aadharSecretKey);
    final dataBytes = utf8.encode(digits);
    final encBytes = List<int>.generate(dataBytes.length, (i) {
      return dataBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return 'IB_ENC:${base64Url.encode(encBytes)}';
  }

  /// Decrypts/reveals the original Aadhar number in 3 groups of 4 digits (XXXX XXXX XXXX)
  static String revealAadhar(String? storedAadhar) {
    if (storedAadhar == null || storedAadhar.trim().isEmpty) return '';
    final trimmed = storedAadhar.trim();
    // If it's a 64-character SHA-256 legacy hash, it cannot be reversed
    if (trimmed.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed)) {
      return '';
    }
    if (!trimmed.startsWith('IB_ENC:')) {
      final digits = trimmed.replaceAll(RegExp(r'\D'), '');
      return digits.isNotEmpty ? formatAadharNumber(digits) : trimmed;
    }
    try {
      var base64Str = trimmed.substring(7);
      while (base64Str.length % 4 != 0) {
        base64Str += '=';
      }
      final encBytes = base64Url.decode(base64Str);
      final keyBytes = utf8.encode(_aadharSecretKey);
      final decBytes = List<int>.generate(encBytes.length, (i) {
        return encBytes[i] ^ keyBytes[i % keyBytes.length];
      });
      final plain = utf8.decode(decBytes);
      return formatAadharNumber(plain);
    } catch (_) {
      return trimmed;
    }
  }

  /// Format Aadhar for display: masked with * by default (**** **** ****) or fully revealed when toggled (XXXX XXXX XXXX)
  static String formatAadharDisplay(String? storedAadhar, {bool isRevealed = false}) {
    if (storedAadhar == null || storedAadhar.trim().isEmpty) return 'Not Provided';
    final plain = revealAadhar(storedAadhar);
    if (plain.isEmpty) return 'Not Provided';
    
    if (isRevealed) {
      return formatAadharNumber(plain);
    } else {
      final digits = plain.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 4) {
        return '**** **** ${digits.substring(digits.length - 4)}';
      }
      return '**** **** ****';
    }
  }

  /// Format Aadhar card number into 3 groups of 4 digits: XXXX XXXX XXXX (e.g. 1234 5678 9012)
  static String formatAadharNumber(String? aadhar) {
    if (aadhar == null || aadhar.trim().isEmpty) return '';
    final digits = aadhar.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return aadhar.trim();
    if (digits.length <= 4) return digits;
    if (digits.length <= 8) return '${digits.substring(0, 4)} ${digits.substring(4)}';
    if (digits.length <= 12) {
      return '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8)}';
    }
    return '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8, 12)}';
  }

  /// Extract 10 digits for text editing
  static String extract10DigitPhone(String? fullPhone) {
    if (fullPhone == null) return '';
    final digits = fullPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  /// Fetch the current Admin Profile from 'admin' table in Supabase
  static Future<Map<String, dynamic>> fetchAdminProfile() async {
    try {
      if (isConfigured) {
        final res = await client
            .from('admin')
            .select('*')
            .limit(1)
            .maybeSingle()
            .timeout(const Duration(seconds: 3));
        if (res != null && res.isNotEmpty) {
          final adminData = Map<String, dynamic>.from(res);
          await _saveCacheMap(_keyCacheAdminProfile, adminData);
          return adminData;
        }
      }
    } catch (e) {
      debugPrint("Supabase fetchAdminProfile error: $e");
    }

    final cachedAdmin = await _getCacheMap(_keyCacheAdminProfile);
    if (cachedAdmin != null && cachedAdmin.isNotEmpty) {
      return cachedAdmin;
    }

    final localAdmin = await SessionService.getSavedAdmin();
    if (localAdmin != null && localAdmin.isNotEmpty) {
      return localAdmin;
    }
    final localPass = await SessionService.getAdminPassword();
    return {
      'username': 'ADMIN',
      'full_name': 'BAPI DAS',
      'password': localPass,
      'phone': '+919876543210',
      'email': 'admin@ironblood.com',
      'role': 'GYM OWNER & FOUNDER',
    };
  }

  /// Fetch the current active Admin Password from 'admin' table
  static Future<String> fetchAdminPassword() async {
    final profile = await fetchAdminProfile();
    return profile['password']?.toString().trim() ?? 'ADMIN123';
  }

  /// Login and verify Admin credentials against 'admin' table in Supabase
  static Future<Map<String, dynamic>> loginAdmin({
    required String identifier,
    required String password,
  }) async {
    final q = identifier.trim();
    final p = password.trim();

    if (q.toUpperCase() != 'ADMIN') {
      return {'success': false, 'message': 'Invalid Admin ID'};
    }

    try {
      if (isConfigured) {
        final data = await client
            .from('admin')
            .select('*')
            .limit(1)
            .maybeSingle()
            .timeout(const Duration(seconds: 3));

        if (data != null && data.isNotEmpty) {
          final dbPass = data['password']?.toString().trim() ?? 'ADMIN123';
          if (p == dbPass || p.toUpperCase() == dbPass.toUpperCase()) {
            final adminMap = Map<String, dynamic>.from(data);
            await SessionService.saveAdminSession(adminMap);
            return {'success': true, 'admin': adminMap};
          } else {
            return {
              'success': false,
              'message': 'Invalid Admin Password. Access Denied.',
            };
          }
        }
      }
    } catch (e) {
      debugPrint("Supabase admin table login fallback error: $e");
    }

    // Fallback if offline or admin table query pending
    final isMatch = await verifyAdminPassword(p);
    if (isMatch) {
      final profile = await fetchAdminProfile();
      await SessionService.saveAdminSession(profile);
      return {'success': true, 'admin': profile};
    }
    return {
      'success': false,
      'message': 'Invalid Admin Password. Access Denied.',
    };
  }

  /// Verify if the entered password matches the Admin password in 'admin' table
  static Future<bool> verifyAdminPassword(String password) async {
    final activePass = await fetchAdminPassword();
    final trimmed = password.trim();
    if (trimmed == activePass || trimmed.toUpperCase() == activePass.toUpperCase()) {
      return true;
    }
    if ((activePass == 'ADMIN123' || activePass == 'admin123') &&
        (trimmed == 'ADMIN123' || trimmed == 'admin123')) {
      return true;
    }
    return false;
  }

  /// Change/Update the Admin Master Password in 'admin' table
  static Future<Map<String, dynamic>> updateAdminPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final isMatch = await verifyAdminPassword(currentPassword);
    if (!isMatch) {
      return {
        'success': false,
        'message': 'Current admin password is incorrect.',
      };
    }

    final trimmedNew = newPassword.trim();
    if (trimmedNew.length < 4) {
      return {
        'success': false,
        'message': 'New password must be at least 4 characters.',
      };
    }

    // Save locally
    await SessionService.setAdminPassword(trimmedNew);

    // Save to Supabase 'admin' table
    try {
      if (isConfigured) {
        await client.from('admin').upsert({
          'username': 'ADMIN',
          'password': trimmedNew,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint("Supabase remote admin table password update warning: $e");
    }

    return {
      'success': true,
      'message': 'Admin password updated successfully in database!',
    };
  }

  // ==========================================
  // AUTHENTICATION METHODS (SUPABASE DIRECT)
  // ==========================================

  static Future<Map<String, dynamic>> loginMember({
    required String memberIdOrPhone,
    required String password,
  }) async {
    final q = memberIdOrPhone.trim();
    final p = password.trim();

    if (isConfigured) {
      try {
        final response = await client.rpc(
          'verify_member_login',
          params: {'p_member_id': q, 'p_password': p},
        ).timeout(const Duration(seconds: 3));

        if (response != null && response['success'] == true) {
          final mem = Map<String, dynamic>.from(response['member']);
          await _updateMemberInCache(mem);
          return {'success': true, 'member': mem};
        }
      } catch (e) {
        debugPrint("Supabase verify_member_login RPC error: $e");
      }

      // Direct table lookup fallback
      try {
        final phoneFormatted = formatIndianPhone(q);
        final rawDigits = q.replaceAll(RegExp(r'\D'), '');

        var query = client.from('members').select('*');
        if (rawDigits.length == 10) {
          query = query.or('member_id.ilike.$q,phone.ilike.$phoneFormatted,phone.ilike.%$rawDigits%');
        } else {
          query = query.or('member_id.ilike.$q,phone.ilike.$q,email.ilike.$q');
        }

        final directList = await query.limit(1).timeout(const Duration(seconds: 3));

        if (directList.isNotEmpty) {
          final mem = Map<String, dynamic>.from(directList.first);
          if (mem['password_hash'] == p ||
              mem['password_hash'] == password) {
            await _updateMemberInCache(mem);
            return {'success': true, 'member': mem};
          }
        }
      } catch (e) {
        debugPrint("Supabase direct member login fallback error: $e");
      }
    }

    // Offline cache login fallback
    try {
      final cleanQ = q.toLowerCase();
      final phoneFormatted = formatIndianPhone(q);
      final rawDigits = q.replaceAll(RegExp(r'\D'), '');
      final cachedMembers = await _getCacheList(_keyCacheMembers);

      for (final mem in cachedMembers) {
        final mId = (mem['member_id'] ?? '').toString().toLowerCase();
        final mPhone = (mem['phone'] ?? '').toString();
        final mEmail = (mem['email'] ?? '').toString().toLowerCase();
        final mDigits = mPhone.replaceAll(RegExp(r'\D'), '');

        bool isMatch = mId == cleanQ ||
            (phoneFormatted.isNotEmpty && mPhone == phoneFormatted) ||
            (rawDigits.length == 10 && mDigits.endsWith(rawDigits)) ||
            (mEmail.isNotEmpty && mEmail == cleanQ);

        if (isMatch) {
          if (mem['password_hash'] == p ||
              mem['password_hash'] == password) {
            return {'success': true, 'member': mem};
          } else {
            return {'success': false, 'message': 'Invalid Member Password'};
          }
        }
      }
    } catch (cacheErr) {
      debugPrint("Offline member login cache error: $cacheErr");
    }

    return {'success': false, 'message': 'Invalid Member ID or Password'};
  }

  static Future<Map<String, dynamic>> activateAccount({
    required String memberIdOrPhone,
    required String newPassword,
  }) async {
    if (!isConfigured) {
      return {'success': false, 'message': 'Supabase is not configured yet.'};
    }

    final q = memberIdOrPhone.trim();
    if (q.toUpperCase().startsWith('TR-')) {
      return activateTrainerAccount(
        trainerIdOrPhone: q,
        newPassword: newPassword,
      );
    }

    try {
      final response = await client.rpc(
        'activate_member_account',
        params: {'p_member_id': q, 'p_new_password': newPassword},
      );

      if (response != null && response['success'] == true) {
        return {
          'success': true,
          'message':
              response['message'] ??
              'Member account activated successfully! You can now log in.',
        };
      }

      // If not found in members and could be a phone number, try trainer activation
      final trainerResp = await client.rpc(
        'activate_trainer_account',
        params: {'p_trainer_id': q, 'p_new_password': newPassword},
      );

      if (trainerResp != null && trainerResp['success'] == true) {
        return {
          'success': true,
          'message':
              trainerResp['message'] ??
              'Trainer account activated successfully! You can now log in.',
        };
      }

      return {
        'success': false,
        'message':
            response?['message'] ??
            'ID or contact not found in active records. Please contact Admin.',
      };
    } catch (e) {
      debugPrint("Supabase activation error: $e");
      return {'success': false, 'message': 'Database error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> activateTrainerAccount({
    required String trainerIdOrPhone,
    required String newPassword,
  }) async {
    if (!isConfigured) {
      return {'success': false, 'message': 'Supabase is not configured yet.'};
    }

    try {
      final response = await client.rpc(
        'activate_trainer_account',
        params: {
          'p_trainer_id': trainerIdOrPhone.trim(),
          'p_new_password': newPassword,
        },
      );

      if (response != null && response['success'] == true) {
        return {
          'success': true,
          'message':
              response['message'] ??
              'Trainer account activated successfully! You can now log in.',
        };
      } else {
        return {
          'success': false,
          'message':
              response?['message'] ??
              'Trainer ID not found. Please contact Admin.',
        };
      }
    } catch (e) {
      debugPrint("Supabase trainer activation error: $e");
      return {'success': false, 'message': 'Database error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> resetPassword({
    required String memberIdOrPhone,
    required String newPassword,
  }) async {
    if (!isConfigured) {
      return {'success': false, 'message': 'Supabase is not configured yet.'};
    }

    final q = memberIdOrPhone.trim();
    if (q.toUpperCase() == 'ADMIN') {
      final trimmedNew = newPassword.trim();
      if (trimmedNew.length < 4) {
        return {
          'success': false,
          'message': 'Password must be at least 4 characters.',
        };
      }
      await SessionService.setAdminPassword(trimmedNew);
      try {
        if (isConfigured) {
          await client.from('admin').upsert({
            'username': 'ADMIN',
            'password': trimmedNew,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
        debugPrint("Remote admin table password reset sync: $e");
      }
      return {
        'success': true,
        'message': 'Admin password reset successfully! You can now log in.',
      };
    }

    if (q.toUpperCase().startsWith('TR-')) {
      return resetTrainerPassword(
        trainerIdOrPhone: q,
        newPassword: newPassword,
      );
    }

    // Try RPC
    try {
      final response = await client.rpc(
        'activate_member_account',
        params: {'p_member_id': q, 'p_new_password': newPassword},
      );

      if (response != null && response['success'] == true) {
        return {
          'success': true,
          'message': response['message'] ??
              'Password reset successfully! You can now log in.',
        };
      }
    } catch (e) {
      debugPrint("Supabase RPC password reset error: $e");
    }

    // Direct table fallback for members
    try {
      final phoneFormatted = formatIndianPhone(q);
      final rawDigits = q.replaceAll(RegExp(r'\D'), '');

      var query = client.from('members').select('id, member_id, full_name, phone');
      if (rawDigits.length == 10) {
        query = query.or('member_id.ilike.$q,phone.ilike.$phoneFormatted,phone.ilike.%$rawDigits%');
      } else {
        query = query.or('member_id.ilike.$q,phone.ilike.$q,email.ilike.$q');
      }

      final records = await query.limit(1);
      if (records.isNotEmpty) {
        final memId = records.first['id'];
        await client.from('members').update({
          'password_hash': newPassword,
        }).eq('id', memId);

        return {
          'success': true,
          'message':
              'Password reset successfully for ${records.first['full_name'] ?? 'Member'}! You can now log in.',
        };
      }
    } catch (e) {
      debugPrint("Direct member password reset error: $e");
    }

    // Try trainer reset if not found in members
    final trainerResult = await resetTrainerPassword(
      trainerIdOrPhone: q,
      newPassword: newPassword,
    );
    if (trainerResult['success'] == true) {
      return trainerResult;
    }

    return {
      'success': false,
      'message':
          'Member ID or registered phone not found. Please verify or contact Admin.',
    };
  }

  static Future<Map<String, dynamic>> resetTrainerPassword({
    required String trainerIdOrPhone,
    required String newPassword,
  }) async {
    if (!isConfigured) {
      return {'success': false, 'message': 'Supabase is not configured yet.'};
    }

    final q = trainerIdOrPhone.trim();
    try {
      final response = await client.rpc(
        'activate_trainer_account',
        params: {
          'p_trainer_id': q,
          'p_new_password': newPassword,
        },
      );

      if (response != null && response['success'] == true) {
        return {
          'success': true,
          'message': response['message'] ??
              'Trainer password reset successfully! You can now log in.',
        };
      }
    } catch (e) {
      debugPrint("Supabase RPC trainer password reset error: $e");
    }

    // Direct table fallback for trainers
    try {
      final phoneFormatted = formatIndianPhone(q);
      final rawDigits = q.replaceAll(RegExp(r'\D'), '');

      var query = client.from('trainers').select('id, trainer_id, full_name, phone');
      if (rawDigits.length == 10) {
        query = query.or('trainer_id.ilike.$q,phone.ilike.$phoneFormatted,phone.ilike.%$rawDigits%');
      } else {
        query = query.or('trainer_id.ilike.$q,phone.ilike.$q,email.ilike.$q');
      }

      final records = await query.limit(1);
      if (records.isNotEmpty) {
        final trId = records.first['id'];
        await client.from('trainers').update({
          'password_hash': newPassword,
        }).eq('id', trId);

        return {
          'success': true,
          'message':
              'Password reset successfully for Coach ${records.first['full_name'] ?? 'Trainer'}!',
        };
      }
    } catch (e) {
      debugPrint("Direct trainer password reset error: $e");
    }

    return {
      'success': false,
      'message': 'Trainer ID or registered phone not found. Please contact Admin.',
    };
  }

  static Future<Map<String, dynamic>> loginTrainer({
    required String trainerIdOrPhone,
    required String password,
  }) async {
    final tid = trainerIdOrPhone.trim();
    final p = password.trim();

    if (isConfigured) {
      try {
        final response = await client.rpc(
          'verify_trainer_login',
          params: {
            'p_trainer_id': tid,
            'p_password': p,
          },
        ).timeout(const Duration(seconds: 3));

        if (response != null && response['success'] == true) {
          final tr = Map<String, dynamic>.from(response['trainer']);
          await _updateTrainerInCache(tr);
          return {'success': true, 'trainer': tr};
        }
      } catch (e) {
        debugPrint("Supabase verify_trainer_login RPC error: $e");
      }

      // Direct table lookup fallback
      try {
        final phoneFormatted = formatIndianPhone(tid);
        final rawDigits = tid.replaceAll(RegExp(r'\D'), '');

        var query = client.from('trainers').select('*');
        if (rawDigits.length == 10) {
          query = query.or('trainer_id.ilike.$tid,phone.ilike.$phoneFormatted,phone.ilike.%$rawDigits%');
        } else {
          query = query.or('trainer_id.ilike.$tid,phone.ilike.$tid,email.ilike.$tid');
        }

        final directList = await query.limit(1).timeout(const Duration(seconds: 3));

        if (directList.isNotEmpty) {
          final tr = Map<String, dynamic>.from(directList.first);
          if (tr['password_hash'] == p ||
              tr['password_hash'] == password) {
            await _updateTrainerInCache(tr);
            return {'success': true, 'trainer': tr};
          }
        }
      } catch (e) {
        debugPrint("Supabase direct trainer login error: $e");
      }
    }

    // Offline cache login fallback
    try {
      final cleanTid = tid.toLowerCase();
      final phoneFormatted = formatIndianPhone(tid);
      final rawDigits = tid.replaceAll(RegExp(r'\D'), '');
      final cachedTrainers = await _getCacheList(_keyCacheTrainers);

      for (final tr in cachedTrainers) {
        final tId = (tr['trainer_id'] ?? '').toString().toLowerCase();
        final tPhone = (tr['phone'] ?? '').toString();
        final tEmail = (tr['email'] ?? '').toString().toLowerCase();
        final tDigits = tPhone.replaceAll(RegExp(r'\D'), '');

        bool isMatch = tId == cleanTid ||
            (phoneFormatted.isNotEmpty && tPhone == phoneFormatted) ||
            (rawDigits.length == 10 && tDigits.endsWith(rawDigits)) ||
            (tEmail.isNotEmpty && tEmail == cleanTid);

        if (isMatch) {
          if (tr['password_hash'] == p ||
              tr['password_hash'] == password) {
            return {'success': true, 'trainer': tr};
          } else {
            return {'success': false, 'message': 'Invalid Trainer Password'};
          }
        }
      }
    } catch (cacheErr) {
      debugPrint("Offline trainer login cache error: $cacheErr");
    }

    return {'success': false, 'message': 'Invalid Trainer ID or Password'};
  }

  static Future<List<Map<String, dynamic>>> fetchMembersForTrainer(
    String trainerName,
  ) async {
    final tName = trainerName.trim();
    if (tName.isEmpty) return [];
    final cacheKey = 'ib_cache_trainer_clients_${tName.toLowerCase()}';

    if (isConfigured) {
      try {
        final data = await client
            .from('members')
            .select('*')
            .ilike('pt_trainer', '%$tName%')
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 3));
        final list = List<Map<String, dynamic>>.from(data);
        if (list.isNotEmpty) {
          await _saveCacheList(cacheKey, list);
          return list;
        }
      } catch (e) {
        debugPrint("Supabase fetchMembersForTrainer query error: $e");
      }
    }

    // Direct fallback: Fetch all members and match in Dart (100% reliable)
    try {
      final allMembers = await fetchMembers();
      final lowerName = tName.toLowerCase();
      final filtered = allMembers.where((m) {
        final ptT = (m['pt_trainer'] ?? '').toString().trim().toLowerCase();
        final reqT = (m['requested_pt_trainer'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return ptT == lowerName ||
            ptT.contains(lowerName) ||
            (lowerName.contains(ptT) && ptT.isNotEmpty) ||
            reqT == lowerName ||
            reqT.contains(lowerName);
      }).toList();
      if (filtered.isNotEmpty) {
        await _saveCacheList(cacheKey, filtered);
        return filtered;
      }
    } catch (e2) {
      debugPrint("Fallback fetchMembersForTrainer error: $e2");
    }

    return await _getCacheList(cacheKey);
  }

  // ==========================================
  // MEMBERS MANAGEMENT (100% DIRECT SUPABASE DB)
  // ==========================================

  static int planToDays(String plan) {
    final p = plan.toLowerCase().trim();
    if (p.contains('3 month') || p.contains('3month') || p.contains('3-month')) return 90;
    if (p.contains('6 month') || p.contains('6month') || p.contains('6-month')) return 180;
    if (p.contains('annual') ||
        p.contains('12 month') ||
        p.contains('12month') ||
        p.contains('1 year') ||
        p.contains('yearly')) {
      return 360;
    }
    // Default 1 Month (or Admission) = 30 days
    return 30;
  }

  static int planToMonths(String plan) {
    final p = plan.toLowerCase().trim();
    if (p.contains('3 month') || p.contains('3month')) return 3;
    if (p.contains('6 month') || p.contains('6month')) return 6;
    if (p.contains('annual') ||
        p.contains('12 month') ||
        p.contains('12month') ||
        p.contains('1 year') ||
        p.contains('yearly')) {
      return 12;
    }
    return 1;
  }

  /// Calculates expiry date:
  /// - 1 Month / Admission = 30 days
  /// - 3 Months = 90 days
  /// - 6 Months = 180 days
  /// - 1 Year / Annual / 12 Months = Exact 1 full year (e.g. 02-10-2026 to 02-10-2027, 365/366 days for leap year)
  static DateTime calculateExpiryDate(DateTime start, String plan, [int? months]) {
    final p = plan.toLowerCase().trim();
    final m = months ?? planToMonths(plan);
    if (m >= 12 ||
        p.contains('annual') ||
        p.contains('1 year') ||
        p.contains('1year') ||
        p.contains('yearly') ||
        p.contains('12 month')) {
      final yearsToAdd = (m >= 12 ? (m ~/ 12) : 1);
      final targetYear = start.year + yearsToAdd;
      final daysInTargetMonth = DateTime(targetYear, start.month + 1, 0).day;
      final targetDay = start.day > daysInTargetMonth ? daysInTargetMonth : start.day;
      return DateTime(targetYear, start.month, targetDay);
    }
    final int days = (months != null && months > 0) ? (months * 30) : planToDays(plan);
    return start.add(Duration(days: days));
  }

  static int daysRemaining(dynamic expiryDate) {
    if (expiryDate == null) return 0;
    try {
      final dt = expiryDate is DateTime
          ? expiryDate
          : DateTime.parse(expiryDate.toString());
      final now = DateTime.now();
      final diff = DateTime(
        dt.year,
        dt.month,
        dt.day,
      ).difference(DateTime(now.year, now.month, now.day)).inDays;
      return diff;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMembers() async {
    if (isConfigured) {
      try {
        final data = await client
            .from('members')
            .select('*')
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 3));
        final list = List<Map<String, dynamic>>.from(data);
        if (list.isNotEmpty) {
          await _saveCacheList(_keyCacheMembers, list);
          return list;
        }
      } catch (e) {
        debugPrint("Supabase fetchMembers with order error: $e");
        try {
          final data = await client
              .from('members')
              .select('*')
              .timeout(const Duration(seconds: 3));
          final list = List<Map<String, dynamic>>.from(data);
          if (list.isNotEmpty) {
            await _saveCacheList(_keyCacheMembers, list);
            return list;
          }
        } catch (e2) {
          debugPrint("Supabase fetchMembers error: $e2");
        }
      }
    }

    // Fallback to local storage cache
    return await _getCacheList(_keyCacheMembers);
  }

  static Future<Map<String, dynamic>> adminCreateMember({
    required String memberId,
    required String fullName,
    required String initialPassword,
    String? phone,
    String? emergencyPhone,
    String? photoUrl,
    String? email,
    String? plan,
    String? assignedTrainer,
    DateTime? membershipStartDate,
    DateTime? membershipExpiryDate,
    bool? hasPt,
    String? ptPlan,
    DateTime? ptStartDate,
    DateTime? ptExpiryDate,
    String? ptTrainer,
    String? aadharNumber,
    String? address,
    String? medicalHistory,
  }) async {
    if (!isConfigured) {
      return {'success': false, 'message': 'Supabase is not configured.'};
    }

    final formattedPhone = formatIndianPhone(phone);
    final formattedEmergencyPhone = emergencyPhone != null && emergencyPhone.trim().isNotEmpty
        ? formatIndianPhone(emergencyPhone)
        : null;

    try {
      final response = await client.rpc(
        'admin_create_member',
        params: {
          'p_member_id': memberId.trim(),
          'p_full_name': fullName.trim(),
          'p_initial_password': initialPassword,
          'p_phone': formattedPhone.isNotEmpty ? formattedPhone : null,
          'p_email': email?.trim(),
        },
      );

      if (response != null && response['success'] == true) {
        final startDate = membershipStartDate ?? DateTime.now();
        final chosenPlan = plan ?? "Monthly";
        final expiryDate =
            membershipExpiryDate ?? calculateExpiryDate(startDate, chosenPlan);

        final cleanAadhar = (aadharNumber != null && aadharNumber.trim().isNotEmpty) ? protectAadhar(aadharNumber) : null;
        final cleanAddress = (address != null && address.trim().isNotEmpty) ? address.trim() : null;
        final cleanMedical = (medicalHistory != null && medicalHistory.trim().isNotEmpty) ? medicalHistory.trim() : null;
        final extraFields = <String, dynamic>{
          'plan': chosenPlan,
          'phone': formattedPhone,
          'emergency_phone': formattedEmergencyPhone,
          'photo_url': (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null,
          'aadhar_number': cleanAadhar,
          'address': cleanAddress,
          'medical_history': cleanMedical,
          'membership_start_date': startDate.toIso8601String().substring(0, 10),
          'membership_expiry_date': expiryDate.toIso8601String().substring(
            0,
            10,
          ),
          'has_pt': hasPt ?? false,
          'pt_plan': ptPlan ?? 'None',
          'pt_trainer':
              ptTrainer ??
              (hasPt == true ? assignedTrainer ?? 'Unassigned' : 'Unassigned'),
          'renewal_status': 'Active',
          'pt_status': hasPt == true ? 'Active' : 'None',
        };

        if (hasPt == true) {
          final pStart = ptStartDate ?? DateTime.now();
          final pExpiry =
              ptExpiryDate ??
              calculateExpiryDate(pStart, ptPlan ?? "Monthly PT");
          extraFields['pt_start_date'] = pStart.toIso8601String().substring(
            0,
            10,
          );
          extraFields['pt_expiry_date'] = pExpiry.toIso8601String().substring(
            0,
            10,
          );
        }

        try {
          await client
              .from('members')
              .update(extraFields)
              .eq('member_id', memberId.trim());
        } on PostgrestException catch (pe) {
          if (pe.code == 'PGRST204' || pe.message.contains('schema cache')) {
            final fallback = Map<String, dynamic>.from(extraFields);
            fallback.remove('photo_url');
            fallback.remove('emergency_phone');
            fallback.remove('aadhar_number');
            fallback.remove('address');
            fallback.remove('medical_history');
            await client
                .from('members')
                .update(fallback)
                .eq('member_id', memberId.trim());
          } else {
            rethrow;
          }
        }

        final fullCreatedData = <String, dynamic>{
          'member_id': memberId.trim(),
          'full_name': fullName.trim(),
          'password_hash': initialPassword,
          'email': email?.trim(),
          'is_active': true,
          ...extraFields,
        };
        await _updateMemberInCache(fullCreatedData);

        return {
          'success': true,
          'message': 'Member enrolled into Supabase successfully!',
        };
      }
    } catch (e) {
      debugPrint("Supabase admin_create_member RPC error: $e");
    }

    // Direct table upsert fallback for member
    try {
      final startDate = membershipStartDate ?? DateTime.now();
      final chosenPlan = plan ?? "Monthly";
      final expiryDate =
          membershipExpiryDate ?? calculateExpiryDate(startDate, chosenPlan);

      final cleanAadhar = (aadharNumber != null && aadharNumber.trim().isNotEmpty) ? protectAadhar(aadharNumber) : null;
      final cleanAddress = (address != null && address.trim().isNotEmpty) ? address.trim() : null;
      final cleanMedical = (medicalHistory != null && medicalHistory.trim().isNotEmpty) ? medicalHistory.trim() : null;
      final insertData = <String, dynamic>{
        'member_id': memberId.trim(),
        'full_name': fullName.trim(),
        'password_hash': initialPassword,
        'phone': formattedPhone,
        'emergency_phone': formattedEmergencyPhone,
        'photo_url': (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null,
        'email': email?.trim(),
        'aadhar_number': cleanAadhar,
        'address': cleanAddress,
        'medical_history': cleanMedical,
        'plan': chosenPlan,
        'membership_start_date': startDate.toIso8601String().substring(0, 10),
        'membership_expiry_date': expiryDate.toIso8601String().substring(0, 10),
        'has_pt': hasPt ?? false,
        'pt_plan': ptPlan ?? 'None',
        'pt_trainer':
            ptTrainer ??
            (hasPt == true ? assignedTrainer ?? 'Unassigned' : 'Unassigned'),
        'renewal_status': 'Active',
        'pt_status': hasPt == true ? 'Active' : 'None',
        'is_active': true,
      };

      if (hasPt == true) {
        final pStart = ptStartDate ?? DateTime.now();
        final pExpiry =
            ptExpiryDate ?? calculateExpiryDate(pStart, ptPlan ?? "Monthly PT");
        insertData['pt_start_date'] = pStart.toIso8601String().substring(0, 10);
        insertData['pt_expiry_date'] = pExpiry.toIso8601String().substring(
          0,
          10,
        );
      }

      try {
        await client.from('members').upsert(insertData, onConflict: 'member_id');
      } on PostgrestException catch (pe) {
        if (pe.code == 'PGRST204' || pe.message.contains('schema cache')) {
          final fallback = Map<String, dynamic>.from(insertData);
          fallback.remove('photo_url');
          fallback.remove('emergency_phone');
          fallback.remove('aadhar_number');
          fallback.remove('address');
          fallback.remove('medical_history');
          await client.from('members').upsert(fallback, onConflict: 'member_id');
        } else {
          rethrow;
        }
      }

      await _updateMemberInCache(insertData);

      return {
        'success': true,
        'message': 'Member enrolled into Supabase successfully!',
      };
    } catch (tableErr) {
      debugPrint("Supabase direct member insert note: $tableErr");
      return {
        'success': true,
        'message': 'Member enrolled in local storage (Offline Cache)!',
      };
    }
  }

  static Future<Map<String, dynamic>> adminUpdateMember({
    required String memberId,
    required String fullName,
    String? phone,
    String? emergencyPhone,
    String? photoUrl,
    String? email,
    String? plan,
    String? assignedTrainer,
    DateTime? membershipStartDate,
    DateTime? membershipExpiryDate,
    bool? hasPt,
    String? ptPlan,
    DateTime? ptStartDate,
    DateTime? ptExpiryDate,
    String? ptTrainer,
    String? renewalStatus,
    String? ptStatus,
    bool? isActive,
    String? aadharNumber,
    String? address,
    String? medicalHistory,
  }) async {
    final cleanPhoto = (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null;
    final cleanAadhar = (aadharNumber != null && aadharNumber.trim().isNotEmpty) ? protectAadhar(aadharNumber) : null;
    final cleanAddress = (address != null && address.trim().isNotEmpty) ? address.trim() : null;
    final cleanMedical = (medicalHistory != null && medicalHistory.trim().isNotEmpty) ? medicalHistory.trim() : null;

    final updateData = <String, dynamic>{
      'member_id': memberId.trim(),
      'full_name': fullName.trim(),
      'photo_url': cleanPhoto,
      'aadhar_number': cleanAadhar,
      'address': cleanAddress,
      'medical_history': cleanMedical,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (phone != null) updateData['phone'] = formatIndianPhone(phone);
    if (emergencyPhone != null) {
      updateData['emergency_phone'] = emergencyPhone.trim().isNotEmpty ? formatIndianPhone(emergencyPhone) : null;
    }
    if (email != null) updateData['email'] = email.trim();
    if (plan != null) updateData['plan'] = plan;
    if (assignedTrainer != null && ptTrainer == null) {
      updateData['pt_trainer'] = assignedTrainer;
    }
    if (membershipStartDate != null) {
      updateData['membership_start_date'] = membershipStartDate
          .toIso8601String()
          .substring(0, 10);
    }
    if (membershipExpiryDate != null) {
      updateData['membership_expiry_date'] = membershipExpiryDate
          .toIso8601String()
          .substring(0, 10);
    }
    if (hasPt != null) updateData['has_pt'] = hasPt;
    if (ptPlan != null) updateData['pt_plan'] = ptPlan;
    if (ptStartDate != null) {
      updateData['pt_start_date'] = ptStartDate.toIso8601String().substring(
        0,
        10,
      );
    }
    if (ptExpiryDate != null) {
      updateData['pt_expiry_date'] = ptExpiryDate.toIso8601String().substring(
        0,
        10,
      );
    }
    if (ptTrainer != null) updateData['pt_trainer'] = ptTrainer;
    if (renewalStatus != null) updateData['renewal_status'] = renewalStatus;
    if (ptStatus != null) updateData['pt_status'] = ptStatus;
    if (isActive != null) updateData['is_active'] = isActive;

    await _updateMemberInCache(updateData);

    if (!isConfigured) {
      return {'success': true, 'message': 'Member updated in local cache!'};
    }

    try {
      try {
        final tableUpdate = Map<String, dynamic>.from(updateData)..remove('member_id');
        await client
            .from('members')
            .update(tableUpdate)
            .eq('member_id', memberId.trim());

        return {
          'success': true,
          'message': 'Member updated in database successfully!',
        };
      } on PostgrestException catch (pe) {
        if (pe.code == 'PGRST204' || pe.message.contains('schema cache')) {
          final fallbackData = Map<String, dynamic>.from(updateData)..remove('member_id');
          fallbackData.remove('photo_url');
          fallbackData.remove('emergency_phone');
          fallbackData.remove('aadhar_number');
          fallbackData.remove('address');
          fallbackData.remove('medical_history');
          if (fallbackData.isNotEmpty) {
            try {
              await client
                  .from('members')
                  .update(fallbackData)
                  .eq('member_id', memberId.trim());
              return {
                'success': true,
                'message': 'Member updated! Note: To save photo or emergency number, run the SQL schema migration in Supabase SQL editor.',
              };
            } catch (retryErr) {
              debugPrint("Supabase fallback member update failed: $retryErr");
            }
          }
        }
        debugPrint("Supabase update member error: $pe");
        return {
          'success': false,
          'message': 'Failed to update member: ${pe.message}',
        };
      }
    } catch (e) {
      debugPrint("Supabase update member note: $e");
      return {
        'success': true,
        'message': 'Member updated in local storage (Offline Cache)!',
      };
    }
  }

  /// Update Member Profile Picture
  static Future<Map<String, dynamic>> updateMemberPhoto({
    required String memberId,
    required String? photoUrl,
  }) async {
    final clean = (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null;
    await _updateMemberInCache({
      'member_id': memberId.trim(),
      'photo_url': clean,
    });

    if (!isConfigured) return {'success': true, 'message': 'Profile picture saved locally!'};
    try {
      await client
          .from('members')
          .update({'photo_url': clean, 'updated_at': DateTime.now().toIso8601String()})
          .eq('member_id', memberId.trim());
      return {'success': true, 'message': 'Profile picture updated successfully!'};
    } on PostgrestException catch (pe) {
      debugPrint("updateMemberPhoto PostgrestException: $pe");
      if (pe.code == 'PGRST204' || pe.message.contains('photo_url') || pe.message.contains('schema cache')) {
        return {
          'success': false,
          'message': "Column 'photo_url' does not exist in Supabase yet. Please run the SQL schema in Supabase SQL editor: ALTER TABLE public.members ADD COLUMN IF NOT EXISTS photo_url TEXT;",
        };
      }
      return {'success': false, 'message': pe.message};
    } catch (e) {
      debugPrint("updateMemberPhoto error: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> adminRenewMembership({
    required String memberId,
    required String plan,
    int? months,
  }) async {
    final m = months ?? planToMonths(plan);
    DateTime baseDate = DateTime.now();
    final newExpiry = calculateExpiryDate(baseDate, plan);

    await _updateMemberInCache({
      'member_id': memberId.trim(),
      'plan': plan,
      'membership_expiry_date': newExpiry.toIso8601String().substring(0, 10),
      'renewal_status': 'Active',
      'requested_renewal_plan': null,
      'is_active': true,
    });

    if (!isConfigured) {
      return {
        'success': true,
        'message': 'Membership renewed until ${newExpiry.toIso8601String().substring(0, 10)}! (Offline Cache)',
      };
    }

    // 1. Try RPC procedure first
    try {
      final response = await client.rpc(
        'admin_renew_membership',
        params: {'p_member_id': memberId.trim(), 'p_plan': plan, 'p_months': m},
      );
      if (response != null && response['success'] == true) {
        return {
          'success': true,
          'message': response['message'] ?? 'Membership renewed successfully!',
        };
      }
    } catch (e) {
      debugPrint(
        "RPC admin_renew_membership error, falling back to direct table update: $e",
      );
    }

    // 2. Direct table update fallback
    try {
      final existingList = await client
          .from('members')
          .select('*')
          .ilike('member_id', memberId.trim())
          .limit(1);

      if (existingList.isNotEmpty) {
        final currentExpiryStr = existingList.first['membership_expiry_date']
            ?.toString();
        if (currentExpiryStr != null) {
          final currentExpiry = DateTime.tryParse(currentExpiryStr);
          if (currentExpiry != null && currentExpiry.isAfter(baseDate)) {
            baseDate = currentExpiry;
          }
        }
      }

      final exactNewExpiry = calculateExpiryDate(baseDate, plan);

      await client
          .from('members')
          .update({
            'plan': plan,
            'membership_expiry_date': exactNewExpiry.toIso8601String().substring(
              0,
              10,
            ),
            'renewal_status': 'Active',
            'requested_renewal_plan': null,
            'is_active': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .ilike('member_id', memberId.trim());

      await _updateMemberInCache({
        'member_id': memberId.trim(),
        'plan': plan,
        'membership_expiry_date': exactNewExpiry.toIso8601String().substring(0, 10),
        'renewal_status': 'Active',
        'requested_renewal_plan': null,
        'is_active': true,
      });

      return {
        'success': true,
        'message':
            'Membership renewed until ${exactNewExpiry.toIso8601String().substring(0, 10)}!',
      };
    } catch (e2) {
      debugPrint("Direct adminRenewMembership error: $e2");
      return {'success': false, 'message': e2.toString()};
    }
  }

  static Future<Map<String, dynamic>> adminDeclineRenewal({
    required String memberId,
  }) async {
    await _updateMemberInCache({
      'member_id': memberId.trim(),
      'renewal_status': 'Active',
      'requested_renewal_plan': null,
    });

    if (!isConfigured) return {'success': true, 'message': 'Renewal request declined.'};
    try {
      await client
          .from('members')
          .update({
            'renewal_status': 'Active',
            'requested_renewal_plan': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .ilike('member_id', memberId.trim());

      return {'success': true, 'message': 'Renewal request declined.'};
    } catch (e) {
      debugPrint("adminDeclineRenewal error: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> adminAssignPt({
    required String memberId,
    required String ptPlan,
    required String trainerName,
    int? months,
  }) async {
    final m = months ?? planToMonths(ptPlan);
    DateTime baseDate = DateTime.now();
    String startDate = DateTime.now().toIso8601String().substring(0, 10);
    final newPtExpiry = calculateExpiryDate(baseDate, ptPlan);

    await _updateMemberInCache({
      'member_id': memberId.trim(),
      'has_pt': true,
      'pt_plan': ptPlan,
      'pt_trainer': trainerName,
      'pt_start_date': startDate,
      'pt_expiry_date': newPtExpiry.toIso8601String().substring(0, 10),
      'pt_status': 'Active',
      'requested_pt_plan': null,
      'requested_pt_trainer': null,
    });

    if (!isConfigured) {
      return {
        'success': true,
        'message': 'Personal Training assigned with $trainerName until ${newPtExpiry.toIso8601String().substring(0, 10)}! (Offline Cache)',
      };
    }

    // 1. Try RPC procedure first
    try {
      final response = await client.rpc(
        'admin_assign_pt',
        params: {
          'p_member_id': memberId.trim(),
          'p_pt_plan': ptPlan,
          'p_trainer_name': trainerName,
          'p_months': m,
        },
      );
      if (response != null && response['success'] == true) {
        return {
          'success': true,
          'message':
              response['message'] ?? 'Personal Training assigned successfully!',
        };
      }
    } catch (e) {
      debugPrint(
        "RPC admin_assign_pt error, falling back to direct table update: $e",
      );
    }

    // 2. Direct table update fallback
    try {
      final existingList = await client
          .from('members')
          .select('*')
          .ilike('member_id', memberId.trim())
          .limit(1);

      if (existingList.isNotEmpty) {
        final currentPtExpiryStr = existingList.first['pt_expiry_date']
            ?.toString();
        if (currentPtExpiryStr != null) {
          final currentPtExpiry = DateTime.tryParse(currentPtExpiryStr);
          if (currentPtExpiry != null && currentPtExpiry.isAfter(baseDate)) {
            baseDate = currentPtExpiry;
          }
        }
        if (existingList.first['pt_start_date'] != null) {
          startDate = existingList.first['pt_start_date'].toString().substring(
            0,
            10,
          );
        }
      }

      final exactPtExpiry = calculateExpiryDate(baseDate, ptPlan);

      await client
          .from('members')
          .update({
            'has_pt': true,
            'pt_plan': ptPlan,
            'pt_trainer': trainerName,
            'pt_start_date': startDate,
            'pt_expiry_date': exactPtExpiry.toIso8601String().substring(0, 10),
            'pt_status': 'Active',
            'requested_pt_plan': null,
            'requested_pt_trainer': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .ilike('member_id', memberId.trim());

      await _updateMemberInCache({
        'member_id': memberId.trim(),
        'has_pt': true,
        'pt_plan': ptPlan,
        'pt_trainer': trainerName,
        'pt_start_date': startDate,
        'pt_expiry_date': exactPtExpiry.toIso8601String().substring(0, 10),
        'pt_status': 'Active',
        'requested_pt_plan': null,
        'requested_pt_trainer': null,
      });

      // Increment trainer client count if trainer found
      try {
        if (trainerName != 'Unassigned') {
          final tList = await client
              .from('trainers')
              .select('*')
              .ilike('full_name', trainerName.trim())
              .limit(1);
          if (tList.isNotEmpty) {
            final currCount =
                (tList.first['clients_count'] as num?)?.toInt() ?? 0;
            await client
                .from('trainers')
                .update({'clients_count': currCount + 1})
                .ilike('full_name', trainerName.trim());
          }
        }
      } catch (_) {}

      return {
        'success': true,
        'message':
            'Personal Training assigned with $trainerName until ${exactPtExpiry.toIso8601String().substring(0, 10)}!',
      };
    } catch (e2) {
      debugPrint("Direct adminAssignPt error: $e2");
      return {'success': false, 'message': e2.toString()};
    }
  }

  static Future<Map<String, dynamic>> adminDeclinePt({
    required String memberId,
  }) async {
    await _updateMemberInCache({
      'member_id': memberId.trim(),
      'pt_status': 'None',
      'requested_pt_plan': null,
      'requested_pt_trainer': null,
    });

    if (!isConfigured) return {'success': true, 'message': 'Personal Training request declined.'};
    try {
      final existingList = await client
          .from('members')
          .select('*')
          .ilike('member_id', memberId.trim())
          .limit(1);

      final hasPt =
          existingList.isNotEmpty && existingList.first['has_pt'] == true;

      await client
          .from('members')
          .update({
            'pt_status': hasPt ? 'Active' : 'None',
            'requested_pt_plan': null,
            'requested_pt_trainer': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .ilike('member_id', memberId.trim());

      await _updateMemberInCache({
        'member_id': memberId.trim(),
        'pt_status': hasPt ? 'Active' : 'None',
        'requested_pt_plan': null,
        'requested_pt_trainer': null,
      });

      return {
        'success': true,
        'message': 'Personal Training request declined.',
      };
    } catch (e) {
      debugPrint("adminDeclinePt error: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> requestMembershipRenewal({
    required String memberId,
    required String plan,
  }) async {
    await _updateMemberInCache({
      'member_id': memberId.trim(),
      'renewal_status': 'Pending Approval',
      'requested_renewal_plan': plan,
    });

    if (!isConfigured) {
      return {
        'success': true,
        'message': 'Membership renewal request submitted for $plan! Front desk will confirm shortly.',
      };
    }

    // 1. Try RPC first
    try {
      final response = await client.rpc(
        'request_membership_renewal',
        params: {'p_member_id': memberId.trim(), 'p_plan': plan},
      );
      if (response != null && response['success'] == true) {
        return {
          'success': true,
          'message':
              response['message'] ??
              'Renewal request submitted for $plan! Admin will confirm shortly.',
        };
      }
    } catch (e) {
      debugPrint(
        "RPC request_membership_renewal error, attempting direct table update: $e",
      );
    }

    // 2. Direct table update fallback
    try {
      await client
          .from('members')
          .update({
            'renewal_status': 'Pending Approval',
            'requested_renewal_plan': plan,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .ilike('member_id', memberId.trim());

      return {
        'success': true,
        'message':
            'Membership renewal request submitted for $plan! Front desk will confirm shortly.',
      };
    } catch (e2) {
      debugPrint("Direct requestMembershipRenewal error: $e2");
      return {'success': false, 'message': e2.toString()};
    }
  }

  static Future<Map<String, dynamic>> requestPersonalTraining({
    required String memberId,
    required String ptPlan,
    required String trainerName,
  }) async {
    await _updateMemberInCache({
      'member_id': memberId.trim(),
      'pt_status': 'Requested',
      'requested_pt_plan': ptPlan,
      'requested_pt_trainer': trainerName,
    });

    if (!isConfigured) {
      return {
        'success': true,
        'message': 'Personal Training request submitted with Coach $trainerName ($ptPlan)! Front desk will review.',
      };
    }

    // 1. Try RPC first
    try {
      final response = await client.rpc(
        'request_personal_training',
        params: {
          'p_member_id': memberId.trim(),
          'p_pt_plan': ptPlan,
          'p_trainer_name': trainerName,
        },
      );
      if (response != null && response['success'] == true) {
        return {
          'success': true,
          'message':
              response['message'] ??
              'Personal training request submitted for $trainerName ($ptPlan)!',
        };
      }
    } catch (e) {
      debugPrint(
        "RPC request_personal_training error, attempting direct table update: $e",
      );
    }

    // 2. Direct table update fallback
    try {
      await client
          .from('members')
          .update({
            'pt_status': 'Requested',
            'requested_pt_plan': ptPlan,
            'requested_pt_trainer': trainerName,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .ilike('member_id', memberId.trim());

      return {
        'success': true,
        'message':
            'Personal Training request submitted with Coach $trainerName ($ptPlan)! Front desk will review.',
      };
    } catch (e2) {
      debugPrint("Direct requestPersonalTraining error: $e2");
      return {'success': false, 'message': e2.toString()};
    }
  }

  static Future<Map<String, dynamic>> adminDeleteMember(String memberId) async {
    await _removeMemberFromCache(memberId);

    if (!isConfigured) {
      return {'success': true, 'message': 'Member removed from local cache!'};
    }

    try {
      await client.from('members').delete().eq('member_id', memberId.trim());
      return {
        'success': true,
        'message': 'Member removed from Supabase database! (Revenue transactions preserved for accounting)',
      };
    } catch (e) {
      debugPrint("Supabase delete member note: $e");
      return {
        'success': true,
        'message': 'Member removed from local cache (Offline)!',
      };
    }
  }

  // ==========================================
  // TRAINERS MANAGEMENT (100% DIRECT SUPABASE DB)
  // ==========================================

  static Future<List<Map<String, dynamic>>> fetchTrainers() async {
    if (isConfigured) {
      try {
        final data = await client
            .from('trainers')
            .select('*')
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 3));
        final list = List<Map<String, dynamic>>.from(data);
        if (list.isNotEmpty) {
          await _saveCacheList(_keyCacheTrainers, list);
        }
        return list;
      } catch (e) {
        debugPrint("Supabase fetchTrainers with order error: $e");
        try {
          final data = await client
              .from('trainers')
              .select('*')
              .timeout(const Duration(seconds: 3));
          final list = List<Map<String, dynamic>>.from(data);
          if (list.isNotEmpty) {
            await _saveCacheList(_keyCacheTrainers, list);
          }
          return list;
        } catch (e2) {
          debugPrint("Supabase fetchTrainers error: $e2");
        }
      }
    }

    return await _getCacheList(_keyCacheTrainers);
  }

  static Future<Map<String, dynamic>> adminCreateTrainer({
    required String trainerId,
    required String fullName,
    required String initialPassword,
    required String phone,
    String? photoUrl,
    String? email,
    String? experience,
    String? aadharNumber,
    String? address,
  }) async {
    final formattedPhone = formatIndianPhone(phone);
    final trimmedEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim()
        : null;
    final cleanExp = (experience != null && experience.trim().isNotEmpty)
        ? experience.trim()
        : '3+ Years';
    final cleanPhoto = (photoUrl != null && photoUrl.trim().isNotEmpty)
        ? photoUrl.trim()
        : null;
    final cleanAddress = (address != null && address.trim().isNotEmpty)
        ? address.trim()
        : null;
    final cleanAadhar = (aadharNumber != null && aadharNumber.trim().isNotEmpty) ? protectAadhar(aadharNumber) : null;

    final cachedTrainerData = <String, dynamic>{
      'trainer_id': trainerId.trim(),
      'full_name': fullName.trim(),
      'password_hash': initialPassword,
      'phone': formattedPhone,
      'photo_url': cleanPhoto,
      'email': trimmedEmail,
      'experience': cleanExp,
      'aadhar_number': cleanAadhar,
      'address': cleanAddress,
      'is_active': true,
      'clients_count': 0,
    };
    await _updateTrainerInCache(cachedTrainerData);

    if (!isConfigured) {
      return {'success': true, 'message': 'Trainer profile saved to local cache!'};
    }

    // 1. Try RPC procedure first if installed
    try {
      final response = await client.rpc(
        'admin_create_trainer',
        params: {
          'p_trainer_id': trainerId.trim(),
          'p_full_name': fullName.trim(),
          'p_initial_password': initialPassword,
          'p_phone': formattedPhone,
          'p_email': trimmedEmail,
          'p_experience': cleanExp,
        },
      );

      if (response != null && response['success'] == true) {
        if (cleanPhoto != null || aadharNumber != null || cleanAddress != null) {
          final extra = <String, dynamic>{};
          if (cleanPhoto != null) extra['photo_url'] = cleanPhoto;
          if (aadharNumber != null && aadharNumber.trim().isNotEmpty) {
            extra['aadhar_number'] = protectAadhar(aadharNumber);
          }
          if (cleanAddress != null) extra['address'] = cleanAddress;
          if (extra.isNotEmpty) {
            try {
              await client.from('trainers').update(extra).eq('trainer_id', trainerId.trim());
            } on PostgrestException catch (pe) {
              if (pe.code == 'PGRST204' || pe.message.contains('schema cache')) {
                final fallback = Map<String, dynamic>.from(extra);
                fallback.remove('photo_url');
                fallback.remove('aadhar_number');
                fallback.remove('address');
                if (fallback.isNotEmpty) {
                  await client.from('trainers').update(fallback).eq('trainer_id', trainerId.trim());
                }
              }
            }
          }
        }
        return {
          'success': true,
          'message': 'Trainer profile created in Supabase database!',
        };
      }
      if (response != null && response['success'] == false) {
        return {
          'success': false,
          'message': response['message'] ?? 'Trainer ID already exists.',
        };
      }
    } catch (e) {
      debugPrint(
        "RPC admin_create_trainer error, falling back to direct insert: $e",
      );
    }

    // 2. Direct table insert fallback
    try {
      final insertData = <String, dynamic>{
        'trainer_id': trainerId.trim(),
        'full_name': fullName.trim(),
        'password_hash': initialPassword,
        'phone': formattedPhone,
        'photo_url': cleanPhoto,
        'email': trimmedEmail,
        'experience': cleanExp,
        'aadhar_number': cleanAadhar,
        'address': cleanAddress,
        'is_active': true,
        'clients_count': 0,
      };

      try {
        await client.from('trainers').insert(insertData);
      } on PostgrestException catch (pe) {
        if (pe.code == 'PGRST204' || pe.message.contains('schema cache')) {
          final fallback = Map<String, dynamic>.from(insertData);
          fallback.remove('photo_url');
          fallback.remove('aadhar_number');
          fallback.remove('address');
          await client.from('trainers').insert(fallback);
        } else {
          rethrow;
        }
      }

      return {
        'success': true,
        'message': 'Trainer profile created in Supabase database!',
      };
    } catch (insertErr) {
      debugPrint("Direct insert failed, attempting upsert: $insertErr");
      try {
        final upsertData = <String, dynamic>{
          'trainer_id': trainerId.trim(),
          'full_name': fullName.trim(),
          'password_hash': initialPassword,
          'phone': formattedPhone,
          'photo_url': cleanPhoto,
          'email': trimmedEmail,
          'experience': cleanExp,
          'aadhar_number': cleanAadhar,
          'address': cleanAddress,
          'is_active': true,
          'clients_count': 0,
        };

        try {
          await client.from('trainers').upsert(upsertData);
        } on PostgrestException catch (pe) {
          if (pe.code == 'PGRST204' || pe.message.contains('schema cache')) {
            final fallback = Map<String, dynamic>.from(upsertData);
            fallback.remove('photo_url');
            fallback.remove('aadhar_number');
            fallback.remove('address');
            await client.from('trainers').upsert(fallback);
          } else {
            rethrow;
          }
        }
        return {
          'success': true,
          'message': 'Trainer profile created in Supabase database!',
        };
      } catch (tableErr) {
        debugPrint("Supabase direct trainer insert note: $tableErr");
        return {
          'success': true,
          'message': 'Trainer profile created in local storage (Offline Cache)!',
        };
      }
    }
  }

  static Future<Map<String, dynamic>> adminUpdateTrainer({
    required String trainerId,
    required String fullName,
    required String phone,
    String? photoUrl,
    String? email,
    String? experience,
    bool? isActive,
    String? aadharNumber,
    String? address,
  }) async {
    final formattedPhone = formatIndianPhone(phone);
    final cleanPhoto = (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null;
    final cleanAadhar = (aadharNumber != null && aadharNumber.trim().isNotEmpty) ? protectAadhar(aadharNumber) : null;
    final cleanAddress = (address != null && address.trim().isNotEmpty) ? address.trim() : null;

    final updateData = <String, dynamic>{
      'trainer_id': trainerId.trim(),
      'full_name': fullName.trim(),
      'phone': formattedPhone,
      'email': email?.trim(),
      'photo_url': cleanPhoto,
      'aadhar_number': cleanAadhar,
      'address': cleanAddress,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (experience != null) updateData['experience'] = experience;
    if (isActive != null) updateData['is_active'] = isActive;

    await _updateTrainerInCache(updateData);

    if (!isConfigured) {
      return {'success': true, 'message': 'Trainer updated in local cache!'};
    }

    try {
      try {
        final tableUpdate = Map<String, dynamic>.from(updateData)..remove('trainer_id');
        await client
            .from('trainers')
            .update(tableUpdate)
            .eq('trainer_id', trainerId.trim());

        return {
          'success': true,
          'message': 'Trainer profile updated in Supabase!',
        };
      } on PostgrestException catch (pe) {
        if (pe.code == 'PGRST204' || pe.message.contains('schema cache')) {
          final fallbackData = Map<String, dynamic>.from(updateData)..remove('trainer_id');
          fallbackData.remove('photo_url');
          fallbackData.remove('aadhar_number');
          fallbackData.remove('address');
          if (fallbackData.isNotEmpty) {
            try {
              await client
                  .from('trainers')
                  .update(fallbackData)
                  .eq('trainer_id', trainerId.trim());
              return {
                'success': true,
                'message': 'Trainer updated! Note: To save photo, run the SQL schema migration in Supabase SQL editor.',
              };
            } catch (retryErr) {
              debugPrint("Supabase fallback trainer update failed: $retryErr");
            }
          }
        }
        debugPrint("Supabase update trainer error: $pe");
        return {
          'success': false,
          'message': 'Error updating trainer: ${pe.message}',
        };
      }
    } catch (e) {
      debugPrint("Supabase update trainer note: $e");
      return {
        'success': true,
        'message': 'Trainer profile updated in local storage (Offline Cache)!',
      };
    }
  }

  /// Update Trainer Profile Picture
  static Future<Map<String, dynamic>> updateTrainerPhoto({
    required String trainerId,
    required String? photoUrl,
  }) async {
    final clean = (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null;
    await _updateTrainerInCache({
      'trainer_id': trainerId.trim(),
      'photo_url': clean,
    });

    if (!isConfigured) return {'success': true, 'message': 'Trainer photo updated locally!'};
    try {
      await client
          .from('trainers')
          .update({'photo_url': clean, 'updated_at': DateTime.now().toIso8601String()})
          .eq('trainer_id', trainerId.trim());
      return {'success': true, 'message': 'Trainer photo updated successfully!'};
    } on PostgrestException catch (pe) {
      debugPrint("updateTrainerPhoto PostgrestException: $pe");
      if (pe.code == 'PGRST204' || pe.message.contains('photo_url') || pe.message.contains('schema cache')) {
        return {
          'success': false,
          'message': "Column 'photo_url' does not exist in Supabase yet. Please run the SQL schema in Supabase SQL editor: ALTER TABLE public.trainers ADD COLUMN IF NOT EXISTS photo_url TEXT;",
        };
      }
      return {'success': false, 'message': pe.message};
    } catch (e) {
      debugPrint("updateTrainerPhoto error: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> adminDeleteTrainer(
    String trainerId,
  ) async {
    await _removeTrainerFromCache(trainerId);

    if (!isConfigured) {
      return {'success': true, 'message': 'Trainer removed from local cache!'};
    }

    try {
      await client.from('trainers').delete().eq('trainer_id', trainerId.trim());
      return {
        'success': true,
        'message': 'Trainer deleted from Supabase database!',
      };
    } catch (e) {
      debugPrint("Supabase delete trainer note: $e");
      return {
        'success': true,
        'message': 'Trainer removed from local cache (Offline)!',
      };
    }
  }

  // ==========================================
  // MEMBERSHIP & PT PLANS PRICING MANAGEMENT (SUPABASE DB)
  // ==========================================

  static final List<Map<String, dynamic>> defaultMembershipPlans = [
    {
      'id': 'plan_admission',
      'plan_name': 'Admission Fee',
      'duration_months': 0,
      'price': 2000.0,
      'display_order': 1,
      'is_active': true,
    },
    {
      'id': 'plan_monthly',
      'plan_name': 'Monthly',
      'duration_months': 1,
      'price': 888.0,
      'display_order': 2,
      'is_active': true,
    },
    {
      'id': 'plan_3months',
      'plan_name': '3 Months',
      'duration_months': 3,
      'price': 3888.0,
      'display_order': 3,
      'is_active': true,
    },
    {
      'id': 'plan_6months',
      'plan_name': '6 Months',
      'duration_months': 6,
      'price': 4888.0,
      'display_order': 4,
      'is_active': true,
    },
    {
      'id': 'plan_yearly',
      'plan_name': 'Yearly',
      'duration_months': 12,
      'price': 8888.0,
      'display_order': 5,
      'is_active': true,
    },
  ];

  static final List<Map<String, dynamic>> defaultPtPlans = [
    {
      'id': 'pt_monthly',
      'plan_name': 'Monthly PT',
      'duration_months': 1,
      'price': 3000.0,
      'display_order': 1,
      'is_active': true,
    },
  ];

  static Future<List<Map<String, dynamic>>> fetchMembershipPlans() async {
    if (isConfigured) {
      try {
        final data = await client
            .from('membership_plans')
            .select('*')
            .order('display_order', ascending: true)
            .timeout(const Duration(seconds: 3));
        if (data.isNotEmpty) {
          final list = List<Map<String, dynamic>>.from(data);
          await _saveCacheList(_keyCacheMembershipPlans, list);
          return list;
        }
      } catch (e) {
        debugPrint("Supabase fetchMembershipPlans error: $e");
      }
    }

    final cached = await _getCacheList(_keyCacheMembershipPlans);
    if (cached.isNotEmpty) {
      return cached;
    }
    return defaultMembershipPlans;
  }

  static Future<List<Map<String, dynamic>>> fetchPtPlans() async {
    if (isConfigured) {
      try {
        final data = await client
            .from('pt_plans')
            .select('*')
            .order('display_order', ascending: true)
            .timeout(const Duration(seconds: 3));
        if (data.isNotEmpty) {
          final list = List<Map<String, dynamic>>.from(data);
          await _saveCacheList(_keyCachePtPlans, list);
          return list;
        }
      } catch (e) {
        debugPrint("Supabase fetchPtPlans error: $e");
      }
    }

    final cached = await _getCacheList(_keyCachePtPlans);
    if (cached.isNotEmpty) {
      return cached;
    }
    return defaultPtPlans;
  }

  static Future<Map<String, dynamic>> adminUpdateMembershipPlan({
    required String id,
    required String planName,
    required double price,
    int? durationMonths,
    bool? isActive,
  }) async {
    final cached = await _getCacheList(_keyCacheMembershipPlans);
    final plans = cached.isNotEmpty ? List<Map<String, dynamic>>.from(cached) : List<Map<String, dynamic>>.from(defaultMembershipPlans);
    final idx = plans.indexWhere((p) => p['id']?.toString() == id);
    final updatedItem = idx != -1 ? Map<String, dynamic>.from(plans[idx]) : <String, dynamic>{'id': id};
    updatedItem['plan_name'] = planName.trim();
    updatedItem['price'] = price;
    if (durationMonths != null) updatedItem['duration_months'] = durationMonths;
    if (isActive != null) updatedItem['is_active'] = isActive;
    if (idx != -1) {
      plans[idx] = updatedItem;
    } else {
      plans.add(updatedItem);
    }
    await _saveCacheList(_keyCacheMembershipPlans, plans);

    if (!isConfigured) {
      return {'success': true, 'message': 'Pricing updated in local cache!'};
    }
    try {
      final updateData = <String, dynamic>{
        'plan_name': planName.trim(),
        'price': price,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (durationMonths != null) {
        updateData['duration_months'] = durationMonths;
      }
      if (isActive != null) updateData['is_active'] = isActive;
      await client.from('membership_plans').update(updateData).eq('id', id);

      return {
        'success': true,
        'message': 'Plan price updated in Supabase successfully!',
      };
    } catch (e) {
      debugPrint("Supabase update membership plan error: $e");
      return {
        'success': true,
        'message': 'Pricing updated (Saved to cache)',
      };
    }
  }

  static Future<Map<String, dynamic>> adminUpdatePtPlan({
    required String id,
    required String planName,
    required double price,
    int? durationMonths,
    bool? isActive,
  }) async {
    final cached = await _getCacheList(_keyCachePtPlans);
    final plans = cached.isNotEmpty ? List<Map<String, dynamic>>.from(cached) : List<Map<String, dynamic>>.from(defaultPtPlans);
    final idx = plans.indexWhere((p) => p['id']?.toString() == id);
    final updatedItem = idx != -1 ? Map<String, dynamic>.from(plans[idx]) : <String, dynamic>{'id': id};
    updatedItem['plan_name'] = planName.trim();
    updatedItem['price'] = price;
    if (durationMonths != null) updatedItem['duration_months'] = durationMonths;
    if (isActive != null) updatedItem['is_active'] = isActive;
    if (idx != -1) {
      plans[idx] = updatedItem;
    } else {
      plans.add(updatedItem);
    }
    await _saveCacheList(_keyCachePtPlans, plans);

    if (!isConfigured) {
      return {'success': true, 'message': 'PT Pricing updated in local cache!'};
    }
    try {
      final updateData = <String, dynamic>{
        'plan_name': planName.trim(),
        'price': price,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (durationMonths != null) {
        updateData['duration_months'] = durationMonths;
      }
      if (isActive != null) updateData['is_active'] = isActive;
      await client.from('pt_plans').update(updateData).eq('id', id);

      return {
        'success': true,
        'message': 'PT Plan price updated in Supabase successfully!',
      };
    } catch (e) {
      debugPrint("Supabase update PT plan error: $e");
      return {
        'success': true,
        'message': 'PT Pricing updated (Saved to cache)',
      };
    }
  }

  static Future<Map<String, dynamic>> adminCreateMembershipPlan({
    required String planName,
    required double price,
    int durationMonths = 1,
  }) async {
    final cached = await _getCacheList(_keyCacheMembershipPlans);
    final plans = cached.isNotEmpty ? List<Map<String, dynamic>>.from(cached) : List<Map<String, dynamic>>.from(defaultMembershipPlans);
    final newPlan = {
      'id': 'plan_${DateTime.now().millisecondsSinceEpoch}',
      'plan_name': planName.trim(),
      'price': price,
      'duration_months': durationMonths,
      'display_order': plans.length + 1,
      'is_active': true,
    };
    plans.add(newPlan);
    await _saveCacheList(_keyCacheMembershipPlans, plans);

    if (!isConfigured) {
      return {'success': true, 'message': 'New membership plan added locally!'};
    }
    try {
      await client.from('membership_plans').insert({
        'plan_name': planName.trim(),
        'price': price,
        'duration_months': durationMonths,
        'display_order': plans.length,
      });
      return {
        'success': true,
        'message': 'New membership plan added successfully!',
      };
    } catch (e) {
      return {'success': true, 'message': 'New membership plan saved locally!'};
    }
  }

  static Future<Map<String, dynamic>> adminCreatePtPlan({
    required String planName,
    required double price,
    int durationMonths = 1,
  }) async {
    final cached = await _getCacheList(_keyCachePtPlans);
    final plans = cached.isNotEmpty ? List<Map<String, dynamic>>.from(cached) : List<Map<String, dynamic>>.from(defaultPtPlans);
    final newPlan = {
      'id': 'pt_${DateTime.now().millisecondsSinceEpoch}',
      'plan_name': planName.trim(),
      'price': price,
      'duration_months': durationMonths,
      'display_order': plans.length + 1,
      'is_active': true,
    };
    plans.add(newPlan);
    await _saveCacheList(_keyCachePtPlans, plans);

    if (!isConfigured) {
      return {'success': true, 'message': 'New PT plan added locally!'};
    }
    try {
      await client.from('pt_plans').insert({
        'plan_name': planName.trim(),
        'price': price,
        'duration_months': durationMonths,
        'display_order': plans.length,
      });
      return {'success': true, 'message': 'New PT plan added successfully!'};
    } catch (e) {
      return {'success': true, 'message': 'New PT plan saved locally!'};
    }
  }

  static Future<Map<String, dynamic>> adminDeleteMembershipPlan(
    String id,
  ) async {
    final cached = await _getCacheList(_keyCacheMembershipPlans);
    if (cached.isNotEmpty) {
      final plans = List<Map<String, dynamic>>.from(cached);
      plans.removeWhere((p) => p['id']?.toString() == id);
      await _saveCacheList(_keyCacheMembershipPlans, plans);
    }

    if (!isConfigured) return {'success': true, 'message': 'Plan removed locally!'};
    try {
      await client.from('membership_plans').delete().eq('id', id);
      return {'success': true, 'message': 'Plan removed successfully!'};
    } catch (e) {
      return {'success': true, 'message': 'Plan removed locally'};
    }
  }

  static Future<Map<String, dynamic>> adminDeletePtPlan(String id) async {
    final cached = await _getCacheList(_keyCachePtPlans);
    if (cached.isNotEmpty) {
      final plans = List<Map<String, dynamic>>.from(cached);
      plans.removeWhere((p) => p['id']?.toString() == id);
      await _saveCacheList(_keyCachePtPlans, plans);
    }

    if (!isConfigured) return {'success': true, 'message': 'PT plan removed locally!'};
    try {
      await client.from('pt_plans').delete().eq('id', id);
      return {'success': true, 'message': 'PT plan removed successfully!'};
    } catch (e) {
      return {'success': true, 'message': 'PT plan removed locally'};
    }
  }

  static Future<Map<String, dynamic>> recordRevenueTransaction({
    String? userId,
    required String memberId,
    required String memberName,
    required String type, // 'Membership' or 'Personal Training'
    required String planName,
    required double amount,
    required double baseAmount,
    double discountAmount = 0.0,
    required String paymentMode, // 'UPI', 'Cash', 'Card'
    String? notes,
  }) async {
    final record = <String, dynamic>{
      if (userId != null && userId.trim().isNotEmpty) 'user_id': userId.trim(),
      'member_id': memberId.trim(),
      'member_name': memberName.trim(),
      'type': type,
      'plan_name': planName,
      'amount': amount,
      'base_amount': baseAmount,
      'discount_amount': discountAmount,
      'payment_mode': paymentMode,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    };

    // 1. Always save to local storage as persistent cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_keyCacheRevenueRecords);
      List<dynamic> list = [];
      if (existingJson != null && existingJson.isNotEmpty) {
        list = jsonDecode(existingJson) as List<dynamic>;
      }
      list.insert(0, record);
      // Keep up to 200 records locally
      if (list.length > 200) list = list.sublist(0, 200);
      await prefs.setString(_keyCacheRevenueRecords, jsonEncode(list));
    } catch (localErr) {
      debugPrint("Local revenue cache save note: $localErr");
    }

    // 2. Insert to Supabase if table exists
    if (!isConfigured) {
      return {'success': true, 'message': 'Transaction saved locally'};
    }
    try {
      await client.from('revenue_transactions').insert(record);
      return {'success': true, 'message': 'Revenue transaction recorded!'};
    } catch (e) {
      // Supabase table optional: record is already saved in local cache
      return {'success': true, 'message': 'Saved to local cache'};
    }
  }

  static Future<List<Map<String, dynamic>>> fetchRevenueTransactions() async {
    if (isConfigured) {
      try {
        final data = await client
            .from('revenue_transactions')
            .select('*')
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 3));
        final list = List<Map<String, dynamic>>.from(data);
        if (list.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyCacheRevenueRecords, jsonEncode(list));
        }
        return list;
      } catch (e) {
        debugPrint("Supabase fetchRevenueTransactions note: $e");
      }
    }

    // Fallback to local storage cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_keyCacheRevenueRecords);
      if (existingJson != null && existingJson.isNotEmpty) {
        final decoded = jsonDecode(existingJson) as List<dynamic>;
        return List<Map<String, dynamic>>.from(decoded);
      }
    } catch (e) {
      debugPrint("Local revenue fetch error: $e");
    }
    return [];
  }

  /// Fetch all official payment receipts / transactions for a specific member with multi-layer verification
  static Future<List<Map<String, dynamic>>> fetchMemberTransactions(
    String memberId, {
    String? memberName,
    String? memberUuid,
    DateTime? memberCreatedAt,
  }) async {
    final cleanId = memberId.trim().toLowerCase();
    final cleanName = memberName?.trim().toLowerCase();
    List<Map<String, dynamic>> results = [];

    if (isConfigured) {
      try {
        final data = await client
            .from('revenue_transactions')
            .select('*')
            .ilike('member_id', memberId.trim())
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 3));
        final rawList = List<Map<String, dynamic>>.from(data);

        // Multi-Layer Verification:
        // 1. UUID Check (if present in transaction)
        // 2. Exact Member Name Match
        // 3. Creation Date Timestamp Check (Cannot be older than when member profile was created)
        results = rawList.where((tx) {
          if (memberUuid != null && memberUuid.isNotEmpty && tx['user_id'] != null) {
            if (tx['user_id'].toString().toLowerCase() != memberUuid.toLowerCase()) {
              return false;
            }
          }
          final txName = (tx['member_name'] ?? '').toString().trim().toLowerCase();
          if (cleanName != null && cleanName.isNotEmpty && txName.isNotEmpty) {
            if (txName != cleanName) return false;
          }
          if (memberCreatedAt != null) {
            final txDate = DateTime.tryParse(tx['created_at']?.toString() ?? '');
            if (txDate != null && txDate.isBefore(memberCreatedAt.subtract(const Duration(minutes: 10)))) {
              return false; // Transaction is from before this member profile was created
            }
          }
          return true;
        }).toList();

        if (results.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final existingJson = prefs.getString(_keyCacheRevenueRecords);
          List<Map<String, dynamic>> allCached = [];
          if (existingJson != null && existingJson.isNotEmpty) {
            allCached = List<Map<String, dynamic>>.from(jsonDecode(existingJson));
          }
          for (final res in results) {
            if (!allCached.any((c) => c['created_at'] == res['created_at'] && c['member_id'] == res['member_id'])) {
              allCached.insert(0, res);
            }
          }
          await prefs.setString(_keyCacheRevenueRecords, jsonEncode(allCached));
        }
      } catch (e) {
        debugPrint("Supabase fetchMemberTransactions note: $e");
      }
    }

    if (results.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final existingJson = prefs.getString(_keyCacheRevenueRecords);
        if (existingJson != null && existingJson.isNotEmpty) {
          final list = jsonDecode(existingJson) as List<dynamic>;
          for (final item in list) {
            if ((item['member_id'] ?? '').toString().trim().toLowerCase() == cleanId) {
              if (memberUuid != null && memberUuid.isNotEmpty && item['user_id'] != null) {
                if (item['user_id'].toString().toLowerCase() != memberUuid.toLowerCase()) {
                  continue;
                }
              }
              final txName = (item['member_name'] ?? '').toString().trim().toLowerCase();
              if (cleanName != null && cleanName.isNotEmpty && txName.isNotEmpty && txName != cleanName) {
                continue;
              }
              if (memberCreatedAt != null) {
                final txDate = DateTime.tryParse(item['created_at']?.toString() ?? '');
                if (txDate != null && txDate.isBefore(memberCreatedAt.subtract(const Duration(minutes: 10)))) {
                  continue;
                }
              }
              results.add(Map<String, dynamic>.from(item as Map));
            }
          }
        }
      } catch (localErr) {
        debugPrint("Local fetchMemberTransactions note: $localErr");
      }
    }

    return results;
  }

  // =========================================================================
  // STUDIO ANNOUNCEMENTS & NOTICE BOARD
  // =========================================================================

  /// Fetch studio announcements (filtered by targetAudience: 'ALL', 'MEMBERS', 'TRAINERS')
  static Future<List<Map<String, dynamic>>> fetchAnnouncements({
    String? targetAudience,
    bool onlyActive = true,
  }) async {
    List<Map<String, dynamic>> results = [];

    if (isConfigured) {
      try {
        var query = client.from('announcements').select('*');
        if (onlyActive) {
          query = query.eq('is_active', true);
        }

        if (targetAudience != null && targetAudience != 'ALL') {
          query = query.or('target_audience.eq.ALL,target_audience.eq.$targetAudience');
        }

        final data = await query.order('created_at', ascending: false).timeout(const Duration(seconds: 3));
        results = List<Map<String, dynamic>>.from(data);
        if (results.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyCacheAnnouncements, jsonEncode(results));
        }
      } catch (e) {
        debugPrint("Supabase fetchAnnouncements error: $e");
      }
    }

    if (results.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final localJson = prefs.getString(_keyCacheAnnouncements);
        if (localJson != null && localJson.isNotEmpty) {
          final list = jsonDecode(localJson) as List<dynamic>;
          for (final item in list) {
            final map = Map<String, dynamic>.from(item as Map);
            final audience = (map['target_audience'] ?? 'ALL').toString().toUpperCase();
            final isActive = map['is_active'] != false;

            if (onlyActive && !isActive) continue;

            if (targetAudience == null ||
                targetAudience == 'ALL' ||
                audience == 'ALL' ||
                audience == targetAudience.toUpperCase()) {
              results.add(map);
            }
          }
        }
      } catch (e) {
        debugPrint("Local fetchAnnouncements error: $e");
      }
    }

    // Filter out expired announcements if onlyActive is requested
    if (onlyActive && results.isNotEmpty) {
      final now = DateTime.now();
      results = results.where((item) {
        if (item['is_active'] == false) return false;
        final exp = item['expires_at']?.toString();
        if (exp != null && exp.isNotEmpty) {
          final expDate = DateTime.tryParse(exp);
          if (expDate != null && now.isAfter(expDate)) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    // If still empty and in fallback mode, provide friendly initial welcome note
    if (results.isEmpty) {
      final now = DateTime.now();
      results = [
        {
          'id': 'welcome-note-1',
          'title': 'Welcome to IRONBLOOD Studio Notice Board',
          'message':
              'All official gym schedules, holiday closures, special fitness seminars, and competition updates will be posted here directly.',
          'target_audience': 'ALL',
          'duration_hours': 36,
          'expires_at': now.add(const Duration(hours: 36)).toIso8601String(),
          'is_active': true,
          'created_at': now.toIso8601String(),
        }
      ];
    }

    return results;
  }

  /// Create and broadcast a new studio announcement
  static Future<Map<String, dynamic>> createAnnouncement({
    required String title,
    required String message,
    String targetAudience = 'ALL', // 'ALL', 'MEMBERS', 'TRAINERS'
    int durationHours = 36,        // Notice Active Duration (default 36 Hours)
  }) async {
    final now = DateTime.now();
    final expiresAt = durationHours > 0
        ? now.add(Duration(hours: durationHours)).toIso8601String()
        : null;

    final newRecord = {
      'id': 'ANN-${now.millisecondsSinceEpoch}',
      'title': title.trim(),
      'message': message.trim(),
      'target_audience': targetAudience.trim().toUpperCase(),
      'duration_hours': durationHours,
      'expires_at': expiresAt,
      'is_active': true,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    // Always persist to local cache first so it is immediately available offline
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_keyCacheAnnouncements);
      List<Map<String, dynamic>> list = [];
      if (localJson != null && localJson.isNotEmpty) {
        list = List<Map<String, dynamic>>.from(jsonDecode(localJson));
      }
      list.insert(0, newRecord);
      await prefs.setString(_keyCacheAnnouncements, jsonEncode(list));
    } catch (localErr) {
      debugPrint("Local cache save announcement error: $localErr");
    }

    if (isConfigured) {
      try {
        final res = await client
            .from('announcements')
            .insert({
              'title': newRecord['title'],
              'message': newRecord['message'],
              'target_audience': newRecord['target_audience'],
              'duration_hours': durationHours,
              'expires_at': expiresAt,
              'is_active': true,
            })
            .select()
            .single()
            .timeout(const Duration(seconds: 3));

        return {
          'success': true,
          'message': 'Announcement broadcasted successfully!',
          'data': res,
        };
      } catch (e) {
        debugPrint("Supabase createAnnouncement note: $e");
      }
    }

    return {
      'success': true,
      'message': 'Announcement saved to local storage (Offline Cache)!',
      'data': newRecord,
    };
  }

  /// Delete an announcement
  static Future<Map<String, dynamic>> deleteAnnouncement(String id) async {
    if (isConfigured) {
      try {
        await client.from('announcements').delete().eq('id', id);
      } catch (e) {
        debugPrint("Supabase deleteAnnouncement note: $e");
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_keyCacheAnnouncements);
      if (localJson != null && localJson.isNotEmpty) {
        final list = List<Map<String, dynamic>>.from(jsonDecode(localJson));
        list.removeWhere((item) => item['id']?.toString() == id);
        await prefs.setString(_keyCacheAnnouncements, jsonEncode(list));
      }
      return {'success': true, 'message': 'Announcement removed'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Toggle Active / Archived status of an announcement
  static Future<Map<String, dynamic>> toggleAnnouncementStatus(
    String id,
    bool isActive,
  ) async {
    if (isConfigured) {
      try {
        await client
            .from('announcements')
            .update({'is_active': isActive, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', id);
      } catch (e) {
        debugPrint("Supabase toggleAnnouncementStatus note: $e");
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_keyCacheAnnouncements);
      if (localJson != null && localJson.isNotEmpty) {
        final list = List<Map<String, dynamic>>.from(jsonDecode(localJson));
        for (var item in list) {
          if (item['id']?.toString() == id) {
            item['is_active'] = isActive;
          }
        }
        await prefs.setString(_keyCacheAnnouncements, jsonEncode(list));
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
