import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
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
    super.dispose();
  }

  Future<void> _applyForEvent() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (nameController.text.trim().isEmpty || emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All fields are required")));
      return;
    }

    setState(() => isLoading = true);

    try {
      await service.joinEvent(
        userId: user.uid,
        name: nameController.text,
        email: emailController.text,
        eventId: widget.eventId,
        organizerId: widget.organizerId,
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request sent! You'll be notified when accepted."), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
          backgroundColor: status == 'accepted' ? Colors.green : Colors.red
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.amber.shade50),
      body: isFetching
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(16.w),
              child: _buildBodyContent(),
            ),
      backgroundColor: Colors.brown.shade50,
    );
  }

  Widget _buildBodyContent() {
    if (participantData == null) {
      // ----------------------------------------------------
      // STATE 1: EXPLORE (Not in event yet) -> APPLY FORM
      // ----------------------------------------------------
      return SingleChildScrollView(
        child: Card(
          elevation: 5,
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              children: [
                Text("Apply for Event", style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Colors.indigo.shade600)),
                Gap(16.h),
                TextFormField(
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: "Name", border: OutlineInputBorder()),
                ),
                Gap(10.h),
                TextFormField(
                  controller: emailController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder()),
                ),
                Gap(16.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                      backgroundColor: Colors.teal.shade400,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    onPressed: isLoading ? null : _applyForEvent,
                    child: isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Submit Request"),
                  ),
                ),
              ],
            ),
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
        elevation: 5,
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline, size: 64.sp, color: Colors.amber.shade600),
              Gap(16.h),
              Text("You're Invited!", style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Colors.indigo.shade600)),
              Gap(8.h),
              Text("The organizer has specially invited you to attend this event.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade700)),
              Gap(24.h),
              if (isLoading)
                const CircularProgressIndicator()
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                        onPressed: () => _respondToInvite('rejected'),
                        child: const Text("Decline"),
                      ),
                    ),
                    Gap(12.w),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
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
        elevation: 5,
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top, size: 64.sp, color: Colors.orange.shade400),
              Gap(16.h),
              Text("Request Pending", style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, color: Colors.indigo.shade600)),
              Gap(8.h),
              Text("Your request to join is awaiting organizer approval. You will be notified once accepted.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade700)),
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
        elevation: 5,
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 64.sp, color: Colors.green.shade500),
              Gap(16.h),
              Text("You're In!", style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
              Gap(8.h),
              Text(
                type == 'invite' ? "You have accepted the invitation." : "Your request was approved.", 
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade700)
              ),
              Gap(24.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 12.h)),
                  icon: const Icon(Icons.qr_code),
                  label: const Text("Go to QR Tickets"),
                  onPressed: () {
                    // Pop this screen to go back to Home
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
        elevation: 5,
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cancel_outlined, size: 64.sp, color: Colors.red.shade400),
              Gap(16.h),
              Text(type == 'invite' ? "Invitation Declined" : "Request Denied", style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
              Gap(8.h),
              Text("You are not attending this event.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade700)),
            ],
          ),
        ),
      );
    }

    return const SizedBox();
  }
}