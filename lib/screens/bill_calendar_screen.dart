import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bill.dart';
import '../models/goal.dart';
import '../providers/app_settings_provider.dart';
import '../models/wallet.dart';
import '../services/bill_service.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/add_button.dart';
import '../widgets/back_to_home.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'bill_detail_screen.dart';
import '../widgets/bill_form_sheet.dart';
import '../widgets/bill_status_badge.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/money_text.dart';
import 'debts_screen.dart';

const List<String> _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Month view of every bill by due date, and where bills are added or edited.
class BillCalendarScreen extends StatefulWidget {
  const BillCalendarScreen({
    this.bills,
    this.instancesFor,
    this.ensureInstances,
    this.today,
    this.initialShowDebts = false,
    this.wallets,
    this.goals,
    super.key,
  });

  /// Replaces the live bill schedules. Used by tests.
  final Stream<List<Bill>>? bills;

  /// Replaces the live occurrences for a month. Used by tests.
  final Stream<List<BillInstance>> Function(int year, int month)? instancesFor;

  /// Fills in a month's missing occurrences. Used by tests.
  final Future<void> Function(List<Bill> bills, int year, int month)?
  ensureInstances;

  /// Injectable so tests don't depend on the clock.
  final DateTime? today;

  /// Opens the combined Bills and Debts page on the debt list.
  final bool initialShowDebts;

  /// Replace the live wallets and goals, for whether this month's bills are
  /// covered. Used by tests.
  final Stream<List<Wallet>>? wallets;
  final Stream<List<Goal>>? goals;

  @override
  State<BillCalendarScreen> createState() => _BillCalendarScreenState();
}

class _BillCalendarScreenState extends State<BillCalendarScreen> {
  late final DateTime _today = _dateOnly(widget.today ?? DateTime.now());
  late final Stream<List<Bill>> _bills =
      widget.bills ?? BillService.watchBills();

  // A test that hands in its bills has no Firebase behind the rest.
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ??
      (widget.bills == null
          ? WalletService.watchWallets()
          : const Stream<List<Wallet>>.empty());
  late final Stream<List<Goal>> _goals =
      widget.goals ??
      (widget.bills == null
          ? GoalService.watchGoals()
          : const Stream<List<Goal>>.empty());

  late DateTime _month = DateTime(_today.year, _today.month);
  late DateTime? _selectedDay = _today;

  bool _showAsList = false;

  /// Set once when the screen opens. Which side you are on is decided by
  /// how you got here, not by a control on the screen.
  late final bool _showDebts = widget.initialShowDebts;

  /// Months already filled in, so scrolling back and forth doesn't ask
  /// Firestore to do the same work over and over.
  final Set<String> _filledMonths = {};

  Stream<List<BillInstance>> _instances(int year, int month) {
    return (widget.instancesFor ?? BillService.watchInstances)(year, month);
  }

