import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/models/cycle_history.dart';
import '../../backend/models/app_transaction.dart';
import '../../backend/models/bill.dart';
import '../../backend/models/dashboard_tip.dart';
import '../../backend/models/goal.dart';
import '../../backend/models/report.dart';
import '../../backend/models/safe_to_spend.dart';
import '../../backend/models/transaction_filter.dart';
import '../../backend/models/voice_command.dart';
import '../../backend/models/wallet.dart';
import '../providers/app_settings_provider.dart';
import '../../backend/services/goal_service.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import '../../backend/utils/ph_time.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_logo.dart';
import '../widgets/money_text.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/safe_to_spend_bar.dart';
import '../widgets/safe_to_spend_card.dart';
import '../widgets/spending_chart.dart';
import '../widgets/transaction_row.dart';
import '../widgets/due_soon_notice.dart';
import '../widgets/matured_savings_notice.dart';
import '../widgets/dashboard_tip.dart';
import '../widgets/transfer_sheet.dart';
import 'add_expense_screen.dart';
import 'history_screen.dart';
import 'bill_calendar_screen.dart';
import 'debts_screen.dart';
import 'bill_detail_screen.dart';
import 'chatbot_screen.dart';
import 'categories_screen.dart';
import 'goals_screen.dart';
import 'help_screen.dart';
import 'income_waterfall_screen.dart';
import 'leftover_review_screen.dart';
import 'ocr_screen.dart';
import 'profile_screen.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';
import 'set_aside_screen.dart';
import 'voice_recognition_screen.dart';
import 'wallet_detail_screen.dart';
import 'transactions_screen.dart';
import 'wallets_screen.dart';

