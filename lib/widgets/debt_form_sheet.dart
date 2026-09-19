import 'package:flutter/material.dart';

import '../models/debt.dart';
import '../models/wallet.dart';
import '../services/debt_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';

/// Adds an installment the user pays, or money someone owes the user.
///
/// Returns which list the new entry went to, or null if nothing was saved,
/// and confirms the save so the user knows it worked.
Future<DebtDirection?> showDebtFormSheet(
  BuildContext context, {
  DebtDirection direction = DebtDirection.iOwe,
}) async {
  final saved = await showModalBottomSheet<DebtDirection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DebtFormSheet(initialDirection: direction),
  );

  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved == DebtDirection.iOwe
              ? 'Installment saved. Its payments are in your Bill Planner.'
              : 'Saved to Owed to me.',
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
    required this.payFromWalletId,
    this.lastPayment = 0,
    required this.movedWalletId,
    required this.note,
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
  final String? payFromWalletId;

  /// Where borrowed money arrived, or where lent money came from.
  final String? movedWalletId;
  final String? note;
}

class DebtFormSheet extends StatefulWidget {
  const DebtFormSheet({
    this.initialDirection = DebtDirection.iOwe,
    this.wallets,
    this.today,
    this.onSave,
    super.key,
  });

  final DebtDirection initialDirection;

  /// Replaces the live wallet list. Used by tests.
  final Stream<List<Wallet>>? wallets;
  final DateTime? today;

  /// Replaces saving. Used by tests.
  final void Function(DebtDraft draft)? onSave;

  @override
  State<DebtFormSheet> createState() => _DebtFormSheetState();
}

class _DebtFormSheetState extends State<DebtFormSheet> {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  late DebtDirection _direction = widget.initialDirection;
  DebtCategory _category = DebtCategory.gadget;
  PaymentFrequency _frequency = PaymentFrequency.monthly;
  late final DateTime _today = widget.today ?? DateTime.now();
  late DateTime? _date = DateTime(_today.year, _today.month + 1, _today.day);

  final _nameController = TextEditingController();
  final _principalController = TextEditingController();
  final _perPaymentController = TextEditingController();
  final _countController = TextEditingController();
  final _lastController = TextEditingController();
  final _noteController = TextEditingController();

  String? _payFromWalletId;
  // Lent money almost always leaves a wallet, so that starts on. An
  // installment is often a gadget bought on credit, where no cash arrives.
  late bool _movedMoney = widget.initialDirection == DebtDirection.owedToMe;
  String? _movedWalletId;
  String? _error;

  bool get _iOwe => _direction == DebtDirection.iOwe;

  @override
  void initState() {
    super.initState();
    // The summary card follows every keystroke.
    for (final controller in [
      _principalController,
      _perPaymentController,
      _countController,
      _lastController,
    ]) {
      controller.addListener(_refresh);
    }
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
      _noteController,
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

  /// Payments typed, or worked out from the amounts when left blank.
  int get _paymentCount {
    if (_countTyped) return int.parse(_countController.text.trim());
    return paymentsToCover(
      _number(_principalController),
      _number(_perPaymentController),
    );
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
      _number(_principalController),
      _number(_perPaymentController),
      _paymentCount,
    );
  }

  Debt get _preview => Debt(
    id: '',
    direction: _direction,
    name: _nameController.text,
    category: _category,
    principal: _number(_principalController),
    perPayment: _number(_perPaymentController),
    paymentCount: _paymentCount,
    lastPayment: _lastPayment,
    frequency: _frequency,
    firstDueDate: _date,
    status: DebtStatus.active,
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

  static double _balanceOf(List<Wallet> wallets, String? id) {
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet.balance;
    }
    return 0;
  }

