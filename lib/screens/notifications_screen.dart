import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color primaryBlue = Color(0xFF1976D2);
  final User? _user = FirebaseAuth.instance.currentUser;
  final Set<String> _readNotificationIds = {};

  @override
  void initState() {
    super.initState();
    UserProfileService.markNotificationsSeen();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _expenseStream {
    if (_user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .collection('expenses')
        .orderBy('date', descending: true)
        .limit(20)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _budgetStream {
    if (_user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .collection('categoryBudgets')
        .snapshots();
  }

  DateTime _periodStart(DateTime now, String period) {
    final date = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'weekly':
        return date.subtract(Duration(days: date.weekday - DateTime.monday));
      case 'monthly':
        return DateTime(now.year, now.month);
      default:
        return date;
    }
  }

  DateTime _periodEnd(DateTime start, String period) {
    switch (period) {
      case 'weekly':
        return start.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(start.year, start.month + 1);
      default:
        return start.add(const Duration(days: 1));
    }
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'weekly':
        return 'this week';
      case 'monthly':
        return 'this month';
      default:
        return 'today';
    }
  }

  String _formatMoney(double amount) => '₱${amount.toStringAsFixed(2)}';

  List<_AppNotification> _buildNotifications(
    QuerySnapshot<Map<String, dynamic>> expensesSnapshot,
    QuerySnapshot<Map<String, dynamic>> budgetsSnapshot,
  ) {
    final expenses = expensesSnapshot.docs;
    final notifications = <_AppNotification>[];
    final now = DateTime.now();

    for (final budgetDocument in budgetsSnapshot.docs) {
      final budget = budgetDocument.data();
      final category = budget['category']?.toString() ?? 'Category';
      final categoryKey = category.toLowerCase();
      final period = budget['period']?.toString() ?? 'daily';
      final limit = (budget['amount'] as num?)?.toDouble() ?? 0;
      final start = _periodStart(now, period);
      final end = _periodEnd(start, period);
      final spent = expenses.fold<double>(0, (total, expenseDocument) {
        final expense = expenseDocument.data();
        final date = (expense['date'] as Timestamp?)?.toDate();
        if (date == null ||
            expense['category']?.toString().toLowerCase() != categoryKey ||
            date.isBefore(start) ||
            !date.isBefore(end)) {
          return total;
        }
        return total + ((expense['amount'] as num?)?.toDouble() ?? 0);
      });

      if (limit <= 0 || spent < limit * 0.75) continue;
      final exceeded = spent >= limit;
      notifications.add(
        _AppNotification(
          id: 'budget_${budgetDocument.id}_${start.toIso8601String()}',
          icon: exceeded
              ? Icons.warning_amber_rounded
              : Icons.notifications_active_outlined,
          title: exceeded
              ? '$category budget exceeded'
              : '$category budget alert',
          message: exceeded
              ? 'You spent ${_formatMoney(spent)} against your ${_periodLabel(period)} limit of ${_formatMoney(limit)}.'
              : 'You have used ${_formatMoney(spent)} of your ${_periodLabel(period)} ${category.toLowerCase()} budget.',
          time: now,
          color: exceeded ? Colors.red : Colors.orange,
        ),
      );
    }

    for (final expenseDocument in expenses.take(10)) {
      final expense = expenseDocument.data();
      final date = (expense['date'] as Timestamp?)?.toDate();
      if (date == null) continue;
      final category = expense['category']?.toString() ?? 'Other';
      final amount = (expense['amount'] as num?)?.toDouble() ?? 0;
      notifications.add(
        _AppNotification(
          id: 'expense_${expenseDocument.id}',
          icon: Icons.check_circle_outline,
          title: 'Expense recorded',
          message:
              '${_formatMoney(amount)} spent on ${category.toLowerCase()}.',
          time: date,
          color: Colors.green,
        ),
      );
    }

    notifications.sort((a, b) => b.time.compareTo(a.time));
    return notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () async {
              setState(() => _readNotificationIds.add('all'));
              await UserProfileService.markNotificationsSeen();
            },
            child: const Text(
              'Mark all read',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _expenseStream,
        builder: (context, expenseSnapshot) {
          if (expenseSnapshot.hasError) {
            return const Center(child: Text('Could not load notifications.'));
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _budgetStream,
            builder: (context, budgetSnapshot) {
              if (budgetSnapshot.hasError) {
                return const Center(
                  child: Text('Could not load notifications.'),
                );
              }
              if (expenseSnapshot.connectionState == ConnectionState.waiting ||
                  budgetSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final notifications = _buildNotifications(
                expenseSnapshot.data!,
                budgetSnapshot.data!,
              );
              if (notifications.isEmpty) {
                return const Center(
                  child: Text(
                    'You are all caught up.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  final isRead =
                      _readNotificationIds.contains('all') ||
                      _readNotificationIds.contains(notification.id);
                  return _NotificationTile(
                    notification: notification,
                    isRead: isRead,
                    onTap: () => setState(
                      () => _readNotificationIds.add(notification.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AppNotification {
  const _AppNotification({
    required this.id,
    required this.icon,
    required this.title,
    required this.message,
    required this.time,
    required this.color,
  });

  final String id;
  final IconData icon;
  final String title;
  final String message;
  final DateTime time;
  final Color color;
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.isRead,
    required this.onTap,
  });

  final _AppNotification notification;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFFEAF3FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(notification.icon, color: notification.color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    notification.message,
                    style: const TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatNotificationTime(notification.time),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNotificationTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays == 1) return 'Yesterday';
    return '${time.day}/${time.month}/${time.year}';
  }
}
