import 'dart:async';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:smart_event_app/auth/login_page.dart';
import 'package:smart_event_app/event/event_create_page.dart';
import 'package:smart_event_app/event/event_details.dart';
import 'package:smart_event_app/event/event_service.dart';
import 'package:smart_event_app/participant/participant_pages.dart';
import 'package:smart_event_app/qr/qr_scanner_page.dart';
import 'package:smart_event_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class EventPage extends StatefulWidget {
  const EventPage({super.key});

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> with WidgetsBindingObserver {
  final service = EventService();
  final authService = AuthService();
  StreamSubscription? _banListener;

  int currentIndex = 0;

  String? selectedEventId;
  String? analyticsEventId;
  bool _fromAnalytics = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen for Real-Time Account Suspensions
    _banListener = FirebaseFirestore.instance
        .collection('users')
        .doc(authService.currentUserId)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data()?['disabled'] == true) {
        _forceLogout();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _banListener?.cancel();
    super.dispose();
  }

  Future<void> _forceLogout() async {
    await authService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyAccountStatus();
    }
  }

  Future<void> _verifyAccountStatus() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled' || e.code == 'user-not-found') {
        _forceLogout();
      }
    }
  }

  // Safe Firestore date conversion
  DateTime? safeDate(dynamic dateField) {
    if (dateField == null) return null;
    if (dateField is Timestamp) return dateField.toDate();
    if (dateField is String) return DateTime.tryParse(dateField);
    return null;
  }

  //Convert Firestore "HH:mm" string to TimeOfDay
  TimeOfDay? parseTime(String? timeString) {
    if (timeString == null || !timeString.contains(':')) return null;
    final parts = timeString.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  //Format TimeOfDay to 12-hour with AM/PM
  String formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final minute = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return "$hour:$minute $period";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: [
          buildEventList(),
          buildAnalytics(),
          buildProfilePage(),
          QRScannerPage(eventId: selectedEventId ?? ''),
        ],
      ),

      // Curved Bottom Nav
      bottomNavigationBar: CurvedNavigationBar(
        index: currentIndex,
        height: (65.h).clamp(0.0, 75.0),
        backgroundColor: Colors.transparent,
        color: AppColors.primary,
        buttonBackgroundColor: AppColors.secondary,
        animationDuration: const Duration(milliseconds: 400),
        items: const [
          Icon(Icons.list, color: Colors.white, semanticLabel: "Event"),
          Icon(Icons.bar_chart_sharp, color: Colors.white),
          Icon(Icons.person_3_sharp, color: Colors.white),
        ],
        onTap: (index) {
          setState(() => currentIndex = index);
          // Also verify account status whenever they tap a new tab
          _verifyAccountStatus();
        },
      ),
    );
  }

  //EVENT LIST
  Widget buildEventList() {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("My Events"),
          backgroundColor: AppColors.surface,
          elevation: 1,
          actions: [
            StreamBuilder<QuerySnapshot>(
              // Fetch targeted notifications locally sorting to prevent index errors
              stream: FirebaseFirestore.instance
                  .collection("notifications")
                  .where('targetUserId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .where('targetRole', isEqualTo: 'organizer') // STRICT ROLE FILTER
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications),
                  );
                }

                // Sorting locally so we don't require users to generate a composite index manually
                final docs = snapshot.data!.docs.toList();
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTime = aData['time'] as Timestamp?;
                  final bTime = bData['time'] as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime); // Descending
                });

                int count = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data["isRead"] == false;
                }).length;

                return Stack(
                  children: [
                    IconButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) {
                            return AlertDialog(
                              title: const Text("Organizer Alerts",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: docs.isEmpty
                                    ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text("No alerts yet."),
                                )
                                    : ListView(
                                  shrinkWrap: true,
                                  children: docs.map((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    return ListTile(
                                      title: Text(data["title"] ?? "",
                                          style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text(data["body"] ?? ""),
                                      tileColor: data["isRead"] == false
                                          ? AppColors.primary.withAlpha(20)
                                          : null,
                                      onTap: () async {
                                        // Mark as read
                                        await FirebaseFirestore.instance
                                            .collection("notifications")
                                            .doc(doc.id)
                                            .update({"isRead": true});

                                        final eventId = data["eventId"];
                                        if (eventId == null) return;

                                        final eventDoc = await FirebaseFirestore.instance
                                            .collection("events").doc(eventId).get();
                                        if (!eventDoc.exists || !context.mounted) return;

                                        final eventData = eventDoc.data()!;

                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                EventDetailsPage(
                                                  eventData: eventData,
                                                  eventDate: safeDate(eventData['date']),
                                                  eventId: eventId,
                                                ),
                                          ),
                                        );
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      icon: const Icon(Icons.notifications),
                    ),
                    if (count > 0)
                      Positioned(
                        right: 5,
                        top: 5,
                        child: Container(
                          padding: EdgeInsets.all(5.w),
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            "$count",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),

        // MOVED FAB TO SCAFFOLD LEVEL SO IT NEVER DISAPPEARS
        floatingActionButton: FloatingActionButton.extended(
          heroTag: "create_event",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                const EventCreatePage(eventData: null, docId: null),
              ),
            );
          },
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            "Create Event",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.secondary,
        ),

        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: service.getEvents(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // Only load events owned by the current organizer
            final currentUserId = FirebaseAuth.instance.currentUser?.uid;
            final docs = snapshot.data!
                .docs
                .where((d) => d.data()['organizerId'] == currentUserId)
                .toList();

            if (docs.isEmpty) {
              return const Center(
                  child: Text(
                      "No events found. Tap 'Create Event' to make one.",
                      style: TextStyle(color: AppColors.textSecondary)
                  )
              );
            }

            return ListView(
              // Added bottom padding so the FAB doesn't block the last item
              padding: EdgeInsets.all(16.w).copyWith(bottom: 80.h),
              children: docs.map((doc) {
                final data = doc.data();
                final eventDate = safeDate(data['date']);

                final status = data['approvalStatus'] ?? 'approved';
                Color badgeColor = AppColors.success;
                String badgeText = "Approved";

                if (status == 'pending') {
                  badgeColor = AppColors.warning;
                  badgeText = "Pending Verification";
                } else if (status == 'rejected') {
                  badgeColor = AppColors.error;
                  badgeText = "Rejected";
                }

                return Card(
                  margin: EdgeInsets.only(bottom: 12.h),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16.r),
                    onTap: () {
                      final eventId = doc.id;
                      if (_fromAnalytics) {
                        analyticsEventId = eventId;
                        setState(() {
                          _fromAnalytics = false;
                          currentIndex = 1;
                        });
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                EventDetailsPage(
                                  eventData: data,
                                  eventDate: eventDate,
                                  eventId: eventId,
                                ),
                          ),
                        );
                      }
                    },
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withAlpha(25),
                        child: const Icon(
                          Icons.event,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(
                          data['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Gap(4.h),
                          Text([data['venue'] ?? ''].where((element) => element.isNotEmpty).join(
                              ' • ')),
                          if (data['description'] != null && data['description']
                              .toString()
                              .isNotEmpty) ...[
                            Gap(4.h),
                            Text(data['description'], maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                          ],
                          Gap(8.h),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: badgeColor.withAlpha(30),
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(badgeText, style: TextStyle(
                                color: badgeColor, fontSize: 10.sp, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: AppColors.success),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EventCreatePage(
                                        eventData: data,
                                        docId: doc.id,
                                      ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: AppColors.error),
                            onPressed: () async {
                              final deleted = await showDialog(
                                context: context,
                                builder: (_) =>
                                    AlertDialog(
                                      title: const Text("Delete Event"),
                                      content: const Text("Are you sure you want to delete?"),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text("Cancel"),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.error),
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text("Delete"),
                                        ),
                                      ],
                                    ),
                              );
                              if (deleted == true) {
                                try {
                                  service.deleteEvent(doc.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      backgroundColor: AppColors.success,
                                      content: Text("Deleted Successfully",
                                          style: TextStyle(color: Colors.white)),
                                    ),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString()),
                                        backgroundColor: AppColors.error),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  // for analytics
  Widget buildAnalytics() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: service.getEvents(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            // Get only the events owned by the current user
            final myEvents = snapshot.data!.docs.where((doc) {
              return doc.data()['organizerId'] == currentUserId;
            }).toList();

            // Empty state
            if (myEvents.isEmpty) {
              return Column(
                children: [
                  Container(
                    color: AppColors.primary,
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                    child: Row(
                      children: [
                        Text("Event Analytics", style: Theme
                            .of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: Colors.white)),
                        const Spacer(),
                        const Text("No events", style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        "No events found.\nCreate an event first.",
                        textAlign: TextAlign.center,
                        style: Theme
                            .of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              );
            }

            // Validate current ID to prevent Dropdown Assertion Error
            bool isValid = myEvents.any((doc) => doc.id == analyticsEventId);
            String safeEventId = isValid ? analyticsEventId! : myEvents.first.id;

            // Sync state if it was invalid
            if (analyticsEventId != safeEventId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => analyticsEventId = safeEventId);
              });
            }

            return Column(
              children: [
                // ── Event Switcher Header ──
                Container(
                  color: AppColors.primary,
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: Row(
                    children: [
                      Text(
                        "Analytics",
                        style: Theme
                            .of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: Colors.white),
                      ),
                      SizedBox(width: 16.w),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: safeEventId,
                            dropdownColor: AppColors.primary,
                            iconEnabledColor: Colors.white,
                            items: myEvents.map((doc) {
                              final title = doc.data()['title'] ?? 'Untitled';
                              return DropdownMenuItem<String>(
                                value: doc.id,
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (eventId) {
                              setState(() => analyticsEventId = eventId);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Attendance Table ──
                Expanded(
                  child: FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('events')
                          .doc(safeEventId)
                          .get(),
                      builder: (context, eventSnapshot) {
                        if (!eventSnapshot.hasData)
                          return const Center(child: CircularProgressIndicator());

                        final eventData = eventSnapshot.data!.data() as Map<String, dynamic>?;
                        if (eventData == null) return const SizedBox();

                        // Calculate if event is in the past
                        DateTime? eDate = safeDate(eventData['date']);
                        final now = DateTime.now();
                        bool isPast = eDate != null &&
                            eDate.isBefore(DateTime(now.year, now.month, now.day));

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('participants')
                              .where('eventId', isEqualTo: safeEventId)
                              .where('status', isEqualTo: 'accepted')
                              .snapshots(),
                          builder: (context, participantSnapshot) {
                            if (!participantSnapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final docs = participantSnapshot.data!.docs;

                            if (docs.isEmpty) {
                              return const Center(
                                child: Text(
                                  "No accepted participants yet.",
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              );
                            }

                            // Count for summary
                            final total = docs.length;
                            final present = docs
                                .where((d) => d.data()['attendance'] == true)
                                .length;
                            final absentOrExpected = total - present;

                            return Column(
                              children: [
                                // ── Summary Cards ──
                                Padding(
                                  padding: EdgeInsets.all(16.w),
                                  child: Row(
                                    children: [
                                      _SummaryCard(label: "Total Guests",
                                          count: total,
                                          color: AppColors.primary),
                                      SizedBox(width: 10.w),
                                      _SummaryCard(label: "Checked In",
                                          count: present,
                                          color: AppColors.success),
                                      SizedBox(width: 10.w),
                                      _SummaryCard(
                                          label: isPast ? "Absent" : "Pending",
                                          count: absentOrExpected,
                                          color: isPast ? AppColors.error : AppColors.warning
                                      ),
                                    ],
                                  ),
                                ),

                                // ── Table Header ──
                                Container(
                                  color: AppColors.primary.withAlpha(25),
                                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 36.w,
                                        child: const Text("S.N", style: TextStyle(
                                            fontWeight: FontWeight.bold, color: AppColors.primary)),
                                      ),
                                      const Expanded(
                                        flex: 3,
                                        child: Text("Name", style: TextStyle(
                                            fontWeight: FontWeight.bold, color: AppColors.primary)),
                                      ),
                                      const Expanded(
                                        flex: 4,
                                        child: Text("Email", style: TextStyle(
                                            fontWeight: FontWeight.bold, color: AppColors.primary)),
                                      ),
                                      SizedBox(
                                        width: 75.w,
                                        child: const Text("Status", style: TextStyle(
                                            fontWeight: FontWeight.bold, color: AppColors.primary),
                                            textAlign: TextAlign.center),
                                      ),
                                    ],
                                  ),
                                ),

                                Divider(height: 1.h, color: AppColors.border),

                                // ── Table Rows ──
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: docs.length,
                                    separatorBuilder: (_, __) =>
                                        Divider(height: 1.h, color: AppColors.border),
                                    itemBuilder: (context, index) {
                                      final data = docs[index].data();
                                      final isPresent = data['attendance'] == true;

                                      final attText = isPresent ? "Present" : (isPast
                                          ? "Absent"
                                          : "Expected");
                                      final attColorBg = isPresent
                                          ? AppColors.success.withAlpha(30)
                                          : (isPast ? AppColors.error.withAlpha(30) : AppColors
                                          .warning.withAlpha(30));
                                      final attColorText = isPresent ? AppColors.success : (isPast
                                          ? AppColors.error
                                          : AppColors.warning);

                                      return Container(
                                        color: index.isEven ? AppColors.surface : AppColors
                                            .background,
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 16.w, vertical: 12.h),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 36.w,
                                              child: Text("${index + 1}", style: TextStyle(
                                                  color: AppColors.textSecondary, fontSize: 13.sp)),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(data['name'] ?? '-', style: TextStyle(
                                                  fontSize: 13.sp,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppColors.textPrimary),
                                                  overflow: TextOverflow.ellipsis),
                                            ),
                                            Expanded(
                                              flex: 4,
                                              child: Text(data['email'] ?? '-', style: TextStyle(
                                                  fontSize: 12.sp, color: AppColors.textSecondary),
                                                  overflow: TextOverflow.ellipsis),
                                            ),
                                            SizedBox(
                                              width: 72.w,
                                              child: Center(
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 8.w, vertical: 4.h),
                                                  decoration: BoxDecoration(
                                                    color: attColorBg,
                                                    borderRadius: BorderRadius.circular(20.r),
                                                  ),
                                                  child: Text(
                                                    attText,
                                                    style: TextStyle(
                                                      fontSize: 11.sp,
                                                      fontWeight: FontWeight.bold,
                                                      color: attColorText,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      }
                  ),
                ),
              ],
            );
          }
      ),
    );
  }

  // PROFILE PAGE
  Widget buildProfilePage() {
    final uid = authService.currentUserId;
    return SafeArea(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!.data();
          if (data == null) return const Center(child: Text("No user found"));

          final name = data['name'] ?? "User";
          final email = data['email'] ?? "No Email";

          return Scaffold(
            appBar: AppBar(
              title: const Text("Profile"),
              actions: [
                PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'switch') {
                        await FirebaseFirestore.instance.collection('users').doc(uid).update(
                            {'role': 'participant'});
                        if (!mounted) return;
                        Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const ParticipantPages()),
                                (route) => false
                        );
                      } else if (value == 'password') {
                        try {
                          await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Password reset link sent to your email!"),
                                  backgroundColor: AppColors.success)
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error)
                          );
                        }
                      } else if (value == 'logout') {
                        _forceLogout();
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      return [
                        const PopupMenuItem(
                            value: 'switch',
                            child: Row(children: [
                              Icon(Icons.swap_horiz, color: AppColors.primary),
                              SizedBox(width: 8),
                              Text("Switch to Participant")
                            ])
                        ),
                        const PopupMenuItem(
                            value: 'password',
                            child: Row(children: [
                              Icon(Icons.lock_reset, color: AppColors.primary),
                              SizedBox(width: 8),
                              Text("Change Password")
                            ])
                        ),
                        const PopupMenuItem(
                            value: 'logout',
                            child: Row(children: [
                              Icon(Icons.logout, color: AppColors.error),
                              SizedBox(width: 8),
                              Text("Logout", style: TextStyle(color: AppColors.error))
                            ])
                        ),
                      ];
                    }
                )
              ],
            ),
            body: SingleChildScrollView(
              padding: EdgeInsets.all(24.w),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Gap(20.h),
                    CircleAvatar(
                      backgroundColor: AppColors.secondary,
                      radius: 48.r,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : "U",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 36.sp
                        ),
                      ),
                    ),
                    Gap(24.h),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Gap(8.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Text("ORGANIZER", style: TextStyle(color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.sp)),
                    ),
                    Gap(16.h),
                    Text(email,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// helper widget
class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Column(
          children: [
            Text(
              "$count",
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: 4.h),
            Text(label,
                style: TextStyle(fontSize: 12.sp, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}