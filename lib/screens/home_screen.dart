import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/bill.dart';
import '../models/dashboard_tip.dart';
import '../models/goal.dart';
import '../models/report.dart';
import '../models/transaction_filter.dart';
import '../models/voice_command.dart';
import '../models/wallet.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../utils/money_format.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/money_text.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/safe_to_spend_card.dart';
import '../widgets/spending_chart.dart';
import '../widgets/transaction_row.dart';
import '../widgets/due_soon_notice.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/matured_savings_notice.dart';
import '../widgets/dashboard_tip.dart';
import '../widgets/transfer_sheet.dart';
import 'add_expense_screen.dart';
import 'history_screen.dart';
import 'bill_calendar_screen.dart';
import 'bill_detail_screen.dart';
import 'chatbot_screen.dart';
import 'categories_screen.dart';
import 'financial_preferences_screen.dart';
import 'help_screen.dart';
import 'income_waterfall_screen.dart';
import 'leftover_review_screen.dart';
import 'ocr_screen.dart';
import 'profile_screen.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';
import 'set_aside_screen.dart';
import 'voice_recognition_screen.dart';
import 'wallets_screen.dart';

/// The landing screen: what is safe to spend today, what the wallets hold,
/// shortcuts, and a glance at this month's spending.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.onOpenTransactions,
    this.onOpenWallets,
    this.onOpenBills,
    this.onOpenSavings,
    this.onOpenDebts,
    this.onVoiceNavigate,
    this.userName,
    this.wallets,
    this.goals,
    this.transactions,
    this.safeToSpend,
    this.today,
    super.key,
  });

  /// Switches the app to the Transactions tab.
  final VoidCallback? onOpenTransactions;

  /// Switches the app to the Wallet tab.
  final VoidCallback? onOpenWallets;

  /// Switch the app to the Goals tab, on savings or on debts.
  /// Opens the Bill Planner. The shell switches to its tab; on its own the
  /// screen is pushed instead.
  final VoidCallback? onOpenBills;
  final VoidCallback? onOpenSavings;
  final VoidCallback? onOpenDebts;

  /// Routes commands recognized by Voice Entry to the app's sections.
  final ValueChanged<VoiceDestination>? onVoiceNavigate;

  /// Replaces the signed-in user's name. Used by tests.
  final String? userName;

  /// Replaces the live wallets. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live savings goals. Used by tests.
  final Stream<List<Goal>>? goals;

  /// Replaces the live transactions. Used by tests.
  final Stream<List<AppTransaction>>? transactions;

  /// Replaces the Safe to Spend card. Used by tests.
  final Widget? safeToSpend;

  /// Replaces the clock. Used by tests.
  final DateTime? today;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Held here so a rebuild doesn't start a second listener.
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();
  late final Stream<List<Goal>> _goals =
      widget.goals ??
      (FirebaseAuth.instance.currentUser == null
          ? Stream.value(const <Goal>[])
          : GoalService.watchGoals());
  late final Stream<List<AppTransaction>> _transactions =
      widget.transactions ?? WalletService.watchTransactions();

  // Changing this rebuilds the Safe to Spend card after income is added.
  int _refreshKey = 0;
  bool _showAllQuickActions = false;

  /// The bills the Safe to Spend card loaded, reused by the tip so the screen
  /// doesn't read them twice.
  List<BillInstance> _bills = const [];

  String get _name {
    if (widget.userName != null) return widget.userName!;
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    return name == null || name.isEmpty ? 'there' : name;
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }

  void _openVoiceDestination(VoiceDestination destination) {
    switch (destination) {
      case VoiceDestination.home:
        return;
      case VoiceDestination.transactions:
        (widget.onOpenTransactions ?? () => _push(const HistoryScreen()))();
        return;
      case VoiceDestination.bills:
        (widget.onOpenBills ?? () => _push(const BillCalendarScreen()))();
        return;
      case VoiceDestination.wallet:
        (widget.onOpenWallets ?? () => _push(const WalletsScreen()))();
        return;
      case VoiceDestination.savings:
        (widget.onOpenSavings ?? () => _openSetAside(SetAsidePart.savings))();
        return;
      case VoiceDestination.debts:
        (widget.onOpenDebts ??
            () => _push(const BillCalendarScreen(initialShowDebts: true)))();
        return;
      case VoiceDestination.goals:
        (widget.onOpenSavings ?? () => _openSetAside(SetAsidePart.savings))();
        return;
      case VoiceDestination.reports:
        _push(const ReportsScreen());
        return;
      case VoiceDestination.settings:
        _push(const ProfileScreen());
        return;
      case VoiceDestination.scanReceipt:
        _push(OcrScreen(wallets: widget.wallets));
        return;
      case VoiceDestination.assistant:
        _push(const ChatbotScreen());
        return;
      case VoiceDestination.expenseCategories:
        _push(const CategoriesScreen());
        return;
      case VoiceDestination.financialPreferences:
        _push(const FinancialPreferencesScreen());
        return;
      case VoiceDestination.payCycleHistory:
        _push(const HistoryScreen());
        return;
      case VoiceDestination.reminders:
        _push(const RemindersScreen());
        return;
      case VoiceDestination.help:
        _push(const HelpScreen());
        return;
    }
  }

  void _startVoiceEntry() {
    _push(
      VoiceRecognitionScreen(
        autoStart: true,
        onNavigate: widget.onVoiceNavigate ?? _openVoiceDestination,
        onIncomeSaved: () => setState(() => _refreshKey++),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.card,
        automaticallyImplyLeading: false,
        title: const AppLogo(width: 82, height: 52),
        actions: [
          IconButton(
            tooltip: 'AI Assistant',
            icon: Image.asset(
              'assets/icons/assistant-robot-192.png',
              width: 26,
              height: 26,
            ),
            onPressed: () => _push(const ChatbotScreen()),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: Image.asset(
              'assets/icons/icons8-settings-96.png',
              width: 24,
              height: 24,
            ),
            onPressed: () => _push(const ProfileScreen()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: _wallets,
        builder: (context, walletSnapshot) {
          return StreamBuilder<List<AppTransaction>>(
            stream: _transactions,
            builder: (context, snapshot) => StreamBuilder<List<Goal>>(
              stream: _goals,
              builder: (context, goalSnapshot) => _buildBody(
                context,
                wallets: walletSnapshot.data,
                transactions: snapshot.data,
                goals: goalSnapshot.data,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required List<Wallet>? wallets,
    required List<AppTransaction>? transactions,
    required List<Goal>? goals,
  }) {
    final colors = context.appColors;
    final now = widget.today ?? DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Text(
          'Hello, $_name!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Here is your financial overview.',
          style: TextStyle(color: colors.textBody, fontSize: 14),
        ),
        const SizedBox(height: 20),

        // What can be spent today comes first: it's the number checked every
        // day. What the wallets hold follows.
        widget.safeToSpend ??
            SafeToSpendCard(key: ValueKey(_refreshKey), belowCard: _belowCard),
        const SizedBox(height: 16),
        _BalanceCard(wallets: wallets, onTap: widget.onOpenWallets),
        const SizedBox(height: 12),
        // Bills and savings money sits in its own wallet, so each has its own
        // balance here rather than being counted into the one above.
        _SetAsideBalanceCard(
          title: 'Bills',
          note: 'View your bills total balance',
          iconAsset: 'assets/icons/icons8-receipt-96.png',
          onTap: () => _openSetAside(SetAsidePart.bills),
        ),
        const SizedBox(height: 12),
        _SetAsideBalanceCard(
          title: 'Savings',
          note: 'View your savings total balance and goals',
          iconAsset: 'assets/icons/icons8-money-box-96.png',
          onTap: () => _openSetAside(SetAsidePart.savings),
        ),

        const SizedBox(height: 25),
        _SectionTitle(
          'Quick Actions',
          action: _showAllQuickActions ? 'Show less' : 'View all',
          onAction: () =>
              setState(() => _showAllQuickActions = !_showAllQuickActions),
        ),
        _quickActions(),
        const SizedBox(height: 20),
        _tip(wallets: wallets, transactions: transactions, now: now),

        const SizedBox(height: 25),
        _SectionTitle(
          'Spending This Month',
          action: 'See Reports',
          onAction: () => _push(const ReportsScreen()),
        ),
        _MonthSpendingCard(
          transactions: transactions,
          now: now,
          onOpenReports: () => _push(const ReportsScreen()),
        ),

        const SizedBox(height: 25),
        _SectionTitle(
          'Recent Transactions',
          action: widget.onOpenTransactions == null ? null : 'View All',
          onAction: widget.onOpenTransactions,
        ),
        _RecentTransactions(transactions: transactions, wallets: wallets),
      ],
    );
  }

  /// The tip needs the bills the Safe to Spend card already loaded, so it is
  /// built from the same inputs further down the screen.
  Widget _tip({
    required List<Wallet>? wallets,
    required List<AppTransaction>? transactions,
    required DateTime now,
  }) {
    return DashboardTipCard(
      tip: dashboardTipFor(
        wallets: wallets,
        transactions: transactions,
        bills: _bills,
        now: now,
      ),
      onOpenHistory: () => _push(const HistoryScreen()),
    );
  }

  /// Opens the balance the user tapped: the bills wallet or the savings one.
  void _openSetAside(SetAsidePart part) =>
      _push(SetAsideScreen(initialPart: part));

  Widget _quickActions() {
    Widget tile(String asset, String title, VoidCallback onTap) {
      return Expanded(
        child: QuickActionTile(
          icon: Image.asset(asset, width: 24, height: 24),
          title: title,
          onTap: onTap,
        ),
      );
    }

    final actions = <({String asset, String title, VoidCallback onTap})>[
      (
        asset: 'assets/icons/icons8-expenses-64.png',
        title: 'Expense',
        onTap: () => _push(AddExpenseScreen(wallets: widget.wallets)),
      ),
      (
        asset: 'assets/icons/icons8-money-transfer-96.png',
        title: 'Income',
        onTap: () async {
          final saved = await showIncomeWaterfall(context);
          if (saved && mounted) setState(() => _refreshKey++);
        },
      ),
      (
        asset: 'assets/icons/icons8-transactions-96.png',
        title: 'Transfer',
        onTap: () async {
          final saved = await showTransferSheet(
            context,
            wallets: widget.wallets,
          );
          if (saved && mounted) setState(() => _refreshKey++);
        },
      ),
      (
        asset: 'assets/icons/icons8-goal-96.png',
        title: 'Save to Goal',
        onTap: () async {
          final saved = await showSaveToGoal(context);
          if (saved && mounted) setState(() => _refreshKey++);
        },
      ),
      (
        asset: 'assets/icons/icons8-camera-96.png',
        title: 'Scan Receipt',
        onTap: () => _push(const OcrScreen()),
      ),
      (
        asset: 'assets/icons/icons8-microphone-96.png',
        title: 'Voice Entry',
        onTap: _startVoiceEntry,
      ),
      (
        asset: 'assets/icons/icons8-calendar-96.png',
        title: 'Bill Planner',
        onTap: widget.onOpenBills ?? () => _push(const BillCalendarScreen()),
      ),
      (
        asset: 'assets/icons/icons8-money-box-96.png',
        title: 'Savings',
        onTap:
            widget.onOpenSavings ?? () => _openSetAside(SetAsidePart.savings),
      ),
      (
        asset: 'assets/icons/lend-96.png',
        title: 'Installments',
        onTap:
            widget.onOpenDebts ??
            () => _push(const BillCalendarScreen(initialShowDebts: true)),
      ),
      (
        asset: 'assets/icons/icons8-combo-chart-100.png',
        title: 'Reports',
        onTap: () => _push(const ReportsScreen()),
      ),
    ];
    final visibleActions = _showAllQuickActions
        ? actions
        : actions.take(3).toList();

    // Keep the Quick Add recording actions on Home too. Scan Receipt and
    // Voice Entry are already here, so only the four missing actions are added.
    return Column(
      children: List.generate((visibleActions.length + 2) ~/ 3, (rowIndex) {
        final rowActions = visibleActions.skip(rowIndex * 3).take(3).toList();
        return Padding(
          padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 12),
          child: Row(
            children: [
              if (rowActions.length < 3) const Spacer(),
              for (var index = 0; index < rowActions.length; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                tile(
                  rowActions[index].asset,
                  rowActions[index].title,
                  rowActions[index].onTap,
                ),
              ],
              if (rowActions.length < 3) const Spacer(),
            ],
          ),
        );
      }),
    );
  }

  /// Offers the leftover review once a pay period is on its last day and
  /// what was left of it hasn't been decided.
  /// Bills due soon, then the leftover decision when one is waiting.
  Widget _belowCard(BuildContext context, SafeToSpendInputs inputs) {
    // Kept for the tip above, which is built before this runs.
    if (!identical(_bills, inputs.bills)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _bills = inputs.bills);
      });
    }

    return Column(
      children: [
        DueSoonNotice(
          bills: inputs.bills,
          now: inputs.now ?? DateTime.now(),
          onOpen: (bill) => _push(BillDetailScreen(instance: bill)),
        ),
        // A time deposit or government savings that has come due. Nothing
        // moves until the user says what they did with it.
        MaturedSavingsNotice(
          wallets: inputs.wallets,
          today: inputs.now,
          onAnswered: () => setState(() => _refreshKey++),
        ),
        _leftoverNotice(context, inputs),
      ],
    );
  }

  Widget _leftoverNotice(BuildContext context, SafeToSpendInputs inputs) {
    final cycle = cycleAwaitingReview(
      inputs.cycles,
      inputs.frequency,
      now: DateTime.now(),
    );
    if (cycle == null) return const SizedBox.shrink();

    final period = periodOf(cycle, inputs.frequency);
    final leftover = leftoverOf(cycle, inputs.transactions, period);
    if (leftover <= 0) return const SizedBox.shrink();

    return LeftoverNotice(
      cycle: cycle,
      leftover: leftover,
      onReview: () => _push(
        LeftoverReviewScreen(
          cycle: cycle,
          leftover: leftover,
          periodEnd: period.end,
        ),
      ),
    );
  }
}

/// A balance the user has already promised: what is kept for bills, and what
/// is kept as savings. Tapping one opens where that money is going.
class _SetAsideBalanceCard extends StatelessWidget {
  const _SetAsideBalanceCard({
    required this.title,
    required this.note,
    required this.iconAsset,
    required this.onTap,
  });

  final String title;
  final String note;
  final String iconAsset;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(9),
                child: Image.asset(iconAsset),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: colors.textBody, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textBody),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.appColors.textBody,
              ),
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: context.appColors.primaryText,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// A plain card for the home sections.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// What every wallet holds together. Tapping it opens the Wallet tab.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallets, this.onTap});

  final List<Wallet>? wallets;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final list = wallets;
    // Bills and savings wallets hold money that is already promised, so they
    // are named separately rather than counted into the balance.
    final spending = list?.where((wallet) => !wallet.isSetAside).toList();
    final count = spending?.length ?? 0;
    final setAside = list == null ? 0.0 : setAsideWalletBalance(list);
    final caption = list == null
        ? 'Loading your wallets…'
        : count == 0
        ? 'Add a wallet to start tracking your money'
        : setAside > 0
        ? 'Across $count wallet${count == 1 ? '' : 's'} · '
              '${formatPeso(setAside)} set aside'
        : 'Across $count wallet${count == 1 ? '' : 's'}';

    return Material(
      color: appPrimaryBlue,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Image.asset(
                'assets/icons/icons8-wallet-96.png',
                width: 30,
                height: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Wallet Total Balance',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    MoneyText(
                      list == null ? 0 : totalWalletBalance(list),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      caption,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

/// This month's spending: the total, how it splits, and the biggest
/// categories.
class _MonthSpendingCard extends StatelessWidget {
  const _MonthSpendingCard({
    required this.transactions,
    required this.now,
    required this.onOpenReports,
  });

  final List<AppTransaction>? transactions;
  final DateTime now;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    final list = transactions;
    if (list == null) {
      return const _Card(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final spending = spendingByCategory(
      transactionsIn(list, ReportPeriod.monthOf(now)),
    );

    final total = spending.fold<double>(0, (sum, e) => sum + e.value);

    if (spending.isEmpty) {
      return _Card(
        child: Row(
          children: [
            Image.asset(
              'assets/icons/icons8-pie-chart-96.png',
              width: 44,
              height: 44,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'No spending yet this month. Expenses and bills you pay '
                'show up here.',
                style: TextStyle(
                  color: context.appColors.textBody,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenReports,
        borderRadius: BorderRadius.circular(16),
        child: _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoneyText(
                total,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: context.appColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'spent so far this month',
                style: TextStyle(
                  fontSize: 13,
                  color: context.appColors.textBody,
                ),
              ),
              const SizedBox(height: 14),
              SpendingBar(spending: spending, limit: 3),
              const SizedBox(height: 6),
              SpendingLegend(spending: spending, limit: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions({
    required this.transactions,
    required this.wallets,
  });

  final List<AppTransaction>? transactions;
  final List<Wallet>? wallets;

  @override
  Widget build(BuildContext context) {
    final list = transactions;
    if (list == null) {
      return const _Card(
        child: SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (list.isEmpty) {
      return _Card(
        child: Text(
          'No transactions yet. Tap + to log an expense or add income.',
          style: TextStyle(color: context.appColors.textBody, height: 1.4),
        ),
      );
    }

    return Column(
      children: [
        for (final transaction in list.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TransactionRow(
              transaction: transaction,
              wallets: wallets ?? const [],
            ),
          ),
      ],
    );
  }
}