  /// Creates whatever occurrences this month is missing, once per month.
  void _fillMonth(List<Bill> bills) {
    final key = '${_month.year}-${_month.month}';

    if (bills.isEmpty || _filledMonths.contains(key)) return;

    _filledMonths.add(key);

    final fill =
        widget.ensureInstances ??
        (bills, year, month) =>
            BillService.ensureInstances(bills: bills, year: year, month: month);

    // Firestore is not asked to write anything during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fill(bills, _month.year, _month.month);
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      // Land on today when it's in view, otherwise show the whole month.
      _selectedDay = _month.year == _today.year && _month.month == _today.month
          ? _today
          : null;
    });
  }

  Future<void> _addBill() async {
    final saved = await showBillFormSheet(context);

    // A new bill may fall due in the month on screen, so let it be filled in
    // again.
    if (saved) setState(() => _filledMonths.clear());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: Text(
          _showDebts ? 'Installments' : 'Bill Planner',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        // As a tab it goes back to Home; opened from Home's Quick Actions it
        // keeps the usual back arrow.
        leading: backToHomeButton(context),
        actions: _showDebts
            ? const []
            : [
                IconButton(
                  tooltip: _showAsList ? 'Show calendar' : 'Show list',
                  icon: Icon(
                    _showAsList ? Icons.calendar_month : Icons.view_list,
                  ),
                  onPressed: () => setState(() => _showAsList = !_showAsList),
                ),
              ],
      ),
      // No toggle: Quick Actions already opens Bill Planner and Debts
      // separately, and the title says which one you are on.
      body: _showDebts ? const DebtsView() : _buildBills(),
    );
  }

  Widget _buildBills() => StreamBuilder<List<Bill>>(
    stream: _bills,
    builder: (context, billsSnapshot) {
      final bills = billsSnapshot.data ?? const <Bill>[];
      _fillMonth(bills);

      return StreamBuilder<List<BillInstance>>(
        stream: _instances(_month.year, _month.month),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _BillsError();
          }

          final instances = snapshot.data ?? const <BillInstance>[];

          if (bills.isEmpty && instances.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 30, bottom: 10),
                  child: EmptyStateView(
                    iconAsset: 'assets/icons/icons8-calendar-96.png',
                    title: 'No bills yet',
                    message:
                        'Add the things you pay on a schedule — rent, '
                        'tuition, load — and they will show up here on their '
                        'due dates.',
                  ),
                ),
                const SizedBox(height: 4),
                AddButton(label: 'Add Bill', onPressed: _addBill),
              ],
            );
          }

          return Column(
            children: [
              _MonthHeader(
                month: _month,
                onPrevious: () => _changeMonth(-1),
                onNext: () => _changeMonth(1),
              ),
              // Whether what is free to spend covers what this month still
              // owes. Only for the month being lived in.
              StreamBuilder<List<Wallet>>(
                stream: _wallets,
                builder: (context, walletSnapshot) => StreamBuilder<List<Goal>>(
                  stream: _goals,
                  builder: (context, goalSnapshot) {
                    final wallets = walletSnapshot.data;
                    final isThisMonth =
                        _month.year == _today.year &&
                        _month.month == _today.month;
                    return _MonthSummary(
                      instances: instances,
                      today: _today,
                      available: wallets == null || !isThisMonth
                          ? null
                          : availableBalance(
                              wallets,
                              goalSnapshot.data ?? const [],
                            ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _showAsList
                    ? _BillList(
                        instances: instances,
                        today: _today,
                        onAdd: _addBill,
                      )
                    : _CalendarAndDay(
                        month: _month,
                        today: _today,
                        selectedDay: _selectedDay,
                        instances: instances,
                        onSelectDay: (day) =>
                            setState(() => _selectedDay = day),
                        onAdd: _addBill,
                      ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrevious,
          ),
          Text(
            '${_monthNames[month.month - 1]} ${month.year}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: context.appColors.textPrimary,
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// What this month costs, how much of it is still hanging over the user,
/// and whether the money free to spend covers it.
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({
    required this.instances,
    required this.today,
    this.available,
  });

  final List<BillInstance> instances;
  final DateTime today;

  /// The Available Balance, or null when it is not compared, as for a month
  /// other than this one.
  final double? available;

  @override
  Widget build(BuildContext context) {
    if (instances.isEmpty) return const SizedBox.shrink();

    final total = instances.fold<double>(
      0,
      (sum, instance) => sum + instance.amount,
    );
    final unpaid = instances
        .where((instance) => instance.status != BillStatus.skipped)
        .fold<double>(0, (sum, instance) => sum + instance.remaining);
    final overdue = instances
        .where(
          (instance) => instance.urgency(now: today) == BillUrgency.overdue,
        )
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SummaryFigure(label: 'Due this month', amount: total),
              Container(
                width: 1,
                height: 34,
                color: context.appColors.border,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              _SummaryFigure(
                label: overdue > 0
                    ? 'Still owing ($overdue overdue)'
                    : 'Still owing',
                amount: unpaid,
                color: overdue > 0 ? Colors.red : null,
              ),
            ],
          ),
          if (available != null && unpaid > 0.005) ...[
            Divider(height: 20, color: context.appColors.border),
            _Coverage(owing: unpaid, available: available!),
          ],
        ],
      ),
    );
  }
}

/// "Covered" or "Short by", against the money free to spend, so the user
/// sees whether this month's bills can be paid without checking each wallet.
class _Coverage extends StatelessWidget {
  const _Coverage({required this.owing, required this.available});

  final double owing;
  final double available;

  @override
  Widget build(BuildContext context) {
    final short = owing - available;
    final covered = short <= 0.005;
    // Hidden amounts stay hidden here too.
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );
    String peso(double amount) => formatPeso(amount, masked: masked);
    final color = covered ? confirmColorOn(context) : dangerColorOn(context);

    return Row(
      key: const Key('bills-coverage'),
      children: [
        Icon(
          covered ? Icons.check_circle_outline : Icons.error_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            covered
                ? 'Covered · ${peso(available)} available'
                : 'Short by ${peso(short)} · ${peso(available)} available',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryFigure extends StatelessWidget {
  const _SummaryFigure({required this.label, required this.amount, this.color});

  final String label;
  final double amount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.appColors.textMuted),
          ),
          const SizedBox(height: 4),
          MoneyText(
            amount,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: color ?? context.appColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarAndDay extends StatelessWidget {
  const _CalendarAndDay({
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.instances,
    required this.onSelectDay,
    required this.onAdd,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selectedDay;
  final List<BillInstance> instances;
  final ValueChanged<DateTime?> onSelectDay;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final shown = selectedDay == null
        ? instances
        : instances
              .where((instance) => _isSameDay(instance.dueDate, selectedDay!))
              .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      children: [
        _MonthGrid(
          month: month,
          today: today,
          selectedDay: selectedDay,
          instances: instances,
          onSelectDay: onSelectDay,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                selectedDay == null
                    ? 'All bills this month'
                    : formatShortDate(selectedDay!),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.appColors.textPrimary,
                ),
              ),
            ),
            if (selectedDay != null)
              TextButton(
                onPressed: () => onSelectDay(null),
                child: const Text('Show all'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              selectedDay == null
                  ? 'Nothing due this month.'
                  : 'Nothing due on this day.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textMuted),
            ),
          )
        else
          for (final instance in shown) ...[
            _BillRow(instance: instance, today: today),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 4),
        AddButton(label: 'Add Bill', onPressed: onAdd),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.instances,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selectedDay;
  final List<BillInstance> instances;
  final ValueChanged<DateTime?> onSelectDay;

  /// The one colour a day should wear: whichever of its bills is most
  /// pressing. An overdue bill outranks a paid one, so a day holding both
  /// still reads red.
  BillUrgency? _urgencyFor(DateTime day) {
    BillUrgency? worst;

    for (final instance in instances) {
      if (!_isSameDay(instance.dueDate, day)) continue;

      worst = _moreUrgent(worst, instance.urgency(now: today));
    }

    return worst;
  }

  static BillUrgency _moreUrgent(BillUrgency? a, BillUrgency b) {
    if (a == null) return b;
    return _rank(b) > _rank(a) ? b : a;
  }

  static int _rank(BillUrgency urgency) {
    switch (urgency) {
      case BillUrgency.overdue:
        return 5;
      case BillUrgency.dueToday:
        return 4;
      case BillUrgency.dueSoon:
        return 3;
      case BillUrgency.upcoming:
        return 2;
      case BillUrgency.paid:
        return 1;
      case BillUrgency.skipped:
      case BillUrgency.moved:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final firstOfMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // DateTime.weekday is 1 for Monday; this grid starts on Sunday.
    final leadingBlanks = firstOfMonth.weekday % 7;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: context.appColors.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1,
            children: [
              for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
              for (var day = 1; day <= daysInMonth; day++)
                _DayCell(
                  date: DateTime(month.year, month.month, day),
                  isToday: _isSameDay(
                    DateTime(month.year, month.month, day),
                    today,
                  ),
                  isSelected:
                      selectedDay != null &&
                      _isSameDay(
                        DateTime(month.year, month.month, day),
                        selectedDay!,
                      ),
                  urgency: _urgencyFor(DateTime(month.year, month.month, day)),
                  onTap: () =>
                      onSelectDay(DateTime(month.year, month.month, day)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.urgency,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final bool isSelected;
  final BillUrgency? urgency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Semantics(
        selected: isSelected,
        label: urgency == null
            ? '${date.day}'
            : '${date.day}, ${billUrgencyLabel(urgency!)}',
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected ? appPrimaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isToday && !isSelected
                ? Border.all(color: appPrimaryBlue, width: 1.4)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday || isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isSelected ? Colors.white : colors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: urgency == null
                      ? Colors.transparent
                      : isSelected
                      ? Colors.white
                      : billUrgencyColor(context, urgency!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillList extends StatelessWidget {
  const _BillList({
    required this.instances,
    required this.today,
    required this.onAdd,
  });

  final List<BillInstance> instances;
  final DateTime today;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (instances.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Nothing due this month.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textMuted),
            ),
          ),
          AddButton(label: 'Add Bill', onPressed: onAdd),
        ],
      );
    }

    // The Add button comes after the last bill, as under every list.
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      itemCount: instances.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => index == instances.length
          ? AddButton(label: 'Add Bill', onPressed: onAdd)
          : _BillRow(instance: instances[index], today: today),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.instance, required this.today});

  final BillInstance instance;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BillDetailScreen(instance: instance),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: CategoryIcon(instance.category, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        BillStatusBadge(instance: instance, now: today),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            formatShortDate(instance.dueDate),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (instance.carriedOver > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Includes what was left from last time',
                        style: TextStyle(fontSize: 11, color: colors.textBody),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    instance.amount,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (instance.status == BillStatus.partial &&
                      !instance.isCarriedForward) ...[
                    const SizedBox(height: 2),
                    MoneyText(
                      instance.remaining,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillsError extends StatelessWidget {
  const _BillsError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: context.appColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              'We could not load your bills',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.appColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.appColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
