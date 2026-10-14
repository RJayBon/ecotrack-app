import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';
import 'admin_activities_screen.dart';
import 'admin_rewards_screen.dart';
import 'admin_quotes_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_profile_screen.dart';

class AdminMoreScreen extends StatelessWidget {
  final Admin admin;
  final void Function(Admin) onAdminUpdated;
  const AdminMoreScreen(
      {super.key, required this.admin, required this.onAdminUpdated});

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem(
          'Eco Activities',
          'Manage activities tenants can complete',
          Icons.directions_run,
          AppColors.primary,
          (ctx) => Navigator.push(ctx,
              MaterialPageRoute(builder: (_) => const AdminActivitiesScreen()))),
      _MenuItem(
          'Rewards',
          'Manage the rewards catalog',
          Icons.card_giftcard,
          AppColors.warning,
          (ctx) => Navigator.push(ctx,
              MaterialPageRoute(builder: (_) => const AdminRewardsScreen()))),
      _MenuItem(
          'Environmental Quotes',
          'Manage daily quotes',
          Icons.format_quote,
          AppColors.accent,
          (ctx) => Navigator.push(ctx,
              MaterialPageRoute(builder: (_) => const AdminQuotesScreen()))),
      _MenuItem(
          'Notifications',
          'Send and review notifications',
          Icons.notifications_outlined,
          AppColors.primaryDark,
          (ctx) => Navigator.push(
              ctx,
              MaterialPageRoute(
                  builder: (_) => const AdminNotificationsScreen()))),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EcoCard(
            onTap: () async {
              final updated = await Navigator.push<Admin>(
                context,
                MaterialPageRoute(
                    builder: (_) => AdminProfileScreen(admin: admin)),
              );
              if (updated != null) onAdminUpdated(updated);
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                      admin.name.isNotEmpty
                          ? admin.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 20,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(admin.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      Text(admin.email,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: EcoCard(
                  onTap: () => item.onTap(context),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: item.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(item.icon, color: item.color, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5)),
                            Text(item.subtitle,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textMuted),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _MenuItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final void Function(BuildContext) onTap;
  _MenuItem(this.title, this.subtitle, this.icon, this.color, this.onTap);
}