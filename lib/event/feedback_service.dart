import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackService {
  final _db = FirebaseFirestore.instance;

  // Submit or update a review
  Future<void> submitFeedback({
    required String eventId,
    required String userId,
    required String participantName,
    required int rating,
    required String review,
  }) async {
    final docId = "${userId}_$eventId";
    
    await _db.collection('feedbacks').doc(docId).set({
      'eventId': eventId,
      'userId': userId,
      'participantName': participantName,
      'rating': rating,
      'review': review,
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Get a specific user's feedback for an event (to pre-fill if they want to edit)
  Future<Map<String, dynamic>?> getUserFeedback({
    required String eventId,
    required String userId,
  }) async {
    final docId = "${userId}_$eventId";
    final doc = await _db.collection('feedbacks').doc(docId).get();
    
    if (doc.exists) {
      return doc.data();
    }
    return null;
  }

  // Stream all feedback for an event (Organizer view)
  Stream<QuerySnapshot<Map<String, dynamic>>> getEventFeedback(String eventId) {
    return _db
        .collection('feedbacks')
        .where('eventId', isEqualTo: eventId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}