/// The landing screen: what is safe to spend today, what the wallets hold,
/// shortcuts, and a glance at this month's spending.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.onOpenTransactions,
    this.onOpenWallets,
    this.onOpenBills,
    this.onOpenSavings,
    this.onOpenGoals,
    this.onOpenDebts,
    this.onOpenReports,
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

  /// Open the Bill Planner and the savings balance. On its own, without
  /// the app shell, the screens are pushed instead.
  final VoidCallback? onOpenBills;
  final VoidCallback? onOpenSavings;

  /// Opens Goals, where goals are added and put in order.
  final VoidCallback? onOpenGoals;

  /// Opens Installments, the things bought to pay off.
  final VoidCallback? onOpenDebts;

  /// Switches the app to the Reports tab.
  final VoidCallback? onOpenReports;

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
  // Every shortcut shows when the app opens; Show less folds them to three.
  bool _showAllQuickActions = true;

  /// The bills the Safe to Spend card loaded, reused by the tip so the screen
  /// doesn't read them twice.
  List<BillInstance> _bills = const [];

  /// Today's Safe to Spend, worked out by the card below the balance and
  /// shown along the bottom of the balance card.
  SafeToSpend? _safeToSpend;

  static bool _sameFigure(SafeToSpend? a, SafeToSpend b) =>
      a != null &&
      a.walletBalance == b.walletBalance &&
      a.billsDue == b.billsDue &&
      a.goalSavings == b.goalSavings &&
      a.spentToday == b.spentToday &&
      a.daysLeft == b.daysLeft;

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
        (widget.onOpenSavings ?? _openSavings)();
        return;
      case VoiceDestination.installments:
        (widget.onOpenDebts ??
            () => _push(const BillCalendarScreen(initialShowDebts: true)))();
        return;
      case VoiceDestination.debts:
        _push(const DebtsScreen());
        return;
      case VoiceDestination.goals:
        (widget.onOpenGoals ?? () => _push(const GoalsScreen()))();
        return;
      case VoiceDestination.reports:
        (widget.onOpenReports ?? () => _push(const ReportsScreen()))();
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
        onSaved: () => setState(() => _refreshKey++),
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
    final now = widget.today ?? philippineNow();

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

        // The money the user has right now comes first: cash on hand plus
        // cash in bank.
        _TotalBalanceCard(
          wallets: wallets,
          goals: goals ?? const [],
          safeToSpend: _safeToSpend,
        ),
        // Bills due soon, matured savings and the leftover question, worked
        // out from the same inputs as Safe to Spend, whose figure Home no
        // longer shows.
        widget.safeToSpend ??
            SafeToSpendCard(
              key: ValueKey(_refreshKey),
              showFigure: false,
              belowCard: _belowCard,
            ),
        const SizedBox(height: 25),
        _SectionTitle(
          'Quick Actions',
          action: _showAllQuickActions ? 'Show less' : 'View all',
          onAction: () =>
              setState(() => _showAllQuickActions = !_showAllQuickActions),
        ),
        _quickActions(),

        const SizedBox(height: 25),
        // Reports is in the bottom bar and Quick Actions, so the side of
        // the title only says which month this is.
        _SectionTitle(
          'This Month',
          note: '${formatMonthName(now)} ${now.year}',
        ),
        _ThisMonthCard(
          transactions: transactions,
          now: now,
          onOpenInflows: () => _openMonth(TransactionType.income, now),
          onOpenOutflows: () => _openMonth(TransactionType.expense, now),
        ),
        // The tip comes after the numbers it talks about.
        const SizedBox(height: 16),
        _tip(wallets: wallets, transactions: transactions, now: now),

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
    );
  }

  /// Opens the user's savings.
  void _openSavings() => _push(const SetAsideScreen());

  /// Transactions for this month so far, only money in or only money out,
  /// so the list adds up to the box that was tapped.
  void _openMonth(TransactionType type, DateTime now) => _push(
    TransactionsScreen(
      initialFilter: TransactionFilter(
        type: type,
        from: DateTime(now.year, now.month),
        to: DateTime(now.year, now.month, now.day),
      ),
    ),
  );

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
        asset: 'assets/icons/icons8-money-out-96.png',
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
        asset: 'assets/icons/icons8-exchange-96.png',
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
        asset: 'assets/icons/scan-receipt-96.png',
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
        onTap: widget.onOpenSavings ?? _openSavings,
      ),
      (
        asset: 'assets/icons/icons8-goal-96.png',
        title: 'Goals',
        onTap: widget.onOpenGoals ?? () => _push(const GoalsScreen()),
      ),
      (
        asset: 'assets/icons/icons8-combo-chart-100.png',
        title: 'Reports',
        onTap: widget.onOpenReports ?? () => _push(const ReportsScreen()),
      ),
      // Last, side by side: what the user pays off, as two kinds. Money
      // with an hourglass for installments, a money bag for money borrowed.
      (
        asset: 'assets/icons/installment-96.png',
        title: 'Installments',
        onTap:
            widget.onOpenDebts ??
            () => _push(const BillCalendarScreen(initialShowDebts: true)),
      ),
      (
        asset: 'assets/icons/icons8-loan-96.png',
        title: 'Debts',
        onTap: () => _push(const DebtsScreen()),
      ),
    ];
    final visibleActions = _showAllQuickActions
        ? actions
        : actions.take(3).toList();

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
    final figure = inputs.safeToSpend;
    if (!_sameFigure(_safeToSpend, figure)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _safeToSpend = figure);
      });
    }

    return Column(
      children: [
        DueSoonNotice(
          bills: inputs.bills,
          now: inputs.now ?? philippineNow(),
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
    // The newest month that is over with what is left still undecided: what
    // came in less what went out, from the actual records.
    final now = philippineNow();
    final month = monthFlows(
      inputs.cycles,
      inputs.transactions,
    ).where((flow) => flow.awaitingDecision(now)).firstOrNull;
    if (month == null || month.leftToDecide <= 0) {
      return const SizedBox.shrink();
    }
    final undecided = newestCycles(month.undecided);

    return LeftoverNotice(
      cycle: undecided.first,
      leftover: month.leftToDecide,
      onReview: () => _push(
        LeftoverReviewScreen(
          cycle: undecided.first,
          leftover: month.leftToDecide,
          periodEnd: month.period.end,
          others: undecided.skip(1).toList(),
        ),
      ),
    );
  }
}

/// A balance the user has already promised: what is kept for bills, and what
/// is kept as savings. Tapping one opens where that money is going.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onAction, this.note});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  /// Plain text on the right, such as the month shown.
  final String? note;

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
            )
          else if (note != null)
            Text(
              note!,
              style: TextStyle(
                fontSize: 13,
                color: context.appColors.textMuted,
              ),
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

/// Home's top card: the money the user can spend right now, split into
/// cash on hand and cash in bank (banks and e-wallets), the same split
/// setup's Cash Summary makes.
///
/// Money set aside is not spending money, so it is left out: what goals
/// hold inside these accounts, and everything in the Bills and Savings
/// wallets, which is where bills, installments and savings are paid from.
/// The accounts' real total is said under it, so it still matches what the
/// bank shows.
class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({
    required this.wallets,
    this.goals = const [],
    this.safeToSpend,
  });

  /// Null while the wallets are still loading.
  final List<Wallet>? wallets;

  /// The goals, for what they hold inside each account.
  final List<Goal> goals;

  /// Today's Safe to Spend, as a bar along the bottom. Null while it is
  /// worked out; left out while the wallets hold nothing.
  final SafeToSpend? safeToSpend;

  /// What can be spent from [wallet]: its balance less what goals hold in it.
  double _free(Wallet wallet) => freeInWallet(wallet, goals);

  /// The wallets behind one box: each with its balance, opening its own
  /// page when tapped.
  void _showWalletGroup(
    BuildContext context,
    String title,
    String iconAsset,
    List<Wallet> group,
  ) => _showWalletSheet(
    context,
    title: title,
    iconAssets: [iconAsset],
    sections: [(label: null, iconAsset: iconAsset, wallets: group)],
    empty: title == 'Cash on Hand'
        ? 'No cash wallets yet. Add one in Wallets.'
        : 'No bank or e-wallet accounts yet. Add one in Wallets.',
  );

  /// Every wallet in the Total Balance, cash on hand first, each group with
  /// what it adds up to, so the big number can be checked line by line.
  void _showAllWallets(
    BuildContext context,
    List<Wallet> cash,
    List<Wallet> bank,
  ) => _showWalletSheet(
    context,
    title: 'Available Balance',
    iconAssets: [WalletType.cash.iconAsset, WalletType.bank.iconAsset],
    sections: [
      (
        label: 'Cash on Hand',
        iconAsset: WalletType.cash.iconAsset,
        wallets: cash,
      ),
      (
        label: 'Cash in Bank',
        iconAsset: WalletType.bank.iconAsset,
        wallets: bank,
      ),
    ],
    empty: 'No wallets yet. Add one in Wallets.',
    explainsGoals: true,
  );

  void _showWalletSheet(
    BuildContext context, {
    required String title,
    required List<String> iconAssets,
    required List<({String? label, String iconAsset, List<Wallet> wallets})>
    sections,
    required String empty,
    bool explainsGoals = false,
  }) {
    final navigator = Navigator.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final colors = sheetContext.appColors;
        final masked = sheetContext.select<AppSettingsProvider, bool>(
          (settings) => settings.amountsMasked,
        );
        final all = [for (final section in sections) ...section.wallets];
        final total = all.fold<double>(0, (sum, w) => sum + _free(w));
        final count = all.length;

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Both icons for the total, as on the Cash Summary.
                    for (final asset in iconAssets)
                      Image.asset(
                        asset,
                        width: iconAssets.length == 1 ? 28 : 22,
                        height: iconAssets.length == 1 ? 28 : 22,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Row(
                  children: [
                    MoneyText(
                      total,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      count == 0
                          ? ''
                          : ' across $count wallet${count == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 14, color: colors.textMuted),
                    ),
                  ],
                ),
                // How the figure is reached, here rather than on the card:
                // what is in the accounts, less what goals hold, is what
                // can be spent.
                if (explainsGoals &&
                    all.fold<double>(0, (sum, w) => sum + w.balance) - total >
                        0.005) ...[
                  const SizedBox(height: 12),
                  _GoalMathCard(
                    inAccounts: all.fold<double>(
                      0,
                      (sum, w) => sum + w.balance,
                    ),
                    available: total,
                  ),
                ],
                const SizedBox(height: 14),
                if (all.isEmpty)
                  Text(
                    empty,
                    style: TextStyle(color: colors.textMuted, height: 1.4),
                  ),
                if (all.isNotEmpty)
                  for (final section in sections) ...[
                    // A named group says what it adds up to before its
                    // wallets, so each part of the total can be checked.
                    if (section.label != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Row(
                          children: [
                            Image.asset(
                              section.iconAsset,
                              width: 20,
                              height: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                section.label!,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            MoneyText(
                              section.wallets.fold<double>(
                                0,
                                (sum, w) => sum + _free(w),
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (section.label != null && section.wallets.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'None yet.',
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ),
                    for (final wallet in section.wallets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: colors.pageBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: colors.border),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              navigator.push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      WalletDetailScreen(wallet: wallet),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colors.primaryTint,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Image.asset(wallet.iconAsset),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          wallet.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          wallet.type.label,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.textMuted,
                                          ),
                                        ),
                                        // What goals hold here, so the
                                        // amount beside it adds up.
                                        if (wallet.balance - _free(wallet) >
                                            0.005)
                                          Text(
                                            '${formatPeso(wallet.balance - _free(wallet), masked: masked)} '
                                            'set aside for goals',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colors.textMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  MoneyText(
                                    _free(wallet),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: colors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// What the figure is, shown as the sum it comes from with the user's
  /// own amounts, laid out like setup's Cash Summary: cash on hand, cash in
  /// bank, and the two together. Then what bank accounts earn in a year,
  /// when they have a rate, and what the figure leaves out.
  void _explain(
    BuildContext context, {
    required double cashOnHand,
    required double inBank,
    required double forGoals,
    required List<Wallet> bankWallets,
    SafeToSpend? safeToSpend,
  }) {
    final available = cashOnHand + inBank;
    // What the accounts with a rate earn in a year, after the bank's tax.
    final interest = bankWallets
        .map((wallet) => wallet.estimatedAnnualInterestIncome)
        .whereType<double>()
        .fold<double>(0, (total, gross) => total + afterTax(gross));
    showDialog<void>(
      context: context,
      builder: (context) {
        final colors = context.appColors;

        Widget line(
          Widget icon,
          String label,
          double amount, {
          String? sign,
          bool result = false,
        }) {
          final style = TextStyle(
            fontSize: result ? 15 : 14,
            fontWeight: result ? FontWeight.bold : FontWeight.normal,
            color: result ? colors.textPrimary : colors.textBody,
          );
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(width: 36, child: icon),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: style)),
                MoneyText(amount, sign: sign, style: style),
              ],
            ),
          );
        }

        return AlertDialog(
          key: const Key('available-balance-explained'),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Image.asset(infoIcon),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Available Balance')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The money you can spend right now.',
                  style: TextStyle(color: colors.textBody, height: 1.4),
                ),
                const SizedBox(height: 12),
                line(
                  Image.asset(WalletType.cash.iconAsset, width: 22, height: 22),
                  'Cash on Hand',
                  cashOnHand,
                ),
                line(
                  Image.asset(WalletType.bank.iconAsset, width: 22, height: 22),
                  'Cash in Bank',
                  inBank,
                ),
                Divider(height: 14, color: colors.border),
                line(
                  // Cash on hand plus cash in bank, so both their icons.
                  Row(
                    children: [
                      Image.asset(
                        WalletType.cash.iconAsset,
                        width: 18,
                        height: 18,
                      ),
                      Image.asset(
                        WalletType.bank.iconAsset,
                        width: 18,
                        height: 18,
                      ),
                    ],
                  ),
                  'Available Balance',
                  available,
                  result: true,
                ),
                if (forGoals > 0.005)
                  Padding(
                    padding: const EdgeInsets.only(left: 44, bottom: 4),
                    child: Text(
                      'Both are after the ${formatPeso(forGoals)} set aside '
                      'for your goals.',
                      key: const Key('available-balance-goals'),
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ),
                if (interest > 0.005) ...[
                  const SizedBox(height: 4),
                  line(
                    Image.asset(
                      'assets/icons/icons8-combo-chart-100.png',
                      width: 22,
                      height: 22,
                    ),
                    'Interest in a Year (after tax)',
                    interest,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: Text(
                      'An estimate after the ${(interestTaxRate * 100).round()}% '
                      'tax banks keep. It is not in Cash in Bank until it is '
                      'paid; FinAssist reminds you to add it as income.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // What is left out, in one short note.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.primaryTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset(
                        'assets/icons/icons8-money-box-96.png',
                        width: 22,
                        height: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Money in Savings is not included.\n'
                          'Bills are taken out when you pay them.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: colors.textBody,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // The bar along the bottom of the card, worked out.
                if (safeToSpend != null && safeToSpend.walletBalance > 0) ...[
                  const Divider(height: 28),
                  Text(
                    'Safe to spend today',
                    key: const Key('safe-to-spend-explained'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'What you can spend today and still have enough for '
                    'bills due this month and your goals.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SafeToSpendWorking(safeToSpend),
                ],
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: openButtonStyle(),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );
    final list = wallets ?? const <Wallet>[];
    // The wallets in the total: cash ones on hand, the rest in bank.
    final counted = list
        .where((wallet) => !wallet.archived && !wallet.isSetAside)
        .toList();
    final cashWallets = counted
        .where((wallet) => wallet.type == WalletType.cash)
        .toList();
    final bankWallets = counted
        .where((wallet) => wallet.type != WalletType.cash)
        .toList();
    // Only what can be spent: each account less what its goals hold.
    final cashOnHand = cashWallets.fold<double>(
      0,
      (sum, wallet) => sum + _free(wallet),
    );
    final inBank = bankWallets.fold<double>(
      0,
      (sum, wallet) => sum + _free(wallet),
    );
    final available = cashOnHand + inBank;
    void explain() => _explain(
      context,
      cashOnHand: cashOnHand,
      inBank: inBank,
      forGoals: totalWalletBalance(list) - available,
      bankWallets: bankWallets,
      safeToSpend: safeToSpend,
    );

    // Each box opens the wallets it adds up.
    Widget part(
      String label,
      String iconAsset,
      double amount,
      List<Wallet> group,
    ) => Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: wallets == null
              ? null
              : () => _showWalletGroup(context, label, iconAsset, group),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                Image.asset(iconAsset, width: 24, height: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      MoneyText(
                        amount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 16),
      decoration: BoxDecoration(
        color: appPrimaryBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Available Balance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // The app's one privacy control: hides every amount. Both are
              // the app's own colored icons, like every other icon in it.
              AppIconButton(
                iconAsset: masked ? amountsHiddenIcon : amountsShownIcon,
                tooltip: masked ? 'Show amounts' : 'Hide amounts',
                onPressed: () =>
                    context.read<AppSettingsProvider>().toggleAmountsMasked(),
              ),
              AppIconButton(
                key: const Key('total-balance-info'),
                iconAsset: infoIcon,
                tooltip: 'What this includes',
                onPressed: explain,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: wallets == null
                ? const SizedBox(
                    height: 38,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                // The total opens every wallet in it, like the two boxes
                // below open theirs.
                : InkWell(
                    key: const Key('total-balance-open'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () =>
                        _showAllWallets(context, cashWallets, bankWallets),
                    child: Row(
                      children: [
                        Flexible(
                          child: MoneyText(
                            available,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 26,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
          ),
          // The accounts' real total, so the figure above can be checked
          // against the bank's.
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                part(
                  'Cash on Hand',
                  WalletType.cash.iconAsset,
                  cashOnHand,
                  cashWallets,
                ),
                const SizedBox(width: 8),
                part(
                  'Cash in Bank',
                  WalletType.bank.iconAsset,
                  inBank,
                  bankWallets,
                ),
              ],
            ),
          ),
          // How much of today's safe amount is spent; the bulb above
          // explains it.
          if (safeToSpend case final figure? when figure.walletBalance > 0) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SafeToSpendBar(safeToSpend: figure, onTap: explain),
            ),
          ],
        ],
      ),
    );
  }
}

/// The sum behind the available balance, for whoever wants it: what is in
/// the accounts, less what goals hold, is what can be spent.
class _GoalMathCard extends StatelessWidget {
  const _GoalMathCard({required this.inAccounts, required this.available});

  final double inAccounts;
  final double available;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget line(
      String label,
      double amount, {
      String? sign,
      bool bold = false,
    }) {
      final style = TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: bold ? colors.textPrimary : colors.textBody,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            MoneyText(amount, sign: sign, style: style),
          ],
        ),
      );
    }

    return Container(
      key: const Key('available-balance-math'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          line('In your accounts', inAccounts),
          line('Set aside for goals', inAccounts - available, sign: '-'),
          Divider(height: 12, color: colors.border),
          line('Available to spend', available, bold: true),
        ],
      ),
    );
  }
}

/// This month's spending: the total, how it splits, and the biggest
/// categories.
/// This month at a glance: what came in and what went out, each opening its
/// own list, then where the spending went by category.
class _ThisMonthCard extends StatelessWidget {
  const _ThisMonthCard({
    required this.transactions,
    required this.now,
    required this.onOpenInflows,
    required this.onOpenOutflows,
  });

  final List<AppTransaction>? transactions;
  final DateTime now;
  final VoidCallback onOpenInflows;
  final VoidCallback onOpenOutflows;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final list = transactions;
    if (list == null) {
      return const _Card(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final month = transactionsIn(list, ReportPeriod.monthOf(now));
    // Transfers between the user's own wallets are neither, and neither is
    // money borrowed or lent: the same rule as Transactions and Reports.
    final flow = inAndOut(month);
    final spending = spendingByCategory(month);

    Widget box({
      required Key key,
      required String label,
      required double amount,
      required String sign,
      required Color color,
      required VoidCallback onTap,
    }) => Expanded(
      child: Material(
        color: colors.pageBackground,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 12, color: colors.textBody),
                      ),
                      const SizedBox(height: 2),
                      MoneyText(
                        amount,
                        sign: amount > 0 ? sign : null,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              box(
                key: const Key('month-inflow'),
                label: 'Inflow',
                amount: flow.moneyIn,
                sign: '+',
                color: confirmColorOn(context),
                onTap: onOpenInflows,
              ),
              const SizedBox(width: 10),
              box(
                key: const Key('month-outflow'),
                label: 'Outflow',
                amount: flow.moneyOut,
                sign: '-',
                color: dangerColorOn(context),
                onTap: onOpenOutflows,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Spending by category',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (spending.isEmpty)
            Text(
              'No spending yet this month. Expenses and bills you pay show '
              'up here.',
              style: TextStyle(color: colors.textBody, height: 1.4),
            )
          else ...[
            SpendingBar(spending: spending, limit: 5),
            const SizedBox(height: 8),
            SpendingLegendGrid(spending: spending, limit: 5),
          ],
        ],
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
