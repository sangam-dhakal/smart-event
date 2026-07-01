import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/event/feedback_service.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class FeedbackFormPage extends StatefulWidget {
  final String eventId;
  final String participantName;

  const FeedbackFormPage({
    super.key,
    required this.eventId,
    required this.participantName,
  });

  @override
  State<FeedbackFormPage> createState() => _FeedbackFormPageState();
}

class _FeedbackFormPageState extends State<FeedbackFormPage> {
  final FeedbackService _feedbackService = FeedbackService();
  final TextEditingController _reviewController = TextEditingController();
  
  int _rating = 0;
  bool _isLoading = false;
  bool _isFetching = true;

  @override
  void initState() {
    super.initState();
    _checkExistingFeedback();
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final existing = await _feedbackService.getUserFeedback(
        eventId: widget.eventId,
        userId: user.uid,
      );

      if (existing != null) {
        setState(() {
          _rating = (existing['rating'] as num).toInt();
          _reviewController.text = existing['review'] ?? '';
        });
      }
    } catch (e) {
      debugPrint("Error fetching existing feedback: $e");
    } finally {
      setState(() => _isFetching = false);
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a star rating"), backgroundColor: AppColors.error),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      await _feedbackService.submitFeedback(
        eventId: widget.eventId,
        userId: user.uid,
        participantName: widget.participantName,
        rating: _rating,
        review: _reviewController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Thank you for your feedback!"), backgroundColor: AppColors.success),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Rate Event"),
      ),
      body: _isFetching 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: EdgeInsets.all(24.w),
            child: Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
                child: Column(
                  children: [
                    Icon(Icons.stars, size: 72.sp, color: AppColors.accent),
                    Gap(16.h),
                    Text(
                      "How was the event?",
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.primary),
                    ),
                    Gap(8.h),
                    Text(
                      "Your feedback is only visible to the event organizer.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Gap(30.h),
                    
                    // Custom Star Rating Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(
                            index < _rating ? Icons.star : Icons.star_border,
                            color: AppColors.accent,
                            size: 36.sp,
                          ),
                          onPressed: () {
                            setState(() => _rating = index + 1);
                          },
                        );
                      }),
                    ),
                    Gap(30.h),

                    // Written Review
                    TextField(
                      controller: _reviewController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: "Write a review (Optional)",
                      ),
                    ),
                    Gap(32.h),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text("Submit Feedback"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}