import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/onboarding_data.dart';
import '../models/wallet.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../widgets/app_logo.dart';
import '../widgets/light_dark_toggle.dart';
import 'main_shell.dart';

/// First-time setup wizard: Welcome, Name, Reminders, Income & priorities,
/// Starting wallets, then a "You're ready" recap.
class FinancialSetupScreen extends StatefulWidget {
  const FinancialSetupScreen({
    this.initialName,
    this.saveOnboarding = UserProfileService.completeOnboarding,
    this.onFinished,
    super.key,
  });

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
  static const _remindersStep = 2;
  static const _incomeStep = 3;
  static const _walletsStep = 4;
  static const _readyStep = 5;

  /// Steps that show "Step X of 5"; the recap comes after them.
  static const _numberedSteps = 5;

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
  final _dailyBudgetController = TextEditingController();

  int _step = _welcomeStep;
  bool _notificationsEnabled = false;
  String? _incomeSource;
  String? _incomeFrequency;
  final List<FinancialPriority> _priorities = FinancialPriority.values.toList();
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
    _dailyBudgetController.dispose();
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

  void _chooseReminders(bool enabled) {
    _notificationsEnabled = enabled;
    _goTo(_incomeStep);
  }

  double? _parseAmount(String text) {
    return double.tryParse(text.trim().replaceAll(',', ''));
  }

  Future<void> _finish() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final dailyBudgetText = _dailyBudgetController.text.trim();
    final data = OnboardingData(
      name: _nameController.text.trim(),
      notificationsEnabled: _notificationsEnabled,
      incomeSource: _incomeSource!,
      incomeFrequency: _incomeFrequency!,
      income: _parseAmount(_incomeController.text),
      dailyBudget: dailyBudgetText.isEmpty
          ? null
          : _parseAmount(dailyBudgetText),
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
    final wallet = await showModalBottomSheet<WalletDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _AddWalletSheet(),
    );

    if (wallet == null || !mounted) return;

    setState(() {
      // The first wallet receives income until the user picks another.
      _wallets.add(wallet.copyWith(receivesIncome: _wallets.isEmpty));
      _showWalletError = false;
    });
  }

  void _removeWallet(int index) {
    setState(() {
      final removed = _wallets.removeAt(index);
      if (removed.receivesIncome && _wallets.isNotEmpty) {
        _wallets[0] = _wallets[0].copyWith(receivesIncome: true);
      }
    });
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
    final showProgress = _step < _readyStep;

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
      case _remindersStep:
        return _buildReminders();
      case _incomeStep:
        return _buildIncome();
      case _walletsStep:
        return _buildWallets();
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
      case _readyStep:
        return _primaryButton('Go to Dashboard', _finish, isLoading: _isSaving);
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
        _title('Welcome to FinAssist! 👋', center: true),
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
  // STEP 3 - REMINDERS
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
  // STEP 4 - INCOME & PRIORITIES
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
          const SizedBox(height: 20),
          _label('How often do you receive it?'),
          DropdownButtonFormField<String>(
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
          ],
          const SizedBox(height: 20),
          _label(
            isIrregular
                ? 'Rough monthly estimate (optional)'
                : 'Usual amount per pay',
          ),
          TextFormField(
            controller: _incomeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration('0.00', prefixText: '₱ '),
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
              "Just a guess is fine. You'll enter the real amount each time "
              'you get paid.',
            ),
          ],
          const SizedBox(height: 20),
          _label('Daily spending limit (optional)'),
          TextFormField(
            controller: _dailyBudgetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration('0.00', prefixText: '₱ '),
            validator: (value) {
              if ((value?.trim() ?? '').isEmpty) return null;
              final amount = _parseAmount(value!);
              return amount == null || amount <= 0
                  ? 'Enter a positive amount, or leave it blank.'
                  : null;
            },
          ),
          const SizedBox(height: 4),
          _noteRow(
            Icons.info_outline,
            "Not sure? Leave it blank. FinAssist will suggest a daily amount "
            'later.',
          ),
          const SizedBox(height: 24),
          _title('What matters most to you?', size: 18),
          const SizedBox(height: 6),
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
                              child: Icon(
                                Icons.drag_handle,
                                color: Colors.grey,
                              ),
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
      ),
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
              incomeSource: _incomeSource,
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

  Widget _buildReady() {
    final colors = context.appColors;
    final name = _nameController.text.trim();
    final income = _parseAmount(_incomeController.text);
    final incomeText = income == null
        ? 'Varies'
        : _incomeFrequency == 'Irregular'
        ? 'About ${formatPeso(income)} a month'
        : formatPeso(income);
    final dailyBudget = _parseAmount(_dailyBudgetController.text);
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
                '$incomeText · $frequencyLabel\n$_incomeSource',
              ),
              _summaryRow(
                'assets/icons/icons8-wallet-96.png',
                'Wallets',
                '${_wallets.length} wallet${_wallets.length == 1 ? '' : 's'}'
                    ' · ${formatPeso(walletTotal)} total',
              ),
              _summaryRow(
                'assets/icons/icons8-goal-96.png',
                'Top priority',
                _priorities.first.label,
              ),
              _summaryRow(
                'assets/icons/icons8-calendar-96.png',
                'Daily limit',
                dailyBudget == null ? 'Not set yet' : formatPeso(dailyBudget),
                showDivider: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
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

  Widget _primaryButton(
    String label,
    VoidCallback onPressed, {
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: appPrimaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: appPrimaryBlue.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
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

class _AddWalletSheet extends StatefulWidget {
  const _AddWalletSheet();

  @override
  State<_AddWalletSheet> createState() => _AddWalletSheetState();
}

class _AddWalletSheetState extends State<_AddWalletSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  WalletType _type = WalletType.cash;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    Navigator.pop(
      context,
      WalletDraft(
        type: _type,
        name: name.isEmpty ? _type.label : name,
        startingBalance: double.parse(
          _balanceController.text.trim().replaceAll(',', ''),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'New Wallet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Type',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in WalletType.values)
                      ChoiceChip(
                        avatar: Image.asset(
                          type.iconAsset,
                          width: 18,
                          height: 18,
                        ),
                        label: Text(type.label),
                        selected: type == _type,
                        showCheckmark: false,
                        selectedColor: appPrimaryBlue,
                        labelStyle: TextStyle(
                          color: type == _type ? Colors.white : colors.textBody,
                          fontWeight: type == _type
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Name (optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 30,
                  decoration: InputDecoration(
                    hintText: 'e.g. ${_type.label} or "BPI Savings"',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Current balance',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _balanceController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: '₱ ',
                    helperText: 'Enter 0 if this wallet is empty.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      (value ?? '').trim().replaceAll(',', ''),
                    );
                    return amount == null || amount < 0
                        ? 'Enter the balance, or 0 if empty.'
                        : null;
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appPrimaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Add Wallet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
