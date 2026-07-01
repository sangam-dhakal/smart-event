import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_event_app/admin/super_admin_dashboard.dart';
import 'package:smart_event_app/admin/super_admin_service.dart';
import 'package:smart_event_app/auth/register_page.dart';
import 'package:smart_event_app/auth/role_selection_page.dart';
import 'package:smart_event_app/participant/participant_pages.dart';
import 'package:smart_event_app/providers/providers.dart';
import 'package:smart_event_app/theme/app_colors.dart';

import '../event/event_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isClick = false;
  final _loginKey = GlobalKey<FormState>();
  bool isToggle = true;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  // Load Remember Me credentials
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email') ?? '';
    final savedPassword = prefs.getString('saved_password') ?? '';
    final rememberMe = prefs.getBool('remember_me') ?? false;

    if (rememberMe) {
      setState(() {
        emailController.text = savedEmail;
        passwordController.text = savedPassword;
        isClick = true;
      });
    }
  }

  // Save Remember Me credentials
  Future<void> _handleRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (isClick) {
      await prefs.setString('saved_email', emailController.text.trim());
      await prefs.setString('saved_password', passwordController.text);
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.setBool('remember_me', false);
    }
  }

  void navigateBasedOnRole(String role) {
    if (role.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
      );
      return;
    }

    if (role == 'organizer') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EventPage()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ParticipantPages()),
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "Login Successful",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.r),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24.w),
            child: Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
                child: Form(
                  key: _loginKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Welcome Back",
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Gap(8.h),
                      Text(
                        "Sign in to continue to Smart Event",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Gap(30.h),

                      TextFormField(
                        controller: emailController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return "Email is required";
                          if (!value.contains("@"))
                            return "Enter a valid email";
                          return null;
                        },
                      ),
                      Gap(16.h),

                      TextFormField(
                        controller: passwordController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => isToggle = !isToggle),
                            icon: Icon(
                              isToggle
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        obscureText: isToggle,
                        obscuringCharacter: "•",
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return "Password is required";
                          if (value.length < 8)
                            return "Password must be at least 8 characters";
                          return null;
                        },
                      ),
                      Gap(24.h),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  if (_loginKey.currentState!.validate()) {
                                    setState(() => isLoading = true);

                                    // Handle local save preference
                                    await _handleRememberMe();

                                    final auth = ref.read(authProvider);

                                    try {
                                      final user = await auth.login(
                                        emailController.text.trim(),
                                        passwordController.text,
                                      );

                                      if (user != null) {
                                        String? managementRole;
                                        try {
                                          managementRole =
                                              await SuperAdminService()
                                                  .checkManagementRole()
                                                  .timeout(
                                                    const Duration(seconds: 5),
                                                  );
                                        } catch (err) {
                                          debugPrint(
                                            "🔴 Super Admin API Check Failed: $err",
                                          );
                                        }

                                        if (managementRole != null) {
                                          if (!mounted) return;
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  SuperAdminDashboard(
                                                    role: managementRole!,
                                                  ),
                                            ),
                                          );
                                          return;
                                        }

                                        final role = await auth.getRole(
                                          user.uid,
                                        );
                                        navigateBasedOnRole(role);
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text("Login Failed: $e"),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                    } finally {
                                      if (mounted)
                                        setState(() => isLoading = false);
                                    }
                                  }
                                },
                          child: isLoading
                              ? SizedBox(
                                  height: 20.h,
                                  width: 20.h,
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("Login"),
                        ),
                      ),

                      Gap(24.h),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.w),
                            child: Text(
                              "OR",
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      Gap(24.h),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: SvgPicture.asset(
                            'assets/image/google-icon-logo.svg',
                            height: 24.h,
                          ),
                          label: const Text(
                            "Continue with Google",
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                          onPressed: isLoading
                              ? null
                              : () async {
                                  setState(() => isLoading = true);
                                  final auth = ref.read(authProvider);

                                  try {
                                    final user = await auth.signInWithGoogle();
                                    if (user != null) {
                                      String? managementRole;
                                      try {
                                        managementRole =
                                            await SuperAdminService()
                                                .checkManagementRole()
                                                .timeout(
                                                  const Duration(seconds: 5),
                                                );
                                      } catch (err) {
                                        debugPrint(
                                          "🔴 Super Admin API Check Failed: $err",
                                        );
                                      }

                                      if (managementRole != null) {
                                        if (!mounted) return;
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => SuperAdminDashboard(
                                              role: managementRole!,
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      final role = await auth.getRole(user.uid);
                                      navigateBasedOnRole(role);
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Google Sign-In Failed: $e",
                                        ),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  } finally {
                                    if (mounted)
                                      setState(() => isLoading = false);
                                  }
                                },
                        ),
                      ),
                      Gap(16.h),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: isClick,
                                activeColor: AppColors.primary,
                                onChanged: (bool? value) {
                                  setState(() => isClick = value ?? false);
                                },
                              ),
                              const Text("Remember me"),
                            ],
                          ),
                          TextButton(
                            onPressed: () {},
                            child: const Text("Forgot Password?"),
                          ),
                        ],
                      ),

                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterPage(),
                            ),
                          );
                        },
                        child: const Text(
                          "Don't have an account? Register here",
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
