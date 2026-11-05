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
    this.fixedInterestAmount,
    this.interestChargedPer,
    this.loanDuration,
    this.loanDurationUnit,
    this.loanStartDate,
    this.balanceBasedSchedule = true,
    this.otherKind,
  });

  final String name;
  final DebtCategory category;

  /// The balance the user still owes when they add this debt.
  final double principal;
  final double perPayment;
  final int paymentCount;
  final double lastPayment;
  final PaymentFrequency frequency;
  final DateTime? firstDueDate;
  final int paidBefore;
  final double? fixedInterestAmount;
  final PaymentFrequency? interestChargedPer;
  final int? loanDuration;
  final String? loanDurationUnit;
  final DateTime? loanStartDate;
  final bool balanceBasedSchedule;
  final String? otherKind;
}

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

enum _LoanTermUnit {
  months('Months', 1),
  years('Years', 12);

  const _LoanTermUnit(this.label, this.monthsPerUnit);

  final String label;
  final int monthsPerUnit;
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

  final String? name;
  final double? amount;
  final int? count;
  final DateTime? today;
  final void Function(LoanDraft draft)? onSave;

  @override
  State<LoanFormSheet> createState() => _LoanFormSheetState();
}

class _LoanFormSheetState extends State<LoanFormSheet> with CheckAfterSave {
  late final DateTime _today = widget.today ?? DateTime.now();
  late DateTime? _nextPaymentDate = DateTime(
    _today.year,
    _today.month + 1,
    _today.day,
  );
  DateTime? _loanStartDate;

  late final _nameController = TextEditingController(text: widget.name);
  late final _balanceController = TextEditingController(
    text: widget.amount == null ? '' : formatAmountInput(widget.amount!),
  );
  final _paymentController = TextEditingController();
  final _fixedInterestController = TextEditingController();
  late final _durationController = TextEditingController(
    text: widget.count?.toString(),
  );
  final _otherKindController = TextEditingController();

  DebtCategory? _pickedKind;
  DebtCategory get _kind {
    if (_pickedKind != null) return _pickedKind!;
    final guess = guessDebtCategory(_nameController.text);
    return guess != null && guess.isLoan ? guess : DebtCategory.personalLoan;
  }

  PaymentFrequency _frequency = PaymentFrequency.monthly;
  PaymentFrequency? _interestChargedPer;
  _LoanTermUnit _durationUnit = _LoanTermUnit.months;
  bool _durationWasEdited = false;
  bool _durationIsAutomatic = false;
  late bool _showAdditionalDetails = widget.count != null;

  @override
  void initState() {
    super.initState();
    _durationWasEdited = widget.count != null;
    for (final controller in _controllers) {
      controller.addListener(
        controller == _durationController ? _refreshDuration : _refresh,
      );
    }
    recheckWhenChanged(_nameController);
  }

  List<TextEditingController> get _controllers => [
    _nameController,
    _balanceController,
    _paymentController,
    _fixedInterestController,
    _durationController,
    _otherKindController,
  ];

  void _refresh() {
    if (!_durationWasEdited) _updateAutomaticDuration();
    if (mounted) setState(() {});
  }

  void _refreshDuration() {
    if (mounted) setState(() {});
  }

  /// Shows an estimated duration as soon as the balance, payment, and
  /// frequency are known. The estimate stays display-only until the user
  /// edits it; the schedule itself continues to use the exact payment count.
  void _updateAutomaticDuration() {
    final automaticCount = _balance > 0 && _payment > 0
        ? paymentsToCover(_balance, _payment)
        : 0;
    if (automaticCount < 1) {
      if (_durationIsAutomatic) {
        _durationIsAutomatic = false;
        _durationController.clear();
      }
      return;
    }

    final duration = switch (_durationUnit) {
      _LoanTermUnit.months => (automaticCount * 12 / _frequency.perYear).ceil(),
      _LoanTermUnit.years => (automaticCount / _frequency.perYear).ceil(),
    };
    final text = duration.toString();
    if (_durationController.text == text && _durationIsAutomatic) return;

    _durationIsAutomatic = true;
    _durationController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(
          controller == _durationController ? _refreshDuration : _refresh,
        )
        ..dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;

  double get _balance => _number(_balanceController);
  double get _payment => _number(_paymentController);
  double? get _fixedInterestAmount =>
      _fixedInterestController.text.trim().isEmpty
      ? null
      : _number(_fixedInterestController);
  int? get _duration => _durationController.text.trim().isEmpty
      ? null
      : int.tryParse(_durationController.text.trim());

  /// Keep a finite schedule for the existing bill and debt tracking flows.
  /// If no duration was supplied, estimate its length from balance/payment.
  int get _paymentCount {
    final duration = _duration;
    if (!_durationIsAutomatic && duration != null && duration > 0) {
      final periodsPerYear = _frequency.perYear;
      final years = duration * _durationUnit.monthsPerUnit / 12;
      return (years * periodsPerYear).ceil();
    }
    return paymentsToCover(_balance, _payment);
  }

  double get _finalPayment => _paymentCount < 1
      ? 0
      : ((_balance - _payment * (_paymentCount - 1)) * 100).round() / 100;

  Debt? get _preview {
    if (_balance <= 0 || _payment <= 0 || _paymentCount < 1) return null;
    return Debt(
      id: '',
      direction: DebtDirection.iOwe,
      name: _nameController.text,
      category: _kind,
      principal: _balance,
      perPayment: _paymentCount == 1 && _payment > _balance
          ? _balance
          : _payment,
      paymentCount: _paymentCount,
      lastPayment: _finalPayment,
      frequency: _frequency,
      firstDueDate: _nextPaymentDate,
      status: DebtStatus.active,
      fixedInterestAmount: _fixedInterestAmount,
      interestChargedPer: _fixedInterestAmount == null
          ? null
          : _interestChargedPer,
      loanDuration: _duration,
      loanDurationUnit: _duration == null ? null : _durationUnit.name,
      loanStartDate: _loanStartDate,
      balanceBasedSchedule: true,
    );
  }

  Future<void> _pickDate({required bool loanStart}) async {
    final initial = loanStart
        ? (_loanStartDate ?? _today)
        : (_nextPaymentDate ?? _today);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(_today.year - 100),
      lastDate: DateTime(_today.year + 50),
    );
    if (picked == null) return;
    setState(() {
      if (loanStart) {
        _loanStartDate = picked;
      } else {
        _nextPaymentDate = picked;
      }
    });
  }

