import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/models/debt.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/debt_service.dart';
import '../../backend/services/wallet_service.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import '../../backend/utils/text_limits.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/amount_input_formatter.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'goal_funding_picker.dart' show fundingWalletKind;
import 'loan_form_sheet.dart';
import 'wallet_split_picker.dart' show isCashOnHand;

/// Adds something bought on installment: a phone, an appliance, a credit
/// card installment, Buy now, pay later. Borrowed money has its own form
/// under Debts ([showLoanFormSheet]), which this one hands over to when the
/// name sounds like a loan.
///
/// Returns whether an installment was saved, and confirms the save so the
/// user knows it worked.
///
/// [existing] reopens it to correct a plan, which is only possible until a
/// payment has been made on it. It then saves through
/// [DebtService.updateInstallment], which works every payment out again.
///
/// [name], [price] and [count] start it filled in, as from Voice Entry; the
/// user checks them before saving.
Future<bool> showInstallmentFormSheet(
  BuildContext context, {
  String? name,
  double? price,
  int? count,
  Debt? existing,
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
      SnackBar(
        content: Text(
          existing == null
              ? 'Installment saved. Its payments are in your Bill Planner.'
              : 'Installment updated. Its payments were worked out again.',
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

  /// Its name when the plan was saved, so the card can show it without
  /// loading the wallets.
  final String? paidWithLabel;
}

class InstallmentFormSheet extends StatefulWidget {
  const InstallmentFormSheet({
    this.initialName,
    this.initialPrice,
    this.initialCount,
    this.existing,
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

  /// A plan already saved, to correct. Filled in from it, saved through
  /// [DebtService.updateInstallment], and only until a payment has been
  /// made on it.
  final Debt? existing;

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

  /// Whether it is open on a plan already saved, to correct it.
  bool get _editing => widget.existing != null;

  late final DateTime _today = widget.today ?? DateTime.now();

  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? widget.initialName,
  );
  late final _principalController = TextEditingController(
    text: _amountText(widget.initialPrice ?? widget.existing?.principal),
  );
  late final _countController = TextEditingController(
    text: (widget.initialCount ?? widget.existing?.paymentCount)?.toString(),
  );
  final _downController = TextEditingController();
  final _perPaymentController = TextEditingController();
  late final _otherKindController = TextEditingController(
    text: widget.existing?.otherKind,
  );

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? const Stream.empty();

  /// The wallet picked for "Wallet used", or null. Editing a plan keeps the
  /// one it was saved with until another is picked.
  String? _paidWithChoice;

  /// Its name, written down with the plan so the card can show it.
  String? _paidWithLabel;

  static String _amountText(double? amount) =>
      amount == null ? '' : formatAmountInput(amount);

  @override
  void initState() {
    super.initState();
    // Editing a plan starts it as it was saved, so nothing is lost by
    // opening it just to look.
    _pickedCategory = widget.existing?.category;
    _paidWithChoice = widget.existing?.paidWithWalletId;
    _paidWithLabel = widget.existing?.paidWithLabel;
    // The summary card follows every keystroke, and the name picks the kind.
    for (final controller in [
      _nameController,
      _principalController,
      _countController,
      _downController,
    ]) {
      controller.addListener(_refresh);
    }
    _syncPerPayment();
    recheckWhenChanged(_nameController);
  }

  /// The each-payment field is worked out, not typed: it follows the price,
  /// the months and any down payment as they change.
  void _refresh() {
    _syncPerPayment();
    setState(() {});
  }

  /// Writes the worked-out payment into its field, grouped with commas like
  /// the amounts the user types.
  void _syncPerPayment() {
    final each = _perPayment;
    final text = each <= 0
        ? ''
        : const ThousandsSeparatorFormatter()
              .formatEditUpdate(
                TextEditingValue.empty,
                TextEditingValue(text: formatAmountInput(each)),
              )
              .text;
    if (_perPaymentController.text == text) return;
    _perPaymentController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _principalController,
      _countController,
      _downController,
      _otherKindController,
      _perPaymentController,
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

  /// The plan starts the day the form is filled in: the installment is
  /// already happening, and writing it down here is how the tracking begins.
  /// Every payment after this first one falls due on the same day of the
  /// month, the month's last day where that month is shorter.
  ///
  /// Editing a plan keeps the date it was saved with: its payments are
  /// already laid out from it, and only what is owed on them can change.
  DateTime get _firstDueDate => widget.existing?.firstDueDate ?? _today;

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
    firstDueDate: _firstDueDate,
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

  Future<void> _save() async {
    markTriedToSave();
    if (_problem() != null) return;

    final name = cleanText(_nameController.text);

    final draft = InstallmentDraft(
      name: name,
      category: _category,
      principal: _financed,
      perPayment: _perPayment,
      paymentCount: _paymentCount,
      lastPayment: _hasDifferentLastPayment ? _lastPayment : 0,
      frequency: _frequency,
      firstDueDate: _firstDueDate,
      otherKind: _category == DebtCategory.other
          ? cleanText(_otherKindController.text)
          : null,
      paidWithWalletId: _paidWithChoice,
      paidWithLabel: _paidWithLabel,
    );

    final existing = widget.existing;

    if (widget.onSave != null) {
      widget.onSave!(draft);
    } else if (existing == null) {
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
    } else {
      // Worked out again from what was changed. It can still be refused if a
      // payment was made while the form was open, and then nothing is
      // written: from that point the plan is a record of what was agreed.
      final saved = await DebtService.updateInstallment(
        from: existing,
        name: draft.name,
        category: draft.category,
        principal: draft.principal,
        perPayment: draft.perPayment,
        paymentCount: draft.paymentCount,
        lastPayment: draft.lastPayment,
        otherKind: draft.otherKind,
        paidWithWalletId: draft.paidWithWalletId,
        paidWithLabel: draft.paidWithLabel,
      );

      if (!mounted) return;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A payment has already been made on this plan, so it can no '
              'longer be edited.',
            ),
            backgroundColor: appDangerRed,
          ),
        );
      }
      Navigator.pop(context, saved);
      return;
    }

    Navigator.pop(context, true);
  }

  /// The wallet the purchase was charged to, picked the way paying always
  /// looks: Cash on Hand or Cash in Bank first, then the wallets under it,
  /// as any sheet that moves money asks. Recorded only, so they can see
  /// later which one it was; it never moves money.
  Widget _paidWithPicker() {
    return StreamBuilder<List<Wallet>>(
      stream: _wallets,
      builder: (context, snapshot) {
        final wallets = [
          for (final wallet in snapshot.data ?? const <Wallet>[])
            if (!wallet.archived &&
                (isCashOnHand(wallet) ||
                    (wallet.isCashInBank && !wallet.isDemandDeposit)))
              wallet,
        ];
        final colors = context.appColors;

        // Start on the user's first wallet rather than an empty field. If the
        // one chosen is no longer there, fall back to the first. A list with
        // nothing in it leaves the choice as it stands, so a plan being
        // edited keeps the wallet it was saved with rather than losing it.
        final chosen =
            wallets
                .where((wallet) => wallet.id == _paidWithChoice)
                .firstOrNull ??
            wallets.firstOrNull;
        if (chosen?.id != _paidWithChoice && wallets.isNotEmpty) {
          _paidWithChoice = chosen?.id;
          _paidWithLabel = chosen?.name;
        }

        if (wallets.isEmpty) {
          return Column(
            key: const Key('installment-paid-with'),
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
        // The group of the wallet now chosen is the one showing. Jumping to
        // the other group takes its first wallet, as the list always had one
        // ready; the cards under it can change that.
        final current = chosen ?? wallets.first;
        final showingBank = !isCashOnHand(current);
        final group = showingBank ? bankWallets : cashWallets;

        void pick(Wallet wallet) {
          setState(() {
            _paidWithChoice = wallet.id;
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
                key: Key('installment-paid-with-${bank ? 'bank' : 'cash'}'),
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
          key: const Key('installment-paid-with'),
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
              _paidWithCard(context, wallet, picked: wallet.id == current.id),
            const SizedBox(height: 10),
            Text(
              'Only written down, so you can see which wallet it was '
              'charged to.',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        );
      },
    );
  }

  /// One wallet to charge the purchase to, shown like the paying-from cards
  /// everywhere: its icon, its name, and its kind with its balance.
  Widget _paidWithCard(
    BuildContext context,
    Wallet wallet, {
    required bool picked,
  }) {
    final colors = context.appColors;
    final pickedStyle = picked
        ? BoxDecoration(
            color: colors.primaryTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.primaryText, width: 1.5),
          )
        : BoxDecoration(
            color: colors.pageBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          );

    return GestureDetector(
      onTap: () {
        setState(() {
          _paidWithChoice = wallet.id;
          _paidWithLabel = wallet.name;
        });
      },
      child: Container(
        key: ValueKey('installment-paid-with-wallet-${wallet.id}'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: pickedStyle,
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
                    _editing ? 'Edit Installment' : 'Add Installment',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Said up front, so a wrong entry is fixed here rather
                  // than the plan being deleted and added again.
                  DialogNote(
                    key: const Key('installment-edit-note'),
                    text:
                        'You can fix this plan any time before a payment is '
                        'made on it${_editing ? ' — every payment is worked out again from '
                                  'what you change' : ' — its payments are worked out from what you '
                                  'enter'}. Once a payment has been made on '
                        'it, it can no longer be edited.',
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
                  // What it is. The description already suggests the kind, so
                  // this shows the guess and lets it be changed.
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
                  // Where it was charged: written down only, so the user can
                  // see later which wallet it was. It never moves money.
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
                  // Worked out, never typed: it fills in as soon as the cash
                  // price and the months are both there.
                  AmountField(
                    key: const Key('installment-each-payment'),
                    controller: _perPaymentController,
                    label: 'Each payment',
                    hint: 'e.g. 2,000',
                    helper:
                        'Cash price less any down payment, split over the '
                        'months.',
                    alwaysShowHint: true,
                    enabled: false,
                    autofocus: false,
                  ),
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
                      child: Text(
                        _editing ? 'Save Changes' : 'Save Installment',
                        style: const TextStyle(
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

/// What the plan comes to, once the amounts are in: the total and when the
/// last payment falls due. Each payment has its own field above, so this
/// does not repeat it. The shop quoted the price, so nothing is added on top.
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
              'You will pay ${formatPeso(debt.totalPayable)} in total.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            if (last != null) ...[
              const SizedBox(height: 6),
              Text(
                '${debt.paymentCount} '
                '${debt.paymentCount == 1 ? 'payment' : 'payments'}, the last '
                'on ${formatShortDate(last)}.',
                style: body,
              ),
            ],
            if (debt.hasDifferentLastPayment) ...[
              const SizedBox(height: 4),
              Text(
                'The last payment is ${formatPeso(debt.finalPayment)}, so the '
                'payments add up exactly.',
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
