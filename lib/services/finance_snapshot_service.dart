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
import 'wallet_service.dart';

/// The user's records for the assistant, kept up to date as they change.
///
/// Read the same way as Home's Safe to Spend card, from the phone's saved
/// copy, so it works offline when cached records are available. Incomplete
/// records emit an error rather than presenting missing obligations as zero.
Stream<FinanceSnapshot> watchFinanceSnapshot({
  Stream<List<Wallet>>? walletStream,
  Stream<List<AppTransaction>>? transactionStream,
  Stream<Map<String, dynamic>?>? profileStream,
  Stream<List<AllocationCycle>>? cycleStream,
  Stream<List<Goal>>? goalStream,
  Stream<List<Debt>>? debtStream,
  Stream<List<Bill>>? billStream,
  Future<List<BillInstance>> Function()? loadBills,
  DateTime Function()? clock,
}) {
  final subscriptions = <StreamSubscription<Object?>>[];
  late final StreamController<FinanceSnapshot> controller;

  var wallets = const <Wallet>[];
  var transactions = const <AppTransaction>[];
  var goals = const <Goal>[];
  var debts = const <Debt>[];
  var bills = const <BillInstance>[];

  // The first answer waits for these, so it is never worked out from half
  // the picture.
  var walletsRead = false;
  var transactionsRead = false;
  var goalsRead = false;
  var debtsRead = false;
  var billsRead = false;
  var schedulesRead = false;

  void send() {
    if (!walletsRead ||
        !transactionsRead ||
        !goalsRead ||
        !debtsRead ||
        !billsRead ||
        !schedulesRead) {
      return;
    }
    if (controller.isClosed) return;
    controller.add(
      FinanceSnapshot(
        now: (clock ?? DateTime.now)(),
        wallets: wallets,
        transactions: transactions,
        bills: bills,
        goals: goals,
        debts: debts,
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
    billsRead = false;
    (loadBills ?? AllocationService.loadOutstandingBills)()
        .then((loaded) {
          if (signature != billsReadFor || controller.isClosed) return;
          bills = loaded;
          billsRead = true;
          send();
        })
        .catchError((Object error) {
          if (signature != billsReadFor || controller.isClosed) return;
          controller.addError(error);
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
            if (!controller.isClosed) {
              controller.addError(
                StateError('Could not load financial records.'),
              );
            }
          },
        ),
      );
    } catch (_) {
      // Signed out between screens: nothing to read.
      onFail?.call();
      if (!controller.isClosed) {
        controller.addError(StateError('Could not load financial records.'));
      }
    }
  }

  controller = StreamController<FinanceSnapshot>(
    onListen: () {
      watch(() => walletStream ?? WalletService.watchWallets(), (value) {
        wallets = value;
        walletsRead = true;
      }, onFail: () => walletsRead = false);
      watch(() => transactionStream ?? WalletService.watchTransactions(), (
        value,
      ) {
        transactions = value;
        transactionsRead = true;
        readBills();
      }, onFail: () => transactionsRead = false);
      watch(() => goalStream ?? GoalService.watchGoals(), (value) {
        goals = value;
        goalsRead = true;
      }, onFail: () => goalsRead = false);
      watch(() => debtStream ?? DebtService.watchDebts(), (value) {
        debts = value;
        debtsRead = true;
      }, onFail: () => debtsRead = false);
      watch(() => billStream ?? BillService.watchBills(), (_) {
        schedulesRead = true;
        billsVersion++;
        readBills();
      }, onFail: () => schedulesRead = false);
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