  static String _nameOf(List<Wallet> wallets, String? id) {
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet.name;
    }
    return 'That wallet';
  }

  void _save(List<Wallet> wallets) {
    final name = _nameController.text.trim();
    final principal = _number(_principalController);
    final perPayment = _number(_perPaymentController);
    final movedWallet = _movedMoney
        ? (_movedWalletId ?? defaultWalletId(wallets))
        : null;

    final String? problem;
    if (name.isEmpty) {
      problem = _iOwe ? 'Give it a name.' : 'Who owes you?';
    } else if (principal <= 0) {
      problem = _iOwe ? 'Enter the amount borrowed.' : 'Enter how much.';
    } else if (_iOwe && perPayment <= 0) {
      problem = 'Enter how much each payment is.';
    } else if (_iOwe && _paymentCount < 1) {
      problem = 'Enter how many payments.';
    } else if (_iOwe && _date == null) {
      problem = 'Choose when the first payment is due.';
    } else if (_iOwe && _preview.totalPayable + 0.005 < principal) {
      problem =
          'Those payments add up to ${formatPeso(_preview.totalPayable)}, '
          'less than the ${formatPeso(principal)} borrowed.';
    } else if (_movedMoney && movedWallet == null) {
      problem = 'Add a wallet first.';
    } else if (!_iOwe &&
        _movedMoney &&
        _balanceOf(wallets, movedWallet) + 0.005 < principal) {
      problem =
          '${_nameOf(wallets, movedWallet)} only holds '
          '${formatPeso(_balanceOf(wallets, movedWallet))}.';
    } else {
      problem = null;
    }

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final draft = DebtDraft(
      direction: _direction,
      name: name,
      category: _iOwe ? _category : DebtCategory.familyFriend,
      principal: principal,
      perPayment: perPayment,
      paymentCount: _paymentCount,
      lastPayment: _preview.hasDifferentLastPayment ? _preview.finalPayment : 0,
      frequency: _frequency,
      firstDueDate: _date,
      payFromWalletId: _payFromWalletId ?? defaultWalletId(wallets),
      movedWalletId: movedWallet,
      note: _noteController.text,
    );

    if (widget.onSave != null) {
      widget.onSave!(draft);
    } else if (_iOwe) {
      DebtService.addInstallment(
        name: draft.name,
        category: draft.category,
        principal: draft.principal,
        perPayment: draft.perPayment,
        paymentCount: draft.paymentCount,
        lastPayment: draft.lastPayment,
        frequency: draft.frequency,
        firstDueDate: draft.firstDueDate!,
        payFromWalletId: draft.payFromWalletId,
        receivedIntoWalletId: draft.movedWalletId,
        note: draft.note,
      );
    } else {
      DebtService.addLent(
        name: draft.name,
        amount: draft.principal,
        dueDate: draft.firstDueDate,
        lentFromWalletId: draft.movedWalletId,
        note: draft.note,
      );
    }

    Navigator.pop(context, draft.direction);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data ?? const <Wallet>[];

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
                    _iOwe ? 'Add Installment' : 'Add Money Owed to You',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<DebtDirection>(
                      segments: const [
                        ButtonSegment(
                          value: DebtDirection.iOwe,
                          label: Text('I owe'),
                        ),
                        ButtonSegment(
                          value: DebtDirection.owedToMe,
                          label: Text('Owed to me'),
                        ),
                      ],
                      selected: {_direction},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) => setState(() {
                        _direction = value.first;
                        _error = null;
                        _movedMoney = !_iOwe;
                        _date = _iOwe
                            ? DateTime(
                                _today.year,
                                _today.month + 1,
                                _today.day,
                              )
                            : null;
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_iOwe) ...[
                    _SummaryCard(debt: _preview),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 40,
                    decoration:
                        dialogFieldDecoration(
                          context,
                          _iOwe ? 'Name' : 'Who owes you?',
                          hint: _iOwe ? 'e.g. Phone, SSS loan' : 'e.g. Ana',
                        ).copyWith(
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                  ),
                  if (_iOwe) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<DebtCategory>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: dialogFieldDecoration(context, 'Kind'),
                      items: [
                        for (final category in DebtCategory.values)
                          DropdownMenuItem(
                            value: category,
                            child: Text(category.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _category = value ?? _category),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AmountField(
                    controller: _principalController,
                    label: _iOwe ? 'Amount borrowed' : 'Amount',
                    hint: _iOwe ? 'e.g. 12,000' : 'e.g. 500',
                    helper: _iOwe
                        ? 'The price or loan amount, before any interest.'
                        : null,
                    alwaysShowHint: true,
                    autofocus: false,
                  ),
                  if (_iOwe) ...[
                    const SizedBox(height: 14),
                    const _ContractGuide(),
                    const SizedBox(height: 14),
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
                            decoration:
                                dialogFieldDecoration(
                                  context,
                                  'Each payment',
                                  helper: 'Every month or week',
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
                            decoration:
                                dialogFieldDecoration(
                                  context,
                                  'Payments',
                                  hint: 'e.g. 12',
                                  helper: 'Blank = auto',
                                ).copyWith(
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _lastController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          dialogFieldDecoration(
                            context,
                            'Last payment (optional)',
                            helper:
                                "Only if your contract's last payment is "
                                'different. Example: a ₱10,000 installment '
                                'paid as ₱3,000 × 3 months, then ₱1,000 on '
                                'the 4th month → type 1,000. Leave it blank '
                                'when all payments are the same.',
                          ).copyWith(
                            prefixText: '₱ ',
                            hintText: 'Same as the rest',
                            helperMaxLines: 4,
                          ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PaymentFrequency>(
                      initialValue: _frequency,
                      isExpanded: true,
                      decoration: dialogFieldDecoration(context, 'How often'),
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
                  ],
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: dialogFieldDecoration(
                        context,
                        _iOwe
                            ? 'First payment due'
                            : 'When they will pay back (optional)',
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _date == null
                                  ? 'No date'
                                  : formatShortDate(_date!),
                            ),
                          ),
                          if (!_iOwe && _date != null)
                            IconButton(
                              tooltip: 'Remove date',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _date = null),
                            )
                          else
                            Image.asset(
                              'assets/icons/icons8-calendar-96.png',
                              width: 22,
                              height: 22,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (wallets.isNotEmpty) ...[
                    if (_iOwe) ...[
                      const SizedBox(height: 16),
                      WalletPicker(
                        wallets: wallets,
                        selectedId:
                            _payFromWalletId ?? defaultWalletId(wallets),
                        label: 'Usually paid from',
                        onChanged: (value) =>
                            setState(() => _payFromWalletId = value),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _movedMoney,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _iOwe
                            ? 'I received this money in a wallet'
                            : 'It came out of one of my wallets',
                      ),
                      subtitle: Text(
                        _iOwe
                            ? 'For a cash loan. Leave off for a gadget bought '
                                  'on installment.'
                            : 'The wallet goes down now, and back up when '
                                  'you are paid back. Turn off for money lent '
                                  'before you used FinAssist.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onChanged: (value) => setState(() => _movedMoney = value),
                    ),
                    if (_movedMoney)
                      WalletPicker(
                        wallets: wallets,
                        selectedId: _movedWalletId ?? defaultWalletId(wallets),
                        label: _iOwe ? 'Received into' : 'Taken from',
                        onChanged: (value) =>
                            setState(() => _movedWalletId = value),
                      ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _noteController,
                    maxLength: 80,
                    decoration: dialogFieldDecoration(
                      context,
                      'Notes (optional)',
                    ),
                  ),
                  if (_error != null) ...[
                    Text(
                      _error!,
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
                      onPressed: () => _save(wallets),
                      style: confirmButtonStyle(),
                      child: Text(
                        _iOwe ? 'Save Installment' : 'Save',
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

/// Where the numbers come from, with an example, for anyone unsure what
/// "each payment" and "payments" mean.
class _ContractGuide extends StatelessWidget {
  const _ContractGuide();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset('assets/icons/icons8-idea-96.png', width: 20, height: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Copy these from your contract. "₱1,500 a month for 12 months" '
              'means Each payment 1,500 and Payments 12. No set number of '
              'payments? Leave Payments blank to pay back just what you '
              'borrowed.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: colors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Updates as the form is filled in: what is borrowed, each payment, how long
/// it runs, and what it costs on top.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.debt});

  final Debt debt;

  @override
  Widget build(BuildContext context) {
    final last = debt.lastDueDate;
    final ready = debt.principal > 0 && debt.perPayment > 0;

    Widget figure(String label, String value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appPrimaryBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              figure('Borrowed', ready ? formatPeso(debt.principal) : '—'),
              figure(
                debt.frequency == PaymentFrequency.weekly
                    ? 'Each week'
                    : 'Each month',
                ready ? formatPeso(debt.perPayment) : '—',
              ),
              figure(
                'Payments',
                debt.paymentCount > 0 ? '${debt.paymentCount}' : '—',
              ),
            ],
          ),
          if (ready && debt.paymentCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Total you will pay: ${formatPeso(debt.totalPayable)}'
              '${debt.extraCost > 0 ? ' · ${formatPeso(debt.extraCost)} more than you borrowed' : ''}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            if (last != null) ...[
              const SizedBox(height: 4),
              Text(
                debt.hasDifferentLastPayment
                    ? 'Last payment ${formatPeso(debt.finalPayment)} on '
                          '${formatShortDate(last)}'
                    : 'Last payment ${formatShortDate(last)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
