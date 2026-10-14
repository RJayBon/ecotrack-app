import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../utils/theme.dart';
import '../widgets/common_widgets.dart';
import 'admin/admin_dashboard_screen.dart';
import 'tenant/tenant_home_screen.dart';

/// Single shared login screen for both Admin and Tenant accounts.
/// Credentials are verified against SQLite; role is read from the users
/// table and used to route to the correct dashboard. No demo buttons,
/// no auto-login, no hard-coded accounts.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  /// Single exit for every failure in [_login]: clears the busy flag and shows
  /// [message], but only while this State is alive.
  ///
  /// DEFECT FIX (B1): `_login` had no try/catch at all. `authenticate()` opens
  /// the database, so any failure there - file not openable, missing libsqlite3
  /// on Linux, absent web wasm assets, a failed migration, a corrupt file -
  /// escaped as an unhandled async error and left `_loading` true forever. That
  /// kept `onPressed: _loading ? null : _login` permanently disabled with a
  /// spinner and showed no message, and because this is the one screen the user
  /// cannot navigate away from, the only recovery was killing the app.
  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final Map<String, dynamic>? result;
    try {
      result = await DatabaseHelper.instance.authenticate(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );
    } catch (error, stackTrace) {
      debugPrint('Login failed: $error\n$stackTrace');
      _fail('Could not reach the local database. Close and reopen the app, '
          'and if it keeps happening contact your administrator.');
      return;
    }

    if (!mounted) return;
    if (result == null) {
      _fail('Invalid username or password.');
      return;
    }
    final role = result['role'] as String;
    final userId = result['userId'] as int;

    try {
      if (role == 'admin') {
        final admin = await DatabaseHelper.instance.getAdminByUserId(userId);
        if (!mounted) return;
        if (admin == null) {
          _fail('Admin profile is missing. Please contact support.');
          return;
        }
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                AdminDashboardScreen(adminUserId: userId, admin: admin),
          ),
        );
      } else {
        final tenant = await DatabaseHelper.instance.getTenantByUserId(userId);
        if (!mounted) return;
        if (tenant == null) {
          _fail('Tenant record not found.');
          return;
        }
        if (tenant.status == 'inactive') {
          // Same wording DatabaseHelper returns from completeActivity /
          // redeemReward, so a tenant blocked at the door and one deactivated
          // mid-session see one consistent message.
          _fail(kTenantDeactivatedMessage);
          return;
        }
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => TenantHomeScreen(tenantUserId: userId)),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Post-login lookup failed: $error\n$stackTrace');
      _fail('Signed in, but your profile could not be loaded. Please try again.');
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
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          gradient: AppColors.heroGradient,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.eco, color: Colors.white, size: 44),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('EcoTrack',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                    const SizedBox(height: 4),
                    const Text('Waste management & eco habits, made simple.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
                    const SizedBox(height: 32),
                    LabeledField(
                      label: 'Username',
                      controller: _usernameCtrl,
                      icon: Icons.person_outline,
                      onChanged: (_) => _clearError(),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        onChanged: (_) => _clearError(),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 20),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: AppColors.textTintAlpha),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_error!,
                                    style: const TextStyle(color: AppColors.danger, fontSize: 13))),
                          ]),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Log In'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tenant accounts are created by your administrator.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
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