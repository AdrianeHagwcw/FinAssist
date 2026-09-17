import 'app_transaction.dart';
import 'bill.dart';
import 'reminder.dart';
import 'wallet.dart';

/// The one short line Home shows above this month's spending.
///
/// Rule-based on purpose: it reads the user's own records, works offline, and
/// is replaced by generated text only once the AI phases land.
class DashboardTip {
  const DashboardTip({
    required this.title,
    required this.message,
    this.showHistory = false,
  });

  final String title;
  final String message;

  /// Whether the tip offers the pay-cycle history.
  final bool showHistory;
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
          'spend for the rest of the period.',
    );
  }

  final today = DateTime(now.year, now.month, now.day);
  final loggedToday = records.any(
    (t) =>
        !t.isLegacy &&
        t.date.year == today.year &&
        t.date.month == today.month &&
        t.date.day == today.day,
  );
  if (transactions != null && !loggedToday) {
    return const DashboardTip(
      title: 'Nothing logged today',
      message:
          'Even small spending counts. Add today\'s expenses with + so the '
          'figure on this screen stays true.',
    );
  }

  return const DashboardTip(
    title: 'Close the loop on payday',
    message:
        'Review what came in, what you set aside, and what is still left to '
        'decide.',
    showHistory: true,
  );
}
