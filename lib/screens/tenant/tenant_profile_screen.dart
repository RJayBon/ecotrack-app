import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/formatters.dart';
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

  /// True when the history read threw, so the two history cards can say so
  /// instead of rendering their empty states.
  bool _historyLoadFailed = false;

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
    final tenantId = _tenant.id;
    if (tenantId == null) return;
    try {
      // Only the most recent entries are ever displayed, so do not pull the
      // tenant's entire lifetime history into memory on every tab visit.
      final results = await Future.wait<Object?>([
        DatabaseHelper.instance.getActivityHistory(tenantId, limit: 8),
        DatabaseHelper.instance.getRedemptionHistory(tenantId, limit: 8),
      ]);
      if (!mounted) return;
      setState(() {
        _activityHistory = results[0] as List<ActivityCompletion>;
        _rewardHistory = results[1] as List<RewardRedemption>;
        _historyLoadFailed = false;
      });
    } catch (error, stackTrace) {
      // DEFECT FIX (B4): no error path existed. A failed read left both history
      // cards showing their empty states, which reads as "you have never done
      // anything" rather than "this could not be loaded". (The duplicated
      // `if (!mounted) return;` that sat between the two casts is also gone -
      // there is no await between them, so the second check was dead code.)
      debugPrint('Tenant profile history load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _historyLoadFailed = true);
    }
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
    try {
      await DatabaseHelper.instance.updateTenant(updated);
      if (!mounted) return;
      setState(() {
        _tenant = updated;
        _editing = false;
        _saving = false;
      });
      widget.onChanged();
      showSuccessSnack(context, 'Profile updated.');
    } catch (error, stackTrace) {
      // DEFECT FIX (B2): a failed write left `_saving` true (button spinning
      // forever) AND `_editing` true, trapping the tenant in the edit form with
      // no message and no way to save.
      debugPrint('Save tenant profile failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Could not save your profile.');
    }
  }

  Future<void> _changePassword() {
    // DEFECT FIX (C5): shared sheet from common_widgets.dart. This file carried
    // a ~102-line private `_ChangePasswordSheet` that was byte-identical to the
    // admin one, so the same two defects (no try/catch, no error path) shipped
    // twice. Both copies are now one fixed widget.
    return showChangePasswordSheet(context, userId: _tenant.userId);
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

  /// Inline "could not be loaded" row for the two history sections. A full
  /// [ErrorState] is too large to sit inside a scrolling profile page, so this
  /// keeps the message local to the section that failed - the point is that it
  /// no longer says "you have never done anything" when the truth is "this
  /// could not be read".
  Widget _historyError() {
    return EcoCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('History could not be loaded.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ),
        TextButton(onPressed: _loadHistory, child: const Text('Retry')),
      ]),
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
                // textTintAlpha, not iconTintAlpha: the initial is text.
                backgroundColor: AppColors.primary
                    .withValues(alpha: AppColors.textTintAlpha),
                // `nameInitial()` also guards against a whitespace-only name,
                // which the inline `name[0]` check did not.
                child: Text(nameInitial(_tenant.name),
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
            if (_historyLoadFailed)
              _historyError()
            else if (_activityHistory.isEmpty)
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
            if (_historyLoadFailed)
              _historyError()
            else if (_rewardHistory.isEmpty)
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
