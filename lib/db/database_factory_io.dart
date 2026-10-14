// Native (Android / iOS / macOS) and desktop (Windows / Linux) SQLite setup.
//
// This file is used whenever dart:io is available.
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show databaseFactory, getDatabasesPath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

/// Installs the correct sqflite [databaseFactory] for the current platform.
///
/// * Android / iOS / macOS - `sqflite` ships an native implementation, so the
///   default factory is already correct and nothing needs to change.
/// * Windows / Linux - there is no native sqflite plugin, so we swap in the
///   Dart-FFI implementation from `sqflite_common_ffi`, which loads (and on
///   Windows bundles) `sqlite3` itself.
///
/// Must be awaited once, before [DatabaseHelper] opens the database.
Future<void> initDatabaseFactory() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
    case TargetPlatform.macOS:
      // Native plugin - nothing to do.
      return;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      return;
  }
}

/// Full path to the on-disk database file for the active factory.
Future<String> databaseFilePath() async {
  final dir = await getDatabasesPath();
  return p.join(dir, 'ecotrack.db');
}
