import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'database_factory_stub.dart'
    if (dart.library.io) 'database_factory_io.dart'
    if (dart.library.js_interop) 'database_factory_web.dart';
import 'password_hasher.dart';

/// Sentinels for the hidden bookkeeping tenant used by [DatabaseHelper.deleteTenant].
///
/// Plain top-level constants (not class members) so other layers can filter
/// the row out without depending on DatabaseHelper's private API.
const String kLedgerUsername = '__ecotrack_ledger__';
const String kLedgerTenantName = '__ecotrack_ledger__';

/// Central SQLite access layer for EcoTrack.
///
/// Owns schema creation, migrations, seeding of reference content (guides,
/// activities, rewards, quotes) and every read/write operation used by the UI.
///
/// Runs on all Flutter platforms via a swappable factory:
///   * Android / iOS / macOS - native `sqflite`
///   * Windows / Linux       - `sqflite_common_ffi`
///   * Web                   - `sqflite_common_ffi_web` (sqlite3 wasm)
///
/// Call [initialize] once before anything else touches the database.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const int _schemaVersion = 2;

  /// Overrides the on-disk location. Only used by tests, which point this at
  /// [inMemoryDatabasePath] so a test run never touches a real database.
  static String? debugDatabasePathOverride;

  static bool _factoryInitialised = false;

  Database? _db;

  /// The open that is currently in flight, if any. See [database].
  Future<Database>? _opening;

  /// Installs the platform SQLite factory. Safe to call more than once.
  ///
  /// This must happen before [database] is first read, so [main] awaits it.
  /// It is also safe for tests to call.
  static Future<void> initialize() async {
    if (_factoryInitialised) return;
    _factoryInitialised = true;
    await initDatabaseFactory();
  }

  /// The open database handle, opened lazily on first use.
  ///
  /// The in-flight open is memoised in [_opening]. Without that guard, every
  /// caller that arrived while the first open was still running started its
  /// *own* `openDatabase()` - and that is exactly what happens on a normal
  /// admin login: [AdminDashboardScreen] builds four tabs at once, each of
  /// them fires several queries from `initState`, and the dashboard itself
  /// batches six more with `Future.wait`. That is a dozen concurrent open
  /// calls before the first one finishes, which can race `onCreate`/
  /// `onUpgrade` (the loser throws "table users already exists"), leave
  /// different callers holding different handles, and leave `_db` pointing at
  /// whichever handle happened to finish last.
  ///
  /// Awaiting one shared future means the database is opened exactly once and
  /// every caller in that frame gets the same, fully initialised handle.
  Future<Database> get database async {
    final open = _db;
    if (open != null) return open;

    final pending = _opening;
    if (pending != null) return pending;

    final future = _initDb();
    _opening = future;
    try {
      final db = await future;
      _db = db;
      return db;
    } finally {
      // Cleared synchronously right after the await resumes, so a caller that
      // arrives later either sees `_db` (success) or starts a fresh attempt
      // (failure, rather than a permanently poisoned future).
      _opening = null;
    }
  }

  /// Closes the handle and forgets it, so the next [database] access reopens.
  /// Used by tests and by anything that needs to swap the backing file.
  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    if (db != null) await db.close();
  }

  Future<Database> _initDb() async {
    // Make sure the factory is installed even if the caller forgot to await
    // initialize(). Without this the very first query throws a
    // "databaseFactory not initialized" error on desktop and web.
    await initialize();

    final path = debugDatabasePathOverride ?? await databaseFilePath();
    return openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createSchema(db);
        await _createIndexes(db);
        await _seedReferenceData(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db, oldVersion);
        await _createIndexes(db);
      },
    );
  }

  // ---------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------
  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('admin','tenant')),
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE admins (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL UNIQUE,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
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
    ''');
    await db.execute('''
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
    ''');
    await db.execute('''
      CREATE TABLE eco_activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        points INTEGER NOT NULL,
        repeatable INTEGER NOT NULL DEFAULT 1,
        icon TEXT NOT NULL,
        category TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE activity_completions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        activity_id INTEGER NOT NULL,
        points_awarded INTEGER NOT NULL,
        completed_at TEXT NOT NULL,
        FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
        FOREIGN KEY (activity_id) REFERENCES eco_activities(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE rewards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        points_required INTEGER NOT NULL,
        stock INTEGER NOT NULL DEFAULT -1,
        active INTEGER NOT NULL DEFAULT 1,
        icon TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
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
    ''');
    await db.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        sender TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE notification_recipients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notification_id INTEGER NOT NULL,
        tenant_id INTEGER NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        read_at TEXT,
        FOREIGN KEY (notification_id) REFERENCES notifications(id) ON DELETE CASCADE,
        FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE environmental_quotes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        quote_text TEXT NOT NULL,
        author TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    // Admin preferences (notification toggles, etc). Key/value so new
    // settings never need another migration.
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// Indexes live in their own method so both fresh installs ([onCreate]) and
  /// upgrades ([onUpgrade]) get any newly added index. `IF NOT EXISTS` makes
  /// running it twice harmless.
  Future<void> _createIndexes(Database db) async {
    final statements = <String>[
      'CREATE INDEX IF NOT EXISTS idx_activity_completions_tenant ON activity_completions(tenant_id)',
      'CREATE INDEX IF NOT EXISTS idx_activity_completions_activity ON activity_completions(activity_id)',
      'CREATE INDEX IF NOT EXISTS idx_reward_redemptions_tenant ON reward_redemptions(tenant_id)',
      'CREATE INDEX IF NOT EXISTS idx_notification_recipients_tenant ON notification_recipients(tenant_id)',
      'CREATE INDEX IF NOT EXISTS idx_notification_recipients_notification ON notification_recipients(notification_id)',
      // Backs the "is this one-time activity already done?" check and the
      // per-tenant activity list.
      'CREATE INDEX IF NOT EXISTS idx_activity_completions_tenant_activity ON activity_completions(tenant_id, activity_id)',
      // Backs ORDER BY ... DESC on the two history timelines.
      'CREATE INDEX IF NOT EXISTS idx_activity_completions_completed_at ON activity_completions(completed_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_reward_redemptions_redeemed_at ON reward_redemptions(redeemed_at DESC)',
      // Backs the Learn tab's category filter.
      'CREATE INDEX IF NOT EXISTS idx_waste_guides_category ON waste_guides(category)',
      // Backs "hide archived items" on the admin lists.
      'CREATE INDEX IF NOT EXISTS idx_eco_activities_archived ON eco_activities(archived)',
      'CREATE INDEX IF NOT EXISTS idx_rewards_archived ON rewards(archived)',
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  /// Brings an existing v1 database up to the current schema.
  ///
  /// Each step is written defensively (column existence is checked first) so
  /// that a database which was created by an older build - or by a partially
  /// applied upgrade - still converges on the right shape.
  Future<void> _migrate(Database db, int oldVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(
          db, 'eco_activities', 'archived', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          db, 'rewards', 'archived', 'INTEGER NOT NULL DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  // ---------------------------------------------------------------------
  // Reference data
  // ---------------------------------------------------------------------
  Future<void> _seedReferenceData(Database db) async {
    final now = DateTime.now().toIso8601String();

    final guides = [
      {
        'category': 'Biodegradable',
        'title': 'Food & Garden Waste',
        'description':
            'Organic material that decomposes naturally, such as leftover food, peelings and yard trimmings.',
        'examples': 'Fruit peels, vegetable scraps, eggshells, coffee grounds, leaves, grass clippings',
        'disposal_method':
            'Collect in a labeled green bin. Compost where possible or place out for organic waste collection.',
        'recycling_tips':
            'Start a home compost bin to turn scraps into fertilizer for plants and reduce landfill load.',
        'icon': 'eco',
      },
      {
        'category': 'Recyclable',
        'title': 'Paper, Plastic, Glass & Metal',
        'description':
            'Clean, dry materials that can be reprocessed into new products instead of going to a landfill.',
        'examples': 'Cardboard, newspaper, plastic bottles, glass jars, aluminum cans',
        'disposal_method':
            'Rinse containers, flatten boxes, and place in the designated blue recycling bin.',
        'recycling_tips':
            'Remove caps and labels when possible, and never bag recyclables in plastic bags.',
        'icon': 'recycling',
      },
      {
        'category': 'Residual',
        'title': 'Non-Recyclable Residual Waste',
        'description':
            'Waste that cannot be composted or recycled and must go to a sanitary landfill.',
        'examples': 'Soiled tissue, diapers, broken ceramics, styrofoam, cigarette butts',
        'disposal_method':
            'Place in a sealed bag inside the black/gray residual waste bin for regular collection.',
        'recycling_tips':
            'Reduce residual waste by choosing reusable products and avoiding single-use packaging.',
        'icon': 'delete',
      },
      {
        'category': 'Hazardous',
        'title': 'Household Hazardous Waste',
        'description':
            'Materials that are toxic, flammable, corrosive or reactive and require special handling.',
        'examples': 'Batteries, paint, pesticides, cleaning chemicals, fluorescent bulbs',
        'disposal_method':
            'Never mix with regular trash. Bring to a certified hazardous waste drop-off point.',
        'recycling_tips':
            'Buy only what you need and store hazardous items in original, labeled containers.',
        'icon': 'warning_amber',
      },
      {
        'category': 'Electronic Waste',
        'title': 'E-Waste',
        'description':
            'Discarded electronic devices and accessories containing metals that can be recovered.',
        'examples': 'Old phones, chargers, laptops, cables, small appliances',
        'disposal_method':
            'Drop off at an authorized e-waste recycling center; never place in regular trash.',
        'recycling_tips':
            'Wipe personal data before disposal and consider donating working devices.',
        'icon': 'devices_other',
      },
    ];
    // Seeding runs once, before the first frame, so it sits on the app's
    // critical start-up path. All 31 rows go through one batch instead of
    // one round trip per row.
    final batch = db.batch();
    for (final g in guides) {
      batch.insert('waste_guides', {...g, 'created_at': now});
    }

    final activities = [
      {
        'title': 'Recycle Plastic Bottles',
        'description': 'Collect and properly recycle at least 5 plastic bottles this week.',
        'points': 20,
        'repeatable': 1,
        'icon': 'recycling',
        'category': 'Recycling',
      },
      {
        'title': 'Properly Segregate Waste',
        'description': 'Sort your household waste into biodegradable, recyclable and residual bins.',
        'points': 15,
        'repeatable': 1,
        'icon': 'sort',
        'category': 'Habits',
      },
      {
        'title': 'Reduce Single-Use Plastics',
        'description': 'Go a full day without using any single-use plastic items.',
        'points': 25,
        'repeatable': 1,
        'icon': 'no_drinks',
        'category': 'Habits',
      },
      {
        'title': 'Read a Recycling Guide',
        'description': 'Read through one full waste segregation guide in the Learn tab.',
        'points': 10,
        'repeatable': 1,
        'icon': 'menu_book',
        'category': 'Education',
      },
      {
        'title': 'Environmental Quiz',
        'description': 'Complete the environmental awareness quiz.',
        'points': 30,
        'repeatable': 0,
        'icon': 'quiz',
        'category': 'Education',
      },
      {
        'title': 'Community Clean-Up',
        'description': 'Participate in a neighborhood or community clean-up drive.',
        'points': 50,
        'repeatable': 1,
        'icon': 'cleaning_services',
        'category': 'Community',
      },
    ];
    for (final a in activities) {
      batch.insert('eco_activities', {...a, 'created_at': now});
    }

    final rewards = [
      {
        'title': '10% Utility Bill Discount',
        'description': 'Redeem for a 10% discount voucher on your next utility bill.',
        'points_required': 100,
        'stock': -1,
        'active': 1,
        'icon': 'receipt_long',
      },
      {
        'title': 'Reusable Eco Tote Bag',
        'description': 'A durable, branded EcoTrack canvas tote bag.',
        'points_required': 60,
        'stock': 25,
        'active': 1,
        'icon': 'shopping_bag',
      },
      {
        'title': 'Reusable Water Bottle',
        'description': 'Stainless steel insulated water bottle.',
        'points_required': 80,
        'stock': 15,
        'active': 1,
        'icon': 'water_drop',
      },
      {
        'title': 'Free Parking Slot (1 Month)',
        'description': 'One month of complimentary reserved parking.',
        'points_required': 200,
        'stock': 5,
        'active': 1,
        'icon': 'local_parking',
      },
      {
        'title': 'Plant a Tree in Your Name',
        'description': 'We plant a tree in a local reforestation project and name it after you.',
        'points_required': 150,
        'stock': -1,
        'active': 1,
        'icon': 'park',
      },
    ];
    for (final r in rewards) {
      batch.insert('rewards', {...r, 'created_at': now});
    }

    final quotes = [
      {'quote_text': 'The earth does not belong to us; we belong to the earth.', 'author': 'Marlee Matlin'},
      {'quote_text': 'We do not inherit the earth from our ancestors; we borrow it from our children.', 'author': 'Native American Proverb'},
      {'quote_text': 'The greatest threat to our planet is the belief that someone else will save it.', 'author': 'Robert Swan'},
      {'quote_text': 'Reduce, reuse, recycle — in that order.', 'author': 'EcoTrack'},
      {'quote_text': 'Small acts, when multiplied by millions of people, can transform the world.', 'author': 'Howard Zinn'},
      {'quote_text': 'There is no such thing as away. When we throw anything away, it must go somewhere.', 'author': 'Annie Leonard'},
      {'quote_text': 'What we do to the environment, we do to ourselves.', 'author': 'Unknown'},
      {'quote_text': 'Every piece of plastic you refuse today is one less in the ocean tomorrow.', 'author': 'EcoTrack'},
      {'quote_text': 'Nature provides a free lunch, but only if we control our appetites.', 'author': 'William Ruckelshaus'},
      {'quote_text': 'A society grows great when people plant trees whose shade they know they shall never sit in.', 'author': 'Greek Proverb'},
    ];
    for (final q in quotes) {
      batch.insert('environmental_quotes', {...q, 'created_at': now});
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------

  /// True when at least one admin account exists (drives first-run setup).
  Future<bool> hasAnyAdmin() async {
    final db = await database;
    final rows = await db.query('users', where: 'role = ?', whereArgs: ['admin'], limit: 1);
    return rows.isNotEmpty;
  }

  /// Case-insensitive duplicate check. `users.username` is UNIQUE, but SQLite
  /// treats 'Admin' and 'admin' as distinct, so we normalise with LOWER()
  /// here to stop confusing near-duplicate accounts.
  Future<bool> usernameExists(String username) async {
    final db = await database;
    final rows = await db
        .query('users', where: 'LOWER(username) = LOWER(?)', whereArgs: [username.trim()], limit: 1);
    return rows.isNotEmpty;
  }

  /// Creates the very first admin account during initial app setup.
  Future<void> createAdminAccount({
    required String username,
    required String password,
    required String name,
    required String email,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final salt = PasswordHasher.generateSalt();
    final hash = await PasswordHasher.hashAsync(password, salt);
    await db.transaction((txn) async {
      final userId = await txn.insert('users', {
        'username': username.trim(),
        'password_hash': hash,
        'salt': salt,
        'role': 'admin',
        'created_at': now,
      });
      await txn.insert('admins', {
        'user_id': userId,
        'name': name,
        'email': email,
        'created_at': now,
      });
    });
  }

  /// Returns `{'userId': int, 'role': String}` on success, or null on failure.
  ///
  /// Returns null for *both* an unknown username and a wrong password, so the
  /// caller cannot be used to enumerate accounts.
  ///
  /// On a successful login against a legacy (single-SHA-256) record, the
  /// stored hash is transparently upgraded to PBKDF2 so existing users are
  /// migrated without any action on their part.
  Future<Map<String, dynamic>?> authenticate(String username, String password) async {
    final db = await database;
    final rows = await db.query('users',
        where: 'LOWER(username) = LOWER(?)', whereArgs: [username.trim()], limit: 1);
    if (rows.isEmpty) return null;

    final user = rows.first;
    final stored = user['password_hash'] as String;
    final salt = user['salt'] as String;

    final ok = await PasswordHasher.verifyAsync(
      password: password,
      stored: stored,
      legacySalt: salt,
    );
    if (!ok) return null;

    if (PasswordHasher.needsRehash(stored)) {
      // Best-effort: a failure here must not block a valid login.
      try {
        final newSalt = PasswordHasher.generateSalt();
        await db.update(
          'users',
          {'password_hash': await PasswordHasher.hashAsync(password, newSalt), 'salt': newSalt},
          where: 'id = ?',
          whereArgs: [user['id']],
        );
      } on DatabaseException {
        // Ignore - the user is still authenticated, they just stay on the
        // old hash for now.
      }
    }

    return {'userId': user['id'], 'role': user['role']};
  }

  Future<bool> changePassword(int userId, String currentPassword, String newPassword) async {
    final db = await database;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) return false;

    final user = rows.first;
    final ok = await PasswordHasher.verifyAsync(
      password: currentPassword,
      stored: user['password_hash'] as String,
      legacySalt: user['salt'] as String,
    );
    if (!ok) return false;

    final newSalt = PasswordHasher.generateSalt();
    await db.update(
      'users',
      {'password_hash': await PasswordHasher.hashAsync(newPassword, newSalt), 'salt': newSalt},
      where: 'id = ?',
      whereArgs: [userId],
    );
    return true;
  }

  // ---------------------------------------------------------------------
  // Tenants
  // ---------------------------------------------------------------------

  /// Creates a tenant plus its login account in one transaction.
  Future<Tenant> createTenant({
    required String username,
    required String password,
    required String name,
    required String email,
    required String phone,
    required String unit,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final salt = PasswordHasher.generateSalt();
    final hash = await PasswordHasher.hashAsync(password, salt);
    late int tenantId;
    await db.transaction((txn) async {
      final userId = await txn.insert('users', {
        'username': username.trim(),
        'password_hash': hash,
        'salt': salt,
        'role': 'tenant',
        'created_at': now,
      });
      tenantId = await txn.insert('tenants', {
        'user_id': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'unit': unit,
        'status': 'active',
        'total_points': 0,
        'created_at': now,
      });
    });
    final row = (await db.rawQuery('''
      SELECT t.*, u.username FROM tenants t
      JOIN users u ON u.id = t.user_id WHERE t.id = ?
    ''', [tenantId])).first;
    return Tenant.fromMap(row);
  }

  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  Future<List<Tenant>> getTenants({
    String? search,
    String? statusFilter,
    String sortBy = 'name',
  }) async {
    final db = await database;
    // The ledger row (see deleteTenant) belongs to no real user and must
    // never surface in any list or count.
    final where = <String>['u.username <> ?'];
    final args = <dynamic>[kLedgerUsername];

    if (search != null && search.trim().isNotEmpty) {
      // ESCAPE + escaped wildcards: searching for "50%" or "A_1" means those
      // literal characters, not "match anything".
      where.add(
          "(t.name LIKE ? ESCAPE '\\' OR t.email LIKE ? ESCAPE '\\' OR "
          "t.unit LIKE ? ESCAPE '\\' OR u.username LIKE ? ESCAPE '\\')");
      final like = '%${_escapeLike(search.trim())}%';
      args.addAll([like, like, like, like]);
    }
    if (statusFilter != null && statusFilter != 'all') {
      where.add('t.status = ?');
      args.add(statusFilter);
    }

    final String orderClause;
    switch (sortBy) {
      case 'points':
        orderClause = 'ORDER BY t.total_points DESC';
      case 'recent':
        orderClause = 'ORDER BY t.created_at DESC';
      case 'status':
        orderClause = 'ORDER BY t.status ASC, t.name ASC';
      default:
        orderClause = 'ORDER BY t.name ASC';
    }

    final rows = await db.rawQuery('''
      SELECT t.*, u.username FROM tenants t
      JOIN users u ON u.id = t.user_id
      WHERE ${where.join(' AND ')}
      $orderClause
    ''', args);
    return rows.map(Tenant.fromMap).toList();
  }

  Future<Tenant?> getTenantById(int id) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.*, u.username FROM tenants t
      JOIN users u ON u.id = t.user_id WHERE t.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return Tenant.fromMap(rows.first);
  }

  Future<Tenant?> getTenantByUserId(int userId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.*, u.username FROM tenants t
      JOIN users u ON u.id = t.user_id WHERE t.user_id = ?
    ''', [userId]);
    if (rows.isEmpty) return null;
    return Tenant.fromMap(rows.first);
  }

  Future<void> updateTenant(Tenant tenant) async {
    final db = await database;
    await db.update(
      'tenants',
      {
        'name': tenant.name,
        'email': tenant.email,
        'phone': tenant.phone,
        'unit': tenant.unit,
        'status': tenant.status,
      },
      where: 'id = ?',
      whereArgs: [tenant.id],
    );
  }

  Future<void> setTenantStatus(int tenantId, String status) async {
    final db = await database;
    await db.update('tenants', {'status': status}, where: 'id = ?', whereArgs: [tenantId]);
  }

  /// Permanently deletes a tenant, its login account and all of its history.
  ///
  /// The tenant's net Eco Point contribution is folded into a hidden
  /// bookkeeping tenant first, so that the cumulative "Total Eco Points"
  /// figure stays truthful. Without this, deleting a tenant silently reduced
  /// the dashboard total and made point balances unexplainable.
  ///
  /// The bookkeeping row belongs to no user account (its password hash cannot
  /// verify) and is excluded from every list and count.
  Future<void> deleteTenant(int tenantId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT t.user_id, t.total_points, u.username FROM tenants t
        JOIN users u ON u.id = t.user_id
        WHERE t.id = ?
      ''', [tenantId]);
      if (rows.isEmpty) return;

      // Never delete the bookkeeping row itself.
      if (rows.first['username'] == kLedgerUsername) return;

      final userId = rows.first['user_id'] as int;

      // `total_points` is already the tenant's *current balance* (earned
      // minus redeemed, maintained by the add/subtract updates elsewhere),
      // so moving the balance across is all that is needed to keep
      // SUM(total_points) - the dashboard's "Total Eco Points" - unchanged.
      final points = rows.first['total_points'] as int;

      final ledgerId = await _ensureLedgerTenant(txn);
      await txn.rawUpdate(
        'UPDATE tenants SET total_points = total_points + ? WHERE id = ?',
        [points, ledgerId],
      );

      // Children cascade from here (foreign_keys is ON).
      await txn.delete('tenants', where: 'id = ?', whereArgs: [tenantId]);
      await txn.delete('users', where: 'id = ?', whereArgs: [userId]);
    });
  }

  /// Creates (once) and returns the id of the hidden bookkeeping tenant.
  Future<int> _ensureLedgerTenant(DatabaseExecutor txn) async {
    final existing = await txn.query('tenants',
        columns: ['id'], where: 'name = ?', whereArgs: [kLedgerTenantName], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;

    final now = DateTime.now().toIso8601String();
    final userId = await txn.insert('users', {
      'username': kLedgerUsername,
      // Deliberately not a valid PBKDF2 record, so this account can never be
      // logged into.
      'password_hash': 'locked',
      'salt': 'locked',
      'role': 'tenant',
      'created_at': now,
    });
    return txn.insert('tenants', {
      'user_id': userId,
      'name': kLedgerTenantName,
      'email': '',
      'phone': '',
      'unit': '',
      'status': 'inactive',
      'total_points': 0,
      'created_at': now,
    });
  }

  // ---------------------------------------------------------------------
  // Admin profile
  // ---------------------------------------------------------------------
  Future<Admin?> getAdminByUserId(int userId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT a.*, u.username FROM admins a
      JOIN users u ON u.id = a.user_id WHERE a.user_id = ?
    ''', [userId]);
    if (rows.isEmpty) return null;
    return Admin.fromMap(rows.first);
  }

  Future<void> updateAdmin(Admin admin) async {
    final db = await database;
    await db.update('admins', {'name': admin.name, 'email': admin.email},
        where: 'id = ?', whereArgs: [admin.id]);
  }

  // ---------------------------------------------------------------------
  // Waste guides
  // ---------------------------------------------------------------------
  Future<List<WasteGuide>> getGuides({String? category}) async {
    final db = await database;
    final rows = (category == null || category == 'All')
        ? await db.query('waste_guides', orderBy: 'category ASC, title ASC')
        : await db.query('waste_guides',
            where: 'category = ?', whereArgs: [category], orderBy: 'title ASC');
    return rows.map(WasteGuide.fromMap).toList();
  }

  Future<int> insertGuide(WasteGuide g) async {
    final db = await database;
    final map = g.toMap()..remove('id');
    map['created_at'] = DateTime.now().toIso8601String();
    return db.insert('waste_guides', map);
  }

  Future<void> updateGuide(WasteGuide g) async {
    final db = await database;
    final map = g.toMap()
      ..remove('id')
      ..remove('created_at');
    await db.update('waste_guides', map, where: 'id = ?', whereArgs: [g.id]);
  }

  /// Hard delete - safe here because nothing references `waste_guides`.
  Future<void> deleteGuide(int id) async {
    final db = await database;
    await db.delete('waste_guides', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // Eco activities
  // ---------------------------------------------------------------------
  Future<List<EcoActivity>> getActivities({bool includeArchived = false}) async {
    final db = await database;
    final rows = await db.query(
      'eco_activities',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'title ASC',
    );
    return rows.map(EcoActivity.fromMap).toList();
  }

  Future<int> insertActivity(EcoActivity a) async {
    final db = await database;
    final map = a.toMap()..remove('id');
    map['created_at'] = DateTime.now().toIso8601String();
    return db.insert('eco_activities', map);
  }

  Future<void> updateActivity(EcoActivity a) async {
    final db = await database;
    final map = a.toMap()
      ..remove('id')
      ..remove('created_at');
    await db.update('eco_activities', map, where: 'id = ?', whereArgs: [a.id]);
  }

  /// Archives an activity - deliberately NOT a hard delete.
  ///
  /// `activity_completions.activity_id` is `ON DELETE CASCADE` and foreign
  /// keys are enforced, so a hard delete would wipe every tenant's completion
  /// history for this activity while leaving their `total_points` untouched -
  /// after which those points could never be explained or audited. Archiving
  /// hides the activity from tenants and keeps history intact and restorable.
  Future<void> deleteActivity(int id) async {
    final db = await database;
    await db.update('eco_activities', {'archived': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Un-archives a previously archived activity.
  Future<void> restoreActivity(int id) async {
    final db = await database;
    await db.update('eco_activities', {'archived': 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// Ids of every activity this tenant has completed at least once.
  Future<Set<int>> getCompletedActivityIds(int tenantId) async {
    final db = await database;
    final rows = await db.query('activity_completions',
        columns: ['activity_id'], where: 'tenant_id = ?', whereArgs: [tenantId]);
    return rows.map((r) => r['activity_id'] as int).toSet();
  }

  /// Total completions ever recorded for a tenant - used by the dashboard
  /// stat tiles so we never have to load every history row just to count.
  Future<int> getActivityCount(int tenantId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM activity_completions WHERE tenant_id = ?',
      [tenantId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Tenants created since [since]. Backs the dashboard "this week" summary,
  /// which the admin notification settings toggle on and off.
  Future<int> getNewTenantCountSince(DateTime since) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) FROM tenants t
      JOIN users u ON u.id = t.user_id
      WHERE u.username <> ? AND t.created_at >= ?
    ''', [kLedgerUsername, since.toIso8601String()]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Redemptions recorded since [since]. See [getNewTenantCountSince].
  Future<int> getRedemptionCountSince(DateTime since) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM reward_redemptions WHERE redeemed_at >= ?',
      [since.toIso8601String()],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Total redemptions ever recorded for a tenant.
  Future<int> getRedemptionCount(int tenantId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM reward_redemptions WHERE tenant_id = ?',
      [tenantId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Completes an activity for a tenant inside a single transaction:
  /// validates that the activity still exists and is not archived, re-reads
  /// its current point value, enforces the repeat rule, records the
  /// completion and updates the tenant's balance.
  ///
  /// Returns null on success, or a user-facing error message on failure.
  Future<String?> completeActivity(int tenantId, EcoActivity activity) async {
    final activityId = activity.id;
    if (activityId == null) return 'This activity is no longer available.';

    final db = await database;
    return db.transaction<String?>((txn) async {
      // Read the authoritative row inside the transaction rather than
      // trusting the copy the UI captured when the list was built: an admin
      // may have archived it, deleted it or changed its point value since.
      final rows = await txn.query('eco_activities',
          where: 'id = ? AND archived = 0', whereArgs: [activityId], limit: 1);
      if (rows.isEmpty) {
        return 'This activity is no longer available.';
      }
      final fresh = EcoActivity.fromMap(rows.first);

      if (!fresh.repeatable) {
        final existing = await txn.query('activity_completions',
            where: 'tenant_id = ? AND activity_id = ?',
            whereArgs: [tenantId, activityId],
            limit: 1);
        if (existing.isNotEmpty) {
          return 'You already completed this one-time activity.';
        }
      }

      await txn.insert('activity_completions', {
        'tenant_id': tenantId,
        'activity_id': activityId,
        'points_awarded': fresh.points,
        'completed_at': DateTime.now().toIso8601String(),
      });
      await txn.rawUpdate(
        'UPDATE tenants SET total_points = total_points + ? WHERE id = ?',
        [fresh.points, tenantId],
      );
      return null;
    });
  }

  Future<List<ActivityCompletion>> getActivityHistory(int tenantId, {int? limit}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT c.*, a.title as activity_title FROM activity_completions c
      JOIN eco_activities a ON a.id = c.activity_id
      WHERE c.tenant_id = ?
      ORDER BY c.completed_at DESC
      ${limit != null ? 'LIMIT ?' : ''}
    ''', [tenantId, if (limit != null) limit]);
    return rows.map(ActivityCompletion.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // Rewards
  // ---------------------------------------------------------------------
  Future<List<Reward>> getRewards({
    bool activeOnly = false,
    bool includeArchived = false,
  }) async {
    final db = await database;
    final where = <String>[];
    if (activeOnly) where.add('active = 1');
    if (!includeArchived) where.add('archived = 0');
    final rows = await db.query(
      'rewards',
      where: where.isEmpty ? null : where.join(' AND '),
      orderBy: 'points_required ASC',
    );
    return rows.map(Reward.fromMap).toList();
  }

  Future<int> insertReward(Reward r) async {
    final db = await database;
    final map = r.toMap()..remove('id');
    map['created_at'] = DateTime.now().toIso8601String();
    return db.insert('rewards', map);
  }

  Future<void> updateReward(Reward r) async {
    final db = await database;
    final map = r.toMap()
      ..remove('id')
      ..remove('created_at');
    await db.update('rewards', map, where: 'id = ?', whereArgs: [r.id]);
  }

  /// Archives a reward - see [deleteActivity] for why this is not a hard
  /// delete (`reward_redemptions.reward_id` is also ON DELETE CASCADE).
  Future<void> deleteReward(int id) async {
    final db = await database;
    await db.update('rewards', {'archived': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Un-archives a previously archived reward.
  Future<void> restoreReward(int id) async {
    final db = await database;
    await db.update('rewards', {'archived': 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// Redeems a reward for a tenant inside a single transaction: re-reads the
  /// reward and the tenant's balance, enforces the points and stock rules,
  /// then debits the balance, decrements the stock and records the redemption.
  ///
  /// Returns null on success, or a user-facing error message on failure.
  Future<String?> redeemReward(int tenantId, Reward reward) async {
    final rewardId = reward.id;
    if (rewardId == null) return 'Reward no longer exists.';

    final db = await database;
    return db.transaction<String?>((txn) async {
      final tenantRows = await txn.query('tenants', where: 'id = ?', whereArgs: [tenantId]);
      if (tenantRows.isEmpty) return 'Tenant not found.';
      final currentPoints = tenantRows.first['total_points'] as int;

      final rewardRows = await txn.query('rewards',
          where: 'id = ? AND archived = 0', whereArgs: [rewardId]);
      if (rewardRows.isEmpty) return 'Reward no longer exists.';
      final freshReward = Reward.fromMap(rewardRows.first);

      if (!freshReward.active) return 'This reward is no longer available.';
      if (freshReward.stock == 0) return 'This reward is out of stock.';
      if (currentPoints < freshReward.pointsRequired) return 'Not enough Eco Points.';

      await txn.rawUpdate(
        'UPDATE tenants SET total_points = total_points - ? WHERE id = ?',
        [freshReward.pointsRequired, tenantId],
      );
      if (freshReward.stock > 0) {
        await txn.rawUpdate('UPDATE rewards SET stock = stock - 1 WHERE id = ?', [rewardId]);
      }
      await txn.insert('reward_redemptions', {
        'tenant_id': tenantId,
        'reward_id': rewardId,
        'points_spent': freshReward.pointsRequired,
        'status': 'completed',
        'redeemed_at': DateTime.now().toIso8601String(),
      });
      return null;
    });
  }

  Future<List<RewardRedemption>> getRedemptionHistory(int tenantId, {int? limit}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT rr.*, r.title as reward_title FROM reward_redemptions rr
      JOIN rewards r ON r.id = rr.reward_id
      WHERE rr.tenant_id = ?
      ORDER BY rr.redeemed_at DESC
      ${limit != null ? 'LIMIT ?' : ''}
    ''', [tenantId, if (limit != null) limit]);
    return rows.map(RewardRedemption.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------
  Future<void> sendNotification({
    required String title,
    required String message,
    required String sender,
    required List<int> tenantIds,
  }) async {
    if (tenantIds.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final notificationId = await txn.insert('notifications', {
        'title': title,
        'message': message,
        'sender': sender,
        'created_at': now,
      });
      // Batch the recipient rows so sending to hundreds of tenants is one
      // round trip instead of N.
      final batch = txn.batch();
      for (final tid in tenantIds) {
        batch.insert('notification_recipients', {
          'notification_id': notificationId,
          'tenant_id': tid,
          'is_read': 0,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// Tenant ids that can actually receive a notification.
  ///
  /// The hidden ledger tenant is always excluded.
  Future<List<int>> getAllTenantIds({bool activeOnly = false}) async {
    final db = await database;
    final where = <String>['u.username <> ?'];
    final args = <dynamic>[kLedgerUsername];
    if (activeOnly) where.add("t.status = 'active'");
    final rows = await db.rawQuery('''
      SELECT t.id FROM tenants t
      JOIN users u ON u.id = t.user_id
      WHERE ${where.join(' AND ')}
    ''', args);
    return rows.map((r) => r['id'] as int).toList();
  }

  Future<List<AppNotification>> getNotificationsForTenant(int tenantId, {int? limit}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT n.*, nr.id as recipient_row_id, nr.is_read FROM notifications n
      JOIN notification_recipients nr ON nr.notification_id = n.id
      WHERE nr.tenant_id = ?
      ORDER BY n.created_at DESC
      ${limit != null ? 'LIMIT ?' : ''}
    ''', [tenantId, if (limit != null) limit]);
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<int> getUnreadCount(int tenantId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as c FROM notification_recipients
      WHERE tenant_id = ? AND is_read = 0
    ''', [tenantId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markNotificationRead(int recipientRowId) async {
    final db = await database;
    await db.update(
      'notification_recipients',
      {'is_read': 1, 'read_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [recipientRowId],
    );
  }

  Future<void> markAllNotificationsRead(int tenantId) async {
    final db = await database;
    await db.update(
      'notification_recipients',
      {'is_read': 1, 'read_at': DateTime.now().toIso8601String()},
      where: 'tenant_id = ? AND is_read = 0',
      whereArgs: [tenantId],
    );
  }

  Future<void> deleteNotificationForTenant(int recipientRowId) async {
    final db = await database;
    await db.delete('notification_recipients', where: 'id = ?', whereArgs: [recipientRowId]);
  }

  Future<List<Map<String, dynamic>>> getRecentNotificationsAdmin({int limit = 5}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT n.*, COUNT(nr.id) as recipient_count FROM notifications n
      LEFT JOIN notification_recipients nr ON nr.notification_id = n.id
      GROUP BY n.id
      ORDER BY n.created_at DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getAllNotificationsAdmin() async {
    final db = await database;
    return db.rawQuery('''
      SELECT n.*, COUNT(nr.id) as recipient_count,
        SUM(CASE WHEN nr.is_read = 1 THEN 1 ELSE 0 END) as read_count
      FROM notifications n
      LEFT JOIN notification_recipients nr ON nr.notification_id = n.id
      GROUP BY n.id
      ORDER BY n.created_at DESC
    ''');
  }

  // ---------------------------------------------------------------------
  // Environmental quotes
  // ---------------------------------------------------------------------
  Future<List<EnvironmentalQuote>> getQuotes() async {
    final db = await database;
    final rows = await db.query('environmental_quotes', orderBy: 'id ASC');
    return rows.map(EnvironmentalQuote.fromMap).toList();
  }

  Future<int> insertQuote(EnvironmentalQuote q) async {
    final db = await database;
    return db.insert('environmental_quotes', {
      'quote_text': q.quoteText,
      'author': q.author,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateQuote(EnvironmentalQuote q) async {
    final db = await database;
    await db.update('environmental_quotes', {'quote_text': q.quoteText, 'author': q.author},
        where: 'id = ?', whereArgs: [q.id]);
  }

  Future<void> deleteQuote(int id) async {
    final db = await database;
    await db.delete('environmental_quotes', where: 'id = ?', whereArgs: [id]);
  }

  /// Deterministically picks the same quote for the whole calendar day and
  /// a different one the next day, based on the day-of-year.
  Future<EnvironmentalQuote?> getQuoteOfTheDay() async {
    final quotes = await getQuotes();
    if (quotes.isEmpty) return null;
    final dayOfYear = DateFormatHelper.dayOfYear(DateTime.now());
    final index = dayOfYear % quotes.length;
    return quotes[index];
  }

  // ---------------------------------------------------------------------
  // App settings (admin preferences)
  // ---------------------------------------------------------------------
  Future<Map<String, String>> getSettings() async {
    final db = await database;
    final rows = await db.query('app_settings');
    return {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------
  // Dashboard stats
  // ---------------------------------------------------------------------
  Future<Map<String, int>> getAdminStats() async {
    final db = await database;

    // Tenant counts exclude the hidden ledger row.
    final totalTenants = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*) FROM tenants t
          JOIN users u ON u.id = t.user_id
          WHERE u.username <> ?
        ''', [kLedgerUsername])) ??
        0;

    final activeTenants = Sqflite.firstIntValue(await db.rawQuery('''
          SELECT COUNT(*) FROM tenants t
          JOIN users u ON u.id = t.user_id
          WHERE u.username <> ? AND t.status = 'active'
        ''', [kLedgerUsername])) ??
        0;

    // Deliberately INCLUDES the ledger row: the ledger holds the net points
    // of tenants that have since been deleted, which is what makes this a
    // stable all-time total rather than a number that drops on every delete.
    final totalPoints = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COALESCE(SUM(total_points),0) FROM tenants')) ??
        0;

    final rewardsRedeemed = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM reward_redemptions')) ??
        0;

    return {
      'totalTenants': totalTenants,
      'activeTenants': activeTenants,
      'totalPoints': totalPoints,
      'rewardsRedeemed': rewardsRedeemed,
    };
  }

  Future<List<Map<String, dynamic>>> getRecentActivityFeed({int limit = 6}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT t.name as tenant_name, a.title as activity_title, c.points_awarded, c.completed_at
      FROM activity_completions c
      JOIN tenants t ON t.id = c.tenant_id
      JOIN eco_activities a ON a.id = c.activity_id
      WHERE t.name <> ?
      ORDER BY c.completed_at DESC
      LIMIT ?
    ''', [kLedgerTenantName, limit]);
  }
}

/// Small date helper kept local to avoid pulling intl for one calculation.
/// Uses UTC so it is not affected by daylight-saving transitions.
class DateFormatHelper {
  static int dayOfYear(DateTime date) {
    final start = DateTime.utc(date.year, 1, 1);
    final d = DateTime.utc(date.year, date.month, date.day);
    return d.difference(start).inDays + 1;
  }
}