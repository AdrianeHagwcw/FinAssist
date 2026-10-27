import 'package:flutter/material.dart';

import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../theme/app_colors.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import 'wallet_split_picker.dart';

// The picker these helpers serve, for screens that only import this file.
export 'wallet_split_picker.dart';

/// What [wallet] still has free for this goal once [otherGoals] are counted.
/// Nothing can be promised from a wallet without a recorded balance.
double goalFundingRoom(Wallet wallet, Iterable<Goal> otherGoals) =>
    wallet.hasRecordedBalance ? freeInWallet(wallet, otherGoals) : 0;

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
