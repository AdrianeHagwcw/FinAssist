import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/amount_input_formatter.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import 'dialog_kit.dart';
import 'goal_funding_picker.dart'
    show
        fundingWalletKind,
        goalFundingProblem,
        goalFundingRoom,
        goalMoneyInterestNote;
import 'wallet_picker.dart';

/// Cash on hand, cash in bank, or both: asked first wherever money comes out
/// of or goes into the user's wallets, so only those wallets are shown.
enum WalletGroupChoice {
  cash('Cash on Hand'),
  bank('Cash in Bank'),
  both('Both');

  const WalletGroupChoice(this.label);

  final String label;

  /// The same icons the wallets use, so a choice matches the accounts it
  /// opens. Both shows the two together.
  List<String> get iconAssets => switch (this) {
    WalletGroupChoice.cash => [WalletType.cash.iconAsset],
    WalletGroupChoice.bank => [WalletType.bank.iconAsset],
    WalletGroupChoice.both => [
      WalletType.cash.iconAsset,
      WalletType.bank.iconAsset,
    ],
  };

  bool get showsCash => this != WalletGroupChoice.bank;
  bool get showsBank => this != WalletGroupChoice.cash;
}

/// Cash wallets are cash on hand. Every other account, bank, e-wallet or
/// savings record, is cash in bank: the same split Home makes.
bool isCashOnHand(Wallet wallet) => wallet.type == WalletType.cash;

/// What the money in a [WalletSplitPicker] is doing. It decides which
/// wallets are offered and how much each one can give or take.
enum SplitPurpose {
  /// Money already saved for a goal, claimed from each account. Nothing
  /// moves, and savings records can hold it too.
  goal,

  /// Money leaving spending wallets for savings or a goal. Each wallet gives
  /// only what it has free.
  giving,

  /// Money paid out of spending wallets, for a bill or an expense. Each
  /// wallet pays only what it has free, fee included.
  paying,

  /// Money coming in: income, a transfer, savings taken out. Any wallet can
  /// take any amount; only the total is checked.
  receiving,
}

/// Whether [amount] asks for more than [room], the money free in an account.
bool exceedsFree(double amount, double room) => amount > room + 0.005;

/// The most [wallet] can give or take for [purpose]: what it has free once
/// [goals] are counted, plus anything arriving in it in the same step, such
/// as income being recorded. Money coming in has no limit per wallet.
double splitRoom(
  SplitPurpose purpose,
  Wallet wallet,
  Iterable<Goal> goals, {
  Map<String, double> adding = const {},
  Map<String, double>? limits,
}) {
  // A limit set for the wallet, such as what a goal holds in it.
  if (limits != null) return limits[wallet.id] ?? 0;
  final arriving = adding[wallet.id] ?? 0;
  return switch (purpose) {
    SplitPurpose.goal => goalFundingRoom(wallet, goals) + arriving,
    SplitPurpose.giving || SplitPurpose.paying =>
      (wallet.hasRecordedBalance ? freeInWallet(wallet, goals) : 0) + arriving,
    SplitPurpose.receiving => double.infinity,
  };
}

/// Why [amount] (with its [fee]) cannot come out of [wallet], which has
/// [room] free.
String splitRoomMessage(
  Wallet wallet, {
  required double amount,
  double fee = 0,
  required double room,
  required Iterable<Goal> goals,
}) {
  final heldByGoals = goalMoneyInWallet(goals, wallet.id) > 0.005;
  if (room <= 0.005) {
    return heldByGoals
        ? 'Nothing in ${wallet.name} is free. Goals hold all of it.'
        : 'Nothing in ${wallet.name} is free.';
  }
  final withFee = fee > 0
      ? ' With the ${formatPeso(fee)} fee, this needs '
            '${formatPeso(amount + fee)}.'
      : '';
  return 'Only ${formatPeso(room)} in ${wallet.name} is free'
      '${heldByGoals ? '; goals hold the rest' : ''}.$withFee';
}

