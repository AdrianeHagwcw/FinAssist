import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/amount_input_formatter.dart';

import '../../backend/models/allocation.dart';
import '../../backend/models/bill.dart';
import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/allocation_service.dart';
import '../../backend/services/budget_service.dart';
import '../../backend/services/goal_service.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/income_sources.dart';
import '../../backend/utils/money_format.dart';
import '../widgets/bill_status_badge.dart';
import '../widgets/category_icon.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/wallet_form_sheet.dart';
import '../widgets/wallet_split_picker.dart';

/// Walks the user through new income: what came in, which bills to pay from
/// it, and what is left. Returns true when the income was saved.
Future<bool> showIncomeWaterfall(
  BuildContext context, {
  String? walletId,
  double? initialAmount,
  String? initialSource,
}) {
  return Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (context) => IncomeWaterfallScreen(
        initialWalletId: walletId,
        initialAmount: initialAmount,
        initialSource: initialSource,
      ),
    ),
  ).then((saved) => saved ?? false);
}

class IncomeWaterfallScreen extends StatefulWidget {
  const IncomeWaterfallScreen({
    this.initialWalletId,
    this.initialAmount,
    this.initialSource,
    this.wallets,
    this.loadBills,
    this.goals,
    this.cycles,
    this.onConfirm,
    this.today,
    super.key,
  });

  /// The wallet the income goes into, when opened from a particular wallet.
  final String? initialWalletId;

  /// The amount and source recognized by Voice Entry, if any.
  final double? initialAmount;
  final String? initialSource;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the lookup of bills to offer. Used by tests.
  final Future<List<BillInstance>> Function()? loadBills;

  /// Replaces the live goals. Used by tests.
  final Stream<List<Goal>>? goals;

  /// Replaces the recent income, which says which pay period this income
  /// joins. Used by tests.
  final Stream<List<AllocationCycle>>? cycles;

  /// Replaces saving to Firestore. Used by tests.
  final void Function({
    required AllocationPlan plan,
    required Map<String, double> incomeByWallet,
    required Map<String, double> billsPaidFrom,
    required Map<String, double> billFees,
    required Map<String, double> goalKeptIn,
    required String source,
    required DateTime receivedAt,
  })?
  onConfirm;

  /// Injectable so tests don't depend on the clock.
  final DateTime? today;

  @override
  State<IncomeWaterfallScreen> createState() => _IncomeWaterfallScreenState();
}

enum _Step { income, bills, goal, summary }

class _IncomeWaterfallScreenState extends State<IncomeWaterfallScreen> {
  late final DateTime _today = widget.today ?? DateTime.now();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  final _amountController = TextEditingController();
  final _otherSourceController = TextEditingController();

  /// One amount box per bill, kept so typing isn't lost between rebuilds.
  final Map<String, TextEditingController> _billControllers = {};

  _Step _step = _Step.income;

  /// Active goals, highest priority first. Null until loaded.
  List<Goal>? _goals;

  /// Every goal, finished ones too, for the money each holds in a wallet.
  List<Goal> _allGoals = const [];
  StreamSubscription<List<Goal>>? _goalSubscription;

  /// Income already logged, to place this one in the right pay period.
  List<AllocationCycle> _recentCycles = const [];
  StreamSubscription<List<AllocationCycle>>? _cycleSubscription;

  /// The goal step's answers.
  bool _toGoal = false;
  String? _goalId;
  bool _useWhatsLeft = true;
  final _goalAmountController = TextEditingController();
  String? _source;
  late DateTime _receivedAt = _today;
  List<Wallet> _walletList = const [];

  /// The bills being decided on, once loaded. Null until then.
  List<BillAllocation>? _allocations;

  /// Bills the user chose to leave alone this time, neither paid nor skipped.
  final Set<String> _leftAlone = {};

  /// Where the income went, by wallet: as much as came in, no more.
  late Map<String, double> _incomeSplit = {
    if (widget.initialWalletId != null && (widget.initialAmount ?? 0) > 0)
      widget.initialWalletId!: widget.initialAmount!,
  };

