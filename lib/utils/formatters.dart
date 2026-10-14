/// Date and name formatting helpers.
///
/// The date helpers were copy-pasted into three different screens before this
/// file existed:
///   * admin_home_tab.dart
///   * tenant_notifications_screen.dart   (relative variant)
///   * tenant_rewards_screen.dart         (absolute variant)
///
/// The name helpers were added later for the same reason: two screens did
/// `name.split(' ').first` inline, which renders "Welcome back, " with an
/// empty gap when the name is blank, and four more re-implemented the
/// avatar-initial fallback by hand.
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

/// The first word of [fullName], for "Welcome back, Maria".
///
/// Returns [fallback] when the name is empty or only whitespace. Neither
/// `admins.name` nor `tenants.name` carries a non-empty CHECK constraint in the
/// schema, so a blank name is reachable and `split(' ').first` on it used to
/// produce "Welcome back, " with a dangling gap.
///
/// Splits on any run of whitespace, so a name with a double space or a tab
/// still yields a single word.
String firstName(String fullName, {String fallback = 'there'}) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed.split(RegExp(r'\s+')).first;
}

/// A single uppercase initial for an avatar, or '?' when [fullName] is blank.
String nameInitial(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed[0].toUpperCase();
}
