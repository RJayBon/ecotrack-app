import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';
import '../login_screen.dart';

class TenantProfileScreen extends StatefulWidget {
  final Tenant tenant;
  final VoidCallback onChanged;
  const TenantProfileScreen(
      {super.key, required this.tenant, required this.onChanged});

  @override
  State<TenantProfileScreen> createState() => _TenantProfileScreenState();
}

class _TenantProfileScreenState extends State<TenantProfileScreen> {
  late Tenant _tenant;
  bool _editing = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  List<ActivityCompletion> _activityHistory = [];
  List<RewardRedemption> _rewardHistory = [];

  @override
  void initState() {
    super.initState();
    _tenant = widget.tenant;
    _nameCtrl = TextEditingController(text: _tenant.name);
    _emailCtrl = TextEditingController(text: _tenant.email);
    _phoneCtrl = TextEditingController(text: _tenant.phone);
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant TenantProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Points, name and contact details can all change while this tab is
    // alive (completing an activity, an admin editing the tenant). Re-sync
    // from the parent's copy instead of showing the initState snapshot.
    if (oldWidget.tenant.id != widget.tenant.id ||
        oldWidget.tenant.totalPoints != widget.tenant.totalPoints ||
        oldWidget.tenant.name != widget.tenant.name ||
        oldWidget.tenant.email != widget.tenant.email ||
        oldWidget.tenant.phone != widget.tenant.phone) {
      setState(() {
        _tenant = widget.tenant;
        if (!_editing) {
          _nameCtrl.text = widget.tenant.name;
          _emailCtrl.text = widget.tenant.email;
          _phoneCtrl.text = widget.tenant.phone;
        }
      });
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    // Only the most recent entries are ever displayed, so do not pull the
    // tenant's entire lifetime history into memory on every tab visit.
    final results = await Future.wait<Object?>([
      DatabaseHelper.instance.getActivityHistory(_tenant.id!, limit: 8),
      DatabaseHelper.instance.getRedemptionHistory(_tenant.id!, limit: 8),
    ]);
    if (!mounted) return;
    final acts = results[0] as List<ActivityCompletion>;
    final reds = results[1] as List<RewardRedemption>;
    if (!mounted) return;
    setState(() {
      _activityHistory = acts;
      _rewardHistory = reds;
    });
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty ||
        !_emailCtrl.text.contains('@') ||
        _phoneCtrl.text.trim().isEmpty) {
      showErrorSnack(context, 'Please fill in all fields with valid values.');
      return;
    }
    setState(() => _saving = true);
    final updated = _tenant.copyWith(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
    );
    await DatabaseHelper.instance.updateTenant(updated);
    if (!mounted) return;
    setState(() {
      _tenant = updated;
      _editing = false;
      _saving = false;
    });
    widget.onChanged();
    showSuccessSnack(context, 'Profile updated.');
  }

  Future<void> _changePassword() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangePasswordSheet(userId: _tenant.userId),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                    _tenant.name.isNotEmpty
                        ? _tenant.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        fontSize: 30,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
                child: Text('${_tenant.totalPoints} Eco Points',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15))),
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
                          child: Text(_editing ? 'Cancel' : 'Edit')),
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
                    LabeledField(
                        label: 'Phone',
                        controller: _phoneCtrl,
                        icon: Icons.phone_outlined),
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
                    _infoRow(Icons.badge_outlined, _tenant.name),
                    const SizedBox(height: 10),
                    _infoRow(Icons.email_outlined, _tenant.email),
                    const SizedBox(height: 10),
                    _infoRow(Icons.phone_outlined, _tenant.phone),
                    const SizedBox(height: 10),
                    _infoRow(Icons.home_outlined, 'Unit ${_tenant.unit}'),
                    const SizedBox(height: 10),
                    _infoRow(Icons.alternate_email, '@${_tenant.username}'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            EcoCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.lock_outline,
                    color: AppColors.primary),
                title: const Text('Change Password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changePassword,
              ),
            ),
            const SizedBox(height: 20),
            const Text('Activity History',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            if (_activityHistory.isEmpty)
              const Text('No activities completed yet.',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 13))
            else
              ..._activityHistory.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: EcoCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(children: [
                        const Icon(Icons.eco,
                            color: AppColors.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(a.activityTitle,
                                style: const TextStyle(fontSize: 13.5))),
                        Text('+${a.pointsAwarded}',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  )),
            const SizedBox(height: 20),
            const Text('Reward History',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            if (_rewardHistory.isEmpty)
              const Text('No rewards redeemed yet.',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 13))
            else
              ..._rewardHistory.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: EcoCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(children: [
                        const Icon(Icons.card_giftcard,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(r.rewardTitle,
                                style: const TextStyle(fontSize: 13.5))),
                        Text('-${r.pointsSpent}',
                            style: const TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  )),
            const SizedBox(height: 24),
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
        Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13.5))),
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