import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/supabase_service.dart';
import 'services/session_service.dart';
import 'services/invoice_service.dart';
import 'widgets/profile_avatar.dart';
import 'auth_screen.dart';

enum AdminSection { members, trainers, renewals, pt, plans, revenue, announcements }

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  // Brand Color Palette
  static const Color primaryGold = Color(0xFFC9A227);
  static const Color primaryGreen = Color(0xFF123222);
  static const Color darkBackground = Color(0xFF091911);
  static const Color cardSurface = Color(0xFF0F261B);
  static const Color lightGold = Color(0xFFFFE082);
  static const Color inputBorderColor = Color(0xFF1E4230);

  // Active Section
  AdminSection _currentSection = AdminSection.members;

  // Data States
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _trainers = [];
  List<Map<String, dynamic>> _membershipPlansList = [];
  List<Map<String, dynamic>> _ptPlansList = [];
  List<Map<String, dynamic>> _announcements = [];
  String _announcementFilter = 'ALL';
  bool _isLoading = true;
  String _searchQuery = "";
  Map<String, dynamic> _adminProfile = {};

  // ==========================================
  // REVENUE CALCULATION HELPERS
  // ==========================================
  double _getMembershipPlanPrice(String? planName) {
    if (planName == null || planName.trim().isEmpty) return 888.0;
    final cleanName = planName.trim().toLowerCase();
    final planObj = _membershipPlansList.firstWhere(
      (item) =>
          (item['plan_name'] ?? '').toString().trim().toLowerCase() ==
          cleanName,
      orElse: () => <String, dynamic>{},
    );
    if (planObj.isNotEmpty && planObj['price'] != null) {
      return (planObj['price'] as num).toDouble();
    }
    if (cleanName.contains('admission')) return 2000.0;
    if (cleanName.contains('3')) return 3888.0;
    if (cleanName.contains('6')) return 4888.0;
    if (cleanName.contains('year') ||
        cleanName.contains('12') ||
        cleanName.contains('annual')) {
      return 8888.0;
    }
    return 888.0;
  }

  double _getPtPlanPrice(String? ptPlanName) {
    if (ptPlanName == null || ptPlanName.trim().isEmpty) return 3000.0;
    final cleanName = ptPlanName.trim().toLowerCase();
    final planObj = _ptPlansList.firstWhere(
      (item) =>
          (item['plan_name'] ?? '').toString().trim().toLowerCase() ==
          cleanName,
      orElse: () => <String, dynamic>{},
    );
    if (planObj.isNotEmpty && planObj['price'] != null) {
      return (planObj['price'] as num).toDouble();
    }
    if (cleanName.contains('3')) return 8500.0;
    if (cleanName.contains('6')) return 16000.0;
    if (cleanName.contains('year') ||
        cleanName.contains('12') ||
        cleanName.contains('annual')) {
      return 30000.0;
    }
    return 3000.0;
  }

  double get _totalMembershipRevenue {
    double total = 0.0;
    for (final m in _members) {
      total += _getMembershipPlanPrice(m['plan']?.toString());
    }
    return total;
  }

  double get _totalPtRevenue {
    double total = 0.0;
    for (final m in _members) {
      final bool hasPt =
          m['has_pt'] == true ||
          (m['pt_status'] != null &&
              m['pt_status'].toString().trim().isNotEmpty &&
              m['pt_status'] != 'None');
      if (hasPt) {
        total += _getPtPlanPrice(m['pt_plan']?.toString());
      }
    }
    return total;
  }

  double get _grandTotalRevenue => _totalMembershipRevenue + _totalPtRevenue;

  String _formatIndianCurrency(double amount) {
    final int val = amount.round();
    final str = val.toString();
    if (str.length <= 3) return '₹$str';

    final last3 = str.substring(str.length - 3);
    final remaining = str.substring(0, str.length - 3);
    final formattedRemaining = remaining.replaceAllMapped(
      RegExp(r'(\d)(?=(\d\d)+$)'),
      (m) => '${m[1]},',
    );
    return '₹$formattedRemaining,$last3';
  }

  String _formatCompactRupee(double amount) {
    if (amount <= 0) return '₹0';
    if (amount >= 10000000) {
      final v = amount / 10000000;
      return '₹${v.toStringAsFixed(v >= 10 ? 0 : 1)}Cr';
    }
    if (amount >= 100000) {
      final v = amount / 100000;
      return '₹${v.toStringAsFixed(v >= 10 ? 0 : 1)}L';
    }
    if (amount >= 1000) {
      final v = amount / 1000;
      return '₹${v.toStringAsFixed(v >= 10 ? 0 : 1)}k';
    }
    return '₹${amount.toInt()}';
  }

  DateTime? _parseMemberDate(dynamic dateVal) {
    if (dateVal == null) return null;
    try {
      if (dateVal is DateTime) return dateVal;
      return DateTime.tryParse(dateVal.toString());
    } catch (_) {
      return null;
    }
  }

  // Controllers for Add/Edit Member
  final _memberFormKey = GlobalKey<FormState>();
  final _memberIdController = TextEditingController();
  final _memberNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();
  final _memberEmergencyPhoneController = TextEditingController();
  final _memberEmailController = TextEditingController();
  final _memberAadharController = TextEditingController();
  final _memberPasswordController = TextEditingController();
  // Member Structured Address Controllers (Flat Name, Flat No, Street/Area, Landmark, City, District, State, PINCODE)
  final _memberAddressFlatNameController = TextEditingController();
  final _memberAddressFlatNoController = TextEditingController();
  final _memberAddressStreetController = TextEditingController();
  final _memberAddressLandmarkController = TextEditingController();
  final _memberAddressCityController = TextEditingController();
  final _memberAddressDistrictController = TextEditingController();
  final _memberAddressStateController = TextEditingController();
  final _memberAddressPincodeController = TextEditingController();
  final _memberMedicalHistoryController = TextEditingController();
  String? _memberPhotoUrl;
  bool _isSavingMember = false;
  bool _isEditingMember = false;

  // Controllers for Add/Edit Trainer
  final _trainerFormKey = GlobalKey<FormState>();
  final _trainerIdController = TextEditingController();
  final _trainerNameController = TextEditingController();
  final _trainerPhoneController = TextEditingController();
  final _trainerEmailController = TextEditingController();
  final _trainerAadharController = TextEditingController();
  final _trainerExpController = TextEditingController();
  final _trainerPasswordController = TextEditingController();
  // Trainer Structured Address Controllers (Flat Name, Flat No, Street/Area, Landmark, City, District, State, PINCODE)
  final _trainerAddressFlatNameController = TextEditingController();
  final _trainerAddressFlatNoController = TextEditingController();
  final _trainerAddressStreetController = TextEditingController();
  final _trainerAddressLandmarkController = TextEditingController();
  final _trainerAddressCityController = TextEditingController();
  final _trainerAddressDistrictController = TextEditingController();
  final _trainerAddressStateController = TextEditingController();
  final _trainerAddressPincodeController = TextEditingController();
  String? _trainerPhotoUrl;
  bool _isSavingTrainer = false;
  bool _isEditingTrainer = false;

  /// Format structured address into standard readable format:
  /// Flat/House Number, Flat/House Name, Street/Area, Landmark, City/Town, District, State - PINCODE
  String _formatStructuredAddress({
    required String flatHouseName,
    required String flatHouseNumber,
    required String streetArea,
    required String landmark,
    required String cityTown,
    required String district,
    required String state,
    required String pincode,
  }) {
    final parts = <String>[];
    if (flatHouseNumber.trim().isNotEmpty) parts.add(flatHouseNumber.trim());
    if (flatHouseName.trim().isNotEmpty) parts.add(flatHouseName.trim());
    if (streetArea.trim().isNotEmpty) parts.add(streetArea.trim());
    if (landmark.trim().isNotEmpty) {
      final lm = landmark.trim();
      parts.add(
        lm.toLowerCase().startsWith('near') ||
                lm.toLowerCase().startsWith('opp') ||
                lm.toLowerCase().startsWith('landmark:')
            ? lm
            : 'Near $lm',
      );
    }
    if (cityTown.trim().isNotEmpty) parts.add(cityTown.trim());
    if (district.trim().isNotEmpty) {
      final dist = district.trim();
      parts.add(dist.toLowerCase().contains('dist') ? dist : '$dist Dist.');
    }
    if (state.trim().isNotEmpty) {
      if (pincode.trim().isNotEmpty) {
        parts.add('${state.trim()} - ${pincode.trim()}');
      } else {
        parts.add(state.trim());
      }
    } else if (pincode.trim().isNotEmpty) {
      parts.add(pincode.trim());
    }
    return parts.join(', ');
  }

  /// Parse stored address string into 8 structured parts
  Map<String, String> _parseStructuredAddress(String? fullAddress) {
    final empty = {
      'flatHouseName': '',
      'flatHouseNumber': '',
      'streetArea': '',
      'landmark': '',
      'cityTown': '',
      'district': '',
      'state': '',
      'pincode': '',
    };
    if (fullAddress == null || fullAddress.trim().isEmpty) {
      return empty;
    }
    final raw = fullAddress.trim();

    // Check if JSON encoded
    if (raw.startsWith('{') && raw.endsWith('}')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return {
            'flatHouseName': (decoded['flatHouseName'] ?? decoded['houseName'] ?? '').toString(),
            'flatHouseNumber': (decoded['flatHouseNumber'] ?? decoded['houseNo'] ?? '').toString(),
            'streetArea': (decoded['streetArea'] ?? decoded['street'] ?? '').toString(),
            'landmark': (decoded['landmark'] ?? '').toString(),
            'cityTown': (decoded['cityTown'] ?? decoded['city'] ?? '').toString(),
            'district': (decoded['district'] ?? '').toString(),
            'state': (decoded['state'] ?? '').toString(),
            'pincode': (decoded['pincode'] ?? decoded['pin'] ?? '').toString(),
          };
        }
      } catch (_) {}
    }

    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return empty;

    String pincode = '';
    String state = '';
    String district = '';
    String cityTown = '';
    String landmark = '';
    String streetArea = '';
    String flatHouseName = '';
    String flatHouseNumber = '';

    // Extract PIN & State from last part
    if (parts.isNotEmpty) {
      final last = parts.last;
      if (last.contains('-')) {
        final spl = last.split('-');
        state = spl.first.trim();
        pincode = spl.last.replaceAll(RegExp(r'\D'), '').trim();
        parts.removeLast();
      } else if (RegExp(r'^\d{6}$').hasMatch(last.replaceAll(RegExp(r'\D'), ''))) {
        pincode = last.replaceAll(RegExp(r'\D'), '').trim();
        parts.removeLast();
        if (parts.isNotEmpty) {
          state = parts.removeLast();
        }
      }
    }

    // Check for District in remaining parts
    for (int i = parts.length - 1; i >= 0; i--) {
      if (parts[i].toLowerCase().contains('dist')) {
        district = parts[i]
            .replaceAll(RegExp(r'dist\.?', caseSensitive: false), '')
            .trim();
        parts.removeAt(i);
        break;
      }
    }

    // Check for Landmark in remaining parts
    for (int i = parts.length - 1; i >= 0; i--) {
      if (parts[i].toLowerCase().startsWith('near ') ||
          parts[i].toLowerCase().startsWith('opp ') ||
          parts[i].toLowerCase().startsWith('landmark:')) {
        landmark = parts[i]
            .replaceAll(
              RegExp(r'^(near|opp|landmark:)\s*', caseSensitive: false),
              '',
            )
            .trim();
        parts.removeAt(i);
        break;
      }
    }

    // Remaining parts:
    if (parts.length >= 4) {
      flatHouseNumber = parts[0];
      flatHouseName = parts[1];
      streetArea = parts.sublist(2, parts.length - 1).join(', ');
      cityTown = parts.last;
    } else if (parts.length == 3) {
      flatHouseNumber = parts[0];
      streetArea = parts[1];
      cityTown = parts[2];
    } else if (parts.length == 2) {
      streetArea = parts[0];
      cityTown = parts[1];
    } else if (parts.length == 1) {
      streetArea = parts[0];
    }

    return {
      'flatHouseName': flatHouseName,
      'flatHouseNumber': flatHouseNumber,
      'streetArea': streetArea,
      'landmark': landmark,
      'cityTown': cityTown,
      'district': district,
      'state': state,
      'pincode': pincode,
    };
  }

  // Dynamic Plans fetched directly from Database
  List<String> get _membershipPlans {
    final plans = _membershipPlansList
        .where(
          (p) => p['is_active'] != false,
        )
        .map((p) => (p['plan_name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (plans.isEmpty) {
      return ["Admission Fee", "Monthly", "3 Months", "6 Months", "Yearly"];
    }
    return plans;
  }

  List<String> get _ptPlans {
    final plans = _ptPlansList
        .where((p) => p['is_active'] != false)
        .map((p) => (p['plan_name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (plans.isEmpty) {
      return ["Monthly PT", "3 Months PT", "6 Months PT", "Annual PT"];
    }
    return plans;
  }

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _memberIdController.dispose();
    _memberNameController.dispose();
    _memberPhoneController.dispose();
    _memberEmergencyPhoneController.dispose();
    _memberEmailController.dispose();
    _memberAadharController.dispose();
    _memberPasswordController.dispose();
    _memberAddressFlatNameController.dispose();
    _memberAddressFlatNoController.dispose();
    _memberAddressStreetController.dispose();
    _memberAddressLandmarkController.dispose();
    _memberAddressCityController.dispose();
    _memberAddressDistrictController.dispose();
    _memberAddressStateController.dispose();
    _memberAddressPincodeController.dispose();
    _memberMedicalHistoryController.dispose();

    _trainerIdController.dispose();
    _trainerNameController.dispose();
    _trainerPhoneController.dispose();
    _trainerEmailController.dispose();
    _trainerAadharController.dispose();
    _trainerExpController.dispose();
    _trainerPasswordController.dispose();
    _trainerAddressFlatNameController.dispose();
    _trainerAddressFlatNoController.dispose();
    _trainerAddressStreetController.dispose();
    _trainerAddressLandmarkController.dispose();
    _trainerAddressCityController.dispose();
    _trainerAddressDistrictController.dispose();
    _trainerAddressStateController.dispose();
    _trainerAddressPincodeController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    // 1. Instantly load from local offline cache (0ms) so admin sees cached dashboard immediately offline
    final cachedMembers = await SupabaseService.getCachedMembers();
    final cachedTrainers = await SupabaseService.getCachedTrainers();
    final cachedPlans = await SupabaseService.getCachedMembershipPlans();
    final cachedPt = await SupabaseService.getCachedPtPlans();
    final cachedAdmin = await SupabaseService.getCachedAdminProfile();
    final cachedAnnouncements =
        await SupabaseService.getCachedAnnouncements(onlyActive: false);

    if (mounted) {
      setState(() {
        _members = cachedMembers;
        _trainers = cachedTrainers;
        _membershipPlansList = cachedPlans;
        _ptPlansList = cachedPt;
        _adminProfile = cachedAdmin;
        _announcements = cachedAnnouncements;
        _isLoading = false;
      });
    }

    // 2. Refresh everything concurrently in the background if connected
    try {
      final results = await Future.wait([
        SupabaseService.fetchMembers(),
        SupabaseService.fetchTrainers(),
        SupabaseService.fetchMembershipPlans(),
        SupabaseService.fetchPtPlans(),
        SupabaseService.fetchAdminProfile(),
        SupabaseService.fetchAnnouncements(onlyActive: false),
      ]);

      if (mounted) {
        setState(() {
          _members = results[0] as List<Map<String, dynamic>>;
          _trainers = results[1] as List<Map<String, dynamic>>;
          _membershipPlansList = results[2] as List<Map<String, dynamic>>;
          _ptPlansList = results[3] as List<Map<String, dynamic>>;
          _adminProfile = results[4] as Map<String, dynamic>;
          _announcements = results[5] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Admin background fetch error: $e");
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ==========================================
  // LOGOUT WITH CONFIRMATION
  // ==========================================
  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: primaryGold, width: 1.2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.shade900.withValues(alpha: 0.5),
                border: Border.all(color: Colors.redAccent, width: 1),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              "CONFIRM LOGOUT",
              style: GoogleFonts.rajdhani(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: lightGold,
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to exit the Admin Command Center, ${_adminProfile['full_name'] ?? 'Admin'}?",
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: primaryGold.withValues(alpha: 0.4)),
              ),
            ),
            child: Text(
              "CANCEL",
              style: GoogleFonts.rajdhani(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await SessionService.clearSession();
              if (!context.mounted) return;
              Navigator.pop(context); // Close dialog
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 600),
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const AuthScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1E1E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.redAccent, width: 1),
              ),
            ),
            child: Text(
              "YES, LOG OUT",
              style: GoogleFonts.rajdhani(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _generateNextMemberId() {
    int maxId = 0;
    final regex = RegExp(r'(\d+)');

    for (final member in _members) {
      final rawId = (member['member_id'] ?? '').toString().trim();
      final match = regex.firstMatch(rawId);
      if (match != null) {
        final parsed = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (parsed > maxId) {
          maxId = parsed;
        }
      }
    }

    final nextNum = maxId + 1;
    return 'MB-${nextNum.toString().padLeft(3, '0')}';
  }

  // ==========================================
  // MEMBER MODAL (ADD & EDIT)
  // ==========================================
  void _showMemberModal({Map<String, dynamic>? memberToEdit}) {
    _isEditingMember = memberToEdit != null;

    if (memberToEdit != null) {
      _memberIdController.text = memberToEdit['member_id'] ?? '';
      _memberNameController.text = memberToEdit['full_name'] ?? '';
      _memberPhoneController.text = SupabaseService.extract10DigitPhone(
        memberToEdit['phone'],
      );
      _memberEmergencyPhoneController.text = SupabaseService.extract10DigitPhone(
        memberToEdit['emergency_phone'],
      );
      _memberEmailController.text = memberToEdit['email'] ?? '';
      _memberAadharController.text =
          memberToEdit['aadhar_number']?.toString() ??
          memberToEdit['aadhar']?.toString() ??
          '';
      final addrParsed = _parseStructuredAddress(
        memberToEdit['address']?.toString(),
      );
      _memberAddressFlatNameController.text =
          addrParsed['flatHouseName'] ?? '';
      _memberAddressFlatNoController.text =
          addrParsed['flatHouseNumber'] ?? '';
      _memberAddressStreetController.text = addrParsed['streetArea'] ?? '';
      _memberAddressLandmarkController.text = addrParsed['landmark'] ?? '';
      _memberAddressCityController.text = addrParsed['cityTown'] ?? '';
      _memberAddressDistrictController.text = addrParsed['district'] ?? '';
      _memberAddressStateController.text = addrParsed['state'] ?? '';
      _memberAddressPincodeController.text = addrParsed['pincode'] ?? '';
      _memberMedicalHistoryController.text =
          memberToEdit['medical_history']?.toString() ?? '';
      _memberPhotoUrl = memberToEdit['photo_url']?.toString();
    } else {
      _memberIdController.text = _generateNextMemberId();
      _memberNameController.clear();
      _memberPhoneController.clear();
      _memberEmergencyPhoneController.clear();
      _memberEmailController.clear();
      _memberAadharController.clear();
      _memberAddressFlatNameController.clear();
      _memberAddressFlatNoController.clear();
      _memberAddressStreetController.clear();
      _memberAddressLandmarkController.clear();
      _memberAddressCityController.clear();
      _memberAddressDistrictController.clear();
      _memberAddressStateController.clear();
      _memberAddressPincodeController.clear();
      _memberMedicalHistoryController.clear();
      _memberPasswordController.text = "ironblood123";
      _memberPhotoUrl = null;
    }

    // Default to Admission plan if available, otherwise first plan or Monthly
    String enrollPlan = 'Monthly';
    final admissionPlan = _membershipPlans.firstWhere(
      (p) => p.toLowerCase().contains('admission'),
      orElse: () => '',
    );
    if (admissionPlan.isNotEmpty) {
      enrollPlan = admissionPlan;
    } else if (_membershipPlans.isNotEmpty) {
      enrollPlan = _membershipPlans.first;
    }
    String enrollPtPlan = 'None';
    String enrollPtTrainer = 'Unassigned';

    final List<String> trainerOptions = ['Unassigned'];
    for (final tr in _trainers) {
      final tName = (tr['full_name'] ?? '').toString().trim();
      if (tName.isNotEmpty && !trainerOptions.contains(tName)) {
        trainerOptions.add(tName);
      }
    }

    final discountController = TextEditingController();
    double discountAmount = 0.0;
    String paymentMode = 'UPI';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) {
          final planObj = _membershipPlansList.firstWhere(
            (item) =>
                (item['plan_name'] ?? '').toString().trim().toLowerCase() ==
                enrollPlan.trim().toLowerCase(),
            orElse: () => <String, dynamic>{},
          );
          final double membershipBasePrice =
              (planObj['price'] as num?)?.toDouble() ??
              (enrollPlan.toLowerCase().contains('admission')
                  ? 2000.0
                  : enrollPlan.contains('3')
                  ? 3888.0
                  : enrollPlan.contains('6')
                  ? 4888.0
                  : enrollPlan.contains('Year')
                  ? 8888.0
                  : 888.0);
          final double ptBasePrice = (enrollPtPlan != 'None' && enrollPtPlan.isNotEmpty)
              ? _getPtPlanPrice(enrollPtPlan)
              : 0.0;
          final double basePrice = membershipBasePrice + ptBasePrice;
          final double finalTotal = (basePrice - discountAmount).clamp(
            0.0,
            double.infinity,
          );

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A1F15),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: primaryGold.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Form(
                  key: _memberFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: primaryGold.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            _isEditingMember
                                ? Icons.edit_note_rounded
                                : Icons.person_add_alt_1_rounded,
                            color: primaryGold,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isEditingMember
                                ? "MEMBER INFORMATION"
                                : "ENROLL NEW MEMBER",
                            style: GoogleFonts.rajdhani(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0,
                              color: lightGold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Profile Picture Selector & Preview
                      Center(
                        child: Column(
                          children: [
                            ProfileAvatar(
                              imageUrl: _memberPhotoUrl,
                              name: _memberNameController.text.isNotEmpty
                                  ? _memberNameController.text
                                  : "Member",
                              radius: 36,
                              showEditIcon: true,
                              onTap: () async {
                                final selected = await ProfileAvatar.pickImageSource(
                                  sheetCtx,
                                  currentImageUrl: _memberPhotoUrl,
                                );
                                if (selected != null) {
                                  setModalState(() {
                                    _memberPhotoUrl = selected.isEmpty ? null : selected;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: () async {
                                final selected = await ProfileAvatar.pickImageSource(
                                  sheetCtx,
                                  currentImageUrl: _memberPhotoUrl,
                                );
                                if (selected != null) {
                                  setModalState(() {
                                    _memberPhotoUrl = selected.isEmpty ? null : selected;
                                  });
                                }
                              },
                              icon: const Icon(
                                Icons.photo_camera_rounded,
                                color: primaryGold,
                                size: 15,
                              ),
                              label: Text(
                                _memberPhotoUrl != null && _memberPhotoUrl!.isNotEmpty
                                    ? "CHANGE PROFILE PHOTO"
                                    : "ADD PROFILE PHOTO",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: lightGold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Member ID (Auto-generated serially, read-only)
                      _buildInputField(
                        controller: _memberIdController,
                        label: "MEMBER ID",
                        hint: "MB-001",
                        icon: Icons.badge_outlined,
                        enabled: false,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? "Required" : null,
                      ),
                      const SizedBox(height: 12),

                      // Full Name
                      _buildInputField(
                        controller: _memberNameController,
                        label: "FULL NAME",
                        hint: "e.g. John Doe",
                        icon: Icons.person_outline_rounded,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? "Required" : null,
                      ),
                      const SizedBox(height: 12),

                      // Phone & Emergency Phone
                      _buildInputField(
                        controller: _memberPhoneController,
                        label: "PRIMARY MOBILE NUMBER (10 DIGITS)",
                        hint: "98765 43210",
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                        isPhone: true,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return "Required";
                          if (v.trim().length != 10) return "Enter 10-digit number";
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildInputField(
                        controller: _memberEmergencyPhoneController,
                        label: "EMERGENCY CONTACT NUMBER (10 DIGITS)",
                        hint: "98765 43210",
                        icon: Icons.contact_phone_rounded,
                        keyboardType: TextInputType.phone,
                        isPhone: true,
                      ),
                      const SizedBox(height: 12),
                      _buildInputField(
                        controller: _memberEmailController,
                        label: "EMAIL ADDRESS",
                        hint: "member@gym.com",
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildInputField(
                        controller: _memberAadharController,
                        label: "AADHAR CARD NUMBER (12 DIGITS)",
                        hint: "e.g. 1234 5678 9012",
                        icon: Icons.fingerprint_rounded,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 14),

                      // Structured Postal Address
                      _buildAddressSection(
                        flatNameController: _memberAddressFlatNameController,
                        flatNoController: _memberAddressFlatNoController,
                        streetController: _memberAddressStreetController,
                        landmarkController: _memberAddressLandmarkController,
                        cityController: _memberAddressCityController,
                        districtController: _memberAddressDistrictController,
                        stateController: _memberAddressStateController,
                        pincodeController: _memberAddressPincodeController,
                      ),
                      const SizedBox(height: 14),

                      // Medical History / Health Conditions
                      _buildInputField(
                        controller: _memberMedicalHistoryController,
                        label: "MEDICAL HISTORY / HEALTH CONDITIONS (OPTIONAL)",
                        hint: "e.g. Asthma, High BP, Back/Knee injury, Allergies, Surgeries, None",
                        icon: Icons.health_and_safety_outlined,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),

                      if (!_isEditingMember) ...[
                        _buildInputField(
                          controller: _memberPasswordController,
                          label: "INITIAL ACCESS PASSWORD",
                          hint: "ironblood123",
                          icon: Icons.lock_outline_rounded,
                          validator: (v) => (v == null || v.length < 6)
                              ? "Minimum 6 chars"
                              : null,
                        ),
                        const SizedBox(height: 14),

                        // MEMBERSHIP PLAN SELECTOR
                        Text(
                          "MEMBERSHIP PLAN",
                          style: GoogleFonts.rajdhani(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: primaryGold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF08180F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: inputBorderColor,
                              width: 1.2,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: enrollPlan,
                              isExpanded: true,
                              dropdownColor: cardSurface,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: primaryGold,
                              ),
                              items: _membershipPlans.map((p) {
                                final pObj = _membershipPlansList.firstWhere(
                                  (item) =>
                                      (item['plan_name'] ?? '')
                                          .toString()
                                          .trim()
                                          .toLowerCase() ==
                                      p.trim().toLowerCase(),
                                  orElse: () => <String, dynamic>{},
                                );
                                final num? price = pObj['price'] as num?;
                                final String priceText = price != null
                                    ? "₹${price.toInt()}"
                                    : "";

                                return DropdownMenuItem<String>(
                                  value: p,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p,
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (priceText.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: primaryGold.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: primaryGold.withValues(
                                                alpha: 0.6,
                                              ),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            priceText,
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: lightGold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() {
                                    enrollPlan = val;
                                    if (discountAmount > basePrice) {
                                      discountAmount = 0.0;
                                      discountController.clear();
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // OPTIONAL PERSONAL TRAINING (PT) PLAN SELECTOR
                        Text(
                          "PERSONAL TRAINING (PT) PLAN (OPTIONAL)",
                          style: GoogleFonts.rajdhani(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: primaryGold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF08180F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: inputBorderColor,
                              width: 1.2,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: enrollPtPlan,
                              isExpanded: true,
                              dropdownColor: cardSurface,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: primaryGold,
                              ),
                              items: ['None', ..._ptPlans].map((p) {
                                final isNone = p == 'None';
                                final pObj = _ptPlansList.firstWhere(
                                  (item) =>
                                      (item['plan_name'] ?? '')
                                          .toString()
                                          .trim()
                                          .toLowerCase() ==
                                      p.trim().toLowerCase(),
                                  orElse: () => <String, dynamic>{},
                                );
                                final num? price = pObj['price'] as num?;
                                final String priceText = (!isNone && price != null)
                                    ? "+ ₹${price.toInt()}"
                                    : (!isNone ? "+ ₹3000" : "NO PT");

                                return DropdownMenuItem<String>(
                                  value: p,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          isNone ? "None (No Personal Training)" : p,
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isNone ? Colors.white70 : Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isNone
                                              ? Colors.white.withValues(alpha: 0.05)
                                              : primaryGold.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isNone
                                                ? Colors.white24
                                                : primaryGold.withValues(alpha: 0.6),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          priceText,
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: isNone ? Colors.white60 : lightGold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() {
                                    enrollPtPlan = val;
                                    if (enrollPtPlan == 'None') {
                                      enrollPtTrainer = 'Unassigned';
                                    } else if (enrollPtTrainer == 'Unassigned' && trainerOptions.length > 1) {
                                      enrollPtTrainer = trainerOptions[1];
                                    }
                                    if (discountAmount > basePrice) {
                                      discountAmount = 0.0;
                                      discountController.clear();
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ASSIGN PERSONAL TRAINER (Shown only if PT is opted)
                        if (enrollPtPlan != 'None') ...[
                          Text(
                            "ASSIGN PERSONAL TRAINER (COACH)",
                            style: GoogleFonts.rajdhani(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: primaryGold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF08180F),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: inputBorderColor,
                                width: 1.2,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: trainerOptions.contains(enrollPtTrainer)
                                    ? enrollPtTrainer
                                    : 'Unassigned',
                                isExpanded: true,
                                dropdownColor: cardSurface,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: primaryGold,
                                ),
                                items: trainerOptions.map((trName) {
                                  final isUnassigned = trName == 'Unassigned';
                                  final trObj = _trainers.firstWhere(
                                    (t) =>
                                        (t['full_name'] ?? '')
                                            .toString()
                                            .trim()
                                            .toLowerCase() ==
                                        trName.trim().toLowerCase(),
                                    orElse: () => <String, dynamic>{},
                                  );
                                  final exp = trObj['experience']?.toString() ?? '';

                                  return DropdownMenuItem<String>(
                                    value: trName,
                                    child: Row(
                                      children: [
                                        Icon(
                                          isUnassigned
                                              ? Icons.person_off_rounded
                                              : Icons.sports_mma_rounded,
                                          size: 16,
                                          color: isUnassigned
                                              ? Colors.white38
                                              : primaryGold,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            isUnassigned
                                                ? "Unassigned (Assign Later)"
                                                : "Coach $trName",
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (exp.isNotEmpty)
                                          Text(
                                            exp,
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: lightGold.withValues(
                                                alpha: 0.8,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setModalState(() {
                                      enrollPtTrainer = val;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // ADMIN SPECIAL DISCOUNT
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_offer_rounded,
                                  color: primaryGold,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  "SPECIAL DISCOUNT (₹)",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                    color: primaryGold,
                                  ),
                                ),
                              ],
                            ),
                            if (discountAmount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF133E24),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: const Color(0xFF4CAF50),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  "SAVE ₹${discountAmount.toInt()}",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF81C784),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF08180F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: discountAmount > 0
                                  ? primaryGold
                                  : inputBorderColor,
                              width: 1.2,
                            ),
                          ),
                          child: TextField(
                            controller: discountController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.montserrat(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            onChanged: (val) {
                              final parsed = double.tryParse(val.trim()) ?? 0.0;
                              setModalState(() {
                                discountAmount = parsed.clamp(0.0, basePrice);
                              });
                            },
                            decoration: InputDecoration(
                              hintText:
                                  "Enter discount amount in ₹ (e.g. 200, 500)",
                              hintStyle: GoogleFonts.rajdhani(
                                color: Colors.white38,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              prefixIcon: const Icon(
                                Icons.currency_rupee_rounded,
                                color: primaryGold,
                                size: 18,
                              ),
                              suffixIcon: discountController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white60,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        setModalState(() {
                                          discountController.clear();
                                          discountAmount = 0.0;
                                        });
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // PAYMENT MODE SELECTOR
                        Text(
                          "PAYMENT MODE",
                          style: GoogleFonts.rajdhani(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: primaryGold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildPaymentModeSelector(
                          selectedMode: paymentMode,
                          onSelected: (mode) =>
                              setModalState(() => paymentMode = mode),
                        ),
                        const SizedBox(height: 16),

                        // FINAL TOTAL SUMMARY CARD
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06140D),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: primaryGold.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            children: [
                              if (enrollPtPlan != 'None') ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "1. $enrollPlan (Membership)",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      "₹${membershipBasePrice.toInt()}",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "2. $enrollPtPlan (PT${enrollPtTrainer != 'Unassigned' ? ' - $enrollPtTrainer' : ''})",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: lightGold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      "₹${ptBasePrice.toInt()}",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: lightGold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Combined Base Subtotal",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white54,
                                      ),
                                    ),
                                    Text(
                                      "₹${basePrice.toInt()}",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Base Plan Price ($enrollPlan)",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    Text(
                                      "₹${basePrice.toInt()}",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (discountAmount > 0) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Discount Applied",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF81C784),
                                      ),
                                    ),
                                    Text(
                                      "-₹${discountAmount.toInt()}",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF81C784),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(
                                  color: Color(0xFF1B4931),
                                  height: 1,
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "FINAL TOTAL ($paymentMode)",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                          color: lightGold,
                                        ),
                                      ),
                                      Text(
                                        "Net Payable Amount",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    "₹${finalTotal.toInt()}",
                                    style: GoogleFonts.montserrat(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: primaryGold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      const SizedBox(height: 8),

                      // Submit Action Button
                      Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF9E7B1A), primaryGold, lightGold],
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _isSavingMember
                                ? null
                                : () async {
                                    if (!(_memberFormKey.currentState
                                            ?.validate() ??
                                        false)) {
                                      return;
                                    }

                                    setModalState(() => _isSavingMember = true);

                                    final rawPhone = _memberPhoneController.text
                                        .trim();
                                    final formattedPhone = rawPhone.isNotEmpty
                                        ? SupabaseService.formatIndianPhone(
                                            rawPhone,
                                          )
                                        : '';

                                    final rawEmergency =
                                        _memberEmergencyPhoneController.text
                                            .trim();
                                    final formattedEmergency =
                                        rawEmergency.isNotEmpty
                                            ? SupabaseService.formatIndianPhone(
                                                rawEmergency,
                                              )
                                            : null;

                                    final Map<String, dynamic> res;
                                    final aadharNum = _memberAadharController
                                        .text
                                        .trim();
                                    final formattedAddress =
                                        _formatStructuredAddress(
                                          flatHouseName:
                                              _memberAddressFlatNameController
                                                  .text,
                                          flatHouseNumber:
                                              _memberAddressFlatNoController
                                                  .text,
                                          streetArea:
                                              _memberAddressStreetController
                                                  .text,
                                          landmark:
                                              _memberAddressLandmarkController
                                                  .text,
                                          cityTown:
                                              _memberAddressCityController.text,
                                          district:
                                              _memberAddressDistrictController
                                                  .text,
                                          state:
                                              _memberAddressStateController
                                                  .text,
                                          pincode:
                                              _memberAddressPincodeController
                                                  .text,
                                        );
                                    final cleanAddress =
                                        formattedAddress.isNotEmpty
                                            ? formattedAddress
                                            : null;
                                    if (_isEditingMember) {
                                      res =
                                          await SupabaseService.adminUpdateMember(
                                            memberId: _memberIdController.text,
                                            fullName:
                                                _memberNameController.text,
                                            phone: formattedPhone,
                                            emergencyPhone: formattedEmergency,
                                            photoUrl: _memberPhotoUrl,
                                            email: _memberEmailController.text,
                                            aadharNumber: aadharNum.isNotEmpty
                                                ? aadharNum
                                                : null,
                                            address: cleanAddress,
                                            medicalHistory: _memberMedicalHistoryController.text.trim().isNotEmpty ? _memberMedicalHistoryController.text.trim() : null,
                                          );
                                    } else {
                                      res =
                                          await SupabaseService.adminCreateMember(
                                            memberId: _memberIdController.text,
                                            fullName:
                                                _memberNameController.text,
                                            initialPassword:
                                                _memberPasswordController.text,
                                            phone: formattedPhone,
                                            emergencyPhone: formattedEmergency,
                                            photoUrl: _memberPhotoUrl,
                                            email: _memberEmailController.text,
                                            plan: enrollPlan,
                                            aadharNumber: aadharNum.isNotEmpty
                                                ? aadharNum
                                                : null,
                                            address: cleanAddress,
                                            medicalHistory: _memberMedicalHistoryController.text.trim().isNotEmpty ? _memberMedicalHistoryController.text.trim() : null,
                                            hasPt: enrollPtPlan != 'None' && enrollPtPlan.isNotEmpty,
                                            ptPlan: enrollPtPlan != 'None' && enrollPtPlan.isNotEmpty ? enrollPtPlan : 'None',
                                            ptTrainer: enrollPtPlan != 'None' && enrollPtPlan.isNotEmpty ? enrollPtTrainer : 'Unassigned',
                                            ptStartDate: enrollPtPlan != 'None' && enrollPtPlan.isNotEmpty ? DateTime.now() : null,
                                            ptExpiryDate: enrollPtPlan != 'None' && enrollPtPlan.isNotEmpty ? SupabaseService.calculateExpiryDate(DateTime.now(), enrollPtPlan) : null,
                                          );
                                    }

                                    if (!_isEditingMember &&
                                        res['success'] == true) {
                                      final hasPtSelected = enrollPtPlan != 'None' && enrollPtPlan.isNotEmpty;
                                      final revenuePlanName = hasPtSelected
                                          ? '$enrollPlan + $enrollPtPlan${enrollPtTrainer != 'Unassigned' ? ' ($enrollPtTrainer)' : ''}'
                                          : enrollPlan;
                                      final revenueType = hasPtSelected ? 'Membership + PT' : 'Membership';

                                      await SupabaseService.recordRevenueTransaction(
                                        memberId: _memberIdController.text
                                            .trim(),
                                        memberName: _memberNameController.text
                                            .trim(),
                                        type: revenueType,
                                        planName: revenuePlanName,
                                        amount: finalTotal,
                                        baseAmount: basePrice,
                                        discountAmount: discountAmount,
                                        paymentMode: paymentMode,
                                        notes: hasPtSelected
                                            ? 'New Member Enrollment (Membership + PT: $enrollPtPlan, Coach: $enrollPtTrainer)'
                                            : 'New Member Enrollment',
                                      );
                                    }

                                    setModalState(
                                      () => _isSavingMember = false,
                                    );

                                    if (res['success'] == true) {
                                      final memberId = _memberIdController.text
                                          .trim();
                                      final memberName = _memberNameController
                                          .text
                                          .trim();
                                      final memberPhone =
                                          _memberPhoneController.text
                                              .trim()
                                              .isNotEmpty
                                          ? SupabaseService.formatIndianPhone(
                                              _memberPhoneController.text
                                                  .trim(),
                                            )
                                          : '';
                                      final memberEmail = _memberEmailController
                                          .text
                                          .trim();

                                      if (!sheetCtx.mounted) return;
                                      Navigator.of(sheetCtx).pop();
                                      await _loadAllData();
                                      if (!mounted) return;

                                      if (!_isEditingMember) {
                                        final hasPtSelected = enrollPtPlan != 'None' && enrollPtPlan.isNotEmpty;
                                        final invoicePlanName = hasPtSelected
                                            ? '$enrollPlan + $enrollPtPlan${enrollPtTrainer != 'Unassigned' ? ' ($enrollPtTrainer)' : ''}'
                                            : enrollPlan;
                                        final now = DateTime.now();
                                        final memExpiry = SupabaseService.calculateExpiryDate(now, enrollPlan);

                                        final List<InvoiceLineItem> lineItems = [];
                                        if (hasPtSelected) {
                                          final ptExpiry = SupabaseService.calculateExpiryDate(now, enrollPtPlan);
                                          lineItems.add(
                                            InvoiceLineItem(
                                              description: '$enrollPlan Membership Plan',
                                              category: 'Gym Floor Access',
                                              coachOrDetails: 'General Floor Access',
                                              startDate: now,
                                              expiryDate: memExpiry,
                                              amount: membershipBasePrice,
                                            ),
                                          );
                                          lineItems.add(
                                            InvoiceLineItem(
                                              description: '$enrollPtPlan Personal Training',
                                              category: 'Personal Training (PT)',
                                              coachOrDetails: enrollPtTrainer != 'Unassigned'
                                                  ? 'Dedicated Coach: $enrollPtTrainer'
                                                  : 'Coach Unassigned',
                                              startDate: now,
                                              expiryDate: ptExpiry,
                                              amount: ptBasePrice,
                                            ),
                                          );
                                        } else {
                                          lineItems.add(
                                            InvoiceLineItem(
                                              description: '$enrollPlan Membership',
                                              category: 'Gym Floor Access',
                                              startDate: now,
                                              expiryDate: memExpiry,
                                              amount: basePrice,
                                            ),
                                          );
                                        }

                                        final invoice = InvoiceModel(
                                          invoiceNo:
                                              InvoiceModel.generateInvoiceNo(
                                                prefix: 'ENR',
                                              ),
                                          invoiceDate: now,
                                          memberId: memberId,
                                          memberName: memberName,
                                          memberPhone: memberPhone.isNotEmpty
                                              ? memberPhone
                                              : null,
                                          memberEmail: memberEmail.isNotEmpty
                                              ? memberEmail
                                              : null,
                                          category: hasPtSelected ? 'Membership + PT Enrollment' : 'Membership Enrollment',
                                          planName: invoicePlanName,
                                          trainerName: hasPtSelected && enrollPtTrainer != 'Unassigned' ? enrollPtTrainer : null,
                                          startDate: now,
                                          expiryDate: memExpiry,
                                          paymentMode: paymentMode,
                                          baseAmount: basePrice,
                                          discountAmount: discountAmount,
                                          finalAmount: finalTotal,
                                          items: lineItems,
                                          notes: hasPtSelected
                                              ? 'Welcome to IRONBLOOD! Full gym access & Personal Training ($enrollPtPlan) activated.'
                                              : 'Welcome to IRONBLOOD! Full gym access activated.',
                                        );
                                        InvoiceService.showReceiptDialog(
                                          context: context,
                                          invoice: invoice,
                                        );
                                      } else {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            backgroundColor: primaryGreen,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              side: const BorderSide(
                                                color: primaryGold,
                                                width: 1.2,
                                              ),
                                            ),
                                            content: Text(
                                              "Member profile updated successfully!",
                                              style: GoogleFonts.rajdhani(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    } else {
                                      if (!sheetCtx.mounted) return;
                                      ScaffoldMessenger.of(
                                        sheetCtx,
                                      ).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(
                                            0xFF8B1E1E,
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            side: const BorderSide(
                                              color: Colors.redAccent,
                                              width: 1.2,
                                            ),
                                          ),
                                          content: Text(
                                            res['message']?.toString() ??
                                                "Failed to save member.",
                                            style: GoogleFonts.rajdhani(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            child: Center(
                              child: _isSavingMember
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF091911),
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      _isEditingMember
                                          ? "SAVE CHANGES"
                                          : "CONFIRM & ENROLL • ₹${finalTotal.toInt()}",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.0,
                                        color: const Color(0xFF091911),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // QUICK MEMBERSHIP RENEWAL MODAL (WITH ADMIN DISCOUNT & FINAL TOTAL)
  // ==========================================
  void _showRenewModal(Map<String, dynamic> member) {
    final availablePlans = _membershipPlans;
    final isRequested =
        member['renewal_status'] == 'Pending Approval' ||
        member['renewal_status'] == 'Pending Renewal' ||
        member['renewal_status'] == 'Requested';
    final requestedPlan = member['requested_renewal_plan']?.toString();

    String renewPlan =
        (requestedPlan != null && availablePlans.contains(requestedPlan))
        ? requestedPlan
        : (member['plan']?.toString() ??
              (availablePlans.isNotEmpty ? availablePlans.first : 'Monthly'));
    if (!availablePlans.contains(renewPlan)) {
      renewPlan = availablePlans.isNotEmpty ? availablePlans.first : 'Monthly';
    }
    final discountController = TextEditingController();
    double discountAmount = 0.0;
    String paymentMode = 'UPI';
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) {
          // Look up plan base price
          final planObj = _membershipPlansList.firstWhere(
            (item) =>
                (item['plan_name'] ?? '').toString().trim().toLowerCase() ==
                renewPlan.trim().toLowerCase(),
            orElse: () => <String, dynamic>{},
          );
          final double basePrice =
              (planObj['price'] as num?)?.toDouble() ??
              (renewPlan.contains('3')
                  ? 3888.0
                  : renewPlan.contains('6')
                  ? 4888.0
                  : renewPlan.contains('Year')
                  ? 8888.0
                  : 888.0);

          final double finalTotal = (basePrice - discountAmount).clamp(
            0.0,
            double.infinity,
          );

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1F15),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: isRequested
                      ? Colors.amberAccent
                      : primaryGold.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: primaryGold.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.autorenew_rounded,
                          color: isRequested ? Colors.amberAccent : primaryGold,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isRequested
                              ? "REVIEW RENEWAL REQUEST"
                              : "RENEW MEMBERSHIP PLAN",
                          style: GoogleFonts.rajdhani(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: isRequested ? Colors.amberAccent : lightGold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Member: ${member['full_name']} (${member['member_id']}) • ${member['phone'] ?? 'No phone'}",
                      style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (isRequested)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade900.withValues(
                              alpha: 0.35,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.amberAccent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.pending_actions_rounded,
                                color: Colors.amberAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Member requested: ${requestedPlan ?? renewPlan}. Review & apply admin discount below.",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    Text(
                      "SELECT / CONFIRM DURATION PLAN",
                      style: GoogleFonts.rajdhani(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF08180F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: inputBorderColor, width: 1.2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: renewPlan,
                          isExpanded: true,
                          dropdownColor: cardSurface,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: primaryGold,
                          ),
                          items: _membershipPlans.map((p) {
                            final pObj = _membershipPlansList.firstWhere(
                              (item) =>
                                  (item['plan_name'] ?? '')
                                      .toString()
                                      .trim()
                                      .toLowerCase() ==
                                  p.trim().toLowerCase(),
                              orElse: () => <String, dynamic>{},
                            );
                            final num? price = pObj['price'] as num?;
                            final String priceText = price != null
                                ? "₹${price.toInt()}"
                                : "";

                            return DropdownMenuItem<String>(
                              value: p,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      p,
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (priceText.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryGold.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: primaryGold.withValues(
                                            alpha: 0.6,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        priceText,
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: lightGold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                renewPlan = val;
                                // Re-validate discount against new base price
                                if (discountAmount > basePrice) {
                                  discountAmount = 0.0;
                                  discountController.clear();
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ADMIN DISCOUNT SECTION
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.local_offer_rounded,
                              color: primaryGold,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "ADMIN SPECIAL DISCOUNT (₹)",
                              style: GoogleFonts.rajdhani(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                                color: primaryGold,
                              ),
                            ),
                          ],
                        ),
                        if (discountAmount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF133E24),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFF4CAF50),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              "SAVE ₹${discountAmount.toInt()}",
                              style: GoogleFonts.rajdhani(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF81C784),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF08180F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: discountAmount > 0
                              ? primaryGold
                              : inputBorderColor,
                          width: 1.2,
                        ),
                      ),
                      child: TextField(
                        controller: discountController,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val.trim()) ?? 0.0;
                          setModalState(() {
                            discountAmount = parsed.clamp(0.0, basePrice);
                          });
                        },
                        decoration: InputDecoration(
                          hintText:
                              "Enter discount amount in ₹ (e.g. 200, 500)",
                          hintStyle: GoogleFonts.rajdhani(
                            color: Colors.white38,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          prefixIcon: const Icon(
                            Icons.currency_rupee_rounded,
                            color: primaryGold,
                            size: 18,
                          ),
                          suffixIcon: discountController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white60,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      discountController.clear();
                                      discountAmount = 0.0;
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // PAYMENT MODE SELECTOR
                    Text(
                      "PAYMENT MODE",
                      style: GoogleFonts.rajdhani(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildPaymentModeSelector(
                      selectedMode: paymentMode,
                      onSelected: (mode) =>
                          setModalState(() => paymentMode = mode),
                    ),
                    const SizedBox(height: 16),

                    // FINAL TOTAL SUMMARY CARD
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06140D),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primaryGold.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Base Plan Price ($renewPlan)",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                "₹${basePrice.toInt()}",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (discountAmount > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Admin Discount Applied",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF81C784),
                                  ),
                                ),
                                Text(
                                  "-₹${discountAmount.toInt()}",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF81C784),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(color: Color(0xFF1B4931), height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "FINAL TOTAL ($paymentMode)",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      color: lightGold,
                                    ),
                                  ),
                                  Text(
                                    "Net Payable Amount",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                "₹${finalTotal.toInt()}",
                                style: GoogleFonts.montserrat(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: primaryGold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // CONFIRM / RENEW BUTTON
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9E7B1A), primaryGold, lightGold],
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: isProcessing
                              ? null
                              : () async {
                                  setModalState(() => isProcessing = true);
                                  final res =
                                      await SupabaseService.adminRenewMembership(
                                        memberId: member['member_id'],
                                        plan: renewPlan,
                                      );

                                  if (res['success'] == true) {
                                    await SupabaseService.recordRevenueTransaction(
                                      memberId:
                                          member['member_id']?.toString() ?? '',
                                      memberName:
                                          member['full_name']?.toString() ?? '',
                                      type: 'Membership',
                                      planName: renewPlan,
                                      amount: finalTotal,
                                      baseAmount: basePrice,
                                      discountAmount: discountAmount,
                                      paymentMode: paymentMode,
                                      notes: 'Membership Renewal',
                                    );
                                  }

                                  setModalState(() => isProcessing = false);

                                  if (res['success'] == true) {
                                    if (!sheetCtx.mounted) return;
                                    Navigator.of(sheetCtx).pop();
                                    await _loadAllData();
                                    if (!mounted) return;

                                    final invoice = InvoiceModel(
                                      invoiceNo: InvoiceModel.generateInvoiceNo(
                                        prefix: 'RNW',
                                      ),
                                      invoiceDate: DateTime.now(),
                                      memberId:
                                          member['member_id']?.toString() ?? '',
                                      memberName:
                                          member['full_name']?.toString() ?? '',
                                      memberPhone: member['phone']?.toString(),
                                      memberEmail: member['email']?.toString(),
                                      category: 'Membership Renewal',
                                      planName: renewPlan,
                                      paymentMode: paymentMode,
                                      baseAmount: basePrice,
                                      discountAmount: discountAmount,
                                      finalAmount: finalTotal,
                                      notes:
                                          'Membership renewed successfully. Keep crushing goals!',
                                    );
                                    InvoiceService.showReceiptDialog(
                                      context: context,
                                      invoice: invoice,
                                    );
                                  } else {
                                    if (!sheetCtx.mounted) return;
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(
                                          0xFF8B1E1E,
                                        ),
                                        content: Text(
                                          res['message'] ??
                                              'Failed to renew membership.',
                                          style: GoogleFonts.rajdhani(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: Center(
                            child: isProcessing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF091911),
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    isRequested
                                        ? "ACCEPT & RENEW • ₹${finalTotal.toInt()}"
                                        : "CONFIRM RENEWAL • ₹${finalTotal.toInt()}",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      color: const Color(0xFF091911),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (isRequested)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Colors.redAccent,
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                            label: Text(
                              "DECLINE REQUEST",
                              style: GoogleFonts.rajdhani(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                                color: Colors.redAccent,
                              ),
                            ),
                            onPressed: isProcessing
                                ? null
                                : () async {
                                    setModalState(() => isProcessing = true);
                                    await SupabaseService.adminDeclineRenewal(
                                      memberId: member['member_id'],
                                    );
                                    setModalState(() => isProcessing = false);
                                    if (!sheetCtx.mounted) return;
                                    Navigator.of(sheetCtx).pop();
                                    _loadAllData();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(
                                          0xFF3B1010,
                                        ),
                                        content: Text(
                                          "Renewal request declined for ${member['full_name']}.",
                                          style: GoogleFonts.rajdhani(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // QUICK PT ASSIGNMENT / RENEWAL MODAL (WITH ADMIN DISCOUNT & FINAL TOTAL)
  // ==========================================
  void _showAssignPtModal(Map<String, dynamic> member) {
    final availablePtPlans = _ptPlans;
    final isPtRequested =
        member['pt_status'] == 'Requested' ||
        member['pt_status'] == 'PT Requested' ||
        member['pt_status'] == 'Pending Approval';
    final reqPlan =
        member['requested_pt_plan']?.toString() ??
        member['pt_plan']?.toString();
    final reqTrainer =
        member['requested_pt_trainer']?.toString() ??
        member['pt_trainer']?.toString();

    String ptPlan = (reqPlan != null && availablePtPlans.contains(reqPlan))
        ? reqPlan
        : (availablePtPlans.isNotEmpty ? availablePtPlans.first : 'Monthly PT');
    if (!availablePtPlans.contains(ptPlan)) {
      ptPlan = availablePtPlans.isNotEmpty
          ? availablePtPlans.first
          : 'Monthly PT';
    }

    String ptTrainer =
        reqTrainer ??
        (_trainers.isNotEmpty
            ? (_trainers.first['full_name'] ?? 'Unassigned')
            : 'Unassigned');
    final discountController = TextEditingController();
    double discountAmount = 0.0;
    String paymentMode = 'UPI';
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) {
          // Look up PT base price
          final planObj = _ptPlansList.firstWhere(
            (item) =>
                (item['plan_name'] ?? '').toString().trim().toLowerCase() ==
                ptPlan.trim().toLowerCase(),
            orElse: () => <String, dynamic>{},
          );
          final double basePrice =
              (planObj['price'] as num?)?.toDouble() ?? 3000.0;

          final double finalTotal = (basePrice - discountAmount).clamp(
            0.0,
            double.infinity,
          );

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1F15),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: isPtRequested
                      ? Colors.amberAccent
                      : primaryGold.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: primaryGold.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.sports_gymnastics_rounded,
                          color: isPtRequested
                              ? Colors.amberAccent
                              : primaryGold,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isPtRequested
                              ? "REVIEW PT REQUEST"
                              : "ASSIGN / EXTEND PERSONAL TRAINING",
                          style: GoogleFonts.rajdhani(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: isPtRequested
                                ? Colors.amberAccent
                                : lightGold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Athlete: ${member['full_name']} (${member['member_id']}) • ${member['phone'] ?? 'No phone'}",
                      style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (isPtRequested)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade900.withValues(
                              alpha: 0.35,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.amberAccent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.contact_support_rounded,
                                color: Colors.amberAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Athlete requested: $ptPlan with Coach $ptTrainer. Review & apply admin discount below.",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    Text(
                      "SELECT / CONFIRM PT PLAN",
                      style: GoogleFonts.rajdhani(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF08180F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: inputBorderColor, width: 1.2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ptPlan,
                          isExpanded: true,
                          dropdownColor: cardSurface,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: primaryGold,
                          ),
                          items: _ptPlans.map((p) {
                            final pObj = _ptPlansList.firstWhere(
                              (item) =>
                                  (item['plan_name'] ?? '')
                                      .toString()
                                      .trim()
                                      .toLowerCase() ==
                                  p.trim().toLowerCase(),
                              orElse: () => <String, dynamic>{},
                            );
                            final num? price = pObj['price'] as num?;
                            final String priceText = price != null
                                ? "₹${price.toInt()}"
                                : "";

                            return DropdownMenuItem<String>(
                              value: p,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      p,
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (priceText.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryGold.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: primaryGold.withValues(
                                            alpha: 0.6,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        priceText,
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: lightGold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                ptPlan = val;
                                if (discountAmount > basePrice) {
                                  discountAmount = 0.0;
                                  discountController.clear();
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text(
                      "ASSIGNED PT COACH",
                      style: GoogleFonts.rajdhani(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF08180F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: inputBorderColor, width: 1.2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value:
                              (_trainers.any(
                                (t) => t['full_name'] == ptTrainer,
                              ))
                              ? ptTrainer
                              : (_trainers.isNotEmpty
                                    ? _trainers.first['full_name']
                                    : "Unassigned"),
                          isExpanded: true,
                          dropdownColor: cardSurface,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: primaryGold,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: "Unassigned",
                              child: Text(
                                "Unassigned Coach",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            ..._trainers.map((t) {
                              return DropdownMenuItem<String>(
                                value: t['full_name'] as String,
                                child: Text(
                                  "${t['full_name']} (${t['experience'] ?? 'Trainer'})",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => ptTrainer = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ADMIN DISCOUNT SECTION
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.local_offer_rounded,
                              color: primaryGold,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "ADMIN SPECIAL DISCOUNT (₹)",
                              style: GoogleFonts.rajdhani(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                                color: primaryGold,
                              ),
                            ),
                          ],
                        ),
                        if (discountAmount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF133E24),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFF4CAF50),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              "SAVE ₹${discountAmount.toInt()}",
                              style: GoogleFonts.rajdhani(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF81C784),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF08180F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: discountAmount > 0
                              ? primaryGold
                              : inputBorderColor,
                          width: 1.2,
                        ),
                      ),
                      child: TextField(
                        controller: discountController,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val.trim()) ?? 0.0;
                          setModalState(() {
                            discountAmount = parsed.clamp(0.0, basePrice);
                          });
                        },
                        decoration: InputDecoration(
                          hintText:
                              "Enter discount amount in ₹ (e.g. 300, 500)",
                          hintStyle: GoogleFonts.rajdhani(
                            color: Colors.white38,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          prefixIcon: const Icon(
                            Icons.currency_rupee_rounded,
                            color: primaryGold,
                            size: 18,
                          ),
                          suffixIcon: discountController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white60,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      discountController.clear();
                                      discountAmount = 0.0;
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // PAYMENT MODE SELECTOR
                    Text(
                      "PAYMENT MODE",
                      style: GoogleFonts.rajdhani(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildPaymentModeSelector(
                      selectedMode: paymentMode,
                      onSelected: (mode) =>
                          setModalState(() => paymentMode = mode),
                    ),
                    const SizedBox(height: 16),

                    // FINAL TOTAL SUMMARY CARD
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06140D),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primaryGold.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Base PT Rate ($ptPlan)",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                "₹${basePrice.toInt()}",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (discountAmount > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Admin Discount Applied",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF81C784),
                                  ),
                                ),
                                Text(
                                  "-₹${discountAmount.toInt()}",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF81C784),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(color: Color(0xFF1B4931), height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "FINAL TOTAL ($paymentMode)",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      color: lightGold,
                                    ),
                                  ),
                                  Text(
                                    "Net Payable Amount",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                "₹${finalTotal.toInt()}",
                                style: GoogleFonts.montserrat(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: primaryGold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // CONFIRM / ASSIGN BUTTON
                    Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9E7B1A), primaryGold, lightGold],
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: isProcessing
                              ? null
                              : () async {
                                  setModalState(() => isProcessing = true);
                                  final res =
                                      await SupabaseService.adminAssignPt(
                                        memberId: member['member_id'],
                                        ptPlan: ptPlan,
                                        trainerName: ptTrainer,
                                      );

                                  if (res['success'] == true) {
                                    await SupabaseService.recordRevenueTransaction(
                                      memberId:
                                          member['member_id']?.toString() ?? '',
                                      memberName:
                                          member['full_name']?.toString() ?? '',
                                      type: 'Personal Training',
                                      planName: ptPlan,
                                      amount: finalTotal,
                                      baseAmount: basePrice,
                                      discountAmount: discountAmount,
                                      paymentMode: paymentMode,
                                      notes: 'PT Coach: $ptTrainer',
                                    );
                                  }

                                  setModalState(() => isProcessing = false);

                                  if (res['success'] == true) {
                                    if (!sheetCtx.mounted) return;
                                    Navigator.of(sheetCtx).pop();
                                    await _loadAllData();
                                    if (!mounted) return;

                                    final invoice = InvoiceModel(
                                      invoiceNo: InvoiceModel.generateInvoiceNo(
                                        prefix: 'PT',
                                      ),
                                      invoiceDate: DateTime.now(),
                                      memberId:
                                          member['member_id']?.toString() ?? '',
                                      memberName:
                                          member['full_name']?.toString() ?? '',
                                      memberPhone: member['phone']?.toString(),
                                      memberEmail: member['email']?.toString(),
                                      category: 'Personal Training',
                                      planName: '$ptPlan (Coach $ptTrainer)',
                                      paymentMode: paymentMode,
                                      baseAmount: basePrice,
                                      discountAmount: discountAmount,
                                      finalAmount: finalTotal,
                                      notes:
                                          'Personal Training assigned with Coach $ptTrainer.',
                                    );
                                    InvoiceService.showReceiptDialog(
                                      context: context,
                                      invoice: invoice,
                                    );
                                  } else {
                                    if (!sheetCtx.mounted) return;
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(
                                          0xFF8B1E1E,
                                        ),
                                        content: Text(
                                          res['message'] ??
                                              'Failed to assign personal training.',
                                          style: GoogleFonts.rajdhani(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: Center(
                            child: isProcessing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF091911),
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    isPtRequested
                                        ? "ACCEPT & ACTIVATE PT • ₹${finalTotal.toInt()}"
                                        : "CONFIRM PT ACTIVATION • ₹${finalTotal.toInt()}",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      color: const Color(0xFF091911),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (isPtRequested)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Colors.redAccent,
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                            label: Text(
                              "DECLINE REQUEST",
                              style: GoogleFonts.rajdhani(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                                color: Colors.redAccent,
                              ),
                            ),
                            onPressed: isProcessing
                                ? null
                                : () async {
                                    setModalState(() => isProcessing = true);
                                    await SupabaseService.adminDeclinePt(
                                      memberId: member['member_id'],
                                    );
                                    setModalState(() => isProcessing = false);
                                    if (!sheetCtx.mounted) return;
                                    Navigator.of(sheetCtx).pop();
                                    _loadAllData();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(
                                          0xFF3B1010,
                                        ),
                                        content: Text(
                                          "Personal Training request declined for ${member['full_name']}.",
                                          style: GoogleFonts.rajdhani(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteMember(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Text(
          "REMOVE MEMBER?",
          style: GoogleFonts.rajdhani(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.redAccent,
          ),
        ),
        content: Text(
          "Are you sure you want to remove ${member['full_name']} (ID: ${member['member_id']}) from IronBlood Gym?",
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CANCEL",
              style: GoogleFonts.rajdhani(
                color: Colors.white60,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await SupabaseService.adminDeleteMember(member['member_id']);
              _loadAllData();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF3B1010),
                  content: Text(
                    "Member ${member['full_name']} deleted.",
                    style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(
              "DELETE",
              style: GoogleFonts.rajdhani(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _generateNextTrainerId() {
    int maxId = 0;
    final regex = RegExp(r'(\d+)');

    for (final trainer in _trainers) {
      final rawId = (trainer['trainer_id'] ?? '').toString().trim();
      final match = regex.firstMatch(rawId);
      if (match != null) {
        final parsed = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (parsed > maxId) {
          maxId = parsed;
        }
      }
    }

    final nextNum = maxId + 1;
    return 'TR-${nextNum.toString().padLeft(2, '0')}';
  }

  // ==========================================
  // TRAINER MODAL (ADD & EDIT)
  // ==========================================
  void _showTrainerModal({Map<String, dynamic>? trainerToEdit}) {
    _isEditingTrainer = trainerToEdit != null;

    if (trainerToEdit != null) {
      _trainerIdController.text = trainerToEdit['trainer_id'] ?? '';
      _trainerNameController.text = trainerToEdit['full_name'] ?? '';
      _trainerPhoneController.text = SupabaseService.extract10DigitPhone(
        trainerToEdit['phone'],
      );
      _trainerEmailController.text = trainerToEdit['email'] ?? '';
      _trainerAadharController.text =
          trainerToEdit['aadhar_number']?.toString() ??
          trainerToEdit['aadhar']?.toString() ??
          '';
      final addrParsed = _parseStructuredAddress(
        trainerToEdit['address']?.toString(),
      );
      _trainerAddressFlatNameController.text =
          addrParsed['flatHouseName'] ?? '';
      _trainerAddressFlatNoController.text =
          addrParsed['flatHouseNumber'] ?? '';
      _trainerAddressStreetController.text = addrParsed['streetArea'] ?? '';
      _trainerAddressLandmarkController.text = addrParsed['landmark'] ?? '';
      _trainerAddressCityController.text = addrParsed['cityTown'] ?? '';
      _trainerAddressDistrictController.text = addrParsed['district'] ?? '';
      _trainerAddressStateController.text = addrParsed['state'] ?? '';
      _trainerAddressPincodeController.text = addrParsed['pincode'] ?? '';
      _trainerExpController.text = trainerToEdit['experience'] ?? '3+ Years';
      _trainerPhotoUrl = trainerToEdit['photo_url']?.toString();
    } else {
      _trainerIdController.text = _generateNextTrainerId();
      _trainerNameController.clear();
      _trainerPhoneController.clear();
      _trainerEmailController.clear();
      _trainerAadharController.clear();
      _trainerAddressFlatNameController.clear();
      _trainerAddressFlatNoController.clear();
      _trainerAddressStreetController.clear();
      _trainerAddressLandmarkController.clear();
      _trainerAddressCityController.clear();
      _trainerAddressDistrictController.clear();
      _trainerAddressStateController.clear();
      _trainerAddressPincodeController.clear();
      _trainerExpController.text = "4+ Years";
      _trainerPasswordController.text = "ironblood123";
      _trainerPhotoUrl = null;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: primaryGold.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Form(
                key: _trainerFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: primaryGold.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          _isEditingTrainer
                              ? Icons.sports_mma_rounded
                              : Icons.person_add_alt_rounded,
                          color: primaryGold,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isEditingTrainer
                              ? "MODIFY TRAINER DETAILS"
                              : "ENROLL NEW TRAINER",
                          style: GoogleFonts.rajdhani(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: lightGold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Profile Picture Selector & Preview
                    Center(
                      child: Column(
                        children: [
                          ProfileAvatar(
                            imageUrl: _trainerPhotoUrl,
                            name: _trainerNameController.text.isNotEmpty
                                ? _trainerNameController.text
                                : "Trainer",
                            radius: 36,
                            showEditIcon: true,
                            onTap: () async {
                              final selected =
                                  await ProfileAvatar.pickImageSource(
                                    sheetCtx,
                                    currentImageUrl: _trainerPhotoUrl,
                                  );
                              if (selected != null) {
                                setModalState(() {
                                  _trainerPhotoUrl =
                                      selected.isEmpty ? null : selected;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () async {
                              final selected =
                                  await ProfileAvatar.pickImageSource(
                                    sheetCtx,
                                    currentImageUrl: _trainerPhotoUrl,
                                  );
                              if (selected != null) {
                                setModalState(() {
                                  _trainerPhotoUrl =
                                      selected.isEmpty ? null : selected;
                                });
                              }
                            },
                            icon: const Icon(
                              Icons.photo_camera_rounded,
                              color: primaryGold,
                              size: 15,
                            ),
                            label: Text(
                              _trainerPhotoUrl != null &&
                                      _trainerPhotoUrl!.isNotEmpty
                                  ? "CHANGE PROFILE PHOTO"
                                  : "ADD PROFILE PHOTO",
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: lightGold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Trainer ID
                    _buildInputField(
                      controller: _trainerIdController,
                      label: _isEditingTrainer
                          ? "TRAINER ID"
                          : "TRAINER ID (AUTO / CUSTOM)",
                      hint: "e.g. TR-01",
                      icon: Icons.badge_outlined,
                      enabled: !_isEditingTrainer,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? "Required" : null,
                    ),
                    const SizedBox(height: 12),

                    // Trainer Name
                    _buildInputField(
                      controller: _trainerNameController,
                      label: "FULL NAME",
                      hint: "e.g. Marcus Stone",
                      icon: Icons.person_outline_rounded,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? "Required" : null,
                    ),
                    const SizedBox(height: 12),

                    // Phone & Email
                    _buildInputField(
                      controller: _trainerPhoneController,
                      label: "CONTACT NUMBER (10 DIGITS)",
                      hint: "98765 43210",
                      icon: Icons.phone_android_rounded,
                      keyboardType: TextInputType.phone,
                      isPhone: true,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return "Required";
                        if (v.trim().length != 10) {
                          return "Enter valid 10-digit mobile number";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      controller: _trainerEmailController,
                      label: "EMAIL ADDRESS",
                      hint: "trainer@ironblood.com",
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      controller: _trainerAadharController,
                      label: "AADHAR CARD NUMBER (12 DIGITS)",
                      hint: "e.g. 1234 5678 9012",
                      icon: Icons.fingerprint_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),

                    // Experience
                    _buildInputField(
                      controller: _trainerExpController,
                      label: "EXPERIENCE",
                      hint: "e.g. 5+ Years",
                      icon: Icons.workspace_premium_rounded,
                    ),
                    const SizedBox(height: 14),

                    // Structured Postal Address
                    _buildAddressSection(
                      flatNameController: _trainerAddressFlatNameController,
                      flatNoController: _trainerAddressFlatNoController,
                      streetController: _trainerAddressStreetController,
                      landmarkController: _trainerAddressLandmarkController,
                      cityController: _trainerAddressCityController,
                      districtController: _trainerAddressDistrictController,
                      stateController: _trainerAddressStateController,
                      pincodeController: _trainerAddressPincodeController,
                    ),
                    const SizedBox(height: 14),

                    if (!_isEditingTrainer) ...[
                      _buildInputField(
                        controller: _trainerPasswordController,
                        label: "INITIAL ACCESS PASSWORD",
                        hint: "ironblood123",
                        icon: Icons.lock_outline_rounded,
                        validator: (v) => (v == null || v.length < 6)
                            ? "Minimum 6 chars"
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 10),

                    // Submit Action Button
                    Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9E7B1A), primaryGold, lightGold],
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _isSavingTrainer
                              ? null
                              : () async {
                                  if (!(_trainerFormKey.currentState
                                          ?.validate() ??
                                      false)) {
                                    return;
                                  }

                                  setModalState(() => _isSavingTrainer = true);

                                  final rawTrainerPhone =
                                      _trainerPhoneController.text.trim();
                                  final formattedTrainerPhone =
                                      SupabaseService.formatIndianPhone(
                                        rawTrainerPhone,
                                      );

                                  final Map<String, dynamic> res;
                                  final trAadhar = _trainerAadharController.text
                                      .trim();
                                  final formattedTrainerAddress =
                                      _formatStructuredAddress(
                                        flatHouseName:
                                            _trainerAddressFlatNameController
                                                .text,
                                        flatHouseNumber:
                                            _trainerAddressFlatNoController
                                                .text,
                                        streetArea:
                                            _trainerAddressStreetController
                                                .text,
                                        landmark:
                                            _trainerAddressLandmarkController
                                                .text,
                                        cityTown:
                                            _trainerAddressCityController.text,
                                        district:
                                            _trainerAddressDistrictController
                                                .text,
                                        state:
                                            _trainerAddressStateController
                                                .text,
                                        pincode:
                                            _trainerAddressPincodeController
                                                .text,
                                      );
                                  final cleanTrainerAddress =
                                      formattedTrainerAddress.isNotEmpty
                                          ? formattedTrainerAddress
                                          : null;

                                  if (_isEditingTrainer) {
                                    res =
                                        await SupabaseService.adminUpdateTrainer(
                                          trainerId: _trainerIdController.text,
                                          fullName: _trainerNameController.text,
                                          phone: formattedTrainerPhone,
                                          photoUrl: _trainerPhotoUrl,
                                          email: _trainerEmailController.text,
                                          experience:
                                              _trainerExpController.text,
                                          aadharNumber: trAadhar.isNotEmpty
                                              ? trAadhar
                                              : null,
                                          address: cleanTrainerAddress,
                                        );
                                  } else {
                                    res =
                                        await SupabaseService.adminCreateTrainer(
                                          trainerId: _trainerIdController.text,
                                          fullName: _trainerNameController.text,
                                          initialPassword:
                                              _trainerPasswordController.text,
                                          phone: formattedTrainerPhone,
                                          photoUrl: _trainerPhotoUrl,
                                          email: _trainerEmailController.text,
                                          experience:
                                              _trainerExpController.text,
                                          aadharNumber: trAadhar.isNotEmpty
                                              ? trAadhar
                                              : null,
                                          address: cleanTrainerAddress,
                                        );
                                  }

                                  setModalState(() => _isSavingTrainer = false);
                                  if (!sheetCtx.mounted) return;

                                  if (res['success'] == true) {
                                    Navigator.pop(sheetCtx);
                                    await _loadAllData();
                                    if (!mounted) return;

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: primaryGreen,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: const BorderSide(
                                            color: primaryGold,
                                            width: 1.2,
                                          ),
                                        ),
                                        content: Text(
                                          _isEditingTrainer
                                              ? "Trainer profile updated!"
                                              : "New trainer registered into roster!",
                                          style: GoogleFonts.rajdhani(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(
                                          0xFF8B1E1E,
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: const BorderSide(
                                            color: Colors.redAccent,
                                            width: 1.2,
                                          ),
                                        ),
                                        content: Text(
                                          res['message']?.toString() ??
                                              "Failed to save trainer.",
                                          style: GoogleFonts.rajdhani(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: Center(
                            child: _isSavingTrainer
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF091911),
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    _isEditingTrainer
                                        ? "SAVE TRAINER PROFILE"
                                        : "REGISTER TRAINER",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2.0,
                                      color: const Color(0xFF091911),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteTrainer(Map<String, dynamic> trainer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A1F15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Text(
          "REMOVE TRAINER?",
          style: GoogleFonts.rajdhani(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.redAccent,
          ),
        ),
        content: Text(
          "Are you sure you want to remove ${trainer['full_name']} (ID: ${trainer['trainer_id']}) from IronBlood Gym roster?",
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CANCEL",
              style: GoogleFonts.rajdhani(
                color: Colors.white60,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await SupabaseService.adminDeleteTrainer(trainer['trainer_id']);
              _loadAllData();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF3B1010),
                  content: Text(
                    "Trainer ${trainer['full_name']} removed.",
                    style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(
              "DELETE",
              style: GoogleFonts.rajdhani(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SIDE PANEL (NAVIGATION DRAWER)
  // ==========================================
  Widget _buildSideDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0A1F15),
      child: Column(
        children: [
          // Drawer Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF143B29), Color(0xFF091911)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border(
                bottom: BorderSide(
                  color: primaryGold.withValues(alpha: 0.3),
                  width: 1.2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryGreen,
                        border: Border.all(color: primaryGold, width: 1.5),
                      ),
                      child: Image.asset(
                        'lib/logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.fitness_center_rounded,
                              color: primaryGold,
                            ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              (_adminProfile['full_name'] ?? "BAPI DAS")
                                  .toString()
                                  .toUpperCase(),
                              style: GoogleFonts.montserrat(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                                color: lightGold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified_rounded,
                              color: primaryGold,
                              size: 16,
                            ),
                          ],
                        ),
                        Text(
                          (_adminProfile['role'] ?? "GYM OWNER & FOUNDER")
                              .toString()
                              .toUpperCase(),
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: const Color(0xFFE8D7A3),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryGreen,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: primaryGold.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    "IRONBLOOD COMMAND CENTER",
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                      color: primaryGold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Drawer Navigation Items
          _buildDrawerItem(
            title: "MEMBERS MANAGEMENT",
            icon: Icons.groups_rounded,
            count: "${_members.length}",
            isSelected: _currentSection == AdminSection.members,
            onTap: () {
              setState(() {
                _currentSection = AdminSection.members;
                _searchQuery = "";
              });
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 8),
          _buildDrawerItem(
            title: "TRAINERS MANAGEMENT",
            icon: Icons.sports_mma_rounded,
            count: "${_trainers.length}",
            isSelected: _currentSection == AdminSection.trainers,
            onTap: () {
              setState(() {
                _currentSection = AdminSection.trainers;
                _searchQuery = "";
              });
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 8),
          _buildDrawerItem(
            title: "MEMBERSHIP RENEW",
            icon: Icons.autorenew_rounded,
            count:
                _members
                    .where(
                      (m) =>
                          m['renewal_status'] == 'Pending Approval' ||
                          m['renewal_status'] == 'Pending Renewal' ||
                          m['renewal_status'] == 'Requested',
                    )
                    .isNotEmpty
                ? "${_members.where((m) => m['renewal_status'] == 'Pending Approval' || m['renewal_status'] == 'Pending Renewal' || m['renewal_status'] == 'Requested').length} REQ"
                : "${_members.where((m) => m['is_active'] == true).length}",
            isSelected: _currentSection == AdminSection.renewals,
            onTap: () {
              setState(() {
                _currentSection = AdminSection.renewals;
                _searchQuery = "";
              });
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 8),
          _buildDrawerItem(
            title: "PERSONAL TRAINING",
            icon: Icons.sports_gymnastics_rounded,
            count:
                _members
                    .where(
                      (m) =>
                          m['pt_status'] == 'Requested' ||
                          m['pt_status'] == 'PT Requested' ||
                          m['pt_status'] == 'Pending Approval',
                    )
                    .isNotEmpty
                ? "${_members.where((m) => m['pt_status'] == 'Requested' || m['pt_status'] == 'PT Requested' || m['pt_status'] == 'Pending Approval').length} REQ"
                : "${_members.where((m) => m['has_pt'] == true).length}",
            isSelected: _currentSection == AdminSection.pt,
            onTap: () {
              setState(() {
                _currentSection = AdminSection.pt;
                _searchQuery = "";
              });
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 8),
          _buildDrawerItem(
            title: "MEMBERSHIP & PT PLANS",
            icon: Icons.price_change_rounded,
            count: "${_membershipPlansList.length + _ptPlansList.length}",
            isSelected: _currentSection == AdminSection.plans,
            onTap: () {
              setState(() {
                _currentSection = AdminSection.plans;
                _searchQuery = "";
              });
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 8),
          _buildDrawerItem(
            title: "TOTAL REVENUE",
            icon: Icons.account_balance_wallet_rounded,
            count: _formatIndianCurrency(_grandTotalRevenue),
            isSelected: _currentSection == AdminSection.revenue,
            onTap: () {
              setState(() {
                _currentSection = AdminSection.revenue;
                _searchQuery = "";
              });
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 8),
          _buildDrawerItem(
            title: "ANNOUNCEMENTS",
            icon: Icons.campaign_rounded,
            count:
                "${_announcements.where((a) => a['is_active'] != false).length}",
            isSelected: _currentSection == AdminSection.announcements,
            onTap: () {
              setState(() {
                _currentSection = AdminSection.announcements;
                _searchQuery = "";
              });
              Navigator.pop(context);
            },
          ),

          const Spacer(),

          // Studio Info Tile
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF08180F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: inputBorderColor),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: primaryGold,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "IRONBLOOD MUSCLE & FITNESS STUDIO",
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Logout Item
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                ),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  "LOG OUT",
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: Colors.redAccent,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleLogout();
                },
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required String title,
    required IconData icon,
    required String count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF143B29), Color(0xFF0F261B)],
                )
              : null,
          border: Border.all(
            color: isSelected
                ? primaryGold
                : primaryGold.withValues(alpha: 0.15),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: isSelected ? primaryGold : Colors.white70),
          title: Text(
            title,
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: isSelected ? lightGold : Colors.white,
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? primaryGold : const Color(0xFF08180F),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count,
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isSelected ? const Color(0xFF091911) : primaryGold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // MAIN BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBackground,
      drawer: _buildSideDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1F15),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: primaryGold, size: 28),
            tooltip: "Open Menu",
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) {
                    return const LinearGradient(
                      colors: [lightGold, primaryGold, lightGold],
                    ).createShader(bounds);
                  },
                  child: Text(
                    (_adminProfile['full_name'] ?? "BAPI DAS")
                        .toString()
                        .toUpperCase(),
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: primaryGold,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "OWNER",
                    style: GoogleFonts.rajdhani(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: const Color(0xFF091911),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              "IRONBLOOD MUSCLE AND FITNESS STUDIO",
              style: GoogleFonts.rajdhani(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: const Color(0xFFE8D7A3),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: primaryGold),
            tooltip: "Refresh Data",
            onPressed: _loadAllData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: "Log Out",
            onPressed: _handleLogout,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: primaryGold.withValues(alpha: 0.3),
            height: 1,
          ),
        ),
      ),
      floatingActionButton: _currentSection == AdminSection.revenue
          ? null
          : FloatingActionButton.extended(
              backgroundColor: primaryGold,
              foregroundColor: const Color(0xFF091911),
              icon: Icon(
                _currentSection == AdminSection.members
                    ? Icons.person_add_alt_1_rounded
                    : (_currentSection == AdminSection.trainers
                          ? Icons.sports_mma_rounded
                          : (_currentSection == AdminSection.renewals
                                ? Icons.autorenew_rounded
                                : (_currentSection == AdminSection.pt
                                      ? Icons.sports_gymnastics_rounded
                                      : (_currentSection == AdminSection.plans
                                            ? Icons.add_card_rounded
                                            : Icons.campaign_rounded)))),
              ),
              label: Text(
                _currentSection == AdminSection.members
                    ? "ENROLL MEMBER"
                    : (_currentSection == AdminSection.trainers
                          ? "ADD TRAINER"
                          : (_currentSection == AdminSection.renewals
                                ? "RENEW MEMBER"
                                : (_currentSection == AdminSection.pt
                                      ? "ASSIGN PT"
                                      : (_currentSection == AdminSection.plans
                                            ? "CREATE PLAN"
                                            : "NEW NOTICE")))),
                style: GoogleFonts.rajdhani(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              onPressed: () {
                if (_currentSection == AdminSection.members) {
                  _showMemberModal();
                } else if (_currentSection == AdminSection.trainers) {
                  _showTrainerModal();
                } else if (_currentSection == AdminSection.renewals) {
                  _showSelectMemberForRenewal();
                } else if (_currentSection == AdminSection.pt) {
                  _showSelectMemberForPt();
                } else if (_currentSection == AdminSection.plans) {
                  _showAddPlanModal();
                } else if (_currentSection == AdminSection.announcements) {
                  _showCreateAnnouncementModal();
                }
              },
            ),
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.6),
                  radius: 1.2,
                  colors: [primaryGreen, Color(0xFF0B1F15), darkBackground],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              physics: const BouncingScrollPhysics(),
              child: _currentSection == AdminSection.members
                  ? _buildMembersSection()
                  : (_currentSection == AdminSection.trainers
                        ? _buildTrainersSection()
                        : (_currentSection == AdminSection.renewals
                              ? _buildRenewalsSection()
                              : (_currentSection == AdminSection.pt
                                    ? _buildPersonalTrainingSection()
                                    : (_currentSection == AdminSection.plans
                                          ? _buildPlansManagementSection()
                                          : (_currentSection ==
                                                  AdminSection.announcements
                                              ? _buildAnnouncementsSection()
                                              : _buildRevenueSection()))))),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SECTION: MEMBERS VIEW
  // ==========================================
  Widget _buildMembersSection() {
    final filteredMembers = _members.where((m) {
      final name = (m['full_name'] ?? '').toString().toLowerCase();
      final id = (m['member_id'] ?? '').toString().toLowerCase();
      final phone = (m['phone'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || id.contains(q) || phone.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick Stats Overview Cards
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: "TOTAL MEMBERS",
                value: "${_members.length}",
                icon: Icons.groups_rounded,
                color: primaryGold,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: "ACTIVE PASSES",
                value:
                    "${_members.where((m) => m['is_active'] == true).length}",
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF4CAF50),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Section Title & Search
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "MEMBERS ROSTER",
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: lightGold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: primaryGold.withValues(alpha: 0.4)),
              ),
              child: Text(
                "${filteredMembers.length} MEMBERS",
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: primaryGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search Field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF08180F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inputBorderColor, width: 1),
          ),
          child: TextField(
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: "Search by Member ID, Name, Phone...",
              hintStyle: GoogleFonts.rajdhani(
                color: Colors.white.withValues(alpha: 0.3),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: primaryGold,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: primaryGold),
                ),
              )
            : filteredMembers.isEmpty
            ? _buildEmptyPlaceholder("No members found.")
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredMembers.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final member = filteredMembers[index];
                  final isActive = member['is_active'] == true;
                  final expiryDateStr = member['membership_expiry_date']
                      ?.toString();
                  final daysLeft = SupabaseService.daysRemaining(expiryDateStr);
                  final hasPt = member['has_pt'] == true;
                  final ptExpiryStr = member['pt_expiry_date']?.toString();
                  final ptDaysLeft = SupabaseService.daysRemaining(ptExpiryStr);
                  final isRenewalPending =
                      member['renewal_status'] == 'Pending Approval';
                  final isPtRequested = member['pt_status'] == 'Requested';

                  return Container(
                    decoration: BoxDecoration(
                      color: cardSurface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isRenewalPending || isPtRequested
                            ? Colors.amberAccent
                            : hasPt
                            ? primaryGold.withValues(alpha: 0.6)
                            : primaryGold.withValues(alpha: 0.3),
                        width: (isRenewalPending || isPtRequested || hasPt)
                            ? 1.4
                            : 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showMemberModal(memberToEdit: member),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header Row: Avatar + Name + Status Badges
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ProfileAvatar(
                                    imageUrl: member['photo_url']?.toString(),
                                    name: member['full_name'] ?? 'Member',
                                    radius: 24,
                                    borderWidth: 1.4,
                                    borderColor:
                                        hasPt ? lightGold : primaryGold,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      member['full_name'] ??
                                                          'Unknown Member',
                                                      style:
                                                          GoogleFonts.rajdhani(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Colors.white,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (hasPt) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: primaryGold,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        "PT VIP",
                                                        style:
                                                            GoogleFonts.rajdhani(
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              color:
                                                                  const Color(
                                                                    0xFF091911,
                                                                  ),
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isActive
                                                    ? Colors.green.shade900
                                                          .withValues(
                                                            alpha: 0.6,
                                                          )
                                                    : Colors.red.shade900
                                                          .withValues(
                                                            alpha: 0.6,
                                                          ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isActive
                                                      ? Colors.greenAccent
                                                      : Colors.redAccent,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                isActive
                                                    ? "ACTIVE"
                                                    : "INACTIVE",
                                                style: GoogleFonts.rajdhani(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: isActive
                                                      ? Colors.greenAccent
                                                      : Colors.redAccent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 2,
                                          children: [
                                            Text(
                                              "ID: ${member['member_id']} • ${member['phone'] ?? 'No phone'}",
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: primaryGold.withValues(
                                                  alpha: 0.9,
                                                ),
                                              ),
                                            ),
                                            if (member['emergency_phone'] !=
                                                    null &&
                                                member['emergency_phone']
                                                    .toString()
                                                    .trim()
                                                    .isNotEmpty)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.emergency_outlined,
                                                    size: 12,
                                                    color: Colors.redAccent,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    "Emg: ${member['emergency_phone']}",
                                                    style: GoogleFonts.rajdhani(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors
                                                          .redAccent
                                                          .shade100,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                        if (member['aadhar_number'] != null &&
                                            member['aadhar_number']
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              "Aadhar: ${SupabaseService.formatAadharNumber(member['aadhar_number'].toString())}",
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Membership Plan & Expiry Info Box
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF08180F),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: inputBorderColor),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.card_membership_rounded,
                                              size: 15,
                                              color: primaryGold,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              "Plan: ${member['plan'] ?? 'Monthly'}",
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: lightGold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: daysLeft <= 5
                                                ? Colors.red.shade900
                                                      .withValues(alpha: 0.5)
                                                : primaryGreen,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: daysLeft <= 5
                                                  ? Colors.redAccent
                                                  : primaryGold,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            expiryDateStr != null
                                                ? (daysLeft > 0
                                                      ? "$daysLeft Days Left"
                                                      : "Expired")
                                                : "Active",
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: daysLeft <= 5
                                                  ? Colors.redAccent
                                                  : lightGold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (expiryDateStr != null) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "Start: ${member['membership_start_date'] ?? 'N/A'}",
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white60,
                                            ),
                                          ),
                                          Text(
                                            "Expires: $expiryDateStr",
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Personal Training (PT) Details Box (if enrolled or requested)
                              if (hasPt || isPtRequested) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF191F0E),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isPtRequested
                                          ? Colors.amberAccent
                                          : primaryGold,
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.sports_gymnastics_rounded,
                                                size: 16,
                                                color: primaryGold,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                "PT: ${member['pt_plan'] ?? 'Personal Training'}",
                                                style: GoogleFonts.rajdhani(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: lightGold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: primaryGold,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isPtRequested
                                                  ? "REQUESTED"
                                                  : (ptExpiryStr != null
                                                        ? (ptDaysLeft > 0
                                                              ? "$ptDaysLeft D Left"
                                                              : "PT Expired")
                                                        : "PT ACTIVE"),
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w900,
                                                color: const Color(0xFF091911),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "Dedicated PT Coach: ${member['pt_trainer'] ?? 'Unassigned'}",
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (ptExpiryStr != null)
                                            Text(
                                              "PT Expiry: $ptExpiryStr",
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white70,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Alerts: Pending Renewal or PT Request
                              if (isRenewalPending || isPtRequested) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade900.withValues(
                                      alpha: 0.35,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.amberAccent,
                                      width: 0.9,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.info_outline_rounded,
                                        size: 16,
                                        color: Colors.amberAccent,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          isRenewalPending
                                              ? "Member requested membership renewal."
                                              : "Member requested Personal Training enrollment.",
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 10),
                              Divider(
                                color: primaryGold.withValues(alpha: 0.15),
                                height: 1,
                              ),
                              const SizedBox(height: 4),

                              // Footer: Tap hint & Delete action
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.touch_app_outlined,
                                        size: 14,
                                        color: primaryGold.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "Tap card to edit & renew",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: primaryGold.withValues(
                                            alpha: 0.8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.redAccent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 14,
                                      color: Colors.redAccent,
                                    ),
                                    label: Text(
                                      "DELETE",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                    onPressed: () =>
                                        _confirmDeleteMember(member),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

        const SizedBox(height: 80),
      ],
    );
  }

  // ==========================================
  // SECTION: TRAINERS VIEW
  // ==========================================
  Widget _buildTrainersSection() {
    final filteredTrainers = _trainers.where((t) {
      final name = (t['full_name'] ?? t['name'] ?? t['trainer_name'] ?? '')
          .toString()
          .toLowerCase();
      final id = (t['trainer_id'] ?? t['id'] ?? '').toString().toLowerCase();
      final phone = (t['phone'] ?? t['contact'] ?? t['phone_number'] ?? '')
          .toString()
          .toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || id.contains(q) || phone.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick Stats Overview Cards
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: "TOTAL TRAINERS",
                value: "${_trainers.length}",
                icon: Icons.sports_mma_rounded,
                color: primaryGold,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: "ACTIVE PT CLIENTS",
                value:
                    "${_members.where((m) => m['has_pt'] == true && m['is_active'] == true).length}",
                icon: Icons.sports_gymnastics_rounded,
                color: const Color(0xFF29B6F6),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Section Title & Search
        Text(
          "TRAINERS & COACHES ROSTER",
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
            color: lightGold,
          ),
        ),
        const SizedBox(height: 12),

        // Search Field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF08180F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inputBorderColor, width: 1),
          ),
          child: TextField(
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: "Search by Trainer Name, Phone, ID...",
              hintStyle: GoogleFonts.rajdhani(
                color: Colors.white.withValues(alpha: 0.3),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: primaryGold,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: primaryGold),
                ),
              )
            : filteredTrainers.isEmpty
            ? _buildEmptyPlaceholder("No trainers found.")
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredTrainers.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final trainer = filteredTrainers[index];

                  return Container(
                    decoration: BoxDecoration(
                      color: cardSurface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: primaryGold.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _showTrainerModal(trainerToEdit: trainer),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ProfileAvatar(
                                imageUrl: trainer['photo_url']?.toString(),
                                name: trainer['full_name'] ??
                                    trainer['name'] ??
                                    trainer['trainer_name'] ??
                                    'Trainer',
                                radius: 21,
                                borderWidth: 1.4,
                                borderColor: primaryGold,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            trainer['full_name'] ??
                                                trainer['name'] ??
                                                trainer['trainer_name'] ??
                                                'Unknown Coach',
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              height: 1.0,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Trainer ID badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF08180F),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: primaryGold,
                                              width: 0.9,
                                            ),
                                          ),
                                          child: Text(
                                            trainer['trainer_id'] ??
                                                trainer['id']?.toString() ??
                                                'TR',
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: lightGold,
                                              height: 1.0,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        // Compact Delete icon
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          onTap: () =>
                                              _confirmDeleteTrainer(trainer),
                                          child: const Padding(
                                            padding: EdgeInsets.all(2),
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 17,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 10,
                                      runSpacing: 2,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.phone_rounded,
                                              size: 11,
                                              color: primaryGold,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              trainer['phone'] ??
                                                  trainer['contact'] ??
                                                  trainer['phone_number'] ??
                                                  'N/A',
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white70,
                                                height: 1.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.workspace_premium_rounded,
                                              size: 11,
                                              color: primaryGold,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              "Exp: ${trainer['experience'] ?? trainer['exp'] ?? '3+ Years'}",
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: lightGold,
                                                height: 1.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (trainer['aadhar_number'] != null &&
                                            trainer['aadhar_number']
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.fingerprint_rounded,
                                                size: 11,
                                                color: primaryGold,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                "Aadhar: ${SupabaseService.formatAadharNumber(trainer['aadhar_number'].toString())}",
                                                style: GoogleFonts.rajdhani(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white70,
                                                  height: 1.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildEmptyPlaceholder(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryGold.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.manage_search_rounded, size: 48, color: primaryGold),
          const SizedBox(height: 12),
          Text(
            message,
            style: GoogleFonts.rajdhani(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.rajdhani(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection({
    required TextEditingController flatNameController,
    required TextEditingController flatNoController,
    required TextEditingController streetController,
    required TextEditingController landmarkController,
    required TextEditingController cityController,
    required TextEditingController districtController,
    required TextEditingController stateController,
    required TextEditingController pincodeController,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF08180F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryGold.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: primaryGold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: primaryGold.withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: primaryGold,
                  size: 15,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "RESIDENTIAL / POSTAL ADDRESS",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: lightGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 1: Flat/House No & Flat/House Name
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _buildInputField(
                  controller: flatNoController,
                  label: "FLAT / HOUSE NO.",
                  hint: "e.g. Flat 402 / #12",
                  icon: Icons.tag_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 7,
                child: _buildInputField(
                  controller: flatNameController,
                  label: "FLAT / HOUSE NAME",
                  hint: "e.g. Galaxy Residency",
                  icon: Icons.apartment_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: Street / Area
          _buildInputField(
            controller: streetController,
            label: "STREET / AREA",
            hint: "e.g. 2nd Cross, 100ft Road, Indiranagar",
            icon: Icons.home_work_outlined,
          ),
          const SizedBox(height: 10),
          // Row 3: Landmark
          _buildInputField(
            controller: landmarkController,
            label: "LANDMARK",
            hint: "e.g. Near Metro Station / Opp. SBI Bank",
            icon: Icons.near_me_outlined,
          ),
          const SizedBox(height: 10),
          // Row 4: City / Town & District
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: _buildInputField(
                  controller: cityController,
                  label: "CITY / TOWN",
                  hint: "e.g. Bengaluru",
                  icon: Icons.location_city_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: _buildInputField(
                  controller: districtController,
                  label: "DISTRICT",
                  hint: "e.g. Bengaluru Urban",
                  icon: Icons.holiday_village_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 5: State & PINCODE
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: _buildInputField(
                  controller: stateController,
                  label: "STATE",
                  hint: "e.g. Karnataka",
                  icon: Icons.map_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: _buildInputField(
                  controller: pincodeController,
                  label: "PINCODE (6 DIGITS)",
                  hint: "e.g. 560038",
                  icon: Icons.markunread_mailbox_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (v) {
                    if (v != null &&
                        v.trim().isNotEmpty &&
                        v.trim().length != 6) {
                      return "Enter valid 6-digit PIN";
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool enabled = true,
    bool isPhone = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final bool phoneField = isPhone || keyboardType == TextInputType.phone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: primaryGold,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator:
              validator ??
              (phoneField
                  ? (v) {
                      if (v != null &&
                          v.trim().isNotEmpty &&
                          v.trim().length != 10) {
                        return "Enter valid 10-digit mobile number";
                      }
                      return null;
                    }
                  : null),
          enabled: enabled,
          keyboardType: phoneField ? TextInputType.number : keyboardType,
          inputFormatters: phoneField
              ? [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ]
              : inputFormatters,
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.white : Colors.white54,
          ),
          decoration: InputDecoration(
            hintText: phoneField ? "98765 43210" : hint,
            hintStyle: GoogleFonts.rajdhani(
              color: Colors.white.withValues(alpha: 0.25),
            ),
            filled: true,
            fillColor: const Color(0xFF08180F),
            prefixIcon: phoneField
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.phone_android_rounded,
                          color: primaryGold,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "+91",
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: primaryGold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 1,
                          height: 16,
                          color: primaryGold.withValues(alpha: 0.35),
                        ),
                      ],
                    ),
                  )
                : Icon(
                    icon,
                    color: enabled
                        ? primaryGold.withValues(alpha: 0.8)
                        : primaryGold.withValues(alpha: 0.3),
                    size: 18,
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: inputBorderColor, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: primaryGold, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: inputBorderColor.withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SECTION: MEMBERSHIP RENEWALS MANAGEMENT
  // ==========================================
  Widget _buildRenewalsSection() {
    final filteredMembers = _members.where((m) {
      final name = (m['full_name'] ?? '').toString().toLowerCase();
      final id = (m['member_id'] ?? '').toString().toLowerCase();
      final phone = (m['phone'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || id.contains(q) || phone.contains(q);
    }).toList();

    final pendingCount = _members
        .where(
          (m) =>
              m['renewal_status'] == 'Pending Approval' ||
              m['renewal_status'] == 'Pending Renewal' ||
              m['renewal_status'] == 'Requested',
        )
        .length;
    final expiringCount = _members.where((m) {
      final d = SupabaseService.daysRemaining(
        m['membership_expiry_date']?.toString(),
      );
      return d >= 0 && d <= 7;
    }).length;
    final activeCount = _members.where((m) => m['is_active'] == true).length;

    final sortedMembers = List<Map<String, dynamic>>.from(filteredMembers);
    sortedMembers.sort((a, b) {
      final aReq =
          a['renewal_status'] == 'Pending Approval' ||
          a['renewal_status'] == 'Pending Renewal' ||
          a['renewal_status'] == 'Requested';
      final bReq =
          b['renewal_status'] == 'Pending Approval' ||
          b['renewal_status'] == 'Pending Renewal' ||
          b['renewal_status'] == 'Requested';
      if (aReq && !bReq) return -1;
      if (!aReq && bReq) return 1;
      return 0;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick Stats Overview Cards
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: "ACTIVE PASSES",
                value: "$activeCount",
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                title: "PENDING APPROVALS",
                value: "$pendingCount",
                icon: Icons.pending_actions_rounded,
                color: Colors.amberAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                title: "EXPIRING (≤7 DAYS)",
                value: "$expiringCount",
                icon: Icons.hourglass_bottom_rounded,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Section Title & Search
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "MEMBERSHIP RENEWAL & EXPIRY",
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: lightGold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: primaryGold.withValues(alpha: 0.4)),
              ),
              child: Text(
                "${filteredMembers.length} MEMBERS",
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: primaryGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search Field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF08180F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inputBorderColor, width: 1),
          ),
          child: TextField(
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: "Search member by ID, Name or Phone to renew...",
              hintStyle: GoogleFonts.rajdhani(
                color: Colors.white.withValues(alpha: 0.3),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: primaryGold,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: primaryGold),
                ),
              )
            : sortedMembers.isEmpty
            ? _buildEmptyPlaceholder("No members match search.")
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedMembers.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final member = sortedMembers[index];
                  final isActive = member['is_active'] == true;
                  final expiryDateStr = member['membership_expiry_date']
                      ?.toString();
                  final daysLeft = SupabaseService.daysRemaining(expiryDateStr);
                  final isRenewalPending =
                      member['renewal_status'] == 'Pending Approval' ||
                      member['renewal_status'] == 'Pending Renewal' ||
                      member['renewal_status'] == 'Requested';
                  final requestedPlan = member['requested_renewal_plan']
                      ?.toString();

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardSurface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isRenewalPending
                            ? Colors.amberAccent
                            : (daysLeft <= 5 && daysLeft >= 0)
                            ? Colors.redAccent.withValues(alpha: 0.7)
                            : primaryGold.withValues(alpha: 0.3),
                        width:
                            (isRenewalPending ||
                                (daysLeft <= 5 && daysLeft >= 0))
                            ? 1.4
                            : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row: Avatar + Name + Status Badges
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isRenewalPending
                                    ? const Color(0xFF2E2207)
                                    : primaryGreen,
                                border: Border.all(
                                  color: isRenewalPending
                                      ? Colors.amberAccent
                                      : primaryGold,
                                  width: 1.4,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                (member['full_name'] ?? 'M')
                                    .toString()
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: GoogleFonts.montserrat(
                                  color: isRenewalPending
                                      ? Colors.amberAccent
                                      : lightGold,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          member['full_name'] ??
                                              'Unknown Member',
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isRenewalPending
                                              ? Colors.amber.shade900
                                              : (isActive
                                                    ? Colors.green.shade900
                                                          .withValues(
                                                            alpha: 0.6,
                                                          )
                                                    : Colors.red.shade900
                                                          .withValues(
                                                            alpha: 0.6,
                                                          )),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: isRenewalPending
                                                ? Colors.amberAccent
                                                : (isActive
                                                      ? Colors.greenAccent
                                                      : Colors.redAccent),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          isRenewalPending
                                              ? "RENEWAL REQUESTED"
                                              : (isActive
                                                    ? "ACTIVE"
                                                    : "INACTIVE"),
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: isRenewalPending
                                                ? Colors.white
                                                : (isActive
                                                      ? Colors.greenAccent
                                                      : Colors.redAccent),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    "ID: ${member['member_id']} • ${member['phone'] ?? 'No phone'}",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: primaryGold.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Membership Plan & Expiry Details Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF08180F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isRenewalPending
                                  ? Colors.amberAccent.withValues(alpha: 0.4)
                                  : inputBorderColor,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.card_membership_rounded,
                                        size: 16,
                                        color: primaryGold,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Current Plan: ${member['plan'] ?? 'Monthly'}",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: lightGold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: daysLeft <= 5
                                          ? Colors.red.shade900.withValues(
                                              alpha: 0.6,
                                            )
                                          : primaryGreen,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: daysLeft <= 5
                                            ? Colors.redAccent
                                            : primaryGold,
                                        width: 0.9,
                                      ),
                                    ),
                                    child: Text(
                                      expiryDateStr != null
                                          ? (daysLeft > 0
                                                ? "$daysLeft Days Remaining"
                                                : "Plan Expired")
                                          : "Active",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: daysLeft <= 5
                                            ? Colors.redAccent
                                            : primaryGold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Registered Expiry Date:",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Text(
                                    expiryDateStr != null
                                        ? expiryDateStr.split('T')[0]
                                        : "Not assigned",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Alert for Pending Renewal
                        if (isRenewalPending) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade900.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.amberAccent,
                                width: 0.9,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.pending_actions_rounded,
                                  size: 16,
                                  color: Colors.amberAccent,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    "Requested: ${requestedPlan ?? member['plan']}. Click below to review & accept.",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),
                        Divider(
                          color: primaryGold.withValues(alpha: 0.15),
                          height: 1,
                        ),
                        const SizedBox(height: 10),

                        // Action Button: Renew Plan
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isRenewalPending
                                  ? const Color(0xFF2E2207)
                                  : primaryGreen,
                              foregroundColor: isRenewalPending
                                  ? Colors.amberAccent
                                  : lightGold,
                              side: BorderSide(
                                color: isRenewalPending
                                    ? Colors.amberAccent
                                    : primaryGold,
                                width: 1.2,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Icon(
                              Icons.autorenew_rounded,
                              size: 18,
                              color: isRenewalPending
                                  ? Colors.amberAccent
                                  : primaryGold,
                            ),
                            label: Text(
                              isRenewalPending
                                  ? "REVIEW & ACCEPT RENEWAL"
                                  : "RENEW / EXTEND PLAN",
                              style: GoogleFonts.rajdhani(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: isRenewalPending
                                    ? Colors.amberAccent
                                    : lightGold,
                              ),
                            ),
                            onPressed: () => _showRenewModal(member),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

        const SizedBox(height: 80),
      ],
    );
  }

  // ==========================================
  // SECTION: PERSONAL TRAINING (PT) MANAGEMENT
  // ==========================================
  Widget _buildPersonalTrainingSection() {
    final filteredMembers = _members.where((m) {
      final name = (m['full_name'] ?? '').toString().toLowerCase();
      final id = (m['member_id'] ?? '').toString().toLowerCase();
      final phone = (m['phone'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || id.contains(q) || phone.contains(q);
    }).toList();

    final activePtCount = _members.where((m) => m['has_pt'] == true).length;
    final ptRequestsCount = _members
        .where(
          (m) =>
              m['pt_status'] == 'Requested' ||
              m['pt_status'] == 'PT Requested' ||
              m['pt_status'] == 'Pending Approval',
        )
        .length;
    final trainersCount = _trainers.length;

    final sortedMembers = List<Map<String, dynamic>>.from(filteredMembers);
    sortedMembers.sort((a, b) {
      final aReq =
          a['pt_status'] == 'Requested' ||
          a['pt_status'] == 'PT Requested' ||
          a['pt_status'] == 'Pending Approval';
      final bReq =
          b['pt_status'] == 'Requested' ||
          b['pt_status'] == 'PT Requested' ||
          b['pt_status'] == 'Pending Approval';
      if (aReq && !bReq) return -1;
      if (!aReq && bReq) return 1;
      return 0;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick Stats Overview Cards
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: "ACTIVE PT VIPs",
                value: "$activePtCount",
                icon: Icons.sports_gymnastics_rounded,
                color: primaryGold,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                title: "PT REQUESTS",
                value: "$ptRequestsCount",
                icon: Icons.contact_support_rounded,
                color: Colors.amberAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                title: "PT COACHES",
                value: "$trainersCount",
                icon: Icons.sports_mma_rounded,
                color: const Color(0xFF4CAF50),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Section Title & Search
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "PERSONAL TRAINING (PT) ROSTER",
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: lightGold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: primaryGold.withValues(alpha: 0.4)),
              ),
              child: Text(
                "$activePtCount PT ACTIVE",
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: primaryGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search Field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF08180F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inputBorderColor, width: 1),
          ),
          child: TextField(
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: "Search athlete to assign coach or manage PT...",
              hintStyle: GoogleFonts.rajdhani(
                color: Colors.white.withValues(alpha: 0.3),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: primaryGold,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: primaryGold),
                ),
              )
            : sortedMembers.isEmpty
            ? _buildEmptyPlaceholder("No athletes match search.")
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedMembers.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final member = sortedMembers[index];
                  final hasPt = member['has_pt'] == true;
                  final isPtRequested =
                      member['pt_status'] == 'Requested' ||
                      member['pt_status'] == 'PT Requested' ||
                      member['pt_status'] == 'Pending Approval';
                  final ptExpiryStr = member['pt_expiry_date']?.toString();
                  final ptDaysLeft = SupabaseService.daysRemaining(ptExpiryStr);
                  final requestedPtPlan = member['requested_pt_plan']
                      ?.toString();
                  final requestedPtTrainer = member['requested_pt_trainer']
                      ?.toString();

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardSurface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isPtRequested
                            ? Colors.amberAccent
                            : hasPt
                            ? primaryGold.withValues(alpha: 0.6)
                            : primaryGold.withValues(alpha: 0.25),
                        width: (isPtRequested || hasPt) ? 1.4 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row: Avatar + Name + Status Badges
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasPt
                                    ? const Color(0xFF2E2207)
                                    : primaryGreen,
                                border: Border.all(
                                  color: hasPt ? lightGold : primaryGold,
                                  width: 1.4,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                (member['full_name'] ?? 'M')
                                    .toString()
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: GoogleFonts.montserrat(
                                  color: lightGold,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          member['full_name'] ??
                                              'Unknown Athlete',
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: hasPt
                                              ? primaryGold
                                              : (isPtRequested
                                                    ? Colors.amber.shade900
                                                    : const Color(0xFF08180F)),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: hasPt
                                                ? lightGold
                                                : (isPtRequested
                                                      ? Colors.amberAccent
                                                      : primaryGold.withValues(
                                                          alpha: 0.3,
                                                        )),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          hasPt
                                              ? "PT VIP"
                                              : (isPtRequested
                                                    ? "REQUESTED"
                                                    : "NO PT"),
                                          style: GoogleFonts.rajdhani(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                            color: hasPt
                                                ? const Color(0xFF091911)
                                                : (isPtRequested
                                                      ? Colors.amberAccent
                                                      : Colors.white60),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    "ID: ${member['member_id']} • ${member['phone'] ?? 'No phone'}",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: primaryGold.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // PT Details Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF08180F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: hasPt
                                  ? primaryGold.withValues(alpha: 0.4)
                                  : inputBorderColor,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.sports_gymnastics_rounded,
                                        size: 16,
                                        color: primaryGold,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "PT Plan: ${hasPt ? (member['pt_plan'] ?? 'Monthly PT') : 'Not Enrolled'}",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: hasPt
                                              ? lightGold
                                              : Colors.white60,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (hasPt && ptExpiryStr != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: ptDaysLeft <= 5
                                            ? Colors.red.shade900.withValues(
                                                alpha: 0.5,
                                              )
                                            : primaryGreen,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        ptDaysLeft > 0
                                            ? "$ptDaysLeft D Left"
                                            : "PT Expired",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: ptDaysLeft <= 5
                                              ? Colors.redAccent
                                              : primaryGold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Assigned Dedicated Coach:",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Text(
                                    hasPt
                                        ? "${member['pt_trainer'] ?? 'Unassigned'}"
                                        : "None",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: hasPt
                                          ? primaryGold
                                          : Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                              if (hasPt && ptExpiryStr != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "PT Expiration Date:",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    Text(
                                      ptExpiryStr.split('T')[0],
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Alert for Requested PT
                        if (isPtRequested) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade900.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.amberAccent,
                                width: 0.9,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.pending_actions_rounded,
                                  size: 16,
                                  color: Colors.amberAccent,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    "Requested: ${requestedPtPlan ?? member['pt_plan'] ?? 'PT Plan'} with ${requestedPtTrainer != null && requestedPtTrainer.isNotEmpty ? 'Coach $requestedPtTrainer' : 'Coach of Admin Choice'}. Click below to review & accept.",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),
                        Divider(
                          color: primaryGold.withValues(alpha: 0.15),
                          height: 1,
                        ),
                        const SizedBox(height: 10),

                        // Action Button: Assign / Manage PT
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPtRequested
                                  ? const Color(0xFF2E2207)
                                  : (hasPt
                                        ? const Color(0xFF1E3A2B)
                                        : primaryGreen),
                              foregroundColor: isPtRequested
                                  ? Colors.amberAccent
                                  : lightGold,
                              side: BorderSide(
                                color: isPtRequested
                                    ? Colors.amberAccent
                                    : primaryGold,
                                width: 1.2,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Icon(
                              Icons.sports_gymnastics_rounded,
                              size: 18,
                              color: isPtRequested
                                  ? Colors.amberAccent
                                  : primaryGold,
                            ),
                            label: Text(
                              isPtRequested
                                  ? "REVIEW & ACCEPT PT REQUEST"
                                  : (hasPt
                                        ? "MANAGE PT / EXTEND"
                                        : "ASSIGN PERSONAL TRAINING"),
                              style: GoogleFonts.rajdhani(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: isPtRequested
                                    ? Colors.amberAccent
                                    : lightGold,
                              ),
                            ),
                            onPressed: () => _showAssignPtModal(member),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

        const SizedBox(height: 80),
      ],
    );
  }

  // Quick picker for FAB renewal
  void _showSelectMemberForRenewal() {
    String search = "";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final list = _members.where((m) {
            final name = (m['full_name'] ?? '').toString().toLowerCase();
            final id = (m['member_id'] ?? '').toString().toLowerCase();
            final q = search.toLowerCase();
            return name.contains(q) || id.contains(q);
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: primaryGold.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: primaryGold.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.autorenew_rounded,
                      color: primaryGold,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "SELECT MEMBER TO RENEW",
                      style: GoogleFonts.rajdhani(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: lightGold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF08180F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: inputBorderColor),
                  ),
                  child: TextField(
                    style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    onChanged: (val) => setModalState(() => search = val),
                    decoration: InputDecoration(
                      hintText: "Search member name or ID...",
                      hintStyle: GoogleFonts.rajdhani(color: Colors.white38),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: primaryGold,
                        size: 18,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final m = list[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: cardSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primaryGold.withValues(alpha: 0.2),
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: primaryGreen,
                            child: Text(
                              (m['full_name'] ?? 'M')
                                  .toString()
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: GoogleFonts.montserrat(
                                color: lightGold,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            "${m['full_name']} (${m['member_id']})",
                            style: GoogleFonts.rajdhani(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            "Plan: ${m['plan'] ?? 'Monthly'} • Expiry: ${m['membership_expiry_date'] ?? 'N/A'}",
                            style: GoogleFonts.rajdhani(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: primaryGold,
                            size: 14,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _showRenewModal(m);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Quick picker for FAB PT assignment
  void _showSelectMemberForPt() {
    String search = "";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final list = _members.where((m) {
            final name = (m['full_name'] ?? '').toString().toLowerCase();
            final id = (m['member_id'] ?? '').toString().toLowerCase();
            final q = search.toLowerCase();
            return name.contains(q) || id.contains(q);
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: primaryGold.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: primaryGold.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.sports_gymnastics_rounded,
                      color: primaryGold,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "SELECT ATHLETE FOR PERSONAL TRAINING",
                      style: GoogleFonts.rajdhani(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: lightGold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF08180F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: inputBorderColor),
                  ),
                  child: TextField(
                    style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    onChanged: (val) => setModalState(() => search = val),
                    decoration: InputDecoration(
                      hintText: "Search athlete name or ID...",
                      hintStyle: GoogleFonts.rajdhani(color: Colors.white38),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: primaryGold,
                        size: 18,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final m = list[index];
                      final hasPt = m['has_pt'] == true;
                      return Container(
                        decoration: BoxDecoration(
                          color: cardSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasPt
                                ? primaryGold
                                : primaryGold.withValues(alpha: 0.2),
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: hasPt
                                ? const Color(0xFF2E2207)
                                : primaryGreen,
                            child: Text(
                              (m['full_name'] ?? 'M')
                                  .toString()
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: GoogleFonts.montserrat(
                                color: hasPt ? lightGold : primaryGold,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            "${m['full_name']} (${m['member_id']})",
                            style: GoogleFonts.rajdhani(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            hasPt
                                ? "PT: ${m['pt_plan'] ?? 'Monthly'} • Coach: ${m['pt_trainer'] ?? 'Unassigned'}"
                                : "No PT active",
                            style: GoogleFonts.rajdhani(
                              fontSize: 12,
                              color: hasPt ? lightGold : Colors.white60,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: primaryGold,
                            size: 14,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _showAssignPtModal(m);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // SECTION: MEMBERSHIP & PT PLANS MANAGEMENT
  // ==========================================
  Widget _buildPlansManagementSection() {
    final filteredMembershipPlans = _membershipPlansList.where((p) {
      final name = (p['plan_name'] ?? '').toString().toLowerCase();
      final desc = (p['description'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();

    final filteredPtPlans = _ptPlansList.where((p) {
      final name = (p['plan_name'] ?? '').toString().toLowerCase();
      final desc = (p['description'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick Stats Overview Cards
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: "MEMBERSHIP TIERS",
                value: "${_membershipPlansList.length}",
                icon: Icons.card_membership_rounded,
                color: primaryGold,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: "PT PLANS",
                value: "${_ptPlansList.length}",
                icon: Icons.sports_gymnastics_rounded,
                color: const Color(0xFFFFD54F),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Section Title & Search
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "PRICING & PLANS CONFIGURATION",
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: lightGold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: primaryGold.withValues(alpha: 0.4)),
              ),
              child: Text(
                "${filteredMembershipPlans.length + filteredPtPlans.length} TIERS",
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: primaryGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search Field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF08180F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inputBorderColor, width: 1),
          ),
          child: TextField(
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: "Search plan name or description...",
              hintStyle: GoogleFonts.rajdhani(
                color: Colors.white.withValues(alpha: 0.3),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: primaryGold,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // 1. MEMBERSHIP PLANS SUBSECTION
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(
                    Icons.card_membership_rounded,
                    color: primaryGold,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "MEMBERSHIP PLANS & ADMISSION",
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: lightGold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () => _showAddPlanModal(isPt: false),
              icon: const Icon(Icons.add_rounded, color: primaryGold, size: 16),
              label: Text(
                "ADD TIER",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: primaryGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredMembershipPlans.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final plan = filteredMembershipPlans[index];
            final price =
                double.tryParse(plan['price']?.toString() ?? '0') ?? 0.0;
            final durationMonths = plan['duration_months'] ?? 1;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardSurface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primaryGold.withValues(alpha: 0.35),
                  width: 1.1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryGreen,
                      border: Border.all(color: primaryGold, width: 1.2),
                    ),
                    child: const Icon(
                      Icons.fitness_center_rounded,
                      color: primaryGold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              (plan['plan_name'] ?? 'Plan')
                                  .toString()
                                  .toUpperCase(),
                              style: GoogleFonts.rajdhani(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF08180F),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: primaryGold,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                "₹${price.toStringAsFixed(0)}",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: lightGold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: primaryGreen,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                durationMonths == 0
                                    ? "ONE-TIME ADMISSION"
                                    : "$durationMonths MONTHS DURATION",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: primaryGold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_note_rounded,
                      color: primaryGold,
                      size: 24,
                    ),
                    tooltip: "Modify Plan Charges",
                    onPressed: () =>
                        _showEditPlanModal(plan: plan, isPt: false),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 28),

        // 2. PERSONAL TRAINING (PT) SUBSECTION
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(
                    Icons.sports_gymnastics_rounded,
                    color: primaryGold,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "PERSONAL TRAINING (PT) CHARGES",
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: lightGold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () => _showAddPlanModal(isPt: true),
              icon: const Icon(Icons.add_rounded, color: primaryGold, size: 16),
              label: Text(
                "ADD PT TIER",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: primaryGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredPtPlans.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final ptPlan = filteredPtPlans[index];
            final price =
                double.tryParse(ptPlan['price']?.toString() ?? '0') ?? 0.0;
            final durationMonths = ptPlan['duration_months'] ?? 1;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF192415),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primaryGold.withValues(alpha: 0.5),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2E2207),
                      border: Border.all(color: lightGold, width: 1.2),
                    ),
                    child: const Icon(
                      Icons.sports_gymnastics_rounded,
                      color: lightGold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              (ptPlan['plan_name'] ?? 'PT Plan')
                                  .toString()
                                  .toUpperCase(),
                              style: GoogleFonts.rajdhani(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF08180F),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: primaryGold,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                "₹${price.toStringAsFixed(0)}",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: lightGold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: primaryGold,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "$durationMonths MONTH DEDICATED PT",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF091911),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.edit_note_rounded,
                      color: lightGold,
                      size: 24,
                    ),
                    tooltip: "Modify PT Charges",
                    onPressed: () =>
                        _showEditPlanModal(plan: ptPlan, isPt: true),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 80),
      ],
    );
  }

  // ==========================================
  // EDIT PLAN CHARGES MODAL
  // ==========================================
  void _showEditPlanModal({
    required Map<String, dynamic> plan,
    required bool isPt,
  }) {
    final nameController = TextEditingController(
      text: plan['plan_name']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: (plan['price'] is num)
          ? (plan['price'] as num).toStringAsFixed(0)
          : (plan['price']?.toString() ?? '0'),
    );
    final durationController = TextEditingController(
      text: plan['duration_months']?.toString() ?? '1',
    );
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: primaryGold.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: primaryGold.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        isPt
                            ? Icons.sports_gymnastics_rounded
                            : Icons.price_change_rounded,
                        color: primaryGold,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isPt ? "EDIT PT CHARGES" : "EDIT PLAN CHARGES",
                        style: GoogleFonts.rajdhani(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                          color: lightGold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Update price and details for ${plan['plan_name']}",
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 18),

                  _buildInputField(
                    controller: nameController,
                    label: "PLAN NAME",
                    hint: "e.g. Monthly",
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 12),

                  _buildInputField(
                    controller: priceController,
                    label: "RATE / CHARGES (₹ INR)",
                    hint: "e.g. 888",
                    icon: Icons.currency_rupee_rounded,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),

                  _buildInputField(
                    controller: durationController,
                    label: "DURATION IN MONTHS (0 for Admission)",
                    hint: "e.g. 1",
                    icon: Icons.calendar_month_rounded,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),

                  // Save Action Button
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9E7B1A), primaryGold, lightGold],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: isSaving
                            ? null
                            : () async {
                                final parsedPrice =
                                    double.tryParse(
                                      priceController.text.trim(),
                                    ) ??
                                    0.0;
                                final parsedMonths =
                                    int.tryParse(
                                      durationController.text.trim(),
                                    ) ??
                                    1;

                                setModalState(() => isSaving = true);

                                if (isPt) {
                                  await SupabaseService.adminUpdatePtPlan(
                                    id: plan['id']?.toString() ?? '',
                                    planName: nameController.text.trim(),
                                    price: parsedPrice,
                                    durationMonths: parsedMonths,
                                  );
                                } else {
                                  await SupabaseService.adminUpdateMembershipPlan(
                                    id: plan['id']?.toString() ?? '',
                                    planName: nameController.text.trim(),
                                    price: parsedPrice,
                                    durationMonths: parsedMonths,
                                  );
                                }

                                setModalState(() => isSaving = false);
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                _loadAllData();

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: primaryGreen,
                                    content: Text(
                                      "Plan charges updated successfully!",
                                      style: GoogleFonts.rajdhani(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                );
                              },
                        child: Center(
                          child: isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF091911),
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  "SAVE CHARGES",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.0,
                                    color: const Color(0xFF091911),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // ADD NEW PLAN MODAL
  // ==========================================
  void _showAddPlanModal({bool isPt = false}) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final durationController = TextEditingController(text: "1");
    bool isPtPlan = isPt;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: primaryGold.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: primaryGold.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.add_card_rounded,
                        color: primaryGold,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "ADD NEW PRICING TIER",
                        style: GoogleFonts.rajdhani(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                          color: lightGold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Category Selector
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => isPtPlan = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !isPtPlan
                                  ? primaryGold
                                  : const Color(0xFF08180F),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: primaryGold),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "MEMBERSHIP PLAN",
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: !isPtPlan
                                    ? const Color(0xFF091911)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => isPtPlan = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isPtPlan
                                  ? primaryGold
                                  : const Color(0xFF08180F),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: primaryGold),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "PERSONAL TRAINING (PT)",
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: isPtPlan
                                    ? const Color(0xFF091911)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _buildInputField(
                    controller: nameController,
                    label: "PLAN NAME",
                    hint: isPtPlan ? "e.g. 3 Months PT" : "e.g. 2 Years VIP",
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 12),

                  _buildInputField(
                    controller: priceController,
                    label: "RATE / CHARGES (₹ INR)",
                    hint: "e.g. 3000",
                    icon: Icons.currency_rupee_rounded,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),

                  _buildInputField(
                    controller: durationController,
                    label: "DURATION IN MONTHS",
                    hint: "e.g. 1",
                    icon: Icons.calendar_month_rounded,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),

                  // Create Action Button
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9E7B1A), primaryGold, lightGold],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: isSaving
                            ? null
                            : () async {
                                if (nameController.text.trim().isEmpty ||
                                    priceController.text.trim().isEmpty) {
                                  return;
                                }

                                final parsedPrice =
                                    double.tryParse(
                                      priceController.text.trim(),
                                    ) ??
                                    0.0;
                                final parsedMonths =
                                    int.tryParse(
                                      durationController.text.trim(),
                                    ) ??
                                    1;

                                setModalState(() => isSaving = true);

                                if (isPtPlan) {
                                  await SupabaseService.adminCreatePtPlan(
                                    planName: nameController.text.trim(),
                                    price: parsedPrice,
                                    durationMonths: parsedMonths,
                                  );
                                } else {
                                  await SupabaseService.adminCreateMembershipPlan(
                                    planName: nameController.text.trim(),
                                    price: parsedPrice,
                                    durationMonths: parsedMonths,
                                  );
                                }

                                setModalState(() => isSaving = false);
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                _loadAllData();

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: primaryGreen,
                                    content: Text(
                                      "New plan created successfully!",
                                      style: GoogleFonts.rajdhani(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                );
                              },
                        child: Center(
                          child: isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF091911),
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  "CREATE & ACTIVATE PLAN",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.0,
                                    color: const Color(0xFF091911),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SECTION: REVENUE & FINANCIAL ANALYTICS
  // ==========================================
  Widget _buildRevenueSection() {
    final double grandTotal = _grandTotalRevenue;
    final double memRev = _totalMembershipRevenue;
    final double ptRev = _totalPtRevenue;
    final double memPercent = grandTotal > 0
        ? (memRev / grandTotal) * 100
        : 0.0;
    final double ptPercent = grandTotal > 0 ? (ptRev / grandTotal) * 100 : 0.0;

    final ptMembersList = _members.where((m) {
      return m['has_pt'] == true ||
          (m['pt_status'] != null &&
              m['pt_status'].toString().trim().isNotEmpty &&
              m['pt_status'] != 'None');
    }).toList();

    // Aggregate Membership breakdown by plan name
    final Map<String, int> memPlanCounts = {};
    for (final m in _members) {
      final pName = (m['plan'] ?? 'Monthly').toString().trim();
      memPlanCounts[pName] = (memPlanCounts[pName] ?? 0) + 1;
    }

    // Aggregate PT breakdown by PT plan name
    final Map<String, int> ptPlanCounts = {};
    for (final m in ptMembersList) {
      final pName = (m['pt_plan'] ?? 'Monthly PT').toString().trim();
      ptPlanCounts[pName] = (ptPlanCounts[pName] ?? 0) + 1;
    }

    // Aggregate PT breakdown by Trainer
    final Map<String, Map<String, dynamic>> trainerPtStats = {};
    for (final t in _trainers) {
      final tName = (t['full_name'] ?? t['name'] ?? '').toString().trim();
      if (tName.isNotEmpty) {
        trainerPtStats[tName] = {
          'count': 0,
          'revenue': 0.0,
          'trainer_id': t['trainer_id'] ?? '',
        };
      }
    }
    for (final m in ptMembersList) {
      final tName = (m['pt_trainer'] ?? m['assigned_trainer'] ?? '')
          .toString()
          .trim();
      final ptCost = _getPtPlanPrice(m['pt_plan']?.toString());
      if (tName.isNotEmpty) {
        if (!trainerPtStats.containsKey(tName)) {
          trainerPtStats[tName] = {
            'count': 0,
            'revenue': 0.0,
            'trainer_id': '',
          };
        }
        trainerPtStats[tName]!['count'] =
            (trainerPtStats[tName]!['count'] as int) + 1;
        trainerPtStats[tName]!['revenue'] =
            (trainerPtStats[tName]!['revenue'] as double) + ptCost;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "REVENUE & EARNINGS",
              style: GoogleFonts.rajdhani(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
                color: Colors.white,
              ),
            ),
            Text(
              "Live gym financials, membership streams & personal training revenue",
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white60,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ====================================================
        // HERO CARD: GRAND TOTAL GYM REVENUE
        // ====================================================
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF163E2B), Color(0xFF0F2B1D), Color(0xFF081910)],
            ),
            border: Border.all(
              color: primaryGold.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryGold.withValues(alpha: 0.12),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryGold.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryGold.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: lightGold,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "TOTAL GYM REVENUE",
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: lightGold,
                          ),
                        ),
                        Text(
                          "Combined Membership + PT",
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2216),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.insights_rounded,
                          color: Color(0xFF10B981),
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "AUDIT",
                          style: GoogleFonts.rajdhani(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Big Grand Total Rupee Display
              Text(
                _formatIndianCurrency(grandTotal),
                style: GoogleFonts.rajdhani(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: primaryGold.withValues(alpha: 0.5),
                      blurRadius: 16,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Visual Proportional Distribution Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "MEMBERSHIP: ${_formatIndianCurrency(memRev)} (${memPercent.toStringAsFixed(1)}%)",
                            style: GoogleFonts.rajdhani(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: const Color(0xFF6EE7B7),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "PT: ${_formatIndianCurrency(ptRev)} (${ptPercent.toStringAsFixed(1)}%)",
                            style: GoogleFonts.rajdhani(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: const Color(0xFFFDE68A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF07140D),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: grandTotal == 0
                          ? const SizedBox()
                          : Row(
                              children: [
                                if (memPercent > 0)
                                  Flexible(
                                    flex: (memPercent * 10).round().clamp(
                                      1,
                                      1000,
                                    ),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFF059669),
                                            Color(0xFF10B981),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                if (ptPercent > 0)
                                  Flexible(
                                    flex: (ptPercent * 10).round().clamp(
                                      1,
                                      1000,
                                    ),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFFD97706),
                                            Color(0xFFF59E0B),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Separate Membership & PT Revenue Summary Cards
              Row(
                children: [
                  Expanded(
                    child: _buildRevenueKpiCard(
                      icon: Icons.card_membership_rounded,
                      iconColor: const Color(0xFF10B981),
                      title: "MEMBERSHIP REVENUE",
                      value: _formatIndianCurrency(memRev),
                      subtitle: "Total Membership Earnings",
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildRevenueKpiCard(
                      icon: Icons.sports_gymnastics_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      title: "PT REVENUE",
                      value: _formatIndianCurrency(ptRev),
                      subtitle: "Personal Training Earnings",
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ====================================================
        // HORIZONTAL SCROLLABLE MONTHLY INCOME BAR CHART
        // ====================================================
        _buildMonthlyRevenueChart(),

        const SizedBox(height: 20),

        // ====================================================
        // SEPARATE BREAKDOWN CARDS (MEMBERSHIP & PT)
        // ====================================================
        // CARD 1: MEMBERSHIP REVENUE BREAKDOWN
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.card_membership_rounded,
                          color: Color(0xFF10B981),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "MEMBERSHIP REVENUE",
                        style: GoogleFonts.rajdhani(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF072115),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      "${memPercent.toStringAsFixed(1)}% SHARE",
                      style: GoogleFonts.rajdhani(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF6EE7B7),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                _formatIndianCurrency(memRev),
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: const Color(0xFF6EE7B7),
                ),
              ),
              Text(
                "${_members.length} enrolled members subscribed across plans",
                style: GoogleFonts.rajdhani(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),

              const SizedBox(height: 14),
              const Divider(color: Color(0xFF1B3D2B), height: 1),
              const SizedBox(height: 12),

              Text(
                "EARNINGS BY MEMBERSHIP PLAN",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: lightGold,
                ),
              ),
              const SizedBox(height: 8),

              if (memPlanCounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "No active membership subscriptions.",
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                )
              else
                ...memPlanCounts.entries.map((entry) {
                  final planName = entry.key;
                  final count = entry.value;
                  final unitPrice = _getMembershipPlanPrice(planName);
                  final subTotal = unitPrice * count;
                  return _buildBreakdownRow(
                    title: planName,
                    badge: "$count subs",
                    unitPrice: _formatIndianCurrency(unitPrice),
                    subTotal: _formatIndianCurrency(subTotal),
                    accentColor: const Color(0xFF10B981),
                  );
                }),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // CARD 2: PT REVENUE BREAKDOWN
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.sports_gymnastics_rounded,
                          color: Color(0xFFF59E0B),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "PERSONAL TRAINING (PT)",
                        style: GoogleFonts.rajdhani(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF221706),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      "${ptPercent.toStringAsFixed(1)}% SHARE",
                      style: GoogleFonts.rajdhani(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFFDE68A),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                _formatIndianCurrency(ptRev),
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: const Color(0xFFFDE68A),
                ),
              ),
              Text(
                "${ptMembersList.length} active clients assigned to personal trainers",
                style: GoogleFonts.rajdhani(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),

              const SizedBox(height: 14),
              const Divider(color: Color(0xFF382910), height: 1),
              const SizedBox(height: 12),

              Text(
                "EARNINGS BY PT PLAN",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: lightGold,
                ),
              ),
              const SizedBox(height: 8),

              if (ptPlanCounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "No members currently enrolled in PT.",
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                )
              else
                ...ptPlanCounts.entries.map((entry) {
                  final planName = entry.key;
                  final count = entry.value;
                  final unitPrice = _getPtPlanPrice(planName);
                  final subTotal = unitPrice * count;
                  return _buildBreakdownRow(
                    title: planName,
                    badge: "$count clients",
                    unitPrice: _formatIndianCurrency(unitPrice),
                    subTotal: _formatIndianCurrency(subTotal),
                    accentColor: const Color(0xFFF59E0B),
                  );
                }),

              if (trainerPtStats.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  "PT EARNINGS BY TRAINER",
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: lightGold,
                  ),
                ),
                const SizedBox(height: 8),
                ...trainerPtStats.entries.map((entry) {
                  final trainerName = entry.key;
                  final count = entry.value['count'] as int;
                  final revenue = entry.value['revenue'] as double;
                  return _buildTrainerPtRow(
                    trainerName: trainerName,
                    clientCount: count,
                    revenue: _formatIndianCurrency(revenue),
                  );
                }),
              ],
            ],
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }

  // ==========================================
  // REVENUE SUB-WIDGETS
  // ==========================================
  Widget _buildRevenueKpiCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF08180F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: inputBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.rajdhani(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: Colors.white60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: lightGold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow({
    required String title,
    required String badge,
    required String unitPrice,
    required String subTotal,
    required Color accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF08180F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentColor.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  "@ $unitPrice",
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  subTotal,
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainerPtRow({
    required String trainerName,
    required int clientCount,
    required String revenue,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF08180F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sports_mma_rounded,
                  color: Color(0xFFF59E0B),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  trainerName,
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "$clientCount clients",
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFDE68A),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              revenue,
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFDE68A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MONTHLY REVENUE BAR CHART
  // ==========================================
  Widget _buildMonthlyRevenueChart() {
    final now = DateTime.now();
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    // Prepare 12 months starting with PRESENT month (index 0) followed by preceding months
    final List<DateTime> months = [];
    for (int i = 0; i < 12; i++) {
      int y = now.year;
      int m = now.month - i;
      while (m <= 0) {
        m += 12;
        y -= 1;
      }
      months.add(DateTime(y, m, 1));
    }

    // Aggregate monthly data
    final List<Map<String, dynamic>> monthlyData = [];
    double globalMax = 1.0;

    for (final dt in months) {
      double memRevenue = 0.0;
      double ptRevenue = 0.0;

      for (final m in _members) {
        // Membership revenue
        final memDate = _parseMemberDate(
          m['membership_start_date'] ?? m['created_at'],
        );
        if (memDate != null) {
          if (memDate.year == dt.year && memDate.month == dt.month) {
            memRevenue += _getMembershipPlanPrice(m['plan']?.toString());
          }
        } else if (dt.year == now.year && dt.month == now.month) {
          memRevenue += _getMembershipPlanPrice(m['plan']?.toString());
        }

        // PT revenue
        final bool hasPt =
            m['has_pt'] == true ||
            (m['pt_status'] != null &&
                m['pt_status'].toString().trim().isNotEmpty &&
                m['pt_status'] != 'None');
        if (hasPt) {
          final ptDate = _parseMemberDate(
            m['pt_start_date'] ?? m['created_at'] ?? m['membership_start_date'],
          );
          if (ptDate != null) {
            if (ptDate.year == dt.year && ptDate.month == dt.month) {
              ptRevenue += _getPtPlanPrice(m['pt_plan']?.toString());
            }
          } else if (dt.year == now.year && dt.month == now.month) {
            ptRevenue += _getPtPlanPrice(m['pt_plan']?.toString());
          }
        }
      }

      if (memRevenue > globalMax) globalMax = memRevenue;
      if (ptRevenue > globalMax) globalMax = ptRevenue;

      monthlyData.add({
        'date': dt,
        'memRevenue': memRevenue,
        'ptRevenue': ptRevenue,
        'total': memRevenue + ptRevenue,
        'isCurrent': dt.year == now.year && dt.month == now.month,
      });
    }

    const double maxBarHeight = 110.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryGold.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title & Legends
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryGold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryGold.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.bar_chart_rounded,
                        color: primaryGold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "MONTHLY INCOME",
                            style: GoogleFonts.rajdhani(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "Membership vs PT",
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white60,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Legend indicators
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildChartLegend(
                    color: const Color(0xFF10B981),
                    label: "MEMBERSHIP",
                  ),
                  const SizedBox(width: 6),
                  _buildChartLegend(
                    color: const Color(0xFFF59E0B),
                    label: "PT",
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF1B3D2B), height: 1),
          const SizedBox(height: 14),

          // Horizontally Scrollable Clean Bar Chart
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: monthlyData.map((data) {
                  final dt = data['date'] as DateTime;
                  final double memRev = data['memRevenue'] as double;
                  final double ptRev = data['ptRevenue'] as double;
                  final bool isCurrent = data['isCurrent'] as bool;
                  final monthLabel =
                      "${monthNames[dt.month - 1]} '${dt.year.toString().substring(2)}";

                  final double memHeight = memRev > 0
                      ? (memRev / globalMax * maxBarHeight).clamp(
                          8.0,
                          maxBarHeight,
                        )
                      : 4.0;
                  final double ptHeight = ptRev > 0
                      ? (ptRev / globalMax * maxBarHeight).clamp(
                          8.0,
                          maxBarHeight,
                        )
                      : 4.0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Two bars standing side-by-side
                        SizedBox(
                          height: maxBarHeight + 22,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // 1. Membership Bar
                              _buildSingleBar(
                                height: memHeight,
                                amount: memRev,
                                accentColor: const Color(0xFF10B981),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF34D399),
                                    Color(0xFF10B981),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),

                              // 2. PT Bar
                              _buildSingleBar(
                                height: ptHeight,
                                amount: ptRev,
                                accentColor: const Color(0xFFF59E0B),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFFDE68A),
                                    Color(0xFFF59E0B),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Baseline separator
                        Container(
                          width: 48,
                          height: 2,
                          margin: const EdgeInsets.only(top: 4, bottom: 6),
                          decoration: BoxDecoration(
                            color: isCurrent ? primaryGold : Colors.white12,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),

                        // Month Label
                        Text(
                          monthLabel,
                          style: GoogleFonts.rajdhani(
                            fontSize: 11.5,
                            fontWeight: isCurrent
                                ? FontWeight.w900
                                : FontWeight.w700,
                            color: isCurrent ? primaryGold : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleBar({
    required double height,
    required double amount,
    required Color accentColor,
    required LinearGradient gradient,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (amount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              _formatCompactRupee(amount),
              style: GoogleFonts.rajdhani(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: accentColor,
              ),
            ),
          )
        else
          const SizedBox(height: 16),
        Container(
          width: 20,
          height: height,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      ],
    );
  }

  Widget _buildChartLegend({required Color color, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentModeSelector({
    required String selectedMode,
    required ValueChanged<String> onSelected,
  }) {
    const modes = [
      {'name': 'UPI', 'icon': Icons.qr_code_scanner_rounded},
      {'name': 'Cash', 'icon': Icons.payments_rounded},
      {'name': 'Card', 'icon': Icons.credit_card_rounded},
    ];

    return Row(
      children: modes.map((m) {
        final name = m['name'] as String;
        final icon = m['icon'] as IconData;
        final isSelected = selectedMode == name;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelected(name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected ? primaryGold : const Color(0xFF08180F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? primaryGold : inputBorderColor,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: isSelected ? const Color(0xFF091911) : primaryGold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: isSelected
                            ? const Color(0xFF091911)
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // =========================================================================
  // SECTION: STUDIO ANNOUNCEMENTS & NOTICE BOARD
  // =========================================================================
  Widget _buildAnnouncementsSection() {
    final activeCount =
        _announcements.where((a) => a['is_active'] != false).length;
    final totalCount = _announcements.length;

    final filtered = _announcements.where((a) {
      final audience =
          (a['target_audience'] ?? 'ALL').toString().toUpperCase();
      final title = (a['title'] ?? '').toString().toLowerCase();
      final message = (a['message'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();

      final matchesQuery = title.contains(q) || message.contains(q);
      if (!matchesQuery) return false;

      if (_announcementFilter == 'ALL') return true;
      if (_announcementFilter == 'MEMBERS') {
        return audience == 'MEMBERS' || audience == 'ALL';
      }
      if (_announcementFilter == 'TRAINERS') {
        return audience == 'TRAINERS' || audience == 'ALL';
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick Stats Overview Cards
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: "TOTAL NOTICES",
                value: "$totalCount",
                icon: Icons.campaign_rounded,
                color: primaryGold,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                title: "ACTIVE BROADCASTS",
                value: "$activeCount",
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Section Title & Action
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "STUDIO BROADCASTS & NOTICES",
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: lightGold,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showCreateAnnouncementModal(),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGold,
                foregroundColor: const Color(0xFF091911),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(
                "POST NOTICE",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search Field
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF08180F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inputBorderColor, width: 1),
          ),
          child: TextField(
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: "Search notices by title or content...",
              hintStyle: GoogleFonts.rajdhani(
                color: Colors.white.withValues(alpha: 0.3),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: primaryGold,
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Audience Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildAnnouncementFilterChip('ALL', 'All Notices (${_announcements.length})'),
              const SizedBox(width: 8),
              _buildAnnouncementFilterChip('MEMBERS', 'Members Only'),
              const SizedBox(width: 8),
              _buildAnnouncementFilterChip('TRAINERS', 'Trainers Only'),
            ],
          ),
        ),

        const SizedBox(height: 18),

        _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: primaryGold),
                ),
              )
            : filtered.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: inputBorderColor),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          size: 48,
                          color: primaryGold.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "NO ANNOUNCEMENTS FOUND",
                          style: GoogleFonts.rajdhani(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Broadcast a notice to send updates directly to all Members and Trainers.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showCreateAnnouncementModal(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGold,
                            foregroundColor: const Color(0xFF091911),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text("CREATE FIRST ANNOUNCEMENT"),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: filtered.map((item) {
                      final id = item['id']?.toString() ?? '';
                      final title = item['title'] ?? 'Notice';
                      final message = item['message'] ?? '';
                      final audience = (item['target_audience'] ?? 'ALL')
                          .toString()
                          .toUpperCase();
                      final isActiveToggle = item['is_active'] != false;
                      final String? expStr = item['expires_at']?.toString();
                      final DateTime? expDate =
                          expStr != null ? DateTime.tryParse(expStr) : null;
                      final bool isExpired =
                          expDate != null && DateTime.now().isAfter(expDate);
                      final bool isLive = isActiveToggle && !isExpired;

                      String expiryLabel = '';
                      if (expDate != null) {
                        if (isExpired) {
                          expiryLabel = 'EXPIRED';
                        } else {
                          final diff = expDate.difference(DateTime.now());
                          if (diff.inDays > 0) {
                            expiryLabel =
                                'Expires in ${diff.inDays}d ${diff.inHours % 24}h';
                          } else if (diff.inHours > 0) {
                            expiryLabel =
                                'Expires in ${diff.inHours}h ${diff.inMinutes % 60}m';
                          } else {
                            expiryLabel = 'Expires in ${diff.inMinutes}m';
                          }
                        }
                      } else {
                        expiryLabel = 'PERMANENT';
                      }

                      final dateStr = _formatDateTimeFriendly(
                        item['created_at']?.toString(),
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: cardSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isLive
                                ? primaryGold.withValues(alpha: 0.4)
                                : Colors.white12,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Badges Row
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF08180F),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: primaryGold
                                                .withValues(alpha: 0.4),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              audience == 'ALL'
                                                  ? Icons.public_rounded
                                                  : (audience == 'MEMBERS'
                                                      ? Icons.people_rounded
                                                      : Icons.sports_mma_rounded),
                                              size: 11,
                                              color: primaryGold,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              audience == 'ALL'
                                                  ? 'TO: ALL'
                                                  : (audience == 'MEMBERS'
                                                      ? 'TO: MEMBERS'
                                                      : 'TO: TRAINERS'),
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.8,
                                                color: lightGold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isExpired
                                              ? Colors.redAccent.withValues(alpha: 0.15)
                                              : primaryGold.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isExpired
                                                ? Colors.redAccent.withValues(alpha: 0.5)
                                                : primaryGold.withValues(alpha: 0.35),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.timer_outlined,
                                              size: 11,
                                              color: isExpired
                                                  ? Colors.redAccent
                                                  : primaryGold,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              expiryLabel,
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                                color: isExpired
                                                    ? Colors.redAccent
                                                    : lightGold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    dateStr,
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // Announcement Title
                              Text(
                                title,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),

                              const SizedBox(height: 6),

                              // Message Body
                              Text(
                                message,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                  height: 1.4,
                                ),
                              ),

                              const SizedBox(height: 14),
                              Divider(
                                color: primaryGold.withValues(alpha: 0.15),
                                height: 1,
                              ),
                              const SizedBox(height: 10),

                              // Footer Row: Status Switch + Delete Action
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.campaign_rounded,
                                        size: 13,
                                        color: primaryGold,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "Official Studio Broadcast",
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      // Active Status Switch
                                      Row(
                                        children: [
                                          Text(
                                            isLive ? "LIVE" : (isExpired ? "EXPIRED" : "ARCHIVED"),
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w900,
                                              color: isLive
                                                  ? const Color(0xFF10B981)
                                                  : Colors.white38,
                                            ),
                                          ),
                                          Transform.scale(
                                            scale: 0.75,
                                            child: Switch(
                                              value: isActiveToggle,
                                              activeThumbColor: primaryGold,
                                              activeTrackColor: primaryGreen,
                                              onChanged: (val) async {
                                                await SupabaseService
                                                    .toggleAnnouncementStatus(
                                                  id,
                                                  val,
                                                );
                                                _loadAllData();
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      // Delete Button
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.redAccent,
                                          size: 19,
                                        ),
                                        tooltip: "Delete Notice",
                                        onPressed: () {
                                          _confirmDeleteAnnouncement(id, title);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _buildAnnouncementFilterChip(String key, String label) {
    final isSelected = _announcementFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _announcementFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primaryGold : const Color(0xFF08180F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? lightGold : primaryGold.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: isSelected ? const Color(0xFF091911) : Colors.white70,
          ),
        ),
      ),
    );
  }

  String _formatDateTimeFriendly(String? isoStr) {
    if (isoStr == null || isoStr.isEmpty) return 'Just now';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) {
        return diff.inMinutes <= 1 ? 'Just now' : '${diff.inMinutes}m ago';
      }
      if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      }
      if (diff.inDays < 7) {
        return '${diff.inDays}d ago';
      }
      return "${dt.day}/${dt.month}/${dt.year}";
    } catch (_) {
      return 'Recent';
    }
  }

  void _confirmDeleteAnnouncement(String id, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1F15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(
              "DELETE NOTICE?",
              style: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to delete '$title'? This announcement will be permanently removed for all users.",
          style: GoogleFonts.rajdhani(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "CANCEL",
              style: GoogleFonts.rajdhani(
                color: Colors.white60,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await SupabaseService.deleteAnnouncement(id);
              _loadAllData();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Announcement deleted successfully"),
                  backgroundColor: Color(0xFF8B1E1E),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1E1E),
            ),
            child: Text(
              "DELETE",
              style: GoogleFonts.rajdhani(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateAnnouncementModal() {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    String targetAudience = 'ALL';
    int durationHours = 36; // Default active duration: 36 hours
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
                top: 24,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF091D13),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: primaryGold, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: primaryGold.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: primaryGreen,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: primaryGold),
                                ),
                                child: const Icon(
                                  Icons.campaign_rounded,
                                  color: primaryGold,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "BROADCAST GYM NOTICE",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      color: lightGold,
                                    ),
                                  ),
                                  Text(
                                    "Instant announcement to Members & Trainers",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white60,
                            ),
                            onPressed: () => Navigator.pop(modalCtx),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Notice Title
                      Text(
                        "NOTICE TITLE",
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: primaryGold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: titleController,
                        style: GoogleFonts.rajdhani(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? "Title is required" : null,
                        decoration: InputDecoration(
                          hintText: "e.g., Diwali Holiday Schedule & Timings",
                          hintStyle: GoogleFonts.rajdhani(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF08180F),
                          prefixIcon: const Icon(
                            Icons.title_rounded,
                            color: primaryGold,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: inputBorderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: inputBorderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: primaryGold),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Notice Message
                      Text(
                        "ANNOUNCEMENT DETAILS & MESSAGE",
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: primaryGold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: messageController,
                        maxLines: 4,
                        style: GoogleFonts.rajdhani(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? "Message is required" : null,
                        decoration: InputDecoration(
                          hintText:
                              "Write the complete notice here. All athletes and coaches will see this immediately...",
                          hintStyle: GoogleFonts.rajdhani(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF08180F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: inputBorderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: inputBorderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: primaryGold),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Target Audience Selector
                      Text(
                        "TARGET AUDIENCE",
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: primaryGold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildAudienceChip(
                            label: "All (Gym-Wide)",
                            value: 'ALL',
                            current: targetAudience,
                            icon: Icons.public_rounded,
                            onTap: () => setModalState(() => targetAudience = 'ALL'),
                          ),
                          const SizedBox(width: 8),
                          _buildAudienceChip(
                            label: "Members Only",
                            value: 'MEMBERS',
                            current: targetAudience,
                            icon: Icons.people_rounded,
                            onTap: () => setModalState(() => targetAudience = 'MEMBERS'),
                          ),
                          const SizedBox(width: 8),
                          _buildAudienceChip(
                            label: "Trainers Only",
                            value: 'TRAINERS',
                            current: targetAudience,
                            icon: Icons.sports_mma_rounded,
                            onTap: () => setModalState(() => targetAudience = 'TRAINERS'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Notice Active Duration Selector
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "ACTIVE DURATION (AUTO-EXPIRES)",
                            style: GoogleFonts.rajdhani(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: primaryGold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: primaryGold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: primaryGold.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              durationHours == 0 ? "NO EXPIRY" : "$durationHours HOURS",
                              style: GoogleFonts.rajdhani(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: lightGold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildDurationChip(
                              label: "12 Hours",
                              hours: 12,
                              current: durationHours,
                              onTap: () => setModalState(() => durationHours = 12),
                            ),
                            const SizedBox(width: 8),
                            _buildDurationChip(
                              label: "24 Hours",
                              hours: 24,
                              current: durationHours,
                              onTap: () => setModalState(() => durationHours = 24),
                            ),
                            const SizedBox(width: 8),
                            _buildDurationChip(
                              label: "36 Hours (Default)",
                              hours: 36,
                              current: durationHours,
                              onTap: () => setModalState(() => durationHours = 36),
                            ),
                            const SizedBox(width: 8),
                            _buildDurationChip(
                              label: "48 Hours",
                              hours: 48,
                              current: durationHours,
                              onTap: () => setModalState(() => durationHours = 48),
                            ),
                            const SizedBox(width: 8),
                            _buildDurationChip(
                              label: "3 Days",
                              hours: 72,
                              current: durationHours,
                              onTap: () => setModalState(() => durationHours = 72),
                            ),
                            const SizedBox(width: 8),
                            _buildDurationChip(
                              label: "7 Days",
                              hours: 168,
                              current: durationHours,
                              onTap: () => setModalState(() => durationHours = 168),
                            ),
                            const SizedBox(width: 8),
                            _buildDurationChip(
                              label: "Permanent",
                              hours: 0,
                              current: durationHours,
                              onTap: () => setModalState(() => durationHours = 0),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            Navigator.pop(modalCtx);
                            setState(() => _isLoading = true);

                            final res = await SupabaseService.createAnnouncement(
                              title: titleController.text,
                              message: messageController.text,
                              targetAudience: targetAudience,
                              durationHours: durationHours,
                            );

                            await _loadAllData();

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  res['message'] ?? 'Notice broadcasted successfully!',
                                ),
                                backgroundColor: res['success'] == true
                                    ? primaryGreen
                                    : const Color(0xFF8B1E1E),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGold,
                            foregroundColor: const Color(0xFF091911),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                "BROADCAST NOTICE NOW",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDurationChip({
    required String label,
    required int hours,
    required int current,
    required VoidCallback onTap,
  }) {
    final isSelected = current == hours;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryGold : const Color(0xFF08180F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? lightGold : inputBorderColor,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: isSelected ? const Color(0xFF091911) : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildAudienceChip({
    required String label,
    required String value,
    required String current,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? primaryGold : const Color(0xFF08180F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? lightGold : inputBorderColor,
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? const Color(0xFF091911) : primaryGold,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? const Color(0xFF091911) : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
