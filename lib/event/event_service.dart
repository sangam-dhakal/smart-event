import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EventService {
  final _db = FirebaseFirestore.instance;

  // Delete Event (Fix: Also sweeps up all related participants and orphaned notifications so ghost data is removed)
  Future<void> deleteEvent(String id) async {
    final user = FirebaseAuth.instance.currentUser;

    final doc = await _db.collection('events').doc(id).get();

    if (doc.data()?['organizerId'] != user?.uid) {
      throw Exception("You are not allowed to delete this event");
    }

    // Safely delete the event first
    await _db.collection('events').doc(id).delete();

    // Sweep participants explicitly associated with this event to demolish ghost QR tickets
    final parts = await _db.collection('participants').where('eventId', isEqualTo: id).get();
    for (var p in parts.docs) {
      await p.reference.delete();
    }
    
    // Sweep orphaned notifications explicitly tied to this event
    final notifs = await _db.collection('notifications').where('eventId', isEqualTo: id).get();
    for (var n in notifs.docs) {
      await n.reference.delete();
    }
  }

  // Update Event
  Future<void> updateEvent(String id, Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;

    final doc = await _db.collection('events').doc(id).get();

    if (doc.data()?['organizerId'] != user?.uid) {
      throw Exception("You are not allowed to edit this event");
    }

    // Force the event back into a pending verification status as requested
    data['approvalStatus'] = 'pending';
    
    await _db.collection('events').doc(id).update(data);

    final participants = await _db
        .collection('participants')
        .where('eventId', isEqualTo: id)
        .get();

    final batch = _db.batch();
    for (final participant in participants.docs) {
      batch.update(participant.reference, {
        'eventTitle': data['title'],
        'eventDate': data['date'],
      });
    }
    await batch.commit();

    await _db.collection("notifications").add({
      "title": "Event Pending Verification",
      "body": "Your updated event '${data['title']}' was sent to the Admin for approval.",
      "time": FieldValue.serverTimestamp(),
      "isRead": false,
      "eventId": id,
      "targetUserId": user?.uid,
      "targetRole": "organizer",
    });
  }

  // CREATE EVENT
  Future<String> createEvent(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not logged in");
    }
    // Ensure 'date' is a Timestamp
    final eventDate = data['date'];
    Timestamp finalDate;

    if (eventDate is String) {
      finalDate = Timestamp.fromDate(DateTime.parse(eventDate));
    } else if (eventDate is DateTime) {
      finalDate = Timestamp.fromDate(eventDate);
    } else if (eventDate is Timestamp) {
      finalDate = eventDate;
    } else {
      throw Exception("Invalid date format");
    }
    final docRef = await _db.collection('events').add({
      ...data, // all fields from UI
      'date': finalDate,
      'createdAt': Timestamp.now(),
      'organizerId': user.uid,
      'approvalStatus': 'pending', // Events must be verified by Super Admin first
    });
    
    await FirebaseFirestore.instance.collection("notifications").add({
      "title": "New Event Pending Verification",
      "body": "Your event '${data['title']}' was sent to the Admin for approval.",
      "time": FieldValue.serverTimestamp(),
      "isRead": false,
      "eventId": docRef.id,
      "targetUserId": user.uid, 
      "targetRole": "organizer", // Keep this notification strictly inside the organizer dashboard
    });
    return docRef.id;
  }

  // READ EVENTS
  Stream<QuerySnapshot<Map<String, dynamic>>> getEvents() {
    return _db
        .collection('events')
        .orderBy('date', descending: false) // sort by event date
        .snapshots();
  }
}
