import 'package:flutter/material.dart';
import '../../models/models.dart';
import 'admin_home_tab.dart';
import 'admin_tenants_screen.dart';
import 'admin_guides_screen.dart';
import 'admin_more_screen.dart';

/// Root shell for the admin experience. Owns the bottom navigation and
/// swaps between the four top-level admin sections.
class AdminDashboardScreen extends StatefulWidget {
  final int adminUserId;
  final Admin admin;
  const AdminDashboardScreen({super.key, required this.adminUserId, required this.admin});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _index = 0;
  late Admin _admin;

  @override
  void initState() {
    super.initState();
    _admin = widget.admin;
  }

  void _refreshAdmin(Admin updated) => setState(() => _admin = updated);

  @override
  Widget build(BuildContext context) {
    final tabs = [
      AdminHomeTab(admin: _admin),
      const AdminTenantsScreen(),
      const AdminGuidesScreen(),
      AdminMoreScreen(admin: _admin, onAdminUpdated: _refreshAdmin),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Tenants'),
          BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book),
              label: 'Guides'),
          BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
