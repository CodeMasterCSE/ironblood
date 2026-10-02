import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/supabase_service.dart';
import 'services/session_service.dart';
import 'admin_screen.dart';
import 'member_screen.dart';
import 'trainer_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Brand Color Palette
  static const Color primaryGold = Color(0xFFC9A227);
  static const Color primaryGreen = Color(0xFF123222);
  static const Color darkBackground = Color(0xFF091911);
  static const Color cardSurface = Color(0xFF0F261B);
  static const Color lightGold = Color(0xFFFFE082);
  static const Color inputBorderColor = Color(0xFF1E4230);

  // Form Controllers
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoggingIn = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState?.validate() ?? false) {
      final identifier = _identifierController.text.trim();
      final password = _passwordController.text.trim();

      // Check if Admin Login credentials entered
      if (identifier.toUpperCase() == 'ADMIN') {
        setState(() => _isLoggingIn = true);
        final adminResult = await SupabaseService.loginAdmin(
          identifier: identifier,
          password: password,
        );

        if (adminResult['success'] == true) {
          final adminData =
              adminResult['admin'] as Map<String, dynamic>? ?? {};
          await SessionService.saveAdminSession(adminData);
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          setState(() => _isLoggingIn = false);

          final adminName =
              adminData['full_name']?.toString().toUpperCase() ?? "ADMIN";

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: primaryGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: primaryGold, width: 1.2),
              ),
              content: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: primaryGold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Welcome $adminName! Accessing Command Center...",
                      style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 700),
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const AdminScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
            ),
          );
          return;
        } else {
          if (!mounted) return;
          setState(() => _isLoggingIn = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF8B1E1E),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
              ),
              content: Text(
                adminResult['message']?.toString() ??
                    "Invalid Admin Password. Access Denied.",
                style: GoogleFonts.rajdhani(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          );
          return;
        }
      }

      // Check if Trainer Login credentials entered (starts with TR-)
      if (identifier.toUpperCase().startsWith('TR-')) {
        setState(() => _isLoggingIn = true);
        final trainerResult = await SupabaseService.loginTrainer(
          trainerIdOrPhone: identifier,
          password: password,
        );
        if (!mounted) return;
        setState(() => _isLoggingIn = false);

        if (trainerResult['success'] == true) {
          final trainerData = trainerResult['trainer'] as Map<String, dynamic>;
          await SessionService.saveTrainerSession(trainerData);
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: primaryGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: primaryGold, width: 1.2),
              ),
              content: Row(
                children: [
                  const Icon(Icons.sports_mma_rounded, color: primaryGold),
                  const SizedBox(width: 12),
                  Text(
                    "Welcome Coach ${trainerData['full_name'] ?? ''}!",
                    style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          );

          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 700),
              pageBuilder: (context, animation, secondaryAnimation) =>
                  TrainerScreen(trainerData: trainerData),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
            ),
          );
          return;
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF3B1010),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
              ),
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      trainerResult['message'] ??
                          'Trainer login failed. Check ID/Password or activate your account.',
                      style: GoogleFonts.rajdhani(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          return;
        }
      }

      // Try Member Login via Supabase
      setState(() => _isLoggingIn = true);

      final result = await SupabaseService.loginMember(
        memberIdOrPhone: identifier,
        password: password,
      );

      if (result['success'] == true) {
        if (!mounted) return;
        setState(() => _isLoggingIn = false);

        final memberData = result['member'] is Map<String, dynamic>
            ? result['member'] as Map<String, dynamic>
            : <String, dynamic>{
                'full_name': identifier,
                'member_id': identifier,
              };

        await SessionService.saveMemberSession(memberData);
        if (!mounted) return;
        final memberName = memberData['full_name'] ?? 'Warrior';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: primaryGold, width: 1.2),
            ),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: primaryGold),
                const SizedBox(width: 12),
                Text(
                  "Access Granted. Welcome back, $memberName!",
                  style: GoogleFonts.rajdhani(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        );

        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 700),
            pageBuilder: (context, animation, secondaryAnimation) =>
                MemberScreen(memberData: memberData),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        );
        return;
      }

      // If member login failed and identifier might be a phone number or email, check Trainer table
      final trainerFallback = await SupabaseService.loginTrainer(
        trainerIdOrPhone: identifier,
        password: password,
      );

      if (!mounted) return;
      setState(() => _isLoggingIn = false);

      if (trainerFallback['success'] == true) {
        final trainerData = trainerFallback['trainer'] as Map<String, dynamic>;
        await SessionService.saveTrainerSession(trainerData);
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: primaryGold, width: 1.2),
            ),
            content: Row(
              children: [
                const Icon(Icons.sports_mma_rounded, color: primaryGold),
                const SizedBox(width: 12),
                Text(
                  "Welcome Coach ${trainerData['full_name'] ?? ''}!",
                  style: GoogleFonts.rajdhani(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        );

        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 700),
            pageBuilder: (context, animation, secondaryAnimation) =>
                TrainerScreen(trainerData: trainerData),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        );
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3B1010),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.redAccent, width: 1.2),
          ),
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  result['message'] ??
                      'Login failed. Please check credentials or activate your account.',
                  style: GoogleFonts.rajdhani(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showActivationModal() {
    final phoneOrIdController = TextEditingController();
    final newPasswordController = TextEditingController();
    bool obscure = true;
    bool isActivating = false;

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
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: primaryGold.withValues(alpha: 0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 30,
                ),
              ],
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
                        Icons.how_to_reg_rounded,
                        color: primaryGold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "ACTIVATE ACCOUNT",
                          style: GoogleFonts.rajdhani(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: lightGold,
                          ),
                        ),
                        Text(
                          "For newly enrolled Members & Trainers registered by Admin",
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  "MEMBER ID / TRAINER ID / PHONE",
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: primaryGold,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: phoneOrIdController,
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: "e.g. MB-001, TR-01 or 9876543210",
                    hintStyle: GoogleFonts.rajdhani(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF08180F),
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      color: primaryGold,
                      size: 20,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: inputBorderColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: primaryGold,
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  "SET NEW ACCESS PASSWORD",
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: primaryGold,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: obscure,
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: "Minimum 6 characters",
                    hintStyle: GoogleFonts.rajdhani(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF08180F),
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: primaryGold,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: primaryGold.withValues(alpha: 0.8),
                        size: 20,
                      ),
                      onPressed: () {
                        setModalState(() => obscure = !obscure);
                      },
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: inputBorderColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: primaryGold,
                        width: 1.8,
                      ),
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
                      onTap: isActivating
                          ? null
                          : () async {
                              final id = phoneOrIdController.text.trim();
                              final pass = newPasswordController.text;

                              if (id.isEmpty || pass.length < 6) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF3B1010),
                                    content: Text(
                                      "Please enter Member ID & a password with min 6 characters.",
                                      style: GoogleFonts.rajdhani(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                                return;
                              }

                              setModalState(() => isActivating = true);
                              final res = await SupabaseService.activateAccount(
                                memberIdOrPhone: id,
                                newPassword: pass,
                              );
                              setModalState(() => isActivating = false);

                              if (!context.mounted) return;
                              Navigator.pop(context);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: res['success'] == true
                                      ? primaryGreen
                                      : const Color(0xFF3B1010),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: res['success'] == true
                                          ? primaryGold
                                          : Colors.redAccent,
                                    ),
                                  ),
                                  content: Text(
                                    res['message'] ?? 'Activation finished.',
                                    style: GoogleFonts.rajdhani(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                            },
                      child: Center(
                        child: isActivating
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF091911),
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                "ACTIVATE & SET PASSWORD",
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
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showResetPasswordModal() {
    final phoneOrIdController = TextEditingController();
    final newPasswordController = TextEditingController();
    bool obscure = true;
    bool isResetting = false;

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
            decoration: BoxDecoration(
              color: const Color(0xFF0A1F15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: primaryGold.withValues(alpha: 0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 30,
                ),
              ],
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
                        Icons.lock_reset_rounded,
                        color: primaryGold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "RESET PASSWORD",
                          style: GoogleFonts.rajdhani(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: lightGold,
                          ),
                        ),
                        Text(
                          "For registered Members & Trainers to recover access",
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  "MEMBER ID / TRAINER ID / PHONE",
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: primaryGold,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: phoneOrIdController,
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: "e.g. MB-001, TR-01 or 9876543210",
                    hintStyle: GoogleFonts.rajdhani(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF08180F),
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      color: primaryGold,
                      size: 20,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: inputBorderColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: primaryGold,
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  "ENTER NEW ACCESS PASSWORD",
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: primaryGold,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: obscure,
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: "Minimum 6 characters",
                    hintStyle: GoogleFonts.rajdhani(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF08180F),
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: primaryGold,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: primaryGold.withValues(alpha: 0.8),
                        size: 20,
                      ),
                      onPressed: () {
                        setModalState(() => obscure = !obscure);
                      },
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: inputBorderColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: primaryGold,
                        width: 1.8,
                      ),
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
                      onTap: isResetting
                          ? null
                          : () async {
                              final id = phoneOrIdController.text.trim();
                              final pass = newPasswordController.text;

                              if (id.isEmpty || pass.length < 6) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF3B1010),
                                    content: Text(
                                      "Please enter Member/Trainer ID & new password (min 6 chars).",
                                      style: GoogleFonts.rajdhani(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                                return;
                              }

                              setModalState(() => isResetting = true);
                              final res = await SupabaseService.resetPassword(
                                memberIdOrPhone: id,
                                newPassword: pass,
                              );
                              setModalState(() => isResetting = false);

                              if (!context.mounted) return;
                              Navigator.pop(context);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: res['success'] == true
                                      ? primaryGreen
                                      : const Color(0xFF3B1010),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: res['success'] == true
                                          ? primaryGold
                                          : Colors.redAccent,
                                    ),
                                  ),
                                  content: Text(
                                    res['message'] ?? 'Password reset completed.',
                                    style: GoogleFonts.rajdhani(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                            },
                      child: Center(
                        child: isResetting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF091911),
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                "RESET & UPDATE PASSWORD",
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
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showInquiryModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                const Icon(
                  Icons.fitness_center_rounded,
                  color: primaryGold,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  "JOIN THE IRONBLOOD GYM",
                  style: GoogleFonts.rajdhani(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: lightGold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Memberships at IRONBLOOD are exclusive & curated. Visit our front desk or reach out to enroll and claim your official Member ID.",
              style: GoogleFonts.rajdhani(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 18),
            _buildContactInfoTile(
              icon: Icons.location_on_rounded,
              title: "GYM Address",
              subtitle:
                  "50, Bansdroni Park, Ward Number 113,\nKolkata, West Bengal 700070, India",
            ),
            const SizedBox(height: 10),
            _buildContactInfoTile(
              icon: Icons.phone_in_talk_rounded,
              title: "Get In Touch",
              subtitle: "+91 82820 72600\nironbloodmuscleandfitness@gmail.com",
            ),
            const SizedBox(height: 10),
            _buildContactInfoTile(
              icon: Icons.access_time_filled_rounded,
              title: "GYM Timings",
              subtitle:
                  "Monday – Saturday \nMorning: 6:30 AM – 12:00 PM \nEvening: 4:00 PM – 10:45 PM\nSunday — Closed",
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryGold, width: 1.2),
                color: primaryGreen.withValues(alpha: 0.5),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context),
                  child: Center(
                    child: Text(
                      "CLOSE INQUIRY",
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                        color: lightGold,
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
    );
  }

  Widget _buildContactInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF08180F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: inputBorderColor, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryGold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: primaryGold,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.rajdhani(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBackground,
      body: Stack(
        children: [
          // Background Gradient Ambience
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
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand Header
                    _buildBrandHeader(),

                    const SizedBox(height: 30),

                    // Login Card Container
                    Container(
                      decoration: BoxDecoration(
                        color: cardSurface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: primaryGold.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: primaryGold.withValues(alpha: 0.08),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(22),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "IRONBLOOD PORTAL LOGIN",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.0,
                                    color: lightGold,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primaryGreen,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: primaryGold.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    "OFFICIAL",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                      color: primaryGold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),

                            // Identifier Field
                            _buildInputField(
                              controller: _identifierController,
                              label: "MEMBER ID / TRAINER ID / PHONE",
                              hint: "e.g. MB-001, TR-01 or 9876543210",
                              icon: Icons.person_outline_rounded,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Please enter your Member/Trainer ID or phone";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Password Field
                            _buildInputField(
                              controller: _passwordController,
                              label: "ACCESS PASSWORD",
                              hint: "••••••••",
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: primaryGold.withValues(alpha: 0.8),
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return "Please enter your access password";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),

                            // Remember Me & Forgot
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: _rememberMe,
                                        activeColor: primaryGold,
                                        checkColor: darkBackground,
                                        side: BorderSide(
                                          color: primaryGold.withValues(
                                            alpha: 0.6,
                                          ),
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        onChanged: (val) {
                                          setState(
                                            () => _rememberMe = val ?? true,
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Keep Logged In",
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: _showResetPasswordModal,
                                  child: Text(
                                    "Forgot PIN / Pass?",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: primaryGold,
                                      decoration: TextDecoration.underline,
                                      decorationColor: primaryGold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),

                            // Submit Button
                            _buildPrimaryButton(
                              label: "ENTER THE ARENA",
                              isLoading: _isLoggingIn,
                              onPressed: _handleLogin,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // First Time Member Activation Action
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF08180F),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primaryGold.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primaryGreen,
                              border: Border.all(
                                color: primaryGold.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Icon(
                              Icons.key_rounded,
                              color: primaryGold,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "First Time Logging In?",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  "Activate Member or Trainer account",
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: primaryGold.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _showActivationModal,
                            style: TextButton.styleFrom(
                              backgroundColor: primaryGold.withValues(
                                alpha: 0.15,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: primaryGold.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                            child: Text(
                              "ACTIVATE",
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: lightGold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Membership Inquiry CTA
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Not an active member yet?",
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _showInquiryModal,
                          child: Text(
                            "Inquire at Desk",
                            style: GoogleFonts.rajdhani(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: lightGold,
                              decoration: TextDecoration.underline,
                              decorationColor: lightGold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Tagline
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryGold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "NO PAIN NO GAIN",
                          style: GoogleFonts.rajdhani(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.8,
                            color: lightGold.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryGold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Top Brand Header
  Widget _buildBrandHeader() {
    return Column(
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: Image.asset(
            'lib/logo.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.fitness_center_rounded,
                size: 60,
                color: primaryGold,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [lightGold, primaryGold, Color(0xFF9E7B1A), lightGold],
            ).createShader(bounds);
          },
          child: Text(
            "IRONBLOOD",
            style: GoogleFonts.montserrat(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 6.5,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          "MUSCLE AND FITNESS STUDIO",
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3.8,
            color: const Color(0xFFE8D7A3),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: primaryGold,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: GoogleFonts.rajdhani(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.rajdhani(
              color: Colors.white.withValues(alpha: 0.25),
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: const Color(0xFF08180F),
            prefixIcon: Icon(
              icon,
              color: primaryGold.withValues(alpha: 0.8),
              size: 20,
            ),
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: inputBorderColor, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryGold, width: 1.8),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
            ),
            errorStyle: GoogleFonts.rajdhani(
              color: Colors.redAccent.shade100,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF9E7B1A), primaryGold, lightGold],
        ),
        boxShadow: [
          BoxShadow(
            color: primaryGold.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Color(0xFF091911),
                      strokeWidth: 2.8,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                          color: const Color(0xFF091911),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF091911),
                        size: 18,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
