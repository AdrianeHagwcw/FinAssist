import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/models/debt.dart';
import '../../backend/services/debt_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import '../../backend/utils/text_limits.dart';
import 'check_after_save.dart';
import 'choice_grid.dart';
import 'dialog_kit.dart';

/// What the Debts form would save, handed to tests instead of Firestore.
class LoanDraft {
  const LoanDraft({
    required this.name,
    required this.category,
    required this.principal,
    required this.perPayment,
    required this.paymentCount,
    required this.frequency,
    required this.firstDueDate,
    this.lastPayment = 0,
    this.paidBefore = 0,
    this.quotedRate,
    this.quotedRatePer = RatePeriod.year,
    this.rateBasis = InterestBasis.wholeAmount,
    this.fees = 0,
    this.otherKind,
  });

  final String name;
  final DebtCategory category;
  final double principal;
  final double perPayment;
  final int paymentCount;

  /// The contract's last payment when it differs; zero when it doesn't.
  final double lastPayment;
  final PaymentFrequency frequency;

  /// When the first payment is due.
  final DateTime? firstDueDate;

  /// Payments made before it was tracked here.
  final int paidBefore;

  /// The rate the lender said they charge, if the user was told.
  final double? quotedRate;
  final RatePeriod quotedRatePer;

  /// How the interest is charged.
  final InterestBasis rateBasis;

  /// Fees taken out of the loan.
  final double fees;

  /// The user's own kind, when they chose Other.
  final String? otherKind;
}

/// Adds money the user borrowed: from a bank or lending company, as cash
/// from a credit card (like Cash2Go), from SSS, Pag-IBIG or GSIS, or from
/// family. The payments are worked out from the interest the lender quoted,
/// the way the lender works them out, and go to the Bill Planner.
///
/// Returns whether it was saved, and confirms the save. [name], [amount]
/// and [count] start it filled in, as from the Installments form or Voice
/// Entry.
Future<bool> showLoanFormSheet(
  BuildContext context, {
  String? name,
  double? amount,
  int? count,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) =>
        LoanFormSheet(name: name, amount: amount, count: count),
  );

  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Debt saved. Its payments are in your Bill Planner.'),
        backgroundColor: appConfirmGreen,
      ),
    );
  }
  return saved == true;
}

/// A true cost above this much a month is flagged: far above what banks and
/// government funds charge, and where unregistered lenders operate.
const _highMonthlyCost = 4.0;

enum _LoanTermUnit {
  months('Months', 12),
  years('Years', 1);

  const _LoanTermUnit(this.label, this.monthsPerYear);

  final String label;
  final int monthsPerYear;
}

class LoanFormSheet extends StatefulWidget {
  const LoanFormSheet({
    this.name,
    this.amount,
    this.count,
    this.today,
    this.onSave,
    super.key,
  });

  /// Filled in when the user came from the Installments form or Voice
  /// Entry: what it is called, the amount borrowed, and how many payments.
  final String? name;
  final double? amount;
  final int? count;
  final DateTime? today;

  /// Replaces saving. Used by tests.
  final void Function(LoanDraft draft)? onSave;

  @override
  State<LoanFormSheet> createState() => _LoanFormSheetState();
}

class _LoanFormSheetState extends State<LoanFormSheet> with CheckAfterSave {
  late final DateTime _today = widget.today ?? DateTime.now();
  late DateTime? _date = DateTime(_today.year, _today.month + 1, _today.day);

  late final _nameController = TextEditingController(text: widget.name);
  late final _principalController = TextEditingController(
    text: widget.amount == null ? '' : formatAmountInput(widget.amount!),
  );
  final _rateController = TextEditingController();
  late final _countController = TextEditingController(
    text: widget.count?.toString(),
  );
  final _statedPaymentController = TextEditingController();
  final _paidBeforeController = TextEditingController();
  final _otherKindController = TextEditingController();

