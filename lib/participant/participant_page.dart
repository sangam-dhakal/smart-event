import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/theme/app_colors.dart';
import 'participant_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ParticipantPage extends StatefulWidget {
  final String eventId;
  final String organizerId;

  const ParticipantPage({
    super.key,
    required this.eventId,
    required this.organizerId,
  });

  @override
  State<ParticipantPage> createState() => _ParticipantPageState();
}

class _ParticipantPageState extends State<ParticipantPage> {
  final service = ParticipantService();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController(); // NEW
  final locationController = TextEditingController(); // NEW

  Map<String, dynamic>? participantData;
  bool isLoading = false;
  bool isFetching = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1. Fetch user data to pre-fill form
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final uData = userDoc.data()!;
        nameController.text = uData['name'] ?? "";
        emailController.text = uData['email'] ?? "";
      }

      // 2. Check existing participant status
      final pData = await service.getParticipant(userId: user.uid, eventId: widget.eventId);
      setState(() {
        participantData = pData;
      });
    } catch (e) {
      debugPrint("Failed to load participant page data: $e");
    } finally {
      setState(() {
        isFetching = false;
      });
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> _applyForEvent() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (nameController.text
        .trim()
        .isEmpty ||
        emailController.text
            .trim()
            .isEmpty ||
        phoneController.text
            .trim()
            .isEmpty ||
        locationController.text
            .trim()
            .isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("All fields are required"), backgroundColor: AppColors.error));
      return;
    }

    setState(() => isLoading = true);

    try {
      await service.joinEvent(
        userId: user.uid,
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        phone: phoneController.text.trim(),
        location: locationController.text.trim(),
        eventId: widget.eventId,
        organizerId: widget.organizerId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request sent! You'll be notified when accepted."),
            backgroundColor: AppColors.success),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _respondToInvite(String status) async {
    if (participantData == null) return;

    setState(() => isLoading = true);
    try {
      await service.respondToInvite(participantData!['docId'], status);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(status == 'accepted' ? "Invitation Accepted!" : "Invitation Declined."),
            backgroundColor: status == 'accepted' ? AppColors.success : AppColors.error
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Join Event")),
      body: isFetching
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: EdgeInsets.all(24.w),
        child: _buildBodyContent(),
      ),
    );
  }

  Widget _buildBodyContent() {
    if (participantData == null) {
      // ----------------------------------------------------
      // STATE 1: EXPLORE (Not in event yet) -> APPLY FORM
      // ----------------------------------------------------
      return Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Application Form", style: Theme
                  .of(context)
                  .textTheme
                  .headlineMedium),
              Gap(8.h),
              Text("Fill out the details below to request a ticket.", style: Theme
                  .of(context)
                  .textTheme
                  .bodyMedium),
              Gap(24.h),
              TextFormField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: "Full Name", prefixIcon: Icon(Icons.person)),
              ),
              Gap(16.h),
              TextFormField(
                controller: emailController,
                readOnly: true, // Non-editable as requested
                style: const TextStyle(color: AppColors.textSecondary),
                decoration: InputDecoration(
                  labelText: "Email Address",
                  prefixIcon: const Icon(Icons.email, color: AppColors.textSecondary),
                  fillColor: AppColors.textSecondary.withAlpha(20),
                ),
              ),
              Gap(16.h),
              TextFormField(
                controller: phoneController,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: "Phone Number", prefixIcon: Icon(Icons.phone)),
              ),
              Gap(16.h),
              TextFormField(
                controller: locationController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                    labelText: "Your Location / City", prefixIcon: Icon(Icons.location_city)),
              ),
              Gap(32.h),
              ElevatedButton(
                onPressed: isLoading ? null : _applyForEvent,
                child: isLoading
                    ? const SizedBox(width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Submit Request"),
              ),
            ],
          ),
        ),
      );
    }

    final status = participantData!['status'];
    final type = participantData!['type'] ?? 'unknown';

    // ----------------------------------------------------
    // STATE 2: INVITED -> ACCEPT/DECLINE
    // ----------------------------------------------------
    if (status == 'invited') {
      return Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline, size: 72.sp, color: AppColors.warning),
              Gap(16.h),
              Text("You're Invited!", style: Theme
                  .of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.primary)),
              Gap(8.h),
              Text("The organizer has specially invited you to attend this event.",
                  textAlign: TextAlign.center, style: Theme
                      .of(context)
                      .textTheme
                      .bodyMedium),
              Gap(32.h),
              if (isLoading)
                const CircularProgressIndicator()
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error)),
                        onPressed: () => _respondToInvite('rejected'),
                        child: const Text("Decline"),
                      ),
                    ),
                    Gap(12.w),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                        onPressed: () => _respondToInvite('accepted'),
                        child: const Text("Accept"),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    // ----------------------------------------------------
    // STATE 3: PENDING REQUEST
    // ----------------------------------------------------
    if (status == 'pending') {
      return Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 72, color: AppColors.warning),
              Gap(16.h),
              Text("Request Pending", style: Theme
                  .of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.primary)),
              Gap(8.h),
              Text(
                  "Your request to join is awaiting organizer approval. You will be notified once accepted.",
                  textAlign: TextAlign.center, style: Theme
                  .of(context)
                  .textTheme
                  .bodyMedium),
            ],
          ),
        ),
      );
    }

    // ----------------------------------------------------
    // STATE 4: ACCEPTED (Ticket Ready)
    // ----------------------------------------------------
    if (status == 'accepted') {
      return Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 72, color: AppColors.success),
              Gap(16.h),
              Text("You're In!", style: Theme
                  .of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.success)),
              Gap(8.h),
              Text(
                  type == 'invite'
                      ? "You have accepted the invitation."
                      : "Your request was approved.",
                  textAlign: TextAlign.center, style: Theme
                  .of(context)
                  .textTheme
                  .bodyMedium
              ),
              Gap(32.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code),
                  label: const Text("Go to QR Tickets"),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ----------------------------------------------------
    // STATE 5: REJECTED
    // ----------------------------------------------------
    if (status == 'rejected') {
      return Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cancel_outlined, size: 72, color: AppColors.error),
              Gap(16.h),
              Text(type == 'invite' ? "Invitation Declined" : "Request Denied", style: Theme
                  .of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.error)),
              Gap(8.h),
              Text("You are not attending this event.", textAlign: TextAlign.center, style: Theme
                  .of(context)
                  .textTheme
                  .bodyMedium),
            ],
          ),
        ),
      );
    }

    return const SizedBox();
  }
}