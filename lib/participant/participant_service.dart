import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class ParticipantService {
  final _db = FirebaseFirestore.instance;

  // Generate unique QR ID
  String generateGuestId() {
    return "GUEST-${const Uuid().v4()}";
  }

  // Create consistent document ID
  String _docId(String userId, String eventId) {
    return "${userId}_$eventId";
  }

  // Helper to format date safely for emails
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "TBD";
    if (timestamp is Timestamp) {
      final d = timestamp.toDate();
      return "${d.day}/${d.month}/${d.year}";
    }
    return "TBD";
  }

  // ─── EMAILJS INTEGRATION ───
  Future<void> _sendEmailJs({
    required String eventId, // ADDED EVENT ID FOR DEEP LINKING
    required String toEmail,
    required String guestName,
    required String eventTitle,
    required String eventDate,
    required String eventTime,
    required String eventVenue,
    required String organizerName,
    required String organizationName,
  }) async {
    final serviceId = dotenv.env['EMAILJS_SERVICE_ID'] ?? '';
    final templateId = dotenv.env['EMAILJS_TEMPLATE_ID'] ?? '';
    final publicKey = dotenv.env['EMAILJS_PUBLIC_KEY'] ?? '';
    final privateKey = dotenv.env['EMAILJS_PRIVATE_KEY'] ?? '';

    if (serviceId.isEmpty || templateId.isEmpty || publicKey.isEmpty) {
      debugPrint("EmailJS keys missing in .env file. Email not sent.");
      return;
    }

    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    final Map<String, dynamic> payload = {
      'service_id': serviceId,
      'template_id': templateId,
      'user_id': publicKey,
      'template_params': {
        'event_id': eventId, // Sent to template for {{event_id}}
        'to_email': toEmail,
        'guest_name': guestName,
        'event_title': eventTitle,
        'event_date': eventDate,
        'event_time': eventTime,
        'event_venue': eventVenue,
        'organizer_name': organizerName,
        'organization_name': organizationName,
      },
    };

    if (privateKey.isNotEmpty) {
      payload['accessToken'] = privateKey;
    }

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        debugPrint("EmailJS Failed: ${response.body}");
      } else {
        debugPrint("Email sent successfully to $toEmail");
      }
    } catch (e) {
      debugPrint("EmailJS Exception: $e");
    }
  }

  // ─── PUSH NOTIFICATION (VERCEL BACKEND) ───
  Future<void> sendPushNotification({
    required String targetFcmToken,
    required String title,
    required String body,
    required String eventId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Request the highly secure, short-lived ID Token from Firebase Auth
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final String baseUrl =
          dotenv.env['API_BASE_URL'] ?? 'https://smart-event-api.vercel.app';
      final String cleanBaseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      final url = Uri.parse('$cleanBaseUrl/api/send-notification');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken', // Sent to Vercel for verification
        },
        body: jsonEncode({
          'token': targetFcmToken,
          'title': title,
          'body': body,
          'eventId': eventId,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint("Push Notification Failed: ${response.body}");
      } else {
        debugPrint("Push Notification Sent Successfully!");
      }
    } catch (e) {
      debugPrint("Error triggering push notification: $e");
    }
  }

  // JOIN EVENT (NO DUPLICATES + NULL SAFE) - EXPLORE REQUESTS
  Future<String> joinEvent({
    required String userId,
    required String name,
    required String email,
    required String eventId,
    required String organizerId,
    String? phone,
    String? location,
  }) async {
    final fcmToken = await FirebaseMessaging.instance.getToken();

    if (eventId.isEmpty) {
      throw Exception("Event id is missing or invalid");
    }

    final eventDoc = await _db.collection('events').doc(eventId).get();
    final eventData = eventDoc.data() ?? {};

    final docRef = _db.collection('participants').doc(_docId(userId, eventId));
    final snapshot = await docRef.get();

    // Generate notification specifically for the ORGANIZER dashboard
    await _db.collection('notifications').add({
      'title': 'New Join Request',
      'body': '$name wants to join ${eventData['title'] ?? 'your event'}.',
      'time': FieldValue.serverTimestamp(),
      'isRead': false,
      'eventId': eventId,
      'targetUserId': organizerId,
      'targetRole': 'organizer', // Prevent bleeding into participant tab
    });

    if (snapshot.exists) {
      final data = snapshot.data();
      await docRef.update({
        'fcmToken': fcmToken,
        'status': 'pending',
        'type': 'request',
        'name': name,
        'email': email,
        if (phone != null) 'phone': phone,
        if (location != null) 'location': location,
        'eventTitle': eventData['title'] ?? 'Unknown Event',
        'eventDate': eventData['date'],
      });
      await FirebaseMessaging.instance.subscribeToTopic("participants");

      if (data == null) {
        final newGuestId = generateGuestId();
        await docRef.set({
          'userId': userId,
          'name': name,
          'email': email,
          if (phone != null) 'phone': phone,
          if (location != null) 'location': location,
          'fcmToken': fcmToken,
          'eventId': eventId,
          'guestId': newGuestId,
          'attendance': false,
          'organizerId': organizerId,
          'status': 'pending',
          'type': 'request',
          'eventTitle': eventData['title'] ?? 'Unknown Event',
          'eventDate': eventData['date'],
          'createdAt': FieldValue.serverTimestamp(),
        });
        return newGuestId;
      }

      final guestId = data['guestId'];
      if (guestId is String && guestId.isNotEmpty) {
        return guestId;
      }

      final newGuestId = generateGuestId();
      await docRef.update({'guestId': newGuestId});
      return newGuestId;
    }

    final guestId = generateGuestId();
    await docRef.set({
      'userId': userId,
      'name': name,
      'email': email,
      if (phone != null) 'phone': phone,
      if (location != null) 'location': location,
      'fcmToken': fcmToken,
      'eventId': eventId,
      'guestId': guestId,
      'attendance': false,
      'organizerId': organizerId,
      'status': 'pending',
      'type': 'request',
      'eventTitle': eventData['title'] ?? 'Unknown Event',
      'eventDate': eventData['date'],
      'createdAt': FieldValue.serverTimestamp(),
    });

    return guestId;
  }

  // BATCH IMPORT INVITEES (CSV) WITH OPTIONAL EMAIL
  Future<void> importInvitees({
    required String eventId,
    required String eventTitle,
    required String organizerId,
    required List<Map<String, String>> guests,
    required bool sendEmail,
  }) async {
    final batch = _db.batch();

    final eventDoc = await _db.collection('events').doc(eventId).get();
    final eventData = eventDoc.data() ?? {};

    final eDate = _formatDate(eventData['date']);
    final eTime = eventData['time'] ?? 'TBD';
    final eVenue = eventData['venue'] ?? 'TBD';
    final eOrganizer = eventData['organizer'] ?? 'an Organizer';
    final eOrganization = eventData['organization'] ?? 'an Organization';

    for (var guest in guests) {
      final email = guest['email']!.trim();
      final cleanEmail = email.toLowerCase();
      final name = guest['name']!.trim();
      final department = guest['department'] ?? '';

      final inviteeDocId =
          "INVITE_${cleanEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_$eventId";
      final ref = _db.collection('participants').doc(inviteeDocId);

      final guestId = generateGuestId();

      // Check for user robustly to avoid case-mismatch bugs
      var userQuery = await _db
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty && cleanEmail != email) {
        userQuery = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
      }

      String assignedUserId = '';
      if (userQuery.docs.isNotEmpty) {
        assignedUserId = userQuery.docs.first.id;
      }

      batch.set(ref, {
        'userId': assignedUserId,
        'name': name,
        'email': cleanEmail, // Safely save as lowercase for easier linking
        'department': department, // Save specific corporate department mapping
        'eventId': eventId,
        'guestId': guestId,
        'attendance': false,
        'organizerId': organizerId,
        'status': 'invited',
        'type': 'invite',
        'eventTitle': eventTitle,
        'eventDate': eventData['date'],
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (sendEmail) {
        _sendEmailJs(
          eventId: eventId,
          toEmail: email,
          guestName: name,
          eventTitle: eventTitle,
          eventDate: eDate,
          eventTime: eTime,
          eventVenue: eVenue,
          organizerName: eOrganizer,
          organizationName: eOrganization,
        );
      }
    }

    await batch.commit();
  }

  // SINGLE GUEST INVITE (VIP / Special Appearance) WITH OPTIONAL EMAIL
  Future<void> inviteSingleGuest({
    required String eventId,
    required String eventTitle,
    required String organizerId,
    required String name,
    required String email,
    required bool sendEmail,
  }) async {
    final eventDoc = await _db.collection('events').doc(eventId).get();
    final eventData = eventDoc.data() ?? {};

    final cleanEmail = email.trim().toLowerCase();
    final exactEmail = email.trim();
    final cleanName = name.trim();

    final inviteeDocId =
        "INVITE_${cleanEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_$eventId";
    final ref = _db.collection('participants').doc(inviteeDocId);

    final existingDoc = await ref.get();
    if (existingDoc.exists) {
      throw Exception("This guest has already been invited to this event.");
    }

    final batch = _db.batch();
    final guestId = generateGuestId();

    // Fallback checks for user to ensure invitation links correctly regardless of casing
    var userQuery = await _db
        .collection('users')
        .where('email', isEqualTo: cleanEmail)
        .limit(1)
        .get();

    if (userQuery.docs.isEmpty && cleanEmail != exactEmail) {
      userQuery = await _db
          .collection('users')
          .where('email', isEqualTo: exactEmail)
          .limit(1)
          .get();
    }

    String assignedUserId = '';
    if (userQuery.docs.isNotEmpty) {
      assignedUserId = userQuery.docs.first.id;
    }

    batch.set(ref, {
      'userId': assignedUserId,
      'name': cleanName,
      'email': cleanEmail, // Safely save as lowercase for easier linking
      'eventId': eventId,
      'guestId': guestId,
      'attendance': false,
      'organizerId': organizerId,
      'status': 'invited',
      'type': 'invite',
      'eventTitle': eventTitle,
      'eventDate': eventData['date'],
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    if (sendEmail) {
      final eDate = _formatDate(eventData['date']);
      final eTime = eventData['time'] ?? 'TBD';
      final eVenue = eventData['venue'] ?? 'TBD';
      final eOrganizer = eventData['organizer'] ?? 'an Organizer';
      final eOrganization = eventData['organization'] ?? 'an Organization';

      await _sendEmailJs(
        eventId: eventId,
        toEmail: exactEmail,
        guestName: cleanName,
        eventTitle: eventTitle,
        eventDate: eDate,
        eventTime: eTime,
        eventVenue: eVenue,
        organizerName: eOrganizer,
        organizationName: eOrganization,
      );
    }
  }

  // Participant responds to an organizer's invitation
  Future<void> respondToInvite(String docId, String status) async {
    if (status != 'accepted' && status != 'rejected') {
      throw Exception("Invalid response status");
    }

    final docRef = _db.collection('participants').doc(docId);
    final docSnap = await docRef.get();

    if (!docSnap.exists) {
      throw Exception("Participant document not found");
    }

    final data = docSnap.data()!;

    // ─── CAPACITY QUEUE LOGIC FOR INVITATIONS ───
    if (status == 'accepted') {
      final eventDoc = await _db
          .collection('events')
          .doc(data['eventId'])
          .get();
      if (eventDoc.exists) {
        final eventData = eventDoc.data()!;
        final maxCapacity = eventData['maxCapacity'];

        if (maxCapacity != null && maxCapacity is int && maxCapacity > 0) {
          final countQuery = await _db
              .collection('participants')
              .where('eventId', isEqualTo: data['eventId'])
              .where('status', isEqualTo: 'accepted')
              .count()
              .get();

          if (countQuery.count! >= maxCapacity) {
            throw Exception(
              "Capacity Full! Event has reached its maximum limit of $maxCapacity attendees.",
            );
          }
        }
      }
    }

    await docRef.update({
      'status': status,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    // Notify the organizer about the invite response specifically to the organizer dashboard
    await _db.collection('notifications').add({
      'title': status == 'accepted'
          ? 'Invitation Accepted'
          : 'Invitation Declined',
      'body':
      '${data['name']} has $status your invitation to ${data['eventTitle']}.',
      'time': FieldValue.serverTimestamp(),
      'isRead': false,
      'eventId': data['eventId'],
      'targetUserId': data['organizerId'],
      'targetRole': 'organizer', // Prevent bleeding into participant tab
    });
  }

  // MARK ATTENDANCE USING ONLY guestId (QR USE)
  Future<void> markAttendanceByGuestId(String guestId, {
    String? currentEventId,
  }) async {
    final query = await _db
        .collection('participants')
        .where('guestId', isEqualTo: guestId)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception("Participant not found");
    }

    final doc = query.docs.first;
    final data = doc.data();
    final eventId = data['eventId'];

    if (eventId == null) {
      throw Exception("Invalid participant data");
    }

    if (currentEventId != null && eventId != currentEventId) {
      throw Exception("Wrong event QR");
    }

    if (data['attendance'] == true) {
      throw Exception("Already checked in");
    }

    // --- TIME BASED SCANNING RESTRICTION ---
    final eventDoc = await _db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) throw Exception("Event not found");

    final eventData = eventDoc.data()!;
    if (eventData['date'] != null) {
      final eDate = (eventData['date'] as Timestamp).toDate();
      final timeStr = eventData['time'] as String? ?? "00:00";

      final parts = timeStr.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final min = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

      final startDateTime = DateTime(
        eDate.year,
        eDate.month,
        eDate.day,
        hour,
        min,
      );
      final allowedScanTime = startDateTime.subtract(const Duration(hours: 6));

      if (DateTime.now().isBefore(allowedScanTime)) {
        throw Exception(
          "Too early! Scanning opens 6 hours before the event starts.",
        );
      }
    }
    // ---------------------------------------

    await doc.reference.update({
      'attendance': true,
      'checkInTime': FieldValue.serverTimestamp(),
    });
  }

  // GET PARTICIPANT (SAFE)
  Future<Map<String, dynamic>?> getParticipant({
    required String userId,
    required String eventId,
  }) async {
    final stdDoc = await _db
        .collection('participants')
        .doc(_docId(userId, eventId))
        .get();
    if (stdDoc.exists) return stdDoc.data()
      ?..addAll({'docId': stdDoc.id});

    final query = await _db
        .collection('participants')
        .where('userId', isEqualTo: userId)
        .where('eventId', isEqualTo: eventId)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first.data()
        ..addAll({'docId': query.docs.first.id});
    }

    return null;
  }

  // DELETE PARTICIPANT (ONLY OWNER SAFE)
  Future<void> deleteParticipant({
    required String userId,
    required String eventId,
  }) async {
    final query = await _db
        .collection('participants')
        .where('userId', isEqualTo: userId)
        .where('eventId', isEqualTo: eventId)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception("Participant not found");
    }

    final docRef = query.docs.first.reference;
    final data = query.docs.first.data();

    if (data['userId'] != userId) {
      throw Exception("Unauthorized delete attempt");
    }

    await docRef.delete();
  }

  //for getting pending participant requests for an event
  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingParticipants({
    required String eventId,
  }) {
    return _db
        .collection('participants')
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'pending')
        .where('type', isEqualTo: 'request')
        .snapshots();
  }

  //for getting ALL participants of an event (for management)
  Stream<QuerySnapshot<Map<String, dynamic>>> getEventParticipants({
    required String eventId,
  }) {
    return _db
        .collection('participants')
        .where('eventId', isEqualTo: eventId)
        .snapshots();
  }

  //for organizer accepting or rejecting an explore request
  Future<void> updateParticipantStatus({
    required String docId,
    required String status,
  }) async {
    if (status != 'accepted' && status != 'rejected') {
      throw Exception("Invalid status");
    }

    final docRef = _db.collection('participants').doc(docId);
    final doc = await docRef.get();

    if (!doc.exists) {
      throw Exception("Participant document not found");
    }

    final data = doc.data()!;

    // ─── CAPACITY QUEUE LOGIC FOR JOIN REQUESTS ───
    if (status == 'accepted') {
      final eventDoc = await _db
          .collection('events')
          .doc(data['eventId'])
          .get();
      if (eventDoc.exists) {
        final eventData = eventDoc.data()!;
        final maxCapacity = eventData['maxCapacity'];

        if (maxCapacity != null && maxCapacity is int && maxCapacity > 0) {
          final countQuery = await _db
              .collection('participants')
              .where('eventId', isEqualTo: data['eventId'])
              .where('status', isEqualTo: 'accepted')
              .count()
              .get();

          if (countQuery.count! >= maxCapacity) {
            throw Exception("Capacity Full! User will remain in the Queue.");
          }
        }
      }
    }

    await docRef.update({
      'status': status,
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }
}