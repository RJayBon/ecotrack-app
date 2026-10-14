import 'dart:async';
import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';
import 'admin_tenant_form_screen.dart';
import 'admin_tenant_detail_screen.dart';

class AdminTenantsScreen extends StatefulWidget {
  const AdminTenantsScreen({super.key});

  @override
  State<AdminTenantsScreen> createState() => _AdminTenantsScreenState();
}

class _AdminTenantsScreenState extends State<AdminTenantsScreen> {
  List<Tenant> _tenants = [];
  String _search = '';
  String _statusFilter = 'all';
  String _sortBy = 'name';
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tenants = await DatabaseHelper.instance.getTenants(
        search: _search,
        statusFilter: _statusFilter,
        sortBy: _sortBy,
      );
      if (!mounted) return;
      setState(() {
        _tenants = tenants;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Tenant list load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  void _onSearchChanged(String value) {
    _search = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
    setState(() {}); // update the clear (X) icon immediately
  }

  Future<void> _openForm({Tenant? tenant}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminTenantFormScreen(tenant: tenant)),
    );
    if (result == true) await _load();
  }

  Future<void> _openDetail(Tenant tenant) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => AdminTenantDetailScreen(tenantId: tenant.id!)),
    );
    if (result == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Tenant'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name, email or unit...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _search = '';
                          _debounce?.cancel();
                          _load();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _filterChip('All', 'all'),
                const SizedBox(width: 8),
                _filterChip('Active', 'active'),
                const SizedBox(width: 8),
                _filterChip('Inactive', 'inactive'),
                const SizedBox(width: 16),
                _sortMenu(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loadFailed
                ? ErrorState(
                    title: 'Tenants could not be loaded',
                    subtitle: 'The database did not return the tenant list. '
                        'Please try again.',
                    onRetry: _load,
                  )
                : _tenants.isEmpty
                ? EmptyState(
                    icon: Icons.people_outline,
                    title: 'No tenants found',
                    subtitle: _search.isEmpty
                        ? 'Add your first tenant to get started.'
                        : 'Try a different search or filter.',
                    action: ElevatedButton.icon(
                      onPressed: _openForm,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Tenant'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      itemCount: _tenants.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final t = _tenants[i];
                        return EcoCard(
                          onTap: () => _openDetail(t),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                // DEFECT FIX (accessibility): the initial is
                                // bold but default-sized (~14px), so it is NOT
                                // WCAG "large text" and needs 4.5:1. Primary on
                                // a primary tint measured 4.36:1 at alpha 0.12.
                                // textTintAlpha (0.08) gives 4.63:1.
                                backgroundColor: AppColors.primary
                                    .withValues(alpha: AppColors.textTintAlpha),
                                // nameInitial() also guards a whitespace-only
                                // name, which `name[0]` does not.
                                child: Text(nameInitial(t.name),
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(t.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14.5)),
                                    const SizedBox(height: 2),
                                    Text('Unit ${t.unit} · @${t.username}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  StatusBadge(status: t.status),
                                  const SizedBox(height: 6),
                                  Text('${t.totalPoints} pts',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textDark,
                                          fontWeight: FontWeight.w600)),
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

  Widget _filterChip(String label, String value) {
    final selected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        // setState, not just _load(): the chip's own selected border is drawn
        // from `_statusFilter`, so without a rebuild the tap changed the query
        // but the chip kept looking unselected.
        setState(() => _statusFilter = value);
        _load();
      },
    );
  }

  Widget _sortMenu() {
    return PopupMenuButton<String>(
      initialValue: _sortBy,
      onSelected: (v) {
        setState(() => _sortBy = v);
        _load();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'name', child: Text('Sort: Name')),
        PopupMenuItem(value: 'points', child: Text('Sort: Points')),
        PopupMenuItem(value: 'recent', child: Text('Sort: Recently Added')),
        PopupMenuItem(value: 'status', child: Text('Sort: Status')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.fieldFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: const Row(
          children: [
            Icon(Icons.sort, size: 16, color: AppColors.textDark),
            SizedBox(width: 6),
            Text('Sort',
                style: TextStyle(fontSize: 13, color: AppColors.textDark)),
          ],
        ),
      ),
    );
  }
}