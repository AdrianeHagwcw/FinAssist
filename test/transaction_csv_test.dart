import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/backend/utils/transaction_csv.dart';

AppTransaction entry({
  String id = 't1',
  TransactionType type = TransactionType.expense,
  double amount = 120,
  String label = 'Food',
  DateTime? date,
  String? walletId = 'w1',
  String? toWalletId,
  String? note,
  bool isLegacy = false,
  String? billInstanceId,
  String? debtId,
  double interest = 0,
}) {
  return AppTransaction(
    id: id,
    type: type,
    amount: amount,
    label: label,
    date: date ?? DateTime(2026, 9, 25, 14, 30),
    walletId: walletId,
    toWalletId: toWalletId,
    note: note,
    isLegacy: isLegacy,
    billInstanceId: billInstanceId,
    debtId: debtId,
    interest: interest,
  );
}

const walletNames = {'w1': 'Cash', 'w2': 'GCash', 'w3': 'BPI'};
const walletTypes = {
  'w1': WalletType.cash,
  'w2': WalletType.gcash,
  'w3': WalletType.bank,
};

/// The rows of a built file, without the trailing empty line.
List<String> rowsOf(String csv) {
  final rows = csv.split('\r\n');
  rows.removeLast();
  return rows;
}

void main() {
  group('the header', () {
    test('names every column, in the order they are defined', () {
      final header = rowsOf(buildTransactionCsv([entry()])).first;

      expect(
        header,
        'Date,Time,Type,Category / Source,Amount,Interest Included,Wallet,'
        'To Wallet,Tag',
      );
      expect(header.split(',').length, csvColumns.length);
    });

    test('is all there is when nothing has been recorded', () {
      expect(rowsOf(buildTransactionCsv(const [])).length, 1);
    });
  });

  group('a row', () {
    test('carries the date, time, type, amount and wallet', () {
      final csv = buildTransactionCsv([
        entry(date: DateTime(2026, 1, 7, 9, 5), amount: 1234.5),
      ], walletNames: walletNames);

      expect(
        rowsOf(csv).last,
        '2026-01-07,09:05,Outflow,Food,1234.50,,Cash,,Regular',
      );
    });

    test('writes the amount plainly, for a spreadsheet to add up', () {
      final csv = buildTransactionCsv([entry(amount: 20000)]);

      expect(csv, contains(',20000.00,'));
      expect(csv, isNot(contains('₱')));
      expect(csv, isNot(contains('20,000')));
    });

    test('names both wallets of a transfer', () {
      final csv = buildTransactionCsv(
        [
          entry(
            type: TransactionType.transfer,
            label: 'Transfer',
            walletId: 'w1',
            toWalletId: 'w2',
          ),
        ],
        walletNames: walletNames,
        walletTypes: walletTypes,
      );

      expect(
        rowsOf(csv).last,
        contains(',Deposit,Transfer,120.00,,Cash,GCash,'),
      );
    });

    test('names a transfer the way the CPA does', () {
      final csv = buildTransactionCsv(
        [
          entry(
            type: TransactionType.transfer,
            label: 'Transfer',
            walletId: 'w3',
            toWalletId: 'w1',
          ),
          entry(
            type: TransactionType.transfer,
            label: 'Transfer',
            walletId: 'w1',
            toWalletId: 'w3',
          ),
          entry(
            type: TransactionType.transfer,
            label: 'Transfer',
            walletId: 'w2',
            toWalletId: 'w3',
          ),
        ],
        walletNames: walletNames,
        walletTypes: walletTypes,
      );

      final rows = rowsOf(csv);
      // Bank to cash, cash to bank, then e-wallet to bank.
      expect(rows[1], contains(',Withdrawal,Transfer,'));
      expect(rows[2], contains(',Deposit,Transfer,'));
      expect(rows[3], contains(',Transfer,Transfer,'));
    });

    test('uses deposit rules for savings and demand deposit transfers', () {
      final cash = Wallet(
        id: 'cash',
        name: 'Cash',
        type: WalletType.cash,
        balance: 0,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
      );
      final ewallet = Wallet(
        id: 'ewallet',
        name: 'GCash',
        type: WalletType.gcash,
        balance: 0,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 1,
      );
      final bank = Wallet(
        id: 'bank',
        name: 'BPI',
        type: WalletType.bank,
        balance: 0,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 2,
      );
      final savings = Wallet(
        id: 'savings',
        name: 'Savings Deposit',
        type: WalletType.other,
        balance: 0,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 3,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit.name,
      );
      final demand = Wallet(
        id: 'demand',
        name: 'Demand Deposit',
        type: WalletType.other,
        balance: 0,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 4,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.demandDeposit.name,
      );

      final csv = buildTransactionCsv(
        [
          entry(
            type: TransactionType.transfer,
            walletId: 'cash',
            toWalletId: 'savings',
          ),
          entry(
            type: TransactionType.transfer,
            walletId: 'ewallet',
            toWalletId: 'savings',
          ),
          entry(
            type: TransactionType.transfer,
            walletId: 'bank',
            toWalletId: 'savings',
          ),
          entry(
            type: TransactionType.transfer,
            walletId: 'savings',
            toWalletId: 'cash',
          ),
          entry(
            type: TransactionType.transfer,
            walletId: 'savings',
            toWalletId: 'ewallet',
          ),
          entry(
            type: TransactionType.transfer,
            walletId: 'savings',
            toWalletId: 'bank',
          ),
          entry(
            type: TransactionType.transfer,
            walletId: 'cash',
            toWalletId: 'demand',
          ),
        ],
        walletRecords: {
          for (final wallet in [cash, ewallet, bank, savings, demand])
            wallet.id: wallet,
        },
      );

      expect(rowsOf(csv).skip(1).map((row) => row.split(',')[2]), [
        'Deposit',
        'Deposit',
        'Transfer',
        'Withdrawal',
        'Withdrawal',
        'Transfer',
        'Deposit',
      ]);
    });

    test('a transfer without known wallets stays a plain transfer', () {
      final csv = buildTransactionCsv([
        entry(
          type: TransactionType.transfer,
          label: 'Transfer',
          walletId: 'gone',
          toWalletId: 'cash',
        ),
      ], walletTypes: walletTypes);

      expect(rowsOf(csv).last, contains(',Transfer,Transfer,'));
    });

    test('says Inflow and Outflow, as the app does', () {
      final csv = buildTransactionCsv([
        entry(type: TransactionType.income, label: 'Salary'),
        entry(),
      ]);

      expect(rowsOf(csv)[1], contains(',Inflow,Salary,'));
      expect(rowsOf(csv)[2], contains(',Outflow,Food,'));
    });

    test('names a goal movement as the app lists it, wallet to goal', () {
      AppTransaction goalRow(String id, String label, String walletId) => entry(
        id: id,
        type: TransactionType.goal,
        label: label,
        walletId: walletId,
        note: 'Laptop',
      );
      final rows = rowsOf(
        buildTransactionCsv(
          [
            goalRow('t1', goalDepositLabel, 'w1'),
            goalRow('t2', goalWithdrawalLabel, 'w1'),
            goalRow('t3', goalDepositLabel, 'w3'),
            goalRow('t4', goalWithdrawalLabel, 'w3'),
          ],
          walletNames: walletNames,
          walletTypes: walletTypes,
        ),
      );

      // Cash on hand in or out is a Deposit or Withdrawal, a bank either way
      // a Transfer; the goal sits on the other side.
      expect(rows[1], endsWith(',Deposit,Goal,120.00,,Cash,Laptop,Regular'));
      expect(rows[2], endsWith(',Withdrawal,Goal,120.00,,Laptop,Cash,Regular'));
      expect(rows[3], endsWith(',Transfer,Goal,120.00,,BPI,Laptop,Regular'));
      expect(rows[4], endsWith(',Transfer,Goal,120.00,,Laptop,BPI,Regular'));
    });

    test('shows how much of a payment was interest', () {
      final csv = buildTransactionCsv([
        entry(amount: 2000, interest: 333.33, billInstanceId: 'loan_20261005'),
      ]);

      expect(rowsOf(csv).last, contains(',2000.00,333.33,'));
    });

    test('leaves the wallet blank when there is none to name', () {
      final csv = buildTransactionCsv([
        entry(walletId: null),
        entry(walletId: 'deleted-wallet'),
      ], walletNames: walletNames);

      for (final row in rowsOf(csv).skip(1)) {
        expect(row, contains('120.00,,,'));
      }
    });

    test('keeps Filipino characters as they were typed', () {
      final csv = buildTransactionCsv([
        entry(label: 'Baon ni Iñigo, ₱50 sukli'),
      ]);

      expect(csv, contains('Baon ni Iñigo'));
      expect(csv, contains('₱50 sukli'));
    });
  });

  group('cells that could break the file', () {
    test('a typed name with a comma stays one cell', () {
      final csv = buildTransactionCsv([entry(label: 'Rice, eggs and milk')]);

      expect(csv, contains('"Rice, eggs and milk"'));
      expect(rowsOf(csv).length, 2);
    });

    test('quotes in a typed name are doubled inside the quoted cell', () {
      final csv = buildTransactionCsv([entry(label: 'Said "sale" today')]);

      expect(csv, contains('"Said ""sale"" today"'));
    });

    test('a typed name on two lines stays in its own row', () {
      final csv = buildTransactionCsv([entry(label: 'Lunch\nwith Ana')]);

      expect(csv, contains('"Lunch\nwith Ana"'));
      // The line break inside the quotes is not a new record.
      expect(rowsOf(csv).length, 2);
    });

    test('a typed name that looks like a formula is not run as one', () {
      final csv = buildTransactionCsv([
        entry(label: '=SUM(A1:A9)'),
        entry(label: '+63 917 123 4567'),
        entry(label: '-50 refund'),
        entry(label: '@everyone'),
      ]);

      expect(csv, contains("'=SUM(A1:A9)"));
      expect(csv, contains("'+63 917 123 4567"));
      expect(csv, contains("'-50 refund"));
      expect(csv, contains("'@everyone"));
    });

    test('dates and amounts are left alone', () {
      final csv = buildTransactionCsv([entry()]);

      expect(csv, isNot(contains("'2026")));
      expect(csv, isNot(contains("'120.00")));
    });
  });

  group('the tag', () {
    test('says what kind of record it is, old records first', () {
      String tagOf(AppTransaction transaction) =>
          rowsOf(buildTransactionCsv([transaction])).last.split(',').last;

      expect(tagOf(entry()), 'Regular');
      expect(tagOf(entry(billInstanceId: 'b1')), 'Bill payment');
      expect(tagOf(entry(debtId: 'd1')), 'Debt');
      expect(tagOf(entry(isLegacy: true)), 'Old record');
      expect(
        tagOf(entry(isLegacy: true, billInstanceId: 'b1', debtId: 'd1')),
        'Old record',
      );
      expect(tagOf(entry(billInstanceId: 'b1', debtId: 'd1')), 'Bill payment');
    });

    test('tells installment, debt and early payoff payments apart', () {
      String tagOf(String instanceId) => rowsOf(
        buildTransactionCsv(
          [entry(billInstanceId: instanceId)],
          billTags: {'phone': 'Installment payment', 'sss': 'Debt payment'},
        ),
      ).last.split(',').last;

      expect(tagOf('phone_20261005'), 'Installment payment');
      expect(tagOf('sss_20261015'), 'Debt payment');
      expect(tagOf('sss_payoff'), 'Paid off early');
      expect(tagOf('meralco_20261020'), 'Bill payment');
    });
  });

  group('the file itself', () {
    test('starts with the mark that tells Excel it is UTF-8', () {
      final bytes = transactionCsvBytes(buildTransactionCsv([entry()]));

      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), startsWith('Date,Time'));
    });

    test('is named after the day it was exported', () {
      expect(
        transactionCsvFileName(DateTime(2026, 9, 25)),
        'FinAssist-transactions-2026-09-25.csv',
      );
      expect(
        transactionCsvFileName(DateTime(2026, 1, 7)),
        'FinAssist-transactions-2026-01-07.csv',
      );
    });

    test('keeps the order it was given, which is newest first', () {
      final csv = buildTransactionCsv([
        entry(id: 'new', label: 'Newest', date: DateTime(2026, 9, 25)),
        entry(id: 'old', label: 'Oldest', date: DateTime(2026, 9, 1)),
      ]);

      final rows = rowsOf(csv);
      expect(rows[1], contains('Newest'));
      expect(rows[2], contains('Oldest'));
    });
  });

  test('a month of records reads as the app shows them', () {
    Wallet account(
      String id,
      String name,
      WalletType type, {
      WalletPurpose purpose = WalletPurpose.spending,
      SavingsKind? kind,
    }) => Wallet(
      id: id,
      name: name,
      type: type,
      balance: 1000,
      startingBalance: 1000,
      receivesIncome: false,
      archived: false,
      sortOrder: 0,
      purpose: purpose,
      savingsKind: kind?.name,
    );
    final accounts = [
      account('cash', 'Cash', WalletType.cash),
      account('maya', 'Maya', WalletType.maya),
      account('bank', 'GoTyme Bank', WalletType.bank),
      account(
        'sd',
        'Savings Deposit',
        WalletType.other,
        purpose: WalletPurpose.savings,
        kind: SavingsKind.savingsDeposit,
      ),
    ];
    AppTransaction row(
      TransactionType type,
      double amount,
      String label, {
      required String from,
      String? to,
      String? note,
      String? bill,
      double interest = 0,
    }) => entry(
      type: type,
      amount: amount,
      label: label,
      walletId: from,
      toWalletId: to,
      note: note,
      billInstanceId: bill,
      interest: interest,
    );

    final rows = rowsOf(
      buildTransactionCsv(
        [
          row(TransactionType.income, 15000, 'Salary', from: 'cash'),
          row(
            TransactionType.transfer,
            500,
            'Transfer',
            from: 'cash',
            to: 'bank',
          ),
          row(
            TransactionType.transfer,
            200,
            'Transfer',
            from: 'maya',
            to: 'bank',
          ),
          // Out of savings: a withdrawal, with its interest as income.
          row(TransactionType.income, 24.66, 'Interest', from: 'sd'),
          row(
            TransactionType.transfer,
            2000,
            'Transfer',
            from: 'sd',
            to: 'cash',
          ),
          row(
            TransactionType.goal,
            500,
            goalDepositLabel,
            from: 'cash',
            note: 'Laptop',
          ),
          row(
            TransactionType.expense,
            1716.67,
            'Bills',
            from: 'bank',
            bill: 'loan_2026-11',
            interest: 50,
          ),
        ],
        walletNames: {for (final a in accounts) a.id: a.name},
        walletTypes: {for (final a in accounts) a.id: a.type},
        walletRecords: {for (final a in accounts) a.id: a},
        billTags: const {'loan': 'Debt payment'},
      ),
    ).skip(1).map((line) => line.substring(17)).toList();

    expect(rows, [
      'Inflow,Salary,15000.00,,Cash,,Regular',
      'Deposit,Transfer,500.00,,Cash,GoTyme Bank,Regular',
      'Transfer,Transfer,200.00,,Maya,GoTyme Bank,Regular',
      'Inflow,Interest,24.66,,Savings Deposit,,Regular',
      'Withdrawal,Transfer,2000.00,,Savings Deposit,Cash,Regular',
      'Deposit,Goal,500.00,,Cash,Laptop,Regular',
      'Outflow,Bills,1716.67,50.00,GoTyme Bank,,Debt payment',
    ]);
  });
}
