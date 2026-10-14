import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  List<Map<String, dynamic>> _sent = [];

  /// True when the last load threw - see `_AdminActivitiesScreenState`.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await DatabaseHelper.instance.getAllNotificationsAdmin();
      if (!mounted) return;
      setState(() {
        _sent = list;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Notification list load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _openCompose() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ComposeNotificationSheet(),
    );
    if (sent == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCompose,
        icon: const Icon(Icons.send),
        label: const Text('Send Notification'),
      ),
      body: _loadFailed
          ? ErrorState(
              title: 'Notifications could not be loaded',
              subtitle: 'The sent list could not be read from the local '
                  'database. Please try again.',
              onRetry: _load,
            )
          : _sent.isEmpty
          ? EmptyState(
              icon: Icons.notifications_outlined,
              title: 'No notifications sent',
              subtitle: 'Send updates or reminders to your tenants.',
              action: ElevatedButton.icon(
                onPressed: _openCompose,
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Send Notification'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: _sent.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final n = _sent[i];
                  final recipients = (n['recipient_count'] as int?) ?? 0;
                  final read = (n['read_count'] as int?) ?? 0;
                  return EcoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.notifications,
                              color: AppColors.primary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(n['title'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14.5))),
                        ]),
                        const SizedBox(height: 6),
                        Text(n['message'] as String,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textMuted)),
                        const SizedBox(height: 8),
                        Text(
                            'Sent to $recipients tenant(s) · $read read · '
                            '${formatRelativeDate(n['created_at'] as String)}',
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textMuted)),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _ComposeNotificationSheet extends StatefulWidget {
  const _ComposeNotificationSheet();

  @override
  State<_ComposeNotificationSheet> createState() =>
      _ComposeNotificationSheetState();
}

class _ComposeNotificationSheetState
    extends State<_ComposeNotificationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  // Defaults to 'active'. The previous default was 'all', which quietly
  // queued notifications for deactivated tenants who can never sign in to
  // read them.
  String _target = 'active'; // all | active | select
  List<Tenant> _tenants = [];
  final Set<int> _selected = {};
  bool _saving = false;
  bool _loadingTenants = true;

  /// Distinguishes "the tenant list could not be read" from "there are no
  /// tenants", which previously both rendered as "No tenants available." -
  /// telling the admin to give up rather than retry.
  bool _tenantsLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadTenants();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTenants() async {
    try {
      final list = await DatabaseHelper.instance.getTenants();
      if (!mounted) return;
      setState(() {
        _tenants = list;
        _loadingTenants = false;
        _tenantsLoadFailed = false;
      });
    } catch (error, stackTrace) {
      // DEFECT FIX (B4): a failed read left `_loadingTenants` true forever, so
      // the picker showed a permanent "Loading tenants..." with no retry.
      debugPrint('Compose tenant list load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loadingTenants = false;
        _tenantsLoadFailed = true;
      });
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    // For the "select" branch there is no async gap before we read
    // `_selected`, so we can validate up-front without touching context.
    if (_target == 'select' && _selected.isEmpty) {
      showErrorSnack(context, 'Select at least one tenant.');
      return;
    }

    setState(() => _saving = true);

    try {
      final List<int> tenantIds;
      if (_target == 'all') {
        tenantIds = await DatabaseHelper.instance.getAllTenantIds();
      } else if (_target == 'active') {
        tenantIds =
            await DatabaseHelper.instance.getAllTenantIds(activeOnly: true);
      } else {
        tenantIds = _selected.toList();
      }

      // Guard: after the async gap(s) above, `context` may be stale.
      if (!mounted) return;

      if (tenantIds.isEmpty) {
        setState(() => _saving = false);
        showErrorSnack(context, 'No recipients match the selected target.');
        return;
      }

      await DatabaseHelper.instance.sendNotification(
        title: _titleCtrl.text.trim(),
        message: _messageCtrl.text.trim(),
        sender: 'Admin',
        tenantIds: tenantIds,
      );
      if (!mounted) return;
      showSuccessSnack(
          context, 'Notification sent to ${tenantIds.length} tenant(s).');
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      // DEFECT FIX (B2): a failure anywhere above left `_saving` true, so the
      // button was stuck on "Sending..." forever and the sheet could only be
      // swiped away - with the admin left guessing whether a broadcast to
      // every tenant had actually gone out. Note the busy flag is now set
      // *before* the recipient queries too, so they cannot be re-tapped while
      // in flight.
      debugPrint('Send notification failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Could not send the notification.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // DEFECT FIX (E2): shared SheetHandle, using the vetted
                // AppColors.cardBorder instead of raw grey.shade300.
                const SheetHandle(),
                const SizedBox(height: 16),
                const Text('Send Notification',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                LabeledField(
                    label: 'Title',
                    controller: _titleCtrl,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null),
                LabeledField(
                    label: 'Message',
                    controller: _messageCtrl,
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null),
                const Text('Recipients',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                        label: const Text('Active Tenants'),
                        selected: _target == 'active',
                        onSelected: (_) => setState(() => _target = 'active')),
                    ChoiceChip(
                        label: const Text('All (incl. deactivated)'),
                        selected: _target == 'all',
                        onSelected: (_) => setState(() => _target = 'all')),
                    ChoiceChip(
                        label: const Text('Choose Tenants'),
                        selected: _target == 'select',
                        onSelected: (_) => setState(() => _target = 'select')),
                  ],
                ),
                if (_target == 'select') ...[
                  const SizedBox(height: 12),
                  if (_loadingTenants)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Loading tenants...'))
                  else if (_tenantsLoadFailed)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(children: [
                        const Expanded(
                          child: Text(
                              'The tenant list could not be loaded.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted)),
                        ),
                        TextButton(
                            onPressed: _loadTenants,
                            child: const Text('Retry')),
                      ]),
                    )
                  else if (_tenants.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('No tenants available.'))
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                          border: Border.all(color: AppColors.cardBorder),
                          borderRadius: BorderRadius.circular(12)),
                      child: ListView(
                        shrinkWrap: true,
                        children: _tenants.map((t) {
                          final id = t.id!;
                          final selected = _selected.contains(id);
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            title: Text(t.name,
                                style: const TextStyle(fontSize: 13.5)),
                            subtitle: Text('Unit ${t.unit}',
                                style: const TextStyle(fontSize: 11.5)),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _send,
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 18),
                  label: Text(_saving ? 'Sending...' : 'Send Notification'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}