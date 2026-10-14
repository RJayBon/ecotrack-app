import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class TenantNotificationsScreen extends StatefulWidget {
  final Tenant tenant;
  const TenantNotificationsScreen({super.key, required this.tenant});

  @override
  State<TenantNotificationsScreen> createState() =>
      _TenantNotificationsScreenState();
}

class _TenantNotificationsScreenState extends State<TenantNotificationsScreen> {
  List<AppNotification> _notifications = [];

  /// True when the last load failed, so the screen can say so instead of
  /// showing an empty list that looks like "you are all caught up".
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await DatabaseHelper.instance
          .getNotificationsForTenant(widget.tenant.id!);
      if (!mounted) return;
      setState(() {
        _notifications = list;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Notification load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _open(AppNotification n) async {
    final rowId = n.recipientRowId;
    if (!n.isRead && rowId != null) {
      // A failed "mark as read" must not stop the tenant from reading the
      // message they just tapped.
      try {
        await DatabaseHelper.instance.markNotificationRead(rowId);
        await _load();
      } catch (error, stackTrace) {
        debugPrint('Mark notification read failed: $error\n$stackTrace');
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(n.message),
              const SizedBox(height: 12),
              Text(
                'From ${n.sender} · ${formatFullDate(n.createdAt)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(AppNotification n) async {
    final rowId = n.recipientRowId;
    if (rowId == null) return;

    // Remove from local state BEFORE awaiting anything.
    //
    // `Dismissible.onDismissed` has already been fired, so the widget is
    // gone from the render tree as far as the framework is concerned. If the
    // row is still in `_notifications` on the next build, Flutter throws
    // "A dismissed Dismissible widget is still part of the tree." - and
    // showing a snackbar does trigger that build. So the list update must be
    // synchronous; only the database write is awaited.
    setState(() => _notifications
        .removeWhere((x) => x.recipientRowId == n.recipientRowId));
    try {
      await DatabaseHelper.instance.deleteNotificationForTenant(rowId);
      if (!mounted) return;
      showSuccessSnack(context, 'Notification deleted.');
    } catch (_) {
      if (!mounted) return;
      showErrorSnack(context, 'Could not delete the notification.');
      await _load(); // put the row back so the UI matches the database
    }
  }

  Future<void> _markAllRead() async {
    try {
      await DatabaseHelper.instance.markAllNotificationsRead(widget.tenant.id!);
      if (!mounted) return;
      showSuccessSnack(context, 'All notifications marked as read.');
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Mark all read failed: $error\n$stackTrace');
      if (!mounted) return;
      showErrorSnack(context, 'Could not update your notifications.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => !n.isRead).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loadFailed
          ? ErrorState(
              title: 'Notifications could not be loaded',
              subtitle: 'This screen could not reach the database. '
                  'Pull down to try again.',
              onRetry: _load,
            )
          : _notifications.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none,
              title: 'No notifications',
              subtitle: 'You are all caught up!',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _notifications.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final n = _notifications[i];
                  return Dismissible(
                    key: ValueKey(n.recipientRowId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _delete(n),
                    child: EcoCard(
                      onTap: () => _open(n),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: n.isRead
                                  ? Colors.transparent
                                  : AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.title,
                                  style: TextStyle(
                                    fontWeight: n.isRead
                                        ? FontWeight.w500
                                        : FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(n.message,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textMuted)),
                                const SizedBox(height: 4),
                                Text(
                                  '${n.sender} · ${formatRelativeDate(n.createdAt)}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}