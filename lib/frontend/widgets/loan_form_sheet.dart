import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/models/debt.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/debt_service.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import '../../backend/utils/text_limits.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'goal_funding_picker.dart' show fundingWalletKind;
import 'wallet_split_picker.dart' show isCashOnHand;

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
    this.firstInterestChargeDate,
    this.paidWithWalletId,
    this.paidWithLabel,
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
  final DateTime? firstInterestChargeDate;
  final String? paidWithWalletId;
  final String? paidWithLabel;
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
    builder: (context) => LoanFormSheet(
      name: name,
      amount: amount,
      count: count,
      wallets: WalletService.watchWallets(),
    ),
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
    this.wallets,
    this.onSave,
    super.key,
  });

  final String? name;
  final double? amount;
  final int? count;
  final DateTime? today;
  final Stream<List<Wallet>>? wallets;
  final void Function(LoanDraft draft)? onSave;

  @override
  State<LoanFormSheet> createState() => _LoanFormSheetState();
}

class _LoanFormSheetState extends State<LoanFormSheet> with CheckAfterSave {
  late final DateTime _today = widget.today ?? DateTime.now();
  DateTime? _nextPaymentDate;
  DateTime? _loanStartDate;
  DateTime? _firstInterestChargeDate;

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
  String? _paidWithWalletId;
  String? _paidWithLabel;
  Stream<List<Wallet>>? get _wallets => widget.wallets;
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

  Future<void> _pickInterestDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstInterestChargeDate ?? _today,
      firstDate: DateTime(_today.year - 100),
      lastDate: DateTime(_today.year + 50),
    );
    if (picked == null) return;
    setState(() => _firstInterestChargeDate = picked);
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
    if (_fixedInterestAmount != null && _firstInterestChargeDate == null) {
      return 'Choose the next interest charge date.';
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
      firstInterestChargeDate: _fixedInterestAmount == null
          ? null
          : _firstInterestChargeDate,
      loanDuration: _duration,
      loanDurationUnit: _duration == null ? null : _durationUnit.name,
      loanStartDate: _loanStartDate,
      balanceBasedSchedule: true,
      otherKind: _kind == DebtCategory.otherLoan
          ? cleanText(_otherKindController.text)
          : null,
      paidWithWalletId: _paidWithWalletId,
      paidWithLabel: _paidWithLabel,
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
        firstInterestChargeDate: draft.firstInterestChargeDate,
        loanDuration: draft.loanDuration,
        loanDurationUnit: draft.loanDurationUnit,
        loanStartDate: draft.loanStartDate,
        balanceBasedSchedule: draft.balanceBasedSchedule,
        paidWithWalletId: draft.paidWithWalletId,
        paidWithLabel: draft.paidWithLabel,
        otherKind: draft.otherKind,
      );
    }
    Navigator.pop(context, true);
  }

  Widget _walletPicker() {
    final walletsStream = _wallets;
    if (walletsStream == null) return const SizedBox.shrink();
    return StreamBuilder<List<Wallet>>(
      stream: walletsStream,
      builder: (context, snapshot) {
        final wallets = [
          for (final wallet in snapshot.data ?? const <Wallet>[])
            if (!wallet.archived &&
                (isCashOnHand(wallet) ||
                    (wallet.isCashInBank && !wallet.isDemandDeposit)))
              wallet,
        ];
        if (wallets.isNotEmpty &&
            !wallets.any((wallet) => wallet.id == _paidWithWalletId)) {
          _paidWithWalletId = wallets.first.id;
          _paidWithLabel = wallets.first.name;
        }
        final colors = context.appColors;

        if (wallets.isEmpty) {
          return Column(
            key: const Key('loan-paid-with'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wallet used',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const DialogNote(text: 'Add a wallet first, under Accounts.'),
            ],
          );
        }

        final cashWallets = [
          for (final wallet in wallets)
            if (isCashOnHand(wallet)) wallet,
        ];
        final bankWallets = [
          for (final wallet in wallets)
            if (!isCashOnHand(wallet)) wallet,
        ];
        final current = wallets.firstWhere(
          (wallet) => wallet.id == _paidWithWalletId,
        );
        final showingBank = !isCashOnHand(current);
        final group = showingBank ? bankWallets : cashWallets;

        void pick(Wallet wallet) {
          setState(() {
            _paidWithWalletId = wallet.id;
            _paidWithLabel = wallet.name;
          });
        }

        Widget groupTile({required bool bank}) {
          final walletsThere = bank ? bankWallets : cashWallets;
          final picked = showingBank == bank;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: walletsThere.isEmpty
                  ? null
                  : () {
                      if (walletsThere.any(
                        (wallet) => wallet.id == current.id,
                      )) {
                        return;
                      }
                      pick(walletsThere.first);
                    },
              child: Container(
                key: Key('loan-paid-with-${bank ? 'bank' : 'cash'}'),
                constraints: const BoxConstraints(minHeight: 76),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: picked ? colors.primaryTint : colors.pageBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: picked ? colors.primaryText : colors.border,
                    width: picked ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      bank
                          ? WalletType.bank.iconAsset
                          : WalletType.cash.iconAsset,
                      width: 26,
                      height: 26,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bank ? 'Cash in Bank' : 'Cash on Hand',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: picked ? FontWeight.bold : FontWeight.w600,
                        color: walletsThere.isEmpty
                            ? colors.textBody.withValues(alpha: 0.45)
                            : colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          key: const Key('loan-paid-with'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wallet used',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  groupTile(bank: false),
                  const SizedBox(width: 8),
                  groupTile(bank: true),
                ],
              ),
            ),
            for (final wallet in group)
              _paidWithCard(wallet, picked: wallet.id == current.id),
            const SizedBox(height: 10),
            Text(
              'Payments start from this wallet. You can change it when you pay.',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        );
      },
    );
  }

  Widget _paidWithCard(Wallet wallet, {required bool picked}) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: () {
        setState(() {
          _paidWithWalletId = wallet.id;
          _paidWithLabel = wallet.name;
        });
      },
      child: Container(
        key: ValueKey('loan-paid-with-wallet-${wallet.id}'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: picked ? colors.primaryTint : colors.pageBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: picked ? colors.primaryText : colors.border,
            width: picked ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Image.asset(wallet.iconAsset, width: 28, height: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wallet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    '${fundingWalletKind(wallet)} · '
                    '${formatPeso(wallet.balance)} balance',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                key: const Key('loan-next-payment-date'),
                label: 'Next payment date',
                date: _nextPaymentDate,
                onTap: () => _pickDate(loanStart: false),
              ),
              const SizedBox(height: 12),
              _walletPicker(),
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
                          'The lender charges this exact amount each period. '
                          'Interest is recorded separately from payments.',
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
                    if (_fixedInterestAmount != null &&
                        _interestChargedPer != null) ...[
                      const SizedBox(height: 12),
                      _dateField(
                        context,
                        key: const Key('loan-first-interest-date'),
                        label: 'Next Interest Charge Date',
                        date: _firstInterestChargeDate,
                        onTap: _pickInterestDueDate,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('use-next-payment-for-interest'),
                          onPressed: _nextPaymentDate == null
                              ? null
                              : () => setState(
                                  () => _firstInterestChargeDate =
                                      _nextPaymentDate,
                                ),
                          child: const Text('Use Next Payment Date'),
                        ),
                      ),
                    ],
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
  Key? key,
  required String label,
  required DateTime? date,
  required VoidCallback onTap,
}) => InkWell(
  key: key,
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
