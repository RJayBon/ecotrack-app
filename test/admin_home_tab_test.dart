import 'package:ecotrack/models/models.dart';
import 'package:ecotrack/screens/admin/admin_home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the bug that made the app "crash / stop responding"
/// right after signing in as an administrator.
///
/// The dashboard's "This Week" summary was a `Row` with
/// `crossAxisAlignment: CrossAxisAlignment.stretch` sitting directly inside
/// the dashboard `ListView`. A scrollable gives its children an unbounded
/// height, so the stretch handed both stat tiles `height: double.infinity`
/// and the very first layout pass after login threw
///
///     BoxConstraints forces an infinite height
///     (RenderFlex.performLayout)
///
/// The whole thing is laid out on the first frame, before any database read
/// resolves, so this test does not need a *working* database: if the invalid
/// constraint ever comes back, `takeException()` is non-null.
///
/// Be precise about what "does not need a working database" means, because it
/// is not the same as "does not touch the database". `AdminHomeTab.initState`
/// really does fire `_load()`, which issues six real `DatabaseHelper` reads. In
/// a `testWidgets` environment those hit sqflite's method-channel factory with
/// no plugin registered, so they fail with `MissingPluginException` - and
/// `_load()`'s own `catch` converts that into `_loadFailed = true`, which the
/// dashboard renders as a warning card. That is why this test passes without
/// any database fixture.
///
/// Do not "fix" that by initialising `sqflite_common_ffi` here: real async I/O
/// inside the `FakeAsync` zone a widget test runs in never completes, so the
/// reads would stall and any `pumpAndSettle` would time out. The widget test
/// asserts on layout, and layout is decided before the first read resolves -
/// the failing reads are harmless to it. Database behaviour is covered where it
/// belongs, in `database_helper_test.dart`, which does set up FFI because it
/// runs outside a widget test's fake-async zone.
void main() {
  testWidgets(
    'admin dashboard lays out on the first frame without an infinite-height '
    'error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminHomeTab(
            admin: Admin(
              userId: 1,
              name: 'Ada Admin',
              email: 'ada@example.com',
              createdAt: '2026-01-01T00:00:00.000',
            ),
          ),
        ),
      );

      // The invalid layout was thrown during this first pump.
      expect(tester.takeException(), isNull);

      // The "This Week" block that used to blow up is actually on screen.
      expect(find.text('This Week'), findsOneWidget);
      expect(find.text('New Tenants'), findsOneWidget);
      expect(find.text('Redemptions'), findsOneWidget);
    },
  );
}
