import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';
import '../login_screen.dart';
import 'tenant_home_tab.dart';
import 'tenant_learn_screen.dart';
import 'tenant_activities_screen.dart';
import 'tenant_rewards_screen.dart';
import 'tenant_profile_screen.dart';

/// Root shell for the tenant experience. Loads the tenant record once,
/// then hosts the Home | Learn | Activities | Rewards | Profile tabs.
class TenantHomeScreen extends StatefulWidget {
  final int tenantUserId;
  const TenantHomeScreen({super.key, required this.tenantUserId});

  @override
  State<TenantHomeScreen> createState() => _TenantHomeScreenState();
}

class _TenantHomeScreenState extends State<TenantHomeScreen> {
  int _index = 0;
  Tenant? _tenant;

  /// True once a load has completed without finding the tenant. Previously
  /// this state rendered a permanently blank screen with no explanation.
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t =
          await DatabaseHelper.instance.getTenantByUserId(widget.tenantUserId);
      if (!mounted) return;
      setState(() {
        _tenant = t;
        _notFound = t == null;
      });
    } catch (error, stackTrace) {
      // DEFECT FIX: if this read threw, `_tenant` stayed null and
      // `_notFound` stayed false, which rendered a spinner that never
      // stopped and never explained itself.
      debugPrint('Tenant shell load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _notFound = true);
    }
  }

  void _onTenantChanged() => _load();

  /// Switches the bottom-navigation tab. Passed down to `TenantHomeTab` so its
  /// Quick Access cards move between the *existing* tabs instead of pushing
  /// duplicate copies of screens this shell already hosts.
  void _goToTab(int i) {
    setState(() => _index = i);
    _load();
  }

  Future<void> _signOut() async {
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenant = _tenant;
    if (tenant == null) {
      return Scaffold(
        body: SafeArea(
          child: _notFound
              ? EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'Account unavailable',
                  subtitle: 'This tenant account could not be loaded. It may '
                      'have been removed by an administrator.',
                  action: ElevatedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Back to Log In'),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final tabs = [
      TenantHomeTab(
          tenant: tenant, onChanged: _onTenantChanged, onNavigate: _goToTab),
      const TenantLearnScreen(),
      TenantActivitiesScreen(tenant: tenant, onChanged: _onTenantChanged),
      TenantRewardsScreen(tenant: tenant, onChanged: _onTenantChanged),
      TenantProfileScreen(tenant: tenant, onChanged: _onTenantChanged),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _goToTab,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book),
              label: 'Learn'),
          BottomNavigationBarItem(
              icon: Icon(Icons.directions_run_outlined),
              activeIcon: Icon(Icons.directions_run),
              label: 'Activities'),
          BottomNavigationBarItem(
              icon: Icon(Icons.card_giftcard_outlined),
              activeIcon: Icon(Icons.card_giftcard),
              label: 'Rewards'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}