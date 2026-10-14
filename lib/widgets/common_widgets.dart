import 'package:flutter/material.dart';

import '../db/database_helper.dart';
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
              color: color.withValues(alpha: AppColors.iconTintAlpha),
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
/// the admin activities and rewards screens.
///
/// The tint is [AppColors.textTintAlpha] (8%) rather than 12% so the label text
/// clears WCAG AA against its own tint: primary 4.63:1, danger 4.96:1, accent
/// 5.87:1, textMuted 4.80:1. At 12% primary lands at 4.36:1 - just short.
class EcoPill extends StatelessWidget {
  final String text;
  final Color color;

  const EcoPill(this.text, {super.key, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.textTintAlpha),
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
                color: AppColors.primary.withValues(alpha: AppColors.textTintAlpha),
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
                color: AppColors.danger.withValues(alpha: AppColors.textTintAlpha),
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
///
/// The tint is [AppColors.textTintAlpha] (8%), not 10%: the label is 12px
/// normal-weight-equivalent text, so it needs 4.5:1. Primary on its own 10%
/// tint measures 4.49:1 - a 0.01 AA failure that only shows up once you
/// actually compute it. At 8% it is 4.63:1, and textMuted on its own 8% tint
/// is 4.80:1.
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
        color: color.withValues(alpha: AppColors.textTintAlpha),
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

/// The little grab handle at the top of every modal bottom sheet.
///
/// Extracted because the same 40x4 pill was hand-written in six sheets, four
/// of which used raw `Colors.grey.shade300` and two of which used the vetted
/// [AppColors.cardBorder]. Wrapped in [Center] on purpose: every sheet puts
/// this inside a `CrossAxisAlignment.stretch` column, and without the `Center`
/// the tight cross-axis constraint would override `width: 40` and draw a
/// full-width bar (the bug `AdminSetupScreen`'s logo had).
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.cardBorder,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Shared "Change Password" bottom sheet for both the admin and tenant
/// profile screens.
///
/// This used to exist twice, verbatim, in `admin_profile_screen.dart` and
/// `tenant_profile_screen.dart` (~106 lines each), which meant every fix had to
/// be applied twice - and indeed both copies shipped the same two defects:
///
///  * no `try`/`catch`, so a database error left the button spinning forever;
///  * no error path at all for a thrown exception.
///
/// Both are fixed here once.
class ChangePasswordSheet extends StatefulWidget {
  final int userId;
  const ChangePasswordSheet({super.key, required this.userId});

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final ok = await DatabaseHelper.instance
          .changePassword(widget.userId, _currentCtrl.text, _newCtrl.text);
      if (!mounted) return;
      if (!ok) {
        setState(() => _saving = false);
        showErrorSnack(context, 'Current password is incorrect.');
        return;
      }
      showSuccessSnack(context, 'Password changed successfully.');
      Navigator.pop(context);
    } catch (error, stackTrace) {
      // Without this the button spun forever and the sheet could only be
      // dismissed by swiping it away, with no explanation.
      debugPrint('Change password failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Could not change the password. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: 16),
              const Text('Change Password',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              LabeledField(
                  label: 'Current password',
                  controller: _currentCtrl,
                  obscure: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null),
              LabeledField(
                  label: 'New password',
                  controller: _newCtrl,
                  obscure: true,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null),
              LabeledField(
                  label: 'Confirm new password',
                  controller: _confirmCtrl,
                  obscure: true,
                  validator: (v) =>
                      v != _newCtrl.text ? 'Passwords do not match' : null),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Update Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Presents [ChangePasswordSheet]. Kept as a helper so neither profile screen
/// has to repeat the sheet's presentation options.
Future<void> showChangePasswordSheet(
  BuildContext context, {
  required int userId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangePasswordSheet(userId: userId),
  );
}
