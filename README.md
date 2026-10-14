# EcoTrack

Waste management, recycling education and eco-habit tracking for residential
communities. Admins manage tenants, waste guides, eco activities, rewards and
broadcast notifications; tenants earn Eco Points by completing activities and
spend them on rewards.

Everything is stored locally in **SQLite** — there is no server.

---

## Requirements

| | |
| --- | --- |
| Flutter | **>= 3.27.0** (required — see the note in `pubspec.yaml`) |
| Dart | >= 3.6.0 |

The Flutter floor is not cosmetic. The code uses `Color.withValues()`,
`CardThemeData` and `DialogThemeData`, all introduced in **Flutter 3.27**.
Without the constraint, `flutter pub get` succeeds on an older SDK and the
build then fails with confusing widget-level errors.

```bash
flutter pub get
flutter run