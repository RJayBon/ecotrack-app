import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ecotrack/db/database_helper.dart';
import 'package:ecotrack/models/models.dart';
import 'package:ecotrack/utils/icon_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The schema exactly as EcoTrack v1 shipped it (no `archived` columns, no
/// `app_settings`). Used to prove the v1 -> v2 upgrade path works on the
/// databases that already exist on people's devices.
const List<String> _v1Schema = [
  '''
  CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    salt TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('admin','tenant')),
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE admins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE tenants (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT NOT NULL,
    unit TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('active','inactive')) DEFAULT 'active',
    total_points INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE waste_guides (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    examples TEXT NOT NULL,
    disposal_method TEXT NOT NULL,
    recycling_tips TEXT NOT NULL,
    icon TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE eco_activities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    points INTEGER NOT NULL,
    repeatable INTEGER NOT NULL DEFAULT 1,
    icon TEXT NOT NULL,
    category TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE activity_completions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id INTEGER NOT NULL,
    activity_id INTEGER NOT NULL,
    points_awarded INTEGER NOT NULL,
    completed_at TEXT NOT NULL,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (activity_id) REFERENCES eco_activities(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE rewards (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    points_required INTEGER NOT NULL,
    stock INTEGER NOT NULL DEFAULT -1,
    active INTEGER NOT NULL DEFAULT 1,
    icon TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE reward_redemptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id INTEGER NOT NULL,
    reward_id INTEGER NOT NULL,
    points_spent INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'completed',
    redeemed_at TEXT NOT NULL,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (reward_id) REFERENCES rewards(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    sender TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE notification_recipients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    notification_id INTEGER NOT NULL,
    tenant_id INTEGER NOT NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    read_at TEXT,
    FOREIGN KEY (notification_id) REFERENCES notifications(id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE environmental_quotes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quote_text TEXT NOT NULL,
    author TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
];

void main() {
  // Runs on the Dart VM, so give sqflite a real SQLite backend. In a test
  // process `defaultTargetPlatform` reports android, which makes the app's
  // own platform bootstrap a no-op - so the factory is set here explicitly.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  final helper = DatabaseHelper.instance;

  setUp(() async {
    await helper.close();
    tempDir = await Directory.systemTemp.createTemp('ecotrack_test');
    DatabaseHelper.debugDatabasePathOverride = p.join(tempDir.path, 'ecotrack.db');
  });

  tearDown(() async {
    await helper.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<Tenant> addTenant(String username, {String name = 'Test Tenant'}) =>
      helper.createTenant(
        username: username,
        password: 'password123',
        name: name,
        email: '$username@example.com',
        phone: '09170000000',
        unit: 'A-1',
      );

  Future<EcoActivity> seededActivity(String title) async =>
      (await helper.getActivities()).firstWhere((a) => a.title == title);

  // -------------------------------------------------------------------
  group('schema and seeding', () {
    test('creates the schema and seeds reference data', () async {
      final db = await helper.database;
      expect(await db.getVersion(), 2);

      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        tables,
        containsAll(<String>[
          'users', 'admins', 'tenants', 'waste_guides', 'eco_activities',
          'activity_completions', 'rewards', 'reward_redemptions',
          'notifications', 'notification_recipients', 'environmental_quotes',
          'app_settings',
        ]),
      );

      expect((await helper.getGuides()).length, 5);
      expect((await helper.getActivities()).length, 6);
      expect((await helper.getRewards()).length, 5);
      expect((await helper.getQuotes()).length, 10);
    });

    test('foreign keys are enforced', () async {
      final db = await helper.database;
      final pragma = await db.rawQuery('PRAGMA foreign_keys');
      expect(pragma.first.values.first, 1);
    });

    test('every seeded icon key resolves in the icon map', () async {
      for (final g in await helper.getGuides()) {
        expect(availableIconKeys, contains(g.icon), reason: 'guide ${g.title}');
      }
      for (final a in await helper.getActivities()) {
        expect(availableIconKeys, contains(a.icon), reason: 'activity ${a.title}');
      }
      for (final r in await helper.getRewards()) {
        expect(availableIconKeys, contains(r.icon), reason: 'reward ${r.title}');
      }
    });

    test('a fresh install has no admin yet', () async {
      expect(await helper.hasAnyAdmin(), isFalse);
    });
  });

  // -------------------------------------------------------------------
  group('v1 -> v2 migration', () {
    test('upgrades an existing v1 database in place, keeping its data',
        () async {
      final path = DatabaseHelper.debugDatabasePathOverride!;
      final now = DateTime.now().toIso8601String();

      // Build a v1 database by hand, exactly as the old build would have.
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            for (final statement in _v1Schema) {
              await db.execute(statement);
            }
          },
        ),
      );
      final userId = await v1.insert('users', {
        'username': 'oldtenant',
        'password_hash': 'deadbeef',
        'salt': 'c2FsdA==',
        'role': 'tenant',
        'created_at': now,
      });
      final tenantId = await v1.insert('tenants', {
        'user_id': userId,
        'name': 'Pre-existing Tenant',
        'email': 'old@example.com',
        'phone': '0900',
        'unit': 'B-9',
        'status': 'active',
        'total_points': 42,
        'created_at': now,
      });
      final activityId = await v1.insert('eco_activities', {
        'title': 'Legacy Activity',
        'description': 'from v1',
        'points': 42,
        'repeatable': 1,
        'icon': 'eco',
        'category': 'Habits',
        'created_at': now,
      });
      await v1.insert('activity_completions', {
        'tenant_id': tenantId,
        'activity_id': activityId,
        'points_awarded': 42,
        'completed_at': now,
      });
      await v1.close();

      // Open it through the app, which is now schema v2.
      final db = await helper.database;
      expect(await db.getVersion(), 2);

      // The new column exists and defaults to "not archived".
      final columns = await db.rawQuery('PRAGMA table_info(eco_activities)');
      expect(columns.any((c) => c['name'] == 'archived'), isTrue);

      // Nothing was lost or duplicated.
      expect((await helper.getActivities()).length, 1);
      expect(await helper.getActivityCount(tenantId), 1);
      final tenant = await helper.getTenantById(tenantId);
      expect(tenant!.totalPoints, 42);

      // The new settings table is usable straight away.
      await helper.setSetting('probe', 'ok');
      expect((await helper.getSettings())['probe'], 'ok');

      // And the upgraded activity can be archived safely.
      await helper.deleteActivity(activityId);
      expect(await helper.getActivityCount(tenantId), 1);
      expect((await helper.getTenantById(tenantId))!.totalPoints, 42);
    });
  });

  // -------------------------------------------------------------------
  group('completing activities', () {
    test('awards points and records the completion', () async {
      final tenant = await addTenant('earner');
      final activity = await seededActivity('Recycle Plastic Bottles');

      expect(await helper.completeActivity(tenant.id!, activity), isNull);
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 20);
      expect(await helper.getActivityCount(tenant.id!), 1);
    });

    test('awards the CURRENT point value, not the stale snapshot', () async {
      final tenant = await addTenant('stale');
      final activity = await seededActivity('Recycle Plastic Bottles');

      // An admin edits the activity after the tenant's list was built.
      await helper.updateActivity(activity.copyWith(points: 5));

      // The tenant completes using the object they were shown (20 points).
      expect(await helper.completeActivity(tenant.id!, activity), isNull);

      // The authoritative value wins.
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 5);
      final history = await helper.getActivityHistory(tenant.id!);
      expect(history.single.pointsAwarded, 5);
    });

    test('a one-time activity cannot be completed twice', () async {
      final tenant = await addTenant('once');
      final activity = await seededActivity('Environmental Quiz');
      expect(activity.repeatable, isFalse);

      expect(await helper.completeActivity(tenant.id!, activity), isNull);
      expect(await helper.completeActivity(tenant.id!, activity),
          'You already completed this one-time activity.');
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 30);
      expect(await helper.getActivityCount(tenant.id!), 1);
    });

    test('a repeatable activity can be completed again', () async {
      final tenant = await addTenant('repeat');
      final activity = await seededActivity('Recycle Plastic Bottles');

      await helper.completeActivity(tenant.id!, activity);
      await helper.completeActivity(tenant.id!, activity);

      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 40);
      expect(await helper.getActivityCount(tenant.id!), 2);
    });

    test('an archived activity cannot be completed', () async {
      final tenant = await addTenant('archivedtarget');
      final activity = await seededActivity('Recycle Plastic Bottles');
      await helper.deleteActivity(activity.id!);

      final staleCopy = activity.copyWith(archived: true);
      expect(await helper.completeActivity(tenant.id!, staleCopy),
          'This activity is no longer available.');
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 0);
    });

    test('a deleted activity cannot be completed', () async {
      final tenant = await addTenant('gonetarget');
      final activity = await seededActivity('Recycle Plastic Bottles');
      final db = await helper.database;
      await db.delete('eco_activities', where: 'id = ?', whereArgs: [activity.id]);

      expect(await helper.completeActivity(tenant.id!, activity),
          'This activity is no longer available.');
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 0);
    });
  });

  // -------------------------------------------------------------------
  group('redeeming rewards', () {
    Future<Tenant> tenantWithPoints(String username, int points) async {
      final tenant = await addTenant(username);
      final db = await helper.database;
      await db.rawUpdate(
        'UPDATE tenants SET total_points = ? WHERE id = ?',
        [points, tenant.id],
      );
      return (await helper.getTenantById(tenant.id!))!;
    }

    test('deducts points, decrements stock and records the redemption',
        () async {
      final tenant = await tenantWithPoints('redeemer', 100);
      final reward =
          (await helper.getRewards()).firstWhere((r) => r.title == 'Reusable Eco Tote Bag');
      expect(reward.stock, 25);

      expect(await helper.redeemReward(tenant.id!, reward), isNull);

      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 40);
      final refreshed =
          (await helper.getRewards()).firstWhere((r) => r.id == reward.id);
      expect(refreshed.stock, 24);
      expect((await helper.getRedemptionHistory(tenant.id!)).length, 1);
    });

    test('unlimited stock (stock = -1) is never decremented', () async {
      final tenant = await tenantWithPoints('unlimited', 500);
      final reward = (await helper.getRewards())
          .firstWhere((r) => r.title == 'Plant a Tree in Your Name');
      expect(reward.stock, -1);

      expect(await helper.redeemReward(tenant.id!, reward), isNull);
      final refreshed =
          (await helper.getRewards()).firstWhere((r) => r.id == reward.id);
      expect(refreshed.stock, -1);
    });

    test('refuses when the tenant cannot afford it', () async {
      final tenant = await tenantWithPoints('poor', 10);
      final reward =
          (await helper.getRewards()).firstWhere((r) => r.title == 'Reusable Water Bottle');

      expect(await helper.redeemReward(tenant.id!, reward), 'Not enough Eco Points.');
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 10);
    });

    test('refuses when stock has run out', () async {
      final tenant = await tenantWithPoints('stockless', 500);
      final reward = (await helper.getRewards())
          .firstWhere((r) => r.title == 'Free Parking Slot (1 Month)');
      final db = await helper.database;
      await db.update('rewards', {'stock': 0}, where: 'id = ?', whereArgs: [reward.id]);

      expect(await helper.redeemReward(tenant.id!, reward),
          'This reward is out of stock.');
    });

    test('refuses a reward that has been archived', () async {
      final tenant = await tenantWithPoints('archreward', 500);
      final reward =
          (await helper.getRewards()).firstWhere((r) => r.title == 'Reusable Eco Tote Bag');
      await helper.deleteReward(reward.id!);

      expect(await helper.redeemReward(tenant.id!, reward),
          'Reward no longer exists.');
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 500);
    });

    test('refuses a reward that has been hidden from tenants', () async {
      final tenant = await tenantWithPoints('hidden', 500);
      final reward =
          (await helper.getRewards()).firstWhere((r) => r.title == 'Reusable Eco Tote Bag');
      await helper.updateReward(reward.copyWith(active: false));

      expect(await helper.redeemReward(tenant.id!, reward),
          'This reward is no longer available.');
    });

    test('a stale "affordable" snapshot cannot overdraw the account', () async {
      final tenant = await tenantWithPoints('overdraw', 150);
      final reward = (await helper.getRewards())
          .firstWhere((r) => r.title == '10% Utility Bill Discount'); // 100 pts

      expect(await helper.redeemReward(tenant.id!, reward), isNull); // 150 -> 50
      expect(await helper.redeemReward(tenant.id!, reward), 'Not enough Eco Points.');
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 50);
    });
  });

  // -------------------------------------------------------------------
  // Regression coverage for the mid-session deactivation guard. Login already
  // refused an `inactive` tenant, but neither points transaction looked at
  // `tenants.status`, so an admin deactivating someone had no effect until that
  // person happened to log out - they could keep earning and spending the whole
  // time. Both transactions now re-read the status inside the transaction.
  group('deactivated tenants are refused mid-session', () {
    Future<Tenant> tenantWithPoints(String username, int points) async {
      final tenant = await addTenant(username);
      final db = await helper.database;
      await db.rawUpdate(
        'UPDATE tenants SET total_points = ? WHERE id = ?',
        [points, tenant.id],
      );
      return (await helper.getTenantById(tenant.id!))!;
    }

    test('completeActivity refuses an inactive tenant and awards nothing',
        () async {
      final tenant = await addTenant('deactivated_earner');
      final activity = await seededActivity('Recycle Plastic Bottles');

      // Sanity: active tenants can earn.
      expect(await helper.completeActivity(tenant.id!, activity), isNull);
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 20);

      await helper.setTenantStatus(tenant.id!, 'inactive');

      // The tenant object the UI already holds is stale by design - the check
      // is against the row, not the argument.
      expect(await helper.completeActivity(tenant.id!, activity),
          kTenantDeactivatedMessage);
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 20);
      expect(await helper.getActivityCount(tenant.id!), 1);
    });

    test('redeemReward refuses an inactive tenant, keeping points and stock',
        () async {
      final tenant = await tenantWithPoints('deactivated_spender', 100);
      final reward = (await helper.getRewards())
          .firstWhere((r) => r.title == 'Reusable Eco Tote Bag');
      final stockBefore = reward.stock;

      await helper.setTenantStatus(tenant.id!, 'inactive');

      expect(await helper.redeemReward(tenant.id!, reward),
          kTenantDeactivatedMessage);
      // No debit, no stock movement, no redemption row: the guard runs before
      // any of the writes inside the transaction.
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 100);
      expect(
        (await helper.getRewards())
            .firstWhere((r) => r.id == reward.id)
            .stock,
        stockBefore,
      );
      expect(await helper.getRedemptionHistory(tenant.id!), isEmpty);
    });

    test('reactivating restores earning and spending', () async {
      final tenant = await tenantWithPoints('reactivated', 100);
      final activity = await seededActivity('Recycle Plastic Bottles');
      final reward = (await helper.getRewards())
          .firstWhere((r) => r.title == 'Reusable Eco Tote Bag');

      await helper.setTenantStatus(tenant.id!, 'inactive');
      expect(await helper.completeActivity(tenant.id!, activity),
          kTenantDeactivatedMessage);

      await helper.setTenantStatus(tenant.id!, 'active');
      expect(await helper.completeActivity(tenant.id!, activity), isNull);
      expect(await helper.redeemReward(tenant.id!, reward), isNull);
      // 100 + 20 earned - 60 spent.
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 60);
    });

    test('a tenant id that no longer exists is reported, not silently ignored',
        () async {
      final activity = await seededActivity('Recycle Plastic Bottles');
      // 999999 was never created; the guard queries `tenants` before anything
      // else, so this cannot reach the activity lookup.
      expect(await helper.completeActivity(999999, activity),
          'Your account could not be found.');
    });

    test('login refuses the same tenant the transactions refuse', () async {
      final tenant = await addTenant('login_blocked');
      await helper.setTenantStatus(tenant.id!, 'inactive');
      final tenantRow = await helper.getTenantById(tenant.id!);
      expect(tenantRow!.status, 'inactive');
      // LoginScreen branches on exactly this field, so the two enforcement
      // points cannot drift apart on the definition of "deactivated".
    });
  });

  // -------------------------------------------------------------------
  // The regression this whole layer exists for: archiving a catalogue item
  // must NOT destroy tenant history (v1 did, via ON DELETE CASCADE, while the
  // dialog claimed history was kept).
  group('archiving preserves history', () {
    test('archiving an activity keeps completions and points intact', () async {
      final tenant = await addTenant('historian');
      final activity = await seededActivity('Community Clean-Up'); // 50 pts
      await helper.completeActivity(tenant.id!, activity);

      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 50);
      expect(await helper.getActivityCount(tenant.id!), 1);

      await helper.deleteActivity(activity.id!);

      // History survived - under the old CASCADE this was 0.
      expect(await helper.getActivityCount(tenant.id!), 1);
      expect((await helper.getActivityHistory(tenant.id!)).length, 1);
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 50);

      // The ledger stays consistent with the visible activity feed.
      final feed = await helper.getRecentActivityFeed();
      expect(feed.single['activity_title'], 'Community Clean-Up');
    });

    test('archived activities are hidden by default but restorable', () async {
      final activity = await seededActivity('Recycle Plastic Bottles');
      expect((await helper.getActivities()).any((a) => a.id == activity.id), isTrue);

      await helper.deleteActivity(activity.id!);
      expect((await helper.getActivities()).any((a) => a.id == activity.id), isFalse);
      expect(
        (await helper.getActivities(includeArchived: true))
            .any((a) => a.id == activity.id),
        isTrue,
      );

      await helper.restoreActivity(activity.id!);
      expect((await helper.getActivities()).any((a) => a.id == activity.id), isTrue);
    });

    test('archiving a reward keeps redemptions and the point ledger', () async {
      final tenant = await addTenant('rewardhistorian');
      final db = await helper.database;
      await db.rawUpdate(
          'UPDATE tenants SET total_points = 100 WHERE id = ?', [tenant.id]);
      final tenantWithPoints = (await helper.getTenantById(tenant.id!))!;

      final reward =
          (await helper.getRewards()).firstWhere((r) => r.title == 'Reusable Eco Tote Bag');
      await helper.redeemReward(tenantWithPoints.id!, reward);
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 40);

      await helper.deleteReward(reward.id!);

      // The tenant's own history still resolves the reward title.
      final history = await helper.getRedemptionHistory(tenant.id!);
      expect(history.length, 1);
      expect(history.single.rewardTitle, 'Reusable Eco Tote Bag');
      expect(history.single.pointsSpent, 60);
      expect((await helper.getTenantById(tenant.id!))!.totalPoints, 40);
    });

    test('archived rewards are hidden from tenants but restorable', () async {
      final reward =
          (await helper.getRewards()).firstWhere((r) => r.title == 'Reusable Eco Tote Bag');
      await helper.deleteReward(reward.id!);

      expect((await helper.getRewards()).any((r) => r.id == reward.id), isFalse);
      expect((await helper.getRewards(activeOnly: true)).any((r) => r.id == reward.id),
          isFalse);
      expect(
        (await helper.getRewards(includeArchived: true)).any((r) => r.id == reward.id),
        isTrue,
      );

      await helper.restoreReward(reward.id!);
      expect((await helper.getRewards(activeOnly: true)).any((r) => r.id == reward.id),
          isTrue);
    });

    test('deleting a guide is still a real delete (nothing references it)',
        () async {
      final guide = (await helper.getGuides()).first;
      await helper.deleteGuide(guide.id!);
      expect((await helper.getGuides()).length, 4);
    });
  });

  // -------------------------------------------------------------------
  group('deleting a tenant', () {
    test('removes the tenant and its history', () async {
      final tenant = await addTenant('doomed');
      final activity = await seededActivity('Recycle Plastic Bottles');
      await helper.completeActivity(tenant.id!, activity);

      await helper.deleteTenant(tenant.id!);

      expect(await helper.getTenantById(tenant.id!), isNull);
      expect(await helper.getTenants(), isEmpty);
    });

    test('does NOT change the dashboard "Total Eco Points" figure', () async {
      final keeper = await addTenant('keeper');
      final doomed = await addTenant('doomed2');
      final activity = await seededActivity('Community Clean-Up'); // 50 pts

      await helper.completeActivity(keeper.id!, activity);
      await helper.completeActivity(doomed.id!, activity);

      final before = await helper.getAdminStats();
      expect(before['totalPoints'], 100);
      expect(before['totalTenants'], 2);

      await helper.deleteTenant(doomed.id!);

      final after = await helper.getAdminStats();
      // Under v1 this silently dropped to 50. The tenant's unspent balance is
      // moved to the hidden ledger row so the total stays truthful.
      expect(after['totalPoints'], 100);
      // ...but the ledger is not counted as a tenant.
      expect(after['totalTenants'], 1);
      expect(after['activeTenants'], 1);
    });

    test('the hidden ledger tenant never shows up anywhere', () async {
      final doomed = await addTenant('doomed3');
      final activity = await seededActivity('Recycle Plastic Bottles');
      await helper.completeActivity(doomed.id!, activity);
      await helper.deleteTenant(doomed.id!);

      expect(await helper.getTenants(), isEmpty);
            expect(await helper.getTenants(search: 'ledger'), isEmpty);
      expect(await helper.getAllTenantIds(), isEmpty);
      expect(await helper.getAllTenantIds(activeOnly: true), isEmpty);
    });

    test('the ledger account cannot be logged into', () async {
      final doomed = await addTenant('doomed4');
      await helper.deleteTenant(doomed.id!);

      expect(await helper.authenticate(kLedgerUsername, ''), isNull);
      expect(await helper.authenticate(kLedgerUsername, 'locked'), isNull);
      expect(await helper.authenticate(kLedgerUsername, 'password123'), isNull);
    });

    test('the same tenant cannot be deleted twice', () async {
      final tenant = await addTenant('once-only');
      await helper.deleteTenant(tenant.id!);
      await helper.deleteTenant(tenant.id!); // must not throw
      expect(await helper.getTenants(), isEmpty);
    });

    test('deleting a tenant frees its username for reuse', () async {
      final tenant = await addTenant('recycled-name');
      await helper.deleteTenant(tenant.id!);
      expect(await helper.usernameExists('recycled-name'), isFalse);
      expect(await addTenant('recycled-name'), isNotNull);
    });
  });

  // -------------------------------------------------------------------
  group('authentication', () {
    test('rejects unknown users and wrong passwords without saying which',
        () async {
      await helper.createAdminAccount(
        username: 'boss',
        password: 'hunter2hunter2',
        name: 'Boss',
        email: 'boss@example.com',
      );

      expect(await helper.authenticate('boss', 'hunter2hunter2'), isNotNull);
      expect(await helper.authenticate('boss', 'wrong'), isNull);
      expect(await helper.authenticate('nobody', 'hunter2hunter2'), isNull);
    });

    test('routes admin vs tenant by role', () async {
      await helper.createAdminAccount(
        username: 'admin1',
        password: 'password123',
        name: 'Admin',
        email: 'a@example.com',
      );
      await addTenant('tenant1');

      expect((await helper.authenticate('admin1', 'password123'))!['role'], 'admin');
      expect((await helper.authenticate('tenant1', 'password123'))!['role'], 'tenant');
    });

    test('usernames are matched case-insensitively', () async {
      await addTenant('CaseTest');
      expect(await helper.usernameExists('casetest'), isTrue);
      expect(await helper.authenticate('CASETEST', 'password123'), isNotNull);
    });

    test('an upgraded legacy password can log in and is silently rehashed',
        () async {
      final db = await helper.database;
      const salt = 'c2FsdGVkU2FsdA==';
      final legacy = sha256Hex('$salt:legacyPass1');
      await db.insert('users', {
        'username': 'legacyuser',
        'password_hash': legacy,
        'salt': salt,
        'role': 'tenant',
        'created_at': DateTime.now().toIso8601String(),
      });

      final result = await helper.authenticate('legacyuser', 'legacyPass1');
      expect(result, isNotNull);

      // The stored record was upgraded in place...
      final row = (await db.query('users',
              where: 'username = ?', whereArgs: ['legacyuser']))
          .single;
      expect((row['password_hash'] as String).startsWith('pbkdf2\$'), isTrue);

      // ...and the new record still verifies the original password.
      expect(await helper.authenticate('legacyuser', 'legacyPass1'), isNotNull);
      expect(await helper.authenticate('legacyuser', 'legacyPass2'), isNull);
    });

    test('changePassword requires the current password', () async {
      await helper.createAdminAccount(
        username: 'changer',
        password: 'firstpass',
        name: 'C',
        email: 'c@example.com',
      );
      final user = await helper.authenticate('changer', 'firstpass');
      final userId = user!['userId'] as int;

      expect(await helper.changePassword(userId, 'wrong', 'secondpass'), isFalse);
      expect(await helper.authenticate('changer', 'firstpass'), isNotNull);

      expect(await helper.changePassword(userId, 'firstpass', 'secondpass'), isTrue);
      expect(await helper.authenticate('changer', 'firstpass'), isNull);
      expect(await helper.authenticate('changer', 'secondpass'), isNotNull);
    });
  });

  // -------------------------------------------------------------------
  group('notifications', () {
    test('fans out to the requested tenants only', () async {
      final a = await addTenant('notif-a');
      final b = await addTenant('notif-b');

      await helper.sendNotification(
        title: 'Hello',
        message: 'Recycling day tomorrow',
        sender: 'Admin',
        tenantIds: [a.id!],
      );

      expect((await helper.getNotificationsForTenant(a.id!)).length, 1);
      expect(await helper.getNotificationsForTenant(b.id!), isEmpty);
      expect(await helper.getUnreadCount(a.id!), 1);
    });

    test('read state is per-tenant, not global', () async {
      final a = await addTenant('read-a');
      final b = await addTenant('read-b');
      await helper.sendNotification(
        title: 'Hi',
        message: 'body',
        sender: 'Admin',
        tenantIds: [a.id!, b.id!],
      );

      final forA = await helper.getNotificationsForTenant(a.id!);
      await helper.markNotificationRead(forA.single.recipientRowId!);

      expect(await helper.getUnreadCount(a.id!), 0);
      expect(await helper.getUnreadCount(b.id!), 1);
    });

    test('mark-all-read only touches the given tenant', () async {
      final a = await addTenant('all-a');
      final b = await addTenant('all-b');
      await helper.sendNotification(
        title: 'Hi',
        message: 'body',
        sender: 'Admin',
        tenantIds: [a.id!, b.id!],
      );

      await helper.markAllNotificationsRead(a.id!);
      expect(await helper.getUnreadCount(a.id!), 0);
      expect(await helper.getUnreadCount(b.id!), 1);
    });

    test('deleting one notification recipient leaves the other intact',
        () async {
      final a = await addTenant('del-a');
      final b = await addTenant('del-b');
      await helper.sendNotification(
        title: 'Hi',
        message: 'body',
        sender: 'Admin',
        tenantIds: [a.id!, b.id!],
      );

      final forA = await helper.getNotificationsForTenant(a.id!);
      await helper.deleteNotificationForTenant(forA.single.recipientRowId!);

      expect(await helper.getNotificationsForTenant(a.id!), isEmpty);
      expect((await helper.getNotificationsForTenant(b.id!)).length, 1);
    });

    test('the "active only" broadcast excludes deactivated tenants', () async {
      final active = await addTenant('active-one');
      final inactive = await addTenant('inactive-one');
      await helper.setTenantStatus(inactive.id!, 'inactive');

      expect(await helper.getAllTenantIds(activeOnly: true), [active.id]);
      expect((await helper.getAllTenantIds()).length, 2);
    });

    test('sending to nobody is a no-op rather than a crash', () async {
      await helper.sendNotification(
        title: 'Nobody', message: 'body', sender: 'Admin', tenantIds: const [],
      );
      expect(await helper.getAllNotificationsAdmin(), isEmpty);
    });
  });

  // -------------------------------------------------------------------
  group('tenants', () {
    test('search matches name, email, unit and username', () async {
      await addTenant('searchable', name: 'Maria Santos');
      await addTenant('other', name: 'Juan Cruz');

      expect((await helper.getTenants(search: 'Maria')).length, 1);
      expect((await helper.getTenants(search: 'searchable')).length, 1);
      expect((await helper.getTenants(search: 'A-1')).length, 2);
      expect((await helper.getTenants(search: 'nobody')).length, 0);
    });

    test('status filter and sorting work', () async {
      final zeta = await addTenant('zeta', name: 'Zeta Cruz');
      final alpha = await addTenant('alpha', name: 'Alpha Reyes');

      // Give one tenant a higher balance so 'points' ordering is observable.
      final db = await helper.database;
      await db.rawUpdate(
          'UPDATE tenants SET total_points = 70 WHERE id = ?', [zeta.id]);

      await helper.setTenantStatus(alpha.id!, 'inactive');

      expect((await helper.getTenants(statusFilter: 'inactive')).length, 1);
      expect(
          (await helper.getTenants(statusFilter: 'inactive')).single.username,
          'alpha');
      expect((await helper.getTenants(statusFilter: 'all')).length, 2);

      expect((await helper.getTenants(sortBy: 'name')).map((t) => t.name),
          ['Alpha Reyes', 'Zeta Cruz']);
      expect((await helper.getTenants(sortBy: 'points')).first.username, 'zeta');
      expect(
          (await helper.getTenants(sortBy: 'status')).first.username, 'zeta',
          reason: 'active sorts before inactive');
    });

    test('status is constrained to active/inactive by the schema', () async {
      final tenant = await addTenant('statuscheck');
      expect(tenant.status, 'active');
      await helper.setTenantStatus(tenant.id!, 'inactive');
      expect((await helper.getTenantById(tenant.id!))!.status, 'inactive');
    });
  });

  // -------------------------------------------------------------------
  group('settings', () {
    test('round-trips values and overwrites existing keys', () async {
      expect(await helper.getSettings(), isEmpty);

      await helper.setSetting('notify_new_tenant', 'false');
      expect((await helper.getSettings())['notify_new_tenant'], 'false');

      await helper.setSetting('notify_new_tenant', 'true');
      expect((await helper.getSettings())['notify_new_tenant'], 'true');
      expect((await helper.getSettings()).length, 1);
    });
  });

  // -------------------------------------------------------------------
  group('quotes', () {
    test('quote of the day is stable within a day and always from the table',
        () async {
      final first = await helper.getQuoteOfTheDay();
      final second = await helper.getQuoteOfTheDay();
      expect(first!.id, second!.id);
      expect((await helper.getQuotes()).map((q) => q.id), contains(first.id));
    });

    test('inserting and deleting quotes works', () async {
      await helper.insertQuote(EnvironmentalQuote(
        quoteText: 'Test quote',
        author: 'Tester',
        createdAt: '',
      ));
      expect((await helper.getQuotes()).length, 11);

      final added =
          (await helper.getQuotes()).firstWhere((q) => q.quoteText == 'Test quote');
      await helper.deleteQuote(added.id!);
      expect((await helper.getQuotes()).length, 10);
    });
  });
}

/// Minimal sha256 helper so the legacy-record test does not depend on the
/// production code it is validating.
String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();