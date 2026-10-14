// Web SQLite setup (sqlite3 compiled to WebAssembly, persisted in IndexedDB).
//
// This file is used when dart.library.js_interop is available.
//
// ONE-TIME SETUP - the wasm binary and the shared worker are not bundled by
// pub, so they must be generated into the `web/` folder once:
//
//     dart run sqflite_common_ffi_web:setup
//
// That writes `web/sqlite3.wasm` and `web/sqflite_sw.js`. Without them the
// web build opens the database and immediately fails to load SQLite.
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart'
    show databaseFactoryFfiWeb;

/// Swaps the default factory for the wasm-backed web implementation.
///
/// Must be awaited once, before [DatabaseHelper] opens the database.
Future<void> initDatabaseFactory() async {
  databaseFactory = databaseFactoryFfiWeb;
}

/// Virtual path inside the wasm filesystem.
///
/// On web the database lives in a single in-memory image that is persisted to
/// IndexedDB, so there is no meaningful directory to join against - the web
/// factory's `getDatabasesPath()` is not a real filesystem location. A plain
/// virtual filename is the documented approach.
Future<String> databaseFilePath() async => 'ecotrack.db';
