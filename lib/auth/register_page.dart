// ignore_for_file: must_be_immutable, use_build_context_synchronously

import 'package:smart_event_app/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:smart_event_app/theme/app_colors.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  
  // Organizer Extra Fields
  final orgNameController = TextEditingController();
  final departmentController = TextEditingController();
  final locationController = TextEditingController();

  String role = "participant"; //default selected role
  bool showRoleOptions = false; //track toggle
  final _formKey = GlobalKey<FormState>();
  bool isHidden = true;
  bool isLoading = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    orgNameController.dispose();
    departmentController.dispose();
    locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Register"),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24.w),
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Text(
                    "Create an Account",
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Gap(8.h),
                  Text(
                    "Join Smart Event today",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Gap(24.h),
                  
                  // Role selection card (Moved to Top for better flow)
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.badge_outlined),
                            title: Text(
                              role.isEmpty ? "Select Role" : role[0].toUpperCase() + role.substring(1),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            trailing: Icon(showRoleOptions ? Icons.arrow_drop_up : Icons.arrow_drop_down),
                            onTap: () {
                              setState(() => showRoleOptions = !showRoleOptions);
                            },
                          ),
                        ),
                        if (showRoleOptions)
                          Container(
                            margin: EdgeInsets.only(top: 8.h),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Column(
                              children: [
                                RadioListTile<String>(
                                  value: "organizer",
                                  groupValue: role,
                                  activeColor: AppColors.primary,
                                  title: const Text("Organizer"),
                                  onChanged: (value) {
                                    setState(() {
                                      role = value!;
                                      showRoleOptions = false;
                                    });
                                  },
                                ),
                                RadioListTile<String>(
                                  value: "participant",
                                  groupValue: role,
                                  activeColor: AppColors.primary,
                                  title: const Text("Participant"),
                                  onChanged: (value) {
                                    setState(() {
                                      role = value!;
                                      showRoleOptions = false;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Gap(16.h),

                  // Standard Fields
                  TextFormField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Full Name",
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return "Name is required";
                      return null;
                    },
                  ),
                  Gap(16.h),
                  
                  TextFormField(
                    controller: emailController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Email Address",
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return "Email is required";
                      if (!value.contains("@")) return "Enter a valid email";
                      return null;
                    },
                  ),
                  Gap(16.h),

                  // ─── DYNAMIC ORGANIZER FIELDS ───
                  if (role == 'organizer') ...[
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withAlpha(20),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: AppColors.secondary.withAlpha(100)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Organizer Details", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondary, fontSize: 12.sp)),
                          Gap(8.h),
                          TextFormField(
                            controller: orgNameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: "Organization Name",
                              prefixIcon: Icon(Icons.business),
                            ),
                            validator: (value) => value == null || value.isEmpty ? "Required" : null,
                          ),
                          Gap(12.h),
                          TextFormField(
                            controller: departmentController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: "Department",
                              prefixIcon: Icon(Icons.groups),
                            ),
                            validator: (value) => value == null || value.isEmpty ? "Required" : null,
                          ),
                          Gap(12.h),
                          TextFormField(
                            controller: locationController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: "Location",
                              prefixIcon: Icon(Icons.location_city),
                            ),
                            validator: (value) => value == null || value.isEmpty ? "Required" : null,
                          ),
                        ],
                      ),
                    ),
                    Gap(16.h),
                  ],
                  // ────────────────────────────────
                  
                  TextFormField(
                    controller: passwordController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => isHidden = !isHidden),
                        icon: Icon(isHidden ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                    obscureText: isHidden,
                    obscuringCharacter: "•",
                    validator: (value) {
                      if (value == null || value.isEmpty) return "Password is required";
                      if (value.length < 8) return "Password must be at least 8 characters";
                      return null;
                    },
                  ),
                  Gap(16.h),
                  
                  TextFormField(
                    controller: confirmController,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: "Confirm Password",
                      prefixIcon: const Icon(Icons.lock_reset),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => isHidden = !isHidden),
                        icon: Icon(isHidden ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                    obscureText: isHidden,
                    obscuringCharacter: "•",
                    validator: (value) {
                      if (value == null || value.isEmpty) return "Confirm Password is required";
                      if (value != passwordController.text) return "Passwords do not match";
                      return null;
                    },
                  ),
                  Gap(32.h),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              if (_formKey.currentState!.validate()) {
                                setState(() => isLoading = true);
                                final auth = ref.read(authProvider);

                                try {
                                  await auth.register(
                                    nameController.text.trim(),
                                    emailController.text.trim(),
                                    passwordController.text.trim(),
                                    confirmController.text.trim(),
                                    role,
                                    orgName: role == 'organizer' ? orgNameController.text : null,
                                    department: role == 'organizer' ? departmentController.text : null,
                                    location: role == 'organizer' ? locationController.text : null,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                        "Register Successful",
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: AppColors.success,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                                    ),
                                  );
                                  Navigator.pop(context);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error),
                                  );
                                } finally {
                                  if (mounted) setState(() => isLoading = false);
                                }
                              }
                            },
                      child: isLoading
                          ? SizedBox(
                              height: 20.h,
                              width: 20.h,
                              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text("Create Account"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}