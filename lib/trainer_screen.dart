import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/supabase_service.dart';
import 'services/session_service.dart';
import 'widgets/profile_avatar.dart';
import 'auth_screen.dart';

class TrainerScreen extends StatefulWidget {
  final Map<String, dynamic>? trainerData;

  const TrainerScreen({super.key, this.trainerData});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  // Brand Color Palette
  static const Color primaryGold = Color(0xFFC9A227);
  static const Color primaryGreen = Color(0xFF123222);
  static const Color darkBackground = Color(0xFF091911);
  static const Color cardSurface = Color(0xFF0F261B);
  static const Color lightGold = Color(0xFFFFE082);
  static const Color inputBorderColor = Color(0xFF1E4230);

  Map<String, dynamic> _trainer = {};
  List<Map<String, dynamic>> _myClients = [];
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoading = false;
  String _searchQuery = "";
  String _clientFilter = "ALL";
  final ScrollController _announcementsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.trainerData != null && widget.trainerData!.isNotEmpty) {
      _trainer = widget.trainerData!;
    }
    _loadTrainerData();
  }

  Future<void> _loadTrainerData() async {
    // 1. Instantly load local session & cached trainer announcements & clients (0ms)
    final savedTrainer = await SessionService.getSavedTrainer();
    if (savedTrainer != null && savedTrainer.isNotEmpty) {
      _trainer = savedTrainer;
    } else if (widget.trainerData != null && widget.trainerData!.isNotEmpty) {
      _trainer = widget.trainerData!;
    }

    final activeName = _trainer['full_name']?.toString() ?? '';
    final cachedAnnouncements = await SupabaseService.getCachedAnnouncements(
      targetAudience: 'TRAINERS',
      onlyActive: true,
    );

    List<Map<String, dynamic>> cachedClients = [];
    if (activeName.isNotEmpty) {
      cachedClients = await SupabaseService.fetchMembersForTrainer(activeName);
    }

    if (mounted) {
      setState(() {
        _announcements = cachedAnnouncements;
        if (cachedClients.isNotEmpty) {
          _myClients = cachedClients;
        }
        _isLoading = false;
      });
    }

    // 2. Refresh concurrently in background
    try {
      final futures = <Future<dynamic>>[
        SupabaseService.fetchTrainers(),
        SupabaseService.fetchAnnouncements(
          targetAudience: 'TRAINERS',
          onlyActive: true,
        ),
      ];
      if (activeName.isNotEmpty) {
        futures.add(SupabaseService.fetchMembersForTrainer(activeName));
      }

      final results = await Future.wait(futures);

      if (mounted) {
        final trainerId = _trainer['trainer_id'] ?? _trainer['id'];
        final allTrainers = results[0] as List<Map<String, dynamic>>;
        final matched = allTrainers.firstWhere(
          (t) =>
              (trainerId != null &&
                  (t['trainer_id'] ?? '').toString().toLowerCase() ==
                      trainerId.toString().toLowerCase()) ||
              (activeName.isNotEmpty &&
                  (t['full_name'] ?? '').toString().toLowerCase() ==
                      activeName.toLowerCase()),
          orElse: () => <String, dynamic>{},
        );

        if (matched.isNotEmpty) {
          _trainer = matched;
          await SessionService.saveTrainerSession(_trainer);
        }

        _announcements = results[1] as List<Map<String, dynamic>>;
        if (results.length >= 3) {
          _myClients = results[2] as List<Map<String, dynamic>>;
        }
        _isLoading = false;
        setState(() {});
      }
    } catch (e) {
      debugPrint("Trainer background fetch error: $e");
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
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
          "Exit Trainer Command Portal, ${_trainer['full_name'] ?? 'Coach'}?",
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

  @override
  Widget build(BuildContext context) {
    final trainerName = _trainer['full_name'] ?? 'Coach Roster';
    final trainerId = _trainer['trainer_id'] ?? 'TR-01';
    final phone = _trainer['phone'] ?? 'N/A';
    final experience = _trainer['experience'] ?? '3+ Years';

    final totalPtCount = _myClients.where((c) => c['has_pt'] == true).length;
    final activePtCount = _myClients.where((c) {
      final d = SupabaseService.daysRemaining(c['pt_expiry_date']?.toString());
      return c['has_pt'] == true && d > 0;
    }).length;
    final expiringPtCount = _myClients.where((c) {
      final d = SupabaseService.daysRemaining(c['pt_expiry_date']?.toString());
      return c['has_pt'] == true && d >= 0 && d <= 7;
    }).length;

    final filteredClients = _myClients.where((c) {
      final hasPt = c['has_pt'] == true;
      final ptDaysLeft =
          SupabaseService.daysRemaining(c['pt_expiry_date']?.toString());

      if (_clientFilter == "ACTIVE" && (!hasPt || ptDaysLeft <= 0)) {
        return false;
      }
      if (_clientFilter == "EXPIRING" &&
          (!hasPt || ptDaysLeft < 0 || ptDaysLeft > 7)) {
        return false;
      }
      if (_clientFilter == "PT" && !hasPt) {
        return false;
      }

      final name = (c['full_name'] ?? '').toString().toLowerCase();
      final id = (c['member_id'] ?? '').toString().toLowerCase();
      final p = (c['phone'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || id.contains(q) || p.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: darkBackground,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1F15),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primaryGold, width: 1.2),
            ),
            child: Image.asset(
              'lib/logo.png',
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.sports_mma_rounded, color: primaryGold),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [lightGold, primaryGold, lightGold],
                  ).createShader(bounds),
                  child: Text(
                    trainerName.toUpperCase(),
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: primaryGold,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "COACH",
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
                fontSize: 10,
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
            tooltip: "Refresh Clients",
            onPressed: _loadTrainerData,
          ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. TRAINER PROFILE BADGE
                  _buildTrainerBadgeCard(
                    trainerName: trainerName,
                    trainerId: trainerId,
                    phone: phone,
                    experience: experience,
                  ),

                  const SizedBox(height: 20),

                  // 2. QUICK STATS ROW (PT VIP CLIENTS, ACTIVE PASSES, EXPIRING)
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: "PT VIP CLIENTS",
                          value: "$totalPtCount",
                          icon: Icons.sports_gymnastics_rounded,
                          color: primaryGold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildStatCard(
                          title: "ACTIVE PASSES",
                          value: "$activePtCount",
                          icon: Icons.check_circle_outline_rounded,
                          color: const Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildStatCard(
                          title: "EXPIRING (≤7 D)",
                          value: "$expiringPtCount",
                          icon: Icons.hourglass_bottom_rounded,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 3. STUDIO NOTICE BOARD & ANNOUNCEMENTS BANNER
                  if (_announcements.isNotEmpty) ...[
                    _buildAnnouncementsSection(),
                    const SizedBox(height: 24),
                  ],

                  // 3. SECTION HEADER & SEARCH
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "ASSIGNED PT CLIENTS",
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                          color: lightGold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: primaryGreen,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: primaryGold.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          "${filteredClients.length} ATHLETES",
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

                  // Filter Pills Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill(
                          label: "⭐ ALL PT VIPs",
                          count: "$totalPtCount",
                          isSelected: _clientFilter == "ALL",
                          onTap: () => setState(() => _clientFilter = "ALL"),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: "ACTIVE SESSIONS",
                          count: "$activePtCount",
                          isSelected: _clientFilter == "ACTIVE",
                          onTap: () => setState(() => _clientFilter = "ACTIVE"),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: "EXPIRING SOON",
                          count: "$expiringPtCount",
                          isSelected: _clientFilter == "EXPIRING",
                          onTap: () => setState(() => _clientFilter = "EXPIRING"),
                        ),
                      ],
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
                        hintText: "Search client by Name, ID, Phone...",
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

                  // Client List
                  _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child:
                                CircularProgressIndicator(color: primaryGold),
                          ),
                        )
                      : filteredClients.isEmpty
                          ? _buildEmptyPlaceholder(
                              "No assigned PT athletes found matching the filter.")
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filteredClients.length,
                              separatorBuilder: (context, index) =>
                                   const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final client = filteredClients[index];
                                final isActive = client['is_active'] == true;
                                final hasPt = client['has_pt'] == true;
                                final isPtRequested = client['pt_status'] == 'Requested';
                                final memExpiry = client['membership_expiry_date']?.toString();
                                final memDaysLeft = SupabaseService.daysRemaining(memExpiry);
                                final ptExpiry = client['pt_expiry_date']?.toString();
                                final ptDaysLeft = SupabaseService.daysRemaining(ptExpiry);

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: cardSurface.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: isPtRequested
                                          ? Colors.amberAccent
                                          : (hasPt
                                              ? primaryGold.withValues(alpha: 0.7)
                                              : primaryGold.withValues(alpha: 0.3)),
                                      width: (hasPt || isPtRequested) ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ProfileAvatar(
                                            imageUrl: client['photo_url']
                                                ?.toString(),
                                            name: client['full_name'] ??
                                                'Athlete',
                                            radius: 24,
                                            borderWidth: 1.4,
                                            borderColor: hasPt
                                                ? lightGold
                                                : primaryGold,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Row(
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              client['full_name'] ??
                                                                  'Unknown Athlete',
                                                              style: GoogleFonts.rajdhani(
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
                                                              padding: const EdgeInsets.symmetric(
                                                                  horizontal: 6, vertical: 1.5),
                                                              decoration: BoxDecoration(
                                                                color: primaryGold,
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: Text(
                                                                "PT VIP",
                                                                style: GoogleFonts.rajdhani(
                                                                  fontSize: 9,
                                                                  fontWeight: FontWeight.w900,
                                                                  color: const Color(0xFF091911),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isActive
                                                            ? Colors.green.shade900
                                                                .withValues(
                                                                    alpha: 0.6)
                                                            : Colors.red.shade900
                                                                .withValues(
                                                                    alpha: 0.6),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                4),
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
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.w900,
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
                                                      "ID: ${client['member_id']} • Phone: ${client['phone'] ?? 'N/A'}",
                                                      style: GoogleFonts.rajdhani(
                                                        fontSize: 12.5,
                                                        fontWeight: FontWeight.w600,
                                                        color: primaryGold
                                                            .withValues(alpha: 0.9),
                                                      ),
                                                    ),
                                                    if (client['emergency_phone'] != null &&
                                                        client['emergency_phone']
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
                                                            "Emg: ${client['emergency_phone']}",
                                                            style: GoogleFonts.rajdhani(
                                                              fontSize: 11.5,
                                                              fontWeight: FontWeight.w700,
                                                              color: Colors.redAccent.shade100,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                  ],
                                                ),
                                                if (client['address'] != null &&
                                                    client['address']
                                                        .toString()
                                                        .trim()
                                                        .isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2),
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.location_on_outlined,
                                                          size: 11,
                                                          color: primaryGold,
                                                        ),
                                                        const SizedBox(width: 3),
                                                        Expanded(
                                                          child: Text(
                                                            client['address'].toString().trim(),
                                                            style: GoogleFonts.rajdhani(
                                                              fontSize: 11.5,
                                                              fontWeight: FontWeight.w600,
                                                              color: Colors.white70,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                if (client['medical_history'] != null &&
                                                    client['medical_history']
                                                        .toString()
                                                        .trim()
                                                        .isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2),
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.health_and_safety_outlined,
                                                          size: 11,
                                                          color: Colors.amberAccent,
                                                        ),
                                                        const SizedBox(width: 3),
                                                        Expanded(
                                                          child: Text(
                                                            "Med: ${client['medical_history'].toString().trim()}",
                                                            style: GoogleFonts.rajdhani(
                                                              fontSize: 11.5,
                                                              fontWeight: FontWeight.w600,
                                                              color: Colors.amber.shade100,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 12),

                                      // Dedicated Personal Training Box
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF08180F),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: hasPt
                                                ? primaryGold.withValues(alpha: 0.4)
                                                : inputBorderColor,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(Icons.sports_gymnastics_rounded,
                                                        size: 16, color: primaryGold),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      "PT Plan: ${client['pt_plan'] ?? 'Personal Training'}",
                                                      style: GoogleFonts.rajdhani(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w800,
                                                        color: hasPt ? lightGold : Colors.white70,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (hasPt && ptExpiry != null)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: ptDaysLeft <= 5
                                                          ? Colors.red.shade900.withValues(alpha: 0.5)
                                                          : primaryGreen,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      ptDaysLeft > 0 ? "$ptDaysLeft D Left" : "PT Expired",
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
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  "PT Schedule / Period:",
                                                  style: GoogleFonts.rajdhani(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                                Text(
                                                  ptExpiry != null
                                                      ? "Expires: ${ptExpiry.split('T')[0]}"
                                                      : "Continuous Coaching",
                                                  style: GoogleFonts.rajdhani(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  "Gym Membership Plan:",
                                                  style: GoogleFonts.rajdhani(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white60,
                                                  ),
                                                ),
                                                Text(
                                                  "${client['plan'] ?? 'Monthly'} (${memExpiry != null ? (memDaysLeft > 0 ? '$memDaysLeft d left' : 'Expired') : 'Active'})",
                                                  style: GoogleFonts.rajdhani(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: lightGold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                  const SizedBox(height: 24),

                  // 4. DAILY COACHING PROTOCOL
                  _buildDailyFloorChecklist(),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainerBadgeCard({
    required String trainerName,
    required String trainerId,
    required String phone,
    required String experience,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
            color: primaryGold.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          ProfileAvatar(
            imageUrl: _trainer['photo_url']?.toString(),
            name: trainerName,
            radius: 28,
            showEditIcon: true,
            borderWidth: 2,
            borderColor: primaryGold,
            onTap: () async {
              final newPhoto = await ProfileAvatar.pickImageSource(
                context,
                currentImageUrl: _trainer['photo_url']?.toString(),
              );
              if (newPhoto != null) {
                final tId = _trainer['trainer_id'] ?? _trainer['id'];
                final res = await SupabaseService.updateTrainerPhoto(
                  trainerId: tId,
                  photoUrl: newPhoto.isEmpty ? null : newPhoto,
                );
                if (res['success'] == true) {
                  setState(() {
                    _trainer['photo_url'] =
                        newPhoto.isEmpty ? null : newPhoto;
                  });
                  await SessionService.saveTrainerSession(_trainer);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Trainer photo updated!"),
                      backgroundColor: primaryGreen,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        trainerName.toUpperCase(),
                        style: GoogleFonts.rajdhani(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF08180F),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: primaryGold),
                      ),
                      child: Text(
                        trainerId,
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: lightGold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "PERSONAL TRAINER & COACH • EXP: $experience",
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: primaryGold,
                  ),
                ),
                Text(
                  "Contact: $phone",
                  style: GoogleFonts.rajdhani(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              Text(
                value,
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required String count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primaryGold : const Color(0xFF08180F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryGold : inputBorderColor,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: isSelected ? const Color(0xFF091911) : Colors.white70,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF091911) : primaryGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count,
                style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? lightGold : primaryGold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyFloorChecklist() {
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
              const Icon(Icons.playlist_add_check_rounded,
                  color: primaryGold, size: 22),
              const SizedBox(width: 8),
              Text(
                "TRAINER FLOOR PROTOCOL",
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
            "1. Inspect barbell clips, cables & bench safety locks\n2. Monitor member lifting form & posture during push/pull sets\n3. Ensure dumbbell racks are organized & weights re-racked\n4. Guide newly enrolled members on initial workout routines",
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaceholder(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryGold.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline_rounded,
              size: 40, color: primaryGold.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            message,
            style: GoogleFonts.rajdhani(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // STUDIO ANNOUNCEMENTS & NOTICE BOARD WIDGET (TRAINER VIEW)
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
                    "${_announcements.length} ${_announcements.length == 1 ? 'NOTICE' : 'NOTICES'}",
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
      return "${dt.day}/${dt.month}/${dt.year}";
    } catch (_) {
      return 'Recent';
    }
  }

  @override
  void dispose() {
    _announcementsScrollController.dispose();
    super.dispose();
  }
}
