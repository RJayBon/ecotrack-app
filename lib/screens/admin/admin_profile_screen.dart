import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
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
    try {
      await DatabaseHelper.instance.updateAdmin(updated);
      if (!mounted) return;
      setState(() {
        _admin = updated;
        _editing = false;
        _saving = false;
      });
      showSuccessSnack(context, 'Profile updated.');
    } catch (error, stackTrace) {
      // DEFECT FIX (B2): a failed write left `_saving` true (button spinning
      // forever) AND `_editing` true, so the admin was trapped in the edit form
      // with no way to save and no message explaining why.
      debugPrint('Save admin profile failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Could not save your profile.');
    }
  }

  Future<void> _changePassword() {
    // DEFECT FIX (C5): shared sheet from common_widgets.dart. This file used to
    // carry its own ~106-line private `_ChangePasswordSheet` that was
    // byte-identical to the tenant one, so every fix had to be applied twice -
    // and neither copy had a try/catch, meaning a database error left the
    // "Update Password" button spinning forever with no message.
    return showChangePasswordSheet(context, userId: _admin.userId);
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
                // textTintAlpha, not iconTintAlpha: the initial is text.
                backgroundColor: AppColors.primary
                    .withValues(alpha: AppColors.textTintAlpha),
                // `nameInitial()` also guards against a whitespace-only name,
                // which the inline `name[0]` check did not.
                child: Text(nameInitial(_admin.name),
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

class _AdminSettingsScreen extends StatefulWidget {
  const _AdminSettingsScreen();

  @override
  State<_AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<_AdminSettingsScreen> {
  bool _loading = true;

  /// True when the settings read threw.
  bool _loadFailed = false;
  bool _notifyNewTenant = true;
  bool _notifyRedemption = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await DatabaseHelper.instance.getSettings();
      if (!mounted) return;
      setState(() {
        // A missing key means "never changed", which defaults to on.
        _notifyNewTenant = settings[kSettingNotifyNewTenant] != 'false';
        _notifyRedemption = settings[kSettingNotifyRedemption] != 'false';
        _loading = false;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      // DEFECT FIX (B4): this left `_loading` true forever, so the whole
      // Settings screen was a permanent spinner with no retry and no message.
      debugPrint('Settings load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  bool _valueFor(String key) =>
      key == kSettingNotifyNewTenant ? _notifyNewTenant : _notifyRedemption;

  void _applyLocally(String key, bool value) {
    if (key == kSettingNotifyNewTenant) {
      _notifyNewTenant = value;
    } else {
      _notifyRedemption = value;
    }
  }

  /// Flips the switch optimistically, persists, and **reverts** on failure.
  ///
  /// DEFECT FIX (E10): `onChanged: (v) => _set(key, v)` discarded the returned
  /// future and the method had no error handling, so a failed `setSetting` left
  /// the switch showing one thing while `app_settings` held another - and
  /// nothing was ever surfaced to the admin. The dashboard reads these keys
  /// back on its own load, so the desync survived a navigation.
  Future<void> _set(String key, bool value) async {
    final previous = _valueFor(key);
    setState(() => _applyLocally(key, value));
    try {
      await DatabaseHelper.instance.setSetting(key, value ? 'true' : 'false');
    } catch (error, stackTrace) {
      debugPrint('Save setting $key failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _applyLocally(key, previous));
      showErrorSnack(context, 'Could not save that setting.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? ErrorState(
              title: 'Settings could not be loaded',
              subtitle: 'Your saved preferences could not be read from the '
                  'local database. Please try again.',
              onRetry: _load,
            )
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