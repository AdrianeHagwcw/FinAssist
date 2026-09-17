import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/report.dart';
import '../models/transaction_filter.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/money_text.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/safe_to_spend_card.dart';
import '../widgets/spending_chart.dart';
import '../widgets/transaction_edit_sheet.dart';
import '../widgets/transaction_row.dart';
import 'bill_calendar_screen.dart';
import 'chatbot_screen.dart';
import 'debts_screen.dart';
import 'goals_screen.dart';
import 'income_waterfall_screen.dart';
import 'leftover_review_screen.dart';
import 'ocr_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';
import 'voice_recognition_screen.dart';

/// The landing screen: what is safe to spend today, what the wallets hold,
/// shortcuts, and a glance at this month's spending.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.onOpenTransactions,
    this.onOpenWallets,
    this.onOpenSavings,
    this.onOpenDebts,
    this.userName,
    this.wallets,
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
  final VoidCallback? onOpenSavings;
  final VoidCallback? onOpenDebts;

  /// Replaces the signed-in user's name. Used by tests.
  final String? userName;

  /// Replaces the live wallets. Used by tests.
  final Stream<List<Wallet>>? wallets;

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
  late final Stream<List<AppTransaction>> _transactions =
      widget.transactions ?? WalletService.watchTransactions();

  // Changing this rebuilds the Safe to Spend card after income is added.
  int _refreshKey = 0;

  String get _name {
    if (widget.userName != null) return widget.userName!;
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    return name == null || name.isEmpty ? 'there' : name;
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
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
              'assets/icons/icons8-robot-48.png',
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
            builder: (context, snapshot) => _buildBody(
              context,
              wallets: walletSnapshot.data,
              transactions: snapshot.data,
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
            SafeToSpendCard(
              key: ValueKey(_refreshKey),
              footerBuilder: _overviewButtons,
              belowCard: _leftoverNotice,
            ),
        const SizedBox(height: 16),
        _BalanceCard(wallets: wallets, onTap: widget.onOpenWallets),

        const SizedBox(height: 25),
        _SectionTitle('Quick Actions'),
        _quickActions(),

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

        const SizedBox(height: 25),
        _SectionTitle('Spending Insight'),
        _InsightCard(
          transactions: transactions,
          now: now,
          onOpenReports: () => _push(const ReportsScreen()),
        ),
      ],
    );
  }

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

    // Two full rows of three: places first, then Reports and the two other
    // ways to log an expense.
    return Column(
      children: [
        Row(
          children: [
            tile(
              'assets/icons/icons8-calendar-96.png',
              'Bill Planner',
              () => _push(const BillCalendarScreen()),
            ),
            const SizedBox(width: 12),
            tile(
              'assets/icons/icons8-money-box-96.png',
              'Savings',
              widget.onOpenSavings ?? () => _push(const GoalsScreen()),
            ),
            const SizedBox(width: 12),
            tile(
              'assets/icons/lend-96.png',
              'Debts',
              widget.onOpenDebts ?? () => _push(const DebtsScreen()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            tile(
              'assets/icons/icons8-combo-chart-100.png',
              'Reports',
              () => _push(const ReportsScreen()),
            ),
            const SizedBox(width: 12),
            tile(
              'assets/icons/icons8-camera-96.png',
              'OCR Receipt',
              () => _push(const OcrScreen(autoStart: true)),
            ),
            const SizedBox(width: 12),
            tile(
              'assets/icons/icons8-microphone-96.png',
              'Voice Input',
              () => _push(const VoiceRecognitionScreen(autoStart: true)),
            ),
          ],
        ),
      ],
    );
  }

  /// The buttons under the Safe to Spend figure. "Daily Limit" opens the
  /// same editor as the card's pencil.
  Widget _overviewButtons(BuildContext context, VoidCallback openLimitEditor) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              final saved = await showIncomeWaterfall(context);
              if (saved && mounted) setState(() => _refreshKey++);
            },
            icon: Image.asset(
              'assets/icons/icons8-money-transfer-96.png',
              width: 18,
              height: 18,
            ),
            label: const Text('Add Income'),
            style: _overviewButtonStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: openLimitEditor,
            icon: Image.asset(
              'assets/icons/icons8-calendar-96.png',
              width: 18,
              height: 18,
            ),
            label: const Text('Daily Limit'),
            style: _overviewButtonStyle,
          ),
        ),
      ],
    );
  }

  /// Offers the leftover review once a pay period is on its last day and
  /// what was left of it hasn't been decided.
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

  /// Same blue as the + button in both light and dark mode, so these
  /// buttons keep one look across themes.
  static final ButtonStyle _overviewButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: appPrimaryBlue,
    foregroundColor: Colors.white,
    elevation: 0,
    minimumSize: const Size(0, 46),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: const TextStyle(fontWeight: FontWeight.w600),
  );
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
    final count = list?.length ?? 0;
    final caption = list == null
        ? 'Loading your wallets…'
        : count == 0
        ? 'Add a wallet to start tracking your money'
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
                      'Total Balance',
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
              onTap: () => showTransactionEditSheet(context, transaction),
            ),
          ),
      ],
    );
  }
}

/// The most useful observation about this month, from the same rules as
/// Reports.
class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.transactions,
    required this.now,
    required this.onOpenReports,
  });

  final List<AppTransaction>? transactions;
  final DateTime now;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final insights = transactions == null
        ? const <String>[]
        : insightsFor(
            transactions!,
            period: ReportPeriod.monthOf(now),
            range: ReportRange.month,
            limit: 1,
          );

    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 45,
            height: 45,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.primaryTint,
              shape: BoxShape.circle,
            ),
            child: Image.asset('assets/icons/icons8-idea-96.png'),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insights.isEmpty
                      ? 'Log your spending for a few days and FinAssist will '
                            'point out patterns worth knowing.'
                      : insights.first,
                  style: TextStyle(color: colors.textBody, height: 1.5),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onOpenReports,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: colors.primaryText,
                  ),
                  child: const Text('View Reports →'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
