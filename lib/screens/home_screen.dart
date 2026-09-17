import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'income_waterfall_screen.dart';
import 'insights_screen.dart';
import 'leftover_review_screen.dart';
import 'chatbot_screen.dart';
import 'profile_screen.dart';
import 'ocr_screen.dart';
import 'voice_recognition_screen.dart';
import 'bill_calendar_screen.dart';
import 'budget_screen.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../utils/categories.dart';
import '../utils/money_format.dart';
import '../models/allocation.dart';
import '../widgets/money_text.dart';
import '../widgets/safe_to_spend_card.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/quick_action_tile.dart';

const Color primaryBlue = Color(0xFF1976D2);

class HomeScreen extends StatefulWidget {
  const HomeScreen({this.onOpenTransactions, super.key});

  /// Switches the app to the Transactions tab.
  final VoidCallback? onOpenTransactions;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final User? user = FirebaseAuth.instance.currentUser;

  // Held here so a rebuild doesn't start a second listener.
  late final Stream<List<Wallet>> _wallets = WalletService.watchWallets();

  // =================================================
  // SECTION TITLE
  // =================================================

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: context.appColors.textBody,
        ),
      ),
    );
  }

  // =================================================
  // NAVIGATION
  // =================================================

  void _openInsights() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const InsightsScreen()),
    );
  }

  void _openChatbot() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChatbotScreen()),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
  }

  void _openBudgets() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BudgetScreen()),
    );
  }

  // =================================================
  // HOME SCREEN
  // =================================================

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('No user is currently signed in.')),
      );
    }

    final expensesStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: context.appColors.pageBackground,

      // =================================================
      // APP BAR
      // =================================================
      appBar: AppBar(
        elevation: 0,
        backgroundColor: context.appColors.card,
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
            onPressed: _openChatbot,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: Image.asset(
              'assets/icons/icons8-settings-96.png',
              width: 24,
              height: 24,
            ),
            onPressed: _openProfile,
          ),

          const SizedBox(width: 8),
        ],
      ),

      // =================================================
      // BODY
      // =================================================
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: expensesStream,

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error loading expenses:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final documents = snapshot.data?.docs ?? [];

          // =================================================
          // CALCULATE EXPENSE TOTALS
          // =================================================

          double totalExpenses = 0;

          final Map<String, double> categoryTotals = {};

          for (final document in documents) {
            final data = document.data();

            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;

            final category = data['category']?.toString() ?? 'Other';

            totalExpenses += amount;

            categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
          }

          // =================================================
          // SORT CATEGORIES
          // =================================================

          final sortedCategories = categoryTotals.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          // =================================================
          // RECENT EXPENSES
          // =================================================

          final recentExpenses = documents.take(5).toList();

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },

            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  const SizedBox(height: 20),

                  // =================================================
                  // GREETING
                  // =================================================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          'Hello, ${user!.displayName ?? 'User'}!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 5),

                        const Text(
                          'Here is your financial overview.',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // =================================================
                  // TOTAL BALANCE CARD
                  // =================================================
                  _buildTotalBalanceCard(totalExpenses, documents.length),

                  const SizedBox(height: 25),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SafeToSpendCard(
                      footerBuilder: _overviewButtons,
                      belowCard: _leftoverNotice,
                    ),
                  ),

                  const SizedBox(height: 25),

                  // =================================================
                  // QUICK ACTIONS
                  // =================================================
                  _sectionTitle('Quick Actions'),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),

                    // Two rows of two: a single row of four squeezes the
                    // labels until they wrap on a narrow phone.
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: QuickActionTile(
                                icon: Image.asset(
                                  'assets/icons/icons8-calendar-96.png',
                                  width: 24,
                                  height: 24,
                                ),
                                title: 'Bill Planner',
                                onTap: _openBillPlanner,
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: QuickActionTile(
                                icon: Image.asset(
                                  'assets/icons/icons8-combo-chart-100.png',
                                  width: 24,
                                  height: 24,
                                ),
                                title: 'Reports',
                                onTap: _openInsights,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: QuickActionTile(
                                icon: Image.asset(
                                  'assets/icons/icons8-camera-96.png',
                                  width: 24,
                                  height: 24,
                                ),
                                title: 'OCR Receipt',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const OcrScreen(autoStart: true),
                                    ),
                                  );
                                },
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: QuickActionTile(
                                icon: Image.asset(
                                  'assets/icons/icons8-microphone-96.png',
                                  width: 24,
                                  height: 24,
                                ),
                                title: 'Voice Input',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const VoiceRecognitionScreen(
                                            autoStart: true,
                                          ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // =================================================
                  // SPENDING SUMMARY
                  // FULL PIE CHART LEFT + DETAILS RIGHT
                  // =================================================
                  _sectionTitle('Spending Summary'),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),

                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),

                      decoration: BoxDecoration(
                        color: context.appColors.card,
                        borderRadius: BorderRadius.circular(16),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),

                      child: categoryTotals.isEmpty || totalExpenses == 0
                          ? const SizedBox(
                              height: 220,

                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,

                                  children: [
                                    Image(
                                      image: AssetImage(
                                        'assets/icons/icons8-pie-chart-96.png',
                                      ),
                                      width: 56,
                                      height: 56,
                                    ),

                                    SizedBox(height: 12),

                                    Text(
                                      'No expenses recorded yet.',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                // ========================================
                                // TOTAL ABOVE PIE CHART
                                // ========================================
                                const Text(
                                  'Total Expenses',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                MoneyText(
                                  totalExpenses,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 18),

                                // ========================================
                                // PIE CHART LEFT + DETAILS RIGHT
                                // ========================================
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,

                                  children: [
                                    // ====================================
                                    // FULL PIE CHART
                                    // ====================================
                                    Expanded(
                                      flex: 5,

                                      child: SizedBox(
                                        height: 220,

                                        child: CustomPaint(
                                          painter: SpendingPieChartPainter(
                                            categoryTotals: categoryTotals,

                                            totalExpenses: totalExpenses,

                                            categoryColor: categoryColor,

                                            dividerColor:
                                                context.appColors.card,
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 15),

                                    // ====================================
                                    // CATEGORY DETAILS
                                    // ====================================
                                    Expanded(
                                      flex: 5,

                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,

                                        children: [
                                          ...sortedCategories.take(5).map((
                                            entry,
                                          ) {
                                            final category = entry.key;

                                            final amount = entry.value;

                                            final percentage = totalExpenses > 0
                                                ? (amount / totalExpenses) * 100
                                                : 0;

                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 14,
                                              ),

                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 10,
                                                    height: 10,

                                                    decoration: BoxDecoration(
                                                      color: categoryColor(
                                                        category,
                                                      ),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),

                                                  const SizedBox(width: 7),

                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,

                                                      children: [
                                                        Text(
                                                          category,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,

                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),

                                                        const SizedBox(
                                                          height: 2,
                                                        ),

                                                        MoneyText(
                                                          amount,

                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  Text(
                                                    '${percentage.toStringAsFixed(0)}%',

                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),

                                          if (sortedCategories.length > 5)
                                            const Text(
                                              'Showing top 5 categories',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 10,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // =================================================
                  // RECENT TRANSACTIONS
                  // =================================================
                  _sectionTitle('Recent Transactions'),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),

                    child: Container(
                      width: double.infinity,

                      decoration: BoxDecoration(
                        color: context.appColors.card,
                        borderRadius: BorderRadius.circular(16),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),

                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user!.uid)
                            .collection('dailyIncomeTransactions')
                            .orderBy('date', descending: true)
                            .limit(5)
                            .snapshots(),
                        builder: (context, incomeSnapshot) {
                          final transactions =
                              <Map<String, dynamic>>[
                                ...recentExpenses.take(5).map((document) {
                                  final data = document.data();
                                  return {
                                    'data': data,
                                    'isIncome': false,
                                    'sortDate': data['date'] as Timestamp?,
                                  };
                                }),
                                ...(incomeSnapshot.data?.docs ?? []).map((
                                  document,
                                ) {
                                  final data = document.data();
                                  return {
                                    'data': data,
                                    'isIncome': true,
                                    'sortDate': data['date'] as Timestamp?,
                                  };
                                }),
                              ]..sort((a, b) {
                                final aDate =
                                    (a['sortDate'] as Timestamp?)?.toDate() ??
                                    DateTime.fromMillisecondsSinceEpoch(0);
                                final bDate =
                                    (b['sortDate'] as Timestamp?)?.toDate() ??
                                    DateTime.fromMillisecondsSinceEpoch(0);
                                return bDate.compareTo(aDate);
                              });

                          final recentTransactions = transactions
                              .take(5)
                              .toList();

                          if (recentTransactions.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(30),
                              child: Center(
                                child: Text(
                                  'No recent transactions.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: [
                              ...recentTransactions.map((transaction) {
                                final data =
                                    transaction['data'] as Map<String, dynamic>;
                                final isIncome =
                                    transaction['isIncome'] as bool;
                                final amount =
                                    (data['amount'] as num?)?.toDouble() ?? 0.0;
                                final category = isIncome
                                    ? 'Daily Income'
                                    : data['category']?.toString() ?? 'Other';
                                final description = isIncome
                                    ? 'Daily Income: ${data['source'] ?? 'Other'}'
                                    : data['description']?.toString() ??
                                          'Expense';
                                final date = data['date'] as Timestamp?;
                                final transactionColor = isIncome
                                    ? Colors.green
                                    : Colors.red;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: transactionColor.withValues(
                                        alpha: 0.12,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(9),
                                    child: Image.asset(
                                      isIncome
                                          ? 'assets/icons/icons8-money-transfer-96.png'
                                          : 'assets/icons/icons8-expenses-64.png',
                                    ),
                                  ),
                                  title: Text(
                                    description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    date != null
                                        ? _formatDate(date.toDate())
                                        : category,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  trailing: MoneyText(
                                    amount,
                                    sign: isIncome ? '+' : '-',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: transactionColor,
                                    ),
                                  ),
                                );
                              }),
                              if (documents.length > 5 &&
                                  widget.onOpenTransactions != null)
                                TextButton(
                                  onPressed: widget.onOpenTransactions,
                                  child: const Text('View All Transactions'),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // =================================================
                  // AI FINANCIAL INSIGHT
                  // =================================================
                  _sectionTitle('AI Financial Insight'),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),

                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),

                      decoration: BoxDecoration(
                        color: context.appColors.card,

                        borderRadius: BorderRadius.circular(16),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),

                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Container(
                            width: 45,
                            height: 45,

                            decoration: BoxDecoration(
                              color: primaryBlue.withValues(alpha: 0.1),

                              shape: BoxShape.circle,
                            ),

                            padding: const EdgeInsets.all(10),
                            child: Image.asset(
                              'assets/icons/icons8-idea-96.png',
                            ),
                          ),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                const Text(
                                  'Your Spending Insight',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 6),

                                Text(
                                  totalExpenses == 0
                                      ? 'Start adding your expenses to receive personalized financial insights.'
                                      : 'You have recorded ${documents.length} expense${documents.length == 1 ? '' : 's'} totaling ${formatPeso(totalExpenses)}. Check your Insights section for a more detailed analysis.',

                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    height: 1.5,
                                  ),
                                ),

                                const SizedBox(height: 10),

                                TextButton(
                                  onPressed: _openInsights,

                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                  ),

                                  child: const Text(
                                    'View Financial Insights →',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // =================================================
  // QUICK ACTION WIDGET
  // =================================================

  Widget _buildTotalBalanceCard(double totalExpenses, int transactionCount) {
    return StreamBuilder<List<Wallet>>(
      stream: _wallets,
      builder: (context, walletSnapshot) {
        final wallets = walletSnapshot.data ?? const <Wallet>[];

        // Once there are wallets, the balance is simply what they hold. It is
        // the same number the Wallet tab shows, so the two can't disagree.
        if (wallets.isNotEmpty) {
          final count = wallets.length;

          return _totalBalanceCardView(
            balance: totalWalletBalance(wallets),
            captions: [
              'Across $count wallet${count == 1 ? '' : 's'}',
              '$transactionCount transaction'
                  '${transactionCount == 1 ? '' : 's'} recorded',
            ],
          );
        }

        // No wallets yet: fall back to income less expenses, so the card is
        // never blank for someone who has not added one.
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .get(),
          builder: (context, snapshot) {
            final profile = snapshot.data?.data();
            final fixedIncome = (profile?['income'] as num?)?.toDouble() ?? 0;
            final dailyIncome =
                (profile?['dailyIncome'] as num?)?.toDouble() ??
                (profile?['otherIncome'] as num?)?.toDouble() ??
                0;
            final totalAccumulatedIncome = fixedIncome + dailyIncome;

            if (snapshot.connectionState == ConnectionState.waiting &&
                profile == null) {
              return const SizedBox(
                height: 132,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return _totalBalanceCardView(
              balance: totalAccumulatedIncome - totalExpenses,
              captions: [
                '${formatPeso(totalAccumulatedIncome)} income less '
                    '${formatPeso(totalExpenses)} in expenses',
                '$transactionCount transaction'
                    '${transactionCount == 1 ? '' : 's'} recorded',
              ],
            );
          },
        );
      },
    );
  }

  Widget _totalBalanceCardView({
    required double balance,
    required List<String> captions,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: primaryBlue,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Total Balance',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 14),
            MoneyText(
              balance,
              style: TextStyle(
                color: balance < 0 ? Colors.redAccent : Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            for (final caption in captions) ...[
              Text(
                caption,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 3),
            ],
          ],
        ),
      ),
    );
  }

  /// The buttons under the Safe-to-Spend figure. "Daily Limit" opens the
  /// same editor as the card's pencil.
  Widget _overviewButtons(BuildContext context, VoidCallback openLimitEditor) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final saved = await showIncomeWaterfall(context);
                  if (saved && mounted) setState(() {});
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
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openBudgets,
            icon: Image.asset(
              'assets/icons/icons8-money-box-96.png',
              width: 18,
              height: 18,
            ),
            label: const Text('Manage Category Budgets'),
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
      onReview: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LeftoverReviewScreen(
            cycle: cycle,
            leftover: leftover,
            periodEnd: period.end,
          ),
        ),
      ),
    );
  }

  void _openBillPlanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BillCalendarScreen()),
    );
  }

  /// Same blue as the + button in both light and dark mode, so these
  /// buttons keep one look across themes.
  static final ButtonStyle _overviewButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryBlue,
    foregroundColor: Colors.white,
    elevation: 0,
    minimumSize: const Size(0, 46),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: const TextStyle(fontWeight: FontWeight.w600),
  );

  // =================================================
  // DATE FORMAT
  // =================================================

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

// =====================================================
// FULL PIE CHART CUSTOM PAINTER
// =====================================================

class SpendingPieChartPainter extends CustomPainter {
  final Map<String, double> categoryTotals;
  final double totalExpenses;
  final Color Function(String) categoryColor;
  final Color dividerColor;

  SpendingPieChartPainter({
    required this.categoryTotals,
    required this.totalExpenses,
    required this.categoryColor,
    required this.dividerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalExpenses <= 0 || categoryTotals.isEmpty) {
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);

    final radius = size.shortestSide * 0.42;

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    double startAngle = -3.141592653589793 / 2;

    for (final entry in sortedCategories) {
      final category = entry.key;

      final amount = entry.value;

      final percentage = amount / totalExpenses;

      final sweepAngle = percentage * 2 * 3.141592653589793;

      // ==========================================
      // PIE SLICE
      // ==========================================

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = categoryColor(category);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),

        startAngle,

        sweepAngle,

        true,

        paint,
      );

      // ==========================================
      // DIVIDER (matches the card background)
      // ==========================================

      final dividerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = dividerColor;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),

        startAngle,

        sweepAngle,

        true,

        dividerPaint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant SpendingPieChartPainter oldDelegate) {
    return oldDelegate.categoryTotals != categoryTotals ||
        oldDelegate.totalExpenses != totalExpenses ||
        oldDelegate.dividerColor != dividerColor;
  }
}
