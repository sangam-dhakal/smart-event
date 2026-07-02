import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/auth/login_page.dart';
import 'package:smart_event_app/event/event_details.dart';
import 'package:smart_event_app/event/event_page.dart';
import 'package:smart_event_app/event/event_service.dart';
import 'package:smart_event_app/qr/qr_page.dart';
import 'package:smart_event_app/services/auth_service.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class ParticipantPages extends StatefulWidget {
  const ParticipantPages({super.key});

  @override
  State<ParticipantPages> createState() => _ParticipantPagesState();
}

class _ParticipantPagesState extends State<ParticipantPages>
    with WidgetsBindingObserver {
  int currentIndex = 0;
  final service = EventService();
  final authService = AuthService();
  StreamSubscription? _banListener;

  final TextEditingController searchController = TextEditingController();

  String searchText = "";
  List<String> locations = [
    "All",
    "Kathmandu",
    "Pokhara",
    "Taplejung",
    "Lalitpur",
    "Bhaktapur",
    "Dharan",
    "Itahari",
    "Biratnagar",
    "Birtamod",
    "USA",
    "Switzerland",
  ];
  String selectedLocation = "All";

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
    searchController.dispose();
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

  void showLocation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            "Select Location",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: locations.map((loc) {
                return ListTile(
                  title: Text(loc),
                  onTap: () {
                    setState(() => selectedLocation = loc);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  DateTime? safeDate(dynamic dateField) {
    if (dateField == null) return null;
    if (dateField is Timestamp) return dateField.toDate();
    if (dateField is String) return DateTime.tryParse(dateField);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: [buildHomeTabs(), showQr(), buildProfile()],
      ),
      bottomNavigationBar: CurvedNavigationBar(
        height: (60.h).clamp(0.0, 75.0),
        color: AppColors.primary,
        buttonBackgroundColor: AppColors.secondary,
        backgroundColor: Colors.transparent,
        animationDuration: const Duration(milliseconds: 300),
        items: const [
          Icon(Icons.home, color: Colors.white),
          Icon(Icons.qr_code, color: Colors.white),
          Icon(Icons.person, color: Colors.white),
        ],
        onTap: (index) {
          setState(() => currentIndex = index);
          _verifyAccountStatus();
        },
      ),
    );
  }

  Widget buildHomeTabs() {
    return SafeArea(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text("Participant Dashboard"),
            bottom: const TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontWeight: FontWeight.bold),
              tabs: [
                Tab(icon: Icon(Icons.explore), text: "Explore"),
                Tab(icon: Icon(Icons.event_seat), text: "My Events"),
              ],
            ),
            actions: [
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("notifications")
                    .where(
                      'targetUserId',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                    )
                    .where(
                      'targetRole',
                      isEqualTo: 'participant',
                    ) // STRICT ROLE FILTER
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.notifications),
                    );
                  }

                  final docs = snapshot.data!.docs.toList();
                  docs.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aTime = aData['time'] as Timestamp?;
                    final bTime = bData['time'] as Timestamp?;
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
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
                                title: const Text(
                                  "Notifications",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  child: docs.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: Text("No notifications yet."),
                                        )
                                      : ListView(
                                          shrinkWrap: true,
                                          children: docs.map((doc) {
                                            final data =
                                                doc.data()
                                                    as Map<String, dynamic>;
                                            return ListTile(
                                              title: Text(
                                                data["title"] ?? "",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              subtitle: Text(
                                                data["body"] ?? "",
                                              ),
                                              tileColor: data["isRead"] == false
                                                  ? AppColors.primary.withAlpha(
                                                      20,
                                                    )
                                                  : null,
                                              onTap: () async {
                                                await FirebaseFirestore.instance
                                                    .collection("notifications")
                                                    .doc(doc.id)
                                                    .update({"isRead": true});

                                                final eventId = data["eventId"];
                                                if (eventId == null) return;

                                                final eventDoc =
                                                    await FirebaseFirestore
                                                        .instance
                                                        .collection("events")
                                                        .doc(eventId)
                                                        .get();
                                                if (!eventDoc.exists ||
                                                    !context.mounted)
                                                  return;

                                                final eventData = eventDoc
                                                    .data()!;

                                                Navigator.pop(context);
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        EventDetailsPage(
                                                          eventData: eventData,
                                                          eventDate: safeDate(
                                                            eventData['date'],
                                                          ),
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
          body: TabBarView(children: [_buildExploreTab(), _buildMyEventsTab()]),
        ),
      ),
    );
  }

  Widget _buildExploreTab() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('participants')
          .where('userId', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, participantSnapshot) {
        Set<String> myEventIds = {};
        if (participantSnapshot.hasData) {
          myEventIds = participantSnapshot.data!.docs
              .map((doc) => doc.data()['eventId'] as String)
              .toSet();
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: service.getEvents(),
          builder: (context, eventSnapshot) {
            if (!eventSnapshot.hasData)
              return const Center(child: CircularProgressIndicator());

            final filteredDocs = eventSnapshot.data!.docs.where((doc) {
              final data = doc.data();

              // Exclude if the current user is the organizer
              if (data['organizerId'] == currentUserId) return false;

              // Exclude if the user is already a participant
              if (myEventIds.contains(doc.id)) return false;

              // EXCLUDE IF EVENT IS NOT APPROVED BY SUPER ADMIN
              final approvalStatus = data['approvalStatus'] ?? 'approved';
              if (approvalStatus != 'approved') return false;

              // AUTO-HIDE EXPIRED EVENTS
              DateTime? eDate = safeDate(data['date']);
              final now = DateTime.now();
              if (eDate != null &&
                  eDate.isBefore(DateTime(now.year, now.month, now.day)))
                return false;

              final title = (data['title'] ?? "").toString().toLowerCase();
              final venue = (data['venue'] ?? "").toString().toLowerCase();

              final matchTitle =
                  searchText.isEmpty ||
                  title.contains(searchText) ||
                  venue.contains(searchText);
              final matchLocation =
                  selectedLocation == "All" ||
                  venue.contains(selectedLocation.toLowerCase());

              return matchTitle && matchLocation;
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: (value) => setState(
                            () => searchText = value.trim().toLowerCase(),
                          ),
                          decoration: InputDecoration(
                            hintText: "Search Explore",
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      searchController.clear();
                                      setState(() => searchText = "");
                                    },
                                    icon: const Icon(Icons.clear),
                                  )
                                : null,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 14.h,
                              horizontal: 16.w,
                            ),
                          ),
                        ),
                      ),
                      Gap(8.w),
                      SizedBox(
                        height: 52.h,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.location_on, size: 18),
                          label: Text(selectedLocation),
                          onPressed: showLocation,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredDocs.isEmpty
                      ? const Center(
                          child: Text("No public events to explore right now."),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          itemCount: filteredDocs.length,
                          itemBuilder: (context, index) {
                            final doc = filteredDocs[index];
                            final data = doc.data();
                            return Card(
                              margin: EdgeInsets.only(bottom: 12.h),
                              child: ListTile(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16.w,
                                  vertical: 8.h,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.secondary
                                      .withAlpha(30),
                                  child: const Icon(
                                    Icons.event_available,
                                    color: AppColors.secondary,
                                  ),
                                ),
                                title: Text(
                                  data['title'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Gap(4.h),
                                    Text(
                                      [data['venue'] ?? '']
                                          .where(
                                            (element) => element.isNotEmpty,
                                          )
                                          .join(' • '),
                                    ),
                                    if (data['description'] != null &&
                                        data['description']
                                            .toString()
                                            .isNotEmpty) ...[
                                      Gap(4.h),
                                      Text(
                                        data['description'],
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: const Text(
                                  "Apply",
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EventDetailsPage(
                                        eventData: data,
                                        eventDate: safeDate(data['date']),
                                        eventId: doc.id,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMyEventsTab() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('participants')
          .where('userId', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              "You have no active events, invitations, or requests.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        List<Map<String, dynamic>> pendingInvites = [];
        List<Map<String, dynamic>> pendingRequests = [];
        List<Map<String, dynamic>> upcomingTickets = [];
        List<Map<String, dynamic>> history = [];

        final now = DateTime.now();

        for (var doc in docs) {
          final data = doc.data();
          final eventId = data['eventId'] as String;
          final status = data['status'] as String? ?? '';
          final type = data['type'] as String? ?? 'request';
          final attendance = data['attendance'] == true;

          DateTime? eventDate = safeDate(data['eventDate']);
          bool isPast =
              eventDate != null &&
              eventDate.isBefore(DateTime(now.year, now.month, now.day));

          final Map<String, dynamic> item = {
            'docId': doc.id,
            'eventId': eventId,
            'title': data['eventTitle'] ?? 'Event',
            'date': eventDate,
            'status': status,
            'type': type,
            'attendance': attendance,
            'isPast': isPast,
          };

          if (attendance) {
            history.add(
              item
                ..['historyLabel'] = type == 'invite'
                    ? 'Attended Invitation'
                    : 'Attended Request',
            );
          } else if (status == 'rejected') {
            history.add(
              item
                ..['historyLabel'] = type == 'invite'
                    ? 'Rejected Invitation'
                    : 'Rejected Request',
            );
          } else if (isPast) {
            if (status == 'accepted')
              history.add(item..['historyLabel'] = 'Missed (Did Not Attend)');
            else if (status == 'invited')
              history.add(item..['historyLabel'] = 'Expired Invitation');
            else if (status == 'pending')
              history.add(item..['historyLabel'] = 'Expired Request');
          } else {
            if (status == 'invited') {
              item['customSubtitle'] = 'Pending Invitation';
              pendingInvites.add(item);
            } else if (status == 'pending') {
              item['customSubtitle'] = 'Pending Request';
              pendingRequests.add(item);
            } else if (status == 'accepted') {
              item['customSubtitle'] = type == 'invite'
                  ? 'Accepted Invitation (To Go)'
                  : 'Accepted Request (To Go)';
              upcomingTickets.add(item);
            }
          }
        }

        return ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            if (pendingInvites.isNotEmpty)
              _buildSection(
                "Action Required: Invitations",
                pendingInvites,
                AppColors.warning,
              ),
            if (upcomingTickets.isNotEmpty)
              _buildSection(
                "Upcoming Tickets",
                upcomingTickets,
                AppColors.success,
              ),
            if (pendingRequests.isNotEmpty)
              _buildSection(
                "Pending Requests",
                pendingRequests,
                AppColors.info,
              ),
            if (history.isNotEmpty)
              _buildSection("History", history, AppColors.textSecondary),
          ],
        );
      },
    );
  }

  Widget _buildSection(
    String title,
    List<Map<String, dynamic>> items,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        ...items.map((item) {
          String subtitle = '';
          if (item['date'] != null) {
            final d = item['date'] as DateTime;
            subtitle = "${d.day}/${d.month}/${d.year} • ";
          }
          if (item['historyLabel'] != null) {
            subtitle += item['historyLabel'];
          } else if (item['customSubtitle'] != null) {
            subtitle += item['customSubtitle'];
          }

          IconData icon = Icons.event;
          if (item['historyLabel'] != null &&
              item['historyLabel'].toString().contains('Attended')) {
            icon = Icons.check_circle;
          }
          if (item['historyLabel'] == 'Missed (Did Not Attend)') {
            icon = Icons.event_busy;
          }
          if (item['status'] == 'invited') icon = Icons.mail;

          return Card(
            elevation: 1,
            margin: EdgeInsets.only(bottom: 8.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
              side: BorderSide(color: color.withAlpha(100), width: 1.5),
            ),
            child: ListTile(
              leading: Icon(icon, color: color),
              title: Text(
                item['title'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: AppColors.textSecondary,
              ),
              onTap: () async {
                final eventDoc = await FirebaseFirestore.instance
                    .collection('events')
                    .doc(item['eventId'])
                    .get();
                if (!eventDoc.exists || !mounted) return;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventDetailsPage(
                      eventData: eventDoc.data()!,
                      eventDate: safeDate(eventDoc.data()!['date']),
                      eventId: item['eventId'],
                    ),
                  ),
                );
              },
            ),
          );
        }).toList(),
        Gap(16.h),
      ],
    );
  }

  Widget showQr() {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    return SafeArea(
      child: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('participants')
            .where('userId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'accepted')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // FIX: Expired Events' QR tickets are demolished for non-attendees
          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            DateTime? eDate = safeDate(data['eventDate']);
            final now = DateTime.now();
            bool isPast =
                eDate != null &&
                eDate.isBefore(DateTime(now.year, now.month, now.day));
            bool attended = data['attendance'] == true;

            // Hide the QR if the event has ended and they didn't check in
            if (isPast && !attended) return false;
            return true;
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text("No active tickets found."));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(24.w),
                child: Text(
                  "My Tickets",
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  children: docs.map((doc) {
                    final data = doc.data();
                    return Card(
                      margin: EdgeInsets.only(bottom: 12.h),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(12.w),
                        leading: Container(
                          padding: EdgeInsets.all(8.w),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: const Icon(
                            Icons.qr_code,
                            color: AppColors.primary,
                          ),
                        ),
                        title: Text(
                          data['eventTitle'] ?? 'Event Ticket',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text("Tap to view QR Code"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QRPage(
                                guestId: data['guestId'],
                                eventId: data['eventId'],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget buildProfile() {
    final uid = authService.currentUserId;
    return SafeArea(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!.data();
          if (data == null) return const Center(child: Text("No user found"));

          final name = data['name'] ?? "User";
          final email = data['email'] ?? "No Email";

          return Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.all(24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Profile",
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    SizedBox(height: 30.h),
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.secondary,
                          radius: 36.r,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : "U",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 28.sp,
                            ),
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 20.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                email,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Gap(40.h),

                    // ROLE SWITCHING BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const ValueKey('participant_switch_role_btn'),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .update({'role': 'organizer'});
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EventPage(),
                            ),
                            (route) => false,
                          );
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.swap_horiz),
                            SizedBox(width: 8),
                            Text("Switch to Organizer Dashboard"),
                          ],
                        ),
                      ),
                    ),
                    Gap(80.h),
                    // Provide clearance for the bottom floating logout button
                  ],
                ),
              ),
              Positioned(
                bottom: 24,
                right: 24,
                child: FloatingActionButton.extended(
                  onPressed: _forceLogout,
                  backgroundColor: AppColors.surface,
                  label: const Text(
                    "Log out",
                    style: TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  icon: const Icon(Icons.logout, color: AppColors.error),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
