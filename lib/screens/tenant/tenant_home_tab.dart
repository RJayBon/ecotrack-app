import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';
import 'tenant_notifications_screen.dart';
import 'tenant_learn_screen.dart';
import 'tenant_activities_screen.dart';

class TenantHomeTab extends StatefulWidget {
  final Tenant tenant;
  final VoidCallback onChanged;
  const TenantHomeTab({super.key, required this.tenant, required this.onChanged});

  @override
  State<TenantHomeTab> createState() => _TenantHomeTabState();
}

class _TenantHomeTabState extends State<TenantHomeTab> {
  EnvironmentalQuote? _quote;
  int _completedCount = 0;
  int _availableRewards = 0;
  int _unread = 0;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TenantHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload whenever the parent hands us a refreshed tenant (points change,
    // new activity completed, redemption made, etc.).
    if (oldWidget.tenant.id != widget.tenant.id ||
        oldWidget.tenant.totalPoints != widget.tenant.totalPoints ||
        oldWidget.tenant.status != widget.tenant.status) {
      _load();
    }
  }

  Future<void> _load() async {
    final tenantId = widget.tenant.id;
    if (tenantId == null) return;

    try {
      // Four independent queries - run them concurrently (Future.wait keeps
      // the results in argument order, so the list stays type-safe below)
      // instead of paying four sequential round trips.
      final results = await Future.wait<Object?>([
        DatabaseHelper.instance.getQuoteOfTheDay(),
        DatabaseHelper.instance.getActivityCount(tenantId),
        DatabaseHelper.instance.getRewards(activeOnly: true),
        DatabaseHelper.instance.getUnreadCount(tenantId),
      ]);
      if (!mounted) return;

      final rewards = results[2] as List<Reward>;
      setState(() {
        _quote = results[0] as EnvironmentalQuote?;
        _completedCount = results[1] as int;
        _availableRewards = rewards.where((r) => r.stock != 0).length;
        _unread = results[3] as int;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      // A failed read must not look like "0 points, 0 rewards" - report it.
      debugPrint('Tenant home load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoTrack'),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              TenantNotificationsScreen(tenant: tenant)));
                  widget.onChanged();
                  await _load();
                },
              ),
              if (_unread > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.redAccent, shape: BoxShape.circle),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text('$_unread',
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Welcome back, ${tenant.name.split(' ').first}! 🌱',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
            const SizedBox(height: 4),
            const Text('Keep up the great eco habits.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            if (_loadFailed) ...[
              const SizedBox(height: 14),
              // Entire subtree is compile-time constant: one const at the top
              // (the inner consts this used to carry are redundant under a
              // const ancestor, and `flutter analyze` flagged the missing
              // `const` on the EcoCard/Row/list).
              const EcoCard(
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: AppColors.danger, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Some of your data could not be loaded. Pull down to '
                        'try again.',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.eco, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${tenant.totalPoints}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      const Text('Eco Points',
                          style:
                              TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_quote != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.format_quote,
                          color: AppColors.accent, size: 18),
                      SizedBox(width: 6),
                      Text('Quote of the Day',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted)),
                    ]),
                    const SizedBox(height: 8),
                    Text('"${_quote!.quoteText}"',
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontStyle: FontStyle.italic,
                            height: 1.4)),
                    const SizedBox(height: 6),
                    Text('— ${_quote!.author}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 116, // long labels need a bit more room
              ),
              children: [
                StatTile(
                    icon: Icons.check_circle_outline,
                    value: '$_completedCount',
                    label: 'Completed Activities',
                    color: AppColors.accent),
                StatTile(
                    icon: Icons.card_giftcard,
                    value: '$_availableRewards',
                    label: 'Available Rewards',
                    color: AppColors.warning),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Quick Access',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: EcoCard(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TenantLearnScreen())),
                    child: const Column(
                      children: [
                        Icon(Icons.menu_book,
                            color: AppColors.primary, size: 26),
                        SizedBox(height: 8),
                        Text('Waste Guides',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: EcoCard(
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TenantActivitiesScreen(
                                  tenant: tenant,
                                  onChanged: widget.onChanged)));
                      await _load();
                    },
                    child: const Column(
                      children: [
                        Icon(Icons.directions_run,
                            color: AppColors.primary, size: 26),
                        SizedBox(height: 8),
                        Text('Eco Activities',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}