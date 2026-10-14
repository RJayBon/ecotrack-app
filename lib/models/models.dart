/// EcoTrack data models.
/// Every model mirrors a SQLite table and provides a `fromMap` factory used by
/// DatabaseHelper for persistence.
///
/// Only [WasteGuide], [EcoActivity] and [Reward] also carry a `toMap`, because
/// those are the only three rows DatabaseHelper writes from a whole model
/// (`insertGuide`/`updateGuide`, `insertActivity`/`updateActivity`,
/// `insertReward`/`updateReward`). Every other write builds its column map
/// inline so it can control exactly which columns are touched - `updateTenant`
/// must not write `total_points`, `createTenant` must not write `id`.
///
/// The six `toMap` helpers that had no caller were removed rather than kept as
/// "convenience": two of them were actively wrong. `AppNotification.toMap()`
/// dropped `isRead` and `recipientRowId`, and `Tenant.toMap()` dropped
/// `username`, so any future caller reaching for the obvious helper would have
/// written an incomplete row.
///
/// NOTE: the previous `AppUser` model was removed - it was never referenced
/// anywhere. Auth reads `users` rows as maps in DatabaseHelper because the
/// web/FFI code paths need the raw `salt` column, which the model dropped.
library models;

class Tenant {
  final int? id;
  final int userId;
  final String name;
  final String email;
  final String phone;
  final String unit;
  final String status; // 'active' | 'inactive'
  final int totalPoints;
  final String createdAt;
  final String username; // joined from users table (read-only convenience)

  Tenant({
    this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    required this.unit,
    required this.status,
    required this.totalPoints,
    required this.createdAt,
    this.username = '',
  });

  factory Tenant.fromMap(Map<String, dynamic> m) => Tenant(
        id: m['id'] as int?,
        userId: m['user_id'] as int,
        name: m['name'] as String,
        email: m['email'] as String,
        phone: m['phone'] as String,
        unit: m['unit'] as String,
        status: m['status'] as String,
        totalPoints: m['total_points'] as int,
        createdAt: m['created_at'] as String,
        username: (m['username'] as String?) ?? '',
      );

  Tenant copyWith({
    String? name,
    String? email,
    String? phone,
    String? unit,
    String? status,
    int? totalPoints,
  }) =>
      Tenant(
        id: id,
        userId: userId,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        unit: unit ?? this.unit,
        status: status ?? this.status,
        totalPoints: totalPoints ?? this.totalPoints,
        createdAt: createdAt,
        username: username,
      );
}

class Admin {
  final int? id;
  final int userId;
  final String name;
  final String email;
  final String createdAt;
  final String username;

  Admin({
    this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.createdAt,
    this.username = '',
  });

  factory Admin.fromMap(Map<String, dynamic> m) => Admin(
        id: m['id'] as int?,
        userId: m['user_id'] as int,
        name: m['name'] as String,
        email: m['email'] as String,
        createdAt: m['created_at'] as String,
        username: (m['username'] as String?) ?? '',
      );
}

class WasteGuide {
  final int? id;
  final String category; // Biodegradable, Recyclable, Residual, Hazardous, Electronic Waste
  final String title;
  final String description;
  final String examples;
  final String disposalMethod;
  final String recyclingTips;
  final String icon; // material icon name key
  final String createdAt;

  WasteGuide({
    this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.examples,
    required this.disposalMethod,
    required this.recyclingTips,
    required this.icon,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category,
        'title': title,
        'description': description,
        'examples': examples,
        'disposal_method': disposalMethod,
        'recycling_tips': recyclingTips,
        'icon': icon,
        'created_at': createdAt,
      };

  factory WasteGuide.fromMap(Map<String, dynamic> m) => WasteGuide(
        id: m['id'] as int?,
        category: m['category'] as String,
        title: m['title'] as String,
        description: m['description'] as String,
        examples: m['examples'] as String,
        disposalMethod: m['disposal_method'] as String,
        recyclingTips: m['recycling_tips'] as String,
        icon: m['icon'] as String,
        createdAt: m['created_at'] as String,
      );
}

class EcoActivity {
  final int? id;
  final String title;
  final String description;
  final int points;
  final bool repeatable;
  final String icon;
  final String category;

  /// Soft-delete flag. Archived activities stay in the database so that
  /// `activity_completions` rows (and the points they awarded) remain
  /// explainable, but they are hidden from tenants and from the admin list.
  final bool archived;
  final String createdAt;

