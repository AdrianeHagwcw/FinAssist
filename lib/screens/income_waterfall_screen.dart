import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/amount_input_formatter.dart';

import '../models/allocation.dart';
import '../models/bill.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/allocation_service.dart';
import '../services/budget_service.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/income_sources.dart';
import '../utils/money_format.dart';
import '../widgets/bill_status_badge.dart';
import '../widgets/category_icon.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/service_charge_field.dart';
import '../widgets/wallet_picker.dart';
import '../widgets/wallet_form_sheet.dart';

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
    required String walletId,
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
  String? _walletId;
  bool _walletSelectionCleared = false;
  late DateTime _receivedAt = _today;
  List<Wallet> _walletList = const [];

  /// The bills being decided on, once loaded. Null until then.
  List<BillAllocation>? _allocations;

  /// Bills the user chose to leave alone this time, neither paid nor skipped.
  final Set<String> _leftAlone = {};

  /// Whether the bank, e-wallet or biller charged for paying the bills on
  /// this step, and how much, as on Pay Bill.
  bool _charged = false;
  final _chargeController = TextEditingController();

  double get _charge =>
      ServiceChargeField.amountOf(on: _charged, controller: _chargeController);

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
    _walletId = widget.initialWalletId;
    _amountController.addListener(_refresh);
    _otherSourceController.addListener(_refresh);
    _chargeController.addListener(_refresh);
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
    _chargeController
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

  String? get _selectedWalletId {
    if (_walletSelectionCleared) return null;
    if (_walletId != null) return _walletId;
    for (final wallet in _walletList) {
      if (!wallet.archived && !wallet.isSetAside) return wallet.id;
    }
    return defaultWalletId(_walletList);
  }

  Wallet? get _selectedWallet {
    for (final wallet in _walletList) {
      if (wallet.id == _selectedWalletId) return wallet;
    }
    return null;
  }

  Future<void> _addWallet() async {
    setState(() {
      _walletSelectionCleared = true;
      _walletId = null;
    });

    final draft = await showWalletFormSheet(context);
    if (draft == null) return;

    final walletId = await WalletService.addWallet(
      type: draft.type,
      name: draft.name,
      startingBalance: draft.startingBalance,
      currentWallets: _walletList,
    );
    if (!mounted) return;
    setState(() {
      _walletSelectionCleared = false;
      _walletId = walletId;
    });
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
      serviceCharge: _charge,
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
    _Step.income =>
      !isRecordableAmount(_income)
          ? minimumAmountError
          : _source == null
          ? 'Choose where the money came from.'
          : _source == otherIncomeSource &&
                _otherSourceController.text.trim().isEmpty
          ? 'Tell us where the money came from.'
          : _selectedWalletId == null
          ? 'Add a wallet first, so the money has somewhere to go.'
          : null,
    _Step.bills when _charged && _plan.toBills > 0 && _charge <= 0 =>
      'Enter the service charge, or turn it off.',
    _Step.bills || _Step.goal => _plan.problems.firstOrNull,
    _Step.summary =>
      _plan.problems.firstOrNull ??
          (_selectedWalletId == null ? 'Choose a wallet.' : null),
  };

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
    final walletId = _selectedWalletId!;

    final save =
        widget.onConfirm ??
        ({
          required AllocationPlan plan,
          required String walletId,
          required String source,
          required DateTime receivedAt,
        }) {
          AllocationService.confirm(
            recentCycles: _recentCycles,
            plan: plan,
            walletId: walletId,
            source: source,
            receivedAt: receivedAt,
            wallets: _walletList,
          );
        };

    save(
      plan: plan,
      walletId: walletId,
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
        return 'Pay any bills from it?';
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
        if (_walletList.isEmpty)
          Text(
            'You have no wallets yet. Add one to receive this income.',
            style: TextStyle(color: context.appColors.textMuted),
          )
        else
          WalletPicker(
            wallets: _walletList,
            selectedId: _selectedWalletId,
            label: 'Into which wallet?',
            // What can be spent, as on Home: goal money is left out.
            goals: _allGoals,
            onChanged: (value) => setState(() {
              _walletSelectionCleared = false;
              _walletId = value;
            }),
            onAddWallet: _addWallet,
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
          'Bills stay unpaid unless you choose to pay them. Tap a bill to '
          'include it, or lower its amount to pay part.',
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
        // Only while a bill is being paid: that is what a fee is for.
        if (plan.toBills > 0) ...[
          ServiceChargeField(
            on: _charged,
            controller: _chargeController,
            onChanged: (on) => setState(() {
              _charged = on;
              // What the Bills wallet, which pays these, was charged last.
              final last = WalletService.walletFor(
                _walletList,
                WalletPurpose.bills,
              )?.serviceCharge;
              if (on && last != null && _chargeController.text.trim().isEmpty) {
                _chargeController.text = formatAmountInput(last);
              }
            }),
          ),
          const SizedBox(height: 6),
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
        ],
        const SizedBox(height: 16),
        _RunningTotal(plan: plan, label: 'Left after bills and goal'),
      ],
    );
  }

  // ------------------------------------------------------------ step 3

  Widget _buildSummaryStep(BuildContext context) {
    final plan = _plan;
    final colors = context.appColors;
    final wallet = _selectedWallet;
    final paying = plan.bills.where((bill) => bill.pays).toList();
    final skipped = plan.bills.where((bill) => bill.skipped).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryCard(
          children: [
            _SummaryLine(
              label: '$_resolvedSource into ${wallet?.name ?? 'your wallet'}',
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: plan.dipsIntoSavings
                ? dangerColorOn(context).withValues(alpha: 0.1)
                : appPrimaryBlue,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.dipsIntoSavings ? 'More than came in' : 'Left to spend',
                style: TextStyle(
                  fontSize: 13,
                  color: plan.dipsIntoSavings
                      ? dangerColorOn(context)
                      : Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatPeso(plan.remaining.abs()),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: plan.dipsIntoSavings
                      ? dangerColorOn(context)
                      : Colors.white,
                ),
              ),
              if (plan.dipsIntoSavings) ...[
                const SizedBox(height: 6),
                Text(
                  'The bills and goals you chose cost more than this income. '
                  'The difference will come out of what was already in '
                  '${wallet?.name ?? 'the wallet'}.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textBody,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
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
                  child: const Text('Back'),
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
