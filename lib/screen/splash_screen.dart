import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_event_app/admin/super_admin_dashboard.dart';
import 'package:smart_event_app/admin/super_admin_service.dart';
import 'package:smart_event_app/auth/login_page.dart';
import 'package:smart_event_app/auth/role_selection_page.dart';
import 'package:smart_event_app/event/event_page.dart';
import 'package:smart_event_app/participant/participant_pages.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Image pahila cache garne — black flash hatauna
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage("assets/image/smart.png"), context);
    });

    _routeUser();
  }

  Future<void> _routeUser() async {
    // Wait for splash animation
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    // AUTH CACHING: If user is already logged in, route directly to their dashboard.
    // Firestore native offline persistence will fetch this from cache if no internet.
    if (user != null) {
      try {
        // 1. ALWAYS Verify Management status against backend
        String? managementRole;
        try {
          managementRole = await SuperAdminService()
              .checkManagementRole()
              .timeout(const Duration(seconds: 4));
        } catch (err) {
          debugPrint("🔴 Offline or timeout when verifying super admin: $err");
          // FALLBACK: Read from cache if user opens app without internet
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getBool('isManagement') == true) {
            managementRole = prefs.getString('managementRole');
          }
        }

        if (managementRole != null && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SuperAdminDashboard(role: managementRole!),
            ),
          );
          return;
        }

        // 2. Fetch User Object
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.serverAndCache));

        if (doc.exists) {
          final role = doc.data()?['role'] ?? '';
          if (!mounted) return;

          if (role == 'organizer' || role == 'admin') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const EventPage()),
            );
            return;
          } else if (role == 'participant') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ParticipantPages()),
            );
            return;
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint("Offline Auth Routing Error (Falling back to login): $e");
      }
    }

    // Fallback: Go to Login Page
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Image container
              Container(
                height: 300.h,
                width: 300.w,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 15.r,
                      offset: Offset(0.w, 8.h),
                    ),
                  ],
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20.r),
                  child: Image.asset(
                    "assets/image/smart.png",
                    fit: BoxFit.cover,

                    //Prevent crash if image missing vayo vane
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.error, size: 100);
                    },
                  ),
                ),
              ),

              const Gap(10),

              AnimatedTextKit(
                animatedTexts: [
                  ColorizeAnimatedText(
                    "SMART EVENT",
                    textStyle: TextStyle(
                      fontSize: 24.r,
                      fontWeight: FontWeight.bold,
                    ),
                    colors: [AppColors.primary, AppColors.secondary, AppColors.textPrimary],
                  ),
                ],
                isRepeatingAnimation: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}