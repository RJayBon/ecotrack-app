import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../utils/icon_map.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class TenantLearnScreen extends StatefulWidget {
  const TenantLearnScreen({super.key});

  @override
  State<TenantLearnScreen> createState() => _TenantLearnScreenState();
}

class _TenantLearnScreenState extends State<TenantLearnScreen> {
  List<WasteGuide> _guides = [];
  String _category = 'All';

  /// True when the last load failed, so the tab can say so instead of
  /// showing an empty list that looks like "there are no guides".
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
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
                    subtitle: 'This screen could not reach the database. '
                        'Pull down to try again.',
                    onRetry: _load,
                  )
                : _guides.isEmpty
                ? const EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: 'No guides available',
                    subtitle:
                        'Check back soon — your admin is adding new content.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _guides.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final g = _guides[i];
                        return EcoCard(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      _GuideDetailScreen(guide: g))),
                          child: Row(
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.textMuted),
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

class _GuideDetailScreen extends StatelessWidget {
  final WasteGuide guide;
  const _GuideDetailScreen({required this.guide});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(guide.category)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: AppColors.iconTintAlpha),
                  shape: BoxShape.circle),
              child: Icon(iconFor(guide.icon),
                  color: AppColors.primary, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          Text(guide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _section('Description', guide.description, Icons.info_outline),
          _section('Examples', guide.examples, Icons.list_alt),
          _section('Proper Disposal Method', guide.disposalMethod,
              Icons.delete_outline),
          _section('Recycling Tips', guide.recyclingTips,
              Icons.tips_and_updates_outlined),
        ],
      ),
    );
  }

  Widget _section(String title, String content, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: EcoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
            ]),
            const SizedBox(height: 8),
            Text(content,
                style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.textDark)),
          ],
        ),
      ),
    );
  }
}