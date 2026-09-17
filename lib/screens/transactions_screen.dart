import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/transaction_filter.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/categories.dart';
import '../utils/date_format.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/legacy_import_card.dart';
import '../widgets/money_text.dart';
import '../widgets/transaction_edit_sheet.dart';

/// Every income, expense and transfer across all wallets, newest first.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    this.transactions,
    this.wallets,
    this.showLegacyImport = true,
    this.onOpen,
    super.key,
  });

  /// Replaces the live transactions. Used by tests.
  final Stream<List<AppTransaction>>? transactions;

  /// Replaces the live wallet list. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Offers to bring in records from before wallets. Off in tests, which
  /// can't reach Firestore.
  final bool showLegacyImport;

  /// Replaces opening the edit sheet. Used by tests.
  final void Function(AppTransaction transaction)? onOpen;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late final Stream<List<AppTransaction>> _transactions =
      widget.transactions ?? WalletService.watchTransactions();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  TransactionFilter _filter = const TransactionFilter();

  void _open(AppTransaction transaction) {
    if (widget.onOpen != null) {
      widget.onOpen!(transaction);
      return;
    }

    showTransactionEditSheet(context, transaction, wallets: _wallets);
  }

  Future<void> _editFilter(List<Wallet> wallets) async {
    final chosen = await showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FilterSheet(initial: _filter, wallets: wallets),
    );

    if (chosen != null) setState(() => _filter = chosen);
  }

  Future<void> _showBreakdown(List<AppTransaction> transactions) async {
    final category = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CategoryBreakdownSheet(transactions: transactions),
    );

    if (category == null) return;

    // Narrows the list to that category's spending.
    setState(
      () => _filter = _filter.copyWith(
        category: () => category,
        type: () => TransactionType.expense,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return StreamBuilder<List<Wallet>>(
      stream: _wallets,
      builder: (context, walletSnapshot) {
        final wallets = walletSnapshot.data ?? const <Wallet>[];

        return StreamBuilder<List<AppTransaction>>(
          stream: _transactions,
          builder: (context, snapshot) {
            final all = snapshot.data;
            final shown = all?.where(_filter.matches).toList() ?? const [];

            return Scaffold(
              backgroundColor: colors.pageBackground,
              appBar: AppBar(
                title: const Text(
                  'Transactions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                centerTitle: true,
                backgroundColor: appPrimaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    tooltip: 'Spending by category',
                    icon: const Icon(Icons.pie_chart_outline),
                    onPressed: all == null ? null : () => _showBreakdown(shown),
                  ),
                  IconButton(
                    tooltip: 'Filter',
                    icon: Badge(
                      isLabelVisible: !_filter.isEmpty,
                      label: Text('${_filter.activeCount}'),
                      child: const Icon(Icons.filter_list),
                    ),
                    onPressed: () => _editFilter(wallets),
                  ),
                ],
              ),
              body: _buildBody(context, all, shown, wallets),
            );
          },
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<AppTransaction>? all,
    List<AppTransaction> shown,
    List<Wallet> wallets,
  ) {
    if (all == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final header = <Widget>[
      if (widget.showLegacyImport) const LegacyImportCard(),
      if (!_filter.isEmpty)
        _ActiveFilters(
          filter: _filter,
          wallets: wallets,
          onClear: () => setState(() => _filter = const TransactionFilter()),
        ),
    ];

    if (all.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ...header,
          const SizedBox(height: 40),
          const EmptyStateView(
            iconAsset: 'assets/icons/icons8-transactions-96.png',
            title: 'No transactions yet',
            message:
                'Money you add, spend or move between wallets shows up here.',
          ),
        ],
      );
    }

    final totals = inAndOut(shown);
    final rows = <Widget>[];
    String? lastDay;

    for (final transaction in shown) {
      final day = transactionDateLabel(transaction.date);

      if (day != lastDay) {
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(4, lastDay == null ? 0 : 18, 4, 8),
            child: Text(
              day,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
        );
        lastDay = day;
      }

      rows
        ..add(
          _TransactionRow(
            transaction: transaction,
            wallets: wallets,
            onTap: () => _open(transaction),
          ),
        )
        ..add(const SizedBox(height: 8));
    }

    return ListView(
      // Room for the bottom bar and the docked "+" button.
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        ...header,
        _InOutStrip(moneyIn: totals.moneyIn, moneyOut: totals.moneyOut),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Nothing matches these filters.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

String _walletName(List<Wallet> wallets, String? id) {
  for (final wallet in wallets) {
    if (wallet.id == id) return wallet.name;
  }
  return 'a wallet';
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.wallets,
    required this.onTap,
  });

  final AppTransaction transaction;
  final List<Wallet> wallets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = transaction;

    final (Color color, String sign) = switch (t.type) {
      TransactionType.expense => (dangerColorOn(context), '-'),
      TransactionType.income => (confirmColorOn(context), '+'),
      TransactionType.transfer => (appPrimaryBlue, ''),
    };

    final title = t.type == TransactionType.transfer
        ? '${_walletName(wallets, t.walletId)} → '
              '${_walletName(wallets, t.toWalletId)}'
        : t.label;

    final details = [
      if (t.type != TransactionType.transfer)
        t.isLegacy ? 'Before wallets' : _walletName(wallets, t.walletId),
      if (t.isBillPayment) 'Bill payment',
      if ((t.note ?? '').isNotEmpty) t.note!,
    ].join(' · ');

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: switch (t.type) {
                  TransactionType.expense => CategoryIcon(t.label, size: 22),
                  TransactionType.income => Image.asset(
                    'assets/icons/icons8-money-transfer-96.png',
                    width: 22,
                    height: 22,
                  ),
                  TransactionType.transfer => Icon(
                    Icons.swap_horiz,
                    color: color,
                  ),
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              MoneyText(
                t.amount,
                sign: sign.isEmpty ? null : sign,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InOutStrip extends StatelessWidget {
  const _InOutStrip({required this.moneyIn, required this.moneyOut});

  final double moneyIn;
  final double moneyOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget figure(String label, double amount, Color color) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            MoneyText(
              amount,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          figure('Money in', moneyIn, confirmColorOn(context)),
          Container(
            width: 1,
            height: 34,
            color: colors.border,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          figure('Money out', moneyOut, dangerColorOn(context)),
        ],
      ),
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.filter,
    required this.wallets,
    required this.onClear,
  });

  final TransactionFilter filter;
  final List<Wallet> wallets;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (filter.type != null) filter.type!.label,
      if (filter.category != null) filter.category!,
      if (filter.walletId != null) _walletName(wallets, filter.walletId),
      if (filter.from != null || filter.to != null)
        [
          if (filter.from != null) formatShortDate(filter.from!),
          if (filter.to != null) formatShortDate(filter.to!),
        ].join(' – '),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing: ${parts.join(' · ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: context.appColors.textBody),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: cancelTextStyle(context),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.wallets});

  final TransactionFilter initial;
  final List<Wallet> wallets;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late TransactionFilter _filter = widget.initial;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _filter.from == null || _filter.to == null
          ? null
          : DateTimeRange(start: _filter.from!, end: _filter.to!),
    );

    if (range != null) {
      setState(
        () => _filter = _filter.copyWith(
          from: () => range.start,
          to: () => range.end,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Filter',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter.type == null,
                  onSelected: (_) => setState(
                    () => _filter = _filter.copyWith(type: () => null),
                  ),
                ),
                for (final type in TransactionType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _filter.type == type,
                    onSelected: (_) => setState(
                      () => _filter = _filter.copyWith(type: () => type),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _filter.walletId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Wallet'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All wallets')),
                for (final wallet in widget.wallets)
                  DropdownMenuItem(value: wallet.id, child: Text(wallet.name)),
              ],
              onChanged: (value) => setState(
                () => _filter = _filter.copyWith(walletId: () => value),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: expenseCategories.contains(_filter.category)
                  ? _filter.category
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All categories'),
                ),
                for (final category in expenseCategories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: (value) => setState(
                () => _filter = _filter.copyWith(category: () => value),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickRange,
              style: openOutlineStyle(context),
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                _filter.from == null
                    ? 'Any date'
                    : '${formatShortDate(_filter.from!)} – '
                          '${formatShortDate(_filter.to!)}',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pop(context, const TransactionFilter()),
                    style: cancelTextStyle(context),
                    child: const Text('Clear all'),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _filter),
                    style: confirmButtonStyle(),
                    child: const Text(
                      'Show results',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBreakdownSheet extends StatelessWidget {
  const _CategoryBreakdownSheet({required this.transactions});

  final List<AppTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final entries = spendingByCategory(transactions);
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spending by category',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'For what is on screen. Tap one to see just those.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No spending here yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              for (final entry in entries)
                InkWell(
                  onTap: () => Navigator.pop(context, entry.key),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CategoryIcon(entry.key, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  MoneyText(
                                    entry.value,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: total == 0 ? 0 : entry.value / total,
                                  minHeight: 6,
                                  backgroundColor: colors.track,
                                  valueColor: AlwaysStoppedAnimation(
                                    categoryColor(entry.key),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
