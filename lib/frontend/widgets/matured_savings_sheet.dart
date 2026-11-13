import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';
import 'wallet_split_picker.dart';

/// Asks what happened to a savings record that has reached its maturity date.
///
/// FinAssist cannot see a real account, so nothing moves until the user says
/// it did. A time deposit can be claimed or renewed; other savings can be
/// taken out or rolled over as before.
Future<bool?> showMaturedSavingsSheet(
  BuildContext context, {
  required Wallet wallet,
  required List<Wallet> wallets,
  bool isMatured = true,
  List<Goal>? goals,
  void Function(double received, Map<String, double> to)? onSettle,
  void Function(DateTime next, double interest)? onRollOver,
  void Function(DateTime next, double interest, Map<String, double> interestTo)?
  onRenewCapital,
  void Function(
    double capital,
    double interest,
    Map<String, double> capitalTo,
    Map<String, double> interestTo,
  )?
  onClaim,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => MaturedSavingsSheet(
      wallet: wallet,
      wallets: wallets,
      isMatured: isMatured,
      goals: goals,
      onSettle: onSettle,
      onRollOver: onRollOver,
      onRenewCapital: onRenewCapital,
      onClaim: onClaim,
    ),
  );
}

Future<bool?> showSavingsWithdrawalSheet(
  BuildContext context, {
  required Wallet wallet,
  required List<Wallet> wallets,
  List<Goal>? goals,
}) => showMaturedSavingsSheet(
  context,
  wallet: wallet,
  wallets: wallets,
  isMatured: false,
  goals: goals,
);

class MaturedSavingsSheet extends StatefulWidget {
  const MaturedSavingsSheet({
    required this.wallet,
    required this.wallets,
    this.isMatured = true,
    this.goals,
    this.onSettle,
    this.onRollOver,
    this.onRenewCapital,
    this.onClaim,
    super.key,
  });

  final Wallet wallet;
  final bool isMatured;
  final List<Goal>? goals;

  /// Every wallet the money could go to, the matured one aside.
  final List<Wallet> wallets;

  /// Replaces the write. Used by tests.
  final void Function(double received, Map<String, double> to)? onSettle;

  /// Replaces the write. Gets the new end date and the interest kept, if any.
  final void Function(DateTime next, double interest)? onRollOver;

  /// Replaces a capital-only renewal. Gets the new end date, the interest
  /// paid out, and where it went.
  final void Function(
    DateTime next,
    double interest,
    Map<String, double> interestTo,
  )?
  onRenewCapital;

  /// Replaces a claim. Gets the original money, the interest, and where each
  /// went.
  final void Function(
    double capital,
    double interest,
    Map<String, double> capitalTo,
    Map<String, double> interestTo,
  )?
  onClaim;

  @override
  State<MaturedSavingsSheet> createState() => _MaturedSavingsSheetState();
}

