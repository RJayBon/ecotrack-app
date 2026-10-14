import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../utils/theme.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';

/// Shown only when the database has no admin account yet. Lets the first
/// real administrator create their own credentials — there is no seeded
/// or hard-coded login anywhere in the app.
class AdminSetupScreen extends StatefulWidget {
  const AdminSetupScreen({super.key});

  @override
  State<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends State<AdminSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final username = _usernameCtrl.text.trim();
      if (await DatabaseHelper.instance.usernameExists(username)) {
        if (!mounted) return;
        setState(() => _saving = false);
        showErrorSnack(context, 'That username is already taken.');
        return;
      }

      await DatabaseHelper.instance.createAdminAccount(
        username: username,
        password: _passwordCtrl.text,
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (error, stackTrace) {
      // DEFECT FIX: a failure here (constraint violation, database not
      // ready, ...) used to escape as an unhandled async error, leaving the
      // button spinning forever with no message and no way forward.
      debugPrint('Admin setup failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Could not create the admin account.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Wrapped in Center on purpose (DEFECT FIX C3). This Column
                    // uses CrossAxisAlignment.stretch, which hands children TIGHT
                    // cross-axis constraints, so the `width: 72` below was
                    // overridden and the badge rendered as a full-width green bar
                    // 72px tall with a floating icon in it instead of a rounded
                    // 72x72 square. Center relaxes the constraint back to loose so
                    // the intrinsic width applies - which is exactly what
                    // login_screen.dart already does for its 84x84 badge.
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.eco, color: Colors.white, size: 38),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Welcome to EcoTrack',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark)),
                    const SizedBox(height: 6),
                    const Text(
                      'Set up the first administrator account to get '
                      'started. This account manages tenants, guides, '
                      'activities and rewards.',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13.5,
                          height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    LabeledField(label: 'Full name', controller: _nameCtrl, icon: Icons.badge_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null),
                    LabeledField(label: 'Email', controller: _emailCtrl, icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null),
                    LabeledField(label: 'Username', controller: _usernameCtrl, icon: Icons.person_outline,
                        validator: (v) => (v == null || v.trim().length < 3) ? 'Min 3 characters' : null),
                    LabeledField(label: 'Password', controller: _passwordCtrl, icon: Icons.lock_outline,
                        obscure: true,
                        validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null),
                    LabeledField(label: 'Confirm password', controller: _confirmCtrl, icon: Icons.lock_outline,
                        obscure: true,
                        validator: (v) => v != _passwordCtrl.text ? 'Passwords do not match' : null),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Create Admin Account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}