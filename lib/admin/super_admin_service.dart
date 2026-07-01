import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class SuperAdminService {
  String get _baseUrl {
    final url = dotenv.env['API_BASE_URL'] ?? 'https://smart-event-api.vercel.app';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Verifies if user is in management, returning their specific tier ('super_admin' or 'staff_admin')
  Future<String?> checkManagementRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final token = await user.getIdToken();
      final res = await http.get(
        Uri.parse('$_baseUrl/api/super-admin/check'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['isManagement'] == true) {
          return data['role'];
        }
      }
    } catch (e) {
      debugPrint('Management Verification Check Error: $e');
    }
    return null;
  }

  /// Grabs ALL registered users across the platform from Firebase Auth
  Future<List<dynamic>> getUsers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final token = await user.getIdToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/api/super-admin/users'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body)['users'] ?? [];
    } else {
      throw Exception('Failed to load users. Backend responded with: ${res.statusCode}');
    }
  }

  /// Suspend or Activate a specific User ID globally
  Future<void> toggleUserStatus(String uid, bool disable) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/api/super-admin/users/$uid/toggle'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'disabled': disable}),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to toggle user status');
    }
  }

  /// Forcibly deletes a user's event and wipes its related participants from Firestore
  Future<void> deleteEvent(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/super-admin/events/$eventId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to delete event');
    }
  }

  /// Blasts a high-priority push notification to EVERY user who installed the app
  Future<void> sendGlobalNotification(String title, String body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/api/super-admin/global-notification'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'title': title, 'body': body}),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to broadcast notification');
    }
  }

  // ─── STAFF CRUD ───

  Future<List<dynamic>> getStaff() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final token = await user.getIdToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/api/super-admin/staff'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body)['staff'] ?? [];
    } else {
      throw Exception('Failed to load staff list.');
    }
  }

  Future<void> addStaff(String email) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/api/super-admin/staff'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'email': email}),
    );

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Failed to add staff';
      throw Exception(error);
    }
  }

  Future<void> removeStaff(String email) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/super-admin/staff/$email'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to remove staff');
    }
  }
}