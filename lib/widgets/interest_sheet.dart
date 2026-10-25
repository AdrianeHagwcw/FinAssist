import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/money_format.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'item_card.dart';
import 'savings_form_parts.dart';

/// Asks how much interest [wallet] paid and adds it as income there.
///
/// It starts on what FinAssist expects after tax, to save typing, but the
/// user is asked to change it to what their app shows: only the real figure
/// keeps the balance matching the account. Returns whether it was added.
Future<bool> showAddInterestSheet(
  BuildContext context, {
  required Wallet wallet,
  DateTime? today,
  void Function(double amount, DateTime date)? onSave,
}) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        AddInterestSheet(wallet: wallet, today: today, onSave: onSave),
  );
  return added ?? false;
}

class AddInterestSheet extends StatefulWidget {
  const AddInterestSheet({
    required this.wallet,
    this.today,
    this.onSave,
    super.key,
  });

  final Wallet wallet;
  final DateTime? today;

  /// Replaces saving. Used by tests.
  final void Function(double amount, DateTime date)? onSave;

  @override
  State<AddInterestSheet> createState() => _AddInterestSheetState();
}

class _AddInterestSheetState extends State<AddInterestSheet>
    with CheckAfterSave {
  late final DateTime _today = widget.today ?? DateTime.now();
  late final double? _expected = widget.wallet.interestPerPayoutAfterTax;

  late final _amountController = TextEditingController(
    text: _expected == null || !isRecordableAmount(_expected)
        ? ''
        : formatAmountInput((_expected * 100).round() / 100),
  );
  late DateTime _date = DateTime(_today.year, _today.month, _today.day);

  @override
  void initState() {
    super.initState();
    recheckWhenChanged(_amountController);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_today.year - 1),
      lastDate: _today,
    );
    if (picked != null) setState(() => _date = picked);
  }

  double? get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', ''));

  void _save() {
    markTriedToSave();
    final amount = _amount;
    if (!isRecordableAmount(amount)) return;

    if (widget.onSave != null) {
      widget.onSave!(amount!, _date);
    } else {
      WalletService.recordInterest(
        wallet: widget.wallet,
        amount: amount!,
        date: _date,
      );
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final wallet = widget.wallet;
    final expected = _expected;
    final error = triedToSave && !isRecordableAmount(_amount)
        ? minimumAmountError
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Image.asset(wallet.iconAsset, width: 32, height: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Interest from ${wallet.name}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DialogNote(
                text:
                    'Check your ${wallet.name} app for the interest it paid. '
                    'Banks keep ${(interestTaxRate * 100).round()}% as tax '
                    'first, so enter what actually came in.',
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _amountController,
                label: 'Amount that came in',
                autofocus: false,
                helper: expected == null || !isRecordableAmount(expected)
                    ? null
                    : 'We expected about ${formatPeso(expected)} after tax. '
                          'Change it to what your app shows.',
              ),
              const FieldLabel('Date it came in'),
              PickDateField(
                date: _date,
                onTap: _pickDate,
                helper: 'The day your app shows it was paid.',
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error,
                  style: TextStyle(
                    color: dangerColorOn(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('add-interest-save'),
                  onPressed: _save,
                  style: confirmButtonStyle(),
                  child: const Text(
                    'Add Interest',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What an account pays in interest and how often, with the button to add
/// what came in. Shown on the page of an account that pays it regularly.
class InterestCard extends StatelessWidget {
  const InterestCard({
    required this.wallet,
    this.onPayoutChanged,
    this.onAdd,
    super.key,
  });

  final Wallet wallet;

  /// Replaces saving the new schedule. Used by tests.
  final ValueChanged<InterestPayout>? onPayoutChanged;

  /// Replaces opening the sheet. Used by tests.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final payout = wallet.interestPayout;
    final each = wallet.interestPerPayoutAfterTax;
    final rate = wallet.annualInterestRatePercent!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                // The app's interest icon, as on the Cash Summary.
                'assets/icons/icons8-combo-chart-100.png',
                width: 28,
                height: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Interest',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      '${percentText(rate)} a year · paid '
                      '${payout.label.toLowerCase()}',
                      style: TextStyle(fontSize: 13, color: colors.textBody),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (each != null) ...[
            const SizedBox(height: 8),
            // Paid daily, what is added is the month's total.
            ItemCardDetail(
              payout.isDaily ? 'Each month, after tax' : 'Each time, after tax',
              'about ${formatPeso(each)}',
            ),
            ItemCardDetail(
              'In a year, after tax',
              'about ${formatPeso(each * 12 / payout.remindEvery)}',
            ),
          ],
          // The same choice as when a savings deposit is added.
          InterestPayoutPicker(
            payout: payout,
            onChanged: (choice) {
              if (choice == payout) return;
              (onPayoutChanged ??
                  (next) =>
                      WalletService.setInterestPayout(wallet, next))(choice);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('add-interest'),
              onPressed:
                  onAdd ?? () => showAddInterestSheet(context, wallet: wallet),
              style: openButtonStyle(),
              icon: const Icon(Icons.add),
              label: const Text(
                'Add Interest',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'FinAssist never adds interest by itself, so your balance keeps '
            'matching your app.',
            style: TextStyle(fontSize: 12, color: colors.textBody),
          ),
        ],
      ),
    );
  }
}
