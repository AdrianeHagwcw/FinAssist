import '../utils/money_format.dart';
import '../utils/ph_time.dart';
import 'app_transaction.dart';
import 'bill.dart';
import 'reminder.dart';
import 'report.dart';
import 'transaction_filter.dart';
import 'wallet.dart';

/// The one short line Home shows above this month's spending.
///
/// Rule-based on purpose: it reads the user's own records, works offline, and
/// is replaced by generated text only once the AI phases land.
class DashboardTip {
  const DashboardTip({required this.title, required this.message});

  final String title;
  final String message;
}

/// Picks the tip that is worth saying now, most urgent first.
DashboardTip dashboardTipFor({
  required List<Wallet>? wallets,
  required List<AppTransaction>? transactions,
  required List<BillInstance> bills,
  required DateTime now,
}) {
  if (wallets != null && wallets.isEmpty) {
    return const DashboardTip(
      title: 'Start with what you hold',
      message:
          'Add a wallet with the money you have right now. Everything else '
          'in FinAssist is built on top of it.',
    );
  }

  final records = transactions ?? const <AppTransaction>[];
  if (transactions != null && records.isEmpty) {
    return const DashboardTip(
      title: 'A small step today',
      message:
          'Record your next expense or income with the + button, and your '
          'spending picture starts filling in.',
    );
  }

  final due = billsDueSoon(bills, now: now);
  if (due.isNotEmpty) {
    final soonest = due.first;
    final overdue = soonest.dueDate.isBefore(
      DateTime(now.year, now.month, now.day),
    );
    return DashboardTip(
      title: overdue ? 'A bill is past its date' : 'A bill needs you soon',
      message:
          '${soonest.name} is ${overdue ? 'overdue' : 'due shortly'}. Paying '
          'it now keeps your Safe to Spend honest.',
    );
  }

  final balance = wallets == null ? null : totalWalletBalance(wallets);
  if (balance != null && balance <= 0) {
    return const DashboardTip(
      title: 'Your wallets are empty',
      message:
          'Record your next income so FinAssist can work out what is safe to '
          'spend for the rest of the month.',
    );
  }

  final today = DateTime(now.year, now.month, now.day);
  final loggedToday = records.any((t) {
    final day = philippineTime(t.date);
    return !t.isLegacy &&
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
  });
  if (transactions != null && !loggedToday) {
    return const DashboardTip(
      title: 'Nothing logged today',
      // Names the figure it protects. "The figure on this screen" left
      // the reader to guess which of the four on Home it meant.
      message:
          'Add what you spent with + so Safe to Spend stays right. Even '
          'small amounts count.',
    );
  }

  return _monthTip(records, now);
}

/// What this month's spending says, from the user's own records: where
/// most of it went, or how it compares with the same days last month.
DashboardTip _monthTip(List<AppTransaction> records, DateTime now) {
  final month = transactionsIn(records, ReportPeriod.monthOf(now));
  final spending = spendingByCategory(month);
  final total = spending.fold<double>(0, (sum, e) => sum + e.value);
  if (total <= 0) {
    return const DashboardTip(
      title: 'Nothing spent yet this month',
      message:
          'Record each expense as it happens, and This Month shows where '
          'your money goes.',
    );
  }

  final top = spending.first;
  final share = (top.value / total * 100).round();
  if (spending.length > 1 && share >= 50) {
    return DashboardTip(
      title: 'Where most of it goes',
      message: '${top.key} is $share% of your spending this month.',
    );
  }

  // The same days of last month, so a month half gone is not compared with
  // a whole one.
  final lastDay = DateTime(now.year, now.month, 0).day;
  final lastMonth = ReportPeriod(
    DateTime(now.year, now.month - 1),
    DateTime(now.year, now.month - 1, now.day < lastDay ? now.day : lastDay),
  );
  final before = inAndOut(transactionsIn(records, lastMonth)).moneyOut;
  final spent = inAndOut(month).moneyOut;
  final difference = spent - before;
  if (before > 0 && difference.abs() >= 1) {
    return DashboardTip(
      title: 'Compared with last month',
      message: difference < 0
          ? "You've spent ${formatPeso(-difference)} less than by this day "
                'last month.'
          : "You've spent ${formatPeso(difference)} more than by this day "
                'last month.',
    );
  }

  return DashboardTip(
    title: 'Where most of it goes',
    message:
        '${top.key} is your biggest spending this month, at '
        '${formatPeso(top.value)}.',
  );
}
