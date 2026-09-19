import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../services/bill_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'bill_detail_screen.dart';
import '../widgets/bill_form_sheet.dart';
import '../widgets/bill_status_badge.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/money_text.dart';

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

  @override
  State<BillCalendarScreen> createState() => _BillCalendarScreenState();
}

class _BillCalendarScreenState extends State<BillCalendarScreen> {
  late final DateTime _today = _dateOnly(widget.today ?? DateTime.now());
  late final Stream<List<Bill>> _bills =
      widget.bills ?? BillService.watchBills();

  late DateTime _month = DateTime(_today.year, _today.month);
  late DateTime? _selectedDay = _today;

  bool _showAsList = false;

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
        title: const Text(
          'Bill Planner',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _showAsList ? 'Show calendar' : 'Show list',
            icon: Icon(_showAsList ? Icons.calendar_month : Icons.view_list),
            onPressed: () => setState(() => _showAsList = !_showAsList),
          ),
        ],
      ),
      body: StreamBuilder<List<Bill>>(
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
                return const EmptyStateView(
                  iconAsset: 'assets/icons/icons8-calendar-96.png',
                  title: 'No bills yet',
                  message:
                      'Add the things you pay on a schedule — rent, tuition, '
                      'load — and they will show up here on their due dates.',
                );
              }

              return Column(
                children: [
                  _MonthHeader(
                    month: _month,
                    onPrevious: () => _changeMonth(-1),
                    onNext: () => _changeMonth(1),
                  ),
                  _MonthSummary(instances: instances, today: _today),
                  Expanded(
                    child: _showAsList
                        ? _BillList(instances: instances, today: _today)
                        : _CalendarAndDay(
                            month: _month,
                            today: _today,
                            selectedDay: _selectedDay,
                            instances: instances,
                            onSelectDay: (day) =>
                                setState(() => _selectedDay = day),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBill,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Bill'),
      ),
    );
  }
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

/// What this month costs, and how much of it is still hanging over the user.
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.instances, required this.today});

  final List<BillInstance> instances;
  final DateTime today;

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
      child: Row(
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
            style: const TextStyle(fontSize: 11, color: Colors.grey),
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
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selectedDay;
  final List<BillInstance> instances;
  final ValueChanged<DateTime?> onSelectDay;

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
              style: const TextStyle(color: Colors.grey),
            ),
          )
        else
          for (final instance in shown) ...[
            _BillRow(instance: instance, today: today),
            const SizedBox(height: 10),
          ],
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
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
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
  const _BillList({required this.instances, required this.today});

  final List<BillInstance> instances;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    if (instances.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing due this month.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      itemCount: instances.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _BillRow(instance: instances[index], today: today),
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
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
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
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
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
            const Icon(Icons.cloud_off, size: 42, color: Colors.grey),
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
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
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