  /// Chosen by tapping; until then the name decides it.
  DebtCategory? _pickedKind;
  DebtCategory get _kind {
    if (_pickedKind != null) return _pickedKind!;
    final guess = guessDebtCategory(_nameController.text);
    return guess != null && guess.isLoan ? guess : DebtCategory.personalLoan;
  }

  /// Cash loans are usually quoted so much a month; others a year. One
  /// rate for the whole loan only fits interest on the whole amount.
  RatePeriod? _pickedPer;
  RatePeriod get _per {
    final per =
        _pickedPer ??
        (_kind == DebtCategory.cardCashLoan ||
                _kind == DebtCategory.personalLoan
            ? RatePeriod.month
            : RatePeriod.year);
    return per == RatePeriod.wholeLoan &&
            _basis == InterestBasis.remainingBalance
        ? RatePeriod.year
        : per;
  }

  /// How the interest is charged. Until chosen, what the lender usually
  /// does: SSS, Pag-IBIG and GSIS charge only on what is still owed; cash
  /// loans and card loans on the whole amount.
  InterestBasis? _pickedBasis;
  InterestBasis get _basis =>
      _pickedBasis ??
      (_kind == DebtCategory.governmentLoan
          ? InterestBasis.remainingBalance
          : InterestBasis.wholeAmount);
  PaymentFrequency _frequency = PaymentFrequency.monthly;
  _LoanTermUnit _termUnit = _LoanTermUnit.months;

