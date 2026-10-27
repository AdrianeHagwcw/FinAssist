import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/amount_input_formatter.dart';
import '../models/debt.dart';
import '../services/debt_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../utils/text_limits.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'loan_form_sheet.dart';

/// Adds something bought on installment: a phone, an appliance, a credit
/// card installment, Buy now, pay later. Borrowed money has its own form
/// under Debts ([showLoanFormSheet]), which this one hands over to when the
/// name sounds like a loan.
///
/// Returns which list the new entry went to, or null if nothing was saved,
/// and confirms the save so the user knows it worked.
///
/// [name], [price], [perPayment] and [count] start it filled in, as from
/// Voice Entry; the user checks them before saving.
Future<DebtDirection?> showDebtFormSheet(
  BuildContext context, {
  String? name,
  double? price,
  double? perPayment,
  int? count,
}) async {
  String? asDebt;
  final saved = await showModalBottomSheet<DebtDirection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => DebtFormSheet(
      initialName: name,
      initialPrice: price,
      initialPerPayment: perPayment,
      initialCount: count,
      onAddAsDebt: (name) {
        asDebt = name;
        Navigator.pop(sheetContext);
      },
    ),
  );

  if (asDebt != null && context.mounted) {
    await showLoanFormSheet(context, name: asDebt);
    return null;
  }

  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Installment saved. Its payments are in your Bill Planner.',
        ),
        backgroundColor: appConfirmGreen,
      ),
    );
  }
  return saved;
}

/// What the form would save, handed to tests instead of Firestore.
class DebtDraft {
  const DebtDraft({
    required this.direction,
    required this.name,
    required this.category,
    required this.principal,
    required this.perPayment,
    required this.paymentCount,
    required this.frequency,
    required this.firstDueDate,
    this.lastPayment = 0,
    this.movedWalletId,
    this.note,
    this.paidBefore = 0,
    this.quotedRate,
    this.quotedRatePer = RatePeriod.year,
    this.rateBasis = InterestBasis.wholeAmount,
    this.fees = 0,
    this.otherKind,
  });

  final DebtDirection direction;
  final String name;
  final DebtCategory category;
  final double principal;
  final double perPayment;
  final int paymentCount;

  /// The contract's last payment when it differs; zero when it doesn't.
  final double lastPayment;
  final PaymentFrequency frequency;

  /// First payment for an installment; the promised date for money owed.
  final DateTime? firstDueDate;

  /// Where borrowed money arrived, or where lent money came from.
  final String? movedWalletId;
  final String? note;

  /// Payments made before it was tracked here.
  final int paidBefore;

  /// The rate the lender said they charge, if the user was told.
  final double? quotedRate;
  final RatePeriod quotedRatePer;

  /// How a loan's interest is charged.
  final InterestBasis rateBasis;

  /// Fees taken out of a loan.
  final double fees;

  /// The user's own kind, when they chose Other.
  final String? otherKind;
}

class DebtFormSheet extends StatefulWidget {
  const DebtFormSheet({
    this.initialName,
    this.initialPrice,
    this.initialPerPayment,
    this.initialCount,
    this.today,
    this.onSave,
    this.onAddAsDebt,
    super.key,
  });

  /// What it starts filled in with.
  final String? initialName;
  final double? initialPrice;
  final double? initialPerPayment;
  final int? initialCount;

  /// Closes this form and opens the Debts one with the name typed so far,
  /// for borrowed money started here by mistake.
  final void Function(String name)? onAddAsDebt;

  final DateTime? today;

  /// Replaces saving. Used by tests.
  final void Function(DebtDraft draft)? onSave;

  @override
  State<DebtFormSheet> createState() => _DebtFormSheetState();
}

class _DebtFormSheetState extends State<DebtFormSheet> with CheckAfterSave {
  /// Chosen by hand under More options; until then the name decides it,
  /// among the kinds bought on installment. Loans belong under Debts.
  DebtCategory? _pickedCategory;
  DebtCategory get _category {
    final guess = guessDebtCategory(_nameController.text);
    return _pickedCategory ??
        (guess != null && !guess.isLoan ? guess : null) ??
        (_nameController.text.trim().isEmpty
            ? DebtCategory.gadget
            : DebtCategory.other);
  }

  /// The name sounds like borrowed money, such as "SSS loan" or "Cash2Go".
  bool get _soundsLikeLoan =>
      _pickedCategory == null &&
      (guessDebtCategory(_nameController.text)?.isLoan ?? false);
  PaymentFrequency _frequency = PaymentFrequency.monthly;
  late final DateTime _today = widget.today ?? DateTime.now();
  late DateTime? _date = DateTime(_today.year, _today.month + 1, _today.day);

