import 'package:flutter/material.dart';

import '../models/allocation.dart';
import '../models/bill.dart';
import '../models/wallet.dart';
import '../services/allocation_service.dart';
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
import '../widgets/wallet_picker.dart';

/// Walks the user through new income: what came in, which bills to pay from
/// it, and what is left. Returns true when the income was saved.
Future<bool> showIncomeWaterfall(BuildContext context, {String? walletId}) {
  return Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (context) => IncomeWaterfallScreen(initialWalletId: walletId),
    ),
  ).then((saved) => saved ?? false);
}

class IncomeWaterfallScreen extends StatefulWidget {
  const IncomeWaterfallScreen({
    this.initialWalletId,
    this.wallets,
    this.loadBills,
    this.onConfirm,
    this.today,
    super.key,
  });

  /// The wallet the income goes into, when opened from a particular wallet.
  final String? initialWalletId;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the lookup of bills to offer. Used by tests.
  final Future<List<BillInstance>> Function()? loadBills;

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

enum _Step { income, bills, summary }

class _IncomeWaterfallScreenState extends State<IncomeWaterfallScreen> {
  late final DateTime _today = widget.today ?? DateTime.now();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  final _amountController = TextEditingController();
  final _otherSourceController = TextEditingController();

  /// One amount box per bill, kept so typing isn't lost between rebuilds.
  final Map<String, TextEditingController> _billControllers = {};

  _Step _step = _Step.income;
  String? _source;
  String? _walletId;
  late DateTime _receivedAt = _today;
  List<Wallet> _walletList = const [];

  /// The bills being decided on, once loaded. Null until then.
  List<BillAllocation>? _allocations;

  /// Bills the user chose to leave alone this time, neither paid nor skipped.
  final Set<String> _leftAlone = {};

  String? _error;

  @override
  void initState() {
    super.initState();
    _walletId = widget.initialWalletId;
    _amountController.addListener(_refresh);
    // Start looking up bills straight away, so they're ready by step 2.
    _loadBills();
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _amountController
      ..removeListener(_refresh)
      ..dispose();
    _otherSourceController.dispose();
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
        _allocations = [for (final bill in bills) BillAllocation.full(bill)];
        for (final bill in bills) {
          _billControllers[bill.id] = TextEditingController(
            text: bill.remaining.toStringAsFixed(2),
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

  String? get _selectedWalletId => _walletId ?? defaultWalletId(_walletList);

  Wallet? get _selectedWallet {
    for (final wallet in _walletList) {
      if (wallet.id == _selectedWalletId) return wallet;
    }
    return null;
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

    return AllocationPlan(income: _income, bills: bills);
  }

  void _toIncomeStep() => setState(() {
    _step = _Step.income;
    _error = null;
  });

  void _fromIncomeStep() {
    final problem = _income <= 0
        ? 'Enter how much came in.'
        : _source == null
        ? 'Choose where the money came from.'
        : _selectedWalletId == null
        ? 'Add a wallet first, so the money has somewhere to go.'
        : null;

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _error = null;
      // Straight to the summary when there are no bills to ask about.
      _step = (_allocations?.isEmpty ?? false) ? _Step.summary : _Step.bills;
    });
  }

  void _fromBillsStep() {
    final problems = _plan.problems;

    if (problems.isNotEmpty) {
      setState(() => _error = problems.first);
      return;
    }

    setState(() {
      _error = null;
      _step = _Step.summary;
    });
  }

  void _backFromSummary() => setState(() {
    _error = null;
    _step = (_allocations?.isEmpty ?? true) ? _Step.income : _Step.bills;
  });

  void _confirm() {
    final plan = _plan;
    final walletId = _selectedWalletId;

    if (walletId == null || plan.problems.isNotEmpty) {
      setState(
        () => _error = plan.problems.isEmpty
            ? 'Choose a wallet.'
            : plan.problems.first,
      );
      return;
    }

    final save =
        widget.onConfirm ??
        ({
          required AllocationPlan plan,
          required String walletId,
          required String source,
          required DateTime receivedAt,
        }) => AllocationService.confirm(
          plan: plan,
          walletId: walletId,
          source: source,
          receivedAt: receivedAt,
        );

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

    if (picked != null) setState(() => _receivedAt = picked);
  }

  int get _stepNumber => _step.index + 1;

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

          return Column(
            children: [
              _StepHeader(step: _stepNumber, of: 3, title: _stepTitle),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    switch (_step) {
                      _Step.income => _buildIncomeStep(context),
                      _Step.bills => _buildBillsStep(context),
                      _Step.summary => _buildSummaryStep(context),
                    },
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
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
            controller: _otherSourceController,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 30,
            decoration: dialogFieldDecoration(
              context,
              'Where did it come from?',
              hint: 'e.g. Sold my old phone',
              helper: 'Optional. Blank just calls it Other.',
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_walletList.isEmpty)
          const Text(
            'You have no wallets yet. Add one from the Wallet tab first.',
            style: TextStyle(color: Colors.grey),
          )
        else
          WalletPicker(
            wallets: _walletList,
            selectedId: _selectedWalletId,
            label: 'Into which wallet?',
            onChanged: (value) => setState(() => _walletId = value),
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
                const Icon(Icons.calendar_today, size: 18),
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
          'These are unpaid or due within the month. Each starts on the full '
          'amount; lower it to pay part, or leave a bill for later.',
          style: TextStyle(fontSize: 13, color: colors.textBody, height: 1.4),
        ),
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
        const SizedBox(height: 6),
        _RunningTotal(plan: plan),
      ],
    );
  }

  void _setSkipped(BillAllocation allocation, bool skipped) {
    final list = _allocations!;
    final index = list.indexWhere(
      (item) => item.instance.id == allocation.instance.id,
    );
    if (index < 0) return;

    _allocations = [...list]..[index] = list[index].copyWith(skipped: skipped);
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
            for (final bill in skipped)
              _SummaryLine(
                label: bill.instance.name,
                detail: 'Skipped this cycle',
                amount: formatPeso(0),
                color: Colors.grey,
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
                  'The bills you chose cost more than this income. The '
                  'difference will come out of what was already in '
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
          const Text(
            'No unpaid bills right now, so there was nothing to pay from this.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  // ----------------------------------------------------------- buttons

  Widget _buildButtons(BuildContext context) {
    final back = switch (_step) {
      _Step.income => null,
      _Step.bills => _toIncomeStep,
      _Step.summary => _backFromSummary,
    };

    final next = switch (_step) {
      _Step.income => _fromIncomeStep,
      _Step.bills => _fromBillsStep,
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
            style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
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
                decoration: dialogFieldDecoration(
                  context,
                  'Pay now',
                  helper: 'Still owes ${formatPeso(bill.remaining)}',
                ).copyWith(prefixText: '₱ '),
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
  const _RunningTotal({required this.plan});

  final AllocationPlan plan;

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
              short ? 'Short by' : 'Left after these bills',
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
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
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
