import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/admin/admin_event_report_page.dart';
import 'package:smart_event_app/admin/super_admin_service.dart';
import 'package:smart_event_app/auth/login_page.dart';
import 'package:smart_event_app/services/auth_service.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class SuperAdminDashboard extends StatefulWidget {
  final String role; // 'super_admin' or 'staff_admin'
  const SuperAdminDashboard({super.key, required this.role});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  int currentIndex = 0;
  StreamSubscription? _banListener;

  bool get isSuperAdmin => widget.role == 'super_admin';

  @override
  void initState() {
    super.initState();
    // Watch for Instant Suspend (If a Super Admin bans a Staff Admin while they are using the app)
    _banListener = FirebaseFirestore.instance
        .collection('users')
        .doc(AuthService().currentUserId)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data()?['disabled'] == true) {
        _forceLogout();
      }
    });
  }

  @override
  void dispose() {
    _banListener?.cancel();
    super.dispose();
  }

  Future<void> _handleLogoutDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) =>
          AlertDialog(
            title: const Text(
                "Log Out", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
            content: const Text("Are you sure you want to exit the Super Admin platform?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Log Out"),
              ),
            ],
          ),
    );

    if (confirm == true) {
      _forceLogout();
    }
  }

  Future<void> _forceLogout() async {
    await AuthService().logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    }
  }

  List<Widget> get _pages {
    return [
      const _UsersTab(),
      const _ApprovalsTab(),
      const _EventsTab(),
      const _BroadcastTab(),
      if (isSuperAdmin) const _StaffTab(),
    ];
  }

  List<Widget> get _navIcons {
    return [
      const Icon(Icons.people, color: Colors.white),
      const Icon(Icons.fact_check, color: Colors.white),
      const Icon(Icons.event_busy, color: Colors.white),
      const Icon(Icons.campaign, color: Colors.white),
      if (isSuperAdmin) const Icon(Icons.admin_panel_settings, color: Colors.white),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isSuperAdmin ? "Super Admin Platform" : "Staff Management",
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.red.shade900,
        elevation: 5,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: "Logout",
            onPressed: _handleLogoutDialog,
          ),
        ],
      ),
      body: IndexedStack(
        index: currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: CurvedNavigationBar(
        height: (60.h).clamp(0.0, 75.0),
        color: Colors.black,
        buttonBackgroundColor: Colors.redAccent.shade400,
        backgroundColor: Colors.transparent,
        animationDuration: const Duration(milliseconds: 300),
        items: _navIcons,
        onTap: (index) => setState(() => currentIndex = index),
      ),
      backgroundColor: Colors.grey.shade100,
    );
  }
}

