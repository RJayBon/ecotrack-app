import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

/// Salted password hashing for EcoTrack.
///
/// Two record formats are understood:
///
/// **Current - `pbkdf2$sha256$<iterations>$<saltB64>$<hashB64>`**
/// PBKDF2-HMAC-SHA256 with a per-user random salt, stored in the
/// `password_hash` column. The salt is *also* stored in the legacy `salt`
/// column so that old and new code can both read the row.
///
/// **Legacy v1 - `<hex sha256>` + separate `salt` column**
/// The original scheme: a single SHA-256 pass over `"<salt>:<password>"`.
/// A single pass is not a password KDF - consumer GPUs test billions of
/// candidates per second - so it is no longer used for *new* passwords, but
/// it is still *accepted* so existing installs keep working. On the first
/// successful login the record is transparently rewritten as PBKDF2
/// (see `DatabaseHelper.authenticate`), so no user has to do anything and
/// no password is ever lost.
///
/// [iterations] is deliberately modest. `package:crypto` is pure Dart, and
/// each PBKDF2 round costs ~4 SHA-256 compressions, so login latency is
/// roughly linear in this number and noticeably slower on low-end phones.
/// 10,000 rounds is ~10,000x more work per guess than the old scheme while
/// staying well under a second on the devices this app targets. If you ever
/// move hashing to a native platform channel, raise it.
///
/// **Always call [hashAsync] / [verifyAsync] from app code.** The plain
/// [hash] and [verify] are synchronous and therefore block whatever thread
/// calls them - see the note above those wrappers.
class PasswordHasher {
  const PasswordHasher._();

  static const String _prefix = 'pbkdf2';
  static const String _algorithm = 'sha256';
  static const int iterations = 10000;

  static const int _saltBytes = 16;
  static const int _keyBytes = 32;
  static const int _sha256BlockBytes = 32;

  static final Random _random = Random.secure();

  /// A fresh 16-byte salt, base64url encoded. No `=` padding, no `$`.
  static String generateSalt() {
    final bytes = Uint8List(_saltBytes);
    for (var i = 0; i < _saltBytes; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Url.encode(bytes);
  }

  /// Builds a complete, self-describing password record for a new password.
  ///
  /// Synchronous - use [hashAsync] from anything that runs on the UI thread.
  static String hash(String password, String saltBase64) {
    final salt = _decodeBase64(saltBase64);
    final derived = _pbkdf2(
      utf8.encode(password),
      salt,
      iterations,
    );
    return '$_prefix\$$_algorithm\$$iterations'
        '\$$saltBase64\$${base64Url.encode(derived)}';
  }

  /// Returns true if [password] matches [stored].
  ///
  /// [legacySalt] is the value of the `salt` column, used only when [stored]
  /// holds a legacy v1 hash.
  ///
  /// Synchronous - use [verifyAsync] from anything that runs on the UI thread.
  static bool verify({
    required String password,
    required String stored,
    required String legacySalt,
  }) {
    if (stored.startsWith('$_prefix\$')) {
      final parts = stored.split(r'$');
      if (parts.length != 5) return false;

      final rounds = int.tryParse(parts[2]);
      if (rounds == null || rounds <= 0) return false;

      final salt = _tryDecodeBase64(parts[3]);
      final expected = _tryDecodeBase64(parts[4]);
      if (salt == null || expected == null) return false;

      final actual = _pbkdf2(utf8.encode(password), salt, rounds);
      return _constantTimeEquals(actual, expected);
    }

    // Legacy v1: sha256("<salt>:<password>") rendered as lowercase hex.
    final legacy = sha256.convert(utf8.encode('$legacySalt:$password')).toString();
    return _constantTimeEquals(utf8.encode(legacy), utf8.encode(stored));
  }

  /// True when [stored] is a legacy record that should be re-hashed after a
  /// successful login.
  static bool needsRehash(String stored) => !stored.startsWith('$_prefix\$');

  // -------------------------------------------------------------------
  // UI-thread-safe wrappers
  // -------------------------------------------------------------------
  //
  // PBKDF2 is *supposed* to be slow, and `hash` / `verify` above compute it
  // synchronously. Awaiting that work directly from a widget blocks the
  // thread that draws the UI, so on a slower phone - and especially in a
  // debug build, which is many times slower than the released app - Android
  // eventually shows its "EcoTrack isn't responding / Wait / Close app"
  // dialog. That is the freeze this wrapper pair exists to remove.
  //
  // `compute` hands the same inputs to a throwaway background isolate and
  // returns the result, so the frame loop keeps running and the login
  // button's spinner keeps spinning while the key is derived. The stored
  // record format is unchanged, so hashes created before this change still
  // verify.
  //
  // On Flutter web there are no isolates; `compute` runs the function
  // inline, which is simply the pre-existing behaviour.

  /// [hash], but off the UI thread.
  static Future<String> hashAsync(String password, String saltBase64) =>
      compute(_hashEntryPoint, <String>[password, saltBase64]);

  /// [verify], but off the UI thread.
  static Future<bool> verifyAsync({
    required String password,
    required String stored,
    required String legacySalt,
  }) =>
      compute(_verifyEntryPoint, <String>[password, stored, legacySalt]);

  // Top-level entry points for `compute` - it cannot send closures or
  // `this`, so the arguments travel as a plain list of strings.
  static String _hashEntryPoint(List<String> args) => hash(args[0], args[1]);

  static bool _verifyEntryPoint(List<String> args) =>
      verify(password: args[0], stored: args[1], legacySalt: args[2]);

  // -------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------

  /// PBKDF2-HMAC-SHA256 (RFC 8018 section 5.2), sized to [_keyBytes].
  static List<int> _pbkdf2(List<int> password, List<int> salt, int rounds) {
    const int hLen = _sha256BlockBytes;
    const int blockCount = (_keyBytes + hLen - 1) ~/ hLen;
    final prf = Hmac(sha256, password);
    final out = Uint8List(blockCount * hLen);
    final blockInput = Uint8List(salt.length + 4);

    for (var block = 1; block <= blockCount; block++) {
      // U1 = PRF(password, salt || INT_32_BE(block))
      blockInput.setRange(0, salt.length, salt);
      blockInput[salt.length] = (block >> 24) & 0xff;
      blockInput[salt.length + 1] = (block >> 16) & 0xff;
      blockInput[salt.length + 2] = (block >> 8) & 0xff;
      blockInput[salt.length + 3] = block & 0xff;

      var u = prf.convert(blockInput).bytes;
      final acc = Uint8List.fromList(u);

      // T = U1 xor U2 xor ... xor Uc
      for (var i = 1; i < rounds; i++) {
        u = prf.convert(u).bytes;
        for (var j = 0; j < hLen; j++) {
          acc[j] ^= u[j];
        }
      }
      out.setRange((block - 1) * hLen, block * hLen, acc);
    }

    return out.sublist(0, _keyBytes);
  }

  static List<int> _decodeBase64(String value) => base64Url.decode(value);

  static List<int>? _tryDecodeBase64(String value) {
    try {
      return base64Url.decode(value);
    } on FormatException {
      return null;
    }
  }

  /// Length-independent, early-exit-free comparison so verification time does
  /// not leak information about how many leading bytes were correct.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}