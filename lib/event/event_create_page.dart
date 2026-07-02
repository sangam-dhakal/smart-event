import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:smart_event_app/theme/app_colors.dart';
import 'event_service.dart';

class EventCreatePage extends StatefulWidget {
  final Map<String, dynamic>? eventData;
  final String? docId;

  const EventCreatePage({super.key, this.eventData, this.docId});

  @override
  State<EventCreatePage> createState() => _EventCreatePageState();
}

class _EventCreatePageState extends State<EventCreatePage> {
  final service = EventService();

  final titleController = TextEditingController();
  final organizerController = TextEditingController();
  final organizationController = TextEditingController();
  final departmentController = TextEditingController(); // NEW
  final venueController = TextEditingController();
  final descriptionController = TextEditingController(); // NEW
  final capacityController = TextEditingController(); // NEW

  DateTime? selectedDate;
  TimeOfDay? selectedTime;

  String? editingEventId;

  List<Map<String, dynamic>> predictions = [];
  double? selectedLat;
  double? selectedLng;
  bool isSearching = false;

  @override
  void initState() {
    super.initState();
    if (widget.eventData != null && widget.docId != null) {
      fillForm(widget.eventData!, widget.docId!);
    } else {
      // It's a new event, fetch and pre-fill organizer profile data
      _prefillFromProfile();
    }
  }

