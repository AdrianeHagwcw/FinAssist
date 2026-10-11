import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/onboarding_data.dart';
import '../models/wallet.dart';
import '../models/goal.dart';
import '../widgets/bill_form_sheet.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/wallet_form_sheet.dart';
import '../services/reminder_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../widgets/app_logo.dart';
import '../widgets/light_dark_toggle.dart';
import 'main_shell.dart';

/// First-time setup wizard: Welcome, Name, Income, priorities, bills, savings,
/// wallets, reminders, then a "You're ready" recap.
class FinancialSetupScreen extends StatefulWidget {
  const FinancialSetupScreen({
    this.initialName,
    this.saveOnboarding = UserProfileService.completeOnboarding,
    this.onFinished,
    this.requestReminderPermission = ReminderService.requestPermission,
    super.key,
  });

  /// Asks Android to allow notifications when the user allows reminders.
  final Future<bool> Function() requestReminderPermission;

  /// Pre-fills the name step. Defaults to the signed-in user's display name.
  final String? initialName;

  /// Saves the answers. Tests pass a fake instead of Firebase.
  final Future<void> Function(OnboardingData data) saveOnboarding;

  /// Runs after saving. Defaults to opening the dashboard.
  final VoidCallback? onFinished;

  @override
  State<FinancialSetupScreen> createState() => _FinancialSetupScreenState();
}

class _FinancialSetupScreenState extends State<FinancialSetupScreen> {
  static const _welcomeStep = 0;
  static const _nameStep = 1;
  static const _incomeStep = 2;
  static const _planStep = 3;
  static const _billsStep = 4;
  static const _savingsStep = 5;
  static const _walletsStep = 6;
  static const _remindersStep = 7;
  static const _reviewStep = 8;
  static const _readyStep = 9;

  /// Main setup steps; reminder permission is an optional interstitial.
  static const _numberedSteps = 9;

  static const _incomeSources = [
    'Allowance',
    'Salary',
    'Part-time Job',
    'Business',
    'Freelance',
    'Other',
  ];

  // Stored value -> label shown in the dropdown.
  static const _incomeFrequencies = {
    'Weekly': 'Weekly',
    'Bi-weekly': 'Every 2 weeks',
    'Semi-monthly': 'Twice a month (15th & 30th)',
    'Monthly': 'Monthly',
    'Irregular': 'Irregular (no fixed payday)',
  };

  final _nameFormKey = GlobalKey<FormState>();
  final _incomeFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _incomeController = TextEditingController();
  final _otherIncomeSourceController = TextEditingController();

  int _step = _welcomeStep;
  bool _notificationsEnabled = false;
  String? _incomeSource;
  String? _incomeFrequency;

  String get _resolvedIncomeSource {
    if (_incomeSource == 'Other') {
      return _otherIncomeSourceController.text.trim();
    }
    return _incomeSource ?? 'income';
  }

