import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';
import 'admin_tenant_form_screen.dart';

class AdminTenantDetailScreen extends StatefulWidget {
  final int tenantId;
  const AdminTenantDetailScreen({super.key, required this.tenantId});

  @override
  State<AdminTenantDetailScreen> createState() => _AdminTenantDetailScreenState();
}

class _AdminTenantDetailScreenState extends State<AdminTenantDetailScreen> {
  Tenant? _tenant;
  List<ActivityCompletion> _activities = [];
  List<RewardRedemption> _redemptions = [];
  int _activityCount = 0;
  int _redemptionCount = 0;
  bool _changed = false;

    /// Distinguishes "the tenant does not exist (any more)" from "we have not
  /// finished loading yet" and from "the read threw". Without this the
  /// screen rendered an empty white body in all three cases.
  bool _loadFailed = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Five independent reads - one round trip instead of five in a row.
      final results = await Future.wait<Object?>([
        DatabaseHelper.instance.getTenantById(widget.tenantId),
        DatabaseHelper.instance.getActivityHistory(widget.tenantId, limit: 10),
        DatabaseHelper.instance.getRedemptionHistory(widget.tenantId, limit: 10),
        DatabaseHelper.instance.getActivityCount(widget.tenantId),
        DatabaseHelper.instance.getRedemptionCount(widget.tenantId),
      ]);
      if (!mounted) return;
      setState(() {
        _tenant = results[0] as Tenant?;
        _activities = results[1] as List<ActivityCompletion>;
        _redemptions = results[2] as List<RewardRedemption>;
        _activityCount = results[3] as int;
        _redemptionCount = results[4] as int;
        _loadFailed = false;
        _loaded = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Tenant detail load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _toggleStatus() async {
    final t = _tenant!;
    final newStatus = t.status == 'active' ? 'inactive' : 'active';
    final confirmed = await showConfirmDialog(
      context,
      title: newStatus == 'inactive' ? 'Deactivate Tenant' : 'Activate Tenant',
      message: newStatus == 'inactive'
          ? '${t.name} will no longer be able to log in until reactivated.'
          : '${t.name} will regain access to their account.',
      confirmLabel: newStatus == 'inactive' ? 'Deactivate' : 'Activate',
      danger: newStatus == 'inactive',
    );
    if (!confirmed) return;
    try {
      await DatabaseHelper.instance.setTenantStatus(t.id!, newStatus);
      _changed = true;
      if (mounted) {
        showSuccessSnack(context,
            'Tenant ${newStatus == 'inactive' ? 'deactivated' : 'activated'}.');
      }
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Set tenant status failed: $error\n$stackTrace');
      if (!mounted) return;
      showErrorSnack(context, 'Could not change the tenant status.');
    }
  }

  Future<void> _delete() async {
    final t = _tenant!;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Tenant',
      message: 'This will permanently remove ${t.name} and their account. This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await DatabaseHelper.instance.deleteTenant(t.id!);
      if (!mounted) return;
      // No snackbar here: this route is being popped, so a snackbar attached
      // to it would never actually be seen. The list behind us refreshes
      // because we pop with `true`, which is the real feedback.
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      debugPrint('Delete tenant failed: $error\n$stackTrace');
      if (!mounted) return;
      showErrorSnack(context, 'Could not delete the tenant.');
    }
  }

  Future<void> _edit() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminTenantFormScreen(tenant: _tenant)),
    );
    if (result == true) {
      _changed = true;
      await _load();
    }
  }

  void _popWithResult() {
    Navigator.pop(context, _changed);
  }

  @override
  Widget build(BuildContext context) {
    final t = _tenant;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithResult();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tenant Details'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _popWithResult,
          ),
          actions: [
            IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: t == null ? null : _edit),
          ],
        ),
        body: _loadFailed
            ? ErrorState(
                title: 'Tenant could not be loaded',
                subtitle: 'The database did not return this tenant. '
                    'Please try again.',
                onRetry: _load,
              )
            : t == null
            ? (_loaded
                ? EmptyState(
                    icon: Icons.person_off_outlined,
                    title: 'Tenant not found',
                    subtitle: 'This tenant no longer exists. They may have '
                        'been removed by another administrator.',
                    action: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back to Tenants'),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    EcoCard(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                            child: Text(
                                t.name.isNotEmpty ? t.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    fontSize: 24,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 10),
                          Text(t.name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('@${t.username}',
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)),
                          const SizedBox(height: 8),
                          StatusBadge(status: t.status),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: StatTile(
                                icon: Icons.eco,
                                value: '${t.totalPoints}',
                                label: 'Eco Points')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: StatTile(
                                icon: Icons.check_circle_outline,
                                value: '$_activityCount',
                                label: 'Activities Done',
                                color: AppColors.accent)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    EcoCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoRow(Icons.email_outlined, t.email),
                          const SizedBox(height: 10),
                          _infoRow(Icons.phone_outlined, t.phone),
                          const SizedBox(height: 10),
                          _infoRow(Icons.home_outlined, 'Unit ${t.unit}'),
                          const SizedBox(height: 10),
                          _infoRow(Icons.card_giftcard_outlined,
                              '$_redemptionCount reward redemption(s)'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Recent Activities',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 8),
                    if (_activities.isEmpty)
                      const Text('No activities completed yet.',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13))
                    else
                      ..._activities.map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: EcoCard(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.eco,
                                      color: AppColors.primary, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(a.activityTitle,
                                            style: const TextStyle(
                                                fontSize: 13.5)),
                                        Text(formatShortDate(a.completedAt),
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                  Text('+${a.pointsAwarded}',
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          )),
                    const SizedBox(height: 20),
                    const Text('Reward Redemptions',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 8),
                    if (_redemptions.isEmpty)
                      const Text('No rewards redeemed yet.',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13))
                    else
                      ..._redemptions.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: EcoCard(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.card_giftcard,
                                      color: AppColors.warning, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(r.rewardTitle,
                                            style: const TextStyle(
                                                fontSize: 13.5)),
                                        Text(formatShortDate(r.redeemedAt),
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                  Text('-${r.pointsSpent}',
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          )),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: _toggleStatus,
                      icon: Icon(
                          t.status == 'active'
                              ? Icons.block
                              : Icons.check_circle_outline,
                          size: 18),
                      label: Text(t.status == 'active'
                          ? 'Deactivate Tenant'
                          : 'Activate Tenant'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger)),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete Tenant'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 18, color: AppColors.textMuted),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
    ]);
  }
}