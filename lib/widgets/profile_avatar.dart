import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

class ProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final bool showEditIcon;
  final VoidCallback? onEditTap;

  const ProfileAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 24,
    this.borderColor,
    this.borderWidth = 1.5,
    this.onTap,
    this.showEditIcon = false,
    this.onEditTap,
  });

  static const Color primaryGold = Color(0xFFC9A227);
  static const Color lightGold = Color(0xFFFFE082);
  static const Color primaryGreen = Color(0xFF123222);

  static ImageProvider? getImageProvider(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (trimmed.startsWith('data:image') && trimmed.contains('base64,')) {
      try {
        final base64String = trimmed.split('base64,').last;
        return MemoryImage(base64Decode(base64String));
      } catch (e) {
        debugPrint("Error decoding base64 image: $e");
        return null;
      }
    } else if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return NetworkImage(trimmed);
    } else {
      // Try raw base64
      try {
        return MemoryImage(base64Decode(trimmed));
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = getImageProvider(imageUrl);
    final initial = name.trim().isNotEmpty
        ? name.trim().substring(0, 1).toUpperCase()
        : 'U';
    final effectiveBorderColor = borderColor ?? primaryGold;
    final double diameter = radius * 2;

    Widget avatarWidget = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: effectiveBorderColor, width: borderWidth),
        gradient: imageProvider == null
            ? const LinearGradient(
                colors: [Color(0xFF1A452B), Color(0xFF0F2C1E), Color(0xFF091911)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        image: imageProvider != null
            ? DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: imageProvider == null
          ? Text(
              initial,
              style: GoogleFonts.montserrat(
                color: lightGold,
                fontSize: radius * 0.85,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );

    if (onTap != null) {
      avatarWidget = GestureDetector(
        onTap: onTap,
        child: avatarWidget,
      );
    }

    if (!showEditIcon) {
      return avatarWidget;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWidget,
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: onEditTap ?? onTap,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: primaryGold,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF091911), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 14,
                color: Color(0xFF091911),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Helper to pick an image or take photo or enter URL.
  /// Returns the base64 string or image URL, or empty string `""` to remove photo, or null if cancelled.
  static Future<String?> pickImageSource(
    BuildContext context, {
    String? currentImageUrl,
  }) async {
    final picker = ImagePicker();

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1F15),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: primaryGold.withValues(alpha: 0.4),
            width: 1.2,
          ),
        ),
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
                const Icon(Icons.account_circle_rounded,
                    color: primaryGold, size: 22),
                const SizedBox(width: 8),
                Text(
                  "PROFILE PICTURE",
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: lightGold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryGreen,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: primaryGold, width: 1),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: primaryGold, size: 20),
              ),
              title: Text(
                "Take Photo (Camera)",
                style: GoogleFonts.rajdhani(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              subtitle: Text(
                "Capture new picture from device camera",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
              onTap: () async {
                try {
                  final XFile? photo = await picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 500,
                    maxHeight: 500,
                    imageQuality: 80,
                  );
                  if (photo != null) {
                    final bytes = await photo.readAsBytes();
                    final base64Str =
                        "data:image/jpeg;base64,${base64Encode(bytes)}";
                    if (sheetCtx.mounted) {
                      Navigator.pop(sheetCtx, base64Str);
                    }
                    return;
                  }
                } catch (e) {
                  debugPrint("Camera error: $e");
                }
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryGreen,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: primaryGold, width: 1),
                ),
                child: const Icon(Icons.photo_library_rounded,
                    color: primaryGold, size: 20),
              ),
              title: Text(
                "Choose from Gallery",
                style: GoogleFonts.rajdhani(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              subtitle: Text(
                "Pick an existing photo from gallery / files",
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
              onTap: () async {
                try {
                  final XFile? photo = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 500,
                    maxHeight: 500,
                    imageQuality: 80,
                  );
                  if (photo != null) {
                    final bytes = await photo.readAsBytes();
                    final base64Str =
                        "data:image/jpeg;base64,${base64Encode(bytes)}";
                    if (sheetCtx.mounted) {
                      Navigator.pop(sheetCtx, base64Str);
                    }
                    return;
                  }
                } catch (e) {
                  debugPrint("Gallery error: $e");
                }
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              },
            ),
            if (currentImageUrl != null && currentImageUrl.trim().isNotEmpty) ...[
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent, width: 1),
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 20),
                ),
                title: Text(
                  "Remove Profile Picture",
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                  ),
                ),
                subtitle: Text(
                  "Revert back to default initials avatar",
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx, "");
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
