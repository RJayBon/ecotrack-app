import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';

/// Add or edit a tenant. When [tenant] is null this creates a brand new
/// tenant + login account; otherwise it edits the existing profile fields.
class AdminTenantFormScreen extends StatefulWidget {
  final Tenant? tenant;
  const AdminTenantFormScreen({super.key, this.tenant});

  @override
  State<AdminTenantFormScreen> createState() => _AdminTenantFormScreenState();
}

class _AdminTenantFormScreenState extends State<AdminTenantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _unitCtrl;
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _status = 'active';
  bool _saving = false;

  bool get _isEdit => widget.tenant != null;

  @override
  void initState() {
    super.initState();
    final t = widget.tenant;
    _nameCtrl = TextEditingController(text: t?.name ?? '');
    _emailCtrl = TextEditingController(text: t?.email ?? '');
    _phoneCtrl = TextEditingController(text: t?.phone ?? '');
    _unitCtrl = TextEditingController(text: t?.unit ?? '');
    _status = t?.status ?? 'active';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _unitCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final updated = widget.tenant!.copyWith(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          unit: _unitCtrl.text.trim(),
          status: _status,
        );
        await DatabaseHelper.instance.updateTenant(updated);
      } else {
        final exists = await DatabaseHelper.instance.usernameExists(_usernameCtrl.text.trim());
        if (exists) {
          setState(() => _saving = false);
          if (mounted) showErrorSnack(context, 'Username already taken.');
          return;
        }
        await DatabaseHelper.instance.createTenant(
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text,
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          unit: _unitCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      showSuccessSnack(context, _isEdit ? 'Tenant updated.' : 'Tenant created.');
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      // Every setState / context use needs a mounted check: the future can
      // resolve after the route was popped, and calling either then throws.
      debugPrint('Failed to save tenant: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Tenant' : 'Add Tenant')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            LabeledField(
              label: 'Full name',
              controller: _nameCtrl,
              icon: Icons.person_outline,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            LabeledField(
              label: 'Email',
              controller: _emailCtrl,
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            LabeledField(
              label: 'Phone',
              controller: _phoneCtrl,
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            LabeledField(
              label: 'Unit / Address',
              controller: _unitCtrl,
              icon: Icons.home_outlined,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            if (_isEdit) ...[
              const SizedBox(height: 4),
              const Text('Account Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Active'),
                    selected: _status == 'active',
                    onSelected: (_) => setState(() => _status = 'active'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Inactive'),
                    selected: _status == 'inactive',
                    onSelected: (_) => setState(() => _status = 'inactive'),
                  ),
                ],
              ),
            ],
            if (!_isEdit) ...[
              const Divider(height: 32),
              const Text('Login Credentials', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 10),
              LabeledField(
                label: 'Username',
                controller: _usernameCtrl,
                icon: Icons.alternate_email,
                validator: (v) => (v == null || v.trim().length < 3) ? 'Min 3 characters' : null,
              ),
              LabeledField(
                label: 'Temporary password',
                controller: _passwordCtrl,
                icon: Icons.lock_outline,
                obscure: true,
                validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save Changes' : 'Create Tenant'),
            ),
          ],
        ),
      ),
    );
  }
}
