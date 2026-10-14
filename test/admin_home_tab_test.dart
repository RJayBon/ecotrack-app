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
/// resolves, so this test does not need a working database: if the invalid
/// constraint ever comes back, `takeException()` is non-null.
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
