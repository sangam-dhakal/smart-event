import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/event/csv_import_page.dart';
import 'package:smart_event_app/event/feedback_list_page.dart';
import 'package:smart_event_app/event/manage_guests_page.dart';
import 'package:smart_event_app/participant/feedback_form_page.dart';
import 'package:smart_event_app/participant/participant_page.dart';
import 'package:smart_event_app/participant/participant_service.dart';
import 'package:smart_event_app/participant/pending_participants_page.dart';
import 'package:smart_event_app/qr/qr_page.dart';
import 'package:smart_event_app/qr/qr_scanner_page.dart';
import 'package:smart_event_app/services/auth_service.dart';
import 'package:smart_event_app/services/local_db_service.dart';
import 'package:smart_event_app/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

class EventDetailsPage extends StatelessWidget {
  final Map<String, dynamic> eventData;
  final DateTime? eventDate;
  final String eventId;

  const EventDetailsPage({
    super.key,
    required this.eventData,
    this.eventDate,
    required this.eventId,
  });

  TimeOfDay? parseTime(String? timeString) {
    if (timeString == null || !timeString.contains(':')) return null;
    final parts = timeString.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final minute = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return "$hour:$minute $period";
  }

  // ─── OFFLINE FEATURE LOGIC ───
  Future<void> _downloadForOffline(BuildContext context) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Downloading list...")));

