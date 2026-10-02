import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/supabase_service.dart';
import 'services/session_service.dart';
import 'services/invoice_service.dart';
import 'widgets/profile_avatar.dart';
import 'auth_screen.dart';

class MemberScreen extends StatefulWidget {
  final Map<String, dynamic>? memberData;

  const MemberScreen({super.key, this.memberData});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  // Brand Color Palette
  static const Color primaryGold = Color(0xFFC9A227);
  static const Color primaryGreen = Color(0xFF123222);
  static const Color darkBackground = Color(0xFF091911);
  static const Color cardSurface = Color(0xFF0F261B);
  static const Color lightGold = Color(0xFFFFE082);
  static const Color inputBorderColor = Color(0xFF1E4230);

  Map<String, dynamic> _member = {};
  List<Map<String, dynamic>> _trainersList = [];
  List<Map<String, dynamic>> _memberReceipts = [];
  List<Map<String, dynamic>> _announcements = [];
  Set<String> _readNotificationIds = {};
  bool _isLoading = false;
  int _selectedDayIndex = DateTime.now().weekday - 1; // 0 = Mon, 6 = Sun
  final ScrollController _receiptsScrollController = ScrollController();
  final ScrollController _announcementsScrollController = ScrollController();

  List<Map<String, dynamic>> _dynamicMembershipPlans = [];
  List<Map<String, dynamic>> _dynamicPtPlans = [];

