import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/event/feedback_service.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class FeedbackListPage extends StatelessWidget {
  final String eventId;
  final String eventTitle;

  const FeedbackListPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  Widget build(BuildContext context) {
    final FeedbackService service = FeedbackService();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Event Feedback", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            Text(eventTitle, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.getEventFeedback(eventId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("An error occurred loading feedback."));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.speaker_notes_off, size: 72.sp, color: AppColors.border),
                  Gap(16.h),
                  Text("No feedback yet.", style: TextStyle(fontSize: 18.sp, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                  Gap(8.h),
                  Text("Participants must attend the event to leave a review.", style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                ],
              ),
            );
          }

          // Calculate Average Rating
          double totalRating = 0;
          for (var doc in docs) {
            totalRating += (doc.data()['rating'] as num).toDouble();
          }
          final double avgRating = totalRating / docs.length;

          return Column(
            children: [
              // Summary Header
              Container(
                color: AppColors.surface,
                padding: EdgeInsets.all(24.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        Text(
                          avgRating.toStringAsFixed(1),
                          style: TextStyle(fontSize: 48.sp, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        Row(
                          children: List.generate(5, (index) {
                            return Icon(
                              index < avgRating.round() ? Icons.star : Icons.star_border,
                              color: AppColors.accent,
                              size: 28.sp,
                            );
                          }),
                        ),
                        Gap(8.h),
                        Text("${docs.length} Reviews", style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),

              // Feedback List
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.all(16.w),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final name = data['participantName'] ?? 'Anonymous';
                    final review = data['review'] ?? '';
                    final rating = (data['rating'] as num).toInt();
                    final timestamp = data['timestamp'] as Timestamp?;
                    
                    String dateStr = '';
                    if (timestamp != null) {
                      final d = timestamp.toDate();
                      dateStr = "${d.day}/${d.month}/${d.year}";
                    }

                    return Card(
                      margin: EdgeInsets.only(bottom: 12.h),
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16.r,
                                      backgroundColor: AppColors.primary.withAlpha(30),
                                      child: Text(name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                    ),
                                    Gap(12.w),
                                    Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp, color: AppColors.textPrimary)),
                                  ],
                                ),
                                Text(dateStr, style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Gap(12.h),
                            Row(
                              children: List.generate(5, (i) => Icon(
                                i < rating ? Icons.star : Icons.star_border,
                                size: 18.sp,
                                color: AppColors.accent,
                              )),
                            ),
                            if (review.isNotEmpty) ...[
                              Gap(12.h),
                              Text(review, style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary, height: 1.4)),
                            ]
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}