  static const _mostPayments = 36500;

  String? get _problem {
    final nameProblem = itemNameProblem(
      _nameController.text,
      maxLength: maxItemNameLength,
      empty: 'Enter a name for this debt.',
    );
    if (nameProblem != null) {
      return nameProblem;
    }
    if (!isRecordableAmount(_balance)) {
      return 'Enter a remaining balance above zero.';
    }
    if (!isRecordableAmount(_payment)) {
      return 'Enter a payment amount above zero.';
    }
    if (_fixedInterestController.text.trim().isNotEmpty &&
        !isRecordableAmount(_fixedInterestAmount ?? 0)) {
      return 'Enter a fixed interest amount above zero.';
    }
    if (_fixedInterestAmount != null && _interestChargedPer == null) {
      return 'Choose how often the fixed interest is charged.';
    }
    if (_durationController.text.trim().isNotEmpty &&
        (_duration == null || _duration! < 1)) {
      return 'Enter a debt duration above zero.';
    }
    if (_paymentCount < 1) return 'Enter a valid payment amount or duration.';
    if (_paymentCount > _mostPayments) {
      return 'The payment schedule is too long. Check the duration.';
    }
    if (_paymentCount > 1 && _finalPayment <= 0) {
      return 'The duration is longer than needed for this balance and payment.';
    }
    if (_payment * _paymentCount + 0.005 < _balance) {
      return 'The payments over that duration are less than the remaining balance.';
    }
    if (_nextPaymentDate == null) return 'Choose the next payment date.';
    return null;
  }