/// What is wrong with a [total] against [target]: more than it, or, with
/// [matchTarget], less than it. Nothing chosen at all is said first.
String? splitTotalProblem(
  double total, {
  required double target,
  required bool matchTarget,
  bool allowBoth = true,
}) {
  if (total <= 0) {
    return target > 0
        ? allowBoth
              ? 'Choose Cash on Hand, Cash in Bank or Both, then enter how much.'
              : 'Choose Cash on Hand or Cash in Bank, then enter how much.'
        : null;
  }
  if (target <= 0) return null;
  if (total > target + 0.005) {
    return 'That is ${formatPeso(total - target)} more than '
        '${formatPeso(target)}.';
  }
  if (matchTarget && total < target - 0.005) {
    return 'Add ${formatPeso(target - total)} more to make '
        '${formatPeso(target)}.';
  }
  return null;
}

/// The first thing wrong with [amounts] and their [fees], by wallet id, or
/// null when they can be saved. Each wallet is checked against what it can
/// give for [purpose]; the total against [target].
String? walletSplitProblem({
  required SplitPurpose purpose,
  required Map<String, double> amounts,
  Map<String, double> fees = const {},
  required List<Wallet> wallets,
  required Iterable<Goal> goals,
  double target = 0,
  bool matchTarget = false,
  Map<String, double> adding = const {},
  Map<String, double>? limits,
  String Function(Wallet wallet, double room)? tooMuchMessage,
  bool allowBoth = true,
}) {
  if (purpose == SplitPurpose.goal) {
    return goalFundingProblem(
      amounts: amounts,
      wallets: wallets,
      otherGoals: goals,
      target: target,
    );
  }

  final byId = {for (final wallet in wallets) wallet.id: wallet};
  // One payment or income, one side: never part cash and part bank.
  if (!allowBoth) {
    final used = [
      for (final entry in amounts.entries)
        if (entry.value > 0) ?byId[entry.key],
    ];
    if (used.any(isCashOnHand) && used.any((w) => !isCashOnHand(w))) {
      return 'Choose Cash on Hand or Cash in Bank, not both.';
    }
  }
  var total = 0.0;
  for (final entry in amounts.entries) {
    final amount = entry.value;
    if (amount <= 0) continue;
    final wallet = byId[entry.key];
    if (wallet == null || wallet.archived) {
      return 'One of these wallets is no longer listed. Choose again.';
    }
    if (!isRecordableAmount(amount)) return minimumAmountError;
    final fee = fees[entry.key] ?? 0;
    final room = splitRoom(
      purpose,
      wallet,
      goals,
      adding: adding,
      limits: limits,
    );
    if (exceedsFree(amount + fee, room)) {
      if (tooMuchMessage != null) return tooMuchMessage(wallet, room);
      return splitRoomMessage(
        wallet,
        amount: amount,
        fee: fee,
        room: room,
        goals: goals,
      );
    }
    total += amount;
  }
  return splitTotalProblem(
    total,
    target: target,
    matchTarget: matchTarget,
    allowBoth: allowBoth,
  );
}

/// Where money comes from or goes to: Cash on Hand, Cash in Bank or Both
/// first, then the user's wallets of that kind, each with an amount. Any
/// number of banks and e-wallets can be added, each once.
///
/// Used wherever money moves in or out of wallets, so it always works the
/// same way. [purpose] decides which wallets show and how much each can
/// give: never more than it has free, after goals, for money going out.
class WalletSplitPicker extends StatefulWidget {
  const WalletSplitPicker({
    required this.wallets,
    required this.goals,
    required this.onChanged,
    this.purpose = SplitPurpose.goal,
    this.target = 0,
    this.matchTarget = false,
    this.initialAmounts = const {},
    this.adding = const {},
    this.withFees = false,
    this.onFeesChanged,
    this.includeSavings = false,
    this.excludeWalletId,
    this.prefill = true,
    this.question,
    this.totalLabel,
    this.keyPrefix,
    this.limits,
    this.tooMuchMessage,
    this.allowBoth = true,
    super.key,
  });

  /// Every wallet; the ones that cannot be used here are left out.
  final List<Wallet> wallets;

  /// Goals whose money in each wallet is not free.
  final List<Goal> goals;

  final SplitPurpose purpose;

  /// The total being split, such as the bill or the income, or zero when
  /// there is none.
  final double target;

  /// The amounts must add up to exactly [target], as for income or an
  /// expense; otherwise they may come to less, as for part of a bill.
  final bool matchTarget;

