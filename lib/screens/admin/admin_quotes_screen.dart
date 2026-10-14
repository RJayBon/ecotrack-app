import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/models.dart';
import '../../utils/theme.dart';
import '../../widgets/common_widgets.dart';

class AdminQuotesScreen extends StatefulWidget {
  const AdminQuotesScreen({super.key});

  @override
  State<AdminQuotesScreen> createState() => _AdminQuotesScreenState();
}

class _AdminQuotesScreenState extends State<AdminQuotesScreen> {
  List<EnvironmentalQuote> _quotes = [];
  EnvironmentalQuote? _quoteOfDay;

  /// True when the last load threw - see `_AdminActivitiesScreenState`.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // DEFECT FIX (C2): two independent reads that used to run back to back.
      final results = await Future.wait<Object?>([
        DatabaseHelper.instance.getQuotes(),
        DatabaseHelper.instance.getQuoteOfTheDay(),
      ]);
      if (!mounted) return;
      setState(() {
        _quotes = results[0] as List<EnvironmentalQuote>;
        _quoteOfDay = results[1] as EnvironmentalQuote?;
        _loadFailed = false;
      });
    } catch (error, stackTrace) {
      // DEFECT FIX (B4): no error path existed, so a failed read rendered
      // "No quotes yet" and offered to add the first one.
      debugPrint('Quote list load failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _openForm({EnvironmentalQuote? quote}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuoteFormSheet(quote: quote),
    );
    if (result == true) await _load();
  }

  Future<void> _delete(EnvironmentalQuote q) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Quote',
      message: 'Delete this quote? This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await DatabaseHelper.instance.deleteQuote(q.id!);
      if (!mounted) return;
      showSuccessSnack(context, 'Quote deleted.');
      await _load();
    } catch (error, stackTrace) {
      // DEFECT FIX (B2): an exception escaped unhandled and the row stayed put
      // with no explanation.
      debugPrint('Delete quote failed: $error\n$stackTrace');
      if (!mounted) return;
      showErrorSnack(context, 'Could not delete the quote.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Environmental Quotes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Add Quote'),
      ),
      body: _loadFailed
          ? ErrorState(
              title: 'Quotes could not be loaded',
              subtitle: 'The quote list could not be read from the local '
                  'database. Please try again.',
              onRetry: _load,
            )
          : _quotes.isEmpty
          ? EmptyState(
              icon: Icons.format_quote,
              title: 'No quotes yet',
              subtitle: 'Add environmental quotes to show tenants each day.',
              action: ElevatedButton.icon(
                onPressed: _openForm,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Quote'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: [
                  if (_quoteOfDay != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: AppColors.heroGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.today, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text("Today's Quote",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          const SizedBox(height: 8),
                          Text('"${_quoteOfDay!.quoteText}"',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontStyle: FontStyle.italic,
                                  height: 1.4)),
                          const SizedBox(height: 8),
                          Text('— ${_quoteOfDay!.author}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ..._quotes.map((q) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: EcoCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.format_quote,
                                  color: AppColors.accent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(q.quoteText,
                                        style: const TextStyle(
                                            fontSize: 13.5, height: 1.35)),
                                    const SizedBox(height: 4),
                                    Text('— ${q.author}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) => v == 'edit'
                                    ? _openForm(quote: q)
                                    : _delete(q),
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}

class _QuoteFormSheet extends StatefulWidget {
  final EnvironmentalQuote? quote;
  const _QuoteFormSheet({this.quote});

  @override
  State<_QuoteFormSheet> createState() => _QuoteFormSheetState();
}

class _QuoteFormSheetState extends State<_QuoteFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _textCtrl;
  late final TextEditingController _authorCtrl;
  bool _saving = false;

  bool get _isEdit => widget.quote != null;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.quote?.quoteText ?? '');
    _authorCtrl = TextEditingController(text: widget.quote?.author ?? '');
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _authorCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final quote = EnvironmentalQuote(
      id: widget.quote?.id,
      quoteText: _textCtrl.text.trim(),
      author: _authorCtrl.text.trim(),
      createdAt: widget.quote?.createdAt ?? '',
    );
    try {
      if (_isEdit) {
        await DatabaseHelper.instance.updateQuote(quote);
      } else {
        await DatabaseHelper.instance.insertQuote(quote);
      }
      if (!mounted) return;
      showSuccessSnack(context, _isEdit ? 'Quote updated.' : 'Quote added.');
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      // DEFECT FIX (B2): a failed write left `_saving` true, stranding the
      // admin's edits in a sheet whose button spun forever.
      debugPrint('Save quote failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnack(context, 'Could not save the quote.');
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // DEFECT FIX (E2): shared SheetHandle, and it now uses the
                // vetted AppColors.cardBorder instead of raw grey.shade300.
                const SheetHandle(),
                const SizedBox(height: 16),
                Text(_isEdit ? 'Edit Quote' : 'Add Quote',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                LabeledField(
                    label: 'Quote text',
                    controller: _textCtrl,
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null),
                LabeledField(
                    label: 'Author',
                    controller: _authorCtrl,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save Changes' : 'Add Quote'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}