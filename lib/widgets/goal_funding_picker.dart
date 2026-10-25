import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/amount_input_formatter.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';

/// Where money already saved for a goal is kept today.
enum GoalFundingOption {
  cash('Cash on Hand'),
  bank('Cash in Bank'),
  both('Both');

  const GoalFundingOption(this.label);

  final String label;

  /// The same icons the wallets use, so a choice matches the accounts it
  /// opens. Both shows the two together.
  List<String> get iconAssets => switch (this) {
    GoalFundingOption.cash => [WalletType.cash.iconAsset],
    GoalFundingOption.bank => [WalletType.bank.iconAsset],
    GoalFundingOption.both => [
      WalletType.cash.iconAsset,
      WalletType.bank.iconAsset,
    ],
  };

  bool get showsCash => this != GoalFundingOption.bank;
  bool get showsBank => this != GoalFundingOption.cash;
}

/// Cash wallets are cash on hand. Every other account a goal can draw on,
/// bank, e-wallet or savings record, is cash in bank, the same split the
/// Cash Summary makes.
bool isCashOnHand(Wallet wallet) => wallet.type == WalletType.cash;

/// What [wallet] still has free for this goal once [otherGoals] are counted.
/// Nothing can be promised from a wallet without a recorded balance.
double goalFundingRoom(Wallet wallet, Iterable<Goal> otherGoals) =>
    wallet.hasRecordedBalance ? freeInWallet(wallet, otherGoals) : 0;

/// Whether [amount] asks for more than [room], the money free in an account.
bool exceedsFree(double amount, double room) => amount > room + 0.005;

/// Whether every amount fits what its account has free. Until they all do,
/// none of them is counted in any total, so no figure is built on money
/// that is not there.
bool fundingFits({
  required Map<String, double> amounts,
  required List<Wallet> wallets,
  required Iterable<Goal> otherGoals,
}) {
  final byId = {for (final wallet in wallets) wallet.id: wallet};
  for (final entry in amounts.entries) {
    final wallet = byId[entry.key];
    // A missing account is reported when saving.
    if (wallet == null) continue;
    if (exceedsFree(entry.value, goalFundingRoom(wallet, otherGoals))) {
      return false;
    }
  }
  return true;
}

/// The first thing wrong with setting [amounts] aside, by wallet id, or null
/// when they can be saved. Each wallet is checked on its own, because money
/// is promised out of one place; the total is checked against [target].
String? goalFundingProblem({
  required Map<String, double> amounts,
  required List<Wallet> wallets,
  required Iterable<Goal> otherGoals,
  required double target,
}) {
  final byId = {for (final wallet in wallets) wallet.id: wallet};
  var total = 0.0;

  for (final entry in amounts.entries) {
    final amount = entry.value;
    if (amount <= 0) continue;
    final wallet = byId[entry.key];
    if (wallet == null || wallet.archived) {
      return 'One of these accounts is no longer listed. Choose again.';
    }
    if (!isRecordableAmount(amount)) return minimumAmountError;
    if (!wallet.hasRecordedBalance) {
      return '${wallet.name} has no balance recorded yet.';
    }
    final room = goalFundingRoom(wallet, otherGoals);
    if (exceedsFree(amount, room)) {
      return room <= 0
          ? '${wallet.name} has nothing left to promise.'
          : '${wallet.name} has ${formatPeso(room)} left to promise.';
    }
    total += amount;
  }

  if (target > 0 && total > target + 0.005) {
    return 'Together that is more than the goal needs '
        '(${formatPeso(target)}).';
  }
  return null;
}

/// One plain line on what money kept in [wallet] earns, with what [amount]
/// of it may earn in a year when a rate is recorded.
String goalMoneyInterestNote(Wallet wallet, double amount) {
  if (wallet.earnsNoInterest) {
    return wallet.type == WalletType.cash
        ? 'Cash earns no interest.'
        : 'This account earns no interest.';
  }
  final rate = wallet.annualInterestRatePercent;
  if (rate == null) return 'No yearly interest rate recorded.';
  final yearly = yearlyInterestOnGoalMoney(wallet, amount);
  if (amount <= 0 || yearly == null) return '${_percent(rate)} interest a year';
  return '${_percent(rate)} interest a year · ${formatPeso(amount)} may earn '
      'about ${formatPeso(yearly)} a year after tax';
}