  /// The wallets the bills were paid from, and what each was charged.
  Map<String, double> _billsFrom = const {};
  Map<String, double> _billFees = const {};

  /// The wallets the goal's money stays in.
  Map<String, double> _goalFrom = const {};

  double get _feesTotal =>
      _billFees.values.fold<double>(0, (sum, fee) => sum + fee);

  /// What each wallet has left of this income once its bills and fees are
  /// paid. Negative when a wallet pays more than it received, from money
  /// already in it.
  Map<String, double> get _afterBills {
    final left = <String, double>{..._incomeSplit};
    for (final entry in _billsFrom.entries) {
      left[entry.key] = (left[entry.key] ?? 0) - entry.value;
    }
    for (final entry in _billFees.entries) {
      left[entry.key] = (left[entry.key] ?? 0) - entry.value;
    }
    return left;
  }

  /// The step whose Next was last tapped. Its problem shows under it and
  /// is worked out again as the user types, so it goes as soon as it is
  /// fixed. A step not tried yet shows none.
  _Step? _triedStep;

  @override
  void initState() {
    super.initState();
    if (widget.initialSource != null) {
      _source = incomeSources.contains(widget.initialSource)
          ? widget.initialSource
          : otherIncomeSource;
      if (_source == otherIncomeSource) {
        _otherSourceController.text = widget.initialSource!;
      }
    }
    if (widget.initialAmount != null) {
      _amountController.text = formatAmountInput(widget.initialAmount!);
    }
    _amountController.addListener(_refresh);
    _otherSourceController.addListener(_refresh);
    // Start looking up bills straight away, so they're ready by step 2.
    _loadBills();
    _goalSubscription = (widget.goals ?? GoalService.watchGoals()).listen(
      (goals) {
        if (!mounted) return;
        setState(() {
          _allGoals = goals;
          _goals = goals
              .where((goal) => goal.status == GoalStatus.active)
              .toList();
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _goals = const []);
      },
    );
    _goalAmountController.addListener(_refresh);
    _cycleSubscription = (widget.cycles ?? BudgetService.watchRecentCycles())
        .listen(
          (cycles) => _recentCycles = cycles,
          // Without them, the income is placed as before: from its own date.
          onError: (Object _) {},
        );
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _amountController
      ..removeListener(_refresh)
      ..dispose();
    _otherSourceController
      ..removeListener(_refresh)
      ..dispose();
    _goalSubscription?.cancel();
    _cycleSubscription?.cancel();
    _goalAmountController
      ..removeListener(_refresh)
      ..dispose();
    for (final controller in _billControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBills() async {
    try {
      final bills =
          await (widget.loadBills ??
              () => AllocationService.loadOutstandingBills(now: _today))();
      if (!mounted) return;

      setState(() {
        final today = DateTime(_today.year, _today.month, _today.day);
        final nextMonth = DateTime(today.year, today.month + 1);
        final shownBills = bills.where((bill) {
          final due = DateTime(
            bill.dueDate.year,
            bill.dueDate.month,
            bill.dueDate.day,
          );
          return due.isBefore(nextMonth);
        }).toList();
        _allocations = [
          for (final bill in shownBills) BillAllocation.full(bill),
        ];
        _leftAlone.addAll(shownBills.map((bill) => bill.id));
        for (final bill in shownBills) {
          _billControllers[bill.id] = TextEditingController(
            text: formatAmountInput(bill.remaining),
          )..addListener(_refresh);
        }
      });
    } catch (_) {
      // Offline with nothing cached: carry on without bills rather than
      // blocking the income from being recorded.
      if (mounted) setState(() => _allocations = const []);
    }
  }

  double get _income =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '')) ?? 0;

  String get _resolvedSource {
    if (_source != otherIncomeSource) return _source ?? '';

    final typed = _otherSourceController.text.trim();
    return typed.isEmpty ? otherIncomeSource : typed;
  }

  /// The wallets named in [amounts], in a short list for the summary.
  String _walletNames(Map<String, double> amounts) {
    final names = [
      for (final wallet in _walletList)
        if ((amounts[wallet.id] ?? 0) > 0) wallet.name,
    ];
    if (names.isEmpty) return 'your wallets';
    if (names.length == 1) return names.single;
    return '${names.sublist(0, names.length - 1).join(', ')} and '
        '${names.last}';
  }

  /// Opened when there is no wallet at all, so the money has somewhere to go.
  Future<void> _addWallet() async {
    final draft = await showWalletFormSheet(context);
    if (draft == null) return;

    await WalletService.addWallet(
      type: draft.type,
      name: draft.name,
      startingBalance: draft.startingBalance,
      currentWallets: _walletList,
    );
  }

  /// The plan as it stands, read from what is typed on screen.
  AllocationPlan get _plan {
    final bills = <BillAllocation>[];

    for (final allocation in _allocations ?? const <BillAllocation>[]) {
      final id = allocation.instance.id;

      if (_leftAlone.contains(id)) continue;

      final typed = double.tryParse(
        (_billControllers[id]?.text ?? '').trim().replaceAll(',', ''),
      );

      bills.add(allocation.copyWith(amount: typed ?? -1));
    }

    final withBills = AllocationPlan(
      income: _income,
      bills: bills,
      serviceCharge: _feesTotal,
    );

    final goal = _toGoal ? _selectedGoal : null;
    if (goal == null) return withBills;

    final double amount;
    if (_useWhatsLeft) {
      // Everything left after bills, but never past what the goal needs.
      final left = withBills.afterBills;
      amount = left <= 0 ? 0 : (left < goal.remaining ? left : goal.remaining);
    } else {
      amount =
          double.tryParse(
            _goalAmountController.text.trim().replaceAll(',', ''),
          ) ??
          -1;
    }

    return AllocationPlan(
      income: _income,
      bills: withBills.bills,
      goal: goal,
      goalAmount: amount,
      serviceCharge: withBills.serviceCharge,
    );
  }

  Goal? get _selectedGoal {
    final goals = _goals ?? const <Goal>[];
    if (goals.isEmpty) return null;

    for (final goal in goals) {
      if (goal.id == _goalId) return goal;
    }
    return goals.first;
  }

  /// The steps this income goes through. Bills and goals are left out when
  /// there are none to ask about, so the step count is honest.
  List<_Step> get _steps => [
    _Step.income,
    if (_allocations?.isNotEmpty ?? true) _Step.bills,
    if (_goals?.isNotEmpty ?? false) _Step.goal,
    _Step.summary,
  ];

  _Step _stepAfter(_Step step) {
    final steps = _steps;
    final index = steps.indexOf(step);
    return index < 0 || index + 1 >= steps.length
        ? _Step.summary
        : steps[index + 1];
  }

  _Step _stepBefore(_Step step) {
    final steps = _steps;
    final index = steps.indexOf(step);
    return index <= 0 ? _Step.income : steps[index - 1];
  }

  void _back() => setState(() => _step = _stepBefore(_step));

  /// What stops the step on screen going on, or null.
  String? get _problem => switch (_step) {
    _Step.income => _incomeProblem,
    _Step.bills => _plan.problems.firstOrNull ?? _billsProblem,
    _Step.goal => _plan.problems.firstOrNull ?? _goalProblem,
    _Step.summary =>
      _incomeProblem ??
          _plan.problems.firstOrNull ??
          _billsProblem ??
          _goalProblem,
  };

  /// The income, where it came from, and where it went: as much as came
  /// in, no more and no less.
  String? get _incomeProblem {
    if (!isRecordableAmount(_income)) return minimumAmountError;
    if (_source == null) return 'Choose where the money came from.';
    if (_source == otherIncomeSource &&
        _otherSourceController.text.trim().isEmpty) {
      return 'Tell us where the money came from.';
    }
    if (_walletList.isEmpty) {
      return 'Add a wallet first, so the money has somewhere to go.';
    }
    return walletSplitProblem(
      purpose: SplitPurpose.receiving,
      amounts: _incomeSplit,
      wallets: _walletList,
      goals: _allGoals,
      target: _income,
      matchTarget: true,
    );
  }

  /// The bills paid must come out of wallets that have the money, this
  /// income included.
  String? get _billsProblem => _plan.toBills <= 0
      ? null
      : walletSplitProblem(
          purpose: SplitPurpose.paying,
          amounts: _billsFrom,
          fees: _billFees,
          wallets: _walletList,
          goals: _allGoals,
          target: _plan.toBills,
          matchTarget: true,
          adding: _incomeSplit,
        );

  /// Goal money must stay in wallets that still have it after the bills.
  String? get _goalProblem => _plan.toGoal <= 0
      ? null
      : walletSplitProblem(
          purpose: SplitPurpose.giving,
          amounts: _goalFrom,
          wallets: _walletList,
          goals: _allGoals,
          target: _plan.toGoal,
          matchTarget: true,
          adding: _afterBills,
        );

  /// Notes that Next was tapped on this step, so its problem shows, and
  /// says whether it can be left.
  bool _checkStep() {
    setState(() => _triedStep = _step);
    return _problem == null;
  }

  void _next(_Step to) {
    if (!_checkStep()) return;
    setState(() => _step = to);
  }

  // Skips straight past bills or goals when there are none to ask about.
  void _fromIncomeStep() => _next(_stepAfter(_Step.income));

  void _fromBillsStep() => _next(_stepAfter(_Step.bills));

  void _fromGoalStep() => _next(_Step.summary);

  void _confirm() {
    if (!_checkStep()) return;
    final plan = _plan;
    // A step the user stepped back out of leaves nothing behind.
    final billsFrom = plan.toBills > 0 ? _billsFrom : const <String, double>{};
    final billFees = plan.toBills > 0 ? _billFees : const <String, double>{};
    final goalFrom = plan.toGoal > 0 ? _goalFrom : const <String, double>{};

    final save =
        widget.onConfirm ??
        ({
          required AllocationPlan plan,
          required Map<String, double> incomeByWallet,
          required Map<String, double> billsPaidFrom,
          required Map<String, double> billFees,
          required Map<String, double> goalKeptIn,
          required String source,
          required DateTime receivedAt,
        }) {
          AllocationService.confirm(
            recentCycles: _recentCycles,
            plan: plan,
            incomeByWallet: incomeByWallet,
            billsPaidFrom: billsPaidFrom,
            billFees: billFees,
            goalKeptIn: goalKeptIn,
            source: source,
            receivedAt: receivedAt,
          );
        };

    save(
      plan: plan,
      incomeByWallet: _incomeSplit,
      billsPaidFrom: billsFrom,
      billFees: billFees,
      goalKeptIn: goalFrom,
      source: _resolvedSource,
      receivedAt: _receivedAt,
    );

    Navigator.pop(context, true);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedAt,
      firstDate: DateTime(_today.year - 1),
      lastDate: _today,
    );

    if (picked != null) {
      setState(() {
        _receivedAt = keepTimeOfDay(picked, _receivedAt);
      });
    }
  }

