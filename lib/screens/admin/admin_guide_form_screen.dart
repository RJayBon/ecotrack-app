import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../widgets/common_widgets.dart';

class AdminGuideFormScreen extends StatefulWidget {
  final WasteGuide? guide;
  const AdminGuideFormScreen({super.key, this.guide});

  @override
  State<AdminGuideFormScreen> createState() => _AdminGuideFormScreenState();
}

class _AdminGuideFormScreenState extends State<AdminGuideFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _examplesCtrl;
  late final TextEditingController _disposalCtrl;
  late final TextEditingController _tipsCtrl;
  late String _category;
  late String _icon;
  bool _saving = false;

  bool get _isEdit => widget.guide != null;

  @override
  void initState() {
    super.initState();
    final g = widget.guide;
    _titleCtrl = TextEditingController(text: g?.title ?? '');
    _descCtrl = TextEditingController(text: g?.description ?? '');
    _examplesCtrl = TextEditingController(text: g?.examples ?? '');
    _disposalCtrl = TextEditingController(text: g?.disposalMethod ?? '');
    _tipsCtrl = TextEditingController(text: g?.recyclingTips ?? '');
    _category = g?.category ?? kWasteCategories.first;
    _icon = g?.icon ?? 'eco';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _examplesCtrl.dispose();
    _disposalCtrl.dispose();
    _tipsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final guide = WasteGuide(
      id: widget.guide?.id,
      category: _category,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      examples: _examplesCtrl.text.trim(),
      disposalMethod: _disposalCtrl.text.trim(),
      recyclingTips: _tipsCtrl.text.trim(),
      icon: _icon,
      createdAt: widget.guide?.createdAt ?? '',
    );
    try {
      if (_isEdit) {
        await DatabaseHelper.instance.updateGuide(guide);
      } else {
        await DatabaseHelper.instance.insertGuide(guide);
      }
      if (!mounted) return;
      showSuccessSnack(context, _isEdit ? 'Guide updated.' : 'Guide added.');
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      // DEFECT FIX: a failed write used to leave the save button spinning
      // forever, with no message and no way to leave the screen.
      debugPrint('Save guide failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Could not save the guide.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Guide' : 'Add Guide')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kWasteCategories
                  .map((c) => ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            LabeledField(label: 'Title', controller: _titleCtrl,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            LabeledField(label: 'Description', controller: _descCtrl, maxLines: 3,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            LabeledField(label: 'Examples (comma separated)', controller: _examplesCtrl, maxLines: 2,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            LabeledField(label: 'Proper disposal method', controller: _disposalCtrl, maxLines: 2,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            LabeledField(label: 'Recycling tips', controller: _tipsCtrl, maxLines: 2,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 4),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            IconPicker(
              selected: _icon,
              onSelected: (key) => setState(() => _icon = key),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save Changes' : 'Add Guide'),
            ),
          ],
        ),
      ),
    );
  }
}