  /// Amounts already chosen, by wallet id, such as when changing them.
  final Map<String, double> initialAmounts;

  /// Money arriving in each wallet in the same step, such as the income
  /// being recorded. It can be paid out or set aside straight away.
  final Map<String, double> adding;

  /// Each wallet can carry its own optional fee, as paying from a bank and
  /// over the counter cost different amounts.
  final bool withFees;
  final ValueChanged<Map<String, double>>? onFeesChanged;

  /// For money coming in: savings records that can take more are offered
  /// with the banks.
  final bool includeSavings;

  /// A wallet that cannot take part, such as the one a transfer comes from.
  final String? excludeWalletId;

  /// With nothing typed yet, choosing Cash on Hand or Cash in Bank fills the
  /// first wallet with [target], as most people use only one.
  final bool prefill;

  final String? question;
  final String? totalLabel;
  final String? keyPrefix;

  /// The most each wallet can give, by id, in place of what it has free,
  /// such as what a goal holds in it. Only these wallets are offered.
  final Map<String, double>? limits;

  /// Says why an amount is more than its wallet can give, in place of the
  /// usual "only so much is free".
  final String Function(Wallet wallet, double room)? tooMuchMessage;

  /// Offers Both. Off where one payment or income must have one clear
  /// side, cash on hand or the bank: bills and income.
  final bool allowBoth;

  /// The amounts by wallet id for the wallets showing. Blank and zero
  /// amounts are left out, and so is a group the user switched away from.
  final ValueChanged<Map<String, double>> onChanged;

  @override
  State<WalletSplitPicker> createState() => _WalletSplitPickerState();
}

/// One bank or e-wallet chosen. The amount belongs to the row, so picking a
/// different account in it keeps what was typed.
class _AccountRow {
  _AccountRow(this.id, this.walletId, this.controller, this.fee);

  final int id;
  String walletId;
  final TextEditingController controller;
  final TextEditingController fee;
}

class _WalletSplitPickerState extends State<WalletSplitPicker> {
  /// Null until the user picks.
  late WalletGroupChoice? _option = switch (_optionFor(widget.initialAmounts)) {
    // Started on both where both are not offered: the user picks one.
    WalletGroupChoice.both when !widget.allowBoth => null,
    final option => option,
  };

  /// The choices offered: Both only where money may come from both.
  List<WalletGroupChoice> get _choices => widget.allowBoth
      ? WalletGroupChoice.values
      : const [WalletGroupChoice.cash, WalletGroupChoice.bank];

  /// One field per cash wallet, kept while switching options so nothing
  /// typed is lost.
  final _controllers = <String, TextEditingController>{};
  final _feeControllers = <String, TextEditingController>{};

  /// The banks and e-wallets added, in the order they were added.
  late final List<_AccountRow> _accountRows = [
    for (final wallet in _accountWallets)
      if ((widget.initialAmounts[wallet.id] ?? 0) > 0)
        _newRow(wallet.id, widget.initialAmounts[wallet.id]!),
  ];
  int _nextRowId = 0;

  /// The field filled in by [_prefill], and what it was given, so a change
  /// of total can follow it until the user types there themselves.
  TextEditingController? _prefilled;
  double _prefilledAmount = 0;

  /// While true, a field changed by the picker itself does not report.
  bool _quiet = false;

  String get _keyPrefix =>
      widget.keyPrefix ??
      switch (widget.purpose) {
        SplitPurpose.goal || SplitPurpose.giving => 'goal-funding',
        SplitPurpose.paying => 'pay-from',
        SplitPurpose.receiving => 'goes-to',
      };

  bool get _paysOut => widget.purpose != SplitPurpose.receiving;

  WalletGroupChoice? _optionFor(Map<String, double> amounts) {
    final used = widget.wallets.where(
      (wallet) => (amounts[wallet.id] ?? 0) > 0,
    );
    final cash = used.any(isCashOnHand);
    final bank = used.any((wallet) => !isCashOnHand(wallet));
    if (cash && bank) return WalletGroupChoice.both;
    if (cash) return WalletGroupChoice.cash;
    if (bank) return WalletGroupChoice.bank;
    return null;
  }

