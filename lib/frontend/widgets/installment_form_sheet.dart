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
import 'loan_form_sheet.dart';

/// Adds something bought on installment: a phone, an appliance, a credit
/// card installment, Buy now, pay later. Borrowed money has its own form
/// under Debts ([showLoanFormSheet]), which this one hands over to when the
/// name sounds like a loan.
///
/// Returns whether an installment was saved, and confirms the save so the
/// user knows it worked.
///
/// [name], [price] and [count] start it filled in, as from Voice Entry; the
/// user checks them before saving.
Future<bool> showInstallmentFormSheet(
  BuildContext context, {
  String? name,
  double? price,
  int? count,
}) async {
  String? asDebt;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => InstallmentFormSheet(
      initialName: name,
      initialPrice: price,
      initialCount: count,
      wallets: WalletService.watchWallets(),
      onAddAsDebt: (name) {
        asDebt = name;
        Navigator.pop(sheetContext);
      },
    ),
  );

  if (asDebt != null && context.mounted) {
    await showLoanFormSheet(context, name: asDebt);
    return false;
  }

  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Installment saved. Its payments are in your Bill Planner.',
        ),
        backgroundColor: appConfirmGreen,
      ),
    );
  }
  return saved == true;
}

/// What the form would save, handed to tests instead of Firestore.
class InstallmentDraft {
  const InstallmentDraft({
    required this.name,
    required this.category,
    required this.principal,
    required this.perPayment,
    required this.paymentCount,
    required this.frequency,
    required this.firstDueDate,
    this.lastPayment = 0,
    this.otherKind,
    this.paidWithWalletId,
    this.paidWithLabel,
  });

  final String name;
  final DebtCategory category;
  final double principal;
  final double perPayment;
  final int paymentCount;

  /// The last payment when it differs; zero when it doesn't.
  final double lastPayment;

  /// Installments are always monthly, but the plan records it.
  final PaymentFrequency frequency;

  /// First payment of the plan.
  final DateTime firstDueDate;

  /// The user's own kind, when they chose Other.
  final String? otherKind;

  /// The wallet the purchase was charged to, for tracking only.
  final String? paidWithWalletId;

  /// The card or account in the user's words, when it is not a wallet.
  final String? paidWithLabel;
}

class InstallmentFormSheet extends StatefulWidget {
  const InstallmentFormSheet({
    this.initialName,
    this.initialPrice,
    this.initialCount,
    this.wallets,
    this.today,
    this.onSave,
    this.onAddAsDebt,
    super.key,
  });

  /// What it starts filled in with.
  final String? initialName;
  final double? initialPrice;
  final int? initialCount;

  /// The cards and accounts to choose from. Empty in tests unless given.
  final Stream<List<Wallet>>? wallets;

  /// Closes this form and opens the Debts one with the name typed so far,
  /// for borrowed money started here by mistake.
  final void Function(String name)? onAddAsDebt;

  final DateTime? today;

  /// Replaces saving. Used by tests.
  final void Function(InstallmentDraft draft)? onSave;

  @override
  State<InstallmentFormSheet> createState() => _InstallmentFormSheetState();
}

