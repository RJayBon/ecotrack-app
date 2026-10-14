import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/icon_map.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class TenantActivitiesScreen extends StatefulWidget {
  final Tenant tenant;
  final VoidCallback onChanged;
  const TenantActivitiesScreen(
      {super.key, required this.tenant, required this.onChanged});

  @override
  State<TenantActivitiesScreen> createState() =>
      _TenantActivitiesScreenState();
}

class _TenantActivitiesScreenState extends State<TenantActivitiesScreen> {
  List<EcoActivity> _activities = [];
  Set<int> _completedIds = {};
  int _currentPoints = 0;
  int? _busyActivityId;

  @override
  void initState() {
    super.initState();
    _currentPoints = widget.tenant.totalPoints;
    _load();
  }

  @override
  void didUpdateWidget(covariant TenantActivitiesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell rebuilds every tab with a refreshed Tenant whenever the
    // balance changes. Without this hook the header kept showing the value
    // captured in initState, so points earned on another tab never appeared.
    if (oldWidget.tenant.id != widget.tenant.id ||
        oldWidget.tenant.totalPoints != widget.tenant.totalPoints) {
      setState(() => _currentPoints = widget.tenant.totalPoints);
      _load();
    }
  }

  Future<void> _load() async {
    final activities = await DatabaseHelper.instance.getActivities();
    final completed =
        await DatabaseHelper.instance.getCompletedActivityIds(widget.tenant.id!);
    final tenant = await DatabaseHelper.instance.getTenantById(widget.tenant.id!);
    if (!mounted) return;
    setState(() {
      _activities = activities;
      _completedIds = completed;
      _currentPoints = tenant?.totalPoints ?? _currentPoints;
    });
  }

  Future<void> _complete(EcoActivity activity) async {
    setState(() => _busyActivityId = activity.id);
    final pointsBefore = _currentPoints;
    final error =
        await DatabaseHelper.instance.completeActivity(widget.tenant.id!, activity);
    if (!mounted) return;
    setState(() => _busyActivityId = null);
    if (error != null) {
      showErrorSnack(context, error);
      return;
    }
    // Refresh first, then announce the *actual* award. `completeActivity`
    // re-reads the activity inside its transaction, so if an admin changed the
    // point value while this list was on screen, the stale `activity.points`
    // the button was built from is not what was credited.
    await _load();
    if (!mounted) return;
    final earned = _currentPoints - pointsBefore;
    showSuccessSnack(context, '+$earned Eco Points earned!');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eco Activities'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Current balance: $_currentPoints Eco Points',
                style: const TextStyle(color: Colors.white, fontSize: 12.5)),
          ),
        ),
      ),
      body: _activities.isEmpty
          ? const EmptyState(
              icon: Icons.directions_run,
              title: 'No activities yet',
              subtitle: 'Check back soon for new ways to earn Eco Points.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                itemCount: _activities.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final a = _activities[i];
                  final done = _completedIds.contains(a.id);
                  final locked = done && !a.repeatable;
                  final busy = _busyActivityId == a.id;
                  return EcoCard(
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              (locked ? AppColors.textMuted : AppColors.primary)
                                  .withValues(alpha: 0.12),
                          child: Icon(iconFor(a.icon),
                              color: locked
                                  ? AppColors.textMuted
                                  : AppColors.primary,
                              size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14.5)),
                              const SizedBox(height: 2),
                              Text(a.description,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textMuted)),
                              const SizedBox(height: 6),
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text('+${a.points} pts',
                                      style: const TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (!a.repeatable) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: AppColors.textMuted
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    child: const Text('One-time',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: AppColors.textMuted,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (locked)
                          const Icon(Icons.check_circle,
                              color: AppColors.primary, size: 26)
                        else
                          SizedBox(
                            height: 34,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14)),
                              onPressed: busy ? null : () => _complete(a),
                              child: busy
                                  ? const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : Text(done ? 'Do Again' : 'Complete',
                                      style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}