  // Auto-fetch the user's saved Organizer Profile details
  Future<void> _prefillFromProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          organizerController.text = data['name'] ?? '';
          organizationController.text = data['orgName'] ?? '';
          departmentController.text = data['department'] ?? '';
          venueController.text = data['location'] ?? ''; 
        });
      }
    } catch (e) {
      debugPrint("Failed to load organizer profile for pre-fill: $e");
    }
  }

  // Nominatim search (FREE - no API key)
  Future<void> searchVenue(String query) async {
    if (query.isEmpty) {
      setState(() => predictions = []);
      return;
    }

    setState(() => isSearching = true);

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=5&addressdetails=1',
      );

      final response = await http.get(uri, headers: {
        'User-Agent': 'EventSmartApp/1.0', 
      });

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          predictions = data.map<Map<String, dynamic>>((e) => {
            'name': e['display_name'],
            'lat': double.parse(e['lat']),
            'lng': double.parse(e['lon']),
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      setState(() => isSearching = false);
    }
  }

  // Convert Firestore date safely
  DateTime? safeDate(dynamic dateField) {
    if (dateField == null) return null;
    if (dateField is Timestamp) return dateField.toDate();
    if (dateField is String) return DateTime.tryParse(dateField);
    return null;
  }

  // Pick Date
  void pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  // Pick Time
  void pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() => selectedTime = picked);
    }
  }

  // Helper: Format TimeOfDay as 12-hour with AM/PM
  String formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final minute = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return "$hour:$minute $period";
  }

  // Fill form when editing
  void fillForm(Map<String, dynamic> data, String docId) {
    setState(() {
      editingEventId = docId;
      titleController.text = data['title'] ?? '';
      organizerController.text = data['organizer'] ?? '';
      organizationController.text = data['organization'] ?? '';
      departmentController.text = data['department'] ?? '';
      venueController.text = data['venue'] ?? '';
      descriptionController.text = data['description'] ?? '';
      capacityController.text = data['maxCapacity']?.toString() ?? '';
      
      selectedDate = safeDate(data['date']);
      selectedLat = (data['lat'] as num?)?.toDouble();
      selectedLng = (data['lng'] as num?)?.toDouble();

      if (data['time'] != null) {
        try {
          final timeString = data['time'].toString();
          final parts = timeString.split(':');
          if (parts.length >= 2) {
            final hour = int.tryParse(parts[0]) ?? 0;
            final minute = int.tryParse(parts[1]) ?? 0;
            selectedTime = TimeOfDay(hour: hour, minute: minute);
          }
        } catch (e) {
          selectedTime = null; 
        }
      }
    });
  }

  // Submit Event
  void submitEvent() {
    if (titleController.text.isEmpty ||
        organizerController.text.isEmpty ||
        venueController.text.isEmpty ||
        descriptionController.text.isEmpty ||
        capacityController.text.isEmpty ||
        selectedDate == null ||
        selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields"), backgroundColor: AppColors.error)
      );
      return;
    }

    int? capacity = int.tryParse(capacityController.text.trim());
    if (capacity == null || capacity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Max Capacity must be a valid positive number"), backgroundColor: AppColors.error)
      );
      return;
    }

    final data = {
      "title": titleController.text.trim(),
      "organizer": organizerController.text.trim(),
      "organization": organizationController.text.trim(),
      "department": departmentController.text.trim(),
      "description": descriptionController.text.trim(),
      "maxCapacity": capacity,
      "venue": venueController.text.trim(),
      "lat": selectedLat, 
      "lng": selectedLng,
      "date": Timestamp.fromDate(selectedDate!),
      "time": "${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}",
      "organizerId": FirebaseAuth.instance.currentUser!.uid,
    };

    if (editingEventId != null) {
      service.updateEvent(editingEventId!, data);
      editingEventId = null;
    } else {
      service.createEvent(data);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Event Saved successfully"), backgroundColor: AppColors.success)
    );

    Navigator.pop(context); 
  }

  @override
  void dispose() {
    titleController.dispose();
    organizerController.dispose();
    organizationController.dispose();
    departmentController.dispose();
    venueController.dispose();
    descriptionController.dispose();
    capacityController.dispose();
    super.dispose();
  }

  Widget buildTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType type = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      maxLines: maxLines,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: maxLines == 1 ? Icon(icon) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editingEventId != null ? "Update Event" : "Create Event"),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24.w),
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildTextField(titleController, "Event Title *", Icons.event),
                const Gap(16),
                buildTextField(descriptionController, "Event Description *", Icons.description, maxLines: 3),
                const Gap(16),
                
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: buildTextField(organizerController, "Host Name *", Icons.person),
                    ),
                    Gap(12.w),
                    Expanded(
                      flex: 1,
                      child: buildTextField(capacityController, "Capacity *", Icons.group_add, type: TextInputType.number),
                    ),
                  ],
                ),
                
                const Gap(16),
                buildTextField(organizationController, "Organization Name", Icons.business),
                const Gap(16),
                buildTextField(departmentController, "Department", Icons.groups),
                const Gap(16),
                
                // Venue Search
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: venueController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: "Venue Location *",
                        prefixIcon: const Icon(Icons.location_on),
                        suffixIcon: isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : venueController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        venueController.clear();
                                        predictions = [];
                                        selectedLat = null;
                                        selectedLng = null;
                                      });
                                    },
                                  )
                                : null,
                      ),
                      onChanged: (value) {
                        Future.delayed(const Duration(milliseconds: 600), () {
                          if (venueController.text == value) searchVenue(value);
                        });
                      },
                    ),

                    // Suggestions list
                    if (predictions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(20),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: predictions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final p = predictions[index];
                            
                            final fullName = p['name'] as String;
                            final parts = fullName.split(',');
                            final mainText = parts[0].trim();
                            final subText = parts.length > 1
                                ? parts.sublist(1, parts.length > 3 ? 3 : parts.length)
                                    .join(',')
                                    .trim()
                                : '';

                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place, color: AppColors.primary, size: 20),
                              title: Text(
                                mainText,
                                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                              ),
                              subtitle: subText.isNotEmpty
                                  ? Text(
                                      subText,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              onTap: () {
                                setState(() {
                                  venueController.text = mainText;
                                  selectedLat = p['lat'];
                                  selectedLng = p['lng'];
                                  predictions = [];
                                });
                              },
                            );
                          },
                        ),
                      ),

                    // Location selected indicator
                    if (selectedLat != null && selectedLng != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: AppColors.success.withAlpha(30),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: AppColors.success.withAlpha(100)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              "Location pinned successfully",
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const Gap(16),

                // Date & Time
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.calendar_today,
                            color: AppColors.primary,
                          ),
                          title: Text(
                            selectedDate == null
                                ? "Date *"
                                : "${selectedDate!.day}-${selectedDate!.month}-${selectedDate!.year}",
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          onTap: pickDate,
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.access_time,
                            color: AppColors.primary,
                          ),
                          title: Text(
                            selectedTime == null
                                ? "Time *"
                                : formatTimeOfDay(selectedTime!),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          onTap: pickTime,
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(32),

                ElevatedButton.icon(
                  onPressed: submitEvent,
                  icon: const Icon(Icons.save),
                  label: Text(
                    editingEventId != null ? "Update Event" : "Create Event",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}