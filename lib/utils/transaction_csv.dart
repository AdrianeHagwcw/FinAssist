import 'dart:convert';
import 'dart:typed_data';

import '../models/app_transaction.dart';

/// Builds the spreadsheet the user exports from Reports.
///
/// Nothing here touches Firebase, so the whole file can be checked by tests.
/// Adding a field to the export means adding one entry to [csvColumns].

/// One column of the exported file.
class CsvColumn {
  const CsvColumn(this.header, this.read, {this.isText = true});

  final String header;

  /// The cell for one transaction. [walletNames] maps a wallet id to its name.
  final String Function(AppTransaction entry, Map<String, String> walletNames)
  read;

  /// Text cells are guarded against being read as a spreadsheet formula.
  /// Dates and amounts are not, so they stay usable as dates and numbers.
  final bool isText;
}

/// Every column of the export, in the order they appear in the file.
const List<CsvColumn> csvColumns = [
  CsvColumn('Date', _date, isText: false),
  CsvColumn('Time', _time, isText: false),
  CsvColumn('Type', _type),
  CsvColumn('Category / Source', _label),
  CsvColumn('Amount', _amount, isText: false),
  CsvColumn('Wallet', _wallet),
  CsvColumn('To Wallet', _toWallet),
  CsvColumn('Note', _note),
  CsvColumn('Tag', _tag),
];

String _date(AppTransaction entry, Map<String, String> walletNames) {
  final date = entry.date;
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _time(AppTransaction entry, Map<String, String> walletNames) {
  return '${entry.date.hour.toString().padLeft(2, '0')}:'
      '${entry.date.minute.toString().padLeft(2, '0')}';
}

String _type(AppTransaction entry, Map<String, String> walletNames) =>
    entry.type.label;

String _label(AppTransaction entry, Map<String, String> walletNames) =>
    entry.label;

/// A plain number, so a spreadsheet can add the column up. The peso sign and
/// the thousands separators the app shows would both get in the way.
String _amount(AppTransaction entry, Map<String, String> walletNames) =>
    entry.amount.toStringAsFixed(2);

String _wallet(AppTransaction entry, Map<String, String> walletNames) =>
    walletNames[entry.walletId] ?? '';

String _toWallet(AppTransaction entry, Map<String, String> walletNames) =>
    walletNames[entry.toWalletId] ?? '';

String _note(AppTransaction entry, Map<String, String> walletNames) =>
    entry.note ?? '';

/// What kind of record this is. The first match wins, so a bill payment
/// brought over from the old collections still reads as an old record.
String _tag(AppTransaction entry, Map<String, String> walletNames) {
  if (entry.isLegacy) return 'Old record';
  if (entry.isBillPayment) return 'Bill payment';
  if (entry.isDebtMovement) return 'Loan';
  return 'Regular';
}

/// The exported file's contents: a header row, then [transactions] in the
/// order they are given, which is the order the app shows them in.
String buildTransactionCsv(
  List<AppTransaction> transactions, {
  Map<String, String> walletNames = const {},
}) {
  final rows = <String>[
    csvColumns.map((column) => _cell(column.header, isText: false)).join(','),
    for (final entry in transactions)
      csvColumns
          .map(
            (column) =>
                _cell(column.read(entry, walletNames), isText: column.isText),
          )
          .join(','),
  ];

  // Ends with a line break as well, the way a spreadsheet writes its own
  // files, so the last row is never mistaken for an unfinished one.
  return '${rows.join('\r\n')}\r\n';
}

/// The bytes to write to the file.
///
/// The byte order mark is what tells Excel the file is UTF-8; without it, it
/// falls back to the system encoding and turns ₱ and ñ into other characters.
Uint8List transactionCsvBytes(String csv) =>
    Uint8List.fromList(utf8.encode('﻿$csv'));

/// The file name offered in the save dialog, e.g.
/// `FinAssist-transactions-2026-09-25.csv`.
String transactionCsvFileName(DateTime exportedOn) {
  final date =
      '${exportedOn.year.toString().padLeft(4, '0')}-'
      '${exportedOn.month.toString().padLeft(2, '0')}-'
      '${exportedOn.day.toString().padLeft(2, '0')}';
  return 'FinAssist-transactions-$date.csv';
}

/// Escapes one cell.
///
/// A cell holding a comma, a quote or a line break is wrapped in quotes, with
/// its own quotes doubled, which is how a spreadsheet keeps the columns lined
/// up. A text cell that starts with `=`, `+`, `-` or `@` is prefixed with an
/// apostrophe, so a note someone typed is never run as a formula.
String _cell(String value, {required bool isText}) {
  var cell = value;

  if (isText && cell.isNotEmpty && '=+-@'.contains(cell[0])) {
    cell = "'$cell";
  }

  if (cell.contains(RegExp('["\r\n,]'))) {
    return '"${cell.replaceAll('"', '""')}"';
  }

  return cell;
}
