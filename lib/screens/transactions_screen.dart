import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/transaction_filter.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/category_options.dart';
import '../utils/categories.dart';
import 'history_screen.dart';
import '../utils/date_format.dart';
import '../widgets/back_to_home.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/legacy_import_card.dart';
import '../widgets/money_text.dart';
import '../widgets/transaction_edit_sheet.dart';
import '../widgets/transaction_row.dart';

/// Every income, expense and transfer across all wallets, newest first.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    this.transactions,
    this.wallets,
    this.showLegacyImport = true,
    this.onOpen,
    this.initialFilter,
    super.key,
  });

  /// Starts the list narrowed down, like one category from Reports.
  final TransactionFilter? initialFilter;

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

  late TransactionFilter _filter =
      widget.initialFilter ?? const TransactionFilter();

  void _open(AppTransaction transaction) {
    if (widget.onOpen != null) {
      widget.onOpen!(transaction);
      return;
    }

    // The sheet opens its own wallet feed; a live feed only hands its data
    // to the first listener, and this screen is already listening.
    showTransactionEditSheet(context, transaction, wallets: widget.wallets);
  }

  Future<void> _editFilter(
    List<Wallet> wallets,
    List<AppTransaction> transactions,
  ) async {
    final chosen = await showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FilterSheet(
        initial: _filter,
        wallets: wallets,
        historicalCategories: transactions
            .where((t) => t.type == TransactionType.expense)
            .map((t) => t.label)
            .toSet()
            .toList(),
      ),
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
                // As a tab it goes back to Home; opened from another screen,
                // like Reports, it gets the usual back arrow.
                leading: backToHomeButton(context),
                actions: [
                  IconButton(
                    tooltip: 'Pay-cycle history',
                    icon: const Icon(Icons.history),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    ),
                  ),
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
                    onPressed: () => _editFilter(wallets, all ?? const []),
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
          TransactionRow(
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
        _InOutStrip(
          moneyIn: totals.moneyIn,
          moneyOut: totals.moneyOut,
          loans: loanMovements(shown),
        ),
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

class _InOutStrip extends StatelessWidget {
  const _InOutStrip({
    required this.moneyIn,
    required this.moneyOut,
    required this.loans,
  });

  final double moneyIn;
  final double moneyOut;

  /// Shown apart, so the list adds up: a loan is your own money leaving and
  /// coming back, not spending or income.
  final ({double moneyIn, double moneyOut}) loans;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (loans.moneyIn > 0.005 || loans.moneyOut > 0.005) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                // Plain text colors: this money isn't earned or spent.
                figure('Loans in', loans.moneyIn, colors.textPrimary),
                Container(
                  width: 1,
                  height: 34,
                  color: colors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                figure('Loans out', loans.moneyOut, colors.textPrimary),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Lent, borrowed or paid back. Not counted in money in or out.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
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
      if (filter.walletId != null) walletNameFor(wallets, filter.walletId),
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
  const _FilterSheet({
    required this.initial,
    required this.wallets,
    required this.historicalCategories,
  });
  final List<String> historicalCategories;

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
              initialValue: _filter.category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All categories'),
                ),
                for (final category in {
                  ...categoryOptions(
                    context,
                    selected: _filter.category,
                    includeHidden: true,
                  ),
                  ...widget.historicalCategories,
                })
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
