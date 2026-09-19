import 'dart:async';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/bill.dart';
import '../models/debt.dart';
import '../models/finance_snapshot.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import 'allocation_service.dart';
import 'bill_service.dart';
import 'budget_service.dart';
import 'debt_service.dart';
import 'goal_service.dart';
import 'user_profile_service.dart';
import 'wallet_service.dart';

/// The user's records for the assistant, kept up to date as they change.
///
/// Read the same way as Home's Safe to Spend card, from the phone's saved
/// copy, so it works offline. A part that can't be read is left empty rather
/// than holding back the rest.
Stream<FinanceSnapshot> watchFinanceSnapshot() {
  final subscriptions = <StreamSubscription<Object?>>[];
  late final StreamController<FinanceSnapshot> controller;

  var wallets = const <Wallet>[];
  var transactions = const <AppTransaction>[];
  var cycles = const <AllocationCycle>[];
  var goals = const <Goal>[];
  var debts = const <Debt>[];
  var bills = const <BillInstance>[];
  Map<String, dynamic>? profile;

  // The first answer waits for these, so it is never worked out from half
  // the picture.
  var walletsRead = false;
  var transactionsRead = false;
  var profileRead = false;

  void send() {
    if (!walletsRead || !transactionsRead || !profileRead) return;
    if (controller.isClosed) return;
    final income = profile?['income'];
    controller.add(
      FinanceSnapshot(
        now: DateTime.now(),
        wallets: wallets,
        transactions: transactions,
        bills: bills,
        goals: goals,
        debts: debts,
        incomeFrequency: profile?['incomeFrequency'] as String?,
        usualIncome: income is num && income > 0 ? income.toDouble() : null,
        lastIncomeAt: lastPayday(
          cycles,
          usualSource: profile?['incomeSource'] as String?,
        ),
        savingsReserve: savingsReserveFrom(profile),
        customDailyLimit: customDailyLimitFrom(profile),
      ),
    );
  }

  // Bills are read again when a payment is recorded or a bill changes.
  var billsVersion = 0;
  Object? billsReadFor;
  void readBills() {
    final signature = Object.hash(
      transactions.length,
      transactions.isEmpty ? null : transactions.first.id,
      billsVersion,
    );
    if (signature == billsReadFor) return;
    billsReadFor = signature;
    AllocationService.loadOutstandingBills()
        .then((loaded) {
          bills = loaded;
          send();
        })
        .catchError((Object _) {
          // Offline and never saved: answer as if no bills are due.
        });
  }

  void watch<T>(
    Stream<T> Function() open,
    void Function(T value) onValue, {
    void Function()? onFail,
  }) {
    try {
      subscriptions.add(
        open().listen(
          (value) {
            onValue(value);
            send();
          },
          onError: (Object _) {
            onFail?.call();
            send();
          },
        ),
      );
    } catch (_) {
      // Signed out between screens: nothing to read.
      onFail?.call();
    }
  }

  controller = StreamController<FinanceSnapshot>(
    onListen: () {
      watch(WalletService.watchWallets, (value) {
        wallets = value;
        walletsRead = true;
      }, onFail: () => walletsRead = true);
      watch(WalletService.watchTransactions, (value) {
        transactions = value;
        transactionsRead = true;
        readBills();
      }, onFail: () => transactionsRead = true);
      watch(UserProfileService.watchProfile, (snapshot) {
        profile = snapshot.data();
        profileRead = true;
      }, onFail: () => profileRead = true);
      watch(BudgetService.watchRecentCycles, (value) => cycles = value);
      watch(GoalService.watchGoals, (value) => goals = value);
      watch(DebtService.watchDebts, (value) => debts = value);
      watch(BillService.watchBills, (_) {
        billsVersion++;
        readBills();
      });
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
