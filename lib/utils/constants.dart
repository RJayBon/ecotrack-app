/// Shared constants that more than one layer needs.
///
/// This file exists to break two bad dependencies:
///
///  * `admin_guide_form_screen.dart` and `admin_guides_screen.dart` used to
///    import each other (a real import cycle) purely to share
///    [kWasteCategories].
///  * `tenant_learn_screen.dart` imported the *admin* guides screen just to
///    read the same constant, which dragged an entire admin screen into the
///    tenant build.
library;

/// The five waste categories EcoTrack recognises.
///
/// Single source of truth for: the admin guide form chips, the tenant "Learn"
/// filter chips, and the category values used to seed `waste_guides`.
/// Anything added here shows up in all three places automatically.
const List<String> kWasteCategories = <String>[
  'Biodegradable',
  'Recyclable',
  'Residual',
  'Hazardous',
  'Electronic Waste',
];

/// Sentinel used by the admin theme/notification settings.
const String kSettingNotifyNewTenant = 'notify_new_tenant';
const String kSettingNotifyRedemption = 'notify_reward_redemption';
