import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/icon_map.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class AdminRewardsScreen extends StatefulWidget {
  const AdminRewardsScreen({super.key});

  @override
  State<AdminRewardsScreen> createState() => _AdminRewardsScreenState();
}

class _AdminRewardsScreenState extends State<AdminRewardsScreen> {
  List<Reward> _rewards = [];

  /// Archived rewards stay in the database so redemption history stays
  /// auditable. Hidden by default; restorable from here.
  bool _showArchived = false;

  /// True when the last load threw - see `_AdminActivitiesScreenState`.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await DatabaseHelper.instance
          .getRewards(includeArchived: _showArchived);
      if (!mounted) return;
      setState(() {
        _rewards = list;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Reward list load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _openForm({Reward? reward}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RewardFormSheet(reward: reward),
    );
    if (result == true) await _load();
  }

  /// Archives rather than deletes - see DatabaseHelper.deleteReward.
  Future<void> _archive(Reward r) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archive Reward',
      message: 'Archive "${r.title}"?\n\n'
          'It will be hidden from tenants and from this list. Past '
          'redemptions and the points already spent are kept, and you can '
          'restore it at any time.',
      confirmLabel: 'Archive',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await DatabaseHelper.instance.deleteReward(r.id!);
      if (!mounted) return;
      showSuccessSnack(context, 'Reward archived.');
      await _load();
    } catch (error, stackTrace) {
      // DEFECT FIX (B2): see _archive in admin_activities_screen.dart.
      debugPrint('Archive reward failed: $error\n$stackTrace');
      if (!mounted) return;
      showErrorSnack(context, 'Could not archive the reward.');
    }
  }

  Future<void> _restore(Reward r) async {
    try {
      await DatabaseHelper.instance.restoreReward(r.id!);
      if (!mounted) return;
      showSuccessSnack(context, 'Reward restored.');
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Restore reward failed: $error\n$stackTrace');
      if (!mounted) return;
      showErrorSnack(context, 'Could not restore the reward.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rewards'),
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
        label: const Text('Add Reward'),
      ),
      body: _loadFailed
          ? ErrorState(
              title: 'Rewards could not be loaded',
              subtitle: 'The reward catalogue could not be read from the local '
                  'database. Please try again.',
              onRetry: _load,
            )
          : _rewards.isEmpty
          ? EmptyState(
              icon: Icons.card_giftcard,
              title: _showArchived ? 'Nothing archived' : 'No rewards yet',
              subtitle: _showArchived
                  ? 'Archived rewards will appear here and can be restored.'
                  : 'Add rewards tenants can redeem with their Eco Points.',
              action: _showArchived
                  ? null
                  : ElevatedButton.icon(
                      onPressed: _openForm,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Reward'),
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: _rewards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = _rewards[i];
                  // DEFECT FIX (D3): this row used to be wrapped in
                  // Opacity(opacity: archived ? 0.65 : 1). Opacity composites
                  // the whole subtree onto the card; measured against the
                  // 4.5:1 AA floor that gave 14.5px title 4.79:1 (pass),
                  // 12.5px description 2.67:1 (fail), '+N pts' pill 2.53:1
                  // (fail) and 'One-time'/'Archived' pills 2.52:1 (fail). So
                  // archived rows - the ones an admin reads most carefully
                  // before deciding to restore - were the least readable rows
                  // on the screen. Archived state is now carried by colour
                  // choice instead: textMuted on the white card is 5.34:1 and
                  // EcoPill at AppColors.textTintAlpha is 4.63:1.
                  final accent = r.archived ? AppColors.textMuted : AppColors.primary;
                  return EcoCard(
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.warning
                              .withValues(alpha: AppColors.iconTintAlpha),
                          child: Icon(iconFor(r.icon),
                              color: AppColors.warning, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.title,
                                  style: TextStyle(
                                      color: r.archived
                                          ? AppColors.textMuted
                                          : AppColors.textDark,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14.5)),
                              const SizedBox(height: 2),
                              Text(r.description,
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
                                  EcoPill('${r.pointsRequired} pts', color: accent),
                                  EcoPill(
                                    r.stock < 0 ? 'Unlimited' : '${r.stock} left',
                                    color: AppColors.textMuted,
                                  ),
                                  EcoPill(
                                    r.active ? 'Visible' : 'Hidden',
                                    color: r.active
                                        ? AppColors.accent
                                        : AppColors.danger,
                                  ),
                                  if (r.archived)
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
                              _openForm(reward: r);
                            } else if (v == 'restore') {
                              _restore(r);
                            } else {
                              _archive(r);
                            }
                          },
                          itemBuilder: (context) => [
                            if (!r.archived)
                              const PopupMenuItem(
                                  value: 'edit', child: Text('Edit')),
                            if (r.archived)
                              const PopupMenuItem(
                                  value: 'restore', child: Text('Restore')),
                            if (!r.archived)
                              const PopupMenuItem(
                                  value: 'archive',
                                  child: Text('Archive')),
                          ],
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

class _RewardFormSheet extends StatefulWidget {
  final Reward? reward;
  const _RewardFormSheet({this.reward});

  @override
  State<_RewardFormSheet> createState() => _RewardFormSheetState();
}

class _RewardFormSheetState extends State<_RewardFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _pointsCtrl;
  late final TextEditingController _stockCtrl;
  late String _icon;
  late bool _active;
  late bool _unlimited;
  bool _saving = false;

  bool get _isEdit => widget.reward != null;

  @override
  void initState() {
    super.initState();
    final r = widget.reward;
    _titleCtrl = TextEditingController(text: r?.title ?? '');
    _descCtrl = TextEditingController(text: r?.description ?? '');
    _pointsCtrl = TextEditingController(text: r?.pointsRequired.toString() ?? '50');
    _unlimited = r == null ? true : r.stock < 0;
    _stockCtrl = TextEditingController(
        text: (r != null && r.stock >= 0) ? r.stock.toString() : '10');
    _icon = r?.icon ?? 'card_giftcard';
    _active = r?.active ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _pointsCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final reward = Reward(
      id: widget.reward?.id,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      pointsRequired: int.tryParse(_pointsCtrl.text.trim()) ?? 0,
      stock: _unlimited ? -1 : (int.tryParse(_stockCtrl.text.trim()) ?? 0),
      active: _active,
      icon: _icon,
      archived: widget.reward?.archived ?? false,
      createdAt: widget.reward?.createdAt ?? '',
    );
    try {
      if (_isEdit) {
        await DatabaseHelper.instance.updateReward(reward);
      } else {
        await DatabaseHelper.instance.insertReward(reward);
      }
      if (!mounted) return;
      showSuccessSnack(context, _isEdit ? 'Reward updated.' : 'Reward added.');
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      // DEFECT FIX (B2): see _ActivityFormSheetState._submit.
      debugPrint('Save reward failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Could not save the reward.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
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
                // DEFECT FIX (E2): shared SheetHandle.
                const SheetHandle(),
                const SizedBox(height: 16),
                Text(_isEdit ? 'Edit Reward' : 'Add Reward',
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
                    label: 'Points required',
                    controller: _pointsCtrl,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null || n <= 0) return 'Enter a positive number';
                      return null;
                    }),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Unlimited stock',
                      style: TextStyle(fontSize: 14)),
                  value: _unlimited,
                  onChanged: (v) => setState(() => _unlimited = v),
                ),
                if (!_unlimited)
                  LabeledField(
                      label: 'Stock quantity',
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n < 0) return 'Enter a valid quantity';
                        return null;
                      }),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Visible to tenants',
                      style: TextStyle(fontSize: 14)),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
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
                      : Text(_isEdit ? 'Save Changes' : 'Add Reward'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}