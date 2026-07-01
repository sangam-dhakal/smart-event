import 'package:cloud_firestore/cloud_firestore.dart';

class Participant {
  final String id;
  final String userId;
  final String name;
  final String email;
  final String eventId;
  final String guestId;
  final bool attendance;
  final DateTime? createdAt;
  //final DateTime? checkInTime;

  Participant({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.eventId,
    required this.guestId,

    this.createdAt,
    // this.checkInTime,
    required this.attendance,
  });

  factory Participant.fromMap(String id, Map<String, dynamic> data) {
    return Participant(
      id: id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      eventId: data['eventId'] ?? '',
      guestId: data['guestId'] ?? '',

      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      attendance: data['attendance'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'eventId': eventId,
      'guestId': guestId,
      'createdAt': createdAt,
    };
  }
}
