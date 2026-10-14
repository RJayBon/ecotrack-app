import 'package:flutter/material.dart';

import '../utils/icon_map.dart';
import '../utils/theme.dart';

/// A rounded, elevated-feeling container used throughout the app for
/// consistent card styling without repeating decoration boilerplate.
class EcoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const EcoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: card,
    );
  }
}

/// Dashboard-style stat tile: icon, big number, label.
class StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return EcoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Small rounded metadata label ("+20 pts", "Unlimited", "One-time", ...).
///
/// Replaces the near-identical private `_pill` helpers that used to live in
/// the admin activities and rewards screens. The background tint is 8% rather
/// than 12% so the label text clears WCAG AA against its own tint
/// (primary 4.63:1, danger 4.96:1) instead of landing just short at 4.36:1.
class EcoPill extends StatelessWidget {
  final String text;
  final Color color;

  const EcoPill(this.text, {super.key, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Grid of selectable icons used by the guide / activity / reward forms.
///
/// Previously copy-pasted three times, each with its own hard-coded
/// `Color(0xFF2E7D32)` / `Color(0xFFF0F5F0)` literals.
class IconPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const IconPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: availableIconKeys.map((key) {
        final isSelected = selected == key;
        return InkWell(
          onTap: () => onSelected(key),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.fieldFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              iconFor(key),
              color: isSelected ? Colors.white : AppColors.textMuted,
              size: 20,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Friendly empty-state placeholder for lists with no data.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Shown when a screen could not load its data (for example a database
/// error).
///
/// This exists because a failed load used to be indistinguishable from "there
/// is nothing here": the exception escaped as an unhandled async error (which
/// the user never sees) while the screen rendered its ordinary empty state, so
/// there was no way to tell "no tenants yet" from "the query blew up" - and no
/// way to retry without leaving the screen.
class ErrorState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.subtitle = 'This screen could not load its data. Please try again.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline,
                  size: 40, color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard confirm dialog; returns true if the user confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: danger ? AppColors.danger : AppColors.primary,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSuccessSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: AppColors.primary,
    ),
  );
}

void showErrorSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: AppColors.danger,
    ),
  );
}

/// Status pill used in tenant lists (active/inactive).
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    final color = isActive ? AppColors.primary : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Text field with consistent styling + validation wired for forms.
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscure;
  final int maxLines;
  final IconData? icon;
  final ValueChanged<String>? onChanged;

  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.maxLines = 1,
    this.icon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        ),
      ),
    );
  }
}