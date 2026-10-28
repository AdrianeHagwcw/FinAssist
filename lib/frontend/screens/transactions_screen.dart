import 'package:flutter/material.dart';

import '../../backend/models/app_transaction.dart';
import '../../backend/models/transaction_filter.dart';
import '../../backend/models/transfer_direction.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/category_options.dart';
import 'history_screen.dart';
import '../../backend/utils/date_format.dart';
import '../widgets/back_to_home.dart';
import '../widgets/choice_grid.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/legacy_import_card.dart';
import '../widgets/money_text.dart';
import '../widgets/transaction_row.dart';

/// Every income, expense and transfer across all wallets, newest first.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    this.transactions,
    this.wallets,
    this.showLegacyImport = true,
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

  Future<void> _editFilter(
    List<Wallet> wallets,
    List<AppTransaction> transactions,
  ) async {
    final chosen = await showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FilterSheet(
        initial: _filter,
        wallets: wallets,
        transactions: transactions,
        historicalCategories: transactions
            .where((t) => t.type == TransactionType.expense)
            .map((t) => t.label)
            .toSet()
            .toList(),
      ),
    );

    if (chosen != null) setState(() => _filter = chosen);
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
            final shown =
                all
                    ?.where((t) => _filter.matches(t, wallets: wallets))
                    .toList() ??
                const [];

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
                    tooltip: 'Cash Inflows',
                    icon: Image.asset(
                      'assets/icons/icons8-idea-96.png',
                      width: 24,
                      height: 24,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    ),
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

    // The rows grouped by the day they fall under. Only the grouping is
    // worked out here, never a widget, so it stays cheap however long the
    // history gets and the rows are built as they are scrolled to.
    final days = <_Day>[];
    String? lastLabel;

    // Read once, so every row is headed against the same moment. Reading it
    // per row would also let a list built across midnight head one day twice.
    final now = DateTime.now();

    for (final transaction in shown) {
      final label = transactionDateLabel(transaction.date, now: now);

      if (label != lastLabel) {
        days.add(_Day(label));
        lastLabel = label;
      }

      days.last.transactions.add(transaction);
    }

    // Everything above the list. Stretched, because a list's children fill
    // the width and a column's do not, and this used to be a list child.
    final top = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...header,
        _InOutStrip(
          moneyIn: totals.moneyIn,
          moneyOut: totals.moneyOut,
          moved: shown
              .where((t) => t.type == TransactionType.transfer)
              .fold<double>(0, (sum, t) => sum + t.amount),
          showing:
              _filter.type ??
              (_filter.direction != null ? TransactionType.transfer : null),
          loans: loanMovements(shown),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('transaction-search-filters'),
            onPressed: () => _editFilter(wallets, all),
            style: openButtonStyle(),
            icon: Badge(
              isLabelVisible: !_filter.isEmpty,
              label: Text('${_filter.activeCount}'),
              child: const Icon(Icons.search),
            ),
            label: const Text(
              'Search transactions & filters',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Nothing matches these filters.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textMuted),
            ),
          ),
      ],
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: top),
        ),
        for (final day in days)
          // Keeps a day's heading with its rows, so the heading can hold the
          // top of the screen for exactly as long as that day is being read.
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _DayHeader(
                  label: day.label,
                  background: context.appColors.pageBackground,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: day.transactions.length,
                  itemBuilder: (context, index) {
                    final transaction = day.transactions[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TransactionRow(
                        transaction: transaction,
                        wallets: wallets,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        // Room for the bottom bar and the docked "+" button.
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

/// One day of the transaction list: what to call it, and what falls under
/// it. Plain data, so the list is grouped without building a single row.
class _Day {
  _Day(this.label);

  final String label;
  final List<AppTransaction> transactions = [];
}

/// A day's heading, which holds the top of the screen while that day's rows
/// pass under it. Without it, scrolling into the middle of a busy day leaves
/// the times on screen with nothing saying which day they belong to.
class _DayHeader extends SliverPersistentHeaderDelegate {
  const _DayHeader({required this.label, required this.background});

  final String label;

  /// Opaque, so rows passing underneath do not show through the heading.
  final Color background;

  /// The gutter the rows use, plus the inset the heading always had.
  static const _sideInset = 24.0;
  static const _height = 38.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: background,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.fromLTRB(_sideInset, 0, _sideInset, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.appColors.textMuted,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeader oldDelegate) =>
      oldDelegate.label != label || oldDelegate.background != background;
}

class _InOutStrip extends StatelessWidget {
  const _InOutStrip({
    required this.moneyIn,
    required this.moneyOut,
    required this.moved,
    required this.loans,
    this.showing,
  });

  final double moneyIn;
  final double moneyOut;

  /// Moved between the user's own wallets: neither in nor out.
  final double moved;

  /// The one kind the list is narrowed to. Only its figure is shown, so the
  /// other never reads as a misleading ₱0.
  final TransactionType? showing;

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
              style: TextStyle(
                fontSize: 11,
                color: context.appColors.textMuted,
              ),
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
            children: switch (showing) {
              TransactionType.income => [
                figure('Inflow', moneyIn, confirmColorOn(context)),
              ],
              TransactionType.expense => [
                figure('Outflow', moneyOut, dangerColorOn(context)),
              ],
              TransactionType.transfer => [
                figure('Moved between your wallets', moved, colors.primaryText),
              ],
              null => [
                figure('Inflow', moneyIn, confirmColorOn(context)),
                Container(
                  width: 1,
                  height: 34,
                  color: colors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                figure('Outflow', moneyOut, dangerColorOn(context)),
              ],
            },
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
            Text(
              'Lent, borrowed or paid back. Not counted as inflow or outflow.',
              style: TextStyle(
                fontSize: 11,
                color: context.appColors.textMuted,
              ),
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
      if (filter.direction != null)
        filter.direction!.label
      else if (filter.type != null)
        filter.type!.flowLabel,
      if (filter.category != null) filter.category!,
      if (filter.query != null && filter.query!.trim().isNotEmpty)
        '"${filter.query!.trim()}"',
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
    required this.transactions,
    required this.historicalCategories,
  });
  final List<String> historicalCategories;

  final TransactionFilter initial;
  final List<Wallet> wallets;

  /// Everything there is to search, so the button can say how many match
  /// before the sheet is closed.
  final List<AppTransaction> transactions;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

/// The dates a search can cover: a quick choice, or dates picked.
enum _DateChoice {
  any('Any time'),
  thisMonth('This month'),
  lastMonth('Last month'),
  custom('Pick dates');

  const _DateChoice(this.label);

  final String label;
}

class _FilterSheetState extends State<_FilterSheet> {
  late TransactionFilter _filter = widget.initial;
  late final TextEditingController _searchController = TextEditingController(
    text: widget.initial.query ?? '',
  );
  final DateTime _today = DateTime.now();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ({DateTime from, DateTime to}) get _thisMonth => (
    from: DateTime(_today.year, _today.month),
    to: DateTime(_today.year, _today.month + 1, 0),
  );

  ({DateTime from, DateTime to}) get _lastMonth => (
    from: DateTime(_today.year, _today.month - 1),
    to: DateTime(_today.year, _today.month, 0),
  );

  static bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  /// Which choice the dates in the filter are.
  _DateChoice get _dateChoice {
    final from = _filter.from;
    if (from == null && _filter.to == null) return _DateChoice.any;
    for (final (choice, range) in [
      (_DateChoice.thisMonth, _thisMonth),
      (_DateChoice.lastMonth, _lastMonth),
    ]) {
      if (_sameDay(from, range.from) && _sameDay(_filter.to, range.to)) {
        return choice;
      }
    }
    return _DateChoice.custom;
  }

  void _setDates(DateTime? from, DateTime? to) => setState(
    () => _filter = _filter.copyWith(from: () => from, to: () => to),
  );

  /// What the Type tiles offer. The stored type names keep their keys; the
  /// two directions sit beside them because a transfer row reads as a
  /// withdrawal or a deposit.
  static const _typeChoices = <String?>[
    null,
    'income',
    'expense',
    'transfer',
    'withdrawal',
    'deposit',
  ];

  static const _typeChoiceLabels = {
    'income': 'Inflow',
    'expense': 'Outflow',
    'transfer': 'Transfer',
    'withdrawal': 'Withdrawal',
    'deposit': 'Deposit',
  };

  static String _typeChoiceLabel(String? choice) =>
      choice == null ? 'All' : _typeChoiceLabels[choice]!;

  /// The tile to highlight: a direction when one is chosen, otherwise the
  /// stored type. Null is All.
  String? get _typeChoice => _filter.direction?.name ?? _filter.type?.name;

  void _pickType(String? choice) {
    setState(() {
      if (choice == null) {
        _filter = _filter.copyWith(type: () => null, direction: () => null);
        return;
      }

      final direction = switch (choice) {
        'withdrawal' => TransferDirection.withdrawal,
        'deposit' => TransferDirection.deposit,
        _ => null,
      };
      if (direction != null) {
        _filter = _filter.copyWith(
          type: () => TransactionType.transfer,
          direction: () => direction,
        );
        return;
      }

      final type = TransactionType.values.firstWhere(
        (type) => type.name == choice,
      );
      _filter = _filter.copyWith(type: () => type, direction: () => null);
    });
  }

  Future<void> _pickDate(_DateChoice choice) async {
    switch (choice) {
      case _DateChoice.any:
        _setDates(null, null);
      case _DateChoice.thisMonth:
        _setDates(_thisMonth.from, _thisMonth.to);
      case _DateChoice.lastMonth:
        _setDates(_lastMonth.from, _lastMonth.to);
      case _DateChoice.custom:
        await _pickRange();
    }
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(_today.year - 5),
      lastDate: _today,
      initialDateRange: _filter.from == null || _filter.to == null
          ? null
          : DateTimeRange(
              start: _filter.from!,
              end: _filter.to!.isAfter(_today) ? _today : _filter.to!,
            ),
    );
    if (range != null) _setDates(range.start, range.end);
  }

  /// Back to everything, here in the sheet, so the user sees it before
  /// choosing again.
  void _clear() {
    _searchController.clear();
    setState(() => _filter = const TransactionFilter());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final matching = widget.transactions
        .where((t) => _filter.matches(t, wallets: widget.wallets))
        .length;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.textBody,
        ),
      ),
    );

    return Padding(
      // Keeps the search above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search & filters',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('transaction-search-input'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration:
                    dialogFieldDecoration(
                      context,
                      'Search',
                      hint: 'Category or type',
                    ).copyWith(
                      prefixIcon: const Icon(Icons.search),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(
                                  () => _filter = _filter.copyWith(
                                    query: () => null,
                                  ),
                                );
                              },
                            ),
                    ),
                onChanged: (value) => setState(
                  () => _filter = _filter.copyWith(query: () => value),
                ),
              ),
              const SizedBox(height: 20),
              section('Type'),
              ChoiceGrid<String?>(
                options: _typeChoices,
                selected: _typeChoice,
                label: _typeChoiceLabel,
                keyOf: (choice) => 'filter-type-${choice ?? 'all'}',
                columns: 3,
                onPick: _pickType,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _filter.walletId,
                isExpanded: true,
                decoration: dialogFieldDecoration(context, 'Wallet'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All wallets'),
                  ),
                  for (final wallet in widget.wallets)
                    DropdownMenuItem(
                      value: wallet.id,
                      child: Text(wallet.name),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _filter = _filter.copyWith(walletId: () => value),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _filter.category,
                isExpanded: true,
                decoration: dialogFieldDecoration(context, 'Category'),
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
              const SizedBox(height: 20),
              section('Date'),
              ChoiceGrid<_DateChoice>(
                options: _DateChoice.values,
                selected: _dateChoice,
                label: (choice) => choice.label,
                keyOf: (choice) => 'filter-date-${choice.name}',
                onPick: _pickDate,
              ),
              if (_dateChoice == _DateChoice.custom)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatShortDate(_filter.from!)} – '
                        '${formatShortDate(_filter.to!)}',
                        key: const Key('filter-date-range'),
                        style: TextStyle(fontSize: 13, color: colors.textBody),
                      ),
                    ),
                    TextButton(
                      onPressed: _pickRange,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primaryText,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    // Solid red, like Log Out. Nothing to clear: nothing to
                    // press, so it shows paler until a filter is set.
                    child: ElevatedButton(
                      key: const Key('filter-clear'),
                      onPressed: _filter.isEmpty ? null : _clear,
                      style: dangerButtonStyle(height: 52),
                      child: const Text(
                        'Clear all',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      key: const Key('filter-apply'),
                      onPressed: () => Navigator.pop(context, _filter),
                      style: confirmButtonStyle(),
                      // How many match, before the sheet is closed.
                      child: Text(
                        matching == 0
                            ? 'No matches'
                            : 'Show $matching '
                                  '${matching == 1 ? 'result' : 'results'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
