import 'package:flutter/material.dart';

import '../models/allocation.dart';
import '../models/financial_preferences.dart';
import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';

/// Account-backed preferences. Stream/callback overrides keep the form testable.
class FinancialPreferencesScreen extends StatefulWidget {
  const FinancialPreferencesScreen({this.profile, this.onSave, super.key});
  final Stream<Map<String, dynamic>?>? profile;
  final void Function(Map<String, dynamic>)? onSave;

  @override
  State<FinancialPreferencesScreen> createState() =>
      _FinancialPreferencesScreenState();
}

class _FinancialPreferencesScreenState
    extends State<FinancialPreferencesScreen> {
  late final _profile =
      widget.profile ??
      UserProfileService.watchProfile().map((snapshot) => snapshot.data());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Financial preferences',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      backgroundColor: appPrimaryBlue,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    body: StreamBuilder<Map<String, dynamic>?>(
      stream: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Could not load your preferences. Please reopen this screen.',
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return _PreferencesForm(
          initial: FinancialPreferences.fromMap(snapshot.data),
          onSave: widget.onSave ?? UserProfileService.updatePreferences,
        );
      },
    ),
  );
}

class _PreferencesForm extends StatefulWidget {
  const _PreferencesForm({required this.initial, required this.onSave});
  final FinancialPreferences initial;
  final void Function(Map<String, dynamic>) onSave;
  @override
  State<_PreferencesForm> createState() => _PreferencesFormState();
}

class _PreferencesFormState extends State<_PreferencesForm> {
  final _form = GlobalKey<FormState>();
  late final _source = TextEditingController(text: widget.initial.source);
  late final _amount = TextEditingController(
    text: widget.initial.income == null
        ? ''
        : formatAmountInput(widget.initial.income!),
  );
  late String _frequency = widget.initial.frequency;
  late LeftoverDecision _leftover = widget.initial.leftover;

  @override
  void dispose() {
    _source.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// Accepts what people type, such as `10,000`.
  static String _clean(String value) => value.trim().replaceAll(',', '');

  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      widget.onSave({
        'incomeSource': _source.text.trim(),
        'incomeFrequency': _frequency,
        'income': double.tryParse(_clean(_amount.text)),
        'defaultLeftover': _leftover.name,
      });
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Financial preferences saved.')),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save preferences. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const PreferenceIntro(
          icon: Icons.tune,
          title: 'A plan that fits your income',
          message:
              'Keep your usual income up to date, then choose how leftover reviews begin.',
        ),
        const SizedBox(height: 24),
        Text('Income profile', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'These are planning details. Saving them does not add income to a wallet.',
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('income-source'),
          controller: _source,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Income source',
            hintText: 'Salary, allowance, freelance…',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter your income source.'
              : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _frequency,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'How often',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final entry in incomeFrequencies.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) => setState(() => _frequency = value!),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('usual-income'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Usual amount per payment (optional)',
            prefixText: '₱ ',
            helperText: 'Leave blank if the amount changes.',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final amount = double.tryParse(_clean(value));
            return amount == null || !amount.isFinite || amount <= 0
                ? 'Enter an amount greater than zero.'
                : null;
          },
        ),
        const SizedBox(height: 28),
        Text(
          'When money is left over',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Preselect a choice in each review. You always confirm before anything is set aside.',
        ),
        const SizedBox(height: 14),
        for (final choice in LeftoverDecision.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: _leftover == choice
                  ? context.appColors.primaryTint
                  : context.appColors.card,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  _leftover == choice
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: context.appColors.primaryText,
                ),
                title: Text(switch (choice) {
                  LeftoverDecision.saved => 'Save it',
                  LeftoverDecision.spent => 'Keep it for spending',
                  LeftoverDecision.split => 'Split it',
                  LeftoverDecision.pending => 'Ask me each time',
                }),
                onTap: () => setState(() => _leftover = choice),
              ),
            ),
          ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _save,
          style: confirmButtonStyle(),
          child: const Text('Save preferences'),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

class PreferenceIntro extends StatelessWidget {
  const PreferenceIntro({
    required this.title,
    required this.message,
    this.icon,
    super.key,
  });

  /// Left out where the screen's own list already carries the icons.
  final IconData? icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.appColors.primaryTint,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, color: context.appColors.primaryText, size: 28),
          const SizedBox(height: 12),
        ],
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(color: context.appColors.textBody, height: 1.5),
        ),
      ],
    ),
  );
}
