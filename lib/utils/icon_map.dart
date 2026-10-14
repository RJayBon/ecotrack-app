import 'package:flutter/material.dart';

/// Maps the small set of icon keys stored in SQLite to actual Material icons.
/// Keeping this centralized means admin forms can offer a dropdown of keys
/// while the rest of the app just calls [iconFor].
const Map<String, IconData> _icons = {
  'eco': Icons.eco,
  'recycling': Icons.recycling,
  'delete': Icons.delete,
  'warning_amber': Icons.warning_amber_rounded,
  'devices_other': Icons.devices_other,
  'sort': Icons.sort,
  'no_drinks': Icons.no_drinks,
  'menu_book': Icons.menu_book,
  'quiz': Icons.quiz,
  'cleaning_services': Icons.cleaning_services,
  'receipt_long': Icons.receipt_long,
  'shopping_bag': Icons.shopping_bag,
  'water_drop': Icons.water_drop,
  'local_parking': Icons.local_parking,
  'park': Icons.park,
  'star': Icons.star,
  'card_giftcard': Icons.card_giftcard,
  'notifications': Icons.notifications,
  'nature': Icons.nature,
  'compost': Icons.compost,
};

IconData iconFor(String key) => _icons[key] ?? Icons.eco;

List<String> get availableIconKeys => _icons.keys.toList();
