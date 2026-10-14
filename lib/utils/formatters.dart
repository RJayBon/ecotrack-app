/// Date formatting helpers.
///
/// These three implementations were copy-pasted into three different screens
/// before this file existed:
///   * admin_home_tab.dart
///   * tenant_notifications_screen.dart   (relative variant)
///   * tenant_rewards_screen.dart         (absolute variant)
library;

/// "Just now", "5m ago", "3h ago", "2d ago", then "10/13/2026".
///
/// Returns [iso] unchanged if it cannot be parsed, so a malformed timestamp
/// never blanks out a row.
String formatRelativeDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final diff = DateTime.now().difference(d);
  if (diff.isNegative) return 'Just now';
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatShortDate(iso);
}

/// "10/13/2026".
///
/// Returns [iso] unchanged if it cannot be parsed.
String formatShortDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.month}/${d.day}/${d.year}';
}

/// "Oct 13, 2026 at 4:05 PM" - used where a full timestamp is genuinely
/// useful (redemption history, activity history).
String formatFullDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final meridiem = d.hour < 12 ? 'AM' : 'PM';
  return '${months[d.month - 1]} ${d.day}, ${d.year} at $hour12:$minute $meridiem';
}
