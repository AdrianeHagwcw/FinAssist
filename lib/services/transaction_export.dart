import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../utils/transaction_csv.dart';
import 'wallet_service.dart';

/// How an export ended.
enum ExportOutcome {
  /// The file was written where the user chose.
  saved,

  /// The user backed out of the save dialog.
  cancelled,

  /// There is nothing recorded yet, so no file was offered.
  nothingToExport,
}

/// The result of one export, including the name the file was offered under.
class ExportResult {
  const ExportResult(this.outcome, {this.fileName});

  final ExportOutcome outcome;
  final String? fileName;
}

/// Saves the user's transactions to a file they choose.
///
/// Android's own save dialog picks the folder, so the app never needs storage
/// permission and never writes anywhere the user did not point at.
class TransactionExport {
  /// Reads the records, builds the file, and asks where to save it.
  ///
  /// [now] only sets the date in the file name; tests pass a fixed day.
  static Future<ExportResult> saveTransactions({DateTime? now}) async {
    final transactions = await WalletService.loadTransactions();

    if (transactions.isEmpty) {
      return const ExportResult(ExportOutcome.nothingToExport);
    }

    // Archived wallets are included, so an entry made in a wallet the user has
    // since put away still shows the wallet it belongs to.
    final wallets = await WalletService.loadWallets();
    final walletNames = {
      for (final wallet in wallets) wallet.id: wallet.name,
    };

    final csv = buildTransactionCsv(transactions, walletNames: walletNames);
    final fileName = transactionCsvFileName(now ?? DateTime.now());

    final savedPath = await FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: transactionCsvBytes(csv),
        fileName: fileName,
        mimeTypesFilter: const ['text/csv'],
      ),
    );

    if (savedPath == null) {
      return const ExportResult(ExportOutcome.cancelled);
    }

    return ExportResult(ExportOutcome.saved, fileName: fileName);
  }
}
