import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'insights_screen.dart';
import 'chatbot_screen.dart';
import 'profile_screen.dart';
import 'ocr_screen.dart';
import 'voice_recognition_screen.dart';
import 'budget_screen.dart';
import '../services/user_profile_service.dart';
import '../utils/categories.dart';
import '../utils/money_format.dart';
import '../widgets/money_text.dart';
import '../theme/app_colors.dart';
import '../widgets/add_income_dialog.dart';
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
            icon: Icon(
              Icons.smart_toy_outlined,
              color: context.appColors.textBody,
            ),
            onPressed: _openChatbot,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: Icon(
              Icons.settings_outlined,
              color: context.appColors.textBody,
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
                          'Hello, ${user!.displayName ?? 'User'}! 👋',
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

                  _buildFinancialOverview(documents),

                  const SizedBox(height: 25),

                  // =================================================
                  // QUICK ACTIONS
                  // =================================================
                  _sectionTitle('Quick Actions'),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),

                    child: Row(
                      children: [
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

                        const SizedBox(width: 12),

                        Expanded(
                          child: QuickActionTile(
                            icon: Image.asset(
                              'assets/icons/icons8-camera-intelligence-94.png',
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
                              'assets/icons/icons8-mic-94.png',
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
                                    Icon(
                                      Icons.pie_chart_outline,
                                      size: 60,
                                      color: Colors.grey,
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
                                    child: Icon(
                                      isIncome
                                          ? Icons.arrow_downward
                                          : Icons.arrow_upward,
                                      color: transactionColor,
                                      size: 20,
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

                            child: const Icon(
                              Icons.auto_awesome,
                              color: primaryBlue,
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
    final profileFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .get();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final fixedIncome = (profile?['income'] as num?)?.toDouble() ?? 0;
        final dailyIncome =
            (profile?['dailyIncome'] as num?)?.toDouble() ??
            (profile?['otherIncome'] as num?)?.toDouble() ??
            0;
        final totalAccumulatedIncome = fixedIncome + dailyIncome;
        final totalBalance = totalAccumulatedIncome - totalExpenses;

        if (snapshot.connectionState == ConnectionState.waiting &&
            profile == null) {
          return const SizedBox(
            height: 132,
            child: Center(child: CircularProgressIndicator()),
          );
        }

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
                  totalBalance,
                  style: TextStyle(
                    color: totalBalance < 0 ? Colors.redAccent : Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${formatPeso(totalAccumulatedIncome)} income less ${formatPeso(totalExpenses)} in expenses',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  '$transactionCount transaction${transactionCount == 1 ? '' : 's'} recorded',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFinancialOverview(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final profileFuture = UserProfileService.getDailyBudgetProfile();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final dailyBudget =
            (profile?['dailyBudget'] as num?)?.toDouble() ??
            (profile?['budget'] as num?)?.toDouble() ??
            0;
        final income = (profile?['income'] as num?)?.toDouble() ?? 0;
        final dailyBudgetStart =
            (profile?['dailyBudgetStartedAt'] as Timestamp?)?.toDate();
        final dailyExpenses = dailyBudgetStart == null
            ? 0.0
            : documents.fold<double>(0, (total, document) {
                final data = document.data();
                final date = (data['date'] as Timestamp?)?.toDate();
                if (date == null || date.isBefore(dailyBudgetStart)) {
                  return total;
                }
                return total + ((data['amount'] as num?)?.toDouble() ?? 0);
              });
        final remainingBudget = dailyBudget - dailyExpenses;
        final budgetUsed = dailyBudget > 0
            ? (dailyExpenses / dailyBudget).clamp(0.0, 1.0).toDouble()
            : 0.0;
        final budgetUsedColor = budgetUsed >= 1.0
            ? Colors.red
            : budgetUsed >= 0.75
            ? Colors.amber.shade700
            : context.appColors.primaryText;

        if (snapshot.connectionState == ConnectionState.waiting &&
            profile == null) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return Padding(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Financial Overview',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _overviewAmount(
                      'Income',
                      income,
                      color: Colors.green,
                      icon: Icons.arrow_downward,
                    ),
                    _overviewAmount(
                      'Daily Limit',
                      dailyBudget,
                      color: context.appColors.primaryText,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    _overviewAmount(
                      'Today',
                      dailyExpenses,
                      color: Colors.red,
                      icon: Icons.arrow_upward,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daily Limit Used',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Remaining: ${formatPeso(remainingBudget)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: budgetUsedColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${(budgetUsed * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: budgetUsedColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: budgetUsed,
                    minHeight: 8,
                    backgroundColor: context.appColors.track,
                    color: primaryBlue,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final saved = await showAddIncomeDialog(context);
                          if (saved && mounted) setState(() {});
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Income'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showAddBudgetDialog(dailyBudget),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Budget'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryBlue,
                          side: const BorderSide(color: primaryBlue),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openBudgets,
                    icon: const Icon(Icons.category_outlined, size: 16),
                    label: const Text('Manage Category Budgets'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryBlue,
                      side: const BorderSide(color: primaryBlue),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddBudgetDialog(double currentBudget) async {
    final amountController = TextEditingController();
    var isSaving = false;
    var budgetUpdateMode = 'Replace daily limit';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Current daily limit: ${formatPeso(currentBudget)}',
                style: const TextStyle(color: Colors.grey),
              ),
              TextField(
                controller: amountController,
                enabled: !isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Daily limit amount',
                  prefixText: '₱',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: budgetUpdateMode,
                decoration: const InputDecoration(
                  labelText: 'Daily limit action',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Replace daily limit',
                    child: Text('Replace daily limit'),
                  ),
                  DropdownMenuItem(
                    value: 'Add to daily limit',
                    child: Text('Add to daily limit'),
                  ),
                ],
                onChanged: isSaving
                    ? null
                    : (value) => setDialogState(
                        () => budgetUpdateMode = value ?? budgetUpdateMode,
                      ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final amount = double.tryParse(
                        amountController.text.trim().replaceAll(',', ''),
                      );
                      if (amount == null || amount <= 0) {
                        _showMessage('Enter a valid positive budget amount.');
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        final updatedBudget =
                            budgetUpdateMode == 'Add to daily limit'
                            ? currentBudget + amount
                            : amount;
                        await UserProfileService.updateBudget(updatedBudget);
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        setState(() {});
                      } catch (_) {
                        setDialogState(() => isSaving = false);
                        _showMessage('Budget could not be saved.');
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _overviewAmount(
    String label,
    double amount, {
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 16, child: Icon(icon, size: 14, color: color)),
            SizedBox(
              height: 28,
              width: double.infinity,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 4),
            MoneyText(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