  void _save() {
    markTriedToSave();
    final problem = _problem;
    final preview = _preview;
    if (problem != null || preview == null) return;

    final draft = LoanDraft(
      name: cleanText(_nameController.text),
      category: _kind,
      principal: _balance,
      perPayment: preview.perPayment,
      paymentCount: _paymentCount,
      lastPayment: preview.hasDifferentLastPayment ? preview.finalPayment : 0,
      frequency: _frequency,
      firstDueDate: _nextPaymentDate,
      fixedInterestAmount: _fixedInterestAmount,
      interestChargedPer: _fixedInterestAmount == null
          ? null
          : _interestChargedPer,
      loanDuration: _duration,
      loanDurationUnit: _duration == null ? null : _durationUnit.name,
      loanStartDate: _loanStartDate,
      balanceBasedSchedule: true,
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
        fixedInterestAmount: draft.fixedInterestAmount,
        interestChargedPer: draft.interestChargedPer,
        loanDuration: draft.loanDuration,
        loanDurationUnit: draft.loanDurationUnit,
        loanStartDate: draft.loanStartDate,
        balanceBasedSchedule: draft.balanceBasedSchedule,
        otherKind: draft.otherKind,
      );
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final error = triedToSave ? _problem : null;
    final amountHint = _kind == DebtCategory.cardCashLoan
        ? 'e.g. Cash2Go'
        : _kind == DebtCategory.governmentLoan
        ? 'e.g. SSS salary loan'
        : _kind == DebtCategory.familyFriend
        ? 'e.g. Personal borrowing'
        : 'e.g. BPI personal loan';

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
              Text(
                'Add Debt',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _sectionTitle(context, 'Basic Information'),
              const SizedBox(height: 10),
              TextField(
                key: const Key('loan-name'),
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: maxItemNameLength,
                inputFormatters: const [SafeTextFormatter()],
                onChanged: (_) => setState(() => _pickedKind = null),
                decoration: dialogFieldDecoration(
                  context,
                  'Debt name',
                  hint: amountHint,
                ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<DebtCategory>(
                key: ValueKey('loan-kind-${_kind.name}'),
                initialValue: _kind,
                isExpanded: true,
                decoration: dialogFieldDecoration(
                  context,
                  'Where did you borrow?',
                ),
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
                  decoration:
                      dialogFieldDecoration(
                        context,
                        'What kind of lender?',
                        hint: 'e.g. Cooperative',
                      ).copyWith(
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                ),
              ],
              const SizedBox(height: 8),
              AmountField(
                key: const Key('loan-balance'),
                controller: _balanceController,
                label: 'Remaining debt balance',
                hint: 'e.g. 15,000',
                alwaysShowHint: true,
                autofocus: false,
              ),
              const SizedBox(height: 20),
              _sectionTitle(context, 'Payment Information'),
              const SizedBox(height: 10),
              AmountField(
                key: const Key('loan-payment'),
                controller: _paymentController,
                label: 'Payment amount',
                hint: 'e.g. 1,000',
                alwaysShowHint: true,
                autofocus: false,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentFrequency>(
                key: ValueKey('loan-frequency-${_frequency.name}'),
                initialValue: _frequency,
                isExpanded: true,
                decoration: dialogFieldDecoration(context, 'Payment frequency'),
                items: [
                  for (final frequency in PaymentFrequency.values)
                    DropdownMenuItem(
                      value: frequency,
                      child: Text(frequency.label),
                    ),
                ],
                onChanged: (value) {
                  _frequency = value ?? _frequency;
                  _refresh();
                },
              ),
              const SizedBox(height: 12),
              _dateField(
                context,
                label: 'Next payment date',
                date: _nextPaymentDate,
                onTap: () => _pickDate(loanStart: false),
              ),
              const SizedBox(height: 12),
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  key: const Key('loan-additional-details'),
                  initiallyExpanded: _showAdditionalDetails,
                  onExpansionChanged: (expanded) =>
                      setState(() => _showAdditionalDetails = expanded),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    'Additional Debt Details (Optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textBody,
                    ),
                  ),
                  children: [
                    const SizedBox(height: 8),
                    AmountField(
                      key: const Key('loan-fixed-interest'),
                      controller: _fixedInterestController,
                      label: 'Fixed Interest Amount',
                      hint: 'e.g. 180',
                      helper:
                          'Enter the fixed amount your lender charges as '
                          'interest for each selected period.',
                      alwaysShowHint: true,
                      autofocus: false,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PaymentFrequency>(
                      key: ValueKey(
                        'loan-interest-charged-per-'
                        '${_interestChargedPer?.name ?? 'none'}',
                      ),
                      initialValue: _interestChargedPer,
                      isExpanded: true,
                      decoration: dialogFieldDecoration(
                        context,
                        'Interest Charged Per',
                      ),
                      items: [
                        for (final period in PaymentFrequency.values)
                          DropdownMenuItem(
                            value: period,
                            child: Text(period.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _interestChargedPer = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('loan-duration'),
                            controller: _durationController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration:
                                dialogFieldDecoration(
                                  context,
                                  'Debt duration',
                                  hint: 'e.g. 12',
                                ).copyWith(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  helperText: _durationIsAutomatic
                                      ? 'Estimated from your balance, '
                                            'payment, and frequency.'
                                      : null,
                                ),
                            onChanged: (value) {
                              _durationWasEdited = value.trim().isNotEmpty;
                              if (!_durationWasEdited) {
                                _durationIsAutomatic = false;
                                _updateAutomaticDuration();
                              } else {
                                _durationIsAutomatic = false;
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<_LoanTermUnit>(
                            key: ValueKey(
                              'loan-duration-unit-${_durationUnit.name}',
                            ),
                            initialValue: _durationUnit,
                            isExpanded: true,
                            decoration: dialogFieldDecoration(
                              context,
                              'Duration unit',
                            ),
                            items: [
                              for (final unit in _LoanTermUnit.values)
                                DropdownMenuItem(
                                  value: unit,
                                  child: Text(unit.label),
                                ),
                            ],
                            onChanged: (unit) {
                              _durationUnit = unit ?? _durationUnit;
                              _refresh();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _dateField(
                      context,
                      label: 'Debt start date',
                      date: _loanStartDate,
                      onTap: () => _pickDate(loanStart: true),
                    ),
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
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

Widget _sectionTitle(BuildContext context, String text) => Text(
  text,
  style: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.bold,
    color: context.appColors.textPrimary,
  ),
);

Widget _dateField(
  BuildContext context, {
  required String label,
  required DateTime? date,
  required VoidCallback onTap,
}) => InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(12),
  child: InputDecorator(
    decoration: dialogFieldDecoration(context, label),
    child: Row(
      children: [
        Expanded(
          child: Text(date == null ? 'Choose a date' : formatShortDate(date)),
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
