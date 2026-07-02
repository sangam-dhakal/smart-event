import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // 1. Reference the correct, single static instance exposed by the package
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Internal Method to link auto-generated CSV invitations to a newly logged-in user
  Future<void> _linkPendingInvitations(User user) async {
    try {
      final email = user.email;
      if (email == null || email.isEmpty) return;

      final query = await _db
          .collection('participants')
          .where('email', isEqualTo: email)
          .where('userId', isEqualTo: '')
          .where('status', isEqualTo: 'invited')
          .get();

      if (query.docs.isNotEmpty) {
        final batch = _db.batch();
        String? fcmToken;
        try {
          fcmToken = await FirebaseMessaging.instance.getToken();
        } catch (e) {
          debugPrint("FCM Fetch Failed During Linking: $e");
        }

        for (var doc in query.docs) {
          batch.update(doc.reference, {
            'userId': user.uid,
            // Explicitly maintaining the status as 'invited' so they can manually accept
            if (fcmToken != null) 'fcmToken': fcmToken,
          });
        }
        await batch.commit();

        try {
          await FirebaseMessaging.instance.subscribeToTopic("participants");
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Error linking invitations: $e");
    }
  }

  /// Registers a user using traditional Email/Password architecture
  Future<void> register(
    String name,
    String email,
    String password,
    String confirm,
    String role, {
    String? orgName,
    String? department,
    String? location,
  }) async {
    final user = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // Save core data + Organizer specific data if applicable
    await _db.collection('users').doc(user.user!.uid).set({
      'name': name.trim(),
      'email': email.trim(),
      'role': role,
      if (role == 'organizer' && orgName != null) 'orgName': orgName.trim(),
      if (role == 'organizer' && department != null) 'department': department.trim(),
      if (role == 'organizer' && location != null) 'location': location.trim(),
    });

    // Attempt to link invitations
    await _linkPendingInvitations(user.user!);
  }

  /// Logs a user in using traditional Email/Password architecture
  Future<User?> login(String email, String password) async {
    final user = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (user.user != null) {
      await _linkPendingInvitations(user.user!);
    }

    return user.user;
  }

  /// Triggers OAuth2 Authentication via Google Identity Services
  Future<User?> signInWithGoogle() async {
    try {
      // Fetch the Web Client ID from your .env configuration
      final String serverClientId = dotenv.get(
        'AUTH_WEB_CLIENT_ID',
        fallback: '',
      );

      if (serverClientId.isEmpty && kDebugMode) {
        debugPrint(
          "🚨 CRITICAL CONFIG WARNING: 'AUTH_WEB_CLIENT_ID' is missing from your .env file!",
        );
      }

      // Dynamically configure the singleton using its initialize method
      await _googleSignIn.initialize(
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
      );

      // Trigger authentication overlay window
      final GoogleSignInAccount? googleUser = await _googleSignIn
          .authenticate();

      if (googleUser == null) {
        // User explicitly backed out or closed the account selection sheet
        return null;
      }

      // Synchronously retrieve the core OAuth security structural metadata
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // FIX: Instead of calling .authorizationForScopes([]), use googleAuth directly!
      // This eliminates the empty scopes array crash entirely.
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken, // Pass the native token directly
        idToken: googleAuth.idToken,
      );

      // Finalize internal Firebase secure handshakes
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        // Ensure synchronization layout inside Firestore user trees
        final doc = await _db.collection('users').doc(user.uid).get();

        if (!doc.exists) {
          await _db.collection('users').doc(user.uid).set({
            'name': user.displayName ?? 'Google User',
            'email': user.email ?? '',
            'role': '', // Require user to select a role explicitly
          });
        }

        await _linkPendingInvitations(user);
      }

      return user;
    } catch (e) {
      debugPrint("❌ AuthService.signInWithGoogle Error Handled: $e");
      rethrow; // Pass up to the UI so the catch block displays a Snackbar message
    }
  }

  /// Retrieves the explicit business role profile associated with the unique UID
  Future<String> getRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists && doc.data()!.containsKey('role')) {
      String r = doc['role'] ?? "";
      if (r == 'admin') return 'organizer'; // Legacy mapping so old accounts don't break
      return r;
    } else {
      return ""; // Default to empty to force role selection
    }
  }

  /// Updates the user's role explicitly (used when picking a role post-registration)
  Future<void> updateRole(String uid, String role) async {
    await _db.collection('users').doc(uid).update({'role': role});
  }

  /// Flushes current caching configurations and breaks Active Firebase Session mappings
  Future<void> logout() async {
    // Clear management cache so a different user isn't accidentally logged in as admin
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isManagement');
    await prefs.remove('managementRole');

    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

extension on GoogleSignInAuthentication {
  String? get accessToken => null;
}