  List<String> get _membershipPlans {
    final plans = _dynamicMembershipPlans
        .where(
          (p) => p['is_active'] != false && (p['duration_months'] ?? 1) > 0,
        )
        .map((p) => (p['plan_name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (plans.isEmpty) {
      return ["Monthly", "3 Months", "6 Months", "Annual"];
    }
    return plans;
  }

  List<String> get _ptPlans {
    final plans = _dynamicPtPlans
        .where((p) => p['is_active'] != false)
        .map((p) => (p['plan_name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (plans.isEmpty) {
      return ["Monthly PT", "3 Months PT", "6 Months PT", "Annual PT"];
    }
    return plans;
  }

  final List<Map<String, dynamic>> _weeklySchedule = [
    {
      "day": "MON",
      "title": "DAY 1 • BACK",
      "focus": "Lats & Back Thickness",
      "protocol": "3 to 4 Sets • 20 × 15 × 12 Reps",
      "exercises": [
        "Chin-ups",
        "Lat Pulldown",
        "Barbell Row",
        "One-Arm Dumbbell Row",
        "Reverse Grip Lat Pulldown",
        "Seated Cable Row",
      ],
    },
    {
      "day": "TUE",
      "title": "DAY 2 • CHEST",
      "focus": "Pectoral Mass & Definition",
      "protocol": "3 to 4 Sets • 20 × 15 × 12 Reps",
      "exercises": [
        "Pec Deck Fly (Butterfly)",
        "Barbell Bench Press",
        "Incline Dumbbell Fly",
        "Machine Chest Press",
        "Butterfly",
        "Dumbbell Pullover",
      ],
    },
    {
      "day": "WED",
      "title": "DAY 3 • SHOULDER",
      "focus": "Deltoids & Traps Power",
      "protocol": "3 to 4 Sets • 20 × 15 × 12 Reps",
      "exercises": [
        "Shoulder Rotation (Warm-up)",
        "Dumbbell Shoulder Press",
        "Dumbbell Side Lateral Raise",
        "Barbell Shoulder Press",
        "Front Raise",
        "Upright Row",
        "Shrugs",
      ],
    },
    {
      "day": "THU",
      "title": "DAY 4 • BICEPS & TRICEPS",
      "focus": "Arm Hypertrophy & Peak",
      "protocol": "3 to 4 Sets • 20 × 15 × 12 Reps",
      "exercises": [
        "Alternate Dumbbell Curl",
        "Barbell Curl",
        "Preacher Curl",
        "Hammer Curl",
        "Lying Triceps Extension",
        "Standing Triceps Extension",
        "Bent-Over Triceps Extension",
        "Dumbbell Kickback",
        "Triceps Pushdown",
      ],
    },
    {
      "day": "FRI",
      "title": "DAY 5 • LEGS & CALVES",
      "focus": "Lower Body Power & Quads",
      "protocol": "3 to 4 Sets • 20 × 15 × 12 Reps",
      "exercises": [
        "Seated Leg Extension",
        "Machine Squats",
        "Lunges",
        "Leg Press",
        "Leg Hamstring Curl",
        "Calf Raise",
        "Wall Simbron Extension",
      ],
    },
    {
      "day": "SAT",
      "title": "DAY 6 • ABS & CORE",
      "focus": "Core Sculpt & Stability",
      "protocol": "3 to 4 Sets • 20 × 15 × 12 Reps",
      "exercises": [
        "Abs Crunches",
        "Hanging Leg Raise",
        "Abs Coaster Machine",
        "Plank (10 Mins Total)",
      ],
    },
    {
      "day": "SUN",
      "title": "DAY 7 • ACTIVE RECOVERY",
      "focus": "Restoration & Mobility",
      "protocol": "Mobility & Rest Protocol",
      "exercises": [
        "Full Body Dynamic Stretching",
        "Foam Rolling & Myofascial Release",
        "Hydration & Protein Synthesis",
        "Mental Re-focus for Monday Overload",
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.memberData != null && widget.memberData!.isNotEmpty) {
      _member = widget.memberData!;
    }
    _loadMemberProfile();
  }

  Future<void> _loadMemberProfile() async {
    // 1. Instantly load local session & cached data (0ms) so user sees cached screen immediately offline
    final savedMember = await SessionService.getSavedMember();
    if (savedMember != null && savedMember.isNotEmpty) {
      _member = savedMember;
    }

    final cachedTrainers = await SupabaseService.getCachedTrainers();
    final cachedPlans = await SupabaseService.getCachedMembershipPlans();
    final cachedPt = await SupabaseService.getCachedPtPlans();
    final cachedAnnouncements = await SupabaseService.getCachedAnnouncements(
      targetAudience: 'MEMBERS',
      onlyActive: true,
    );

    final memberId = _member['member_id']?.toString() ?? '';
    Set<String> localReadNotifs = {};
    List<Map<String, dynamic>> localReceipts = [];

    if (memberId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final readList = prefs.getStringList('ib_read_notifs_$memberId') ?? [];
        localReadNotifs = readList.toSet();
      } catch (_) {}
      localReceipts = await SupabaseService.fetchMemberTransactions(
          memberId,
          memberName: _member['full_name']?.toString(),
          memberUuid: _member['id']?.toString(),
          memberCreatedAt: DateTime.tryParse(_member['created_at']?.toString() ?? '') ??
              DateTime.tryParse(_member['membership_start_date']?.toString() ?? ''),
        );
    }

    if (mounted) {
      setState(() {
        _trainersList = cachedTrainers;
        _dynamicMembershipPlans = cachedPlans;
        _dynamicPtPlans = cachedPt;
        _announcements = cachedAnnouncements;
        _readNotificationIds = localReadNotifs;
        _memberReceipts = localReceipts;
        _isLoading = false;
      });
    }

    // 2. Fetch fresh data concurrently in the background if network is available
    try {
      final futures = <Future<dynamic>>[
        SupabaseService.fetchTrainers(),
        SupabaseService.fetchMembershipPlans(),
        SupabaseService.fetchPtPlans(),
        SupabaseService.fetchAnnouncements(
          targetAudience: 'MEMBERS',
          onlyActive: true,
        ),
      ];

      if (memberId.isNotEmpty) {
        futures.add(SupabaseService.fetchMembers());
        futures.add(SupabaseService.fetchMemberTransactions(
          memberId,
          memberName: _member['full_name']?.toString(),
          memberUuid: _member['id']?.toString(),
          memberCreatedAt: DateTime.tryParse(_member['created_at']?.toString() ?? '') ??
              DateTime.tryParse(_member['membership_start_date']?.toString() ?? ''),
        ));
      }

      final results = await Future.wait(futures);

      if (mounted) {
        setState(() {
          _trainersList = results[0] as List<Map<String, dynamic>>;
          _dynamicMembershipPlans = results[1] as List<Map<String, dynamic>>;
          _dynamicPtPlans = results[2] as List<Map<String, dynamic>>;
          _announcements = results[3] as List<Map<String, dynamic>>;

          if (memberId.isNotEmpty && results.length >= 6) {
            final membersList = results[4] as List<Map<String, dynamic>>;
            final match = membersList.firstWhere(
              (m) =>
                  (m['member_id'] ?? '').toString().toLowerCase() ==
                  memberId.toLowerCase(),
              orElse: () => _member,
            );
            _member = match;
            _memberReceipts = results[5] as List<Map<String, dynamic>>;
          }
          _isLoading = false;
        });

        if (memberId.isNotEmpty) {
          await SessionService.saveMemberSession(_member);
        }
      }
    } catch (e) {
      debugPrint("Member background fetch error: $e");
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return "N/A";
    DateTime? dt;
    if (date is DateTime) {
      dt = date;
    } else if (date is String) {
      dt = DateTime.tryParse(date);
    }
    if (dt == null) return date.toString();

    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}";
  }

  void _showRenewMembershipModal() {
    String selectedRenewalPlan = _member['plan']?.toString() ?? "Monthly";
    if (!_membershipPlans.contains(selectedRenewalPlan)) {
      selectedRenewalPlan = _membershipPlans.first;
    }
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1F15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: primaryGold.withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryGreen,
                      border: Border.all(color: primaryGold, width: 1),
                    ),
                    child: const Icon(
                      Icons.published_with_changes_rounded,
                      color: primaryGold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "RENEW MEMBERSHIP PLAN",
                        style: GoogleFonts.rajdhani(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.8,
                          color: lightGold,
                        ),
                      ),
                      Text(
                        "Extend your IronBlood gym access uninterrupted",
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "CHOOSE RENEWAL PLAN",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: primaryGold,
                ),
              ),
              const SizedBox(height: 8),
              ..._membershipPlans.map((plan) {
                final isSelected = selectedRenewalPlan == plan;
                final planObj = _dynamicMembershipPlans.firstWhere(
                  (p) =>
                      (p['plan_name'] ?? '').toString().toLowerCase().trim() ==
                          plan.toLowerCase().trim() ||
                      (p['plan_name'] ?? '').toString().toLowerCase().contains(
                        plan.toLowerCase(),
                      ),
                  orElse: () => <String, dynamic>{},
                );
                final priceText = planObj.isNotEmpty && planObj['price'] != null
                    ? "₹${(planObj['price'] is num ? (planObj['price'] as num).toInt() : planObj['price'])} • "
                    : "";

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () =>
                        setModalState(() => selectedRenewalPlan = plan),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? primaryGreen
                            : const Color(0xFF08180F),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? primaryGold : inputBorderColor,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: isSelected
                                    ? primaryGold
                                    : Colors.white38,
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                plan,
                                style: GoogleFonts.rajdhani(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? lightGold : Colors.white,
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
                              color: const Color(0xFF08180F),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: primaryGold.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              "$priceText+${SupabaseService.planToMonths(plan)} Months",
                              style: GoogleFonts.rajdhani(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: primaryGold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 18),
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
                    onTap: isSubmitting
                        ? null
                        : () async {
                            setModalState(() => isSubmitting = true);
                            final memberId =
                                _member['member_id']?.toString() ?? '';
                            final res =
                                await SupabaseService.requestMembershipRenewal(
                                  memberId: memberId,
                                  plan: selectedRenewalPlan,
                                );
                            setModalState(() => isSubmitting = false);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            _loadMemberProfile();

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: primaryGreen,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: primaryGold,
                                    width: 1.2,
                                  ),
                                ),
                                content: Text(
                                  res['message'] ??
                                      "Renewal request sent successfully!",
                                  style: GoogleFonts.rajdhani(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          },
                    child: Center(
                      child: isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Color(0xFF091911),
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              "SUBMIT RENEWAL REQUEST",
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
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showPersonalTrainingModal() {
    String selectedPtPlan = "Monthly PT";
    String selectedTrainer = _trainersList.isNotEmpty
        ? (_trainersList.first['full_name']?.toString() ?? "Marcus Stone")
        : "Marcus Stone";
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1F15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: primaryGold.withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryGreen,
                      border: Border.all(color: primaryGold, width: 1),
                    ),
                    child: const Icon(
                      Icons.sports_mma_rounded,
                      color: primaryGold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "PERSONAL TRAINING (PT) ENROLLMENT",
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: lightGold,
                        ),
                      ),
                      Text(
                        "1-on-1 coaching, nutrition & tailored routines",
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "SELECT PT PLAN",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
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
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: inputBorderColor, width: 1.2),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedPtPlan,
                    isExpanded: true,
                    dropdownColor: cardSurface,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: primaryGold,
                    ),
                    items: _ptPlans.map((plan) {
                      final ptObj = _dynamicPtPlans.firstWhere(
                        (p) =>
                            (p['plan_name'] ?? '')
                                .toString()
                                .toLowerCase()
                                .trim() ==
                            plan.toLowerCase().trim(),
                        orElse: () => <String, dynamic>{},
                      );
                      final priceLabel =
                          ptObj.isNotEmpty && ptObj['price'] != null
                          ? " (₹${ptObj['price'] is num ? (ptObj['price'] as num).toInt() : ptObj['price']})"
                          : "";

                      return DropdownMenuItem(
                        value: plan,
                        child: Text(
                          "$plan$priceLabel",
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedPtPlan = val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "SELECT PREFERRED COACH",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
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
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: inputBorderColor, width: 1.2),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value:
                        _trainersList.any(
                          (t) => t['full_name'] == selectedTrainer,
                        )
                        ? selectedTrainer
                        : (_trainersList.isNotEmpty
                              ? _trainersList.first['full_name']
                              : null),
                    isExpanded: true,
                    dropdownColor: cardSurface,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: primaryGold,
                    ),
                    items: _trainersList.isNotEmpty
                        ? _trainersList.map((t) {
                            return DropdownMenuItem<String>(
                              value: t['full_name'] as String,
                              child: Text(
                                "${t['full_name']} (${t['experience'] ?? 'Pro Coach'})",
                                style: GoogleFonts.rajdhani(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }).toList()
                        : [
                            const DropdownMenuItem(
                              value: "Marcus Stone",
                              child: Text(
                                "Head Coach Marcus Stone",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedTrainer = val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 22),
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
                    onTap: isSubmitting
                        ? null
                        : () async {
                            setModalState(() => isSubmitting = true);
                            final memberId =
                                _member['member_id']?.toString() ?? '';
                            final res =
                                await SupabaseService.requestPersonalTraining(
                                  memberId: memberId,
                                  ptPlan: selectedPtPlan,
                                  trainerName: selectedTrainer,
                                );
                            setModalState(() => isSubmitting = false);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            _loadMemberProfile();

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: primaryGreen,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: primaryGold,
                                    width: 1.2,
                                  ),
                                ),
                                content: Text(
                                  res['message'] ??
                                      "PT request submitted successfully!",
                                  style: GoogleFonts.rajdhani(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          },
                    child: Center(
                      child: isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Color(0xFF091911),
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              "CONFIRM PT ENROLLMENT REQUEST",
                              style: GoogleFonts.rajdhani(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
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
    );
  }

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
          "Are you sure you want to log out from IronBlood Studio, ${_member['full_name'] ?? 'Athlete'}?",
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
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white70,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await SessionService.clearSession();
              if (!context.mounted) return;
              Navigator.pop(context);
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
            ),
            child: Text(
              "LOG OUT",
              style: GoogleFonts.rajdhani(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // NOTIFICATION SYSTEM ENGINE & PERSISTENCE
  // =========================================================================
  Future<void> _markNotificationAsRead(String id) async {
    _readNotificationIds.add(id);
    final memberId = _member['member_id']?.toString() ?? '';
    if (memberId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
          'ib_read_notifs_$memberId',
          _readNotificationIds.toList(),
        );
      } catch (e) {
        debugPrint("Error saving read notification: $e");
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _markAllNotificationsAsRead(List<String> ids) async {
    _readNotificationIds.addAll(ids);
    final memberId = _member['member_id']?.toString() ?? '';
    if (memberId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
          'ib_read_notifs_$memberId',
          _readNotificationIds.toList(),
        );
      } catch (e) {
        debugPrint("Error saving all read notifications: $e");
      }
    }
    if (mounted) setState(() {});
  }

  List<_MemberNotificationItem> _getNotificationsList() {
    final List<_MemberNotificationItem> list = [];

    final membershipStartDate = _member['membership_start_date'];
    final membershipExpiryDate = _member['membership_expiry_date'];
    final daysLeft = SupabaseService.daysRemaining(membershipExpiryDate);
    final plan = _member['plan']?.toString() ?? 'Membership Plan';
    final renewalStatus = _member['renewal_status']?.toString() ?? 'Active';

    final hasPt = _member['has_pt'] == true;
    final ptPlan = _member['pt_plan']?.toString() ?? 'Personal Training';
    final ptTrainer =
        _member['pt_trainer']?.toString() ??
        _member['assigned_trainer']?.toString() ??
        'Head Coach';
    final ptStartDate = _member['pt_start_date'];
    final ptExpiryDate = _member['pt_expiry_date'];
    final ptDaysLeft = SupabaseService.daysRemaining(ptExpiryDate);
    final ptStatus = _member['pt_status']?.toString() ?? 'None';

    // 1. MEMBERSHIP EXPIRY NOTIFICATIONS (Expired, Today, 1d, 3d, 7d, 15d)
    if (membershipExpiryDate != null) {
      if (daysLeft < 0) {
        list.add(_MemberNotificationItem(
          id: 'mem_expired_$membershipExpiryDate',
          title: "Membership Pass Expired",
          message:
              "Your $plan membership expired ${-daysLeft} day${-daysLeft == 1 ? '' : 's'} ago on ${_formatDate(membershipExpiryDate)}. Renew now to restore uninterrupted gym access.",
          category: 'EXPIRY',
          priority: 'URGENT',
          timestamp:
              DateTime.tryParse(membershipExpiryDate.toString()) ??
              DateTime.now(),
          icon: Icons.error_outline_rounded,
          iconColor: Colors.redAccent,
          badgeText: "EXPIRED",
          actionLabel: "RENEW MEMBERSHIP",
          onTap: _showRenewMembershipModal,
        ));
      } else if (daysLeft == 0) {
        list.add(_MemberNotificationItem(
          id: 'mem_expire_0d_$membershipExpiryDate',
          title: "Membership Expires Today!",
          message:
              "Today is the final day of your $plan membership. Tap below to submit your renewal request immediately.",
          category: 'EXPIRY',
          priority: 'URGENT',
          timestamp: DateTime.now(),
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.redAccent,
          badgeText: "EXPIRES TODAY",
          actionLabel: "RENEW TODAY",
          onTap: _showRenewMembershipModal,
        ));
      } else if (daysLeft == 1) {
        list.add(_MemberNotificationItem(
          id: 'mem_expire_1d_$membershipExpiryDate',
          title: "1 Day Remaining — Membership Expiring Tomorrow!",
          message:
              "Action required: Your $plan membership expires tomorrow on ${_formatDate(membershipExpiryDate)}. Renew today to keep your access active.",
          category: 'EXPIRY',
          priority: 'URGENT',
          timestamp: DateTime.now(),
          icon: Icons.notification_important_rounded,
          iconColor: Colors.redAccent,
          badgeText: "1 DAY LEFT",
          actionLabel: "RENEW PASS",
          onTap: _showRenewMembershipModal,
        ));
      } else if (daysLeft <= 3) {
        list.add(_MemberNotificationItem(
          id: 'mem_expire_3d_$membershipExpiryDate',
          title: "3 Days Remaining — Renewal Alert",
          message:
              "Your $plan pass expires in $daysLeft days on ${_formatDate(membershipExpiryDate)}. Keep your gym streak going by renewing now.",
          category: 'EXPIRY',
          priority: 'WARNING',
          timestamp: DateTime.now(),
          icon: Icons.alarm_on_rounded,
          iconColor: Colors.orangeAccent,
          badgeText: "$daysLeft DAYS LEFT",
          actionLabel: "RENEW PLAN",
          onTap: _showRenewMembershipModal,
        ));
      } else if (daysLeft <= 7) {
        list.add(_MemberNotificationItem(
          id: 'mem_expire_7d_$membershipExpiryDate',
          title: "7 Days Remaining — Renewal Reminder",
          message:
              "Your $plan membership expires in $daysLeft days on ${_formatDate(membershipExpiryDate)}. Early renewal is available anytime.",
          category: 'EXPIRY',
          priority: 'WARNING',
          timestamp: DateTime.now(),
          icon: Icons.calendar_month_rounded,
          iconColor: primaryGold,
          badgeText: "$daysLeft DAYS LEFT",
          actionLabel: "RENEW PASS",
          onTap: _showRenewMembershipModal,
        ));
      } else if (daysLeft <= 15) {
        list.add(_MemberNotificationItem(
          id: 'mem_expire_15d_$membershipExpiryDate',
          title: "15 Days Remaining — Upcoming Expiry Notice",
          message:
              "Your $plan membership expires in $daysLeft days on ${_formatDate(membershipExpiryDate)}. Plan your renewal ahead.",
          category: 'EXPIRY',
          priority: 'INFO',
          timestamp: DateTime.now(),
          icon: Icons.info_outline_rounded,
          iconColor: lightGold,
          badgeText: "$daysLeft DAYS LEFT",
          actionLabel: "VIEW RENEWAL",
          onTap: _showRenewMembershipModal,
        ));
      }
    }

    // 2. MEMBERSHIP RENEWALS & ACTIVE PASS STATUS
    final isPendingRenewal =
        renewalStatus == 'Pending Approval' ||
        renewalStatus == 'Pending Renewal' ||
        renewalStatus == 'Requested';
    if (isPendingRenewal) {
      list.add(_MemberNotificationItem(
        id: 'mem_renewal_pending_${_member['member_id']}',
        title: "Renewal Request Pending Approval",
        message:
            "Your renewal request for $plan is currently being verified by Gym Administration.",
        category: 'RENEWAL',
        priority: 'WARNING',
        timestamp: DateTime.now(),
        icon: Icons.pending_actions_rounded,
        iconColor: Colors.amberAccent,
        badgeText: "PENDING APPROVAL",
      ));
    } else if (daysLeft > 15 && membershipStartDate != null) {
      list.add(_MemberNotificationItem(
        id: 'mem_active_$membershipStartDate',
        title: "Membership Active — $plan Plan",
        message:
            "Your membership pass is active in good standing through ${_formatDate(membershipExpiryDate)}.",
        category: 'RENEWAL',
        priority: 'SUCCESS',
        timestamp:
            DateTime.tryParse(membershipStartDate.toString()) ??
            DateTime.now(),
        icon: Icons.verified_rounded,
        iconColor: const Color(0xFF10B981),
        badgeText: "ACTIVE PASS",
      ));
    }

    // 3. PERSONAL TRAINING (PT) EXPIRATION & RENEWAL NOTIFICATIONS
    if (hasPt && ptExpiryDate != null) {
      if (ptDaysLeft < 0) {
        list.add(_MemberNotificationItem(
          id: 'pt_expired_$ptExpiryDate',
          title: "Personal Training (PT) Expired",
          message:
              "Your 1-on-1 PT coaching package with Coach $ptTrainer expired on ${_formatDate(ptExpiryDate)}. Renew your sessions to resume personal training.",
          category: 'PT',
          priority: 'URGENT',
          timestamp:
              DateTime.tryParse(ptExpiryDate.toString()) ?? DateTime.now(),
          icon: Icons.sports_gymnastics_rounded,
          iconColor: Colors.redAccent,
          badgeText: "PT EXPIRED",
          actionLabel: "RENEW PT",
          onTap: _showPersonalTrainingModal,
        ));
      } else if (ptDaysLeft == 0) {
        list.add(_MemberNotificationItem(
          id: 'pt_expire_0d_$ptExpiryDate',
          title: "PT Sessions Expire Today!",
          message:
              "Today is the final day of your PT package with Coach $ptTrainer. Book renewal sessions to keep training.",
          category: 'PT',
          priority: 'URGENT',
          timestamp: DateTime.now(),
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.redAccent,
          badgeText: "PT TODAY",
          actionLabel: "EXTEND PT",
          onTap: _showPersonalTrainingModal,
        ));
      } else if (ptDaysLeft == 1) {
        list.add(_MemberNotificationItem(
          id: 'pt_expire_1d_$ptExpiryDate',
          title: "1 Day Remaining — PT Package Expiring!",
          message:
              "Your PT coaching sessions with Coach $ptTrainer end tomorrow on ${_formatDate(ptExpiryDate)}. Extend your sessions now.",
          category: 'PT',
          priority: 'URGENT',
          timestamp: DateTime.now(),
          icon: Icons.notification_important_rounded,
          iconColor: Colors.redAccent,
          badgeText: "1 DAY LEFT",
          actionLabel: "EXTEND PT",
          onTap: _showPersonalTrainingModal,
        ));
      } else if (ptDaysLeft <= 3) {
        list.add(_MemberNotificationItem(
          id: 'pt_expire_3d_$ptExpiryDate',
          title: "3 Days Remaining — PT Package Expiry Alert",
          message:
              "Only $ptDaysLeft days remaining on your PT package with Coach $ptTrainer (${_formatDate(ptExpiryDate)}).",
          category: 'PT',
          priority: 'WARNING',
          timestamp: DateTime.now(),
          icon: Icons.timer_outlined,
          iconColor: Colors.orangeAccent,
          badgeText: "$ptDaysLeft DAYS LEFT",
          actionLabel: "EXTEND PT",
          onTap: _showPersonalTrainingModal,
        ));
      } else if (ptDaysLeft <= 7) {
        list.add(_MemberNotificationItem(
          id: 'pt_expire_7d_$ptExpiryDate',
          title: "7 Days Remaining — PT Renewal Reminder",
          message:
              "Your PT package with Coach $ptTrainer expires in $ptDaysLeft days on ${_formatDate(ptExpiryDate)}.",
          category: 'PT',
          priority: 'WARNING',
          timestamp: DateTime.now(),
          icon: Icons.fitness_center_rounded,
          iconColor: primaryGold,
          badgeText: "$ptDaysLeft DAYS LEFT",
          actionLabel: "RENEW PT",
          onTap: _showPersonalTrainingModal,
        ));
      } else if (ptDaysLeft <= 15) {
        list.add(_MemberNotificationItem(
          id: 'pt_expire_15d_$ptExpiryDate',
          title: "15 Days Remaining — PT Package Expiry Notice",
          message:
              "Your PT package with Coach $ptTrainer expires in $ptDaysLeft days on ${_formatDate(ptExpiryDate)}.",
          category: 'PT',
          priority: 'INFO',
          timestamp: DateTime.now(),
          icon: Icons.fitness_center_rounded,
          iconColor: lightGold,
          badgeText: "$ptDaysLeft DAYS LEFT",
          actionLabel: "VIEW PT",
          onTap: _showPersonalTrainingModal,
        ));
      } else {
        list.add(_MemberNotificationItem(
          id: 'pt_active_${ptStartDate ?? 'curr'}',
          title: "Active PT Coaching — Coach $ptTrainer",
          message:
              "Your $ptPlan coaching with Coach $ptTrainer is active through ${_formatDate(ptExpiryDate)}.",
          category: 'PT',
          priority: 'SUCCESS',
          timestamp:
              DateTime.tryParse(ptStartDate?.toString() ?? '') ??
              DateTime.now(),
          icon: Icons.fitness_center_rounded,
          iconColor: const Color(0xFF10B981),
          badgeText: "PT ACTIVE",
        ));
      }
    }

    // PT Request Pending
    final isPtPending =
        ptStatus == 'Requested' ||
        ptStatus == 'PT Requested' ||
        ptStatus == 'Pending Approval';
    if (isPtPending) {
      list.add(_MemberNotificationItem(
        id: 'pt_pending_${_member['member_id']}',
        title: "PT Coaching Request Submitted",
        message:
            "Your enrollment request for $ptPlan with Coach $ptTrainer is under review by Gym Admin.",
        category: 'PT',
        priority: 'WARNING',
        timestamp: DateTime.now(),
        icon: Icons.pending_actions_rounded,
        iconColor: Colors.amberAccent,
        badgeText: "PT REQUESTED",
      ));
    }

    // 4. ANNOUNCEMENTS & STUDIO BROADCASTS
    for (final ann in _announcements) {
      final title = ann['title']?.toString().trim() ?? 'Studio Notice';
      final message = ann['message']?.toString().trim() ?? '';
      final createdIso = ann['created_at'];
      final dt =
          DateTime.tryParse(createdIso?.toString() ?? '') ?? DateTime.now();

      list.add(_MemberNotificationItem(
        id: 'announcement_${ann['id'] ?? title}_${createdIso ?? ''}',
        title: title,
        message: message,
        category: 'ANNOUNCEMENT',
        priority: 'INFO',
        timestamp: dt,
        icon: Icons.campaign_rounded,
        iconColor: primaryGold,
        badgeText: "STUDIO NOTICE",
      ));
    }

    // 5. INVOICES & VERIFIED RECEIPTS
    final synthesizedReceipts = _getSynthesizedReceiptsList();
    for (final tx in synthesizedReceipts) {
      final invoice = _buildInvoiceFromTx(tx);
      final isPt = invoice.category.contains('PERSONAL');
      final amount = invoice.finalAmount;

      list.add(_MemberNotificationItem(
        id: 'invoice_${invoice.invoiceNo}',
        title: isPt
            ? "PT Invoice #${invoice.invoiceNo}"
            : "Membership Invoice #${invoice.invoiceNo}",
        message:
            "Official receipt generated for ₹${amount.toInt()} (${invoice.planName}) via ${invoice.paymentMode.toUpperCase()}.",
        category: 'INVOICE',
        priority: 'SUCCESS',
        timestamp: invoice.invoiceDate,
        icon: Icons.receipt_long_rounded,
        iconColor: const Color(0xFF10B981),
        badgeText: "TAX INVOICE",
        actionLabel: "VIEW RECEIPT",
        onTap: () {
          InvoiceService.showReceiptDialog(
            context: context,
            invoice: invoice,
          );
        },
      ));
    }

    // Sort: Unread first, then by priority (URGENT > WARNING > SUCCESS > INFO), then timestamp descending
    list.sort((a, b) {
      final aRead = _readNotificationIds.contains(a.id);
      final bRead = _readNotificationIds.contains(b.id);
      if (aRead != bRead) {
        return aRead ? 1 : -1; // Unread first
      }

      int score(String p) {
        switch (p) {
          case 'URGENT':
            return 4;
          case 'WARNING':
            return 3;
          case 'SUCCESS':
            return 2;
          default:
            return 1;
        }
      }

      final scoreDiff = score(b.priority).compareTo(score(a.priority));
      if (scoreDiff != 0) return scoreDiff;

      return b.timestamp.compareTo(a.timestamp);
    });

    return list;
  }

  Widget _buildNotificationBellButton() {
    final notifications = _getNotificationsList();
    final unreadCount = notifications
        .where((n) => !_readNotificationIds.contains(n.id))
        .length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            unreadCount > 0
                ? Icons.notifications_active_rounded
                : Icons.notifications_outlined,
            color: unreadCount > 0 ? lightGold : primaryGold,
            size: 22,
          ),
          tooltip:
              "Notifications ${unreadCount > 0 ? '($unreadCount new)' : ''}",
          onPressed: _showNotificationsModal,
        ),
        if (unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF0B1F15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.6),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                unreadCount > 99 ? "99+" : "$unreadCount",
                style: GoogleFonts.rajdhani(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  void _showNotificationsModal() {
    String selectedFilter = 'ALL';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final allNotifications = _getNotificationsList();
          final unreadCount = allNotifications
              .where((n) => !_readNotificationIds.contains(n.id))
              .length;

          List<_MemberNotificationItem> filteredList;
          if (selectedFilter == 'ALERTS') {
            filteredList = allNotifications
                .where(
                  (n) =>
                      n.category == 'EXPIRY' ||
                      n.category == 'RENEWAL' ||
                      n.category == 'PT',
                )
                .toList();
          } else if (selectedFilter == 'NOTICES') {
            filteredList = allNotifications
                .where((n) => n.category == 'ANNOUNCEMENT')
                .toList();
          } else if (selectedFilter == 'INVOICES') {
            filteredList = allNotifications
                .where((n) => n.category == 'INVOICE')
                .toList();
          } else {
            filteredList = allNotifications;
          }

          final alertCount = allNotifications
              .where(
                (n) =>
                    n.category == 'EXPIRY' ||
                    n.category == 'RENEWAL' ||
                    n.category == 'PT',
              )
              .length;
          final noticeCount = allNotifications
              .where((n) => n.category == 'ANNOUNCEMENT')
              .length;
          final invoiceCount = allNotifications
              .where((n) => n.category == 'INVOICE')
              .length;

          return DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.45,
            maxChildSize: 0.94,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: const Color(0xFF091911),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: primaryGold.withValues(alpha: 0.45),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Top Drag Handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: primaryGold.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),

                  // Header Row
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: primaryGreen,
                                  border: Border.all(
                                    color: primaryGold,
                                    width: 1.2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.notifications_active_rounded,
                                  color: primaryGold,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            "NOTIFICATIONS & ALERTS",
                                            style: GoogleFonts.rajdhani(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.2,
                                              color: lightGold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (unreadCount > 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDC2626),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              "$unreadCount NEW",
                                              style: GoogleFonts.rajdhani(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      "Membership, PT renewals, alerts & notices",
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
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              await _markAllNotificationsAsRead(
                                allNotifications.map((n) => n.id).toList(),
                              );
                              setModalState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: primaryGold.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: primaryGold.withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.done_all_rounded,
                                    size: 13,
                                    color: primaryGold,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Mark read",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: lightGold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Filter Chips Row
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip(
                            label: "ALL (${allNotifications.length})",
                            isSelected: selectedFilter == 'ALL',
                            onTap: () =>
                                setModalState(() => selectedFilter = 'ALL'),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: "ALERTS & PASS ($alertCount)",
                            isSelected: selectedFilter == 'ALERTS',
                            onTap: () =>
                                setModalState(() => selectedFilter = 'ALERTS'),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: "NOTICES ($noticeCount)",
                            isSelected: selectedFilter == 'NOTICES',
                            onTap: () =>
                                setModalState(() => selectedFilter = 'NOTICES'),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: "RECEIPTS ($invoiceCount)",
                            isSelected: selectedFilter == 'INVOICES',
                            onTap: () => setModalState(
                              () => selectedFilter = 'INVOICES',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(color: Color(0xFF1E4230), height: 14),

                  // Notifications List
                  Expanded(
                    child: filteredList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: 44,
                                  color: primaryGold.withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "ALL CAUGHT UP!",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                    color: lightGold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "No notifications found in this filter category.",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            itemCount: filteredList.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = filteredList[index];
                              final isUnread =
                                  !_readNotificationIds.contains(item.id);

                              return _buildNotificationCardItem(
                                item: item,
                                isUnread: isUnread,
                                onDismiss: () async {
                                  await _markNotificationAsRead(item.id);
                                  setModalState(() {});
                                },
                                onTapAction: () async {
                                  await _markNotificationAsRead(item.id);
                                  setModalState(() {});
                                  if (context.mounted && item.onTap != null) {
                                    Navigator.pop(context);
                                    item.onTap!();
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primaryGold : const Color(0xFF0F261B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? primaryGold
                : primaryGold.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: isSelected ? const Color(0xFF091911) : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCardItem({
    required _MemberNotificationItem item,
    required bool isUnread,
    required VoidCallback onDismiss,
    required VoidCallback onTapAction,
  }) {
    final timeStr = _formatFriendlyTime(item.timestamp.toIso8601String());

    Color cardBorderColor;
    if (isUnread) {
      if (item.priority == 'URGENT') {
        cardBorderColor = Colors.redAccent.withValues(alpha: 0.8);
      } else if (item.priority == 'WARNING') {
        cardBorderColor = Colors.orangeAccent.withValues(alpha: 0.8);
      } else {
        cardBorderColor = primaryGold.withValues(alpha: 0.7);
      }
    } else {
      cardBorderColor = const Color(0xFF1E4230);
    }

    return Container(
      decoration: BoxDecoration(
        color: isUnread
            ? const Color(0xFF0F2B1D)
            : const Color(0xFF0B1F15).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cardBorderColor,
          width: isUnread ? 1.3 : 1.0,
        ),
        boxShadow: isUnread
            ? [
                BoxShadow(
                  color: primaryGold.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTapAction,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Circle
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.iconColor.withValues(alpha: 0.15),
                    border: Border.all(
                      color: item.iconColor.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 18),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge & Time Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: item.iconColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color:
                                        item.iconColor.withValues(alpha: 0.6),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  item.badgeText,
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    color: item.iconColor,
                                  ),
                                ),
                              ),
                              if (isUnread) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: primaryGold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            timeStr,
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Title
                      Text(
                        item.title,
                        style: GoogleFonts.rajdhani(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: isUnread ? Colors.white : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 3),

                      // Message
                      Text(
                        item.message,
                        style: GoogleFonts.rajdhani(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white60,
                          height: 1.35,
                        ),
                      ),

                      // Action Button if present
                      if (item.actionLabel != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: primaryGold,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.actionLabel!,
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                      color: const Color(0xFF091911),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 12,
                                    color: Color(0xFF091911),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = _member['full_name'] ?? 'IronBlood Athlete';
    final memberId = _member['member_id'] ?? 'MB-001';
    final plan = _member['plan'] ?? 'Monthly';
    final trainer =
        _member['pt_trainer'] ??
        _member['assigned_trainer'] ??
        'Unassigned (General)';
    final phone = _member['phone'] ?? 'N/A';
    final currentDaySchedule = _weeklySchedule[_selectedDayIndex];

    final membershipStartDate = _member['membership_start_date'];
    final membershipExpiryDate = _member['membership_expiry_date'];
    final daysLeft = SupabaseService.daysRemaining(membershipExpiryDate);
    final hasPt = _member['has_pt'] == true;
    final ptPlan = _member['pt_plan'] ?? 'None';
    final ptTrainer = _member['pt_trainer'] ?? trainer;
    final ptStartDate = _member['pt_start_date'];
    final ptExpiryDate = _member['pt_expiry_date'];
    final ptDaysLeft = SupabaseService.daysRemaining(ptExpiryDate);
    final renewalStatus = _member['renewal_status'] ?? 'Active';
    final ptStatus = _member['pt_status'] ?? 'None';

    return Scaffold(
      backgroundColor: darkBackground,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1F15),
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: primaryGold, width: 1.2),
              ),
              child: Image.asset(
                'lib/logo.png',
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.fitness_center_rounded, color: primaryGold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [lightGold, primaryGold, lightGold],
                        ).createShader(bounds),
                        child: Text(
                          "MEMBER PASS",
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: daysLeft > 0
                              ? Colors.green.shade900.withValues(alpha: 0.6)
                              : Colors.red.shade900.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: daysLeft > 0
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          daysLeft > 0 ? "ACTIVE" : "EXPIRED",
                          style: GoogleFonts.rajdhani(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: daysLeft > 0
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    "IRONBLOOD MUSCLE AND FITNESS STUDIO",
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: const Color(0xFFE8D7A3),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: primaryGold),
            tooltip: "Refresh Pass",
            onPressed: _loadMemberProfile,
          ),
          _buildNotificationBellButton(),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: "Log Out",
            onPressed: _handleLogout,
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: primaryGold.withValues(alpha: 0.3),
            height: 1,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Ambient Radial Background
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
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryGold),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. DIGITAL MEMBERSHIP VIP PASS CARD
                        _buildDigitalMembershipPass(
                          fullName: fullName,
                          memberId: memberId,
                          plan: plan,
                          phone: phone,
                          trainer: trainer,
                          expiryDate: membershipExpiryDate,
                          daysLeft: daysLeft,
                          hasPt: hasPt,
                        ),

                        const SizedBox(height: 20),

                        // STUDIO NOTICE BOARD & ANNOUNCEMENTS BANNER
                        if (_announcements.isNotEmpty) ...[
                          _buildAnnouncementsSection(),
                          const SizedBox(height: 20),
                        ],

                        // 2. MEMBERSHIP PERIOD & RENEWAL CARD
                        _buildMembershipPeriodCard(
                          plan: plan,
                          startDate: membershipStartDate,
                          expiryDate: membershipExpiryDate,
                          daysLeft: daysLeft,
                          renewalStatus: renewalStatus,
                        ),

                        const SizedBox(height: 20),

                        // 3. PERSONAL TRAINING (PT) SESSION SPOTLIGHT CARD
                        _buildPersonalTrainingCard(
                          hasPt: hasPt,
                          ptPlan: ptPlan,
                          ptTrainer: ptTrainer,
                          ptStartDate: ptStartDate,
                          ptExpiryDate: ptExpiryDate,
                          ptDaysLeft: ptDaysLeft,
                          ptStatus: ptStatus,
                        ),

                        const SizedBox(height: 20),

                        // 4. MY RECEIPTS & INVOICES (IN-APP MEMBER BILLING PORTAL)
                        _buildPaymentReceiptsSection(),

                        const SizedBox(height: 24),

                        // 5. WEEKLY WORKOUT SCHEDULE SPLIT
                        Text(
                          "TRAINING SPLIT & WORKOUTS",
                          style: GoogleFonts.rajdhani(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: lightGold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Day Selector Pills
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: List.generate(_weeklySchedule.length, (
                              index,
                            ) {
                              final isSelected = _selectedDayIndex == index;
                              final dayItem = _weeklySchedule[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedDayIndex = index),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? primaryGold
                                          : const Color(0xFF08180F),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? lightGold
                                            : primaryGold.withValues(
                                                alpha: 0.25,
                                              ),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Text(
                                      dayItem['day'],
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                        color: isSelected
                                            ? const Color(0xFF091911)
                                            : Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Selected Day's Workout Details
                        _buildWorkoutDetailCard(currentDaySchedule),

                        const SizedBox(height: 24),

                        // 6. GYM ACCESS TIMINGS & GUIDELINES
                        _buildStudioInfoCard(),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDigitalMembershipPass({
    required String fullName,
    required String memberId,
    required String plan,
    required String phone,
    required String trainer,
    dynamic expiryDate,
    required int daysLeft,
    required bool hasPt,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B4931), Color(0xFF0F2C1E), Color(0xFF08180F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: primaryGold, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryGold.withValues(alpha: 0.18),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: Studio Brand & Member ID
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "IRONBLOOD",
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        color: lightGold,
                      ),
                    ),
                    Text(
                      "OFFICIAL ACCESS PASS",
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: primaryGold,
                      ),
                    ),
                  ],
                ),
                    Row(
                      children: [
                        if (hasPt) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: primaryGreen,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: primaryGold, width: 1),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: primaryGold,
                                  size: 12,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  "PT VIP",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: lightGold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF08180F),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: primaryGold, width: 1.2),
                          ),
                          child: Text(
                            memberId,
                            style: GoogleFonts.montserrat(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: primaryGold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Member Avatar + Full Name & Contacts
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ProfileAvatar(
                      imageUrl: _member['photo_url']?.toString(),
                      name: fullName,
                      radius: 30,
                      showEditIcon: true,
                      borderWidth: 2,
                      borderColor: primaryGold,
                      onTap: () async {
                        final newPhoto = await ProfileAvatar.pickImageSource(
                          context,
                          currentImageUrl: _member['photo_url']?.toString(),
                        );
                        if (newPhoto != null) {
                          final res = await SupabaseService.updateMemberPhoto(
                            memberId: _member['member_id'],
                            photoUrl: newPhoto.isEmpty ? null : newPhoto,
                          );
                          if (res['success'] == true) {
                            setState(() {
                              _member['photo_url'] = newPhoto.isEmpty
                                  ? null
                                  : newPhoto;
                            });
                            await SessionService.saveMemberSession(_member);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Profile picture updated!"),
                                backgroundColor: primaryGreen,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName.toUpperCase(),
                            style: GoogleFonts.rajdhani(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "Phone Number: $phone",
                            style: GoogleFonts.rajdhani(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                              color: Colors.white70,
                            ),
                          ),
                          if (_member['medical_history'] != null &&
                              _member['medical_history']
                                  .toString()
                                  .trim()
                                  .isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.health_and_safety_outlined,
                                  size: 13,
                                  color: primaryGold,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    "Medical: ${_member['medical_history'].toString().trim()}",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Divider(color: primaryGold.withValues(alpha: 0.25), height: 1),
                const SizedBox(height: 14),

                // Plan, Expiry & Days Left
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "MEMBERSHIP PLAN",
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: primaryGold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          plan,
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: lightGold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "EXPIRES ON",
                          style: GoogleFonts.rajdhani(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: primaryGold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(expiryDate),
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildMembershipPeriodCard({
    required String plan,
    dynamic startDate,
    dynamic expiryDate,
    required int daysLeft,
    required String renewalStatus,
  }) {
    final isExpiringSoon = daysLeft <= 7 && daysLeft >= 0;
    final isExpired = daysLeft < 0;
    final isPendingRenewal =
        renewalStatus == 'Pending Approval' ||
        renewalStatus == 'Pending Renewal' ||
        renewalStatus == 'Requested';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isExpired
              ? Colors.redAccent
              : (isExpiringSoon
                    ? Colors.orangeAccent
                    : primaryGold.withValues(alpha: 0.35)),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryGreen,
                        border: Border.all(color: primaryGold, width: 1),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: primaryGold,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "MEMBERSHIP VALIDITY",
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isExpired
                      ? Colors.red.shade900.withValues(alpha: 0.6)
                      : (isExpiringSoon
                            ? Colors.orange.shade900.withValues(alpha: 0.6)
                            : primaryGreen),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isExpired
                        ? Colors.redAccent
                        : (isExpiringSoon ? Colors.orangeAccent : primaryGold),
                    width: 1,
                  ),
                ),
                child: Text(
                  isExpired
                      ? "EXPIRED"
                      : (daysLeft == 0
                            ? "EXPIRES TODAY"
                            : "$daysLeft DAYS LEFT"),
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: isExpired
                        ? Colors.redAccent
                        : (isExpiringSoon ? Colors.orangeAccent : lightGold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF08180F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: inputBorderColor, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      "JOINED / START",
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatDate(startDate),
                      style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: primaryGold.withValues(alpha: 0.25),
                ),
                Column(
                  children: [
                    Text(
                      "EXPIRATION DATE",
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatDate(expiryDate),
                      style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isExpired
                            ? Colors.redAccent
                            : (isExpiringSoon
                                  ? Colors.orangeAccent
                                  : lightGold),
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: primaryGold.withValues(alpha: 0.25),
                ),
                Column(
                  children: [
                    Text(
                      "ACTIVE TIER",
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: primaryGold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      plan,
                      style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isPendingRenewal) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amberAccent, width: 0.9),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.pending_actions_rounded,
                    color: Colors.amberAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Renewal Request Submitted. Awaiting Admin approval.",
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
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _showRenewMembershipModal,
              icon: const Icon(
                Icons.flash_on_rounded,
                color: Color(0xFF091911),
                size: 18,
              ),
              label: Text(
                isPendingRenewal
                    ? "UPDATE RENEWAL REQUEST"
                    : "RENEW MEMBERSHIP PLAN",
                style: GoogleFonts.rajdhani(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: const Color(0xFF091911),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGold,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalTrainingCard({
    required bool hasPt,
    required String ptPlan,
    required String ptTrainer,
    dynamic ptStartDate,
    dynamic ptExpiryDate,
    required int ptDaysLeft,
    required String ptStatus,
  }) {
    final isPtActive = hasPt && ptDaysLeft >= 0;
    final isPtPending =
        ptStatus == 'Requested' ||
        ptStatus == 'PT Requested' ||
        ptStatus == 'Pending Approval';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPtPending
              ? Colors.amberAccent
              : (isPtActive ? primaryGold : primaryGold.withValues(alpha: 0.3)),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryGreen,
                        border: Border.all(color: primaryGold, width: 1),
                      ),
                      child: const Icon(
                        Icons.fitness_center_rounded,
                        color: primaryGold,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "PERSONAL TRAINING (PT)",
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPtActive
                      ? primaryGreen
                      : (isPtPending
                            ? Colors.amber.shade900.withValues(alpha: 0.6)
                            : const Color(0xFF08180F)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isPtActive
                        ? primaryGold
                        : (isPtPending ? Colors.amberAccent : Colors.white24),
                    width: 1,
                  ),
                ),
                child: Text(
                  isPtActive
                      ? "$ptDaysLeft DAYS LEFT"
                      : (isPtPending ? "PENDING APPROVAL" : "AVAILABLE"),
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: isPtActive
                        ? lightGold
                        : (isPtPending ? Colors.amberAccent : Colors.white60),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isPtActive) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF08180F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: inputBorderColor, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        "DEDICATED COACH",
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: primaryGold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ptTrainer,
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: primaryGold.withValues(alpha: 0.25),
                  ),
                  Column(
                    children: [
                      Text(
                        "PT EXPIRATION",
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: primaryGold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatDate(ptExpiryDate),
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: lightGold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _showPersonalTrainingModal,
                icon: const Icon(
                  Icons.replay_rounded,
                  color: lightGold,
                  size: 16,
                ),
                label: Text(
                  "EXTEND / RENEW PT SESSION",
                  style: GoogleFonts.rajdhani(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: lightGold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: primaryGold.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ] else ...[
            Text(
              "Transform your physique with 1-on-1 personalized guidance, customized exercise programming, form correction, and dedicated diet tracking.",
              style: GoogleFonts.rajdhani(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            if (isPtPending) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amberAccent, width: 0.9),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pending_actions_rounded,
                      color: Colors.amberAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "PT Request Submitted. Awaiting Admin assignment.",
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
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: _showPersonalTrainingModal,
                icon: const Icon(
                  Icons.sports_gymnastics_rounded,
                  color: Color(0xFF091911),
                  size: 18,
                ),
                label: Text(
                  isPtPending
                      ? "UPDATE PT REQUEST"
                      : "ENROLL IN PERSONAL TRAINING (PT)",
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: const Color(0xFF091911),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: lightGold,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkoutDetailCard(Map<String, dynamic> schedule) {
    final exercises = schedule['exercises'] as List<dynamic>;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryGold.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  schedule['title'],
                  style: GoogleFonts.montserrat(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: lightGold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryGreen,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: primaryGold.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  schedule['focus'],
                  style: GoogleFonts.rajdhani(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: primaryGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (schedule['protocol'] != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF08180F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: primaryGold.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fitness_center_rounded,
                    color: primaryGold,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      schedule['protocol'],
                      style: GoogleFonts.rajdhani(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: lightGold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            const SizedBox(height: 12),
          ],
          ...exercises.map((ex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 10),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: primaryGold,
                      size: 15,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      ex.toString(),
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStudioInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF08180F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: inputBorderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: primaryGold,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "GYM ACCESS TIMINGS",
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: lightGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "• Monday – Saturday\n  Morning: 6:30 AM – 12:00 PM\n  Evening: 4:00 PM – 10:45 PM\n• Sunday — Closed",
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: primaryGold.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 10),
          Text(
            "Gym Owner & Founder: BAPI DAS • IronBlood Muscle & Fitness",
            style: GoogleFonts.rajdhani(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: primaryGold,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 4. MY RECEIPTS & INVOICES SECTION (IN-APP MEMBER BILLING PORTAL)
  // =========================================================================

  InvoiceModel _buildInvoiceFromTx(Map<String, dynamic> tx) {
    final memberId = _member['member_id']?.toString() ?? 'MB-001';
    final memberName = _member['full_name']?.toString() ?? 'IronBlood Athlete';
    final memberPhone = _member['phone']?.toString() ?? '';
    final memberEmail = _member['email']?.toString() ?? '';

    final typeStr = (tx['type'] ?? 'Membership').toString();
    final isPt =
        typeStr.toLowerCase().contains('personal') ||
        typeStr.toLowerCase().contains('pt');

    final planName =
        tx['plan_name']?.toString() ??
        (isPt
            ? (_member['pt_plan'] ?? 'Monthly PT')
            : (_member['plan'] ?? 'Monthly'));

    final rawCreatedAt = tx['created_at'];
    DateTime invoiceDate = DateTime.now();
    if (rawCreatedAt != null) {
      invoiceDate =
          DateTime.tryParse(rawCreatedAt.toString()) ?? DateTime.now();
    } else if (isPt && _member['pt_start_date'] != null) {
      invoiceDate =
          DateTime.tryParse(_member['pt_start_date'].toString()) ??
          DateTime.now();
    } else if (!isPt && _member['membership_start_date'] != null) {
      invoiceDate =
          DateTime.tryParse(_member['membership_start_date'].toString()) ??
          DateTime.now();
    }

    final startDate = isPt
        ? (DateTime.tryParse(_member['pt_start_date']?.toString() ?? '') ??
              invoiceDate)
        : (DateTime.tryParse(
                _member['membership_start_date']?.toString() ?? '',
              ) ??
              invoiceDate);

    final expiryDate = isPt
        ? (DateTime.tryParse(_member['pt_expiry_date']?.toString() ?? '') ??
              invoiceDate.add(const Duration(days: 30)))
        : (DateTime.tryParse(
                _member['membership_expiry_date']?.toString() ?? '',
              ) ??
              invoiceDate.add(const Duration(days: 30)));

    final baseAmount =
        (tx['base_amount'] as num?)?.toDouble() ??
        (tx['amount'] as num?)?.toDouble() ??
        (isPt ? 3000.0 : 888.0);
    final discountAmount = (tx['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final finalAmount =
        (tx['amount'] as num?)?.toDouble() ?? (baseAmount - discountAmount);

    final paymentMode = tx['payment_mode']?.toString() ?? 'UPI';
    final trainerName =
        tx['trainer_name']?.toString() ??
        (isPt ? (_member['pt_trainer'] ?? 'Head Coach') : null);

    final invoiceNo =
        tx['invoice_no']?.toString() ??
        "IB-${isPt ? 'PT' : 'MB'}-${invoiceDate.year}${invoiceDate.month.toString().padLeft(2, '0')}${invoiceDate.day.toString().padLeft(2, '0')}-${(invoiceDate.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}";

    final isCombined = typeStr.contains('+') || planName.contains('+');
    List<InvoiceLineItem>? lineItems;

    if (isCombined) {
      final memPlan = _member['plan'] ?? 'Monthly';
      final ptPlan = _member['pt_plan'] ?? 'Monthly PT';
      final ptTrainer = _member['pt_trainer'] ?? trainerName ?? 'Head Coach';
      final memExpiry = DateTime.tryParse(_member['membership_expiry_date']?.toString() ?? '') ?? invoiceDate.add(const Duration(days: 30));
      final ptExpiry = DateTime.tryParse(_member['pt_expiry_date']?.toString() ?? '') ?? invoiceDate.add(const Duration(days: 30));

      lineItems = [
        InvoiceLineItem(
          description: '$memPlan Membership Plan',
          category: 'Gym Floor Access',
          coachOrDetails: 'General Floor Access',
          startDate: startDate,
          expiryDate: memExpiry,
          amount: (baseAmount > 0 ? (baseAmount * 0.4).roundToDouble() : 0.0),
        ),
        InvoiceLineItem(
          description: '$ptPlan Personal Training',
          category: 'Personal Training (PT)',
          coachOrDetails: 'Dedicated Coach: $ptTrainer',
          startDate: startDate,
          expiryDate: ptExpiry,
          amount: (baseAmount > 0 ? (baseAmount * 0.6).roundToDouble() : 0.0),
        ),
      ];
    }

    return InvoiceModel(
      invoiceNo: invoiceNo,
      invoiceDate: invoiceDate,
      memberId: memberId,
      memberName: memberName,
      memberPhone: memberPhone,
      memberEmail: memberEmail,
      category: isCombined ? 'MEMBERSHIP + PT ENROLLMENT' : (isPt ? 'PERSONAL TRAINING (PT)' : 'MEMBERSHIP ACCESS'),
      planName: planName,
      trainerName: trainerName,
      startDate: startDate,
      expiryDate: expiryDate,
      baseAmount: baseAmount,
      discountAmount: discountAmount,
      finalAmount: finalAmount,
      paymentMode: paymentMode,
      items: lineItems,
      notes: tx['notes']?.toString(),
    );
  }

  List<Map<String, dynamic>> _getSynthesizedReceiptsList() {
    final currentName = (_member['full_name'] ?? '').toString().trim().toLowerCase();
    final memberUuid = (_member['id'] ?? '').toString().toLowerCase();
    final memberCreated = DateTime.tryParse(_member['created_at']?.toString() ?? '') ??
        DateTime.tryParse(_member['membership_start_date']?.toString() ?? '');

    // Multi-Layer Filter:
    // 1. UUID Check (if present in record)
    // 2. Name Check
    // 3. Timestamp check: Cannot be older than when this member account was created
    List<Map<String, dynamic>> list = _memberReceipts.where((tx) {
      if (memberUuid.isNotEmpty && tx['user_id'] != null) {
        if (tx['user_id'].toString().toLowerCase() != memberUuid) return false;
      }
      final txName = (tx['member_name'] ?? '').toString().trim().toLowerCase();
      if (txName.isNotEmpty && currentName.isNotEmpty) {
        if (txName != currentName) return false;
      }
      if (memberCreated != null) {
        final txDate = DateTime.tryParse(tx['created_at']?.toString() ?? '');
        if (txDate != null && txDate.isBefore(memberCreated.subtract(const Duration(minutes: 10)))) {
          return false; // Created before this member account existed
        }
      }
      return true;
    }).toList();

    // If no transactions logged yet, synthesize from current active pass so the member always sees their bill
    if (list.isEmpty) {
      final planName = _member['plan'] ?? 'Monthly';
      double price = 888.0;
      final planObj = _dynamicMembershipPlans.firstWhere(
        (p) =>
            (p['plan_name'] ?? '').toString().toLowerCase().trim() ==
            planName.toString().toLowerCase().trim(),
        orElse: () => <String, dynamic>{},
      );
      if (planObj.isNotEmpty && planObj['price'] != null) {
        price = (planObj['price'] as num).toDouble();
      }

      list.add({
        'type': 'Membership Enrollment',
        'plan_name': planName,
        'amount': price,
        'base_amount': price,
        'discount_amount': 0.0,
        'payment_mode': 'UPI',
        'created_at':
            _member['membership_start_date'] ??
            _member['created_at'] ??
            DateTime.now().toIso8601String(),
        'notes': 'Official Active Membership Access Pass',
      });

      if (_member['has_pt'] == true) {
        final ptPlan = _member['pt_plan'] ?? 'Monthly PT';
        double ptPrice = 3000.0;
        final ptObj = _dynamicPtPlans.firstWhere(
          (p) =>
              (p['plan_name'] ?? '').toString().toLowerCase().trim() ==
              ptPlan.toString().toLowerCase().trim(),
          orElse: () => <String, dynamic>{},
        );
        if (ptObj.isNotEmpty && ptObj['price'] != null) {
          ptPrice = (ptObj['price'] as num).toDouble();
        }

        list.add({
          'type': 'Personal Training',
          'plan_name': ptPlan,
          'trainer_name': _member['pt_trainer'] ?? 'Head Coach',
          'amount': ptPrice,
          'base_amount': ptPrice,
          'discount_amount': 0.0,
          'payment_mode': 'UPI',
          'created_at':
              _member['pt_start_date'] ??
              _member['membership_start_date'] ??
              DateTime.now().toIso8601String(),
          'notes': 'Personal Training with Coach ${_member['pt_trainer']}',
        });
      }
    }

    // Sort by latest invoice date first
    list.sort((a, b) {
      final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });

    return list;
  }

  Widget _buildReceiptCardWidget(Map<String, dynamic> tx) {
    final invoice = _buildInvoiceFromTx(tx);
    final isPt = invoice.category.contains('PERSONAL');
    final amount = invoice.finalAmount;
    final dateStr = _formatDate(invoice.invoiceDate);
    final paymentMode = invoice.paymentMode.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF08180F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryGold.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            InvoiceService.showReceiptDialog(
              context: context,
              invoice: invoice,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Receipt Top Row: Type & Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isPt
                                ? const Color(0xFF1E3A8A)
                                : const Color(0xFF065F46),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isPt ? "PERSONAL TRAINING" : "MEMBERSHIP",
                            style: GoogleFonts.rajdhani(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "#${invoice.invoiceNo}",
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      dateStr,
                      style: GoogleFonts.rajdhani(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: primaryGold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Plan Title & Amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            invoice.planName,
                            style: GoogleFonts.rajdhani(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          if (invoice.trainerName != null &&
                              invoice.trainerName!.isNotEmpty &&
                              invoice.trainerName != 'Unassigned') ...[
                            Text(
                              "Coach: ${invoice.trainerName}",
                              style: GoogleFonts.rajdhani(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF6EE7B7),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "₹${amount.toInt()}",
                          style: GoogleFonts.montserrat(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: lightGold,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(
                              paymentMode == 'UPI'
                                  ? Icons.qr_code_rounded
                                  : (paymentMode == 'CARD'
                                        ? Icons.credit_card_rounded
                                        : Icons.payments_rounded),
                              color: const Color(0xFF10B981),
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "$paymentMode • PAID",
                              style: GoogleFonts.rajdhani(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                Divider(
                  color: primaryGold.withValues(alpha: 0.15),
                  height: 1,
                ),
                const SizedBox(height: 8),

                // Subtle Tap Cue Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Official Tax Invoice Available",
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white54,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          "VIEW INVOICE & PDF",
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: primaryGold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 10,
                          color: primaryGold,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentReceiptsSection() {
    final receipts = _getSynthesizedReceiptsList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryGold.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryGreen,
                        border: Border.all(color: primaryGold, width: 1.2),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: primaryGold,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "MY RECEIPTS & INVOICES",
                            style: GoogleFonts.rajdhani(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: lightGold,
                            ),
                          ),
                          Text(
                            "Instant access to your verified gym payment receipts",
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryGreen,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: primaryGold.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  "${receipts.length} ${receipts.length == 1 ? 'BILL' : 'BILLS'}",
                  style: GoogleFonts.rajdhani(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: primaryGold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Receipts List: shows latest 2 records and scrollable for more
          if (receipts.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Text(
                "No payment receipts found",
                style: GoogleFonts.rajdhani(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else if (receipts.length <= 2) ...[
            ...receipts.map((tx) => _buildReceiptCardWidget(tx)),
          ] else ...[
            // Fixed height showing 2 records cleanly, scrollable for older records
            SizedBox(
              height: 282,
              child: RawScrollbar(
                controller: _receiptsScrollController,
                thumbColor: primaryGold.withValues(alpha: 0.6),
                radius: const Radius.circular(6),
                thickness: 4,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _receiptsScrollController,
                  padding: EdgeInsets.zero,
                  itemCount: receipts.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    return _buildReceiptCardWidget(receipts[index]);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // STUDIO ANNOUNCEMENTS & NOTICE BOARD WIDGET (MEMBER VIEW)
  // =========================================================================
  Widget _buildAnnouncementsSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primaryGold.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryGold.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1F15),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(
                  color: primaryGold.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.campaign_rounded,
                      color: primaryGold,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "STUDIO NOTICE BOARD",
                      style: GoogleFonts.rajdhani(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: lightGold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: primaryGold,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${_announcements.length} ${_announcements.length == 1 ? 'UPDATE' : 'UPDATES'}",
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: const Color(0xFF091911),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Announcements List (Shows 1 notice cleanly, scrollable for remaining)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _announcements.length <= 1
                ? Column(
                    children: _announcements
                        .map((item) => _buildNoticeCardWidget(item))
                        .toList(),
                  )
                : SizedBox(
                    height: 140,
                    child: RawScrollbar(
                      controller: _announcementsScrollController,
                      thumbColor: primaryGold.withValues(alpha: 0.6),
                      radius: const Radius.circular(6),
                      thickness: 4,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _announcementsScrollController,
                        padding: EdgeInsets.zero,
                        itemCount: _announcements.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          return _buildNoticeCardWidget(_announcements[index]);
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeCardWidget(Map<String, dynamic> item) {
    final title = item['title'] ?? 'Notice';
    final message = item['message'] ?? '';
    final dateStr = _formatFriendlyTime(item['created_at']);
    final String? expStr = item['expires_at']?.toString();
    final DateTime? expDate =
        expStr != null ? DateTime.tryParse(expStr) : null;

    String expiryBadge = '';
    if (expDate != null) {
      final diff = expDate.difference(DateTime.now());
      if (diff.inDays > 0) {
        expiryBadge = '${diff.inDays}d ${diff.inHours % 24}h left';
      } else if (diff.inHours > 0) {
        expiryBadge = '${diff.inHours}h left';
      } else if (diff.inMinutes > 0) {
        expiryBadge = '${diff.inMinutes}m left';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF08180F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryGold.withValues(alpha: 0.25),
          width: 1.0,
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
                  const Icon(
                    Icons.campaign_rounded,
                    size: 14,
                    color: primaryGold,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "STUDIO NOTICE",
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: lightGold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  if (expiryBadge.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: primaryGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 10,
                            color: primaryGold,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            expiryBadge,
                            style: GoogleFonts.rajdhani(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: lightGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.rajdhani(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFriendlyTime(dynamic isoStr) {
    if (isoStr == null) return 'Recent';
    try {
      final dt = DateTime.parse(isoStr.toString()).toLocal();
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
      return "${dt.day} ${_getShortMonth(dt.month)}";
    } catch (_) {
      return 'Recent';
    }
  }

  String _getShortMonth(int m) {
    const list = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (m >= 1 && m <= 12) return list[m - 1];
    return '';
  }

  @override
  void dispose() {
    _receiptsScrollController.dispose();
    _announcementsScrollController.dispose();
    super.dispose();
  }
}

class _MemberNotificationItem {
  final String id;
  final String title;
  final String message;
  final String category; // 'EXPIRY', 'RENEWAL', 'PT', 'ANNOUNCEMENT', 'INVOICE'
  final String priority; // 'URGENT', 'WARNING', 'INFO', 'SUCCESS'
  final DateTime timestamp;
  final IconData icon;
  final Color iconColor;
  final String badgeText;
  final String? actionLabel;
  final VoidCallback? onTap;

  _MemberNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.priority,
    required this.timestamp,
    required this.icon,
    required this.iconColor,
    required this.badgeText,
    this.actionLabel,
    this.onTap,
  });
}
