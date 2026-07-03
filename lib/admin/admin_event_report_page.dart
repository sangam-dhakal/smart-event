import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class AdminEventReportPage extends StatelessWidget {
  final String eventId;
  final Map<String, dynamic> eventData;

  const AdminEventReportPage({
    super.key,
    required this.eventId,
    required this.eventData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Event Report", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            Text(eventData['title'] ?? 'Unknown Event', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── EVENT DETAILS ───
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Host: ${eventData['organizer'] ?? 'N/A'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Gap(4.h),
                    Text("Venue: ${eventData['venue'] ?? 'N/A'}"),
                    Gap(4.h),
                    Text("Capacity: ${eventData['maxCapacity'] ?? 'Unlimited'}"),
                  ],
                ),
              ),
            ),
            Gap(16.h),

            // ─── PARTICIPANT STATS ───
            Text("Participant Analytics", style: Theme.of(context).textTheme.titleLarge),
            Gap(8.h),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('participants')
                  .where('eventId', isEqualTo: eventId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs;
                final totalRequests = docs.length;
                final accepted = docs.where((d) => (d.data() as Map)['status'] == 'accepted').toList();
                final attended = accepted.where((d) => (d.data() as Map)['attendance'] == true).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _StatCard(label: "Requests", value: totalRequests.toString(), color: AppColors.primary),
                        Gap(8.w),
                        _StatCard(label: "Accepted", value: accepted.length.toString(), color: AppColors.info),
                        Gap(8.w),
                        _StatCard(label: "Attended", value: attended.length.toString(), color: AppColors.success),
                      ],
                    ),
                    Gap(24.h),

                    // ─── ATTENDEE LOG ───
                    Text("Registered Users Log", style: Theme.of(context).textTheme.titleLarge),
                    Gap(8.h),
                    if (docs.isEmpty)
                      const Text("No users have registered yet.", style: TextStyle(color: AppColors.textSecondary))
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final pData = docs[index].data() as Map<String, dynamic>;
                          final name = pData['name'] ?? 'Unknown';
                          final email = pData['email'] ?? '';
                          final phone = pData['phone'] ?? 'N/A';
                          final loc = pData['location'] ?? 'N/A';
                          final status = pData['status'] ?? '';
                          final isPresent = pData['attendance'] == true;
                          
                          String timeStr = "Not Checked In";
                          if (isPresent && pData['checkInTime'] != null) {
                            final ts = (pData['checkInTime'] as Timestamp).toDate();
                            timeStr = "In: ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}";
                          }

                          return Card(
                            elevation: 1,
                            margin: EdgeInsets.only(bottom: 8.h),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isPresent ? AppColors.success.withAlpha(40) : Colors.grey.shade200,
                                child: Icon(Icons.person, color: isPresent ? AppColors.success : Colors.grey),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("$email\n$phone • $loc\n$timeStr"),
                              isThreeLine: true,
                              trailing: Chip(
                                label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                backgroundColor: status == 'accepted' ? AppColors.success.withAlpha(30) : AppColors.warning.withAlpha(30),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
            Gap(24.h),

            // ─── FEEDBACK LIST ───
            Text("Event Feedback", style: Theme.of(context).textTheme.titleLarge),
            Gap(8.h),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('feedbacks')
                  .where('eventId', isEqualTo: eventId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                // FIX: Local sort
                final feedbacks = snapshot.data!.docs.toList();
                feedbacks.sort((a, b) {
                  final aTime = (a.data() as Map)['timestamp'] as Timestamp?;
                  final bTime = (b.data() as Map)['timestamp'] as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });
                
                if (feedbacks.isEmpty) return const Text("No feedback received yet.", style: TextStyle(color: AppColors.textSecondary));

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: feedbacks.length,
                  itemBuilder: (context, index) {
                    final fb = feedbacks[index].data() as Map<String, dynamic>;
                    final rating = fb['rating'] ?? 0;
                    return Card(
                      margin: EdgeInsets.only(bottom: 8.h),
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(fb['participantName'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Row(
                              children: List.generate(5, (i) => Icon(
                                i < rating ? Icons.star : Icons.star_border,
                                size: 16,
                                color: AppColors.accent,
                              )),
                            )
                          ],
                        ),
                        subtitle: Text(fb['review'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold, color: color)),
            Gap(4.h),
            Text(label, style: TextStyle(fontSize: 12.sp, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}