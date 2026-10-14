import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../utils/icon_map.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';
import 'admin_guide_form_screen.dart';

class AdminGuidesScreen extends StatefulWidget {
  const AdminGuidesScreen({super.key});

  @override
  State<AdminGuidesScreen> createState() => _AdminGuidesScreenState();
}

class _AdminGuidesScreenState extends State<AdminGuidesScreen> {
  List<WasteGuide> _guides = [];
  String _category = 'All';
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final guides =
          await DatabaseHelper.instance.getGuides(category: _category);
      if (!mounted) return;
      setState(() {
        _guides = guides;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Guide list load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _openForm({WasteGuide? guide}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminGuideFormScreen(guide: guide)),
    );
    if (result == true) await _load();
  }

  Future<void> _delete(WasteGuide g) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Guide',
      message: 'Delete "${g.title}"? This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await DatabaseHelper.instance.deleteGuide(g.id!);
      if (!mounted) return;
      showSuccessSnack(context, 'Guide deleted.');
      await _load();
    } catch (error, stackTrace) {
      // DEFECT FIX (B2): an exception here escaped unhandled and the guide
      // stayed in the list with no explanation.
      debugPrint('Delete guide failed: $error\n$stackTrace');
      if (!mounted) return;
      showErrorSnack(context, 'Could not delete the guide.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Waste Guides')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Add Guide'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _catChip('All'),
                ...kWasteCategories.map(_catChip),
              ],
            ),
          ),
          Expanded(
            child: _loadFailed
                ? ErrorState(
                    title: 'Guides could not be loaded',
                    subtitle: 'The database did not return the guide list. '
                        'Please try again.',
                    onRetry: _load,
                  )
                : _guides.isEmpty
                ? EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: 'No guides yet',
                    subtitle:
                        'Add a waste segregation guide for tenants to learn from.',
                    action: ElevatedButton.icon(
                      onPressed: _openForm,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Guide'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: _guides.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final g = _guides[i];
                        return EcoCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.primary
                                    .withValues(alpha: AppColors.iconTintAlpha),
                                child: Icon(iconFor(g.icon),
                                    color: AppColors.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(g.category,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMuted,
                                            fontWeight: FontWeight.w600)),
                                    Text(g.title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14.5)),
                                    const SizedBox(height: 4),
                                    Text(g.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) =>
                                    v == 'edit' ? _openForm(guide: g) : _delete(g),
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _catChip(String label) {
    final selected = _category == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _category = label);
          _load();
        },
      ),
    );
  }
}