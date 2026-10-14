import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/formatters.dart';
import '../../utils/icon_map.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class TenantRewardsScreen extends StatefulWidget {
  final Tenant tenant;
  final VoidCallback onChanged;
  const TenantRewardsScreen(
      {super.key, required this.tenant, required this.onChanged});

  @override
  State<TenantRewardsScreen> createState() => _TenantRewardsScreenState();
}

class _TenantRewardsScreenState extends State<TenantRewardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Reward> _rewards = [];
  List<RewardRedemption> _history = [];
  int _currentPoints = 0;
  int? _busyRewardId;

  /// True when the last load threw - see the same field in
  /// `_TenantActivitiesScreenState`.
  bool _loadFailed = false;

  /// DEFECT FIX (C1): `getRedemptionHistory` was called with no limit, so the
  /// History tab materialised every redemption this tenant has ever made into
  /// Dart objects on *every* refresh (and after every redemption). A long-lived
  /// account turns that into an ever-growing cost paid to render a screen the
  /// user can only scroll through a page at a time. History is now fetched one
  /// page at a time and extended on demand.
  static const int _historyPageSize = 50;
  int _historyLimit = _historyPageSize;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentPoints = widget.tenant.totalPoints;
    _load();
  }

  @override
  void didUpdateWidget(covariant TenantRewardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the "available points" banner honest when the parent refreshes
    // the tenant (e.g. an activity was just completed on another tab).
    if (oldWidget.tenant.id != widget.tenant.id ||
        oldWidget.tenant.totalPoints != widget.tenant.totalPoints) {
      setState(() => _currentPoints = widget.tenant.totalPoints);
      _load();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tenantId = widget.tenant.id;
    if (tenantId == null) return;
    try {
      // DEFECT FIX (C2): three independent reads that used to run one after
      // another. `Future.wait` keeps results in argument order.
      final results = await Future.wait<Object?>([
        DatabaseHelper.instance.getRewards(activeOnly: true),
        DatabaseHelper.instance
            .getRedemptionHistory(tenantId, limit: _historyLimit),
        DatabaseHelper.instance.getTenantById(tenantId),
      ]);
      if (!mounted) return;
      setState(() {
        _rewards = results[0] as List<Reward>;
        _history = results[1] as List<RewardRedemption>;
        _currentPoints =
            (results[2] as Tenant?)?.totalPoints ?? _currentPoints;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      // DEFECT FIX (B4): no error path existed, so a failed read rendered
      // "No rewards available" / "No redemptions yet" - indistinguishable from
      // a genuinely empty catalogue.
      debugPrint('Tenant rewards load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  /// Extends the History tab by one page and reloads.
  Future<void> _loadMoreHistory() async {
    setState(() => _historyLimit += _historyPageSize);
    await _load();
  }

  Future<void> _redeem(Reward reward) async {
    // Re-read the reward so the dialog shows the freshest points/stock even
    // if an admin edited it while this screen was open.
    final List<Reward> freshList;
    try {
      freshList = await DatabaseHelper.instance.getRewards(activeOnly: true);
    } catch (error, stackTrace) {
      debugPrint('Pre-redeem reward read failed: $error\n$stackTrace');
      if (!mounted) return;
      showErrorSnack(context,
          'Could not check the latest price for that reward. Please retry.');
      return;
    }
    final fresh = freshList.firstWhere(
      (r) => r.id == reward.id,
      orElse: () => reward,
    );
    if (!mounted) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Redeem Reward',
      message: 'Redeem "${fresh.title}" for ${fresh.pointsRequired} Eco Points?',
      confirmLabel: 'Redeem',
    );
    if (!confirmed) return;

    // DEFECT FIX (B3): `showConfirmDialog` above awaits, so this State may
    // already be gone (the tenant can switch tabs, and the shell keeps every
    // tab alive in an IndexedStack - but the route can still be disposed).
    // `setState` on a disposed State throws, so re-check `mounted` here; the
    // guard earlier in this method only covered the *previous* await.
    if (!mounted) return;
    setState(() => _busyRewardId = reward.id);

    final String? error;
    try {
      error =
          await DatabaseHelper.instance.redeemReward(widget.tenant.id!, fresh);
    } catch (thrown, stackTrace) {
      // DEFECT FIX (B2): `redeemReward` runs a transaction that debits points
      // and decrements stock, and it can throw. With no catch, `_busyRewardId`
      // was never cleared, so that reward's button spun forever and the tenant
      // had no way to tell whether their points had been taken.
      debugPrint('Redeem reward failed: $thrown\n$stackTrace');
      if (!mounted) return;
      setState(() => _busyRewardId = null);
      showErrorSnack(context, 'Could not redeem that reward. Please retry.');
      return;
    }

    if (!mounted) return;
    setState(() => _busyRewardId = null);
    if (error != null) {
      showErrorSnack(context, error);
      return;
    }
    showSuccessSnack(context, 'Reward redeemed successfully!');
    widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rewards'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white,
          tabs: const [Tab(text: 'Browse'), Tab(text: 'History')],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.eco, color: Colors.white, size: 24),
                const SizedBox(width: 10),
                Text('$_currentPoints Eco Points available',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildBrowse(), _buildHistory()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowse() {
    if (_loadFailed) {
      return ErrorState(
        title: 'Rewards could not be loaded',
        subtitle: 'The reward catalogue could not be read from the local '
            'database. Please try again.',
        onRetry: _load,
      );
    }
    if (_rewards.isEmpty) {
      return const EmptyState(
        icon: Icons.card_giftcard,
        title: 'No rewards available',
        subtitle: 'Check back soon for new rewards to redeem.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _rewards.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _rewards[i];
          final canAfford = _currentPoints >= r.pointsRequired;
          final outOfStock = r.stock == 0;
          final busy = _busyRewardId == r.id;
          return EcoCard(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.warning
                      .withValues(alpha: AppColors.iconTintAlpha),
                  child:
                      Icon(iconFor(r.icon), color: AppColors.warning, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(r.description,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.textMuted)),
                      const SizedBox(height: 6),
                      Text(
                          '${r.pointsRequired} pts${r.stock >= 0 ? ' · ${r.stock} left' : ''}',
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      // DEFECT FIX (D4): the disabled state used raw
                      // Colors.grey.shade600 on Colors.grey.shade300 = 3.49:1,
                      // below the 4.5:1 AA floor - and "Locked" / "Out of stock"
                      // is exactly the label a tenant most needs to read. The
                      // palette's vetted disabled tokens give 4.84:1.
                      backgroundColor: (canAfford && !outOfStock)
                          ? AppColors.primary
                          : AppColors.disabledBackground,
                      foregroundColor: (canAfford && !outOfStock)
                          ? Colors.white
                          : AppColors.disabledForeground,
                    ),
                    onPressed: (!canAfford || outOfStock || busy)
                        ? null
                        : () => _redeem(r),
                    child: busy
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(
                            outOfStock
                                ? 'Out of stock'
                                : (canAfford ? 'Redeem' : 'Locked'),
                            style: const TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistory() {
    if (_loadFailed) {
      return ErrorState(
        title: 'Redemption history could not be loaded',
        subtitle: 'Your past redemptions could not be read from the local '
            'database. Please try again.',
        onRetry: _load,
      );
    }
    if (_history.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'No redemptions yet',
        subtitle: 'Your redeemed rewards will show up here.',
      );
    }
    // One extra row when a page boundary was hit, so the older redemptions
    // stay reachable - C1 caps the read, it does not hide data.
    final hasMore = _history.length >= _historyLimit;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _history.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i >= _history.length) {
            return Center(
              child: TextButton.icon(
                onPressed: _loadMoreHistory,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Load earlier redemptions'),
              ),
            );
          }
          final r = _history[i];
          return EcoCard(
            child: Row(
              children: [
                const Icon(Icons.card_giftcard,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.rewardTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(formatShortDate(r.redeemedAt),
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Text('-${r.pointsSpent}',
                    style: const TextStyle(
                        color: AppColors.danger, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );
  }
}