  int get _stepNumber => _steps.indexOf(_step) + 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Add Income',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: _wallets,
        builder: (context, snapshot) {
          _walletList = snapshot.data ?? const [];
          final error = _triedStep == _step ? _problem : null;

          return Column(
            children: [
              _StepHeader(
                step: _stepNumber,
                of: _steps.length,
                title: _stepTitle,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    switch (_step) {
                      _Step.income => _buildIncomeStep(context),
                      _Step.bills => _buildBillsStep(context),
                      _Step.goal => _buildGoalStep(context),
                      _Step.summary => _buildSummaryStep(context),
                    },
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        error,
                        style: TextStyle(
                          color: dangerColorOn(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _buildButtons(context),
            ],
          );
        },
      ),
    );
  }

  String get _stepTitle {
    switch (_step) {
      case _Step.income:
        return 'What came in?';
      case _Step.bills:
        return 'Did you pay any bills from it?';
      case _Step.goal:
        return 'Save some toward a goal?';
      case _Step.summary:
        return 'Here is what is left';
    }
  }

  // ------------------------------------------------------------ step 1

  Widget _buildIncomeStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AmountField(controller: _amountController, label: 'Amount received'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _source,
          isExpanded: true,
          decoration: dialogFieldDecoration(context, 'Source'),
          items: [
            for (final source in incomeSources)
              DropdownMenuItem(value: source, child: Text(source)),
          ],
          onChanged: (value) => setState(() => _source = value),
        ),
        if (_source == otherIncomeSource) ...[
          const SizedBox(height: 16),
          TextField(
            key: const Key('other-income-source'),
            controller: _otherSourceController,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 30,
            decoration: dialogFieldDecoration(
              context,
              'Where did it come from?',
              hint: 'e.g. Sold my old phone',
              helper:
                  'Name where the money came from, such as selling an '
                  'item, rental income or support from family.',
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_walletList.isEmpty) ...[
          Text(
            'You have no wallets yet. Add one to receive this income.',
            style: TextStyle(color: context.appColors.textMuted),
          ),
          TextButton.icon(
            onPressed: _addWallet,
            icon: const Icon(Icons.add),
            label: const Text('Add wallet'),
          ),
        ] else
          WalletSplitPicker(
            key: const ValueKey('income-goes-to'),
            wallets: _walletList,
            goals: _allGoals,
            purpose: SplitPurpose.receiving,
            question: 'Where did it go?',
            target: _income,
            matchTarget: true,
            initialAmounts: _incomeSplit,
            totalLabel: 'Received',
            onChanged: (amounts) => setState(() => _incomeSplit = amounts),
          ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: dialogFieldDecoration(context, 'Date received'),
            child: Row(
              children: [
                Expanded(child: Text(formatShortDate(_receivedAt))),
                Image.asset(
                  'assets/icons/icons8-calendar-96.png',
                  width: 22,
                  height: 22,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ step 2

  Widget _buildBillsStep(BuildContext context) {
    final allocations = _allocations;

    if (allocations == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final plan = _plan;
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tick only the bills you paid, and lower the amount if you paid '
          'part. The rest stay in Bill Planner.',
          style: TextStyle(fontSize: 13, color: colors.textBody, height: 1.4),
        ),
        if (allocations.length > 1) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${allocations.length} bills',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _setAllPaid(!_allPaid(allocations)),
                style: TextButton.styleFrom(
                  foregroundColor: colors.primaryText,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  _allPaid(allocations) ? 'Uncheck all' : 'Check all',
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        for (final allocation in allocations) ...[
          _BillChoice(
            allocation: allocation,
            controller: _billControllers[allocation.instance.id]!,
            leftAlone: _leftAlone.contains(allocation.instance.id),
            skipped: allocation.skipped,
            today: _today,
            onPayChanged: (pay) => setState(() {
              final id = allocation.instance.id;
              pay ? _leftAlone.remove(id) : _leftAlone.add(id);
              _setSkipped(allocation, false);
            }),
            onSkipChanged: (skip) => setState(() {
              _leftAlone.remove(allocation.instance.id);
              _setSkipped(allocation, skip);
            }),
          ),
          const SizedBox(height: 10),
        ],
        // Only while a bill is being paid: where the money came from, this
        // income included, and what each wallet was charged.
        if (plan.toBills > 0) ...[
          const SizedBox(height: 6),
          WalletSplitPicker(
            key: const ValueKey('bills-paid-from'),
            wallets: _walletList,
            goals: _allGoals,
            purpose: SplitPurpose.paying,
            question: 'Where did you pay them from?',
            target: plan.toBills,
            matchTarget: true,
            withFees: true,
            adding: _incomeSplit,
            initialAmounts: _billsFrom,
            totalLabel: 'Paying bills',
            onChanged: (amounts) => setState(() => _billsFrom = amounts),
            onFeesChanged: (fees) => setState(() => _billFees = fees),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 6),
        _RunningTotal(plan: plan),
      ],
    );
  }

  /// True when every bill on the list is ticked to be paid now.
  bool _allPaid(List<BillAllocation> allocations) {
    return allocations.every(
      (allocation) =>
          !allocation.skipped && !_leftAlone.contains(allocation.instance.id),
    );
  }

  /// Ticks or unticks every bill at once. Ticking one that was skipped brings
  /// it back, so "Check all" really does cover the whole list.
  void _setAllPaid(bool pay) {
    final allocations = _allocations;
    if (allocations == null) return;

    setState(() {
      if (pay) {
        _leftAlone.clear();
        _allocations = [
          for (final allocation in allocations)
            allocation.skipped
                ? allocation.copyWith(skipped: false)
                : allocation,
        ];
      } else {
        _leftAlone.addAll(
          allocations.map((allocation) => allocation.instance.id),
        );
      }
    });
  }

  void _setSkipped(BillAllocation allocation, bool skipped) {
    final list = _allocations!;
    final index = list.indexWhere(
      (item) => item.instance.id == allocation.instance.id,
    );
    if (index < 0) return;

    _allocations = [...list]..[index] = list[index].copyWith(skipped: skipped);
  }

  // ------------------------------------------------------------ goal step

  Widget _buildGoalStep(BuildContext context) {
    final colors = context.appColors;
    final goals = _goals ?? const <Goal>[];
    final goal = _selectedGoal;
    final plan = _plan;
    final left = plan.afterBills;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Money set aside for a goal stays in your wallet, but stops counting '
          'as money you can spend.',
          style: TextStyle(fontSize: 13, color: colors.textBody, height: 1.4),
        ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Not this time')),
            ButtonSegment(value: true, label: Text('Yes')),
          ],
          selected: {_toGoal},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => _toGoal = value.first),
        ),
        if (_toGoal && goal != null) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: goal.id,
            isExpanded: true,
            decoration: dialogFieldDecoration(context, 'Which goal?'),
            items: [
              for (final option in goals)
                DropdownMenuItem(
                  value: option.id,
                  child: Text(
                    '${option.name} · ${formatPeso(option.remaining)} to go',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _goalId = value),
          ),
          const SizedBox(height: 16),
          RadioGroup<bool>(
            groupValue: _useWhatsLeft,
            onChanged: (value) =>
                setState(() => _useWhatsLeft = value ?? _useWhatsLeft),
            child: Column(
              children: [
                RadioListTile<bool>(
                  value: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use what is left'),
                  subtitle: Text(
                    left <= 0
                        ? 'Nothing is left after bills.'
                        : left > goal.remaining
                        ? '${formatPeso(goal.remaining)}, all this goal needs'
                        : formatPeso(left),
                  ),
                ),
                RadioListTile<bool>(
                  value: false,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enter an amount'),
                ),
              ],
            ),
          ),
          if (!_useWhatsLeft)
            TextField(
              controller: _goalAmountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [ThousandsSeparatorFormatter()],
              decoration: dialogFieldDecoration(
                context,
                'Amount to set aside',
                helper: '${goal.name} needs ${formatPeso(goal.remaining)} more',
              ).copyWith(prefixText: '₱ ', hintText: '0.00'),
            ),
          if (plan.toGoal > 0) ...[
            const SizedBox(height: 16),
            WalletSplitPicker(
              key: const ValueKey('goal-kept-in'),
              wallets: _walletList,
              goals: _allGoals,
              purpose: SplitPurpose.giving,
              question: 'Which wallets keep it?',
              target: plan.toGoal,
              matchTarget: true,
              adding: _afterBills,
              initialAmounts: _goalFrom,
              totalLabel: 'Toward ${goal.name}',
              onChanged: (amounts) => setState(() => _goalFrom = amounts),
            ),
          ],
        ],
        const SizedBox(height: 16),
        _RunningTotal(plan: plan, label: 'Left after bills and goal'),
      ],
    );
  }

  // ------------------------------------------------------------ step 3

  Widget _buildSummaryStep(BuildContext context) {
    final plan = _plan;
    final paying = plan.bills.where((bill) => bill.pays).toList();
    final skipped = plan.bills.where((bill) => bill.skipped).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryCard(
          children: [
            _SummaryLine(
              label: '$_resolvedSource into ${_walletNames(_incomeSplit)}',
              detail: formatShortDate(_receivedAt),
              amount: formatPeso(plan.income, sign: '+'),
              color: confirmColorOn(context),
            ),
            for (final bill in paying)
              _SummaryLine(
                label: bill.instance.name,
                detail: bill.amount + 0.005 < bill.instance.remaining
                    ? 'Part payment'
                    : 'Paid in full',
                amount: formatPeso(bill.amount, sign: '-'),
                color: dangerColorOn(context),
              ),
            if (plan.billsServiceCharge > 0)
              _SummaryLine(
                label: 'Service charge',
                detail: 'For paying these bills',
                amount: formatPeso(plan.billsServiceCharge, sign: '-'),
                color: dangerColorOn(context),
              ),
            for (final bill in skipped)
              _SummaryLine(
                label: bill.instance.name,
                detail: 'Skipped this time',
                amount: formatPeso(0),
                color: context.appColors.textMuted,
              ),
            if (plan.goal != null && plan.toGoal > 0)
              _SummaryLine(
                label: plan.goal!.name,
                detail: 'Set aside toward your goal',
                amount: formatPeso(plan.toGoal, sign: '-'),
                color: appPrimaryBlue,
              ),
          ],
        ),
        const SizedBox(height: 16),
        _BalanceAfter(
          tally: _tally(plan),
          // What this income leaves, only when bills or a goal took some of
          // it: otherwise it is simply the income.
          left: plan.toBills > 0 || plan.toGoal > 0 || plan.dipsIntoSavings
              ? plan.remaining
              : null,
        ),
        if (plan.dipsIntoSavings) ...[
          const SizedBox(height: 10),
          Text(
            'The bills and goals you chose cost more than this income. The '
            'difference comes out of what was already in your wallets.',
            style: TextStyle(
              fontSize: 12,
              color: dangerColorOn(context),
              height: 1.4,
            ),
          ),
        ],
        if (_allocations?.isEmpty ?? false) ...[
          const SizedBox(height: 12),
          Text(
            'No unpaid bills right now, so there was nothing to pay from this.',
            style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
          ),
        ],
      ],
    );
  }

  /// What is free to spend now and once this is confirmed, added up the
  /// way Home does: cash wallets on hand, the rest in bank, each less what
  /// goals hold in it. Bills paid and fees come out of the wallets they are
  /// paid from; goal money stays in its wallet, marked for the goal.
  ({double cashBefore, double cashAfter, double bankBefore, double bankAfter})
  _tally(AllocationPlan plan) {
    final goals = _goals ?? const <Goal>[];
    final billsFrom = plan.toBills > 0 ? _billsFrom : const <String, double>{};
    final fees = plan.toBills > 0 ? _billFees : const <String, double>{};
    final goalFrom = plan.toGoal > 0 ? _goalFrom : const <String, double>{};
    final income = _incomeSplit;
    var cashBefore = 0.0;
    var cashAfter = 0.0;
    var bankBefore = 0.0;
    var bankAfter = 0.0;
    for (final wallet in _walletList) {
      if (wallet.archived || wallet.isSetAside) continue;
      final before = freeInWallet(wallet, goals);
      final after =
          before +
          (income[wallet.id] ?? 0) -
          (billsFrom[wallet.id] ?? 0) -
          (fees[wallet.id] ?? 0) -
          (goalFrom[wallet.id] ?? 0);
      if (wallet.type == WalletType.cash) {
        cashBefore += before;
        cashAfter += after;
      } else {
        bankBefore += before;
        bankAfter += after;
      }
    }
    return (
      cashBefore: cashBefore,
      cashAfter: cashAfter,
      bankBefore: bankBefore,
      bankAfter: bankAfter,
    );
  }

  // ----------------------------------------------------------- buttons

  Widget _buildButtons(BuildContext context) {
    final back = _step == _Step.income ? null : _back;

    final next = switch (_step) {
      _Step.income => _fromIncomeStep,
      _Step.bills => _fromBillsStep,
      _Step.goal => _fromGoalStep,
      _Step.summary => _confirm,
    };

    final isLast = _step == _Step.summary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            if (back != null) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: back,
                  style: openOutlineStyle(context, height: 52),
                  child: const Text(
                    'Back',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: next,
                // Only the last step commits anything, so only it is green.
                style: isLast ? confirmButtonStyle() : openButtonStyle(),
                child: Text(
                  isLast ? 'Confirm' : 'Next',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The user's money once this income is confirmed, as Home will show it:
/// the Available Balance, then cash on hand and cash in bank, each with what
/// it was, so the change can be checked before confirming.
class _BalanceAfter extends StatelessWidget {
  const _BalanceAfter({required this.tally, this.left});

  final ({
    double cashBefore,
    double cashAfter,
    double bankBefore,
    double bankAfter,
  })
  tally;

  /// What this income leaves after the bills and goal it paid; negative
  /// when they took more than came in. Null to leave the line out.
  final double? left;

  static String _change(double after, double before) {
    final change = after - before;
    if (change.abs() < 0.005) return 'No change';
    return formatPeso(change, sign: change > 0 ? '+' : '-');
  }

  @override
  Widget build(BuildContext context) {
    final before = tally.cashBefore + tally.bankBefore;
    final after = tally.cashAfter + tally.bankAfter;

    Widget part(String label, String iconAsset, double now, double was) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(iconAsset, width: 18, height: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  formatPeso(now),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _change(now, was),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        );

    return Container(
      key: const Key('income-balance-after'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appPrimaryBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Balance after this',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            formatPeso(after),
            key: const Key('income-available-after'),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            'Was ${formatPeso(before)} · ${_change(after, before)}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              part(
                'Cash on Hand',
                WalletType.cash.iconAsset,
                tally.cashAfter,
                tally.cashBefore,
              ),
              const SizedBox(width: 8),
              part(
                'Cash in Bank',
                WalletType.bank.iconAsset,
                tally.bankAfter,
                tally.bankBefore,
              ),
            ],
          ),
          if (left != null) ...[
            const Divider(height: 24, color: Colors.white24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    left! < 0
                        ? 'More than came in'
                        : 'Left to spend from this '
                              'income',
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
                Text(
                  formatPeso(left!.abs()),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.of,
    required this.title,
  });

  final int step;
  final int of;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step $step of $of',
            style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: step / of,
              minHeight: 5,
              backgroundColor: colors.track,
              valueColor: const AlwaysStoppedAnimation(appPrimaryBlue),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillChoice extends StatelessWidget {
  const _BillChoice({
    required this.allocation,
    required this.controller,
    required this.leftAlone,
    required this.skipped,
    required this.today,
    required this.onPayChanged,
    required this.onSkipChanged,
  });

  final BillAllocation allocation;
  final TextEditingController controller;
  final bool leftAlone;
  final bool skipped;
  final DateTime today;
  final ValueChanged<bool> onPayChanged;
  final ValueChanged<bool> onSkipChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bill = allocation.instance;
    final paying = !leftAlone && !skipped;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: paying ? appPrimaryBlue.withValues(alpha: 0.5) : colors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: paying,
                onChanged: (value) => onPayChanged(value ?? false),
              ),
              CategoryIcon(bill.category, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        decoration: skipped ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        BillStatusBadge(instance: bill, now: today),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Due ${formatShortDate(bill.dueDate)}',
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
                  ],
                ),
              ),
            ],
          ),
          if (paying) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [ThousandsSeparatorFormatter()],
                decoration: dialogFieldDecoration(
                  context,
                  'Pay now',
                  helper: 'Still owes ${formatPeso(bill.remaining)}',
                ).copyWith(prefixText: '₱ ', hintText: '0.00'),
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => onSkipChanged(!skipped),
              style: skipped
                  ? openOutlineStyle(context, height: 36)
                  : dangerTextStyle(context),
              icon: Icon(skipped ? Icons.undo : Icons.close, size: 16),
              label: Text(skipped ? 'Undo skip' : 'Skip this bill'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunningTotal extends StatelessWidget {
  const _RunningTotal({
    required this.plan,
    this.label = 'Left after these bills',
  });

  final AllocationPlan plan;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final short = plan.dipsIntoSavings;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              short ? 'Short by' : label,
              style: TextStyle(fontSize: 13, color: colors.textBody),
            ),
          ),
          Text(
            formatPeso(plan.remaining.abs()),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: short ? dangerColorOn(context) : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: context.appColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.detail,
    required this.amount,
    required this.color,
  });

  final String label;
  final String detail;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
