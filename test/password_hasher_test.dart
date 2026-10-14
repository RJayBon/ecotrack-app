import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ecotrack/db/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

/// The original v1 scheme, reproduced here so the migration path can be
/// tested exactly as it shipped.
String legacyHash(String password, String salt) =>
    sha256.convert(utf8.encode('$salt:$password')).toString();

void main() {
  group('PasswordHasher', () {
    test('verifies a password it just hashed', () {
      final salt = PasswordHasher.generateSalt();
      final stored = PasswordHasher.hash('correct horse battery staple', salt);

      expect(
        PasswordHasher.verify(
          password: 'correct horse battery staple',
          stored: stored,
          legacySalt: salt,
        ),
        isTrue,
      );
    });

    test('rejects the wrong password', () {
      final salt = PasswordHasher.generateSalt();
      final stored = PasswordHasher.hash('right-password', salt);

      expect(
        PasswordHasher.verify(
          password: 'wrong-password',
          stored: stored,
          legacySalt: salt,
        ),
        isFalse,
      );
    });

    test('is salted: the same password produces different records', () {
      final a = PasswordHasher.hash('same', PasswordHasher.generateSalt());
      final b = PasswordHasher.hash('same', PasswordHasher.generateSalt());
      expect(a, isNot(equals(b)));
    });

    test('record is self-describing', () {
      final stored = PasswordHasher.hash('x', PasswordHasher.generateSalt());
      final parts = stored.split(r'$');
      expect(parts.length, 5);
      expect(parts[0], 'pbkdf2');
      expect(parts[1], 'sha256');
      expect(int.parse(parts[2]), PasswordHasher.iterations);
    });

    test('changed credentials do not verify against an old record', () {
      final salt = PasswordHasher.generateSalt();
      final stored = PasswordHasher.hash('old', salt);
      expect(
        PasswordHasher.verify(password: 'new', stored: stored, legacySalt: salt),
        isFalse,
      );
    });

    group('legacy v1 compatibility', () {
      test('still accepts a single-SHA-256 record', () {
        const salt = 'bGVnYWN5c2FsdA==';
        final stored = legacyHash('my-old-password', salt);

        expect(
          PasswordHasher.verify(
            password: 'my-old-password',
            stored: stored,
            legacySalt: salt,
          ),
          isTrue,
        );
      });

      test('legacy records are flagged for rehash, new ones are not', () {
        const salt = 'c2FsdA==';
        expect(PasswordHasher.needsRehash(legacyHash('pw', salt)), isTrue);
        expect(
          PasswordHasher.needsRehash(PasswordHasher.hash('pw', salt)),
          isFalse,
        );
      });

      test('an upgraded password still verifies against the new record', () {
        const salt = 'c2FsdA==';
        const password = 'my-old-password';

        // This is what DatabaseHelper.authenticate does on first login.
        final upgraded = PasswordHasher.hash(password, PasswordHasher.generateSalt());
        expect(PasswordHasher.needsRehash(upgraded), isFalse);
        expect(
          PasswordHasher.verify(
            password: password,
            stored: upgraded,
            legacySalt: salt,
          ),
          isTrue,
        );
      });
    });

    group('malformed records fail closed', () {
      test('unknown scheme with wrong number of parts', () {
        expect(
          PasswordHasher.verify(
            password: 'x',
            stored: r'pbkdf2$sha256$1000',
            legacySalt: 'salt',
          ),
          isFalse,
        );
      });

      test('non-numeric iteration count', () {
        expect(
          PasswordHasher.verify(
            password: 'x',
            stored: r'pbkdf2$sha256$abc$c2FsdA==$aGFzaA==',
            legacySalt: 'salt',
          ),
          isFalse,
        );
      });

      test('invalid base64 payload', () {
        expect(
          PasswordHasher.verify(
            password: 'x',
            stored: r'pbkdf2$sha256$1000$not*base64$also*invalid',
            legacySalt: 'salt',
          ),
          isFalse,
        );
      });

      test('password that happens to equal the legacy hash does not verify '
          'against a pbkdf2 record', () {
        final salt = PasswordHasher.generateSalt();
        final stored = PasswordHasher.hash('secret', salt);
        expect(
          PasswordHasher.verify(
            password: stored,
            stored: stored,
            legacySalt: salt,
          ),
          isFalse,
        );
      });
    });
  });
}