class _MaturedSavingsSheetState extends State<MaturedSavingsSheet>
    with CheckAfterSave, WatchesGoals {
  bool get _isTimeDeposit => widget.wallet.isTimeDeposit;

  /// The interest the deposit should have paid, after tax, when its rate and
  /// dates are recorded. The amount starts on the balance plus this, so the
  /// user only changes it if the bank paid something else.
  late final double? _expectedInterest = (() {
    if (!widget.isMatured) return null;
    final gross = widget.wallet.estimatedTimeDepositInterest();
    return gross == null || gross <= 0 ? null : afterTax(gross);
  })();

  late final _amountController = TextEditingController(
    text: formatAmountInput(widget.wallet.balance + (_expectedInterest ?? 0)),
  );
  final _interestController = TextEditingController();

  /// Where the money went, by wallet: as much as came back, no more.
  Map<String, double> _to = const {};

  /// Time deposit claim details.
  late final double _principal = widget.wallet.timeDepositPrincipal > 0
      ? widget.wallet.timeDepositPrincipal
      : widget.wallet.balance;
  double get _interest {
    final typed = _interestController.text.trim().replaceAll(',', '');
    if (typed.isNotEmpty) {
      final amount = double.tryParse(typed);
      if (amount != null && amount.isFinite && amount >= 0) {
        return (amount * 100).round() / 100;
      }
    }
    final recorded = widget.wallet.balance - _principal;
    if (recorded > 0.005) return (recorded * 100).round() / 100;
    return (_expectedInterest ?? 0);
  }

  String? get _interestOverrideProblem {
    final text = _interestController.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    final amount = double.tryParse(text);
    if (amount == null ||
        !amount.isFinite ||
        amount < 0 ||
        amount > 999999999) {
      return 'Enter a valid interest amount.';
    }
    return null;
  }

  Map<String, double> _capitalTo = const {};
  Map<String, double> _interestTo = const {};
  bool _separateInterest = false;
  bool _saving = false;
  bool _queuedOffline = false;
  String? _actionProblem;
  StreamSubscription<TimeDepositSettlementUpdate>? _settlementSubscription;

  double get _tdTotal => _principal + _interest;

  /// Anywhere the money can land, savings included. Only the record that
  /// matured is left out, and any time deposit, which can't be added to.
  bool get _hasDestination => widget.wallets.any(
    (wallet) =>
        !wallet.archived &&
        wallet.id != widget.wallet.id &&
        !wallet.isTimeDeposit &&
        (isCashOnHand(wallet) ||
            wallet.isCashInBank ||
            (wallet.isSetAside && !wallet.isLockedSavings)),
  );

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
    _interestController.addListener(() => setState(() {}));
    _settlementSubscription = WalletService.timeDepositSettlementUpdates.listen(
      _onSettlementUpdate,
    );
    // Tests answer through the callbacks and have no goals behind them.
    watchGoals(
      given: widget.goals == null ? null : Stream.value(widget.goals!),
      walletsGiven:
          widget.onSettle != null ||
          widget.onRollOver != null ||
          widget.onRenewCapital != null ||
          widget.onClaim != null ||
          widget.goals != null,
    );
  }

  @override
  void dispose() {
    _settlementSubscription?.cancel();
    _amountController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  void _onSettlementUpdate(TimeDepositSettlementUpdate update) {
    if (!mounted || update.walletId != widget.wallet.id) return;
    if (update.status == TimeDepositSettlementStatus.completed) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _queuedOffline = false;
      _saving = false;
      _actionProblem =
          'This deposit was already handled on another device. Refresh your wallets.';
    });
  }

  double? get _typed {
    final text = _amountController.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    final amount = double.tryParse(text);
    return amount == null || !amount.isFinite ? null : amount;
  }

  /// The line under the field: what this amount leaves behind, or adds.
  String get _consequence {
    final amount = _typed;
    if (amount == null || !isRecordableAmount(amount)) {
      return minimumAmountError;
    }
    final taken = (amount * 100).round() / 100;
    final balance = (widget.wallet.balance * 100).round() / 100;

    if (taken > balance) {
      return '${formatPeso(taken - balance)} above the recorded balance, '
          'counted as interest.';
    }
    if (taken == balance) return 'This record closes.';
    return '${formatPeso(balance - taken)} stays in ${widget.wallet.name}.';
  }

  Future<DateTime?> _pickNewMaturity() async {
    final today = DateTime.now();
    final old = widget.wallet.maturityDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(old.year + 1, old.month, old.day),
      firstDate: DateTime(old.year, old.month, old.day + 1),
      lastDate: DateTime(today.year + 20),
      helpText: 'When does the new term end?',
    );
    return picked;
  }

  /// A short summary before money is claimed or renewed.
  Future<bool> _confirm({
    required String title,
    required List<String> lines,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('matured-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: confirmTextStyle(context),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _claimTimeDeposit() async {
    markTriedToSave();
    if (_problem != null || _saving) return;
    final confirmed = await _confirm(
      title: 'Claim this time deposit?',
      lines: [
        'Original money: ${formatPeso(_principal)}',
        'Interest: ${formatPeso(_interest)}',
        'Total: ${formatPeso(_tdTotal)}',
        'This closes the deposit.',
      ],
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);

    try {
      var result = const TimeDepositSettlementResult(
        TimeDepositSettlementStatus.completed,
      );
      if (widget.onClaim != null) {
        widget.onClaim!(_principal, _interest, _capitalTo, _interestTo);
      } else if (widget.onSettle != null) {
        widget.onSettle!(
          _tdTotal,
          _combinedDestinations(_capitalTo, _interestTo),
        );
      } else {
        result = await WalletService.claimTimeDeposit(
          wallet: widget.wallet,
          capitalTo: _capitalTo,
          interestTo: _separateInterest ? _interestTo : const {},
          capitalAmount: _principal,
          interestAmount: _interest,
          goals: heldGoals,
          wallets: widget.wallets,
        );
      }
      if (!mounted) return;
      if (result.status == TimeDepositSettlementStatus.completed) {
        Navigator.pop(context, true);
      } else if (result.status == TimeDepositSettlementStatus.queued) {
        setState(() {
          _saving = false;
          _queuedOffline = true;
          _actionProblem = null;
        });
      } else {
        setState(() {
          _saving = false;
          _actionProblem =
              'This deposit was already claimed or renewed. Refresh your wallets to see its latest status.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _actionProblem =
            'Could not claim this deposit. Check your connection and try again.';
      });
    }
  }

  Map<String, double> _combinedDestinations(
    Map<String, double> capital,
    Map<String, double> interest,
  ) {
    final result = <String, double>{};
    capital.forEach((id, amount) {
      result[id] = (result[id] ?? 0) + amount;
    });
    interest.forEach((id, amount) {
      result[id] = (result[id] ?? 0) + amount;
    });
    return result;
  }

  /// The same destination split, scaled to [target]. Used when the interest
  /// goes where the original money goes, as a default.
  Map<String, double> _scaledTo(Map<String, double> amounts, double target) {
    final total = amounts.values.fold<double>(0, (sum, amount) => sum + amount);
    if (total <= 0) return amounts;
    final result = <String, double>{};
    var left = (target * 100).round();
    final entries = amounts.entries.toList();
    for (var index = 0; index < entries.length; index++) {
      final share = index == entries.length - 1
          ? left
          : ((entries[index].value / total) * target * 100).round();
      if (share <= 0) continue;
      result[entries[index].key] = share / 100;
      left -= share;
    }
    return result;
  }

  Future<void> _renewTimeDeposit({required bool includeInterest}) async {
    markTriedToSave();
    if (_problem != null || _saving) return;

    final interestTo = _separateInterest
        ? _interestTo
        : _scaledTo(_capitalTo, _interest);
    if (!includeInterest && _interest > 0.005) {
      final problem = walletSplitProblem(
        purpose: SplitPurpose.receiving,
        amounts: interestTo,
        wallets: widget.wallets,
        goals: heldGoals,
        target: _interest,
        matchTarget: true,
      );
      if (problem != null) {
        setState(() {});
        return;
      }
    }

    final picked = await _pickNewMaturity();
    if (picked == null || !mounted) return;

    final newPrincipal = includeInterest ? _tdTotal : _principal;
    final confirmed = await _confirm(
      title: includeInterest
          ? 'Renew with the interest?'
          : 'Renew the original money?',
      lines: [
        'New time deposit: ${formatPeso(newPrincipal)}',
        'New end date: ${formatShortDate(picked)}',
        if (!includeInterest && _interest > 0.005)
          'Interest paid out: ${formatPeso(_interest)}',
        'The old record closes and stays in history.',
      ],
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);

    try {
      var result = const TimeDepositSettlementResult(
        TimeDepositSettlementStatus.completed,
      );
      if (widget.onRenewCapital != null && !includeInterest) {
        widget.onRenewCapital!(picked, _interest, interestTo);
      } else if (widget.onRollOver != null) {
        widget.onRollOver!(picked, includeInterest ? _interest : 0);
      } else {
        result = await WalletService.renewTimeDeposit(
          wallet: widget.wallet,
          maturityDate: picked,
          annualInterestRatePercent:
              widget.wallet.annualInterestRatePercent ?? 0,
          interestAmount: _interest,
          includeInterest: includeInterest,
          interestTo: includeInterest ? const {} : interestTo,
          goals: heldGoals,
          currentWallets: widget.wallets,
        );
      }
      if (!mounted) return;
      if (result.status == TimeDepositSettlementStatus.completed) {
        Navigator.pop(context, true);
      } else if (result.status == TimeDepositSettlementStatus.queued) {
        setState(() {
          _saving = false;
          _queuedOffline = true;
          _actionProblem = null;
        });
      } else {
        setState(() {
          _saving = false;
          _actionProblem =
              'This deposit was already claimed or renewed. Refresh your wallets to see its latest status.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _actionProblem =
            'Could not renew this deposit. Check your connection and try again.';
      });
    }
  }

  /// The old settlement path for government savings and part withdrawals.
  Future<void> _settleOther() async {
    markTriedToSave();
    if (_problem != null || _saving) return;
    final amount = _typed!;
    setState(() => _saving = true);

    if (widget.onSettle != null) {
      widget.onSettle!(amount, _to);
    } else if (widget.isMatured) {
      WalletService.settleMatured(
        wallet: widget.wallet,
        received: amount,
        to: _to,
        goals: heldGoals,
      );
    } else {
      WalletService.settleSavingsWithdrawal(
        wallet: widget.wallet,
        received: amount,
        to: _to,
        goals: heldGoals,
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _rollOverOther() async {
    final picked = await _pickNewMaturity();
    if (picked == null || !mounted) return;

    final amount = _typed;
    final balance = (widget.wallet.balance * 100).round() / 100;
    final interest = amount == null || amount <= balance
        ? 0.0
        : ((amount - balance) * 100).round() / 100;

    if (widget.onRollOver != null) {
      widget.onRollOver!(picked, interest);
    } else {
      WalletService.rollOverMaturity(widget.wallet, picked, interest: interest);
    }
    if (mounted) Navigator.pop(context, true);
  }

  /// What stops the money being moved out as it stands, or null.
  String? get _problem {
    if (_isTimeDeposit) {
      if (_interestOverrideProblem != null) return _interestOverrideProblem;
      if (!_hasDestination) return 'Add another wallet to move it into.';
      if (!_separateInterest) {
        return walletSplitProblem(
          purpose: SplitPurpose.receiving,
          amounts: _capitalTo,
          wallets: widget.wallets,
          goals: heldGoals,
          target: _tdTotal,
          matchTarget: true,
        );
      }
      final capitalProblem = walletSplitProblem(
        purpose: SplitPurpose.receiving,
        amounts: _capitalTo,
        wallets: widget.wallets,
        goals: heldGoals,
        target: _principal,
        matchTarget: true,
      );
      if (capitalProblem != null) return capitalProblem;
      return walletSplitProblem(
        purpose: SplitPurpose.receiving,
        amounts: _interestTo,
        wallets: widget.wallets,
        goals: heldGoals,
        target: _interest,
        matchTarget: true,
      );
    }

    final amount = _typed;
    if (amount == null || !isRecordableAmount(amount)) {
      return minimumAmountError;
    }
    if (!_hasDestination) return 'Add another wallet to move it into.';
    return walletSplitProblem(
      purpose: SplitPurpose.receiving,
      amounts: _to,
      wallets: widget.wallets,
      goals: heldGoals,
      target: amount,
      matchTarget: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final due = widget.wallet.maturityDate;
    final error = _actionProblem ?? (triedToSave ? _problem : null);

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
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.track,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.isMatured
                    ? '${widget.wallet.name} is ready to take out'
                    : 'Withdraw from ${widget.wallet.name}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                due == null || !widget.isMatured
                    ? 'Recorded balance ${formatPeso(widget.wallet.balance)}.'
                    : 'Due ${formatShortDate(due)} · recorded balance '
                          '${formatPeso(widget.wallet.balance)}.',
                style: TextStyle(fontSize: 13, color: colors.textBody),
              ),
              const SizedBox(height: 18),
              if (_isTimeDeposit && widget.isMatured)
                ..._timeDepositFields(context, error)
              else ...[
                TextField(
                  key: const Key('matured-amount'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [ThousandsSeparatorFormatter()],
                  decoration:
                      dialogFieldDecoration(
                        context,
                        'Amount it came to',
                      ).copyWith(
                        prefixText: '₱ ',
                        helperText: _expectedInterest == null
                            ? 'With any interest your bank paid.'
                            : 'Starts on ${formatPeso(widget.wallet.balance)} '
                                  'plus about ${formatPeso(_expectedInterest)} '
                                  'interest after tax. Change it to what '
                                  'your bank paid.',
                        helperMaxLines: 3,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _consequence,
                  key: const Key('matured-consequence'),
                  style: TextStyle(fontSize: 12, color: colors.primaryText),
                ),
                const SizedBox(height: 16),
                if (_hasDestination)
                  WalletSplitPicker(
                    key: const ValueKey('matured-to'),
                    wallets: widget.wallets,
                    goals: heldGoals,
                    purpose: SplitPurpose.receiving,
                    question: 'Where did it go?',
                    excludeWalletId: widget.wallet.id,
                    target: _typed ?? 0,
                    matchTarget: true,
                    totalLabel: 'Taken out',
                    onChanged: (amounts) => setState(() => _to = amounts),
                  ),
                const SizedBox(height: 6),
                if (goalMoneyInWallet(heldGoals, widget.wallet.id) > 0.005) ...[
                  Text(
                    '${formatPeso(goalMoneyInWallet(heldGoals, widget.wallet.id))} '
                    'of it is for your goals. It stays set aside for them in '
                    'the wallets you choose.',
                    key: const Key('matured-goal-money'),
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  'Choose one or more cash or bank wallets for the money.',
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error,
                    style: TextStyle(
                      fontSize: 12,
                      color: dangerColorOn(context),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    key: const Key('matured-settle'),
                    style: confirmButtonStyle(),
                    onPressed: _saving ? null : _settleOther,
                    child: Text(
                      widget.isMatured ? 'I withdrew it' : 'Record withdrawal',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.isMatured)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton(
                      key: const Key('matured-rollover'),
                      onPressed: _saving ? null : _rollOverOther,
                      style: confirmOutlineStyle(context),
                      child: const Text('It was renewed'),
                    ),
                  ),
              ],
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  // Grey: leaving this for another day decides nothing.
                  style: neutralTextStyle(context),
                  child: const Text('Not yet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _timeDepositFields(BuildContext context, String? error) {
    final colors = context.appColors;
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.pageBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            _moneyRow('Original money', _principal),
            const SizedBox(height: 6),
            _moneyRow('Interest earned', _interest),
            Divider(height: 20, color: colors.border),
            _moneyRow('Total at maturity', _tdTotal, bold: true),
          ],
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('matured-td-interest'),
        controller: _interestController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [ThousandsSeparatorFormatter()],
        decoration: dialogFieldDecoration(context, 'Actual interest (optional)')
            .copyWith(
              prefixText: 'â‚± ',
              helperText: _expectedInterest == null
                  ? 'Leave blank if no interest was paid.'
                  : 'Leave blank to use about ${formatPeso(_expectedInterest)} '
                        'from the saved rate and dates.',
              helperMaxLines: 2,
              errorText: _interestOverrideProblem,
            ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Text(
              'Send the interest to a different wallet',
              style: TextStyle(fontSize: 13, color: colors.textBody),
            ),
          ),
          Switch(
            key: const Key('matured-separate-interest'),
            value: _separateInterest,
            onChanged: (value) => setState(() {
              _separateInterest = value;
              _capitalTo = const {};
              _interestTo = const {};
            }),
          ),
        ],
      ),
      const SizedBox(height: 8),
      WalletSplitPicker(
        key: const ValueKey('matured-to'),
        wallets: widget.wallets,
        goals: heldGoals,
        purpose: SplitPurpose.receiving,
        question: _separateInterest
            ? 'Where does the original money go?'
            : 'Where does it go?',
        excludeWalletId: widget.wallet.id,
        target: _separateInterest ? _principal : _tdTotal,
        matchTarget: true,
        includeSavings: true,
        totalLabel: _separateInterest ? 'Original money' : 'Claimed',
        onChanged: (amounts) => setState(() => _capitalTo = amounts),
      ),
      if (_separateInterest) ...[
        const SizedBox(height: 12),
        WalletSplitPicker(
          key: const ValueKey('matured-interest-to'),
          wallets: widget.wallets,
          goals: heldGoals,
          purpose: SplitPurpose.receiving,
          question: 'Where does the interest go?',
          excludeWalletId: widget.wallet.id,
          target: _interest,
          matchTarget: true,
          includeSavings: true,
          totalLabel: 'Interest',
          onChanged: (amounts) => setState(() => _interestTo = amounts),
        ),
      ],
      const SizedBox(height: 6),
      if (goalMoneyInWallet(heldGoals, widget.wallet.id) > 0.005) ...[
        Text(
          '${formatPeso(goalMoneyInWallet(heldGoals, widget.wallet.id))} '
          'of it is for your goals. It stays set aside for them in the '
          'wallets you choose.',
          key: const Key('matured-goal-money'),
          style: TextStyle(fontSize: 12, color: colors.textBody),
        ),
        const SizedBox(height: 6),
      ],
      Text(
        'Cash, bank, e-wallet, savings deposit or demand deposit.',
        style: TextStyle(fontSize: 12, color: colors.textBody),
      ),
      if (_queuedOffline) ...[
        const SizedBox(height: 10),
        Text(
          'Saved on this device. Your wallets update when you reconnect.',
          key: const Key('matured-offline-queued'),
          style: TextStyle(fontSize: 12, color: colors.primaryText),
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: 10),
        Text(
          error,
          style: TextStyle(fontSize: 12, color: dangerColorOn(context)),
        ),
      ],
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          key: const Key('matured-settle'),
          style: confirmButtonStyle(),
          onPressed: _saving || _queuedOffline || _problem != null
              ? null
              : _claimTimeDeposit,
          child: const Text('Claim original money + interest'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton(
          key: const Key('matured-rollover'),
          style: confirmOutlineStyle(context),
          onPressed: _saving || _queuedOffline
              ? null
              : () => _renewTimeDeposit(includeInterest: true),
          child: const Text('Renew with the interest'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton(
          key: const Key('matured-renew-capital'),
          style: confirmOutlineStyle(context),
          onPressed: _saving || _queuedOffline
              ? null
              : () => _renewTimeDeposit(includeInterest: false),
          child: const Text('Renew the original money only'),
        ),
      ),
    ];
  }

  Widget _moneyRow(String label, double amount, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: context.appColors.textBody,
            ),
          ),
        ),
        Text(
          formatPeso(amount),
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: context.appColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
