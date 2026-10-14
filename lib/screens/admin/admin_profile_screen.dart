import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';
import '../login_screen.dart';

class AdminProfileScreen extends StatefulWidget {
  final Admin admin;
  const AdminProfileScreen({super.key, required this.admin});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  late Admin _admin;
  bool _editing = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _admin = widget.admin;
    _nameCtrl = TextEditingController(text: _admin.name);
    _emailCtrl = TextEditingController(text: _admin.email);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty || !_emailCtrl.text.contains('@')) {
      showErrorSnack(context, 'Enter a valid name and email.');
      return;
    }
    setState(() => _saving = true);
    final updated = Admin(
      id: _admin.id,
      userId: _admin.userId,
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      createdAt: _admin.createdAt,
      username: _admin.username,
    );
    await DatabaseHelper.instance.updateAdmin(updated);
    if (!mounted) return;
    setState(() {
      _admin = updated;
      _editing = false;
      _saving = false;
    });
    showSuccessSnack(context, 'Profile updated.');
  }

  Future<void> _changePassword() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangePasswordSheet(userId: _admin.userId),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log Out',
      message: 'Are you sure you want to log out?',
      confirmLabel: 'Log Out',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _popWithResult() => Navigator.pop(context, _admin);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithResult();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Profile'),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _popWithResult),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                    _admin.name.isNotEmpty
                        ? _admin.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        fontSize: 30,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            EcoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Profile Info',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      TextButton(
                        onPressed: () =>
                            setState(() => _editing = !_editing),
                        child: Text(_editing ? 'Cancel' : 'Edit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_editing) ...[
                    LabeledField(
                        label: 'Full name',
                        controller: _nameCtrl,
                        icon: Icons.badge_outlined),
                    LabeledField(
                        label: 'Email',
                        controller: _emailCtrl,
                        icon: Icons.email_outlined),
                    ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save Changes'),
                    ),
                  ] else ...[
                    _infoRow(Icons.badge_outlined, _admin.name),
                    const SizedBox(height: 10),
                    _infoRow(Icons.email_outlined, _admin.email),
                    const SizedBox(height: 10),
                    _infoRow(Icons.alternate_email, '@${_admin.username}'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            EcoCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline,
                        color: AppColors.primary),
                    title: const Text('Change Password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _changePassword,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined,
                        color: AppColors.primary),
                    title: const Text('Settings'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const _AdminSettingsScreen())),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger)),
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
      ]);
}

class _ChangePasswordSheet extends StatefulWidget {
  final int userId;
  const _ChangePasswordSheet({required this.userId});

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await DatabaseHelper.instance
        .changePassword(widget.userId, _currentCtrl.text, _newCtrl.text);
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      showErrorSnack(context, 'Current password is incorrect.');
      return;
    }
    showSuccessSnack(context, 'Password changed successfully.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              const Text('Change Password',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              LabeledField(
                  label: 'Current password',
                  controller: _currentCtrl,
                  obscure: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null),
              LabeledField(
                  label: 'New password',
                  controller: _newCtrl,
                  obscure: true,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null),
              LabeledField(
                  label: 'Confirm new password',
                  controller: _confirmCtrl,
                  obscure: true,
                  validator: (v) =>
                      v != _newCtrl.text ? 'Passwords do not match' : null),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Update Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSettingsScreen extends StatefulWidget {
  const _AdminSettingsScreen();

  @override
  State<_AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<_AdminSettingsScreen> {
  bool _loading = true;
  bool _notifyNewTenant = true;
  bool _notifyRedemption = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await DatabaseHelper.instance.getSettings();
    if (!mounted) return;
    setState(() {
      // A missing key means "never changed", which defaults to on.
      _notifyNewTenant = settings[kSettingNotifyNewTenant] != 'false';
      _notifyRedemption = settings[kSettingNotifyRedemption] != 'false';
      _loading = false;
    });
  }

  Future<void> _set(String key, bool value) async {
    setState(() {
      if (key == kSettingNotifyNewTenant) {
        _notifyNewTenant = value;
      } else {
        _notifyRedemption = value;
      }
    });
    await DatabaseHelper.instance.setSetting(key, value ? 'true' : 'false');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                EcoCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Show new tenant sign-ups'),
                        subtitle: const Text(
                            "Displays this week's new tenants on the dashboard"),
                        value: _notifyNewTenant,
                        onChanged: (v) => _set(kSettingNotifyNewTenant, v),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Show reward redemptions'),
                        subtitle: const Text(
                            "Displays this week's redemptions on the dashboard"),
                        value: _notifyRedemption,
                        onChanged: (v) => _set(kSettingNotifyRedemption, v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Saved on this device. These control the "This week" summary '
                  'on the admin dashboard.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.4),
                ),
                const SizedBox(height: 16),
                const EcoCard(
                  child: Text(
                    'EcoTrack v1.0.0\nWaste management, recycling education & eco-friendly habits.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                        height: 1.5),
                  ),
                ),
              ],
            ),
    );
  }
}