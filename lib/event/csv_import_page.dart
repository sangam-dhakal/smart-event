import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/participant/participant_service.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class CsvImportPage extends StatefulWidget {
  final String eventId;
  final String eventTitle;
  final String organizerId;

  const CsvImportPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.organizerId,
  });

  @override
  State<CsvImportPage> createState() => _CsvImportPageState();
}

class _CsvImportPageState extends State<CsvImportPage> {
  final ParticipantService _service = ParticipantService();

  List<List<dynamic>> _csvData = [];
  List<String> _headers = [];
  
  String? _nameHeader;
  String? _emailHeader;
  String? _departmentHeader;

  List<Map<String, dynamic>> _parsedGuests = [];
  Set<String> _existingEmails = {};

  bool _isLoading = false;
  bool _isFetchingExisting = true;
  
  // Safety defaults
  bool _sendEmail = false; 

  // Search and Select functionalities
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchExistingParticipants();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Fetch emails of people already in this event to prevent duplicates
  Future<void> _fetchExistingParticipants() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('participants')
          .where('eventId', isEqualTo: widget.eventId)
          .get();

      setState(() {
        _existingEmails = snapshot.docs
            .map((doc) => doc.data()['email'].toString().toLowerCase().trim())
            .toSet();
        _isFetchingExisting = false;
      });
    } catch (e) {
      debugPrint("Error fetching existing participants: $e");
      setState(() => _isFetchingExisting = false);
    }
  }

  // Lightweight native CSV Parser
  List<List<dynamic>> _parseCsv(String input) {
    List<List<dynamic>> rows = [];
    List<dynamic> currentRow = [];
    StringBuffer currentField = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < input.length; i++) {
      String char = input[i];

      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            currentField.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          currentField.write(char);
        }
      } else {
        if (char == '"') {
          inQuotes = true;
        } else if (char == ',') {
          currentRow.add(currentField.toString().trim());
          currentField.clear();
        } else if (char == '\n' || char == '\r') {
          if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') {
            i++; 
          }
          currentRow.add(currentField.toString().trim());
          if (currentRow.any((field) => field.toString().isNotEmpty)) {
            rows.add(currentRow);
          }
          currentRow = [];
          currentField.clear();
        } else {
          currentField.write(char);
        }
      }
    }
    if (currentField.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentField.toString().trim());
      if (currentRow.any((field) => field.toString().isNotEmpty)) {
        rows.add(currentRow);
      }
    }
    return rows;
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final input = File(path).readAsStringSync();
        
        final rows = _parseCsv(input);

        if (rows.length > 1) {
          setState(() {
            _csvData = rows;
            _headers = rows.first.map((e) => e.toString().trim()).toList();
            _nameHeader = null;
            _emailHeader = null;
            _departmentHeader = null;
            _parsedGuests = [];
            _searchQuery = '';
            _searchController.clear();
          });
        } else {
          _showError("CSV file is empty or missing headers.");
        }
      }
    } catch (e) {
      _showError("Failed to pick file: $e");
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
        .hasMatch(email);
  }

  void _processPreview() {
    if (_nameHeader == null || _emailHeader == null) return;

    if (_nameHeader == _emailHeader) {
      setState(() => _parsedGuests = []);
      return;
    }

    int nameIndex = _headers.indexOf(_nameHeader!);
    int emailIndex = _headers.indexOf(_emailHeader!);
    int deptIndex = _departmentHeader != null ? _headers.indexOf(_departmentHeader!) : -1;

    List<Map<String, dynamic>> guests = [];

    for (int i = 1; i < _csvData.length; i++) {
      final row = _csvData[i];
      if (row.length > nameIndex && row.length > emailIndex) {
        String name = row[nameIndex].toString().trim();
        String email = row[emailIndex].toString().trim();
        String department = (deptIndex != -1 && row.length > deptIndex) ? row[deptIndex].toString().trim() : '';

        bool isValid = _isValidEmail(email);
        bool isDuplicate = _existingEmails.contains(email.toLowerCase());

        guests.add({
          'name': name,
          'email': email,
          'department': department,
          'isValid': isValid,
          'isDuplicate': isDuplicate,
          'selected': false, // NO AUTO-SELECT: Organizer must manually review and select
        });
      }
    }

    setState(() => _parsedGuests = guests);
  }

  // Derived filtered list for the UI
  List<Map<String, dynamic>> get _filteredGuests {
    if (_searchQuery.isEmpty) return _parsedGuests;
    return _parsedGuests.where((g) {
      final name = g['name'].toString().toLowerCase();
      final email = g['email'].toString().toLowerCase();
      final dept = g['department'].toString().toLowerCase();
      return name.contains(_searchQuery) || email.contains(_searchQuery) || dept.contains(_searchQuery);
    }).toList();
  }

  void _selectAllFiltered() {
    setState(() {
      for (var g in _filteredGuests) {
        if (g['isValid'] && !g['isDuplicate']) {
          g['selected'] = true;
        }
      }
    });
  }

  void _deselectAllFiltered() {
    setState(() {
      for (var g in _filteredGuests) {
        g['selected'] = false;
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _importData() async {
    final selectedGuests = _parsedGuests.where((g) => g['selected'] == true).toList();

    if (selectedGuests.isEmpty) {
      _showError("No valid guests selected for import.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final guestsToImport = selectedGuests.map((g) => {
        'name': g['name'] as String,
        'email': g['email'] as String,
        'department': g['department'] as String,
      }).toList();

      await _service.importInvitees(
        eventId: widget.eventId,
        eventTitle: widget.eventTitle,
        organizerId: widget.organizerId,
        guests: guestsToImport,
        sendEmail: _sendEmail,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Successfully invited ${guestsToImport.length} guests!", style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      _showError("Error during import: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetchingExisting) {
      return Scaffold(
        appBar: AppBar(title: const Text("Import Invitees (CSV)")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Import Invitees (CSV)"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("1. Select CSV File", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                          Gap(10.h),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.upload_file),
                              label: const Text("Upload CSV"),
                            ),
                          ),
                          if (_headers.isNotEmpty) ...[
                            Gap(10.h),
                            Text("File loaded with ${_csvData.length - 1} rows.", style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                          ]
                        ],
                      ),
                    ),
                  ),
                  Gap(16.h),

                  if (_headers.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("2. Map CSV Columns", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                            Gap(16.h),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: "Name Column *"),
                              value: _nameHeader,
                              items: _headers.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _nameHeader = val;
                                  if (_nameHeader == _emailHeader) _emailHeader = null; 
                                });
                                _processPreview();
                              },
                            ),
                            Gap(16.h),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: "Email Column *"),
                              value: _emailHeader,
                              items: _headers.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _emailHeader = val;
                                  if (_emailHeader == _nameHeader) _nameHeader = null;
                                });
                                _processPreview();
                              },
                            ),
                            Gap(16.h),
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: "Department Column (Optional)"),
                              value: _departmentHeader,
                              items: [
                                const DropdownMenuItem<String>(value: null, child: Text("None")),
                                ..._headers.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList()
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _departmentHeader = val;
                                });
                                _processPreview();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  Gap(16.h),

                  if (_parsedGuests.isNotEmpty && _nameHeader != null && _emailHeader != null)
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("3. Review & Invite", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                            Gap(16.h),
                            
                            // Email Settings Checkbox
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.info.withAlpha(20),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: AppColors.info.withAlpha(80)),
                              ),
                              child: CheckboxListTile(
                                title: const Text("Send Email Invitations", style: TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: const Text("Fires EmailJS API for the selected guests below."),
                                value: _sendEmail,
                                onChanged: (val) => setState(() => _sendEmail = val ?? false),
                                activeColor: AppColors.primary,
                                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                              ),
                            ),
                            Gap(16.h),

                            // Search Bar
                            TextField(
                              controller: _searchController,
                              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase().trim()),
                              decoration: const InputDecoration(
                                hintText: "Search name, email, dept...",
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            Gap(16.h),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Selected: ${_parsedGuests.where((g) => g['selected'] == true).length}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: _selectAllFiltered, 
                                      child: const Text("Select All")
                                    ),
                                    TextButton(
                                      onPressed: _deselectAllFiltered, 
                                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                                      child: const Text("Clear")
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Gap(8.h),

                            // The Guest List
                            Container(
                              height: 350.h,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: _filteredGuests.isEmpty
                                  ? const Center(child: Text("No matching guests", style: TextStyle(color: AppColors.textSecondary)))
                                  : ListView.separated(
                                      itemCount: _filteredGuests.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final guest = _filteredGuests[index];
                                        final isDuplicate = guest['isDuplicate'];
                                        final isValid = guest['isValid'];

                                        Widget secondaryIcon;
                                        if (isDuplicate) secondaryIcon = const Icon(Icons.info, color: AppColors.warning, size: 20);
                                        else if (isValid) secondaryIcon = const Icon(Icons.check_circle, color: AppColors.success, size: 20);
                                        else secondaryIcon = const Icon(Icons.error, color: AppColors.error, size: 20);

                                        return CheckboxListTile(
                                          value: guest['selected'],
                                          onChanged: (isValid && !isDuplicate) ? (val) {
                                            setState(() => guest['selected'] = val ?? false);
                                          } : null,
                                          title: Text(guest['name'], style: TextStyle(color: isDuplicate ? AppColors.textSecondary : AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                          subtitle: Text(
                                            isDuplicate ? "Already in system" : "${guest['email']} ${guest['department'].toString().isNotEmpty ? '• ${guest['department']}' : ''}", 
                                            style: TextStyle(color: isDuplicate ? AppColors.warning : (isValid ? AppColors.textSecondary : AppColors.error)),
                                          ),
                                          secondary: secondaryIcon,
                                          controlAffinity: ListTileControlAffinity.leading,
                                          activeColor: AppColors.primary,
                                        );
                                      },
                                    ),
                            ),
                            Gap(24.h),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _parsedGuests.any((g) => g['selected'] == true) ? _importData : null,
                                icon: const Icon(Icons.send),
                                label: const Text("Confirm & Invite Selected"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}