  /// The wallets that can take part here.
  List<Wallet> get _eligible {
    final wallets = widget.wallets;
    final limits = widget.limits;
    // With a limit for each, such as what a goal holds there, those wallets
    // are the ones that can give, savings records included.
    if (limits != null) {
      return [
        for (final wallet in wallets)
          if (!wallet.archived &&
              wallet.id != widget.excludeWalletId &&
              (limits[wallet.id] ?? 0) > 0.005)
            wallet,
      ];
    }
    final all = switch (widget.purpose) {
      SplitPurpose.goal => goalFundingWallets(wallets),
      SplitPurpose.giving || SplitPurpose.paying => [
        for (final wallet in wallets)
          if (!wallet.archived && !wallet.isSetAside) wallet,
      ],
      SplitPurpose.receiving => [
        for (final wallet in wallets)
          if (!wallet.archived &&
              (!wallet.isSetAside ||
                  (widget.includeSavings &&
                      wallet.purpose == WalletPurpose.savings &&
                      !wallet.isLockedSavings)))
            wallet,
      ],
    };
    return [
      for (final wallet in all)
        if (wallet.id != widget.excludeWalletId) wallet,
    ];
  }

  List<Wallet> get _accountWallets =>
      _eligible.where((wallet) => !isCashOnHand(wallet)).toList();

  /// Money going out needs a recorded balance to come from.
  bool _takesAmount(Wallet wallet) =>
      !_paysOut ||
      widget.limits != null ||
      wallet.hasRecordedBalance ||
      widget.adding[wallet.id] != null;

  double _room(Wallet wallet) => splitRoom(
    widget.purpose,
    wallet,
    widget.goals,
    adding: widget.adding,
    limits: widget.limits,
  );

