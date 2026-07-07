import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/event/event_page.dart';
import 'package:smart_event_app/participant/participant_pages.dart';
import 'package:smart_event_app/providers/providers.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class RoleSelectionPage extends ConsumerStatefulWidget {
  const RoleSelectionPage({super.key});

  @override
  ConsumerState<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends ConsumerState<RoleSelectionPage> {
  bool isLoading = false;

  Future<void> _selectRole(String role) async {
    setState(() => isLoading = true);
    try {
      final auth = ref.read(authProvider);
      final uid = auth.currentUserId;

      if (uid != null) {
        await auth.updateRole(uid, role);

        if (!mounted) return;

        if (role == 'organizer') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const EventPage()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ParticipantPages()),
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "Welcome! Login Successful",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.r),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Account Setup"),
      ),
      body: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Welcome!",
              textAlign: TextAlign.center,
              style: Theme
                  .of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(
                color: AppColors.primary,
              ),
            ),
            Gap(16.h),
            Text(
              "Please choose how you want to use the app.\nThis selection determines your dashboard.",
              textAlign: TextAlign.center,
              style: Theme
                  .of(context)
                  .textTheme
                  .bodyMedium,
            ),
            Gap(40.h),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ...[
                ElevatedButton.icon(
                  // Uses default AppTheme elevated button style (Primary color)
                  icon: const Icon(Icons.business_center),
                  onPressed: () => _selectRole('organizer'),
                  label: const Text("I am an Organizer"),
                ),
                Gap(20.h),
                ElevatedButton.icon(
                  // Override background color specifically for the participant button
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                  ),
                  icon: const Icon(Icons.person),
                  onPressed: () => _selectRole('participant'),
                  label: const Text("I am a Participant"),
                ),
              ]
          ],
        ),
      ),
    );
  }
}