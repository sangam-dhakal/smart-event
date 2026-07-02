import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:smart_event_app/theme/app_colors.dart';
import '../participant/participant_service.dart';

class PendingParticipantsPage extends StatelessWidget {
  final String eventId;
  final String eventTitle;

  const PendingParticipantsPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  Widget build(BuildContext context) {
    final service = ParticipantService();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Join Requests",
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            Text(
              eventTitle,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.getPendingParticipants(eventId: eventId),
        builder: (context, snapshot) {
          // Loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Error
          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error: ${snapshot.error}",
                style: const TextStyle(color: AppColors.error),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // Empty state
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 72,
                    color: AppColors.border,
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    "No pending requests",
                    style: TextStyle(
                      fontSize: 18.sp,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    "All join requests will appear here",
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(16.w),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final name = data['name'] ?? 'Unknown';
              final email = data['email'] ?? '';
              final docId = doc.id;

              return Card(
                margin: EdgeInsets.only(bottom: 12.h),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 16.h,
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 24.r,
                        backgroundColor: AppColors.primary.withAlpha(20),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      SizedBox(width: 16.w),

                      // Name & Email
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              email,
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // REJECT button
                      _ActionButton(
                        icon: Icons.close,
                        color: AppColors.error,
                        tooltip: "Reject",
                        onTap: () => _handleAction(
                          context: context,
                          service: service,
                          docId: docId,
                          status: 'rejected',
                          name: name,
                          data: data,
                        ),
                      ),
                      SizedBox(width: 12.w),

                      // ACCEPT button
                      _ActionButton(
                        icon: Icons.check,
                        color: AppColors.success,
                        tooltip: "Accept",
                        onTap: () => _handleAction(
                          context: context,
                          service: service,
                          docId: docId,
                          status: 'accepted',
                          name: name,
                          data: data,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleAction({
    required BuildContext context,
    required ParticipantService service,
    required String docId,
    required String status,
    required String name,
    required Map<String, dynamic> data,
  }) async {
    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          status == 'accepted' ? "Accept Request?" : "Reject Request?",
          style: TextStyle(fontWeight: FontWeight.bold, color: status == 'accepted' ? AppColors.success : AppColors.error)
        ),
        content: Text(
          status == 'accepted'
              ? "Are you sure you want to accept $name?"
              : "Are you sure you want to reject $name?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: status == 'accepted' ? AppColors.success : AppColors.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(status == 'accepted' ? "Accept" : "Reject"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await service.updateParticipantStatus(docId: docId, status: status);
      
      // Trigger Push Notification via Vercel Backend
      final token = data['fcmToken'];
      final evId = data['eventId'];
      
      if (evId != null) {
        final title = status == 'accepted' ? 'Request Approved!' : 'Request Denied';
        final body = status == 'accepted' 
          ? 'Hi $name! Your request to join the event has been accepted. View your QR ticket now.'
          : 'Sorry $name, your request to join the event has been declined by the organizer.';
          
        // Background push notification call
        if (token != null) {
          service.sendPushNotification(
            targetFcmToken: token,
            title: title,
            body: body,
            eventId: evId,
          );
        }

        // Add IN-APP notification to Firestore targeting this specific participant
        if (data['userId'] != null && data['userId'].toString().isNotEmpty) {
          await FirebaseFirestore.instance.collection('notifications').add({
            'title': title,
            'body': body,
            'time': FieldValue.serverTimestamp(),
            'isRead': false,
            'eventId': evId,
            'targetUserId': data['userId'], 
            'targetRole': 'participant', // Prevent bleeding into Organizer tab
          });
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: status == 'accepted'
              ? AppColors.success
              : AppColors.error,
          content: Text(
            status == 'accepted'
                ? "$name accepted successfully!"
                : "$name rejected.",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      
      final msg = e.toString().replaceAll("Exception: ", "");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: msg.contains("Capacity Full") ? AppColors.warning : AppColors.error,
        )
      );
    }
  }
}

//Small reusable icon button widget
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Container(
           padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: color.withAlpha(100))
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}