      final snapshot = await FirebaseFirestore.instance
          .collection('participants')
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'accepted')
          .get();

      final list = snapshot.docs.map((d) => d.data()).toList();

      await LocalDbService().saveParticipantsOffline(list);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Downloaded ${list.length} expected guests for offline scanning!",
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Download failed: $e"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _syncOfflineData(BuildContext context) async {
    try {
      final pending = await LocalDbService().getPendingSyncs(eventId);

      if (pending.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No offline scans to sync.")),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Syncing ${pending.length} scans to Cloud...")),
      );

      final batch = FirebaseFirestore.instance.batch();
      for (var p in pending) {
        final guestId = p['guestId'];
        final query = await FirebaseFirestore.instance
            .collection('participants')
            .where('guestId', isEqualTo: guestId)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          batch.update(query.docs.first.reference, {
            'attendance': true,
            'checkInTime': FieldValue.serverTimestamp(),
          });
        }
        await LocalDbService().markSynced(guestId);
      }

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cloud Sync complete!"),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sync failed: $e"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─────────────────────────────

  // Shows dialog for manual VIP guest invite
  void _showSingleInviteDialog(BuildContext context,
      String eventId,
      String eventTitle,
      String organizerId,) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;
    bool sendEmail = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                  "Invite Single Guest", style: TextStyle(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Guest Name",
                      ),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                    const Gap(16),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: "Guest Email",
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return "Required";
                        if (!RegExp(
                          r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                        ).hasMatch(v)) {
                          return "Invalid email";
                        }
                        return null;
                      },
                    ),
                    const Gap(16),
                    CheckboxListTile(
                      title: const Text(
                        "Send Email Invitation",
                        style: TextStyle(fontSize: 14),
                      ),
                      value: sendEmail,
                      onChanged: (val) =>
                          setState(() => sendEmail = val ?? true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                    if (formKey.currentState!.validate()) {
                      // Added Confirmation Dialog
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (_) =>
                            AlertDialog(
                              title: const Text("Send Invite?"),
                              content: Text(
                                  "Are you sure you want to invite ${nameController.text}?"),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text("Cancel")),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("Yes, Send"),
                                ),
                              ],
                            ),
                      );

                      if (confirm != true) return;

                      setState(() => isLoading = true);
                      try {
                        await ParticipantService().inviteSingleGuest(
                          eventId: eventId,
                          eventTitle: eventTitle,
                          organizerId: organizerId,
                          name: nameController.text,
                          email: emailController.text,
                          sendEmail: sendEmail,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Guest invited successfully!",
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() => isLoading = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceAll("Exception: ", ""),
                            ),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  },
                  child: isLoading
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text("Send Invite"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOrganizerActionGroups(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text("SCAN QR TICKETS", style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: EdgeInsets.symmetric(vertical: 16.h),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QRScannerPage(eventId: eventId),
                ),
              );
            },
          ),
        ),
        Gap(16.h),

        // GROUP 1: Manage Participants
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r), side: BorderSide(color: AppColors.border)),
          child: ExpansionTile(
            leading: const Icon(Icons.people_alt, color: AppColors.primary),
            title: const Text("Manage Participants", style: TextStyle(fontWeight: FontWeight.bold)),
            childrenPadding: EdgeInsets.all(16.w),
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.people),
                  label: const Text("Manage Guests"),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) =>
                        ManageGuestsPage(eventId: eventId, eventTitle: eventData['title'] ?? "")));
                  },
                ),
              ),
              Gap(8.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text("View Join Requests"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary.withAlpha(200)),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) =>
                        PendingParticipantsPage(
                            eventId: eventId, eventTitle: eventData['title'] ?? "")));
                  },
                ),
              ),
            ],
          ),
        ),
        Gap(8.h),

        // GROUP 2: Mail Invitations
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r), side: BorderSide(color: AppColors.border)),
          child: ExpansionTile(
            leading: const Icon(Icons.mail_outline, color: AppColors.warning),
            title: const Text("Mail Invitations", style: TextStyle(fontWeight: FontWeight.bold)),
            childrenPadding: EdgeInsets.all(16.w),
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text("Invite Single Guest (VIP)"),
                  onPressed: () =>
                      _showSingleInviteDialog(context, eventId, eventData['title'] ?? "",
                          eventData['organizerId'] ?? ""),
                ),
              ),
              Gap(8.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Import Invitees (CSV)"),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) =>
                        CsvImportPage(eventId: eventId,
                            eventTitle: eventData['title'] ?? "",
                            organizerId: eventData['organizerId'] ?? "")));
                  },
                ),
              ),
            ],
          ),
        ),
        Gap(8.h),

        // GROUP 3: Event Feedback
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r), side: BorderSide(color: AppColors.border)),
          child: ListTile(
            leading: const Icon(Icons.star, color: AppColors.accent),
            title: const Text("View Event Feedback", style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) =>
                  FeedbackListPage(eventId: eventId, eventTitle: eventData['title'] ?? "")));
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("User not logged in")));
    }
    final authService = AuthService();
    final time = parseTime(eventData['time']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Details'),
        actions: [
          // If Organizer, show offline tool popup menu to prevent clutter
          FutureBuilder<String>(
            future: authService.getRole(user.uid),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data == 'organizer' &&
                  eventData['organizerId'] == user.uid) {
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) {
                    if (val == 'download') _downloadForOffline(context);
                    if (val == 'sync') _syncOfflineData(context);
                  },
                  itemBuilder: (_) =>
                  [
                    const PopupMenuItem(value: 'download', child: Row(children: [Icon(Icons
                        .download, color: AppColors.secondary), SizedBox(width: 8), Text(
                        "Download Offline Data")
                    ])),
                    const PopupMenuItem(value: 'sync', child: Row(children: [Icon(Icons.cloud_sync,
                        color: AppColors.info), SizedBox(width: 8), Text("Sync Offline Scans")])),
                  ],
                );
              }
              return const SizedBox();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //EVENT CARD
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eventData['title'] ?? '',
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    if (eventData['description'] != null && eventData['description']
                        .toString()
                        .isNotEmpty) ...[
                      Gap(8.h),
                      Text(eventData['description'],
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp)),
                    ],
                    const Gap(16),
                    Row(
                      children: [
                        const Icon(Icons.person, color: AppColors.primary),
                        SizedBox(width: 8.w),
                        Text(eventData['organizer'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const Gap(8),
                    Row(
                      children: [
                        const Icon(Icons.business, color: AppColors.primary),
                        SizedBox(width: 8.w),
                        Text(eventData['organization'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const Gap(8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primary),
                        SizedBox(width: 8.w),
                        Expanded(child: Text(eventData['venue'] ?? '', style: const TextStyle(
                            fontWeight: FontWeight.w500))),
                      ],
                    ),
                    // Hide View on Map if this user is the organizer of this event
                    if (eventData['lat'] != null && eventData['lng'] != null &&
                        eventData['organizerId'] != user.uid) ...[
                      const Gap(12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.map_outlined),
                          label: const Text("View on Map"),
                          onPressed: () async {
                            final lat = eventData['lat'];
                            final lng = eventData['lng'];
                            final uri = Uri.parse(
                              "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
                            );
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                    const Gap(16),
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, color: AppColors.primary, size: 18),
                              SizedBox(width: 8.w),
                              Text(
                                eventDate != null
                                    ? "${eventDate!.day}-${eventDate!.month}-${eventDate!.year}"
                                    : '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, color: AppColors.primary),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.access_time, color: AppColors.primary, size: 18),
                              const Gap(8),
                              Text(
                                time != null ? formatTimeOfDay(time) : '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, color: AppColors.primary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24.h),

            // ROLE-BASED BUTTON
            FutureBuilder<String>(
              future: authService.getRole(user.uid),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final role = snapshot.data;

                // ── PARTICIPANT DYNAMIC UI ──
                if (role == "participant") {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('participants')
                        .where('userId', isEqualTo: user.uid)
                        .where('eventId', isEqualTo: eventId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // Check if participant record exists
                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                        final doc = snapshot.data!.docs.first;
                        final pData = doc.data() as Map<String, dynamic>;
                        final status = pData['status'] ?? '';
                        final type = pData['type'] ?? 'request';
                        final attendance = pData['attendance'] == true;

                        if (status == 'invited') {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: EdgeInsets.all(16.w),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withAlpha(30),
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(
                                    color: AppColors.warning.withAlpha(100),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.mail,
                                      color: AppColors.warning,
                                    ),
                                    SizedBox(width: 12.w),
                                    const Expanded(
                                      child: Text(
                                        "You have been invited to this event!",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.warning,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Gap(16.h),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.error,
                                        side: const BorderSide(
                                          color: AppColors.error,
                                        ),
                                      ),
                                      onPressed: () async {
                                        await ParticipantService()
                                            .respondToInvite(
                                          doc.id,
                                          'rejected',
                                        );
                                      },
                                      child: const Text("Decline"),
                                    ),
                                  ),
                                  Gap(12.w),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                      ),
                                      onPressed: () async {
                                        try {
                                          await ParticipantService().respondToInvite(
                                              doc.id, 'accepted');
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                content: Text(
                                                    e.toString().replaceAll("Exception: ", "")),
                                                backgroundColor: AppColors.warning));
                                          }
                                        }
                                      },
                                      child: const Text("Accept Invitation"),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        } else if (status == 'pending') {
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.warning,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: null,
                              icon: const Icon(Icons.hourglass_top, color: Colors.white),
                              label: const Text("Request Pending Approval",
                                  style: TextStyle(color: Colors.white)),
                            ),
                          );
                        } else if (status == 'accepted') {
                          return Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            QRPage(
                                              guestId: pData['guestId'],
                                              eventId: eventId,
                                            ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.qr_code),
                                  label: Text(
                                    type == 'invite'
                                        ? "Accepted Invitation - View QR Ticket"
                                        : "Request Approved - View QR Ticket",
                                  ),
                                ),
                              ),
                              // ── Post-Event Feedback Button (Only if attended) ──
                              if (attendance) ...[
                                Gap(12.h),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: AppColors.primary,
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              FeedbackFormPage(
                                                eventId: eventId,
                                                participantName:
                                                pData['name'] ?? 'Guest',
                                              ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.star),
                                    label: const Text(
                                      "Rate & Review Event",
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        } else if (status == 'rejected') {
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                disabledBackgroundColor: AppColors.error.withAlpha(50),
                                disabledForegroundColor: AppColors.error,
                              ),
                              onPressed: null,
                              icon: const Icon(Icons.cancel),
                              label: Text(
                                type == 'invite'
                                    ? "Invitation Declined"
                                    : "Request Denied",
                              ),
                            ),
                          );
                        }
                      }

                      // Check if event is approved by super admin. If not, block applying.
                      final approvalStatus = eventData['approvalStatus'] ?? 'approved';
                      if (approvalStatus != 'approved') {
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              disabledBackgroundColor: AppColors.border,
                              disabledForegroundColor: AppColors.textSecondary,
                            ),
                            onPressed: null,
                            icon: const Icon(Icons.lock_clock),
                            label: const Text("EVENT PENDING VERIFICATION"),
                          ),
                        );
                      }

                      // Safety Check: Make sure the creator cannot apply to their own event!
                      if (eventData['organizerId'] == user.uid) {
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              disabledBackgroundColor: AppColors.border,
                              disabledForegroundColor: AppColors.textSecondary,
                            ),
                            onPressed: null,
                            icon: const Icon(Icons.shield),
                            label: const Text("YOU ARE THE ORGANIZER"),
                          ),
                        );
                      }

                      // Check if Registration Deadline has passed
                      DateTime? regDeadline;
                      if (eventData['registrationDeadline'] != null) {
                        regDeadline = (eventData['registrationDeadline'] as Timestamp).toDate();
                      }
                      bool isRegClosed = regDeadline != null && DateTime.now().isAfter(regDeadline);

                      if (isRegClosed) {
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              disabledBackgroundColor: AppColors.border,
                              disabledForegroundColor: AppColors.textSecondary,
                            ),
                            onPressed: null,
                            icon: const Icon(Icons.timer_off),
                            label: const Text("REGISTRATION CLOSED"),
                          ),
                        );
                      }

                      // Default: Not applied, not invited, and registration is open -> Show Apply button
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                          ),
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ParticipantPage(
                                      eventId: eventId,
                                      organizerId: eventData['organizerId'] ?? '',
                                    ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.send),
                          label: const Text("APPLY FOR EVENT"),
                        ),
                      );
                    },
                  );
                }

                // ── ORGANIZER UI ──
                if (role == "organizer" && eventData['organizerId'] == user.uid) {
                  return _buildOrganizerActionGroups(context);
                }

                return const SizedBox();
              },
            ),
          ],
        ),
      ),
    );
  }
}