class _InstallmentFormSheetState extends State<InstallmentFormSheet>
    with CheckAfterSave {
  /// Chosen by hand from Kind; until then the name decides it, among the
  /// kinds bought on installment. Loans belong under Debts.
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

  /// Installments are always paid once a month.
  static const _frequency = PaymentFrequency.monthly;

  late final DateTime _today = widget.today ?? DateTime.now();

  late final _nameController = TextEditingController(text: widget.initialName);
  late final _principalController = TextEditingController(
    text: _amountText(widget.initialPrice),
  );
  late final _countController = TextEditingController(
    text: widget.initialCount?.toString(),
  );
  final _downController = TextEditingController();
  final _otherKindController = TextEditingController();
  final _paidWithLabelController = TextEditingController();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? const Stream.empty();

  /// The wallet picked for "Card or account used", [_otherCard], or null.
  String? _paidWithChoice;
  String? _paidWithLabel;

  static const _otherCard = '__other_card__';

  static String _amountText(double? amount) =>
      amount == null ? '' : formatAmountInput(amount);

  @override
  void initState() {
    super.initState();
    // The summary card follows every keystroke, and the name picks the kind.
    for (final controller in [
      _nameController,
      _principalController,
      _countController,
      _downController,
      _paidWithLabelController,
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
      _countController,
      _downController,
      _otherKindController,
      _paidWithLabelController,
    ]) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;

  double get _price => _number(_principalController);

  /// What the payments are for: the cash price less any down payment made
  /// when it was bought.
  double get _financed {
    final left = _price - _number(_downController);
    return left > 0 ? left : 0;
  }

  /// Months typed. Required: the payments are worked out from them.
  int get _paymentCount => int.tryParse(_countController.text.trim()) ?? 0;

  /// Each payment and the last one, worked out from the price and the
  /// months so they add up to the price exactly.
  ({double perPayment, double lastPayment}) get _payments =>
      installmentPayments(total: _financed, count: _paymentCount);

  double get _perPayment => _payments.perPayment;

  double get _lastPayment => _payments.lastPayment;

  bool get _hasDifferentLastPayment =>
      _paymentCount > 1 && (_lastPayment - _perPayment).abs() > 0.005;

  /// The next payment falls due on the same day next month, or the month's
  /// last day where it is shorter.
  DateTime get _nextDueDate => nextMonthSameDay(_today);

  Debt get _preview => Debt(
    id: '',
    direction: DebtDirection.iOwe,
    name: _nameController.text,
    category: _category,
    principal: _financed,
    perPayment: _perPayment,
    paymentCount: _paymentCount,
    lastPayment: _hasDifferentLastPayment ? _lastPayment : 0,
    frequency: _frequency,
    firstDueDate: _nextDueDate,
    status: DebtStatus.active,
  );

  /// What stops the plan being saved as it stands, or null. Shown once Save
  /// has been tapped, and gone as soon as it is fixed.
  String? _problem() {
    final nameProblem = itemNameProblem(
      _nameController.text,
      maxLength: maxItemNameLength,
      empty: 'Give it a description.',
    );

    if (nameProblem != null) {
      return nameProblem;
    } else if (!isRecordableAmount(_price)) {
      return 'Enter the cash price.';
    } else if (_paymentCount < 1) {
      return 'Enter how many months.';
    } else if (_paymentCount > _mostPayments) {
      return 'Up to $_mostPayments months. Check the number on your '
          'contract.';
    } else if (_number(_downController) > 0 &&
        _number(_downController) >= _price) {
      return 'The down payment must be less than the cash price.';
    } else if (!isRecordableAmount(_perPayment)) {
      return 'The price is too small to split into $_paymentCount payments.';
    }
    return null;
  }

  /// Thirty years of monthly payments, more than any personal plan, so a
  /// slip such as 1200 for 12 is caught.
  static const _mostPayments = 360;

  void _save() {
    markTriedToSave();
    if (_problem() != null) return;

    final name = cleanText(_nameController.text);
    final otherCard = _paidWithChoice == _otherCard
        ? cleanText(_paidWithLabelController.text)
        : null;

    final draft = InstallmentDraft(
      name: name,
      category: _category,
      principal: _financed,
      perPayment: _perPayment,
      paymentCount: _paymentCount,
      lastPayment: _hasDifferentLastPayment ? _lastPayment : 0,
      frequency: _frequency,
      firstDueDate: _nextDueDate,
      otherKind: _category == DebtCategory.other
          ? cleanText(_otherKindController.text)
          : null,
      paidWithWalletId: _paidWithChoice == null || _paidWithChoice == _otherCard
          ? null
          : _paidWithChoice,
      paidWithLabel: otherCard ?? _paidWithLabel,
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
        firstDueDate: draft.firstDueDate,
        otherKind: draft.otherKind,
        paidWithWalletId: draft.paidWithWalletId,
        paidWithLabel: draft.paidWithLabel,
      );
    }

    Navigator.pop(context, true);
  }

  /// Any card or account the purchase was charged to. Recorded only, so the
  /// user can see later which one it was; it never moves money.
  Widget _paidWithPicker() {
    return StreamBuilder<List<Wallet>>(
      stream: _wallets,
      builder: (context, snapshot) {
        final wallets = [
          for (final wallet in snapshot.data ?? const <Wallet>[])
            if (!wallet.archived) wallet,
        ];
        final selected = _paidWithChoice ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('installment-paid-with'),
              initialValue: selected,
              isExpanded: true,
              decoration:
                  dialogFieldDecoration(
                    context,
                    'Card or account used',
                    helper:
                        'Optional. Only written down, so you can see what it '
                        'was charged to.',
                  ).copyWith(
                    helperMaxLines: 3,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Not recorded')),
                for (final wallet in wallets)
                  DropdownMenuItem(value: wallet.id, child: Text(wallet.name)),
                const DropdownMenuItem(
                  value: _otherCard,
                  child: Text('Another card or account'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  if (value == null || value.isEmpty) {
                    _paidWithChoice = null;
                    _paidWithLabel = null;
                  } else if (value == _otherCard) {
                    _paidWithChoice = _otherCard;
                    _paidWithLabel = null;
                  } else {
                    _paidWithChoice = value;
                    _paidWithLabel = wallets
                        .where((wallet) => wallet.id == value)
                        .firstOrNull
                        ?.name;
                  }
                });
              },
            ),
            if (_paidWithChoice == _otherCard) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('installment-paid-with-label'),
                controller: _paidWithLabelController,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                inputFormatters: const [SafeTextFormatter()],
                decoration: dialogFieldDecoration(
                  context,
                  'Card or account',
                  hint: 'e.g. BPI credit card',
                ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
              ),
            ],
          ],
        );
      },
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
                    key: const Key('installment-description'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: maxItemNameLength,
                    inputFormatters: const [SafeTextFormatter()],
                    decoration:
                        dialogFieldDecoration(
                          context,
                          'Description',
                          hint: 'e.g. iPhone 15 from Globe',
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
                  _paidWithPicker(),
                  const SizedBox(height: 16),
                  AmountField(
                    key: const Key('installment-price'),
                    controller: _principalController,
                    label: 'Cash price',
                    hint: 'e.g. 12,000',
                    alwaysShowHint: true,
                    autofocus: false,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('installment-months'),
                    controller: _countController,
                    keyboardType: TextInputType.number,
                    // Whole months only, never a sign, a point or a pasted
                    // paragraph.
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration:
                        dialogFieldDecoration(
                          context,
                          'How many months',
                          hint: 'e.g. 12',
                          helper:
                              'Each payment is worked out from the price and '
                              'the months.',
                        ).copyWith(
                          helperMaxLines: 3,
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                  ),
                  // Only matters with a cash price, so it waits for one.
                  if (_price > 0) ...[
                    const SizedBox(height: 16),
                    AmountField(
                      key: const Key('installment-down-payment'),
                      controller: _downController,
                      label: 'Down payment (optional)',
                      hint: 'e.g. 2,000',
                      helper: 'If you paid part of the price upfront.',
                      alwaysShowHint: true,
                      autofocus: false,
                    ),
                  ],
                  const SizedBox(height: 16),
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
                  if (_category == DebtCategory.other) ...[
                    const SizedBox(height: 16),
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
                  ],
                  const SizedBox(height: 16),
                  _SummaryCard(debt: _preview),
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

/// What the plan comes to, once the amounts are in: how many payments and
/// what each one is. The shop quoted the price, so nothing is added on top.
/// It sits under the fields it adds up, and before anything is typed shows
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
              'You will pay ${formatPeso(debt.totalPayable)} in total.',
              style: body,
            ),
            if (debt.hasDifferentLastPayment) ...[
              const SizedBox(height: 4),
              Text(
                'The last payment is ${formatPeso(debt.finalPayment)}, to '
                'make the payments add up exactly.',
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