  /// The user doesn't know the interest, so they give the payment on their
  /// loan papers instead. What it costs is worked out from that, so nobody
  /// is stuck for a number they don't have.
  bool _byPayment = false;

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_refresh);
    }
    recheckWhenChanged(_nameController);
  }

  List<TextEditingController> get _controllers => [
    _nameController,
    _principalController,
    _rateController,
    _countController,
    _statedPaymentController,
    _paidBeforeController,
    _otherKindController,
  ];

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;

  double get _principal => _number(_principalController);
  double? get _rate => double.tryParse(_rateController.text.trim());
  int get _term => int.tryParse(_countController.text.trim()) ?? 0;
  int get _count =>
      (_term * _frequency.perYear / _termUnit.monthsPerYear).round();
  double get _statedPayment => _number(_statedPaymentController);

  /// The rate counted: blank is no interest, for a lender who need not
  /// state one.
  double get _rateUsed => _rate ?? 0;

  bool get _startedBefore {
    final date = _date;
    if (date == null) return false;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).isBefore(DateTime(_today.year, _today.month, _today.day));
  }

  int get _paidBefore =>
      _startedBefore ? int.tryParse(_paidBeforeController.text.trim()) ?? 0 : 0;

  /// The payments the quoted rate comes to.
  LoanPayments? get _worked => loanPayments(
    principal: _principal,
    rate: _rateUsed,
    per: _per,
    basis: _basis,
    count: _count,
    frequency: _frequency,
  );

  /// The loan as it would be saved. The amount on the loan papers, when
  /// typed, is what gets paid; otherwise the worked-out one.
  Debt? get _preview {
    if (_byPayment) {
      if (_principal <= 0 || _count < 1 || _statedPayment <= 0) return null;
      return Debt(
        id: '',
        direction: DebtDirection.iOwe,
        name: _nameController.text,
        category: _kind,
        principal: _principal,
        perPayment: _statedPayment,
        paymentCount: _count,
        frequency: _frequency,
        firstDueDate: _date,
        status: DebtStatus.active,
        paidBefore: _paidBefore,
      );
    }
    final worked = _worked;
    if (worked == null || (_kind.mustDiscloseRate && _rate == null)) {
      return null;
    }
    final stated = _statedPayment;
    return Debt(
      id: '',
      direction: DebtDirection.iOwe,
      name: _nameController.text,
      category: _kind,
      principal: _principal,
      perPayment: stated > 0 ? stated : worked.perPayment,
      paymentCount: _count,
      lastPayment: stated > 0 ? 0 : worked.lastPayment,
      frequency: _frequency,
      firstDueDate: _date,
      status: DebtStatus.active,
      paidBefore: _paidBefore,
      quotedRate: _rate,
      quotedRatePer: _per,
      rateBasis: _basis,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? _today,
      firstDate: DateTime(_today.year - 5),
      lastDate: DateTime(_today.year + 10),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Thirty years of monthly payments, as long as a home loan runs.
  static const _mostPayments = 360;

  /// What stops the loan being saved as it stands, or null. Shown once Save
  /// has been tapped, and gone as soon as it is fixed.
  String? get _problem {
    final nameProblem = itemNameProblem(
      _nameController.text,
      maxLength: maxItemNameLength,
      empty: 'Give it a name.',
    );
    final rate = _rate;
    final preview = _preview;
    if (nameProblem != null) return nameProblem;
    if (!isRecordableAmount(_principal)) return minimumAmountError;
    if (_byPayment && !isRecordableAmount(_statedPayment)) {
      return 'Enter the payment on your loan papers.';
    }
    if (!_byPayment && rate == null && _kind.mustDiscloseRate) {
      return 'Enter the interest from your loan papers, or tap "Don\'t know '
          'the interest?" to enter the payment instead.';
    }
    if (!_byPayment && rate != null && rate > 100) {
      return 'Enter a rate up to 100%.';
    }
    if (_term < 1) return 'Enter how long you have to pay it off.';
    if (_count > _mostPayments) {
      return 'Up to $_mostPayments payments. Check the number on your loan '
          'papers.';
    }
    if (_date == null) return 'Choose when the first payment is due.';
    if (_paidBefore >= _count) {
      return 'That is every payment, so nothing is left to pay.';
    }
    if (preview != null && preview.totalPayable + 0.005 < _principal) {
      return 'Those payments add up to ${formatPeso(preview.totalPayable)}, '
          'less than the ${formatPeso(_principal)} borrowed.';
    }
    return null;
  }

  void _save() {
    markTriedToSave();
    final preview = _preview;
    if (_problem != null || preview == null) return;

    final draft = LoanDraft(
      name: cleanText(_nameController.text),
      category: _kind,
      principal: preview.principal,
      perPayment: preview.perPayment,
      paymentCount: preview.paymentCount,
      lastPayment: preview.hasDifferentLastPayment ? preview.finalPayment : 0,
      frequency: _frequency,
      firstDueDate: _date,
      paidBefore: _paidBefore,
      quotedRate: _byPayment ? null : _rate,
      quotedRatePer: _per,
      rateBasis: _basis,
      otherKind: _kind == DebtCategory.otherLoan
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
        quotedRate: draft.quotedRate,
        quotedRatePer: draft.quotedRatePer,
        rateBasis: draft.rateBasis,
        otherKind: draft.otherKind,
      );
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final error = triedToSave ? _problem : null;
    final preview = _preview;
    final required = _kind.mustDiscloseRate;

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
                'Add Debt',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Money you borrowed and pay back over time.',
                style: TextStyle(fontSize: 13, color: colors.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('loan-name'),
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: maxItemNameLength,
                inputFormatters: const [SafeTextFormatter()],
                onChanged: (_) => setState(() => _pickedKind = null),
                decoration: dialogFieldDecoration(
                  context,
                  'What is this debt called?',
                  hint: switch (_kind) {
                    DebtCategory.cardCashLoan => 'e.g. Cash2Go',
                    DebtCategory.governmentLoan => 'e.g. SSS salary loan',
                    DebtCategory.familyFriend => 'e.g. Tita Baby',
                    DebtCategory.otherLoan => 'e.g. Cooperative loan',
                    _ => 'e.g. BPI personal loan',
                  },
                ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<DebtCategory>(
                key: ValueKey('loan-kind-${_kind.name}'),
                initialValue: _kind,
                isExpanded: true,
                decoration: dialogFieldDecoration(context, 'Loan type'),
                items: [
                  for (final kind in DebtCategory.loanKinds)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (kind) => setState(() => _pickedKind = kind),
              ),
              if (_kind == DebtCategory.otherLoan) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('loan-other-kind'),
                  controller: _otherKindController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 30,
                  inputFormatters: const [SafeTextFormatter()],
                  decoration: dialogFieldDecoration(
                    context,
                    'What kind of loan?',
                    hint: 'e.g. Pawnshop, cooperative',
                  ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
                ),
              ],
              const SizedBox(height: 8),
              AmountField(
                controller: _principalController,
                label: 'Amount borrowed',
                hint: 'e.g. 5,000',
                alwaysShowHint: true,
                autofocus: false,
              ),
              const SizedBox(height: 16),
              if (_byPayment) ...[
                AmountField(
                  key: const Key('loan-payment-papers'),
                  controller: _statedPaymentController,
                  label: 'Payment on your loan papers',
                  hint: 'e.g. 1,716.67',
                  helper: 'Each payment, as your papers or the lender says.',
                  alwaysShowHint: true,
                  autofocus: false,
                ),
                _switchLink(
                  context,
                  'I know the interest',
                  () => setState(() => _byPayment = false),
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        key: const Key('loan-rate'),
                        controller: _rateController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [RateInputFormatter()],
                        decoration:
                            dialogFieldDecoration(
                              context,
                              required ? 'Interest' : 'Interest (optional)',
                              hint: _per == RatePeriod.month
                                  ? 'e.g. 1'
                                  : 'e.g. 10',
                              helper: required
                                  ? 'Your lender must tell you this before you '
                                        'sign. Check your loan papers.'
                                  : 'Leave blank if there is no interest.',
                            ).copyWith(
                              suffixText: '%',
                              helperMaxLines: 3,
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<RatePeriod>(
                        key: ValueKey('loan-rate-per-$_per'),
                        initialValue: _per,
                        isExpanded: true,
                        decoration: dialogFieldDecoration(context, 'Charged'),
                        items: [
                          for (final period in RatePeriod.values)
                            // One rate for the whole loan is always charged on
                            // the whole amount.
                            if (_basis == InterestBasis.wholeAmount ||
                                period != RatePeriod.wholeLoan)
                              DropdownMenuItem(
                                value: period,
                                child: Text(period.choiceLabel),
                              ),
                        ],
                        onChanged: (value) =>
                            setState(() => _pickedPer = value ?? _per),
                      ),
                    ),
                  ],
                ),
                // How it is charged changes what the rate means, so it sits
                // right under it, set to what the lender usually does. Only
                // asked when there is interest.
                if (_rateUsed > 0) ...[
                  const SizedBox(height: 16),
                  _label(context, 'How does the interest work?'),
                  const SizedBox(height: 8),
                  ChoiceGrid<InterestBasis>(
                    options: InterestBasis.values,
                    selected: _basis,
                    label: (basis) => basis.label,
                    keyOf: (basis) => 'loan-basis-${basis.name}',
                    onPick: (basis) => setState(() => _pickedBasis = basis),
                  ),
                  Text(
                    '${_basis.example}.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
                _switchLink(
                  context,
                  "Don't know the interest? Enter the payment instead",
                  () => setState(() => _byPayment = true),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'How long to pay it off?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textBody,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('loan-term'),
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: dialogFieldDecoration(
                        context,
                        'For how long?',
                        hint: 'e.g. 12',
                      ).copyWith(
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<_LoanTermUnit>(
                      key: ValueKey('loan-term-unit-${_termUnit.name}'),
                      initialValue: _termUnit,
                      isExpanded: true,
                      decoration: dialogFieldDecoration(context, 'Term unit'),
                      items: [
                        for (final unit in _LoanTermUnit.values)
                          DropdownMenuItem(value: unit, child: Text(unit.label)),
                      ],
                      onChanged: (unit) => setState(
                        () => _termUnit = unit ?? _termUnit,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentFrequency>(
                key: ValueKey('loan-frequency-${_frequency.name}'),
                initialValue: _frequency,
                isExpanded: true,
                decoration: dialogFieldDecoration(context, 'How often do you pay?'),
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
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: dialogFieldDecoration(context, 'First payment'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _date == null ? 'No date' : formatShortDate(_date!),
                        ),
                      ),
                      Image.asset(
                        'assets/icons/icons8-calendar-96.png',
                        width: 22,
                        height: 22,
                      ),
                    ],
                  ),
                ),
              ),
              if (_startedBefore) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const Key('loan-paid-before'),
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
                            'The first payment is past. These count as paid, '
                            'and no wallet changes.',
                      ).copyWith(
                        helperMaxLines: 3,
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: 16),
                LoanResultCard(debt: preview),
              ],
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(
                  error,
                  style: TextStyle(
                    color: dangerColorOn(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: confirmButtonStyle(),
                  child: const Text(
                    'Save Debt',
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

/// A quiet link to answer a question another way.
Widget _switchLink(BuildContext context, String text, VoidCallback onTap) =>
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: context.appColors.primaryText,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ),
    );

Widget _label(BuildContext context, String text) => Text(
  text,
  style: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: context.appColors.textBody,
  ),
);

/// [value] as a percent to one decimal: "17.9%", "35%".
String _oneDecimal(double value) {
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.truncateToDouble()
      ? '${rounded.toInt()}%'
      : '$rounded%';
}

/// What a loan comes to, like a lender's loan calculator: the payment, big,
/// then the total, the interest and what it really costs a year. Used on
/// the form as it is filled in.
class LoanResultCard extends StatelessWidget {
  const LoanResultCard({required this.debt, super.key});

  final Debt debt;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final body = TextStyle(fontSize: 13, height: 1.4, color: colors.textBody);
    final strong = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    );
    final yearly = debt.yearlyCostPercent;
    final monthly = debt.monthlyCostPercent;
    final interest = debt.totalPayable - debt.principal;

    Widget row(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: body)),
          Text(value, key: key, style: strong),
        ],
      ),
    );

    return Container(
      key: const Key('loan-result'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You pay',
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            formatPeso(debt.perPayment),
            key: const Key('loan-payment'),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          Text(
            '${debt.frequency.label.toLowerCase()}, '
            '${debt.paymentCount} '
            '${debt.paymentCount == 1 ? 'payment' : 'payments'}',
            style: body,
          ),
          if (debt.hasDifferentLastPayment)
            Text(
              'The last one is ${formatPeso(debt.finalPayment)}, from '
              'rounding.',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          Divider(height: 22, color: colors.border),
          row(
            'Total to pay back',
            formatPeso(debt.totalPayable),
            key: const Key('loan-total'),
          ),
          row(
            'Total interest',
            formatPeso(interest > 0.005 ? interest : 0),
            key: const Key('loan-interest'),
          ),
          if (debt.fees > 0) ...[
            row('Fees taken out', formatPeso(debt.fees)),
            row('You receive', formatPeso(debt.amountReceived)),
          ],
          if (yearly != null) ...[
            row(
              'Real cost in a year',
              _oneDecimal(yearly),
              key: const Key('loan-true-cost'),
            ),
            const SizedBox(height: 4),
            Text(
              'Lower is better. Use it to compare loans'
              '${debt.fees > 0 ? '; it counts the fees too' : ''}.',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
          if (monthly != null && monthly > _highMonthlyCost) ...[
            const SizedBox(height: 12),
            _HighCostNote(monthly: monthly, yearly: yearly!),
          ],
          Divider(height: 22, color: colors.border),
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

/// A gentle warning, in amber: a cost this high is worth a second look,
/// but the user may have good reason to borrow anyway.
class _HighCostNote extends StatelessWidget {
  const _HighCostNote({required this.monthly, required this.yearly});

  final double monthly;
  final double yearly;

  @override
  Widget build(BuildContext context) {
    final amber = context.isDarkMode
        ? const Color(0xFFF59E0B)
        : const Color(0xFFB45309);
    return Container(
      key: const Key('loan-high-cost'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This costs a lot: about ${_oneDecimal(monthly)} a month, or '
              '${_oneDecimal(yearly)} a year. Compare other offers, and make '
              'sure the lender is registered with the government (SEC).',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: context.appColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
