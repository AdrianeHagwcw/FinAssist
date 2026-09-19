import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/goal.dart';
import '../models/onboarding_data.dart';
import '../models/reminder.dart';
import 'allocation_service.dart';
import 'bill_service.dart';
import 'budget_service.dart';
import 'firestore_write.dart';
import 'goal_service.dart';
import 'reminder_service.dart';
import 'user_profile_service.dart';
import 'wallet_service.dart';

/// Saves the user's reminder choices on their profile.
class ReminderSettingsService {
  static DocumentReference<Map<String, dynamic>> get _profile {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  static void _save(Map<String, dynamic> reminders, String label) {
    commitFirestoreWrite(
      _profile.set({
        'reminders': reminders,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      label,
    );
  }

  /// Every reminder on or off. Onboarding's answer is kept in step, so the
  /// two never disagree.
  static void setEnabled(bool enabled) {
    commitFirestoreWrite(
      _profile.set({
        'notificationsEnabled': enabled,
        'reminders': {'enabled': enabled},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'turn reminders ${enabled ? 'on' : 'off'}',
    );
  }

  /// Switches one reminder by hand, or hands it back to the priorities when
  /// [on] is null.
  static void setKind(ReminderKind kind, bool? on) {
    _save({kind.name: on ?? FieldValue.delete()}, 'set ${kind.name} reminder');
  }

  /// How many days before a bill to remind, or null for the suggestion.
  static void setBillLeadDays(int? days) {
    _save({
      'billLeadDays': days ?? FieldValue.delete(),
    }, 'set bill reminder timing');
  }

  static void setPriorities(List<FinancialPriority> priorities) {
    commitFirestoreWrite(
      _profile.set({
        'priorities': [for (final priority in priorities) priority.name],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'reorder priorities',
    );
  }
}

/// Keeps the scheduled reminders in step with the user's data.
///
/// Listens to everything a reminder depends on and plans them again shortly
/// after any of it changes, so paying a bill or changing a setting updates
/// what is scheduled without the user doing anything.
class ReminderScheduler {
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _debounce;
  bool _running = false;

  Map<String, dynamic>? _profile;
  List<Goal> _goals = const [];
  List<AllocationCycle> _cycles = const [];
  List<AppTransaction> _transactions = const [];

  void start() {
    if (_running) return;
    _running = true;

    void listen<T>(Stream<T> stream, void Function(T value) onData) {
      _subscriptions.add(
        stream.listen((value) {
          onData(value);
          refresh();
        }, onError: (Object _) {}),
      );
    }

    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1);

    listen(UserProfileService.watchProfile(), (s) => _profile = s.data());
    listen(GoalService.watchGoals(), (goals) => _goals = goals);
    listen(BudgetService.watchRecentCycles(), (cycles) => _cycles = cycles);
    listen(WalletService.watchTransactions(), (t) => _transactions = t);
    // Adding, editing or skipping a bill doesn't make a transaction.
    listen(BillService.watchBills(), (_) {});
    listen(BillService.watchInstances(now.year, now.month), (_) {});
    listen(BillService.watchInstances(next.year, next.month), (_) {});
  }

  /// Plans again soon. Several changes close together plan only once.
  void refresh() {
    if (!_running) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _plan);
  }

  Future<void> _plan() async {
    final profile = _profile;
    if (profile == null) return;

    final now = DateTime.now();
    final settings = ReminderSettings.fromProfile(profile);

    try {
      final bills = settings.enabled
          ? await AllocationService.loadOutstandingBills(now: now)
          : const <Never>[];

      final planned = planReminders(
        settings: settings,
        bills: bills,
        goals: _goals,
        cycles: _cycles,
        incomeFrequency: profile['incomeFrequency'] as String?,
        incomeSource: profile['incomeSource'] as String?,
        transactions: _transactions,
        now: now,
      );
      await ReminderService.schedule(planned);
      debugPrint('Reminders scheduled: ${planned.length}');
    } catch (_) {
      // Offline with nothing cached: keep what was scheduled last time.
    }
  }

  void stop() {
    _running = false;
    _debounce?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
