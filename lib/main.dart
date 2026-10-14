import 'package:flutter/material.dart';

import 'db/database_helper.dart';
import 'screens/admin_setup_screen.dart';
import 'screens/login_screen.dart';
import 'utils/theme.dart';

/// EcoTrack entry point.
///
/// Startup order matters now that EcoTrack runs on six platforms:
///
///   1. `DatabaseHelper.initialize()` installs the right SQLite factory
///      (native plugin on mobile/macOS, Dart FFI on Windows/Linux, sqlite3
///      wasm on web). Without it the first query throws on desktop and web.
///   2. Reference content is seeded on first run, before `runApp`, so the
///      very first frame already knows whether an admin account exists and
///      can go straight to the right screen instead of showing a splash.
///
/// A failure at this point used to leave the app on a permanent blank screen
/// with no explanation, so it is now surfaced to the user.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await DatabaseHelper.initialize();
    final hasAdmin = await DatabaseHelper.instance.hasAnyAdmin();
    runApp(EcoTrackApp(hasAdmin: hasAdmin));
  } catch (error, stackTrace) {
    debugPrint('EcoTrack failed to start: $error');
    debugPrint('$stackTrace');
    runApp(EcoTrackStartupErrorApp(error: error));
  }
}

class EcoTrackApp extends StatelessWidget {
  final bool hasAdmin;
  const EcoTrackApp({super.key, required this.hasAdmin});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: hasAdmin ? const LoginScreen() : const AdminSetupScreen(),
    );
  }
}

/// Shown when the database could not be opened at all.
///
/// The common real-world causes are a web build missing the sqlite3 wasm
/// assets (`dart run sqflite_common_ffi_web:setup`) or a failed migration.
class EcoTrackStartupErrorApp extends StatelessWidget {
  final Object error;
  const EcoTrackStartupErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.storage_outlined,
                        size: 56, color: AppColors.danger),
                    const SizedBox(height: 16),
                    const Text(
                      'EcoTrack could not open its database',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The local database failed to start, so no data can be '
                      'read or saved. On web this usually means the sqlite3 '
                      'assets are missing; on desktop it usually means the '
                      'SQLite library is not installed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        // textTintAlpha, not a bare 0.08: the error text inside this box is
              // painted in AppColors.danger on a danger tint, which is exactly
              // the case the constant encodes (4.96:1).
              color: AppColors.danger.withValues(alpha: AppColors.textTintAlpha),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        '$error',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.danger,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
