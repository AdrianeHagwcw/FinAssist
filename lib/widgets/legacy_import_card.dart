import 'package:flutter/material.dart';

import '../services/legacy_migration.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';

/// Offers to copy records made before wallets existed into the ledger.
///
/// Shows nothing at all when there is nothing to copy, which is the normal
/// case, so it quietly disappears once the import has been done.
class LegacyImportCard extends StatefulWidget {
  const LegacyImportCard({this.countPending, this.runImport, super.key});

  /// Counts the records waiting to be copied. Tests pass a fake.
  final Future<int> Function()? countPending;

  /// Does the copying and returns how many were copied. Tests pass a fake.
  final Future<int> Function()? runImport;

  @override
  State<LegacyImportCard> createState() => _LegacyImportCardState();
}

class _LegacyImportCardState extends State<LegacyImportCard> {
  late Future<int> _pending = _count();

  bool _isImporting = false;

  Future<int> _count() async {
    try {
      return await (widget.countPending ?? LegacyMigration.countPending)();
    } catch (_) {
      // Offline or blocked: say there is nothing rather than show an error
      // for something the user did not ask for.
      return 0;
    }
  }

  Future<void> _import(int pending) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add older records?'),
        content: Text(
          'Your $pending older ${pending == 1 ? 'record' : 'records'} will be '
          'copied into your history and marked as being from before you had '
          'wallets.\n\n'
          'No wallet balance will change, because the money in those records '
          'is already part of the balances you entered. Nothing is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: confirmTextStyle(context),
            child: const Text('Add them'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isImporting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final copied = await (widget.runImport ?? LegacyMigration.run)();

      if (!mounted) return;

      setState(() {
        _isImporting = false;
        _pending = Future.value(0);
      });

      messenger.showSnackBar(
        SnackBar(content: Text('Added $copied older records to your history.')),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() => _isImporting = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not add them right now. Check your connection and try '
            'again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _pending,
      builder: (context, snapshot) {
        final pending = snapshot.data ?? 0;

        if (pending == 0) return const SizedBox.shrink();

        final colors = context.appColors;

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primaryTint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/icons/icons8-transactions-96.png',
                    width: 22,
                    height: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You have $pending older '
                      '${pending == 1 ? 'record' : 'records'}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'These were saved before you had wallets. Add them to your '
                'history to keep everything in one place. Balances stay as '
                'they are.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: colors.textBody,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _isImporting ? null : () => _import(pending),
                  style: confirmButtonStyle(height: 44),
                  child: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Add to my history',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
