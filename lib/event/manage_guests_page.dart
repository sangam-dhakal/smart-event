import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:smart_event_app/participant/participant_service.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class ManageGuestsPage extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const ManageGuestsPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<ManageGuestsPage> createState() => _ManageGuestsPageState();
}

class _ManageGuestsPageState extends State<ManageGuestsPage> {
  final ParticipantService service = ParticipantService();
  String _filter = 'All';

  final List<String> _filters = [
    'All',
    'Pending Invites',
    'Pending Requests',
    'Accepted Invites',
    'Accepted Requests',
    'Rejected/Declined',
    'Attended',
    'Missed',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Manage Guests", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            Text(widget.eventTitle, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Dropdown
          Container(
            width: double.infinity,
            color: AppColors.surface,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filter,
                isExpanded: true,
                icon: const Icon(Icons.filter_list, color: AppColors.primary),
                items: _filters.map((f) => DropdownMenuItem(
                  value: f, 
                  child: Text(f, style: const TextStyle(fontWeight: FontWeight.bold))
                )).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _filter = val);
                },
              ),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: service.getEventParticipants(eventId: widget.eventId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: AppColors.error)));
                }

                final docs = snapshot.data?.docs ?? [];
                final now = DateTime.now();

                // Apply Filters dynamically
                final filteredDocs = docs.where((doc) {
                  final data = doc.data();
                  final status = data['status'] ?? '';
                  final type = data['type'] ?? 'request';
                  final attendance = data['attendance'] == true;
                  
                  // Safe date parsing
                  DateTime? eventDate;
                  if (data['eventDate'] != null && data['eventDate'] is Timestamp) {
                    eventDate = (data['eventDate'] as Timestamp).toDate();
                  }
                  bool isPast = eventDate != null && eventDate.isBefore(DateTime(now.year, now.month, now.day));

                  if (_filter == 'All') return true;
                  if (_filter == 'Pending Invites') return status == 'invited';
                  if (_filter == 'Pending Requests') return status == 'pending';
                  if (_filter == 'Accepted Invites') return status == 'accepted' && type == 'invite' && !attendance;
                  if (_filter == 'Accepted Requests') return status == 'accepted' && type == 'request' && !attendance;
                  if (_filter == 'Rejected/Declined') return status == 'rejected';
                  if (_filter == 'Attended') return attendance == true;
                  if (_filter == 'Missed') return status == 'accepted' && isPast && !attendance;
                  
                  return false;
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.group_off_outlined, size: 72, color: AppColors.border),
                        SizedBox(height: 16.h),
                        Text("No guests found for '$_filter'", style: TextStyle(fontSize: 16.sp, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.all(16.w),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final data = doc.data();
                    final name = data['name'] ?? 'Unknown';
                    final email = data['email'] ?? '';
                    final status = data['status'] ?? 'unknown';
                    final type = data['type'] ?? 'request';
                    final attendance = data['attendance'] ?? false;

                    // Re-calculate isPast for the badge logic
                    DateTime? eventDate;
                    if (data['eventDate'] != null && data['eventDate'] is Timestamp) {
                      eventDate = (data['eventDate'] as Timestamp).toDate();
                    }
                    bool isPast = eventDate != null && eventDate.isBefore(DateTime(now.year, now.month, now.day));

                    Color statusColor;
                    if (status == 'accepted') statusColor = AppColors.success;
                    else if (status == 'invited') statusColor = AppColors.info;
                    else if (status == 'pending') statusColor = AppColors.warning;
                    else statusColor = AppColors.error;

                    return Card(
                      margin: EdgeInsets.only(bottom: 12.h),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withAlpha(30),
                          child: Icon(type == 'invite' ? Icons.mail : Icons.person, color: statusColor),
                        ),
                        title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(email, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                            SizedBox(height: 8.h),
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                  decoration: BoxDecoration(
                                    color: statusColor.withAlpha(20),
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(color: statusColor.withAlpha(100)),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: statusColor),
                                  ),
                                ),
                                if (status == 'accepted' || attendance) ...[
                                  SizedBox(width: 8.w),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                    decoration: BoxDecoration(
                                      color: attendance ? AppColors.success.withAlpha(30) : (isPast ? AppColors.error.withAlpha(30) : AppColors.warning.withAlpha(30)),
                                      borderRadius: BorderRadius.circular(8.r),
                                    ),
                                    child: Text(
                                      attendance ? "PRESENT" : (isPast ? "ABSENT" : "EXPECTED"),
                                      style: TextStyle(
                                        fontSize: 10.sp, 
                                        fontWeight: FontWeight.bold, 
                                        color: attendance ? AppColors.success : (isPast ? AppColors.error : AppColors.warning)
                                      ),
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                          tooltip: "Remove Guest",
                          onPressed: () => _deleteGuest(context, doc.id, name),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _deleteGuest(BuildContext context, String docId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove Guest", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
        content: Text("Are you sure you want to remove $name from this event?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('participants').doc(docId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name removed."), backgroundColor: AppColors.success));
      }
    }
  }
}