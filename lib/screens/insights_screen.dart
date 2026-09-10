import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;

  static const _primaryBlue = Color(0xFF1976D2);
  static const _pageBackground = Color(0xFFF6F8FC);

  // ------------------------------------------------------------
  // CATEGORY COLORS
  // ------------------------------------------------------------

  Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Colors.orange;

      case 'transportation':
      case 'transport':
        return Colors.blue;

      case 'shopping':
        return Colors.purple;

      case 'bills':
      case 'utilities':
        return Colors.red;

      case 'entertainment':
        return Colors.pink;

      case 'health':
        return Colors.green;

      case 'education':
        return Colors.indigo;

      case 'other':
        return Colors.grey;

      default:
        return Colors.teal;
    }
  }

  // ------------------------------------------------------------
  // CATEGORY ICONS
  // ------------------------------------------------------------

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;

      case 'transportation':
      case 'transport':
        return Icons.directions_car;

      case 'shopping':
        return Icons.shopping_bag;

      case 'bills':
      case 'utilities':
        return Icons.receipt_long;

      case 'entertainment':
        return Icons.movie;

      case 'health':
        return Icons.health_and_safety;

      case 'education':
        return Icons.school;

      case 'other':
        return Icons.category;

      default:
        return Icons.attach_money;
    }
  }

  // ------------------------------------------------------------
  // FIRESTORE STREAM
  // ------------------------------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> _expenseStream() {
    if (_user == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,

      appBar: AppBar(
        title: const Text(
          'Financial Insights',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _expenseStream(),

        builder: (context, snapshot) {
          // ------------------------------------------------------
          // LOADING
          // ------------------------------------------------------

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _primaryBlue),
            );
          }

          // ------------------------------------------------------
          // ERROR
          // ------------------------------------------------------

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 55,
                      color: Colors.redAccent,
                    ),

                    const SizedBox(height: 15),

                    const Text(
                      'Unable to load insights',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          final documents = snapshot.data?.docs ?? [];

          // ------------------------------------------------------
          // EMPTY STATE
          // ------------------------------------------------------

          if (documents.isEmpty) {
            return _buildEmptyState();
          }

          // ------------------------------------------------------
          // CALCULATE DATA
          // ------------------------------------------------------

          final analysis = _calculateInsights(documents);

          // ------------------------------------------------------
          // MAIN CONTENT
          // ------------------------------------------------------

          return RefreshIndicator(
            color: _primaryBlue,

            onRefresh: () async {
              setState(() {});
            },

            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),

              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  // ==================================================
                  // FINANCIAL HEALTH SCORE
                  // ==================================================
                  _buildHealthScoreCard(analysis),

                  const SizedBox(height: 20),

                  // ==================================================
                  // SUMMARY CARDS
                  // ==================================================
                  _buildSummarySection(analysis),

                  const SizedBox(height: 25),

                  // ==================================================
                  // SPENDING TREND
                  // ==================================================
                  _buildSectionTitle('Spending Trend'),

                  const SizedBox(height: 10),

                  _buildSpendingTrend(documents),

                  const SizedBox(height: 25),

                  // ==================================================
                  // TOP CATEGORY
                  // ==================================================
                  _buildSectionTitle('Top Spending Category'),

                  const SizedBox(height: 10),

                  _buildTopCategoryCard(analysis),

                  const SizedBox(height: 25),

                  // ==================================================
                  // CATEGORY BREAKDOWN
                  // ==================================================
                  _buildSectionTitle('Category Breakdown'),

                  const SizedBox(height: 10),

                  _buildCategoryBreakdown(analysis),

                  const SizedBox(height: 25),

                  // ==================================================
                  // AI FINANCIAL INSIGHT
                  // ==================================================
                  _buildSectionTitle('AI Financial Insights'),

                  const SizedBox(height: 10),

                  _buildAIInsights(analysis),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // CALCULATE INSIGHTS
  // ============================================================

  Map<String, dynamic> _calculateInsights(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    double totalExpenses = 0;

    final Map<String, double> categoryTotals = {};

    // ------------------------------------------------------------
    // PROCESS EXPENSES
    // ------------------------------------------------------------

    for (final document in documents) {
      final data = document.data();

      final amount = (data['amount'] as num?)?.toDouble() ?? 0;

      final category = data['category']?.toString() ?? 'Other';

      totalExpenses += amount;

      categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
    }

    // ------------------------------------------------------------
    // SORT CATEGORIES
    // ------------------------------------------------------------

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ------------------------------------------------------------
    // TOP CATEGORY
    // ------------------------------------------------------------

    String topCategory = 'None';

    double topCategoryAmount = 0;

    if (sortedCategories.isNotEmpty) {
      topCategory = sortedCategories.first.key;

      topCategoryAmount = sortedCategories.first.value;
    }

    // ------------------------------------------------------------
    // AVERAGE EXPENSE
    // ------------------------------------------------------------

    final averageExpense = documents.isNotEmpty
        ? totalExpenses / documents.length
        : 0.0;

    // ------------------------------------------------------------
    // TOP CATEGORY PERCENTAGE
    // ------------------------------------------------------------

    final topCategoryPercentage = totalExpenses > 0
        ? (topCategoryAmount / totalExpenses) * 100
        : 0.0;

    // ------------------------------------------------------------
    // HEALTH SCORE
    // ------------------------------------------------------------

    final healthScore = _calculateHealthScore(
      documents,
      totalExpenses,
      categoryTotals,
    );

    return {
      'totalExpenses': totalExpenses,
      'transactionCount': documents.length,
      'averageExpense': averageExpense,
      'categoryTotals': categoryTotals,
      'sortedCategories': sortedCategories,
      'topCategory': topCategory,
      'topCategoryAmount': topCategoryAmount,
      'topCategoryPercentage': topCategoryPercentage,
      'healthScore': healthScore,
    };
  }

  // ============================================================
  // FINANCIAL HEALTH SCORE
  // ============================================================

  int _calculateHealthScore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,

    double totalExpenses,

    Map<String, double> categoryTotals,
  ) {
    if (documents.isEmpty) {
      return 0;
    }

    double score = 100;

    // ------------------------------------------------------------
    // FACTOR 1:
    // Large individual expenses
    // ------------------------------------------------------------

    final averageExpense = totalExpenses / documents.length;

    int largeExpenses = 0;

    for (final document in documents) {
      final amount = (document.data()['amount'] as num?)?.toDouble() ?? 0;

      if (amount > averageExpense * 2) {
        largeExpenses++;
      }
    }

    if (largeExpenses >= 5) {
      score -= 15;
    } else if (largeExpenses >= 3) {
      score -= 10;
    } else if (largeExpenses >= 1) {
      score -= 5;
    }

    // ------------------------------------------------------------
    // FACTOR 2:
    // Spending concentration
    // ------------------------------------------------------------

    if (totalExpenses > 0 && categoryTotals.isNotEmpty) {
      final highestCategory = categoryTotals.values.reduce(
        (a, b) => a > b ? a : b,
      );

      final concentration = highestCategory / totalExpenses;

      if (concentration >= 0.70) {
        score -= 15;
      } else if (concentration >= 0.55) {
        score -= 10;
      } else if (concentration >= 0.40) {
        score -= 5;
      }
    }

    // ------------------------------------------------------------
    // FACTOR 3:
    // Transaction frequency
    // ------------------------------------------------------------

    if (documents.length >= 100) {
      score -= 10;
    } else if (documents.length >= 50) {
      score -= 5;
    }

    // ------------------------------------------------------------
    // KEEP SCORE BETWEEN 0 AND 100
    // ------------------------------------------------------------

    if (score < 0) {
      score = 0;
    }

    if (score > 100) {
      score = 100;
    }

    return score.round();
  }

  // ============================================================
  // HEALTH SCORE CARD
  // ============================================================

  Widget _buildHealthScoreCard(Map<String, dynamic> analysis) {
    final int score = analysis['healthScore'] as int;

    String status;

    IconData statusIcon;

    if (score >= 80) {
      status = 'Excellent';
      statusIcon = Icons.sentiment_very_satisfied;
    } else if (score >= 60) {
      status = 'Good';
      statusIcon = Icons.sentiment_satisfied;
    } else if (score >= 40) {
      status = 'Needs Attention';
      statusIcon = Icons.sentiment_neutral;
    } else {
      status = 'Needs Improvement';
      statusIcon = Icons.sentiment_dissatisfied;
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        color: _primaryBlue,

        borderRadius: BorderRadius.circular(20),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),

            blurRadius: 12,

            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: Column(
        children: [
          const Text(
            'Financial Health Score',

            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),

          const SizedBox(height: 12),

          Stack(
            alignment: Alignment.center,

            children: [
              SizedBox(
                width: 150,
                height: 150,

                child: CircularProgressIndicator(
                  value: score / 100,

                  strokeWidth: 12,

                  backgroundColor: Colors.white24,

                  color: Colors.white,
                ),
              ),

              Column(
                children: [
                  Text(
                    '$score',

                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const Text(
                    '/ 100',

                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 15),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              Icon(statusIcon, color: Colors.white, size: 23),

              const SizedBox(width: 8),

              Text(
                status,

                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          const Text(
            'Based on your recorded spending activity',

            textAlign: TextAlign.center,

            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY SECTION
  // ============================================================

  Widget _buildSummarySection(Map<String, dynamic> analysis) {
    final total = analysis['totalExpenses'] as double;

    final average = analysis['averageExpense'] as double;

    final count = analysis['transactionCount'] as int;

    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            icon: Icons.payments_outlined,
            title: 'Total Spending',
            value: '₱${total.toStringAsFixed(2)}',
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: _summaryCard(
            icon: Icons.receipt_long_outlined,
            title: 'Transactions',
            value: '$count',
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: _summaryCard(
            icon: Icons.analytics_outlined,
            title: 'Average',
            value: '₱${average.toStringAsFixed(0)}',
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SUMMARY CARD
  // ============================================================

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      height: 125,

      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),

            blurRadius: 8,

            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,

        children: [
          Icon(icon, color: _primaryBlue, size: 27),

          const SizedBox(height: 8),

          Text(
            title,

            textAlign: TextAlign.center,

            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),

          const SizedBox(height: 4),

          Text(
            value,

            textAlign: TextAlign.center,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: const TextStyle(
              color: _primaryBlue,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SPENDING TREND
  // ============================================================

  Widget _buildSpendingTrend(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final now = DateTime.now();

    double thisWeek = 0;
    double lastWeek = 0;

    for (final document in documents) {
      final data = document.data();

      final amount = (data['amount'] as num?)?.toDouble() ?? 0;

      final timestamp = data['date'] as Timestamp?;

      if (timestamp == null) {
        continue;
      }

      final date = timestamp.toDate();

      final difference = now.difference(date).inDays;

      if (difference >= 0 && difference < 7) {
        thisWeek += amount;
      } else if (difference >= 7 && difference < 14) {
        lastWeek += amount;
      }
    }

    String comparisonText;

    IconData comparisonIcon;

    if (lastWeek == 0 && thisWeek > 0) {
      comparisonText = 'No previous week data available for comparison.';

      comparisonIcon = Icons.info_outline;
    } else if (lastWeek == 0 && thisWeek == 0) {
      comparisonText = 'No spending recorded during the last two weeks.';

      comparisonIcon = Icons.info_outline;
    } else {
      final difference = thisWeek - lastWeek;

      final percentage = lastWeek > 0 ? (difference / lastWeek) * 100 : 0;

      if (difference > 0) {
        comparisonText =
            'Spending is ${percentage.abs().toStringAsFixed(1)}% higher than last week.';

        comparisonIcon = Icons.trending_up;
      } else if (difference < 0) {
        comparisonText =
            'Spending is ${percentage.abs().toStringAsFixed(1)}% lower than last week.';

        comparisonIcon = Icons.trending_down;
      } else {
        comparisonText = 'Spending is the same as last week.';

        comparisonIcon = Icons.trending_flat;
      }
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),

            blurRadius: 8,

            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Expanded(child: _trendAmount('This Week', thisWeek)),

              Container(width: 1, height: 45, color: Colors.grey.shade300),

              Expanded(child: _trendAmount('Last Week', lastWeek)),
            ],
          ),

          const SizedBox(height: 18),

          Container(
            width: double.infinity,

            padding: const EdgeInsets.all(12),

            decoration: BoxDecoration(
              color: _primaryBlue.withValues(alpha: 0.07),

              borderRadius: BorderRadius.circular(12),
            ),

            child: Row(
              children: [
                Icon(comparisonIcon, color: _primaryBlue, size: 22),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    comparisonText,

                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TREND AMOUNT
  // ============================================================

  Widget _trendAmount(String title, double amount) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),

        const SizedBox(height: 5),

        Text(
          '₱${amount.toStringAsFixed(2)}',

          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: _primaryBlue,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TOP CATEGORY CARD
  // ============================================================

  Widget _buildTopCategoryCard(Map<String, dynamic> analysis) {
    final category = analysis['topCategory'] as String;

    final amount = analysis['topCategoryAmount'] as double;

    final percentage = analysis['topCategoryPercentage'] as double;

    if (category == 'None') {
      return _simpleMessageCard('No category data available yet.');
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),

            blurRadius: 8,

            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Row(
        children: [
          Container(
            width: 55,
            height: 55,

            decoration: BoxDecoration(
              color: _categoryColor(category).withValues(alpha: 0.12),

              borderRadius: BorderRadius.circular(15),
            ),

            child: Icon(
              _categoryIcon(category),

              color: _categoryColor(category),

              size: 28,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                const Text(
                  'Highest spending category',

                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),

                const SizedBox(height: 4),

                Text(
                  category,

                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '₱${amount.toStringAsFixed(2)} • ${percentage.toStringAsFixed(1)}% of total spending',

                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CATEGORY BREAKDOWN
  // ============================================================

  Widget _buildCategoryBreakdown(Map<String, dynamic> analysis) {
    final categories =
        analysis['sortedCategories'] as List<MapEntry<String, double>>;

    final total = analysis['totalExpenses'] as double;

    if (categories.isEmpty) {
      return _simpleMessageCard('No category data available yet.');
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),

            blurRadius: 8,

            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        children: categories.map((entry) {
          final percentage = total > 0 ? (entry.value / total) * 100 : 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 18),

            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 35,
                      height: 35,

                      decoration: BoxDecoration(
                        color: _categoryColor(
                          entry.key,
                        ).withValues(alpha: 0.12),

                        borderRadius: BorderRadius.circular(10),
                      ),

                      child: Icon(
                        _categoryIcon(entry.key),

                        size: 18,

                        color: _categoryColor(entry.key),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        entry.key,

                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    Text(
                      '₱${entry.value.toStringAsFixed(2)}',

                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(width: 8),

                    Text(
                      '${percentage.toStringAsFixed(1)}%',

                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                ClipRRect(
                  borderRadius: BorderRadius.circular(10),

                  child: LinearProgressIndicator(
                    value: percentage / 100,

                    minHeight: 7,

                    backgroundColor: Colors.grey.shade200,

                    color: _categoryColor(entry.key),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================
  // AI INSIGHTS
  // ============================================================

  Widget _buildAIInsights(Map<String, dynamic> analysis) {
    final total = analysis['totalExpenses'] as double;

    final category = analysis['topCategory'] as String;

    final percentage = analysis['topCategoryPercentage'] as double;

    final count = analysis['transactionCount'] as int;

    final List<String> insights = [];

    // ------------------------------------------------------------
    // INSIGHT 1
    // ------------------------------------------------------------

    if (category != 'None') {
      if (percentage >= 50) {
        insights.add(
          '$category accounts for ${percentage.toStringAsFixed(1)}% of your recorded spending. Consider monitoring this category closely.',
        );
      } else {
        insights.add(
          '$category is your largest spending category at ${percentage.toStringAsFixed(1)}% of your total expenses.',
        );
      }
    }

    // ------------------------------------------------------------
    // INSIGHT 2
    // ------------------------------------------------------------

    if (count > 0) {
      final average = total / count;

      insights.add(
        'Your average recorded expense is ₱${average.toStringAsFixed(2)}.',
      );
    }

    // ------------------------------------------------------------
    // INSIGHT 3
    // ------------------------------------------------------------

    if (count >= 50) {
      insights.add(
        'You have recorded many transactions. Reviewing your expenses regularly can help you identify recurring spending patterns.',
      );
    } else if (count >= 10) {
      insights.add(
        'You have enough recorded transactions to start identifying useful spending patterns.',
      );
    } else {
      insights.add(
        'Continue recording your expenses so FinAssist can provide more meaningful spending insights.',
      );
    }

    return Column(
      children: insights.map((insight) {
        return Container(
          width: double.infinity,

          margin: const EdgeInsets.only(bottom: 10),

          padding: const EdgeInsets.all(16),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(16),

            border: Border.all(color: _primaryBlue.withValues(alpha: 0.12)),
          ),

          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Container(
                width: 35,
                height: 35,

                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.10),

                  shape: BoxShape.circle,
                ),

                child: const Icon(
                  Icons.auto_awesome,
                  color: _primaryBlue,
                  size: 18,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  insight,

                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _buildSectionTitle(String title) {
    return Text(
      title,

      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF222222),
      ),
    );
  }

  // ============================================================
  // SIMPLE MESSAGE CARD
  // ============================================================

  Widget _simpleMessageCard(String message) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),
      ),

      child: Text(
        message,

        textAlign: TextAlign.center,

        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 100,
              height: 100,

              decoration: BoxDecoration(
                color: _primaryBlue.withValues(alpha: 0.10),

                shape: BoxShape.circle,
              ),

              child: const Icon(
                Icons.insights_outlined,

                color: _primaryBlue,

                size: 50,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'No Insights Yet',

              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            const Text(
              'Start adding your expenses and FinAssist will analyze your spending patterns and provide financial insights.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