String _percent(double rate) =>
    '${rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate}%';

/// The kind shown beside a wallet's name. A savings record says what it is,
/// not the "Other" type it is stored under.
String fundingWalletKind(Wallet wallet) =>
    wallet.purpose == WalletPurpose.savings
    ? wallet.savingsType.label
    : wallet.type.label;

/// "A", "A and B", "A, B and C".
String _joinNames(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// What a goal holds in each account: one row per account, with the same
/// icon the wallet has everywhere else, and one line for the interest the
/// money may earn. Used wherever a goal's money is listed, so it reads the
/// same in setup and on the goal's own page.
class GoalFundingList extends StatelessWidget {
  const GoalFundingList({required this.sources, super.key});

  /// Each account with what the goal holds in it, in the order shown.
  final List<(Wallet, double)> sources;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    var interest = 0.0;
    final earning = <String>[];
    final now = DateTime.now();
    for (final (wallet, amount) in sources) {
      final yearly = yearlyInterestOnGoalMoney(wallet, amount);
      if (yearly != null && yearly > 0) {
        interest += yearly;
        earning.add(wallet.name);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (wallet, amount) in sources)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Image.asset(wallet.iconAsset, width: 24, height: 24),
                const SizedBox(width: 10),
                // Long bank names wrap instead of being cut off. Money in a
                // time deposit says when it can be taken out.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${wallet.name}${wallet.archived ? ' (archived)' : ''}',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (wallet.readyOn(now) case final ready?)
                        Text(
                          'Ready on ${formatShortDate(ready)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatPeso(amount),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        if (earning.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.trending_up, size: 16, color: colors.textBody),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'May earn about ${formatPeso(interest)} a year after tax '
                  'from ${_joinNames(earning)}. Add it as income when it is '
                  'paid.',
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Lets the user say where money already saved for a goal is kept: cash on
/// hand, cash in bank, or both, with an amount for each account used. Any
/// number of banks and e-wallets can be added, each once.
///
/// Nothing moves. Each amount is a claim on that account's recorded balance,
/// so the balance, the Cash Summary and the account's own interest stay as
/// they are.
class GoalFundingPicker extends StatefulWidget {
  const GoalFundingPicker({
    required this.wallets,
    required this.otherGoals,
    required this.target,
    required this.onChanged,
    this.initialAmounts = const {},
    this.movingIn = false,
    super.key,
  });

  /// Every wallet; the ones a goal cannot draw on are left out here.
  final List<Wallet> wallets;

  /// For money being moved into new savings rather than set aside for a
  /// goal: only cash, bank and e-wallet accounts can give it, and the total
  /// is simply what moves in.
  final bool movingIn;

  /// Goals whose claims on the same accounts are already counted.
  final List<Goal> otherGoals;

  /// The goal's target, for the total and what is still to save. Zero while
  /// it has not been typed.
  final double target;

  /// Amounts already chosen, by wallet id, such as when changing them.
  final Map<String, double> initialAmounts;

  /// The amounts by wallet id for the accounts showing. Blank and zero
  /// amounts are left out, and so is a section the user switched away from.
  final ValueChanged<Map<String, double>> onChanged;

  @override
  State<GoalFundingPicker> createState() => _GoalFundingPickerState();
}

/// One bank or e-wallet chosen for the goal. The amount belongs to the row,
/// so picking a different account in it keeps what was typed.
class _AccountRow {
  _AccountRow(this.id, this.walletId, this.controller);

  final int id;
  String walletId;
  final TextEditingController controller;
}

class _GoalFundingPickerState extends State<GoalFundingPicker> {
  /// Null until the user picks, so the optional step stays short.
  late GoalFundingOption? _option = _optionFor(widget.initialAmounts);

  /// One field per cash wallet, kept while switching options so nothing
  /// typed is lost.
  final _controllers = <String, TextEditingController>{};

  /// The banks and e-wallets added, in the order they were added. As many as
  /// the user has; each account can be in only one row.
  late final List<_AccountRow> _accountRows = [
    for (final wallet in _accountWallets)
      if ((widget.initialAmounts[wallet.id] ?? 0) > 0)
        _newRow(wallet.id, widget.initialAmounts[wallet.id]!),
  ];
  int _nextRowId = 0;

  GoalFundingOption? _optionFor(Map<String, double> amounts) {
    final used = widget.wallets.where(
      (wallet) => (amounts[wallet.id] ?? 0) > 0,
    );
    final cash = used.any(isCashOnHand);
    final bank = used.any((wallet) => !isCashOnHand(wallet));
    if (cash && bank) return GoalFundingOption.both;
    if (cash) return GoalFundingOption.cash;
    if (bank) return GoalFundingOption.bank;
    return null;
  }

  /// The accounts money can come from here.
  List<Wallet> get _eligible => widget.movingIn
      ? goalFundingWallets(
          widget.wallets,
        ).where((wallet) => !wallet.isSetAside).toList()
      : goalFundingWallets(widget.wallets);

  List<Wallet> get _accountWallets =>
      _eligible.where((wallet) => !isCashOnHand(wallet)).toList();

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final row in _accountRows) {
      row.controller.dispose();
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

  _AccountRow _newRow(String walletId, [double amount = 0]) => _AccountRow(
    _nextRowId++,
    walletId,
    TextEditingController(text: amount > 0 ? formatAmountInput(amount) : '')
      ..addListener(_report),
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

  Map<String, double> get _amounts {
    final option = _option;
    final amounts = <String, double>{};
    if (option == null) return amounts;
    final byId = {for (final wallet in widget.wallets) wallet.id: wallet};

    if (option.showsCash) {
      for (final wallet in _eligible) {
        if (!isCashOnHand(wallet) || !wallet.hasRecordedBalance) continue;
        final amount = _amountFrom(_controllers[wallet.id]);
        if (amount > 0) amounts[wallet.id] = amount;
      }
    }
    if (option.showsBank) {
      final eligible = {for (final wallet in _accountWallets) wallet.id};
      for (final row in _accountRows) {
        // A row whose account was archived meanwhile has nothing to give.
        if (!eligible.contains(row.walletId) ||
            byId[row.walletId]?.hasRecordedBalance != true) {
          continue;
        }
        final amount = _amountFrom(row.controller);
        if (amount > 0) amounts[row.walletId] = amount;
      }
    }
    return amounts;
  }

  void _report() {
    setState(() {});
    widget.onChanged(_amounts);
  }

  void _choose(GoalFundingOption option) {
    // Tapping the chosen option again takes it back, as nothing here is
    // required.
    setState(() {
      _option = _option == option ? null : option;
      // The first account is ready to fill in, saving a tap.
      final first = _nextAccount;
      if (_option?.showsBank == true && _accountRows.isEmpty && first != null) {
        _accountRows.add(_newRow(first.id));
      }
    });
    widget.onChanged(_amounts);
  }

  void _addAccount() {
    final next = _nextAccount;
    if (next == null) return;
    setState(() => _accountRows.add(_newRow(next.id)));
    widget.onChanged(_amounts);
  }

  void _removeAccount(_AccountRow row) {
    row.controller.removeListener(_report);
    setState(() => _accountRows.remove(row));
    // Its field leaves the screen in this frame; disposing waits for that.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => row.controller.dispose(),
    );
    widget.onChanged(_amounts);
  }

  void _changeAccount(_AccountRow row, String? walletId) {
    if (walletId == null || walletId == row.walletId) return;
    setState(() => row.walletId = walletId);
    widget.onChanged(_amounts);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final eligible = _eligible;
    final cashWallets = eligible.where(isCashOnHand).toList();
    final bankWallets = _accountWallets;

    if (eligible.isEmpty) {
      return const DialogNote(
        text:
            'Add a cash, bank, or e-wallet account before setting money '
            'aside.',
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
          widget.movingIn
              ? 'Which wallets is it coming from?'
              : 'Where is this money now?',
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
              for (final (index, choice)
                  in GoalFundingOption.values.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _OptionTile(
                    option: choice,
                    selected: option == choice,
                    enabled: switch (choice) {
                      GoalFundingOption.cash => cashWallets.isNotEmpty,
                      GoalFundingOption.bank => bankWallets.isNotEmpty,
                      GoalFundingOption.both =>
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
            if (option == GoalFundingOption.both) groupTitle('Cash on Hand'),
            for (final wallet in cashWallets) _cashCard(wallet),
          ],
          if (option.showsBank) ...[
            if (option == GoalFundingOption.both) groupTitle('Cash in Bank'),
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
            fundingFits(
                  amounts: amounts,
                  wallets: widget.wallets,
                  otherGoals: widget.otherGoals,
                )
                ? _summary(amounts)
                : _summaryOnHold(),
        ],
      ],
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: context.appColors.pageBackground,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: context.appColors.border),
  );

  /// The kind, what is free to set aside, and what the amount may earn.
  List<Widget> _details(Wallet wallet, double amount) {
    final room = goalFundingRoom(wallet, widget.otherGoals);
    final note = TextStyle(fontSize: 12, color: context.appColors.textBody);
    final kind = fundingWalletKind(wallet);

    final ready = wallet.readyOn(DateTime.now());
    return [
      Text(
        !wallet.hasRecordedBalance
            ? '$kind · No balance recorded, so nothing can be set aside.'
            : (room - wallet.balance).abs() < 0.005
            ? '$kind · ${formatPeso(room)} available'
            : '$kind · ${formatPeso(wallet.balance)} balance · '
                  '${formatPeso(room)} available',
        style: note,
      ),
      // Counted toward the goal now, but only out on its end date.
      if (ready != null && !widget.movingIn)
        Text(
          'Counts toward the goal now. Ready on ${formatShortDate(ready)}, '
          'when it can be taken out.',
          style: note,
        ),
      // What goal money there may earn; money moving out earns nothing there.
      if (!widget.movingIn)
        Text(goalMoneyInterestNote(wallet, amount), style: note),
    ];
  }

  /// The amount box for one account. The account is named just above it, so
  /// the label stays short enough never to be cut off. Asking for more than
  /// the account has free is flagged as it is typed: an earmark can only
  /// claim money that is there and not already promised to another goal.
  Widget _amountField(Wallet wallet, TextEditingController controller) {
    final amount = _amountFrom(controller);
    final room = goalFundingRoom(wallet, widget.otherGoals);
    final heldByGoals = wallet.balance - room > 0.005;

    return TextField(
      key: Key('goal-funding-${wallet.id}'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [ThousandsSeparatorFormatter()],
      decoration: dialogFieldDecoration(context, 'Amount').copyWith(
        prefixText: '₱ ',
        hintText: '0',
        errorMaxLines: 3,
        errorText: !exceedsFree(amount, room)
            ? null
            : room <= 0
            ? 'Nothing in ${wallet.name} is free to set aside. Other goals '
                  'already hold all of it.'
            : 'Only ${formatPeso(room)} in ${wallet.name} is free to set '
                  'aside${heldByGoals ? '; other goals hold the rest' : ''}.',
      ),
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
          if (wallet.hasRecordedBalance) ...[
            const SizedBox(height: 10),
            _amountField(wallet, controller),
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
      key: ValueKey('goal-funding-row-${row.id}'),
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
                  displayBalances: {
                    for (final account in accounts)
                      account.id: goalFundingRoom(account, widget.otherGoals),
                  },
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
                  if (wallet.hasRecordedBalance) ...[
                    const SizedBox(height: 10),
                    _amountField(wallet, row.controller),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// For money moving into new savings: only how much moves, said once.
  Widget _movingSummary(Map<String, double> amounts) {
    final colors = context.appColors;
    final total = amounts.values.fold<double>(0, (sum, amount) => sum + amount);

    return Container(
      key: const Key('moving-in-total'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Moving into this savings',
              style: TextStyle(color: colors.textBody),
            ),
          ),
          Text(
            formatPeso(total),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Shown in place of the total while an amount is more than its account
  /// has free. A total, a "still to save" or an interest guess built on that
  /// amount would describe money that is not there.
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
              'Fix the amount in red to see your total. An account can only '
              'give what it has free.',
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// The total, what is still to save, and the interest the money may earn,
  /// kept apart so the guess never reads as money saved.
  Widget _summary(Map<String, double> amounts) {
    final colors = context.appColors;
    if (widget.movingIn) return _movingSummary(amounts);
    final byId = {for (final wallet in widget.wallets) wallet.id: wallet};
    final total = amounts.values.fold<double>(0, (sum, amount) => sum + amount);
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

    Widget row(String label, String value, {bool bold = false}) => Padding(
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

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Total set aside', formatPeso(total), bold: true),
          if (widget.target > 0)
            row('Still to save', formatPeso(left > 0 ? left : 0)),
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
            row(
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
        ],
      ),
    );
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

  final GoalFundingOption option;
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