// ─── TAB 1: USERS MANAGEMENT ───
class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final SuperAdminService _service = SuperAdminService();
  late Future<List<dynamic>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  void _fetchUsers() {
    setState(() {
      _usersFuture = _service.getUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return FutureBuilder<List<dynamic>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.red));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text("Verification Failed: ${snapshot.error}",
                style: const TextStyle(color: Colors.red)),
          );
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) return const Center(child: Text("No users found."));

        return ListView.builder(
          padding: EdgeInsets.all(16.w),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final uid = user['uid'];
            final email = user['email'] ?? 'No email associated';
            final name = user['displayName'] ?? 'Unknown User';
            final role = (user['role'] ?? 'unknown').toString().toUpperCase();
            final disabled = user['disabled'] == true;

            final isMe = uid == currentUid;
            final isSuperAdminRole = role == 'SUPER_ADMIN';

            return Card(
              margin: EdgeInsets.only(bottom: 12.h),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: disabled ? Colors.red.shade100 : Colors.green.shade100,
                  child: Icon(
                    disabled ? Icons.person_off : Icons.person,
                    color: disabled ? Colors.red : Colors.green,
                  ),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("$email\nRole: $role"),
                isThreeLine: true,

                // Hide the toggle switch completely if they are the Super Admin or Themselves
                trailing: (isMe || isSuperAdminRole)
                    ? Chip(label: Text(isSuperAdminRole ? "ADMIN" : "YOU",
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))
                    : Switch(
                  value: !disabled,
                  activeColor: Colors.green,
                  inactiveThumbColor: Colors.red,
                  inactiveTrackColor: Colors.red.shade200,
                  onChanged: (val) async {
                    // The value is true if we want them ENABLED, false if DISABLED.
                    final disableAction = !val;
                    try {
                      await _service.toggleUserStatus(uid, disableAction);
                      _fetchUsers(); // Refresh silently

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(disableAction ? "User Suspended!" : "User Activated!"),
                            backgroundColor: disableAction ? Colors.red : Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Failed to alter user status."),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── TAB 2: PENDING EVENT APPROVALS ───
class _ApprovalsTab extends StatelessWidget {
  const _ApprovalsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('approvalStatus', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.red));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 72.sp, color: Colors.grey.shade400),
                Gap(16.h),
                Text("All caught up!", style: TextStyle(
                    fontSize: 18.sp, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                Text("No pending events require verification.",
                    style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16.w),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;

            // Format Registration Deadline if it exists
            String regDeadlineStr = "N/A";
            if (data['registrationDeadline'] != null) {
              final d = (data['registrationDeadline'] as Timestamp).toDate();
              regDeadlineStr =
              "${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}";
            }

            return Card(
              margin: EdgeInsets.only(bottom: 16.h),
              elevation: 3,
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.assignment, color: Colors.orange),
                        Gap(8.w),
                        Expanded(child: Text(data['title'] ?? 'Untitled Event',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      ],
                    ),
                    const Divider(),
                    Gap(8.h),

                    // Detailed Information for Admin
                    Text("Host: ${data['organizer'] ?? 'Unknown'}",
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text("Organization: ${data['organization'] ?? 'N/A'}"),
                    Text("Venue: ${data['venue'] ?? 'N/A'}"),
                    Text("Max Capacity: ${data['maxCapacity'] ?? 'N/A'}"),
                    Text("Reg. Deadline: $regDeadlineStr"),
                    Gap(8.h),
                    const Text("Description:", style: TextStyle(fontWeight: FontWeight.w600)),
                    Text("${data['description'] ?? 'No description provided'}",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13.sp)),

                    Gap(16.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text("Reject", style: TextStyle(color: Colors.red)),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) =>
                                  AlertDialog(
                                    title: const Text("Reject Event?"),
                                    content: const Text(
                                        "Are you sure you want to reject this event?"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false),
                                          child: const Text("Cancel")),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text("Reject"),
                                      ),
                                    ],
                                  ),
                            );

                            if (confirm == true) {
                              await FirebaseFirestore.instance
                                  .collection('events')
                                  .doc(doc.id)
                                  .update({'approvalStatus': 'rejected'});

                              // Send targeted rejection notification to Organizer explicitly
                              await FirebaseFirestore.instance.collection("notifications").add({
                                "title": "Event Verification Failed",
                                "body": "Your event '${data['title']}' was rejected by the Admin.",
                                "time": FieldValue.serverTimestamp(),
                                "isRead": false,
                                "eventId": doc.id,
                                "targetUserId": data['organizerId'],
                                "targetRole": "organizer", // FIX: Lock to organizer role
                              });
                            }
                          },
                        ),
                        Gap(8.w),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: const Text("Approve", style: TextStyle(color: Colors.white)),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) =>
                                  AlertDialog(
                                    title: const Text("Approve Event?"),
                                    content: const Text(
                                        "This will make the event publicly visible. Proceed?"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false),
                                          child: const Text("Cancel")),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green),
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text("Approve"),
                                      ),
                                    ],
                                  ),
                            );

                            if (confirm == true) {
                              await FirebaseFirestore.instance
                                  .collection('events')
                                  .doc(doc.id)
                                  .update({'approvalStatus': 'approved'});

                              // Send targeted approval notification to Organizer explicitly
                              await FirebaseFirestore.instance.collection("notifications").add({
                                "title": "Event Approved!",
                                "body": "Your event '${data['title']}' is verified and publicly visible.",
                                "time": FieldValue.serverTimestamp(),
                                "isRead": false,
                                "eventId": doc.id,
                                "targetUserId": data['organizerId'],
                                "targetRole": "organizer", // FIX: Lock to organizer role
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── TAB 3: GLOBAL EVENTS MANAGEMENT ───
class _EventsTab extends StatelessWidget {
  const _EventsTab();

  @override
  Widget build(BuildContext context) {
    final SuperAdminService service = SuperAdminService();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.red));
        }
        if (snapshot.hasError) {
          return const Center(child: Text("Error fetching global events"));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text("No events on platform yet."));

        return ListView.builder(
          padding: EdgeInsets.all(16.w),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final approvalStatus = data['approvalStatus'] ?? 'approved';

            return Card(
              margin: EdgeInsets.only(bottom: 12.h),
              elevation: 2,
              child: ListTile(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) =>
                      AdminEventReportPage(eventId: doc.id, eventData: data)));
                },
                leading: const Icon(Icons.event, color: Colors.indigo),
                title: Row(
                  children: [
                    Expanded(child: Text(data['title'] ?? 'Untitled Event', style: const TextStyle(
                        fontWeight: FontWeight.bold))),
                    if (approvalStatus == 'pending') const Icon(
                        Icons.access_time, color: Colors.orange, size: 16),
                  ],
                ),
                subtitle: Text("Host: ${data['organizer'] ?? 'Unknown'}\nVenue: ${data['venue'] ??
                    ''}\nStatus: ${approvalStatus.toUpperCase()}"),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.red, size: 28),
                  tooltip: "Force Delete Event",
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            AlertDialog(
                              title: const Text("Delete Event globally?",
                                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              content: const Text(
                                  "This action is irreversible. It removes the event and wipes all related participants permanently."),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false),
                                    child: const Text("Cancel")),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red, foregroundColor: Colors.white),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text("ANNIHILATE"),
                                ),
                              ],
                            )
                    );

                    if (confirm == true) {
                      try {
                        await service.deleteEvent(doc.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text("Event annihilated!"), backgroundColor: Colors.red));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text("Delete Failed: $e"), backgroundColor: Colors.red));
                        }
                      }
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── TAB 4: SYSTEM BROADCAST ───
class _BroadcastTab extends StatefulWidget {
  const _BroadcastTab();

