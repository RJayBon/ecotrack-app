import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class AdminHomeTab extends StatefulWidget {
  final Admin admin;
  const AdminHomeTab({super.key, required this.admin});

  @override
  State<AdminHomeTab> createState() => _AdminHomeTabState();
}

class _AdminHomeTabState extends State<AdminHomeTab> {
  Map<String, int> _stats = const {
    'totalTenants': 0, 'activeTenants': 0, 'totalPoints': 0, 'rewardsRedeemed': 0
  };
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _recentNotifications = [];

  // "This week" summary - the only two settings the admin Settings screen
  // exposes, so they need to actually do something.
  bool _showNewTenants = true;
  bool _showRedemptions = true;
  int _newTenants = 0;
  int _redemptions = 0;

  /// True when the last load failed. Without this the dashboard silently kept
  /// showing zeros and the real exception vanished into the async void.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    try {
      // Independent reads - fetch them concurrently.
      final results = await Future.wait<Object?>([
        DatabaseHelper.instance.getAdminStats(),
        DatabaseHelper.instance.getRecentActivityFeed(limit: 6),
        DatabaseHelper.instance.getRecentNotificationsAdmin(limit: 5),
        DatabaseHelper.instance.getSettings(),
        DatabaseHelper.instance.getNewTenantCountSince(since),
        DatabaseHelper.instance.getRedemptionCountSince(since),
      ]);
      if (!mounted) return;

      final settings = results[3] as Map<String, String>;
      setState(() {
        _stats = results[0] as Map<String, int>;
        _recentActivity = results[1] as List<Map<String, dynamic>>;
        _recentNotifications = results[2] as List<Map<String, dynamic>>;
        // A missing key means the admin never changed it -> default on.
        _showNewTenants = settings[kSettingNotifyNewTenant] != 'false';
        _showRedemptions = settings[kSettingNotifyRedemption] != 'false';
        _newTenants = results[4] as int;
        _redemptions = results[5] as int;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      // Surface the failure instead of leaving a dashboard of zeros that
      // looks like real (empty) data.
      debugPrint('Admin dashboard load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoTrack Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // `firstName()` instead of a bare `name.split(' ').first`: the
            // inline version throws on an empty name and renders
            // "Welcome back, " for a whitespace-only one.
            Text('Welcome back, ${firstName(widget.admin.name)}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
            const SizedBox(height: 4),
            const Text('Here is what is happening across EcoTrack today.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            if (_loadFailed) ...[
              const SizedBox(height: 14),
              EcoCard(
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Some dashboard data could not be loaded. The figures '
                        'below may be out of date.',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textMuted),
                      ),
                    ),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 112, // fixed height → no overflow
              ),
              children: [
                StatTile(
                  icon: Icons.people,
                  value: '${_stats['totalTenants']}',
                  label: 'Total Tenants'),
                StatTile(
                  icon: Icons.person_pin_circle,
                  value: '${_stats['activeTenants']}',
                  label: 'Active Tenants',
                  color: AppColors.accent),
                StatTile(
                  icon: Icons.eco,
                  value: '${_stats['totalPoints']}',
                  label: 'Total Eco Points'),
                StatTile(
                  icon: Icons.card_giftcard,
                  value: '${_stats['rewardsRedeemed']}',
                  label: 'Rewards Redeemed',
                  color: AppColors.warning),
              ],
            ),
            if (_showNewTenants || _showRedemptions) ...[
              const SizedBox(height: 24),
              const Text('This Week',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark)),
              const SizedBox(height: 10),
              // REGRESSION NOTE - do not remove the IntrinsicHeight.
              //
              // `CrossAxisAlignment.stretch` on a Row means "give every child
              // the full height of this Row". This Row sits inside the
              // dashboard's ListView, and a scrollable hands its children an
              // *unbounded* height - so the stretch forwarded
              // `height: double.infinity` to both tiles and the first frame
              // after an admin signed in failed during layout with
              // "BoxConstraints forces an infinite height" from
              // RenderFlex.performLayout. In debug that is the red error
              // screen; in release the infinite box also corrupts the
              // ListView's scroll extent, which is what made the app look
              // like it had crashed / stopped responding right after login.
              //
              // IntrinsicHeight measures the tallest tile first and hands the
              // Row a finite height, which keeps the two tiles the same
              // height - the original intent - without the infinite
              // constraint.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showNewTenants)
                      Expanded(
                        child: StatTile(
                          icon: Icons.person_add_alt_1,
                          value: '$_newTenants',
                          label: 'New Tenants',
                          color: AppColors.accent,
                        ),
                      ),
                    if (_showNewTenants && _showRedemptions)
                      const SizedBox(width: 12),
                    if (_showRedemptions)
                      Expanded(
                        child: StatTile(
                          icon: Icons.redeem,
                          value: '$_redemptions',
                          label: 'Redemptions',
                          color: AppColors.warning,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Recent Activities',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
            const SizedBox(height: 10),
            if (_recentActivity.isEmpty)
              const EcoCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No tenant activity yet.', style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else
              EcoCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: List.generate(_recentActivity.length, (i) {
                    final a = _recentActivity[i];
                    return Column(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.avatarTint,
                            child: Icon(Icons.eco, color: AppColors.primary, size: 20),
                          ),
                          title: Text('${a['tenant_name']} completed ${a['activity_title']}'),
                          subtitle: Text(formatRelativeDate(a['completed_at'] as String)),
                          trailing: Text('+${a['points_awarded']}',
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                        if (i != _recentActivity.length - 1) const Divider(height: 1),
                      ],
                    );
                  }),
                ),
              ),
            const SizedBox(height: 24),
            const Text('Recent Notifications',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
            const SizedBox(height: 10),
            if (_recentNotifications.isEmpty)
              const EcoCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No notifications sent yet.', style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else
              EcoCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: List.generate(_recentNotifications.length, (i) {
                    final n = _recentNotifications[i];
                    return Column(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.avatarTint,
                            child: Icon(Icons.notifications, color: AppColors.primary, size: 20),
                          ),
                          title: Text(n['title'] as String,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('Sent to ${n['recipient_count']} '
                              'tenant(s) · '
                              '${formatRelativeDate(n['created_at'] as String)}'),
                        ),
                        if (i != _recentNotifications.length - 1) const Divider(height: 1),
                      ],
                    );
                  }),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
