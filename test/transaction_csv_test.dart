import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/utils/transaction_csv.dart';

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
  );
}

const walletNames = {'w1': 'Cash', 'w2': 'GCash'};

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
        'Date,Time,Type,Category / Source,Amount,Wallet,To Wallet,Note,Tag',
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
        '2026-01-07,09:05,Expense,Food,1234.50,Cash,,,Regular',
      );
    });

    test('writes the amount plainly, for a spreadsheet to add up', () {
      final csv = buildTransactionCsv([entry(amount: 20000)]);

      expect(csv, contains(',20000.00,'));
      expect(csv, isNot(contains('₱')));
      expect(csv, isNot(contains('20,000')));
    });

    test('names both wallets of a transfer', () {
      final csv = buildTransactionCsv([
        entry(
          type: TransactionType.transfer,
          label: 'Transfer',
          walletId: 'w1',
          toWalletId: 'w2',
        ),
      ], walletNames: walletNames);

      expect(rowsOf(csv).last, contains(',Transfer,Transfer,120.00,Cash,GCash,'));
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
        entry(label: 'Pagkain', note: 'Baon ni Iñigo, ₱50 sukli'),
      ]);

      expect(csv, contains('Baon ni Iñigo'));
      expect(csv, contains('₱50 sukli'));
    });
  });

  group('cells that could break the file', () {
    test('a note with a comma stays one cell', () {
      final csv = buildTransactionCsv([
        entry(note: 'Rice, eggs and milk'),
      ]);

      expect(csv, contains('"Rice, eggs and milk"'));
      expect(rowsOf(csv).length, 2);
    });

    test('quotes in a note are doubled inside the quoted cell', () {
      final csv = buildTransactionCsv([entry(note: 'Said "sale" today')]);

      expect(csv, contains('"Said ""sale"" today"'));
    });

    test('a note written on two lines stays in its own row', () {
      final csv = buildTransactionCsv([entry(note: 'Lunch\nwith Ana')]);

      expect(csv, contains('"Lunch\nwith Ana"'));
      // The line break inside the quotes is not a new record.
      expect(rowsOf(csv).length, 2);
    });

    test('a note that looks like a formula is not run as one', () {
      final csv = buildTransactionCsv([
        entry(note: '=SUM(A1:A9)'),
        entry(note: '+63 917 123 4567'),
        entry(note: '-50 refund'),
        entry(note: '@everyone'),
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
      expect(tagOf(entry(debtId: 'd1')), 'Loan');
      expect(tagOf(entry(isLegacy: true)), 'Old record');
      expect(
        tagOf(entry(isLegacy: true, billInstanceId: 'b1', debtId: 'd1')),
        'Old record',
      );
      expect(tagOf(entry(billInstanceId: 'b1', debtId: 'd1')), 'Bill payment');
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
}