  @override
  State<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends State<_BroadcastTab> {
  final SuperAdminService _service = SuperAdminService();
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  bool isSending = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20.w),
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.campaign, size: 72.sp, color: Colors.redAccent),
              Gap(16.h),
              Text(
                "System Broadcast",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24.sp, fontWeight: FontWeight.bold, color: Colors.red.shade900),
              ),
              Gap(8.h),
              Text(
                "Warning: This sends a High-Priority Push Notification to EVERY user who has the app installed.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              Gap(32.h),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: "Notification Title",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              Gap(16.h),
              TextField(
                controller: bodyController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: "Message Body",
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              Gap(24.h),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  elevation: 3,
                ),
                icon: isSending
                    ? const SizedBox(width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: Text(isSending ? "Transmitting..." : "SEND GLOBAL ALERT",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: isSending ? null : () async {
                  if (titleController.text.isEmpty || bodyController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Fields cannot be empty!")));
                    return;
                  }

                  // Confirm broadcast
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        AlertDialog(
                          title: const Text("Transmit Global Alert?",
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          content: const Text(
                              "This will ping the phone of every single registered app user instantly. Are you absolutely sure?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false),
                                child: const Text("Cancel")),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Transmit"),
                            ),
                          ],
                        ),
                  );

                  if (confirm != true) return;

                  setState(() => isSending = true);
                  try {
                    await _service.sendGlobalNotification(
                        titleController.text, bodyController.text);
                    titleController.clear();
                    bodyController.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
                          "Broadcast Transmitted Globally!"), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
                          "Transmission Error: $e"), backgroundColor: Colors.red));
                    }
                  } finally {
                    if (mounted) setState(() => isSending = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── TAB 5: STAFF MANAGEMENT (SUPER ADMIN ONLY) ───
class _StaffTab extends StatefulWidget {
  const _StaffTab();

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  final SuperAdminService _service = SuperAdminService();
  final emailController = TextEditingController();
  late Future<List<dynamic>> _staffFuture;
  bool isAdding = false;

  @override
  void initState() {
    super.initState();
    _fetchStaff();
  }

  void _fetchStaff() {
    setState(() {
      _staffFuture = _service.getStaff();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Add Staff Header Form
        Container(
          color: Colors.white,
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    hintText: "Enter email to add staff...",
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
              ),
              Gap(8.w),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
                ),
                onPressed: isAdding ? null : () async {
                  if (emailController.text
                      .trim()
                      .isEmpty) return;
                  setState(() => isAdding = true);
                  try {
                    await _service.addStaff(emailController.text.trim());
                    emailController.clear();
                    _fetchStaff();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("Staff added successfully!"),
                          backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e
                          .toString()
                          .replaceAll('Exception: ', '')), backgroundColor: Colors.red));
                    }
                  } finally {
                    if (mounted) setState(() => isAdding = false);
                  }
                },
                child: isAdding
                    ? const SizedBox(width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text("ADD"),
              ),
            ],
          ),
        ),

        // Staff List
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _staffFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.red));
              }
              if (snapshot.hasError) {
                return Center(child: Text("Error fetching staff: ${snapshot.error}",
                    style: const TextStyle(color: Colors.red)));
              }

              final staff = snapshot.data ?? [];
              if (staff.isEmpty) return const Center(child: Text("No staff members yet."));

              return ListView.builder(
                padding: EdgeInsets.all(16.w),
                itemCount: staff.length,
                itemBuilder: (context, index) {
                  final s = staff[index];
                  final email = s['email'];

                  return Card(
                    margin: EdgeInsets.only(bottom: 8.h),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.black12,
                        child: Icon(Icons.admin_panel_settings, color: Colors.red),
                      ),
                      title: Text(email, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text("Staff Admin"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) =>
                                AlertDialog(
                                  title: const Text("Remove Staff?"),
                                  content: Text(
                                      "Are you sure you want to revoke staff privileges from $email?"),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false),
                                        child: const Text("Cancel")),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text("Remove"),
                                    ),
                                  ],
                                ),
                          );

                          if (confirm == true) {
                            try {
                              await _service.removeStaff(email);
                              _fetchStaff();
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Staff removed"),
                                      backgroundColor: Colors.green));
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Failed to remove: $e"),
                                      backgroundColor: Colors.red));
                            }
                          }
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}