  EcoActivity({
    this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.repeatable,
    required this.icon,
    required this.category,
    this.archived = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'points': points,
        'repeatable': repeatable ? 1 : 0,
        'icon': icon,
        'category': category,
        'archived': archived ? 1 : 0,
        'created_at': createdAt,
      };

  factory EcoActivity.fromMap(Map<String, dynamic> m) => EcoActivity(
        id: m['id'] as int?,
        title: m['title'] as String,
        description: m['description'] as String,
        points: m['points'] as int,
        repeatable: (m['repeatable'] as int) == 1,
        icon: m['icon'] as String,
        category: m['category'] as String,
        // Defaults to false if the column is absent, so a map built by hand
        // (or read before the v2 migration ran) still parses.
        archived: (m['archived'] as int?) == 1,
        createdAt: m['created_at'] as String,
      );

  EcoActivity copyWith({
    String? title,
    String? description,
    int? points,
    bool? repeatable,
    String? icon,
    String? category,
    bool? archived,
  }) =>
      EcoActivity(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        points: points ?? this.points,
        repeatable: repeatable ?? this.repeatable,
        icon: icon ?? this.icon,
        category: category ?? this.category,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );
}

class ActivityCompletion {
  final int? id;
  final int tenantId;
  final int activityId;
  final int pointsAwarded;
  final String completedAt;
  final String activityTitle; // joined convenience field

  ActivityCompletion({
    this.id,
    required this.tenantId,
    required this.activityId,
    required this.pointsAwarded,
    required this.completedAt,
    this.activityTitle = '',
  });

  factory ActivityCompletion.fromMap(Map<String, dynamic> m) =>
      ActivityCompletion(
        id: m['id'] as int?,
        tenantId: m['tenant_id'] as int,
        activityId: m['activity_id'] as int,
        pointsAwarded: m['points_awarded'] as int,
        completedAt: m['completed_at'] as String,
        activityTitle: (m['activity_title'] as String?) ?? '',
      );
}

class Reward {
  final int? id;
  final String title;
  final String description;
  final int pointsRequired;
  final int stock;
  final bool active;
  final String icon;

  /// Soft-delete flag - see [EcoActivity.archived]. Archiving a reward keeps
  /// `reward_redemptions` (and their point ledger) intact.
  final bool archived;
  final String createdAt;

  Reward({
    this.id,
    required this.title,
    required this.description,
    required this.pointsRequired,
    required this.stock,
    required this.active,
    required this.icon,
    this.archived = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'points_required': pointsRequired,
        'stock': stock,
        'active': active ? 1 : 0,
        'icon': icon,
        'archived': archived ? 1 : 0,
        'created_at': createdAt,
      };

  factory Reward.fromMap(Map<String, dynamic> m) => Reward(
        id: m['id'] as int?,
        title: m['title'] as String,
        description: m['description'] as String,
        pointsRequired: m['points_required'] as int,
        stock: m['stock'] as int,
        active: (m['active'] as int) == 1,
        icon: m['icon'] as String,
        archived: (m['archived'] as int?) == 1,
        createdAt: m['created_at'] as String,
      );

  Reward copyWith({
    String? title,
    String? description,
    int? pointsRequired,
    int? stock,
    bool? active,
    String? icon,
    bool? archived,
  }) =>
      Reward(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        pointsRequired: pointsRequired ?? this.pointsRequired,
        stock: stock ?? this.stock,
        active: active ?? this.active,
        icon: icon ?? this.icon,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );
}

class RewardRedemption {
  final int? id;
  final int tenantId;
  final int rewardId;
  final int pointsSpent;
  final String status; // 'completed'
  final String redeemedAt;
  final String rewardTitle;

  RewardRedemption({
    this.id,
    required this.tenantId,
    required this.rewardId,
    required this.pointsSpent,
    required this.status,
    required this.redeemedAt,
    this.rewardTitle = '',
  });

  factory RewardRedemption.fromMap(Map<String, dynamic> m) =>
      RewardRedemption(
        id: m['id'] as int?,
        tenantId: m['tenant_id'] as int,
        rewardId: m['reward_id'] as int,
        pointsSpent: m['points_spent'] as int,
        status: m['status'] as String,
        redeemedAt: m['redeemed_at'] as String,
        rewardTitle: (m['reward_title'] as String?) ?? '',
      );
}

class AppNotification {
  final int? id;
  final String title;
  final String message;
  final String sender;
  final String createdAt;
  final bool isRead; // resolved for current tenant via recipient row
  final int? recipientRowId;

  AppNotification({
    this.id,
    required this.title,
    required this.message,
    required this.sender,
    required this.createdAt,
    this.isRead = false,
    this.recipientRowId,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as int?,
        title: m['title'] as String,
        message: m['message'] as String,
        sender: m['sender'] as String,
        createdAt: m['created_at'] as String,
        isRead: (m['is_read'] as int?) == 1,
        recipientRowId: m['recipient_row_id'] as int?,
      );
}

class EnvironmentalQuote {
  final int? id;
  final String quoteText;
  final String author;
  final String createdAt;

  EnvironmentalQuote({
    this.id,
    required this.quoteText,
    required this.author,
    required this.createdAt,
  });

  factory EnvironmentalQuote.fromMap(Map<String, dynamic> m) =>
      EnvironmentalQuote(
        id: m['id'] as int?,
        quoteText: m['quote_text'] as String,
        author: m['author'] as String,
        createdAt: m['created_at'] as String,
      );
}
