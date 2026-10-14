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
    final rewards = await DatabaseHelper.instance.getRewards(activeOnly: true);
    final history =
        await DatabaseHelper.instance.getRedemptionHistory(widget.tenant.id!);
    final tenant = await DatabaseHelper.instance.getTenantById(widget.tenant.id!);
    if (!mounted) return;
    setState(() {
      _rewards = rewards;
      _history = history;
      _currentPoints = tenant?.totalPoints ?? _currentPoints;
    });
  }

  Future<void> _redeem(Reward reward) async {
    // Re-read the reward so the dialog shows the freshest points/stock even
    // if an admin edited it while this screen was open.
    final freshList = await DatabaseHelper.instance.getRewards(activeOnly: true);
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

    setState(() => _busyRewardId = reward.id);
    final error =
        await DatabaseHelper.instance.redeemReward(widget.tenant.id!, fresh);
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
                  backgroundColor:
                      AppColors.warning.withValues(alpha: 0.15),
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
                      backgroundColor: (canAfford && !outOfStock)
                          ? AppColors.primary
                          : Colors.grey.shade300,
                      foregroundColor: (canAfford && !outOfStock)
                          ? Colors.white
                          : Colors.grey.shade600,
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
    if (_history.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'No redemptions yet',
        subtitle: 'Your redeemed rewards will show up here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
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