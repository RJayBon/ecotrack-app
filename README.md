# EcoTrack

Waste management, recycling education and eco-habit tracking for residential
communities. Admins manage tenants, waste guides, eco activities, rewards and
broadcast notifications; tenants earn **Eco Points** by completing activities
and spend them on rewards.

Everything is stored locally in **SQLite** — there is no server, no network
layer and no accounts service.

---

## Contents

- [Requirements](#requirements)
- [First-time setup](#first-time-setup)
- [Running the app](#running-the-app)
- [Running on the web](#running-on-the-web)
- [Desktop prerequisites](#desktop-prerequisites)
- [App icon](#app-icon)
- [Tests](#tests)
- [First admin account](#first-admin-account)
- [Project structure](#project-structure)
- [How it works](#how-it-works)
- [Accessibility](#accessibility)
- [Known limitations](#known-limitations)

---

## Requirements

| | |
| --- | --- |
| Flutter | **>= 3.44.0** |
| Dart | **>= 3.12.0** |

These are the floors declared in `pubspec.yaml`, and they match the `sdks:`
section of the committed `pubspec.lock`. That section is the intersection of
the SDK constraints of every package the lock resolved to, so it is the minimum
SDK that can reproduce this dependency set at all.

The floor is also load-bearing for the code itself: the app calls
`Color.withValues()` (26 call sites) and `DialogThemeData`, neither of which
exists on older SDKs.

Check yours with:

```bash
flutter --version
```

If you are below the floor, either upgrade Flutter or — if you must support an
older SDK — delete `pubspec.lock`, lower the floors in `pubspec.yaml`, re-run
`flutter pub get`, and commit the newly resolved lock.

---

## First-time setup

**This checkout contains no platform folders.** There is no `android/`, `ios/`,
`web/`, `windows/`, `linux/` or `macos/` directory, and no `.metadata` file —
only the Dart sources, tests, assets and configuration are version controlled.
So `flutter run` will fail until you generate the platform scaffolding once:

```bash
flutter pub get

# Generate every platform folder this app supports. Run from the repo root;
# the trailing "." is the project path.
flutter create --platforms=android,ios,web,windows,linux,macos .
```

Notes on that command:

- It is **additive**. `flutter create` on an existing project writes only the
  missing platform folders and never touches `lib/`, `test/`, `pubspec.yaml` or
  `assets/`.
- It also writes `.metadata`, which records the Flutter version the project was
  created with. Commit it.
- Re-run it later to add a platform you skipped (for example
  `flutter create --platforms=web .`).
- The generated `android/` and `ios/` folders default to the organisation
  `com.example`. Change the application id / bundle id before you ship:
  `com.example.ecotrack` is not publishable.

Add `.gitignore` entries are already in place for the generated build output.

---

## Running the app

```bash
flutter pub get
flutter run                      # default device
flutter run -d chrome            # web (see the web section first)
flutter run -d windows           # or macos / linux
```

To list available devices:

```bash
flutter devices
```

Release builds:

```bash
flutter build apk --release      # Android
flutter build ios --release      # iOS (macOS host, Xcode installed)
flutter build web --release
flutter build windows --release
```

---

## Running on the web

Web SQLite runs on `sqlite3` compiled to WebAssembly and persists to IndexedDB.
The wasm binary and its shared worker are **not** distributed by pub, so they
must be generated into `web/` once, after `flutter create` has produced that
folder:

```bash
dart run sqflite_common_ffi_web:setup
```

That writes two files:

| File | Purpose |
| --- | --- |
| `web/sqlite3.wasm` | the SQLite engine, compiled to WebAssembly |
| `web/sqflite_sw.js` | the shared worker that runs it |

Both are listed in `.gitignore`: they are large, machine-generated, and pinned
to the resolved `sqflite_common_ffi_web` version, so each developer regenerates
them. If you skip this step the app opens the database and immediately fails —
`main.dart` catches that and renders a full-screen
"EcoTrack could not open its database" message rather than a blank screen.

Re-run the setup command after upgrading `sqflite_common_ffi_web`.

---

## Desktop prerequisites

Windows and Linux have no native `sqflite` plugin, so the app swaps in the
Dart-FFI implementation from `sqflite_common_ffi` (see
`lib/db/database_factory_io.dart`). That needs the SQLite shared library at
runtime:

- **Windows** — nothing to do. `sqflite_common_ffi` bundles `sqlite3.dll`.
- **Linux** — install it: `sudo apt install libsqlite3-dev` (Debian/Ubuntu) or
  `sudo dnf install sqlite-devel` (Fedora).
- **macOS** — nothing to do; the native `sqflite` plugin is used.

---

## App icon

One 1024×1024 source PNG lives at `assets/icon/app_icon.png`. Every platform
size is generated from it by `flutter_launcher_icons`, configured in the
`flutter_launcher_icons:` block at the bottom of `pubspec.yaml`:

```bash
# after `flutter create` has produced the platform folders
dart run flutter_launcher_icons
flutter clean && flutter run
```

Icons are baked in at build time — **hot reload does not pick them up**, hence
the `flutter clean`.

The PNG is deliberately *not* declared in a `flutter: assets:` block, because
nothing in the app renders it with `Image.asset`. `flutter_launcher_icons`
reads `image_path` from the filesystem at generation time, not from the asset
bundle, so declaring it would only copy a megabyte-scale image into every build
artefact. If you do want to render it in-app, re-add the `assets:` block (the
exact snippet is in a comment in `pubspec.yaml`).

Two optional extras are configured but commented out in `pubspec.yaml`:

- **Android 8+ adaptive icon** — add a second PNG with the glyph inside the
  centre 66% safe zone, then uncomment `adaptive_icon_background` /
  `adaptive_icon_foreground`.
- **Web favicon and PWA icons** — uncomment the `web:` block.

iOS rejects icons containing an alpha channel; `remove_alpha_ios: true`
flattens transparency onto a solid backdrop instead of erroring out.

---

## Tests

```bash
flutter test
```

Three suites, 64 tests:

| File | Tests | Covers |
| --- | --- | --- |
| `test/database_helper_test.dart` | 51 | schema and seeding, the v1 → v2 migration, completing activities, redeeming rewards, **mid-session deactivation**, archive-preserves-history, tenant deletion, authentication, notifications, tenant queries, settings, quotes |
| `test/password_hasher_test.dart` | 12 | PBKDF2 round-trip, legacy v1 hash compatibility, malformed records failing closed |
| `test/admin_home_tab_test.dart` | 1 | regression test for the infinite-height layout crash that used to hit the dashboard right after admin sign-in |

The database tests run against a real SQLite file via `sqflite_common_ffi`, so
they need the desktop SQLite library described above (Windows and macOS need
nothing extra).

Run a single suite or test:

```bash
flutter test test/database_helper_test.dart
flutter test --plain-name 'redeeming rewards'
```

---

## First admin account

There are **no seeded or hard-coded credentials**. On a fresh database
`main.dart` calls `hasAnyAdmin()`; if it returns false the app routes straight
to `AdminSetupScreen`, where the first real administrator creates their own
name, email, username and password. Every later launch goes to `LoginScreen`.

Tenant accounts can only be created by an administrator, from
**Tenants → Add Tenant**, which generates the tenant's login at the same time.

---

## Project structure

```
lib/
  main.dart                     entry point, startup error screen
  admin_setup_screen.dart       first-run admin registration
  login_screen.dart             shared admin/tenant login
  db/
    database_helper.dart        schema, migrations, seeding, all queries
    password_hasher.dart        PBKDF2 hashing + legacy v1 verification
    database_factory_io.dart    native (mobile/macOS) + FFI (Windows/Linux)
    database_factory_web.dart   sqlite3 wasm factory
    database_factory_stub.dart  compile-time fallback for the conditional import
  models/
    models.dart                 Tenant, Admin, EcoActivity, Reward, WasteGuide,
                                ActivityCompletion, RewardRedemption,
                                EnvironmentalQuote, AppNotification,
                                WeeklySummary
  screens/
    admin/                      dashboard shell + tenants, guides, activities,
                                rewards, quotes, notifications, profile, tips
    tenant/                     home shell + learn, activities, rewards,
                                notifications, profile
  utils/
    theme.dart                  palette (with computed contrast ratios), theme
    constants.dart              settings keys and shared constants
    formatters.dart             dates, relative dates, firstName(), nameInitial()
    icon_map.dart               string icon keys -> IconData
  widgets/
    common_widgets.dart         EcoCard, StatTile, EcoPill, StatusBadge,
                                LabeledField, IconPicker, EmptyState, ErrorState,
                                SheetHandle, ChangePasswordSheet, dialogs,
                                snackbars
assets/
  icon/app_icon.png             launcher-icon source (see "App icon")
test/                           3 suites, 59 tests
```

---

## How it works

**Database.** `DatabaseHelper` is a singleton owning a single SQLite file at
schema version 2. `_createSchema` builds 12 tables, `_createIndexes` adds the
covering indexes (it runs on both create *and* upgrade, and every statement is
`IF NOT EXISTS`), and `_migrate` handles the v1 → v2 upgrade on devices that
already have data — adding the `archived` columns and the `app_settings` table
without touching existing rows.

**Platform swap.** `database_helper.dart` uses a conditional import
(`database_factory_stub.dart`, overridden by `database_factory_io.dart` when
`dart.library.io` exists and by `database_factory_web.dart` when
`dart.library.js_interop` exists) so one codebase runs on six platforms.
`DatabaseHelper.initialize()` must be awaited before the first query; `main()`
does that.

**Reference content.** On first run the database is seeded with 26 rows of
reference content — 5 waste guides, 6 eco activities, 5 rewards and 10
environmental quotes — so the app is never empty on a fresh install.

**Points arithmetic.** Earning and spending happen **in SQL, inside
transactions**, never in Dart. `completeActivity` re-reads the activity row
inside its transaction (so an admin editing the point value mid-session cannot
be raced), enforces the repeat rule, inserts the completion and updates the
balance atomically. `redeemReward` does the same for stock and balance. Both
also re-check the tenant's `status`, so deactivating an account takes effect
immediately rather than at the next login.

**Passwords.** PBKDF2-HMAC-SHA256, 10,000 iterations, a fresh 16-byte
`Random.secure()` salt per user, stored self-describing as
`pbkdf2$sha256$<iterations>$<salt>$<hash>`. Hashing runs on a background
isolate via `compute()` so it never blocks the UI. Verification is
constant-time. Legacy v1 hashes (a single SHA-256 pass) are still accepted and
transparently upgraded on the next successful login. Malformed records fail
closed.

**Archiving, not deleting.** Activities and rewards are archived rather than
deleted, so completion and redemption history — and the points already earned
or spent — stay auditable. Archived rows are hidden by default and can be
revealed and restored from the admin list's toolbar.

**The ledger tenant.** Deleting a tenant would orphan their completion history,
so `deleteTenant` reassigns those rows to a hidden bookkeeping tenant
identified by the `kLedgerUsername` / `kLedgerTenantName` sentinels. Every
tenant-facing query excludes it.

**SQL safety.** All queries use parameterised `whereArgs`. The two `LIKE`
searches additionally escape `%`, `_` and `\` and declare `ESCAPE '\'`, so a
tenant named `%` cannot become a wildcard.

---

## Accessibility

The palette in `lib/utils/theme.dart` carries **computed** WCAG 2.1 contrast
ratios for every token against the backdrop it is actually used on — not
estimates. Two constants encode the rules so a new screen cannot get them wrong
by guessing an alpha value:

| Constant | Value | Use for |
| --- | --- | --- |
| `AppColors.textTintAlpha` | `0.08` | a tint that sits behind **text**. Primary text on a primary tint at this alpha is 4.63:1 (AA). At 0.10 it drops to 4.49:1 and at 0.12 to 4.36:1 — both failures. |
| `AppColors.iconTintAlpha` | `0.12` | a **decorative** wash behind an icon, where only the 3:1 non-text threshold applies. |

Also relevant:

- `AppColors.disabledForeground` / `disabledBackground` replace the raw
  `Colors.grey.shade600`-on-`grey.shade300` (3.49:1) that the disabled Redeem
  button used. That label is the only thing distinguishing "you cannot afford
  this" from "out of stock", so it has to be legible: the tokens give 4.84:1.
- Archived rows are dimmed by **colour choice**, never by an `Opacity` wrapper.
  `Opacity(0.65)` composites the whole subtree and used to drop 12.5px body
  text to 2.67:1.
- The unread-notification badge uses `AppColors.danger` (5.62:1 for its white
  9px label) rather than `Colors.redAccent` (3.85:1).

---

## Known limitations

- **No dark theme.** `AppTheme.light()` is the only theme and
  `MaterialApp.darkTheme` is not set, so the app ignores the system dark-mode
  preference. Every colour token is a light-mode value.
- **Single-device data.** Everything is in one local SQLite file. There is no
  sync, backup or multi-device story, and uninstalling the app deletes the data.
- **No pagination on the admin lists.** Tenant, activity, reward, quote, guide
  and notification lists are read whole. The tenant-facing redemption history
  *is* paged (50 at a time with a "Load earlier redemptions" control).
- **No push notifications.** "Notifications" are in-app rows written to SQLite
  and read when the tenant opens the app.
- **Web storage is per-browser.** The IndexedDB-backed database is scoped to one
  browser profile on one device, and is cleared with the site's storage.
- **`flutter analyze` needs the SDK.** Static analysis, `dart format` and the
  test suite all require a local Flutter installation at or above the floor
  above; none of them can run in a Dart-only environment.

---

## Licence

Not specified. Add a `LICENSE` file before distributing.
