import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:smart_event_app/screen/splash_screen.dart';
import 'package:smart_event_app/theme/app_theme.dart';

import 'event/event_details.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Store initial eventId for deep linking
String? initialEventId;

// BACKGROUND HANDLER
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await showNotification(message);
  } catch (e) {
    debugPrint("Background handler error: $e");
  }
}

// THE MAIN FUNCTION
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Firebase initialization errors
  try {
    // Load the environment variables
    await dotenv.load(fileName: ".env");

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("FIREBASE INIT ERROR: $e");
  }

  // Get initial message quickly without blocking
  try {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();

    if (initialMessage != null) {
      initialEventId = initialMessage.data['eventId'];
    }
  } catch (e) {
    debugPrint("Failed to get initial FCM message: $e");
  }

  // Run the app
  runApp(const ProviderScope(child: MyApp()));
}

// FCM SETUP for notifications
Future<void> setupFCM() async {
  try {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request Permission
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Save Organizer/User FCM Token so Admins can push to them
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
              'fcmToken': token,
              'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    }

    // Subscribe ALL participants
    await messaging.subscribeToTopic("participants");

    // LOCAL NOTIFICATION SETUP
    try {
      // Ensure you have an app_icon.png in your android/app/src/main/res/drawable folder,
      // otherwise change '@mipmap/ic_launcher' to your correct icon name.
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initSettings = InitializationSettings(
        android: androidInit,
      );

      await localNotifications.initialize(initSettings);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.high,
      );

      await localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      await localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint("🔴 LOCAL NOTIFICATIONS INIT ERROR: $e");
    }

    // FOREGROUND MESSAGE
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      showNotification(message);
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(refreshedUser.uid)
          .set({
            'fcmToken': token,
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    });

    // ON CLICK
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      final eventId = message.data['eventId'];

      if (eventId != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('events')
              .doc(eventId)
              .get();

          if (!doc.exists) return;

          final data = doc.data()!;

          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => EventDetailsPage(
                eventData: data,
                eventDate: null,
                eventId: eventId,
              ),
            ),
          );
        } catch (e) {
          debugPrint("Failed to navigate on notification click: $e");
        }
      }
    });
  } catch (e) {
    debugPrint("🔴 FCM SETUP ERROR: $e");
  }
}

// SHOW NOTIFICATION
Future<void> showNotification(RemoteMessage message) async {
  try {
    final title =
        message.notification?.title ??
        message.data['title'] ??
        message.data['newsTitle'] ??
        "Event Update";

    final body =
        message.notification?.body ??
        message.data['body'] ??
        message.data['newsDescription'] ??
        "";

    await localNotifications.show(
      DateTime.now().millisecondsSinceEpoch,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  } catch (e) {
    debugPrint("Failed to show local notification: $e");
  }
}

// ROOT APP WIDGET
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Run heavy FCM setup asynchronously AFTER app start
    setupFCM();
    handleInitialNavigation();
    initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  // ─── DEEP LINKING LOGIC ───
  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks.getInitialLink();

      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint("Failed to get initial deep link: $e");
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint("Deep link error: $err");
      },
    );
  }

  void _handleDeepLink(Uri uri) async {
    // Expected incoming URI from our backend intent: smartevent://invite/EVENT_ID
    if (uri.scheme == 'smartevent' && uri.host == 'invite') {
      final eventId = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.first
          : null;
      if (eventId != null && eventId.isNotEmpty) {
        // Wait briefly for Splash Screen routing if app just launched
        Future.delayed(const Duration(seconds: 4), () async {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('events')
                .doc(eventId)
                .get();
            if (doc.exists) {
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => EventDetailsPage(
                    eventData: doc.data()!,
                    eventId: eventId,
                  ),
                ),
              );
            }
          } catch (e) {
            debugPrint("Deep link navigation error: $e");
          }
        });
      }
    }
  }

  // Handle Push Notification Navigation AFTER UI loads
  Future<void> handleInitialNavigation() async {
    if (initialEventId == null) return;

    // Delay to allow Splash Screen to finish
    Future.delayed(const Duration(seconds: 4), () async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('events')
            .doc(initialEventId)
            .get();

        if (!doc.exists) return;

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => EventDetailsPage(
              eventData: doc.data()!,
              eventDate: null,
              eventId: initialEventId!,
            ),
          ),
        );
      } catch (e) {
        debugPrint("Initial Navigation Error: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Wrapped MaterialApp with ScreenUtilInit
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: AppTheme.lightTheme, // Hooked up the central theme here
          home: child,
        );
      },
      child: const SplashScreen(),
    );
  }
}