  late final _nameController = TextEditingController(text: widget.initialName);
  late final _principalController = TextEditingController(
    text: _amountText(widget.initialPrice),
  );
  late final _perPaymentController = TextEditingController(
    text: _amountText(widget.initialPerPayment),
  );
  late final _countController = TextEditingController(
    text: widget.initialCount?.toString(),
  );
  final _lastController = TextEditingController();
  final _downController = TextEditingController();
  final _paidBeforeController = TextEditingController();
  final _otherKindController = TextEditingController();

  static String _amountText(double? amount) =>
      amount == null ? '' : formatAmountInput(amount);

  /// Everything a plan does not need is folded away until asked for. The
  /// form was a wall of fields and explanations before anything was typed.
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    // The summary card follows every keystroke, and the name picks the kind.
    for (final controller in [
      _nameController,
      _principalController,
      _perPaymentController,
      _countController,
      _lastController,
      _downController,
      _paidBeforeController,
    ]) {
      controller.addListener(_refresh);
    }
    recheckWhenChanged(_nameController);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _principalController,
      _perPaymentController,
      _countController,
      _lastController,
      _downController,
      _paidBeforeController,
      _otherKindController,
    ]) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;

  bool get _countTyped {
    final typed = int.tryParse(_countController.text.trim());
    return typed != null && typed > 0;
  }

  /// What the payments are for: the cash price less any down payment
  /// made when it was bought. Zero when no price was typed.
  double get _financed {
    final price = _number(_principalController);
    if (price <= 0) return 0;
    final left = price - _number(_downController);
    return left > 0 ? left : 0;
  }

  /// Payments typed, or worked out from the amounts when left blank.
  int get _paymentCount {
    if (_countTyped) return int.parse(_countController.text.trim());
    return paymentsToCover(_financed, _number(_perPaymentController));
  }

  /// What the payments are for. Optional: left blank, it is taken as
  /// everything paid, so no interest is assumed.
  double get _principal {
    final typed = _financed;
    if (typed > 0 || _paymentCount < 1) return typed;
    final each = _number(_perPaymentController);
    final last = _number(_lastController);
    return each * (_paymentCount - 1) + (last > 0 ? last : each);
  }

  /// The contract's last payment when it differs: as typed, or, with the
  /// number of payments left blank, what is left of the amount borrowed
  /// after the others. Typed terms are the contract, so they are kept as
  /// they are. Zero means the same as every other payment.
  double get _lastPayment {
    final typed = _number(_lastController);
    if (typed > 0) return typed;
    if (_countTyped) return 0;
    return coveringLastPayment(
      _financed,
      _number(_perPaymentController),
      _paymentCount,
    );
  }

  /// Whether the first payment is already behind, so some may be paid.
  bool get _startedBefore {
    final date = _date;
    if (date == null) return false;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).isBefore(DateTime(_today.year, _today.month, _today.day));
  }

  /// Payments made before it was tracked here; only asked for, and only
  /// counted, when the first one is already behind.
  int get _paidBefore =>
      _startedBefore ? int.tryParse(_paidBeforeController.text.trim()) ?? 0 : 0;

  Debt get _preview => Debt(
    id: '',
    direction: DebtDirection.iOwe,
    name: _nameController.text,
    category: _category,
    principal: _principal,
    perPayment: _number(_perPaymentController),
    paymentCount: _paymentCount,
    lastPayment: _lastPayment,
    frequency: _frequency,
    firstDueDate: _date,
    status: DebtStatus.active,
    paidBefore: _paidBefore,
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? _today,
      firstDate: DateTime(_today.year - 5),
      lastDate: DateTime(_today.year + 10),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// What stops the plan being saved as it stands, or null. Shown once Save
  /// has been tapped, and gone as soon as it is fixed.
  String? _problem() {
    final principal = _principal;
    final perPayment = _number(_perPaymentController);
    final nameProblem = itemNameProblem(
      _nameController.text,
      maxLength: maxItemNameLength,
      empty: 'Give it a name.',
    );

    if (nameProblem != null) {
      return nameProblem;
    } else if (!isRecordableAmount(perPayment)) {
      return minimumAmountError;
    } else if (_paymentCount < 1) {
      return 'Enter how many payments.';
    } else if (_paymentCount > _mostPayments) {
      return 'Up to $_mostPayments payments. Check the number on your '
          'contract.';
    } else if (_paidBefore >= _paymentCount) {
      return 'That is every payment, so nothing is left to pay.';
    } else if (_date == null) {
      return 'Choose when the first payment is due.';
    } else if (_number(_downController) > 0 &&
        _number(_downController) >= _number(_principalController)) {
      return 'The down payment must be less than the cash price.';
    } else if (_preview.totalPayable + 0.005 < principal) {
      // Most often a down payment left out: say where it goes.
      return 'Those payments add up to ${formatPeso(_preview.totalPayable)}, '
          'less than the ${formatPeso(principal)} '
          '${_number(_downController) > 0 ? 'left after the down payment' : 'cash price'}. '
          '${_number(_downController) > 0 ? 'Check the amounts.' : 'If you paid part upfront, add it as the down payment under More options.'}';
    }
    return null;
  }

  /// Thirty years of monthly payments, more than any personal loan, so a
  /// slip such as 1200 for 12 is caught.
  static const _mostPayments = 360;

  void _save() {
    markTriedToSave();
    if (_problem() != null) return;

    final name = cleanText(_nameController.text);
    final principal = _principal;
    final perPayment = _number(_perPaymentController);

    final draft = DebtDraft(
      direction: DebtDirection.iOwe,
      name: name,
      category: _category,
      principal: principal,
      perPayment: perPayment,
      paymentCount: _paymentCount,
      lastPayment: _preview.hasDifferentLastPayment ? _preview.finalPayment : 0,
      frequency: _frequency,
      firstDueDate: _date,
      paidBefore: _paidBefore,
      otherKind: _category == DebtCategory.other
          ? cleanText(_otherKindController.text)
          : null,
    );

    if (widget.onSave != null) {
      widget.onSave!(draft);
    } else {
      DebtService.addInstallment(
        name: draft.name,
        category: draft.category,
        principal: draft.principal,
        perPayment: draft.perPayment,
        paymentCount: draft.paymentCount,
        lastPayment: draft.lastPayment,
        frequency: draft.frequency,
        firstDueDate: draft.firstDueDate!,
        paidBefore: draft.paidBefore,
        otherKind: draft.otherKind,
      );
    }

    Navigator.pop(context, draft.direction);
  }

  Widget _datePicker() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: dialogFieldDecoration(context, 'First payment'),
        child: Row(
          children: [
            Expanded(
              child: Text(_date == null ? 'No date' : formatShortDate(_date!)),
            ),
            Image.asset(
              'assets/icons/icons8-calendar-96.png',
              width: 22,
              height: 22,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Builder(
            builder: (context) {
              final error = triedToSave ? _problem() : null;

              return Column(
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
                  // A visible way out: a long sheet can only be dragged down
                  // from the very top of it.
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add Installment',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: maxItemNameLength,
                    inputFormatters: const [SafeTextFormatter()],
                    decoration:
                        dialogFieldDecoration(
                          context,
                          'Name',
                          hint: 'e.g. Phone, Aircon',
                        ).copyWith(
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                  ),
                  if (_soundsLikeLoan && widget.onAddAsDebt != null) ...[
                    DialogNote(
                      text:
                          'This sounds like borrowed money. Add it under '
                          'Debts, where the payments are worked out from the '
                          'interest.',
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => widget.onAddAsDebt!(
                          cleanText(_nameController.text),
                        ),
                        child: const Text('Add it as a debt'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AmountField(
                    controller: _principalController,
                    label: 'Cash price (optional)',
                    hint: 'e.g. 12,000',
                    helper: 'Shows how much more you pay than paying in full.',
                    alwaysShowHint: true,
                    autofocus: false,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _perPaymentController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [
                            ThousandsSeparatorFormatter(),
                          ],
                          decoration:
                              dialogFieldDecoration(
                                context,
                                'Each payment',
                              ).copyWith(
                                // The peso sign waits for the first digit,
                                // so the example isn't taken for an amount.
                                prefixText: _perPaymentController.text.isEmpty
                                    ? null
                                    : '₱ ',
                                hintText: 'e.g. 1,500',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _countController,
                          keyboardType: TextInputType.number,
                          // Whole payments only, never a sign, a point or
                          // a pasted paragraph.
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          decoration:
                              dialogFieldDecoration(
                                context,
                                'How many',
                                hint: 'e.g. 12',
                              ).copyWith(
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<PaymentFrequency>(
                          initialValue: _frequency,
                          isExpanded: true,
                          decoration: dialogFieldDecoration(
                            context,
                            'How often',
                          ),
                          items: [
                            for (final frequency in PaymentFrequency.values)
                              DropdownMenuItem(
                                value: frequency,
                                child: Text(frequency.label),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _frequency = value ?? _frequency),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _datePicker()),
                    ],
                  ),
                  // Already paying it: what is behind counts as paid, so the
                  // app never asks for those payments again.
                  if (_startedBefore) ...[
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('installment-paid-before'),
                      controller: _paidBeforeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration:
                          dialogFieldDecoration(
                            context,
                            'How many have you paid already?',
                            hint: 'e.g. 3',
                            helper:
                                'The first payment is past. These count as '
                                'paid, and no wallet changes.',
                          ).copyWith(
                            helperMaxLines: 3,
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _SummaryCard(debt: _preview),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showMore = !_showMore),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primaryText,
                        padding: EdgeInsets.zero,
                      ),
                      icon: Icon(
                        _showMore ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        _showMore ? 'Fewer options' : 'More options (optional)',
                      ),
                    ),
                  ),
                  if (_showMore) ...[
                    const SizedBox(height: 8),
                    // Only matters with a cash price, so it waits for one.
                    if (_number(_principalController) > 0) ...[
                      AmountField(
                        key: const Key('installment-down-payment'),
                        controller: _downController,
                        label: 'Down payment (optional)',
                        hint: 'e.g. 2,000',
                        helper: 'If you paid part of the price upfront.',
                        alwaysShowHint: true,
                        autofocus: false,
                      ),
                      const SizedBox(height: 16),
                    ],
                    DropdownButtonFormField<DebtCategory>(
                      // Rebuilt as the name changes the guess.
                      key: ValueKey(_category),
                      initialValue: _category,
                      isExpanded: true,
                      decoration: dialogFieldDecoration(context, 'Kind'),
                      items: [
                        for (final category in DebtCategory.installmentKinds)
                          DropdownMenuItem(
                            value: category,
                            child: Text(category.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _pickedCategory = value),
                    ),
                    const SizedBox(height: 16),
                    if (_category == DebtCategory.other) ...[
                      TextField(
                        key: const Key('installment-other-kind'),
                        controller: _otherKindController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 30,
                        inputFormatters: const [SafeTextFormatter()],
                        decoration: dialogFieldDecoration(
                          context,
                          'What kind is it?',
                          hint: 'e.g. Dental treatment',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      key: const Key('installment-last-payment'),
                      controller: _lastController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [ThousandsSeparatorFormatter()],
                      decoration:
                          dialogFieldDecoration(
                            context,
                            'Last payment (optional)',
                            helper:
                                "Only if your contract's last payment is "
                                'different, such as ₱3,000 three times then '
                                '₱1,000.',
                          ).copyWith(
                            prefixText: '₱ ',
                            hintText: 'Same as the rest',
                            helperMaxLines: 3,
                          ),
                    ),
                  ],
                  if (error != null) ...[
                    Text(
                      error,
                      style: TextStyle(
                        color: dangerColorOn(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: confirmButtonStyle(),
                      child: const Text(
                        'Save Installment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// What the plan comes to, once the amounts are in: how many payments, the
/// total, what it costs on top and how much of each payment is interest. It
/// sits under the fields it adds up, and before anything is typed shows
/// only that saving the plan moves no money.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.debt});

  final Debt debt;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final last = debt.lastDueDate;
    final ready =
        debt.principal > 0 && debt.perPayment > 0 && debt.paymentCount > 0;
    final body = TextStyle(fontSize: 13, height: 1.4, color: colors.textBody);
    if (!ready) return const SizedBox.shrink();
    final next = debt.paidBefore > 0
        ? debt.dueDateOf(debt.paidBefore + 1)
        : null;

    return Container(
      key: const Key('installment-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ready) ...[
            Text(
              '${debt.paymentCount} '
              '${debt.paymentCount == 1 ? 'payment' : 'payments'} of '
              '${formatPeso(debt.perPayment)}, '
              '${debt.frequency.label.toLowerCase()}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You will pay ${formatPeso(debt.totalPayable)} in total'
              '${debt.extraCost > 0 ? ', which is ${formatPeso(debt.extraCost)} more than you borrowed (${roundedPercent(debt.extraCostPercent)})' : ''}.',
              style: body,
            ),
            if (debt.yearlyCostPercent != null) ...[
              const SizedBox(height: 4),
              Text(costRateText(debt), style: body),
            ],
            // How it will show in Transactions and Reports.
            if (debt.extraCost > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${formatPeso(debt.interestOf(1))} of each payment is '
                'interest.',
                style: body,
              ),
            ],
            if (next != null) ...[
              const SizedBox(height: 4),
              Text(
                '${debt.paidBefore} already paid · next one '
                '${formatShortDate(next)}',
                style: body,
              ),
            ],
            if (last != null) ...[
              const SizedBox(height: 4),
              Text(
                debt.hasDifferentLastPayment
                    ? 'Last payment ${formatPeso(debt.finalPayment)} on '
                          '${formatShortDate(last)}'
                    : 'Last payment ${formatShortDate(last)}',
                style: body,
              ),
            ],
            Divider(height: 20, color: colors.border),
          ],
          Text(
            'This only writes down the plan. Your money does not move until '
            'you pay.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