  @override
  void didUpdateWidget(WalletSplitPicker old) {
    super.didUpdateWidget(old);
    // Cash on Hand or Cash in Bank chosen before the total was typed: it
    // fills in now.
    if (old.target <= 0 && widget.target > 0 && _prefilled == null) {
      _prefill();
      if (_prefilled != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _emit();
        });
      }
      return;
    }
    // A total changed above: the amount filled in for it follows, until the
    // user types there themselves.
    final prefilled = _prefilled;
    if (prefilled != null &&
        (widget.target - old.target).abs() > 0.005 &&
        (_amountFrom(prefilled) - _prefilledAmount).abs() < 0.005) {
      final amount = _cappedFor(prefilled, widget.target);
      _quiet = true;
      prefilled.text = amount > 0 ? formatAmountInput(amount) : '';
      _quiet = false;
      _prefilledAmount = amount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emit();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [
      ..._controllers.values,
      ..._feeControllers.values,
    ]) {
      controller.dispose();
    }
    for (final row in _accountRows) {
      row.controller.dispose();
      row.fee.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String walletId) {
    return _controllers.putIfAbsent(walletId, () {
      final initial = widget.initialAmounts[walletId] ?? 0;
      return TextEditingController(
        text: initial > 0 ? formatAmountInput(initial) : '',
      )..addListener(_report);
    });
  }

  TextEditingController _feeFor(String walletId) => _feeControllers.putIfAbsent(
    walletId,
    () => TextEditingController()..addListener(_report),
  );

  _AccountRow _newRow(String walletId, [double amount = 0]) => _AccountRow(
    _nextRowId++,
    walletId,
    TextEditingController(text: amount > 0 ? formatAmountInput(amount) : '')
      ..addListener(_report),
    TextEditingController()..addListener(_report),
  );

  /// The first bank or e-wallet not in a row yet, or null when all are.
  Wallet? get _nextAccount {
    final used = {for (final row in _accountRows) row.walletId};
    for (final wallet in _accountWallets) {
      if (!used.contains(wallet.id)) return wallet;
    }
    return null;
  }

  /// Rounded to centavos, so a long decimal cannot creep past a limit.
  double _amountFrom(TextEditingController? controller) {
    final text = controller?.text.trim().replaceAll(',', '') ?? '';
    final value = double.tryParse(text) ?? 0;
    return value.isFinite && value > 0 ? (value * 100).round() / 100 : 0;
  }

  /// Each shown wallet's amount, or its fee with [fees].
  Map<String, double> _collect({bool fees = false}) {
    final option = _option;
    final values = <String, double>{};
    if (option == null) return values;

    if (option.showsCash) {
      for (final wallet in _eligible) {
        if (!isCashOnHand(wallet) || !_takesAmount(wallet)) continue;
        final amount = _amountFrom(_controllers[wallet.id]);
        if (amount <= 0) continue;
        values[wallet.id] = fees
            ? _amountFrom(_feeControllers[wallet.id])
            : amount;
      }
    }
    if (option.showsBank) {
      final eligible = {
        for (final wallet in _accountWallets) wallet.id: wallet,
      };
      for (final row in _accountRows) {
        final wallet = eligible[row.walletId];
        // A row whose account was archived or excluded meanwhile is left out.
        if (wallet == null || !_takesAmount(wallet)) continue;
        final amount = _amountFrom(row.controller);
        if (amount <= 0) continue;
        values[row.walletId] = fees ? _amountFrom(row.fee) : amount;
      }
    }
    if (fees) values.removeWhere((_, fee) => fee <= 0);
    return values;
  }

  Map<String, double> get _amounts => _collect();
  Map<String, double> get _fees =>
      widget.withFees ? _collect(fees: true) : const {};

  void _emit() {
    widget.onChanged(_amounts);
    widget.onFeesChanged?.call(_fees);
  }

  void _report() {
    if (_quiet) return;
    setState(() {});
    _emit();
  }

  /// [amount], kept within what the wallet behind [controller] can give.
  double _cappedFor(TextEditingController controller, double amount) {
    if (!_paysOut) return amount;
    Wallet? wallet;
    for (final entry in _controllers.entries) {
      if (entry.value == controller) {
        wallet = widget.wallets.where((w) => w.id == entry.key).firstOrNull;
      }
    }
    for (final row in _accountRows) {
      if (row.controller == controller) {
        wallet = widget.wallets.where((w) => w.id == row.walletId).firstOrNull;
      }
    }
    if (wallet == null) return amount;
    return math.max(0, math.min(amount, _room(wallet)));
  }

  /// With nothing typed yet, the whole total goes in the first wallet
  /// shown: most people use one, so a tap is enough, and it is still easy
  /// to split.
  void _prefill() {
    final option = _option;
    // Goal money is spread on purpose, so nothing is filled in for it.
    if (option == null ||
        !widget.prefill ||
        widget.purpose == SplitPurpose.goal ||
        widget.target <= 0) {
      return;
    }
    if (_amounts.isNotEmpty) return;

    TextEditingController? controller;
    if (option.showsCash) {
      final cash = _eligible.where(
        (wallet) => isCashOnHand(wallet) && _takesAmount(wallet),
      );
      if (cash.isNotEmpty) controller = _controllerFor(cash.first.id);
    }
    if (controller == null && option.showsBank && _accountRows.isNotEmpty) {
      controller = _accountRows.first.controller;
    }
    if (controller == null || controller.text.trim().isNotEmpty) return;

    final amount = _cappedFor(controller, widget.target);
    if (amount <= 0) return;
    _quiet = true;
    controller.text = formatAmountInput(amount);
    _quiet = false;
    _prefilled = controller;
    _prefilledAmount = amount;
  }

  void _choose(WalletGroupChoice option) {
    // Tapping the chosen option again takes it back.
    setState(() {
      _option = _option == option ? null : option;
      // The first account is ready to fill in, saving a tap.
      final first = _nextAccount;
      if (_option?.showsBank == true && _accountRows.isEmpty && first != null) {
        _accountRows.add(_newRow(first.id));
      }
    });
    _prefill();
    _emit();
  }

  void _addAccount() {
    final next = _nextAccount;
    if (next == null) return;
    setState(() => _accountRows.add(_newRow(next.id)));
    _emit();
  }

  void _removeAccount(_AccountRow row) {
    row.controller.removeListener(_report);
    row.fee.removeListener(_report);
    setState(() => _accountRows.remove(row));
    if (_prefilled == row.controller) _prefilled = null;
    // Its fields leave the screen in this frame; disposing waits for that.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      row.controller.dispose();
      row.fee.dispose();
    });
    _emit();
  }

  void _changeAccount(_AccountRow row, String? walletId) {
    if (walletId == null || walletId == row.walletId) return;
    setState(() => row.walletId = walletId);
    _emit();
  }

  String get _question =>
      widget.question ??
      switch (widget.purpose) {
        SplitPurpose.goal => 'Where is this money now?',
        SplitPurpose.giving => 'Which wallets is it coming from?',
        SplitPurpose.paying => 'Where are you paying from?',
        SplitPurpose.receiving => 'Where is the money going?',
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final eligible = _eligible;
    final cashWallets = eligible.where(isCashOnHand).toList();
    final bankWallets = _accountWallets;

    if (eligible.isEmpty) {
      return const DialogNote(
        text: 'Add a cash, bank, or e-wallet account first.',
      );
    }

    final option = _option;
    final amounts = _amounts;

    Widget groupTitle(String text) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.textBody,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _question,
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
              for (final (index, choice) in _choices.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _OptionTile(
                    option: choice,
                    selected: option == choice,
                    enabled: switch (choice) {
                      WalletGroupChoice.cash => cashWallets.isNotEmpty,
                      WalletGroupChoice.bank => bankWallets.isNotEmpty,
                      WalletGroupChoice.both =>
                        cashWallets.isNotEmpty && bankWallets.isNotEmpty,
                    },
                    onTap: () => _choose(choice),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (option != null) ...[
          if (option.showsCash) ...[
            if (option == WalletGroupChoice.both) groupTitle('Cash on Hand'),
            for (final wallet in cashWallets) _cashCard(wallet),
          ],
          if (option.showsBank) ...[
            if (option == WalletGroupChoice.both) groupTitle('Cash in Bank'),
            for (final row in _accountRows) _accountRowCard(row, bankWallets),
            if (_nextAccount != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                // The same look as the Add button on every setup step.
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _addAccount,
                    style: confirmButtonStyle(),
                    child: const Text(
                      'Add account',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
          if (amounts.isNotEmpty)
            _allFit(amounts) ? _summary(amounts) : _summaryOnHold(),
        ],
      ],
    );
  }

  /// Whether every amount, with its fee, fits what its wallet can give.
  bool _allFit(Map<String, double> amounts) {
    if (!_paysOut) return true;
    final fees = _fees;
    final byId = {for (final wallet in widget.wallets) wallet.id: wallet};
    for (final entry in amounts.entries) {
      final wallet = byId[entry.key];
      if (wallet == null) continue;
      if (exceedsFree(entry.value + (fees[entry.key] ?? 0), _room(wallet))) {
        return false;
      }
    }
    return true;
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: context.appColors.pageBackground,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: context.appColors.border),
  );

  /// The kind, what is free, and for a goal what the amount may earn.
  List<Widget> _details(Wallet wallet, double amount) {
    final note = TextStyle(fontSize: 12, color: context.appColors.textBody);
    final kind = fundingWalletKind(wallet);

    if (!_paysOut) {
      return [Text('$kind · ${formatPeso(wallet.balance)} now', style: note)];
    }

    final room = _room(wallet);
    final arriving = widget.adding[wallet.id] ?? 0;
    final ready = wallet.readyOn(DateTime.now());
    return [
      Text(
        !_takesAmount(wallet)
            ? '$kind · No balance recorded, so nothing can come from it.'
            : arriving > 0
            ? '$kind · ${formatPeso(room)} available, with the '
                  '${formatPeso(arriving)} coming in'
            : (room - wallet.balance).abs() < 0.005
            ? '$kind · ${formatPeso(room)} available'
            : '$kind · ${formatPeso(wallet.balance)} balance · '
                  '${formatPeso(room)} available',
        style: note,
      ),
      // Counted toward the goal now, but only out on its end date.
      if (ready != null && widget.purpose == SplitPurpose.goal)
        Text(
          'Counts toward the goal now. Ready on ${formatShortDate(ready)}, '
          'when it can be taken out.',
          style: note,
        ),
      if (widget.purpose == SplitPurpose.goal)
        Text(goalMoneyInterestNote(wallet, amount), style: note),
    ];
  }

  /// The amount box for one wallet, and its optional fee beside it. Asking
  /// for more than the wallet has free is flagged as it is typed.
  Widget _amountFields(
    Wallet wallet,
    TextEditingController controller,
    TextEditingController fee,
  ) {
    final amount = _amountFrom(controller);
    final feeAmount = widget.withFees ? _amountFrom(fee) : 0.0;
    final room = _room(wallet);
    final tooMuch = _paysOut && exceedsFree(amount + feeAmount, room);
    final lastFee = wallet.serviceCharge;

    final amountField = TextField(
      key: Key('$_keyPrefix-${wallet.id}'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [ThousandsSeparatorFormatter()],
      decoration: dialogFieldDecoration(context, 'Amount').copyWith(
        prefixText: '₱ ',
        hintText: '0',
        errorMaxLines: 3,
        errorText: !tooMuch
            ? null
            : widget.purpose == SplitPurpose.goal
            ? (room <= 0
                  ? 'Nothing in ${wallet.name} is free to set aside. Other '
                        'goals already hold all of it.'
                  : 'Only ${formatPeso(room)} in ${wallet.name} is free to '
                        'set aside${wallet.balance - room > 0.005 ? '; other goals hold the rest' : ''}.')
            : widget.tooMuchMessage?.call(wallet, room) ??
                  splitRoomMessage(
                    wallet,
                    amount: amount,
                    fee: feeAmount,
                    room: room,
                    goals: widget.goals,
                  ),
      ),
    );

    if (!widget.withFees) return amountField;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: amountField),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: TextField(
            key: Key('$_keyPrefix-fee-${wallet.id}'),
            controller: fee,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [ThousandsSeparatorFormatter()],
            decoration: dialogFieldDecoration(
              context,
              'Fee (optional)',
              helper: lastFee == null || lastFee <= 0
                  ? null
                  : 'Last time ${formatPeso(lastFee)}',
            ).copyWith(prefixText: '₱ ', hintText: '0'),
          ),
        ),
      ],
    );
  }

  Widget _cashCard(Wallet wallet) {
    final controller = _controllerFor(wallet.id);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                        color: context.appColors.textPrimary,
                      ),
                    ),
                    ..._details(wallet, _amountFrom(controller)),
                  ],
                ),
              ),
            ],
          ),
          if (_takesAmount(wallet)) ...[
            const SizedBox(height: 10),
            _amountFields(wallet, controller, _feeFor(wallet.id)),
          ],
        ],
      ),
    );
  }

  /// A chosen bank or e-wallet: which account, its amount, and a way to take
  /// it off. Accounts in other rows are greyed out in the list, so the same
  /// money cannot be counted twice.
  Widget _accountRowCard(_AccountRow row, List<Wallet> accounts) {
    final wallet = accounts
        .where((item) => item.id == row.walletId)
        .firstOrNull;

    return Container(
      key: ValueKey('$_keyPrefix-row-${row.id}'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: WalletPicker(
                  wallets: accounts,
                  selectedId: wallet?.id,
                  allowed: const {
                    WalletPurpose.spending,
                    WalletPurpose.savings,
                  },
                  disabledWalletIds: {
                    for (final other in _accountRows)
                      if (other != row) other.walletId,
                  },
                  disabledLabel: 'Added',
                  displayBalances: _paysOut
                      ? {
                          for (final account in accounts)
                            account.id: _room(account),
                        }
                      : null,
                  label: 'Account',
                  onChanged: (id) => _changeAccount(row, id),
                ),
              ),
              IconButton(
                tooltip: 'Remove ${wallet?.name ?? 'account'}',
                onPressed: () => _removeAccount(row),
                color: dangerColorOn(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (wallet != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  ..._details(wallet, _amountFrom(row.controller)),
                  if (_takesAmount(wallet)) ...[
                    const SizedBox(height: 10),
                    _amountFields(wallet, row.controller, row.fee),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Shown in place of the total while an amount is more than its wallet
  /// has free. A total built on it would describe money that is not there.
  Widget _summaryOnHold() {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: dangerColorOn(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Fix the amount in red to see your total. A wallet can only '
              'give what it has free.',
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: colors.textBody)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(List<Widget> children, {Key? key}) => Container(
    key: key,
    width: double.infinity,
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.appColors.primaryTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  /// The total against what was asked for, in red when it does not fit.
  Widget? _targetLine(double total) {
    final problem = widget.target > 0
        ? splitTotalProblem(
            total,
            target: widget.target,
            matchTarget: widget.matchTarget,
            allowBoth: widget.allowBoth,
          )
        : null;
    if (problem == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        problem,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: dangerColorOn(context),
        ),
      ),
    );
  }

  Widget _summary(Map<String, double> amounts) {
    final total = amounts.values.fold<double>(0, (sum, amount) => sum + amount);
    final targetLine = _targetLine(total);

    switch (widget.purpose) {
      case SplitPurpose.goal:
        return _goalSummary(amounts, total);
      case SplitPurpose.giving:
        return _summaryBox(key: const Key('moving-in-total'), [
          _summaryRow(
            widget.totalLabel ?? 'Moving into this savings',
            formatPeso(total),
            bold: true,
          ),
          ?targetLine,
        ]);
      case SplitPurpose.paying:
        final fees = _fees.values.fold<double>(0, (sum, fee) => sum + fee);
        final left = widget.target - total;
        return _summaryBox(key: const Key('paying-total'), [
          _summaryRow(widget.totalLabel ?? 'Paying', formatPeso(total)),
          if (fees > 0) ...[
            _summaryRow('Fees', formatPeso(fees)),
            _summaryRow(
              'Out of your wallets',
              formatPeso(total + fees),
              bold: true,
            ),
          ],
          if (targetLine == null &&
              !widget.matchTarget &&
              widget.target > 0 &&
              left > 0.005)
            _summaryRow('Still owed after this', formatPeso(left)),
          ?targetLine,
        ]);
      case SplitPurpose.receiving:
        return _summaryBox(key: const Key('receiving-total'), [
          _summaryRow(
            widget.totalLabel ?? 'Going into your wallets',
            formatPeso(total),
            bold: true,
          ),
          ?targetLine,
        ]);
    }
  }

  /// The total, what is still to save, and the interest the money may earn,
  /// kept apart so the guess never reads as money saved.
  Widget _goalSummary(Map<String, double> amounts, double total) {
    final colors = context.appColors;
    final byId = {for (final wallet in widget.wallets) wallet.id: wallet};
    final left = widget.target - total;

    var interest = 0.0;
    var hasEstimate = false;
    final noRate = <String>[];
    for (final entry in amounts.entries) {
      final wallet = byId[entry.key]!;
      final yearly = yearlyInterestOnGoalMoney(wallet, entry.value);
      if (yearly == null) {
        noRate.add(wallet.name);
      } else if (!wallet.earnsNoInterest) {
        interest += yearly;
        hasEstimate = true;
      }
    }

    return _summaryBox([
      _summaryRow('Total set aside', formatPeso(total), bold: true),
      if (widget.target > 0)
        _summaryRow('Still to save', formatPeso(left > 0 ? left : 0)),
      if (widget.target > 0 && left < -0.005)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'That is ${formatPeso(-left)} more than the goal needs.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: dangerColorOn(context),
            ),
          ),
        ),
      if (hasEstimate)
        _summaryRow(
          'Interest in a year, after tax',
          'about ${formatPeso(interest)}',
        ),
      if (hasEstimate || noRate.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          [
            if (hasEstimate)
              "Interest is an estimate at today's rate, after the "
                  '${(interestTaxRate * 100).round()}% tax banks keep. It '
                  'goes to the account, not this goal: add it as income '
                  'when it is paid.',
            if (noRate.isNotEmpty)
              'No rate recorded for ${noRate.join(', ')}, so '
                  '${noRate.length == 1 ? 'it is' : 'they are'} left out.',
          ].join(' '),
          style: TextStyle(fontSize: 12, color: colors.textBody),
        ),
      ],
    ]);
  }
}

/// One of the three choices, large enough to tap comfortably.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final WalletGroupChoice option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final faded = colors.textBody.withValues(alpha: 0.45);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: selected ? colors.primaryText : colors.border,
        width: selected ? 1.5 : 1,
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? colors.primaryTint : colors.pageBackground,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: enabled ? 1 : 0.4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, asset)
                            in option.iconAssets.indexed) ...[
                          if (index > 0) const SizedBox(width: 4),
                          Image.asset(asset, width: 26, height: 26),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    option.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: enabled ? colors.textPrimary : faded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
