import 'package:flutter/material.dart';

import '../services/transaction_export.dart';
import '../theme/app_colors.dart';

/// The Settings row that writes the user's records out as a spreadsheet.
///
/// It lives with the rest of "Your money" rather than on a screen of its own,
/// and says in full what the file is, so nobody has to press it to find out.
class ExportTransactionsTile extends StatefulWidget {
  const ExportTransactionsTile({this.onExport, super.key});

  /// Replaces saving the file. Used by tests.
  final Future<ExportResult> Function()? onExport;

  @override
  State<ExportTransactionsTile> createState() => _ExportTransactionsTileState();
}

class _ExportTransactionsTileState extends State<ExportTransactionsTile> {
  /// True while the save dialog is open, so one tap opens one dialog.
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final result =
          await (widget.onExport ?? TransactionExport.saveTransactions)();
      if (!mounted) return;

      switch (result.outcome) {
        case ExportOutcome.saved:
          _showMessage('Saved ${result.fileName}');
        case ExportOutcome.nothingToExport:
          _showMessage('No transactions to export yet.');
        case ExportOutcome.cancelled:
          break;
      }
    } catch (_) {
      if (mounted) {
        _showMessage('The file could not be saved. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: context.appColors.primaryTint,
          borderRadius: BorderRadius.circular(10),
        ),
        // The same drawn icon the rows around it use, rather than a flat
        // Material one.
        padding: const EdgeInsets.all(9),
        child: Image.asset('assets/icons/icons8-transactions-96.png'),
      ),
      title: const Text(
        'Export transactions',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Save all your records as a CSV file you can open in Excel or '
        'Google Sheets',
        style: TextStyle(fontSize: 12.5),
      ),
      trailing: _exporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: _exporting ? null : _export,
    );
  }
}
