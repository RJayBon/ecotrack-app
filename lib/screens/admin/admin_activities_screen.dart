import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/icon_map.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class AdminActivitiesScreen extends StatefulWidget {
  const AdminActivitiesScreen({super.key});

  @override
  State<AdminActivitiesScreen> createState() => _AdminActivitiesScreenState();
}

class _AdminActivitiesScreenState extends State<AdminActivitiesScreen> {
  List<EcoActivity> _activities = [];

  /// Archived activities stay in the database so completion history and
  /// earned points stay auditable. They are hidden by default and can be
  /// revealed - and restored - from here.
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseHelper.instance
        .getActivities(includeArchived: _showArchived);
    if (!mounted) return;
    setState(() => _activities = list);
  }

  Future<void> _openForm({EcoActivity? activity}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActivityFormSheet(activity: activity),
    );
    if (result == true) await _load();
  }

  /// Archives rather than deletes - see DatabaseHelper.deleteActivity.
  Future<void> _archive(EcoActivity a) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archive Activity',
      message: 'Archive "${a.title}"?\n\n'
          'It will be hidden from tenants and from this list. Past '
          'completions and the points already earned are kept, and you can '
          'restore it at any time.',
      confirmLabel: 'Archive',
      danger: true,
    );
    if (!confirmed) return;
    await DatabaseHelper.instance.deleteActivity(a.id!);
    if (!mounted) return;
    showSuccessSnack(context, 'Activity archived.');
    await _load();
  }

  Future<void> _restore(EcoActivity a) async {
    await DatabaseHelper.instance.restoreActivity(a.id!);
    if (!mounted) return;
    showSuccessSnack(context, 'Activity restored.');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eco Activities'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Hide archived' : 'Show archived',
            icon: Icon(_showArchived
                ? Icons.visibility_off_outlined
                : Icons.archive_outlined),
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Add Activity'),
      ),
      body: _activities.isEmpty
          ? EmptyState(
              icon: Icons.directions_run,
              title: _showArchived ? 'Nothing archived' : 'No activities yet',
              subtitle: _showArchived
                  ? 'Archived activities will appear here and can be restored.'
                  : 'Add eco activities tenants can complete to earn points.',
              action: _showArchived
                  ? null
                  : ElevatedButton.icon(
                      onPressed: _openForm,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Activity'),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: _activities.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final a = _activities[i];
                  return EcoCard(
                    child: Opacity(
                      opacity: a.archived ? 0.65 : 1,
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: (a.archived
                                    ? AppColors.textMuted
                                    : AppColors.primary)
                                .withValues(alpha: 0.12),
                            child: Icon(
                              iconFor(a.icon),
                              color: a.archived
                                  ? AppColors.textMuted
                                  : AppColors.primary,
                              size: 20,
                            ),
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
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textMuted)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    EcoPill('${a.points} pts'),
                                    EcoPill(
                                      a.repeatable ? 'Repeatable' : 'One-time',
                                      color: AppColors.textMuted,
                                    ),
                                    EcoPill(a.category, color: AppColors.accent),
                                    if (a.archived)
                                      const EcoPill('Archived',
                                          color: AppColors.textMuted),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') {
                                _openForm(activity: a);
                              } else if (v == 'restore') {
                                _restore(a);
                              } else {
                                _archive(a);
                              }
                            },
                            itemBuilder: (context) => [
                              if (!a.archived)
                                const PopupMenuItem(
                                    value: 'edit', child: Text('Edit')),
                              if (a.archived)
                                const PopupMenuItem(
                                    value: 'restore', child: Text('Restore')),
                              if (!a.archived)
                                const PopupMenuItem(
                                    value: 'archive',
                                    child: Text('Archive')),
                            ],
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

class _ActivityFormSheet extends StatefulWidget {
  final EcoActivity? activity;
  const _ActivityFormSheet({this.activity});

  @override
  State<_ActivityFormSheet> createState() => _ActivityFormSheetState();
}

class _ActivityFormSheetState extends State<_ActivityFormSheet> {
  /// The categories a tenant can see in the Learn tab, plus the activity
  /// groupings already used by the seed data. Previously this field existed
  /// but had no editor, so every new activity was silently forced to
  /// 'Habits'.
  static const List<String> _categories = [
    'Habits',
    'Recycling',
    'Education',
    'Community',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _pointsCtrl;
  late String _category;
  late String _icon;
  late bool _repeatable;
  bool _saving = false;

  bool get _isEdit => widget.activity != null;

  @override
  void initState() {
    super.initState();
    final a = widget.activity;
    _titleCtrl = TextEditingController(text: a?.title ?? '');
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _pointsCtrl = TextEditingController(text: a?.points.toString() ?? '10');
    _category = a?.category ?? _categories.first;
    _icon = a?.icon ?? 'eco';
    _repeatable = a?.repeatable ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _pointsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final points = int.tryParse(_pointsCtrl.text.trim()) ?? 0;
    final activity = EcoActivity(
      id: widget.activity?.id,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      points: points,
      repeatable: _repeatable,
      icon: _icon,
      category: _category,
      archived: widget.activity?.archived ?? false,
      createdAt: widget.activity?.createdAt ?? '',
    );
    if (_isEdit) {
      await DatabaseHelper.instance.updateActivity(activity);
    } else {
      await DatabaseHelper.instance.insertActivity(activity);
    }
    if (!mounted) return;
    showSuccessSnack(context, _isEdit ? 'Activity updated.' : 'Activity added.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.cardBorder,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(_isEdit ? 'Edit Activity' : 'Add Activity',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                LabeledField(
                    label: 'Title',
                    controller: _titleCtrl,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null),
                LabeledField(
                    label: 'Description',
                    controller: _descCtrl,
                    maxLines: 2,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null),
                LabeledField(
                    label: 'Eco Points',
                    controller: _pointsCtrl,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final n = int.tryParse(v.trim());
                      if (n == null || n <= 0) return 'Enter a positive number';
                      return null;
                    }),
                const SizedBox(height: 6),
                const Text('Category',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories
                      .map((c) => ChoiceChip(
                            label: Text(c),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repeatable',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Tenants can complete this more than once',
                      style: TextStyle(fontSize: 12)),
                  value: _repeatable,
                  onChanged: (v) => setState(() => _repeatable = v),
                ),
                const SizedBox(height: 8),
                const Text('Icon',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                IconPicker(
                  selected: _icon,
                  onSelected: (key) => setState(() => _icon = key),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save Changes' : 'Add Activity'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}