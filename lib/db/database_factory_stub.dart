// Platform dispatch stub.
//
// This file is only compiled when neither `dart.library.io` nor
// `dart.library.js_interop` is available, which does not happen for any
// platform Flutter actually targets. It exists so the conditional import
// in database_helper.dart type-checks.
//

/// Thrown when EcoTrack is compiled for a platform with no SQLite backend.
class UnsupportedPlatformError extends UnsupportedError {
  UnsupportedPlatformError(super.message);
}

Never _unsupported() {
  throw UnsupportedPlatformError(
    'EcoTrack has no SQLite backend for this platform. '
    'Supported: Android, iOS, macOS, Windows, Linux and Web.',
  );
}

/// Installs the platform SQLite factory. See database_factory_io.dart.
Future<void> initDatabaseFactory() async => _unsupported();

/// Absolute/virtual path of the EcoTrack database. See database_factory_io.dart.
Future<String> databaseFilePath() async => _unsupported();