  /// The day the user last got paid. It anchors the first pay period, so the
  /// days left on Home are right as soon as setup is finished.
  DateTime? _lastPaydayAt;
  final List<FinancialPriority> _priorities = FinancialPriority.values.toList();
  final List<OnboardingBill> _onboardingBills = [];
  final List<OnboardingSavingsAccount> _onboardingSavingsAccounts = [];
  final List<OnboardingGoal> _onboardingGoals = [];
  final List<WalletDraft> _wallets = [];
  bool _showWalletError = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = (widget.initialName ?? _signedInName()).trim();
  }

  String _signedInName() {
    try {
      return FirebaseAuth.instance.currentUser?.displayName ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _incomeController.dispose();
    _otherIncomeSourceController.dispose();
    super.dispose();
  }

  // =========================================================
  // NAVIGATION BETWEEN STEPS
  // =========================================================

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
  }

  void _next() {
    switch (_step) {
      case _nameStep:
        if (!_nameFormKey.currentState!.validate()) return;
      case _incomeStep:
        if (!_incomeFormKey.currentState!.validate()) return;
      case _walletsStep:
        if (_wallets.isEmpty) {
          setState(() => _showWalletError = true);
          return;
        }
    }
    _goTo(_step + 1);
  }

  Future<void> _chooseReminders(bool enabled) async {
    // Android asks here, right after the user said yes, so the question makes
    // sense. Saying no to Android keeps reminders off rather than pretending.
    _notificationsEnabled = enabled && await widget.requestReminderPermission();
    if (!mounted) return;
    _goTo(_reviewStep);
  }

  double? _parseAmount(String text) {
    return double.tryParse(text.trim().replaceAll(',', ''));
  }

  Future<void> _finish() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final data = OnboardingData(
      name: _nameController.text.trim(),
      notificationsEnabled: _notificationsEnabled,
      incomeSource: _resolvedIncomeSource,
      incomeFrequency: _incomeFrequency!,
      lastPaydayAt: _lastPaydayAt,
      monthlyIncome: _parseAmount(_incomeController.text),
      bills: List.unmodifiable(_onboardingBills),
      savingsAccounts: List.unmodifiable(_onboardingSavingsAccounts),
      goals: List.unmodifiable(_onboardingGoals),
      priorities: List.unmodifiable(_priorities),
      wallets: List.unmodifiable(_wallets),
    );

    try {
      await widget.saveOnboarding(data);
      if (!mounted) return;

      if (widget.onFinished != null) {
        widget.onFinished!();
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainShell()),
          (route) => false,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('We could not save your setup. Please try again.'),
          ),
        );
    }
  }

  // =========================================================
  // WALLETS
  // =========================================================

  Future<void> _addWallet() async {
    final wallet = await showWalletFormSheet(context, balanceOptional: true);

    if (wallet == null || !mounted) return;

    setState(() {
      // The first wallet receives income until the user picks another.
      _wallets.add(wallet.copyWith(receivesIncome: _wallets.isEmpty));
      _numberRepeatedWallets();
      _showWalletError = false;
    });
  }

  void _removeWallet(int index) {
    setState(() {
      final removed = _wallets.removeAt(index);
      if (removed.receivesIncome && _wallets.isNotEmpty) {
        _wallets[0] = _wallets[0].copyWith(receivesIncome: true);
      }
      _numberRepeatedWallets();
    });
  }

  /// Two wallets of the same name are impossible to tell apart in a list, so
  /// repeats are numbered in the order they were added: "BPI 1", "BPI 2".
  /// A name used only once keeps its plain form, including after a delete.
  void _numberRepeatedWallets() {
    final counts = <String, int>{};
    for (final wallet in _wallets) {
      final base = _baseWalletName(wallet.name);
      counts[base] = (counts[base] ?? 0) + 1;
    }

    final used = <String, int>{};
    for (var i = 0; i < _wallets.length; i++) {
      final base = _baseWalletName(_wallets[i].name);
      if (counts[base] == 1) {
        _wallets[i] = _wallets[i].copyWith(name: base);
        continue;
      }
      final position = (used[base] ?? 0) + 1;
      used[base] = position;
      _wallets[i] = _wallets[i].copyWith(name: '$base $position');
    }
  }

  /// The name without a number this screen added, so renumbering stays stable.
  String _baseWalletName(String name) {
    final trimmed = name.trim();
    final match = RegExp(r'^(.*?)\s+\d+$').firstMatch(trimmed);
    return match == null ? trimmed : match.group(1)!.trim();
  }

  void _setIncomeWallet(int index) {
    setState(() {
      for (var i = 0; i < _wallets.length; i++) {
        _wallets[i] = _wallets[i].copyWith(receivesIncome: i == index);
      }
    });
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return PopScope(
      // Android back goes to the previous step instead of leaving setup.
      canPop: _step == _welcomeStep,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSaving) _goTo(_step - 1);
      },
      child: Scaffold(
        backgroundColor: colors.card,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  // A new key per step starts each step scrolled to the top.
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: _buildStep(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: _buildActions(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colors = context.appColors;
    final showProgress = _step <= _walletsStep;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 48,
                child: _step > _welcomeStep && !_isSaving
                    ? IconButton(
                        tooltip: 'Back',
                        icon: Icon(Icons.arrow_back, color: colors.textBody),
                        onPressed: () => _goTo(_step - 1),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  showProgress ? 'Step ${_step + 1} of $_numberedSteps' : '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 48, child: LightDarkIconButton()),
            ],
          ),
          if (showProgress)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (_step + 1) / _numberedSteps,
                  minHeight: 6,
                  backgroundColor: colors.track,
                  color: appPrimaryBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _welcomeStep:
        return _buildWelcome();
      case _nameStep:
        return _buildName();
      case _incomeStep:
        return _buildIncome();
      case _planStep:
        return _buildPlan();
      case _billsStep:
        return _buildBillsPlan();
      case _savingsStep:
        return _buildSavingsPlan();
      case _walletsStep:
        return _buildWallets();
      case _remindersStep:
        return _buildReminders();
      case _reviewStep:
        return _buildReview();
      default:
        return _buildReady();
    }
  }

  Widget _buildActions() {
    switch (_step) {
      case _welcomeStep:
        return _primaryButton('Get Started', _next);
      case _remindersStep:
        return Column(
          children: [
            _primaryButton('Allow Reminders', () => _chooseReminders(true)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _chooseReminders(false),
              child: Text(
                'Skip for now',
                style: TextStyle(color: context.appColors.primaryText),
              ),
            ),
          ],
        );
      case _reviewStep:
        return _primaryButton('Continue', _next);
      case _readyStep:
        return _primaryButton(
          'Go to Dashboard',
          _finish,
          isLoading: _isSaving,
          confirm: true,
        );
      default:
        return _primaryButton('Next', _next);
    }
  }

  // =========================================================
  // STEP 1 - WELCOME
  // =========================================================

  Widget _buildWelcome() {
    return Column(
      children: [
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: const AppLogo(
            width: 240,
            height: 160,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
        const SizedBox(height: 20),
        _title('Welcome to FinAssist!', center: true),
        const SizedBox(height: 8),
        _subtitle(
          "Let's set up your personal budget. It only takes a minute.",
          center: true,
        ),
        const SizedBox(height: 28),
        _featureRow(
          'assets/icons/icons8-wallet-96.png',
          'Keep track of your wallets and balances',
        ),
        _featureRow(
          'assets/icons/icons8-expenses-64.png',
          'Record what you spend',
        ),
        _featureRow(
          'assets/icons/icons8-money-box-96.png',
          'Plan for bills and savings',
        ),
      ],
    );
  }

  // =========================================================
  // STEP 2 - NAME
  // =========================================================

  Widget _buildName() {
    return Form(
      key: _nameFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _title('What should we call you?'),
          const SizedBox(height: 8),
          _subtitle("We'll use your name to greet you."),
          const SizedBox(height: 28),
          _label('Your name'),
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 40,
            onFieldSubmitted: (_) => _next(),
            decoration: _inputDecoration('e.g. Dave'),
            validator: (value) => (value?.trim() ?? '').isEmpty
                ? 'Please enter your name.'
                : null,
          ),
          const SizedBox(height: 4),
          _noteRow(Icons.lock_outline, 'Only you can see your profile.'),
        ],
      ),
    );
  }

  // =========================================================
  // OPTIONAL REMINDER PERMISSION
  // =========================================================

  Widget _buildReminders() {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('Never miss a bill'),
        const SizedBox(height: 8),
        _subtitle('FinAssist can remind you before a bill is due, like this:'),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.pageBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Image.asset('assets/icons/icons8-bell-96.png'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FinAssist · now',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Electricity bill is due tomorrow',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatPeso(1850)} · Tap to mark as paid',
                      style: TextStyle(fontSize: 13, color: colors.textBody),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _noteRow(
          Icons.cloud_off_outlined,
          'Reminders come from your phone, so they work even without internet.',
        ),
        _noteRow(
          Icons.info_outline,
          "Android will ask for permission when reminders are switched on. "
          'You can change your choice later.',
        ),
      ],
    );
  }

  // =========================================================
  // STEP 3 - INCOME
  // =========================================================

  Widget _buildIncome() {
    final colors = context.appColors;
    final isIrregular = _incomeFrequency == 'Irregular';

    return Form(
      key: _incomeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _title('Your income'),
          const SizedBox(height: 8),
          _subtitle('This helps FinAssist plan your money each pay period.'),
          const SizedBox(height: 24),
          _label('Main source of income'),
          DropdownButtonFormField<String>(
            key: const Key('income-source-dropdown'),
            initialValue: _incomeSource,
            isExpanded: true,
            decoration: _inputDecoration('Select your income source'),
            items: _incomeSources
                .map(
                  (source) => DropdownMenuItem(
                    value: source,
                    child: Text(source, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _incomeSource = value),
            validator: (value) =>
                value == null ? 'Select an income source.' : null,
          ),
          if (_incomeSource == 'Other') ...[
            const SizedBox(height: 16),
            _label('Please specify your income source'),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('other-income-source-specification'),
              controller: _otherIncomeSourceController,
              textCapitalization: TextCapitalization.sentences,
              decoration: _inputDecoration('e.g. Rental income'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Please specify your income source.'
                  : null,
            ),
          ],
          const SizedBox(height: 20),
          _label('How often do you receive it?'),
          DropdownButtonFormField<String>(
            key: const Key('income-frequency-dropdown'),
            initialValue: _incomeFrequency,
            isExpanded: true,
            decoration: _inputDecoration('Select how often'),
            items: _incomeFrequencies.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _incomeFrequency = value),
            validator: (value) =>
                value == null ? 'Select how often you receive income.' : null,
          ),
          if (isIrregular) ...[
            const SizedBox(height: 8),
            _noteRow(
              Icons.lightbulb_outline,
              "No fixed payday? No problem. Each time you add income, you'll "
              'choose how long it should last.',
            ),
          ] else ...[
            const SizedBox(height: 20),
            _label('When did you last receive it?'),
            FormField<DateTime>(
              initialValue: _lastPaydayAt,
              validator: (_) =>
                  _incomeFrequency == null || _lastPaydayAt != null
                  ? null
                  : 'Choose the day your last pay came in.',
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    key: const Key('last-payday'),
                    onTap: () async {
                      final today = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _lastPaydayAt ?? today,
                        firstDate: DateTime(today.year - 1),
                        lastDate: today,
                        helpText: 'When did you last get paid?',
                      );
                      if (picked == null) return;
                      setState(() => _lastPaydayAt = picked);
                      field.didChange(picked);
                    },
                    child: InputDecorator(
                      decoration: _inputDecoration(
                        'Select the date',
                      ).copyWith(errorText: field.errorText),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _lastPaydayAt == null
                                  ? 'Select the date'
                                  : formatShortDate(_lastPaydayAt!),
                              style: TextStyle(
                                color: _lastPaydayAt == null
                                    ? colors.textBody
                                    : colors.textPrimary,
                              ),
                            ),
                          ),
                          Image.asset(
                            'assets/icons/icons8-calendar-96.png',
                            width: 22,
                            height: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _noteRow(
                    Icons.info_outline,
                    'Your pay period is counted from this day, so Home can '
                    'show how many days it still has to last.',
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _label(
            isIrregular
                ? 'Estimated monthly income (optional)'
                : 'Monthly income',
          ),
          TextFormField(
            key: const Key('monthly-income'),
            controller: _incomeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration(
              isIrregular ? 'Optional estimate' : 'Total for a typical month',
              prefixText: '₱ ',
            ),
            validator: (value) {
              // Irregular income changes, so the estimate may be left blank.
              if (isIrregular && (value?.trim() ?? '').isEmpty) return null;
              final amount = _parseAmount(value ?? '');
              if (amount == null || amount <= 0) {
                return isIrregular
                    ? 'Enter a positive amount, or leave it blank.'
                    : 'Enter a valid positive amount.';
              }
              return null;
            },
          ),
          if (isIrregular) ...[
            const SizedBox(height: 4),
            _noteRow(
              Icons.info_outline,
              "A rough monthly estimate is fine. You'll enter the real amount "
              'each time you get paid.',
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================
  // STEP 4 - PRIORITIES
  // =========================================================

  Widget _buildPlan() {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('What matters most to you?'),
        const SizedBox(height: 8),
        _subtitle('Set the priorities that will guide your financial plan.'),
        const SizedBox(height: 16),
        _subtitle(
          'Use the arrows, or hold and drag, to put the most important '
          'first.',
        ),
        const SizedBox(height: 12),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: _movePriority,
          children: [
            for (var index = 0; index < _priorities.length; index++)
              Padding(
                key: ValueKey(_priorities[index]),
                padding: const EdgeInsets.only(bottom: 8),
                // Long-press anywhere on the row to drag it.
                child: ReorderableDelayedDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                    decoration: BoxDecoration(
                      color: colors.pageBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: colors.primaryTint,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colors.primaryText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _priorities[index].label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        _moveButton(
                          icon: Icons.keyboard_arrow_up,
                          tooltip: 'Move "${_priorities[index].label}" up',
                          onPressed: index == 0
                              ? null
                              : () => _movePriority(index, index - 1),
                        ),
                        _moveButton(
                          icon: Icons.keyboard_arrow_down,
                          tooltip: 'Move "${_priorities[index].label}" down',
                          onPressed: index == _priorities.length - 1
                              ? null
                              : () => _movePriority(index, index + 1),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // STEP 5 - BILL REMINDERS

  Future<void> _addOnboardingBill() async {
    OnboardingBill? draft;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => BillFormSheet(
        wallets: Stream.value(const <Wallet>[]),
        onSave:
            ({
              required name,
              required amount,
              required category,
              required firstDueDate,
              required recurrence,
              String? walletId,
            }) {
              draft = OnboardingBill(
                name: name.trim(),
                amount: amount,
                category: category,
                firstDueDate: firstDueDate,
                recurrence: recurrence,
              );
            },
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _onboardingBills.add(draft!));
  }

  void _removeOnboardingBill(int index) {
    setState(() => _onboardingBills.removeAt(index));
  }

  Future<void> _addOnboardingSavingsAccount() async {
    final account = await showModalBottomSheet<OnboardingSavingsAccount>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _OnboardingSavingsSheet(),
    );
    if (account == null || !mounted) return;
    setState(() => _onboardingSavingsAccounts.add(account));
  }

  Future<void> _addOnboardingGoal() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GoalFormSheet(
        nextPriority: _onboardingGoals.length,
        allowAlreadySaved: false,
        wallets: Stream.value(const <Wallet>[]),
        onSave: (draft) {
          _onboardingGoals.add(
            OnboardingGoal(
              name: draft.name,
              kind: draft.kind,
              targetAmount: draft.targetAmount,
              targetDate: draft.targetDate,
              frequency: draft.frequency,
              planAmount: draft.planAmount,
              note: draft.note,
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildBillsPlan() {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('Add bill reminders'),
        const SizedBox(height: 8),
        _subtitle(
          'Add any existing bills with their due dates and amounts. '
          'You can skip this and add bills later.',
        ),
        const SizedBox(height: 20),
        if (_onboardingBills.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: colors.pageBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              'No bills added yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textBody),
            ),
          )
        else
          for (var index = 0; index < _onboardingBills.length; index++)
            Card(
              key: ValueKey('onboarding-bill-$index'),
              color: colors.pageBackground,
              child: ListTile(
                title: Text(_onboardingBills[index].name),
                subtitle: Text(
                  '${formatPeso(_onboardingBills[index].amount)} · '
                  'Due ${formatShortDate(_onboardingBills[index].firstDueDate)} · '
                  '${_onboardingBills[index].recurrence.label}',
                ),
                trailing: IconButton(
                  key: Key('remove-onboarding-bill-$index'),
                  tooltip: 'Remove ${_onboardingBills[index].name}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeOnboardingBill(index),
                ),
              ),
            ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            key: const Key('add-onboarding-bill'),
            onPressed: _addOnboardingBill,
            icon: const Icon(Icons.add),
            label: const Text('Add a Bill'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.primaryText,
              side: BorderSide(color: colors.primaryText),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // STEP 6 - SAVINGS

  Widget _buildSavingsPlan() {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('Build your savings'),
        const SizedBox(height: 8),
        _subtitle(
          'Add savings accounts or set a goal. You can do either now or later.',
        ),
        const SizedBox(height: 20),
        for (final (index, account) in _onboardingSavingsAccounts.indexed)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(account.kind.icon, color: colors.primaryText),
              title: Text(account.name),
              subtitle: Text(account.kind.label),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatPeso(account.balance)),
                  IconButton(
                    tooltip: 'Remove ${account.name}',
                    onPressed: () => setState(
                      () => _onboardingSavingsAccounts.removeAt(index),
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        if (_onboardingGoals.isNotEmpty) ...[
          const SizedBox(height: 8),
          _label('Savings goals'),
          for (final (index, goal) in _onboardingGoals.indexed)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(goal.kind.icon, color: colors.primaryText),
                title: Text(goal.name),
                subtitle: Text(goal.kind.label),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatPeso(goal.targetAmount)),
                    IconButton(
                      tooltip: 'Remove ${goal.name}',
                      onPressed: () =>
                          setState(() => _onboardingGoals.removeAt(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            key: const Key('add-onboarding-savings-account'),
            onPressed: _addOnboardingSavingsAccount,
            icon: const Icon(Icons.add),
            label: const Text('Add Savings'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            key: const Key('add-onboarding-goal'),
            onPressed: _addOnboardingGoal,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Add Goal'),
          ),
        ),
      ],
    );
  }

  void _movePriority(int oldIndex, int newIndex) {
    setState(() {
      _priorities.insert(newIndex, _priorities.removeAt(oldIndex));
    });
  }

  Widget _moveButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      color: context.appColors.primaryText,
      disabledColor: context.appColors.border,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }

  // =========================================================
  // STEP 5 - STARTING WALLETS
  // =========================================================

  Widget _buildWallets() {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('Your starting wallets'),
        const SizedBox(height: 8),
        _subtitle(
          'Add where your money is right now, like cash on hand or your GCash '
          'balance.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.primaryTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/icons/icons8-shield-96.png',
                width: 20,
                height: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "FinAssist isn't connected to your bank or e-wallet. You enter "
                  'balances yourself, and no money is ever moved.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.textBody,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_wallets.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: colors.pageBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                Image.asset(
                  'assets/icons/icons8-wallet-96.png',
                  width: 40,
                  height: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  'No wallets yet',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Add at least one wallet to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          )
        else
          for (var index = 0; index < _wallets.length; index++)
            _WalletDraftCard(
              wallet: _wallets[index],
              incomeSource: _resolvedIncomeSource,
              onRemove: () => _removeWallet(index),
              onSetIncome: () => _setIncomeWallet(index),
            ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _addWallet,
            icon: const Icon(Icons.add),
            label: Text(_wallets.isEmpty ? 'Add a Wallet' : 'Add Another'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.primaryText,
              side: BorderSide(color: colors.primaryText),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        if (_showWalletError) ...[
          const SizedBox(height: 10),
          const Text(
            'Please add at least one wallet.',
            style: TextStyle(color: Colors.red),
          ),
        ],
      ],
    );
  }

  // =========================================================
  // RECAP - YOU'RE READY
  // =========================================================

  // =========================================================
  // STEP 9 - REVIEW
  // =========================================================

  /// A last look before anything is saved. Each line jumps back to the step
  /// that set it, so a wrong answer is two taps from being fixed.
  Widget _buildReview() {
    final income = _parseAmount(_incomeController.text);
    final incomeText = income == null
        ? 'Not set'
        : _incomeFrequency == 'Irregular'
        ? 'About ${formatPeso(income)} a month'
        : formatPeso(income);
    final walletTotal = _wallets.fold<double>(
      0,
      (total, wallet) => total + wallet.startingBalance,
    );
    final billsTotal = _onboardingBills.fold<double>(
      0,
      (total, bill) => total + bill.amount,
    );
    String plural(int count, String word) =>
        '$count $word${count == 1 ? '' : 's'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('Check your answers'),
        const SizedBox(height: 8),
        _subtitle(
          'Nothing is saved yet. Tap Edit on anything that is wrong, then '
          'come back here.',
        ),
        const SizedBox(height: 20),
        _reviewRow('Your name', _nameController.text.trim(), _nameStep),
        _reviewRow(
          'Income',
          '$incomeText · ${_incomeFrequencies[_incomeFrequency] ?? 'Not set'}\n'
          '$_resolvedIncomeSource',
          _incomeStep,
        ),
        _reviewRow(
          'Last payday',
          _lastPaydayAt == null ? 'Not set' : formatShortDate(_lastPaydayAt!),
          _incomeStep,
        ),
        _reviewRow('What matters most', _priorities.first.label, _planStep),
        _reviewRow(
          'Bills',
          _onboardingBills.isEmpty
              ? 'None added'
              : '${plural(_onboardingBills.length, 'bill')} · '
                    '${formatPeso(billsTotal)}',
          _billsStep,
        ),
        _reviewRow(
          'Savings',
          '${plural(_onboardingSavingsAccounts.length, 'account')} · '
          '${plural(_onboardingGoals.length, 'goal')}',
          _savingsStep,
        ),
        _reviewRow(
          'Wallets',
          _wallets.isEmpty
              ? 'None added'
              : '${plural(_wallets.length, 'wallet')} · '
                    '${formatPeso(walletTotal)} total',
          _walletsStep,
        ),
        _reviewRow(
          'Bill reminders',
          _notificationsEnabled ? 'On' : 'Off',
          _remindersStep,
        ),
      ],
    );
  }

  /// One answer, with the way back to the step that set it.
  Widget _reviewRow(String label, String value, int step) {
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? 'Not set' : value,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _goTo(step),
            child: Text('Edit', style: TextStyle(color: colors.primaryText)),
          ),
        ],
      ),
    );
  }

  Widget _buildReady() {
    final colors = context.appColors;
    final name = _nameController.text.trim();
    final income = _parseAmount(_incomeController.text);
    final incomeText = income == null
        ? 'Varies'
        : _incomeFrequency == 'Irregular'
        ? 'About ${formatPeso(income)} a month'
        : '${formatPeso(income)} a month';
    final walletTotal = _wallets.fold<double>(
      0,
      (total, wallet) => total + wallet.startingBalance,
    );
    final frequencyLabel = _incomeFrequencies[_incomeFrequency] ?? '';

    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: colors.successTint,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(18),
          child: Image.asset('assets/icons/icons8-verified-96.png'),
        ),
        const SizedBox(height: 20),
        _title("You're ready, $name!", center: true),
        const SizedBox(height: 8),
        _subtitle("Here's your setup. You can change it later.", center: true),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.pageBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              _summaryRow(
                'assets/icons/icons8-banknotes-96.png',
                'Income',
                '$incomeText · $frequencyLabel\n$_resolvedIncomeSource',
              ),
              _summaryRow(
                'assets/icons/icons8-wallet-96.png',
                'Wallets',
                '${_wallets.length} wallet${_wallets.length == 1 ? '' : 's'}'
                    ' · ${formatPeso(walletTotal)} total',
              ),
              _summaryRow(
                'assets/icons/icons8-expenses-64.png',
                'Bills',
                _onboardingBills.isEmpty
                    ? 'No bill reminders added'
                    : '${_onboardingBills.length} bill reminder${_onboardingBills.length == 1 ? '' : 's'}',
              ),
              _summaryRow(
                'assets/icons/icons8-goal-96.png',
                'Savings',
                '${_onboardingSavingsAccounts.length} account${_onboardingSavingsAccounts.length == 1 ? '' : 's'}'
                    ' · ${_onboardingGoals.length} goal${_onboardingGoals.length == 1 ? '' : 's'}',
              ),
              _summaryRow(
                'assets/icons/icons8-goal-96.png',
                'Top priority',
                _priorities.first.label,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.primaryTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: colors.primaryText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'After you tap Go to Dashboard, these shortcuts will be '
                  'available there:',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _featureRow(
          'assets/icons/icons8-money-transfer-96.png',
          'Tap + anytime to add an expense or income',
        ),
        _featureRow(
          'assets/icons/icons8-combo-chart-100.png',
          'See where your money goes in Reports',
        ),
      ],
    );
  }

  // =========================================================
  // SMALL BUILDING BLOCKS
  // =========================================================

  /// [confirm] marks the button that finishes setup. The steps before it
  /// only move forward, so they stay blue.
  Widget _primaryButton(
    String label,
    VoidCallback onPressed, {
    bool isLoading = false,
    bool confirm = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: confirm ? confirmButtonStyle() : openButtonStyle(),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _title(String text, {bool center = false, double size = 24}) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: context.appColors.textPrimary,
      ),
    );
  }

  Widget _subtitle(String text, {bool center = false}) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: const TextStyle(fontSize: 15, color: Colors.grey, height: 1.4),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _featureRow(String iconAsset, String text) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.primaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(iconAsset),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: colors.textBody),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String iconAsset,
    String label,
    String value, {
    bool showDivider = true,
  }) {
    final colors = context.appColors;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(iconAsset, width: 20, height: 20),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        if (showDivider) Divider(height: 24, color: colors.border),
      ],
    );
  }

  InputDecoration _inputDecoration(String hintText, {String? prefixText}) {
    return InputDecoration(
      hintText: hintText,
      prefixText: prefixText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: appPrimaryBlue, width: 2),
      ),
    );
  }
}

class _OnboardingSavingsSheet extends StatefulWidget {
  const _OnboardingSavingsSheet();

  @override
  State<_OnboardingSavingsSheet> createState() =>
      _OnboardingSavingsSheetState();
}

class _OnboardingSavingsSheetState extends State<_OnboardingSavingsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  GoalKind _kind = GoalKind.emergencyFund;

  static const _savingsKinds = [
    GoalKind.emergencyFund,
    GoalKind.savingsAccount,
    GoalKind.timeDeposit,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  double? _parseBalance(String value) =>
      double.tryParse(value.trim().replaceAll(',', ''));

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final balance = _balanceController.text.trim().isEmpty
        ? 0.0
        : _parseBalance(_balanceController.text)!;
    Navigator.pop(
      context,
      OnboardingSavingsAccount(
        name: name.isEmpty ? _kind.label : name,
        kind: _kind,
        balance: balance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Savings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<GoalKind>(
                key: const Key('onboarding-savings-kind'),
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Savings type'),
                items: _savingsKinds
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(kind.label),
                      ),
                    )
                    .toList(),
                onChanged: (kind) {
                  if (kind != null) setState(() => _kind = kind);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('onboarding-savings-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                  hintText: 'Uses the savings type if left blank',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('onboarding-savings-balance'),
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Current balance (optional)',
                  prefixText: '₱ ',
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) return null;
                  final amount = _parseBalance(value!);
                  if (amount == null || !amount.isFinite || amount < 0) {
                    return 'Enter a valid balance.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('save-onboarding-savings'),
                  onPressed: _save,
                  child: const Text('Add Savings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================
// WALLET CARD (ONBOARDING)
// =========================================================

class _WalletDraftCard extends StatelessWidget {
  const _WalletDraftCard({
    required this.wallet,
    required this.incomeSource,
    required this.onRemove,
    required this.onSetIncome,
  });

  final WalletDraft wallet;
  final String? incomeSource;
  final VoidCallback onRemove;
  final VoidCallback onSetIncome;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final incomeLabel = 'Receives my ${incomeSource ?? 'income'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 6),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: wallet.receivesIncome ? colors.primaryText : colors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(9),
                child: Image.asset(wallet.type.iconAsset),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wallet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      wallet.type.label,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Text(
                formatPeso(wallet.startingBalance),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              IconButton(
                tooltip: 'Remove ${wallet.name}',
                icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                onPressed: onRemove,
              ),
            ],
          ),
          Semantics(
            button: true,
            selected: wallet.receivesIncome,
            label: incomeLabel,
            excludeSemantics: true,
            child: InkWell(
              onTap: onSetIncome,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      wallet.receivesIncome
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: wallet.receivesIncome
                          ? colors.primaryText
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      incomeLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: wallet.receivesIncome
                            ? colors.primaryText
                            : Colors.grey,
                        fontWeight: wallet.receivesIncome
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// ADD WALLET SHEET
// =========================================================
