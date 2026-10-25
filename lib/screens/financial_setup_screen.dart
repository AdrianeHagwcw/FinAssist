import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/amount_input_formatter.dart';
import '../models/bill.dart';
import '../models/onboarding_data.dart';
import '../models/goal.dart';
import '../models/reminder.dart';
import '../models/wallet.dart';
import '../widgets/bill_form_sheet.dart';
import '../widgets/category_icon.dart';
import '../widgets/check_after_save.dart';
import '../widgets/goal_funding_picker.dart';
import '../widgets/goal_progress.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/item_card.dart';
import '../widgets/savings_form_parts.dart';
import '../widgets/savings_guide.dart';
import '../widgets/wallet_form_sheet.dart';
import '../services/reminder_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../utils/text_limits.dart';
import '../utils/unique_name.dart';
import '../widgets/app_logo.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/light_dark_toggle.dart';
import 'main_shell.dart';

/// The label on every green button in setup, matching the wallet and bill
/// sheets' save buttons.
const _saveLabelStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);

/// First-time setup wizard: Welcome, Name, then what the user has (wallets,
/// their cash summary, savings), what they owe (bills), what they are saving
/// for (goals), reminders, the reminder ranking when reminders are allowed,
/// review, and a "You're ready" recap. Wallets come before anything that
/// uses them.
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

class _FinancialSetupScreenState extends State<FinancialSetupScreen>
    with CheckAfterSave {
  // Have, then owe, then saving for: wallets first, since the cash summary
  // adds them up and goals set money aside from them. The ranking only picks
  // reminders, so it comes after reminders are allowed, and not at all when
  // they are not.
  static const _welcomeStep = 0;
  static const _nameStep = 1;
  static const _walletsStep = 2;
  static const _cashSummaryStep = 3;
  static const _savingsStep = 4;
  static const _billsStep = 5;
  static const _goalsStep = 6;
  static const _remindersStep = 7;
  static const _planStep = 8;
  static const _reviewStep = 9;
  static const _readyStep = 10;

  final _nameFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  int _step = _welcomeStep;
  bool _notificationsEnabled = false;

  /// Set once the user answers the reminders question.
  bool _remindersAnswered = false;

  /// True while a step was opened with Edit on the Review screen. That step
  /// then says "Back to Review" and returns there, instead of walking the
  /// user through every step after it. Arriving on Review clears it.
  bool _editingFromReview = false;

  /// The Review row last edited and what it said before, so Review can mark
  /// it "Updated" only when the answer really changed.
  int? _editedStep;
  String? _editedValueBefore;

  /// Every answer as it was when the pencil was tapped, so the back arrow
  /// can cancel the edit, including what it changed elsewhere (removing a
  /// wallet also trims goals funded from it).
  _SetupAnswers? _beforeEdit;

  /// Whether the reminder ranking is one of the steps. Until reminders are
  /// answered it counts, so the step total never shrinks then grows back.
  bool get _asksPriorities => !_remindersAnswered || _notificationsEnabled;

  /// How many numbered steps there are: 10, or 9 without the ranking.
  int get _numberedSteps => _asksPriorities ? 10 : 9;

  /// The number shown for the current step, counting only steps asked.
  int get _stepNumber =>
      !_asksPriorities && _step > _planStep ? _step : _step + 1;

  /// The step Back returns to. With reminders off, Review goes back to the
  /// reminders question, past the ranking that was never asked.
  int get _previousStep => _step == _reviewStep && !_notificationsEnabled
      ? _remindersStep
      : _step - 1;
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
    _nameController.text = cleanText(widget.initialName ?? _signedInName());
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
    super.dispose();
  }

  // =========================================================
  // NAVIGATION BETWEEN STEPS
  // =========================================================

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      if (step == _reviewStep) {
        _editingFromReview = false;
        _beforeEdit = null;
      }
    });
  }

  /// Whether the current step's answers can be left: a name, and at least
  /// one wallet. Shows what is missing when not.
  bool _stepIsComplete() {
    switch (_step) {
      case _nameStep:
        return checkForm(_nameFormKey);
      case _walletsStep:
        if (_wallets.isEmpty) {
          setState(() => _showWalletError = true);
          return false;
        }
    }
    return true;
  }

  void _next() {
    if (!_stepIsComplete()) return;
    _goTo(_editingFromReview ? _reviewStep : _step + 1);
  }

  /// Back: while editing from Review it cancels the edit; otherwise it goes
  /// to the step before.
  void _goBack() {
    if (_editingFromReview) {
      _cancelEdit();
      return;
    }
    _goTo(_previousStep);
  }

  /// Opens a step from Review to fix one answer, remembering every answer
  /// so the edit can be cancelled.
  void _editFromReview(int step, String valueBefore) {
    _editingFromReview = true;
    _editedStep = step;
    _editedValueBefore = valueBefore;
    _beforeEdit = _SetupAnswers.of(this);
    _goTo(step);
  }

  /// Leaves an edit without keeping it. Asks first when something changed,
  /// so a slip of the thumb never throws work away.
  Future<void> _cancelEdit() async {
    final before = _beforeEdit;
    if (before != null && !before.sameAs(_SetupAnswers.of(this))) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: dialogShape,
          title: const Text('Discard your changes?'),
          content: Text(
            "What you changed here won't be kept. Your answers go back to "
            'how they were.',
            style: TextStyle(color: context.appColors.textBody, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: appPrimaryBlue,
                minimumSize: const Size(64, 44),
              ),
              child: const Text(
                'Keep Editing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: dangerButtonStyle(height: 44),
              child: const Text(
                'Discard',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      before.restoreTo(this);
    }
    _showWalletError = false;
    _goTo(_reviewStep);
  }

  List<WalletDraft> get _bankAndEWalletDrafts => _wallets
      .where(
        (wallet) =>
            wallet.type == WalletType.bank ||
            wallet.type == WalletType.gcash ||
            wallet.type == WalletType.maya ||
            wallet.type == WalletType.ewallet,
      )
      .toList(growable: false);

  /// What the setup goals hold in [wallet].
  double _goalMoneyIn(WalletDraft wallet) {
    final id = wallet.id ?? 'setup-${_wallets.indexOf(wallet)}';
    return goalMoneyInWallet(_onboardingGoalsAsGoals(), id);
  }

  /// What can be spent from [wallet]: its balance less what goals hold in
  /// it. Nothing for a balance not entered.
  double _availableIn(WalletDraft wallet) => wallet.balanceRecorded
      ? (wallet.startingBalance - _goalMoneyIn(wallet))
            .clamp(0.0, double.infinity)
            .toDouble()
      : 0;

  /// What [wallets] have to spend together. Every total in setup says this,
  /// as Home does: money set aside for a goal is not spending money.
  double _availableTotal(Iterable<WalletDraft> wallets) =>
      wallets.fold<double>(0, (total, wallet) => total + _availableIn(wallet));

  /// The sheet behind a Cash Summary line: what it adds up to, then the
  /// wallets in it, so the figure can be checked one by one. Cash on Hand,
  /// Cash in Bank and the total all open one.
  Future<void> _showSummarySheet({
    required String title,
    required String closeTooltip,
    required List<Widget> Function(AppColors colors) body,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final colors = sheetContext.appColors;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: closeTooltip,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...body(colors),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One wallet in a Cash Summary sheet: its icon, name and what can be
  /// spent from it, with what goals hold in it under the name.
  Widget _summaryWalletLine(WalletDraft wallet, AppColors colors) {
    final forGoals = wallet.balanceRecorded ? _goalMoneyIn(wallet) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Image.asset(wallet.type.iconAsset, width: 24, height: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (forGoals > 0.005)
                  Text(
                    '${formatPeso(forGoals)} set aside for goals',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            wallet.balanceRecorded
                ? formatPeso(_availableIn(wallet))
                : 'Balance not recorded',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// A group in the total's sheet, with what it adds up to.
  Widget _summaryGroupTitle(
    String label,
    String iconAsset,
    double amount,
    AppColors colors,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Image.asset(iconAsset, width: 20, height: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            formatPeso(amount),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  List<WalletDraft> get _cashDrafts => _wallets
      .where((wallet) => wallet.type == WalletType.cash)
      .toList(growable: false);

  /// Every cash wallet, so "Cash" and "Petty Cash" can both be seen in
  /// Cash on Hand.
  Future<void> _showCashDetails() {
    final cash = _cashDrafts;
    return _showSummarySheet(
      title: 'Cash on Hand',
      closeTooltip: 'Close cash details',
      body: (colors) => [
        Text(
          'Total · ${formatPeso(_availableTotal(cash))}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        if (cash.isEmpty)
          Text(
            'No cash wallets added yet.',
            style: TextStyle(color: colors.textBody),
          )
        else
          for (final wallet in cash) _summaryWalletLine(wallet, colors),
      ],
    );
  }

  /// The total, split back into the cash and the accounts it adds up.
  Future<void> _showTotalDetails() {
    final cash = _cashDrafts;
    final accounts = _bankAndEWalletDrafts;
    final cashTotal = _availableTotal(cash);
    final accountTotal = _availableTotal(accounts);
    return _showSummarySheet(
      title: 'Total Available Money',
      closeTooltip: 'Close total details',
      body: (colors) => [
        Text(
          'Total · ${formatPeso(cashTotal + accountTotal)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Cash on Hand plus Cash in Bank and E-Wallets.',
          style: TextStyle(fontSize: 13, color: colors.textBody),
        ),
        const SizedBox(height: 16),
        _summaryGroupTitle(
          'Cash on Hand',
          WalletType.cash.iconAsset,
          cashTotal,
          colors,
        ),
        if (cash.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('None yet.', style: TextStyle(color: colors.textBody)),
          )
        else
          for (final wallet in cash) _summaryWalletLine(wallet, colors),
        const SizedBox(height: 8),
        _summaryGroupTitle(
          'Cash in Bank and E-Wallets',
          WalletType.bank.iconAsset,
          accountTotal,
          colors,
        ),
        if (accounts.isEmpty)
          Text('None yet.', style: TextStyle(color: colors.textBody))
        else
          for (final wallet in accounts) _summaryWalletLine(wallet, colors),
      ],
    );
  }

  Future<void> _showBankDetails() async {
    final accounts = _bankAndEWalletDrafts;
    final bankTotal = _availableTotal(accounts);

    await _showSummarySheet(
      title: 'Cash in Bank and E-Wallets',
      closeTooltip: 'Close bank account details',
      body: (colors) => [
        Text(
          'Total · ${formatPeso(bankTotal)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        if (accounts.isEmpty)
          Text(
            'No bank accounts or e-wallets added yet.',
            style: TextStyle(color: colors.textBody),
          )
        else
          for (final wallet in accounts)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.pageBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(wallet.type.iconAsset, width: 24, height: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          wallet.type == WalletType.bank ||
                                  wallet.type == WalletType.ewallet
                              ? wallet.name
                              : wallet.type.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        wallet.balanceRecorded
                            ? formatPeso(wallet.startingBalance)
                            : 'Balance not recorded',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if ((wallet.type == WalletType.gcash ||
                          wallet.type == WalletType.maya) &&
                      wallet.name != wallet.type.label) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Nickname: ${wallet.name}',
                      style: TextStyle(color: colors.textBody),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    wallet.type == WalletType.bank
                        ? 'Bank Account'
                        : 'E-Wallet',
                    style: TextStyle(color: colors.textBody),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // Worded as on every other card: "3% a year".
                    wallet.annualInterestRatePercent == null
                        ? 'Interest: no rate entered'
                        : 'Interest: '
                              '${percentText(wallet.annualInterestRatePercent!)} '
                              'a year',
                    style: TextStyle(color: colors.textBody),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    wallet.estimatedAnnualInterestIncome != null
                        ? 'Interest in a year, after tax: '
                              '${formatPeso(afterTax(wallet.estimatedAnnualInterestIncome!))}'
                        : 'Interest in a year: no rate yet',
                    style: TextStyle(color: colors.textBody),
                  ),
                ],
              ),
            ),
        if (accounts.any((wallet) => !wallet.balanceRecorded)) ...[
          const SizedBox(height: 4),
          Text(
            'Accounts without a recorded balance are excluded from '
            'the total.',
            style: TextStyle(color: colors.textBody),
          ),
        ],
      ],
    );
  }

  Future<void> _chooseReminders(bool enabled) async {
    // Android asks here, right after the user said yes, so the question makes
    // sense. Saying no to Android keeps reminders off rather than pretending.
    _notificationsEnabled = enabled && await widget.requestReminderPermission();
    _remindersAnswered = true;
    if (!mounted) return;
    // The ranking only picks reminders, so it is asked only when they are on.
    _goTo(_notificationsEnabled ? _planStep : _reviewStep);
  }

  Future<void> _finish() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final data = OnboardingData(
      name: cleanText(_nameController.text),
      notificationsEnabled: _notificationsEnabled,
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
    final wallet = await showWalletFormSheet(context);

    if (wallet == null || !mounted) return;

    setState(() {
      // The first wallet receives income until the user picks another.
      _wallets.add(
        wallet.copyWith(
          id: 'setup-${UniqueKey()}',
          // A repeated name gets the next number: "Cash", then "Cash 2".
          name: uniqueName(wallet.name, [
            for (final other in _wallets) other.name,
          ], maxLength: maxSavedWalletNameLength),
          receivesIncome: _wallets.isEmpty,
        ),
      );
      _showWalletError = false;
    });
  }

  Future<void> _editWallet(int index) async {
    final wallet = await showWalletFormSheet(
      context,
      initialDraft: _wallets[index],
    );
    if (wallet == null || !mounted) return;

    setState(() {
      _wallets[index] = wallet.copyWith(
        id: _wallets[index].id ?? 'setup-${UniqueKey()}',
        // A name left as it was stays; a new one is numbered if repeated.
        name: wallet.name == _wallets[index].name
            ? wallet.name
            : uniqueName(wallet.name, [
                for (var i = 0; i < _wallets.length; i++)
                  if (i != index) _wallets[i].name,
              ], maxLength: maxSavedWalletNameLength),
      );
      final updated = _wallets[index];
      final eligible =
          updated.type == WalletType.cash || isBankOrEWalletType(updated.type);
      // Only this wallet's share of each goal changes; a goal that also
      // draws on other wallets keeps those amounts.
      var remaining = eligible && updated.balanceRecorded
          ? updated.startingBalance
          : 0.0;
      for (var i = 0; i < _onboardingGoals.length; i++) {
        final goal = _onboardingGoals[i];
        final amount = goal.fundingByWalletDraftId[updated.id];
        if (amount == null) continue;
        final kept = amount.clamp(0.0, remaining).toDouble();
        _onboardingGoals[i] = _withFunding(goal, {
          ...goal.fundingByWalletDraftId,
          updated.id!: kept,
        });
        remaining -= kept;
      }
    });
  }

  void _removeWallet(int index) {
    setState(() {
      final removed = _wallets.removeAt(index);
      for (var i = 0; i < _onboardingGoals.length; i++) {
        final goal = _onboardingGoals[i];
        if (goal.fundingByWalletDraftId.containsKey(removed.id)) {
          _onboardingGoals[i] = _withFunding(goal, goal.fundingByWalletDraftId);
        }
      }
      if (removed.receivesIncome && _wallets.isNotEmpty) {
        _wallets[0] = _wallets[0].copyWith(receivesIncome: true);
      }
    });
  }

  /// [goal] drawing [amounts] from the starting wallets, by draft id. Wallets
  /// no longer listed and empty amounts drop out, and the source follows the
  /// wallets left, so cash with an account reads as both.
  OnboardingGoal _withFunding(
    OnboardingGoal goal,
    Map<String, double> amounts,
  ) {
    final funded = {
      for (final wallet in _wallets)
        if ((amounts[wallet.id] ?? 0) > 0) wallet.id!: amounts[wallet.id]!,
    };
    if (funded.isEmpty) return goal.copyWith(clearFunding: true);
    return goal
        .copyWith(clearFunding: true)
        .copyWith(
          fundingByWalletDraftId: funded,
          fundingSource: GoalFundingSource.fromTypes([
            for (final wallet in _wallets)
              if (funded.containsKey(wallet.id)) wallet.type,
          ]),
        );
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
        if (!didPop && !_isSaving) _goBack();
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
    // While editing, the step number would say "9 of 10" to someone who
    // came from the end, so the header just says what is happening.
    final showProgress = _step <= _reviewStep && !_editingFromReview;

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
                        tooltip: _editingFromReview ? 'Cancel' : 'Back',
                        icon: Icon(Icons.arrow_back, color: colors.textBody),
                        onPressed: _goBack,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  _editingFromReview
                      ? 'Editing'
                      : showProgress
                      ? 'Step $_stepNumber of $_numberedSteps'
                      : '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.appColors.textMuted,
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
                  value: _stepNumber / _numberedSteps,
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
      case _planStep:
        return _buildPlan();
      case _walletsStep:
        return _buildWallets();
      case _cashSummaryStep:
        return _buildCashSummary();
      case _savingsStep:
        return _buildSavingsPlan();
      case _billsStep:
        return _buildBillsPlan();
      case _goalsStep:
        return _buildGoalsPlan();
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
        // Editing from Review: Save Changes keeps it, the back arrow
        // cancels it.
        return _editingFromReview
            ? _primaryButton('Save Changes', _next, confirm: true)
            : _primaryButton('Next', _next);
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
      autovalidateMode: checkMode,
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
            maxLength: maxPersonNameLength,
            // Letters from any language, so Niño and Ma. Clara fit; nothing
            // hidden, and nothing past the limit, typed or pasted.
            inputFormatters: [
              personNameFormatter,
              const SafeTextFormatter(),
              LengthLimitingTextInputFormatter(maxPersonNameLength),
            ],
            onFieldSubmitted: (_) => _next(),
            decoration: _inputDecoration('e.g. Dave'),
            validator: (value) => personNameProblem(value ?? ''),
          ),
          const SizedBox(height: 4),
          _featureRow(
            'assets/icons/icons8-lock-96.png',
            'Only you can see your profile.',
          ),
        ],
      ),
    );
  }

  // =========================================================
  // STEP 8 - REMINDER PERMISSION
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
                    Text(
                      'FinAssist · now',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.textMuted,
                      ),
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
        // The same tiles as the other setup screens: a phone for reminders
        // that come from the phone, a shield for the permission Android asks.
        _featureRow(
          'assets/icons/icons8-mobile-payment-96.png',
          'Reminders come from your phone, so they work even without internet.',
        ),
        _featureRow(
          'assets/icons/icons8-shield-96.png',
          'Android will ask for permission when reminders are switched on. '
              'You can change your choice later.',
        ),
        _featureRow(
          'assets/icons/icons8-settings-96.png',
          'If you skip for now, you can turn reminders on anytime in Profile '
              '& Settings, under Reminders.',
        ),
      ],
    );
  }

  // =========================================================
  // =========================================================
  // STEP 9 - REMINDER RANKING, ONLY WHEN REMINDERS ARE ON
  // =========================================================

  Widget _buildPlan() {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('What should we remind you about most?'),
        const SizedBox(height: 8),
        _subtitle(
          'The higher it is, the more reminders it gets: #1 gets 4, #2 gets '
          '3, #3 gets 2 and #4 gets 1. You can change it later in Settings.',
        ),
        const SizedBox(height: 16),
        _subtitle('Use the arrows, or hold and drag, to move them.'),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _priorities[index].label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              // What this place is worth, so moving an item
                              // shows what changes.
                              Text(
                                reminderCountText(index + 1),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textBody,
                                ),
                              ),
                            ],
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
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.drag_handle,
                              color: context.appColors.textMuted,
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
    );
  }

  // STEP 6 - BILL REMINDERS

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

  /// Opens the same sheet as adding, filled in, and puts the change back in
  /// the same place.
  Future<void> _editOnboardingBill(int index) async {
    final existing = _onboardingBills[index];
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
        existing: Bill(
          id: 'setup-bill-$index',
          name: existing.name,
          amount: existing.amount,
          category: existing.category,
          firstDueDate: existing.firstDueDate,
          recurrence: existing.recurrence,
        ),
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
    setState(() => _onboardingBills[index] = draft!);
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
    final name = uniqueName(account.kind.label, [
      for (final saved in _onboardingSavingsAccounts) saved.name,
    ], maxLength: maxItemNameLength);
    setState(
      () => _onboardingSavingsAccounts.add(account.copyWith(name: name)),
    );
  }

  Future<void> _addOnboardingGoal() async {
    final draftWallets = _walletDraftsAsWallets();
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
        wallets: Stream.value(draftWallets),
        goals: Stream.value(_onboardingGoalsAsGoals()),
        onSave: (draft) {
          _onboardingGoals.add(
            OnboardingGoal(
              name: draft.name,
              kind: draft.kind,
              targetAmount: draft.targetAmount,
              targetDate: draft.targetDate,
              frequency: draft.frequency,
              customInterval: draft.customInterval,
              planAmount: draft.planAmount,
              note: draft.note,
              fundingByWalletDraftId: draft.savedByWallet,
              fundingSource: draft.fundingSource,
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// The one Edit for a setup goal: its details, the money set aside for
  /// it, and releasing that money, all in the form it was made with.
  Future<void> _editOnboardingGoal(int index) async {
    final goal = _onboardingGoals[index];
    // Everything the form shows, so nothing opens blank.
    final existing = Goal(
      id: 'onboarding-$index',
      name: goal.name,
      targetAmount: goal.targetAmount,
      savedAmount: goal.allocated,
      priority: index,
      status: GoalStatus.active,
      kind: goal.kind,
      targetDate: goal.targetDate,
      frequency: goal.frequency,
      customInterval: goal.customInterval,
      planAmount: goal.planAmount,
      note: goal.note,
    );
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GoalFormSheet(
        existing: existing,
        editsFunding: true,
        initialFunding: goal.fundingByWalletDraftId,
        wallets: Stream.value(_walletDraftsAsWallets()),
        // The other goals only: this one's own money is free to keep.
        goals: Stream.value(_onboardingGoalsAsGoals()..removeAt(index)),
        onRelease: goal.allocated > 0 ? () => _releaseFunding(index) : null,
        onSave: (draft) {
          // Built whole rather than copied, so a date or amount the user
          // cleared stays cleared.
          final updated = OnboardingGoal(
            name: draft.name,
            kind: draft.kind,
            targetAmount: draft.targetAmount,
            targetDate: draft.targetDate,
            frequency: draft.frequency,
            customInterval: draft.customInterval,
            planAmount: draft.planAmount,
            note: draft.note,
            fundedBy: goal.fundedBy,
            allocated: goal.fundingByWalletDraftId.isEmpty ? goal.allocated : 0,
          );
          // The new amounts replace the old ones whole, so changing them
          // never counts the same money twice. A goal funded the old way,
          // by savings record name, keeps that when nothing new is chosen.
          _onboardingGoals[index] =
              draft.savedByWallet.isEmpty && goal.fundedBy != null
              ? updated
              : _withFunding(updated, draft.savedByWallet);
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// The one warning every delete in setup shows: a red trash can, what
  /// will happen, a blue Cancel and a red Delete. Returns true to delete.
  Future<bool> _confirmDelete(String name, String message) async {
    final delete = await confirmDestructive(
      context,
      title: 'Delete $name?',
      message: message,
    );
    return delete && mounted;
  }

  /// Asks before a goal is deleted: it cannot be brought back, and what was
  /// set aside for it is freed.
  Future<void> _confirmRemoveGoal(int index) async {
    final goal = _onboardingGoals[index];
    final delete = await _confirmDelete(
      goal.name,
      goal.allocated > 0
          ? 'This goal will be removed, and the '
                '${formatPeso(goal.allocated)} set aside for it will be free '
                'again. Your wallet balances stay the same.'
          : 'This goal will be removed. You can add it again later.',
    );
    if (delete) setState(() => _onboardingGoals.removeAt(index));
  }

  /// Asks before a wallet is deleted, saying what goes with it: money goals
  /// set aside from it is freed.
  Future<void> _confirmRemoveWallet(int index) async {
    final wallet = _wallets[index];
    final setAside = _onboardingGoals.fold<double>(
      0,
      (total, goal) => total + (goal.fundingByWalletDraftId[wallet.id] ?? 0),
    );
    final delete = await _confirmDelete(
      wallet.name,
      setAside > 0
          ? 'This wallet will be removed, and the ${formatPeso(setAside)} '
                'your goals set aside from it will be free again.'
          : 'This wallet will be removed. You can add it again later.',
    );
    if (delete) _removeWallet(index);
  }

  /// Asks before a bill is deleted.
  Future<void> _confirmRemoveBill(int index) async {
    final delete = await _confirmDelete(
      _onboardingBills[index].name,
      'This bill and its reminders will be removed. You can add it again '
      'later.',
    );
    if (delete) _removeOnboardingBill(index);
  }

  List<Wallet> _walletDraftsAsWallets() => [
    for (var index = 0; index < _wallets.length; index++)
      Wallet(
        id: _wallets[index].id ?? 'setup-$index',
        name: _wallets[index].name,
        type: _wallets[index].type,
        balance: _wallets[index].startingBalance,
        hasRecordedBalance: _wallets[index].balanceRecorded,
        startingBalance: _wallets[index].startingBalance,
        receivesIncome: _wallets[index].receivesIncome,
        archived: false,
        sortOrder: index,
        annualInterestRatePercent: _wallets[index].annualInterestRatePercent,
        purpose: _wallets[index].purpose,
        savingsKind: _wallets[index].savingsKind,
      ),
  ];

  List<Goal> _onboardingGoalsAsGoals() => [
    for (var index = 0; index < _onboardingGoals.length; index++)
      Goal(
        id: 'onboarding-$index',
        name: _onboardingGoals[index].name,
        targetAmount: _onboardingGoals[index].targetAmount,
        savedAmount: _onboardingGoals[index].allocated,
        priority: index,
        status: GoalStatus.active,
        walletId: _onboardingGoals[index].fundingWalletDraftId,
        fundingSource: _onboardingGoals[index].fundingSource,
        savedByWallet: _onboardingGoals[index].fundingByWalletDraftId,
      ),
  ];

  Widget _buildBillsPlan() {
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
          _emptyListState(
            iconAsset: 'assets/icons/icons8-receipt-96.png',
            title: 'No bills added yet',
            message:
                'This step is optional. You can tap Next and add bills '
                'whenever you are ready.',
          )
        else
          for (final (index, bill) in _onboardingBills.indexed)
            _billCard(index, bill),
        const SizedBox(height: 6),
        _addButton(
          key: const Key('add-onboarding-bill'),
          label: 'Add a Bill',
          onPressed: _addOnboardingBill,
        ),
      ],
    );
  }

  // STEP 5 - SAVINGS

  Widget _buildSavingsPlan() {
    final savedTotal = _onboardingSavingsAccounts.fold<double>(
      0,
      (total, account) => total + account.balance,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('Build your savings'),
        const SizedBox(height: 8),
        _subtitle(
          'Track savings you already have. You can add a savings record now '
          'or set it up later.',
        ),
        const SizedBox(height: 20),

        if (_onboardingSavingsAccounts.isEmpty)
          _emptyListState(
            iconAsset: 'assets/icons/icons8-money-box-96.png',
            title: 'Nothing saved here yet',
            message:
                'This step is optional. You can tap Next and add savings '
                'whenever you are ready.',
          ),

        if (_onboardingSavingsAccounts.isNotEmpty) ...[
          _savingsSectionTitle('Your savings', formatPeso(savedTotal)),
          const SizedBox(height: 10),
          for (final (index, account) in _onboardingSavingsAccounts.indexed)
            _savingsRecordCard(index, account),
          const SizedBox(height: 6),
        ],

        _addButton(
          key: const Key('add-onboarding-savings-account'),
          label: 'Add Savings',
          onPressed: _addOnboardingSavingsAccount,
        ),
      ],
    );
  }

  /// What the savings, bills and goals steps show before anything is added:
  /// the step's icon, a short line, and that it can be skipped.
  Widget _emptyListState({
    required String iconAsset,
    required String title,
    required String message,
  }) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Image.asset(iconAsset, width: 44, height: 44),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.textBody),
          ),
        ],
      ),
    );
  }

  Widget _savingsSectionTitle(String title, String? trailing) {
    final colors = context.appColors;

    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
      ],
    );
  }

  /// One savings record: its kind's icon, how much is in it, then the facts
  /// that apply to that kind, the same as on the Savings screen.
  Widget _savingsRecordCard(int index, OnboardingSavingsAccount account) {
    final free = unallocatedSavings(account, _onboardingGoals);

    return ItemCard(
      key: ValueKey('onboarding-savings-$index'),
      icon: Image.asset(savingsKindIcon(account.kind)),
      title: account.name,
      subtitle: savingsRecordSubtitle(
        name: account.name,
        kind: account.kind,
        balance: account.balance,
      ),
      onEdit: () => _editOnboardingSavingsAccount(index),
      onDelete: () => _removeOnboardingSavingsAccount(index),
      details: savingsRecordDetails(
        kind: account.kind,
        balance: account.balance,
        rate: account.annualInterestRatePercent,
        start: account.depositStartDate,
        end: account.maturityDate,
        interestUntilEnd: account.estimatedSimpleInterest,
        promised: account.balance - free,
        payout: account.interestPayout,
      ),
    );
  }

  /// One bill: its category's icon, the same one the bills list uses, what
  /// it costs and how often, then when it is due.
  Widget _billCard(int index, OnboardingBill bill) {
    final once = bill.recurrence == BillRecurrence.once;

    return ItemCard(
      key: ValueKey('onboarding-bill-$index'),
      deleteKey: Key('remove-onboarding-bill-$index'),
      icon: CategoryIcon(bill.category, size: 32),
      title: bill.name,
      subtitle:
          '${formatPeso(bill.amount)} '
          '${once ? 'one time' : bill.recurrence.label.toLowerCase()}',
      onEdit: () => _editOnboardingBill(index),
      onDelete: () => _confirmRemoveBill(index),
      details: [
        ItemCardDetail(
          once ? 'Due date' : 'First due date',
          formatShortDate(bill.firstDueDate),
        ),
      ],
    );
  }

  /// One goal: how far along it is, then where its money is, one row per
  /// account. The numbers come first and the details stay short, so a list
  /// of goals can be read at a glance.
  Widget _onboardingGoalCard(int index, OnboardingGoal goal) {
    final colors = context.appColors;
    final sources = [
      for (final wallet in _walletDraftsAsWallets())
        if (goal.fundingByWalletDraftId[wallet.id] case final amount?)
          (wallet, amount),
    ];
    final reached = goal.isReached;

    return ItemCard(
      // A reached goal trades its target for a green check.
      icon: Image.asset(
        reached ? goalReachedIcon : 'assets/icons/icons8-goal-96.png',
      ),
      title: goal.name,
      subtitle: reached
          ? '${formatPeso(goal.targetAmount)} saved — completed!'
          : '${formatPeso(goal.allocated)} of '
                '${formatPeso(goal.targetAmount)} saved',
      // One Edit for everything: the details, the money set aside, and
      // releasing it.
      onEdit: () => _editOnboardingGoal(index),
      onDelete: () => _confirmRemoveGoal(index),
      details: [
        GoalProgressBar(progress: goal.progress, reached: reached),
        // How much a month reaches it, from what is left once the money
        // already set aside is counted.
        if (goalPlanLine(
              remaining: goal.targetAmount - goal.allocated,
              targetDate: goal.targetDate,
              now: DateTime.now(),
              frequency: goal.frequency,
              custom: goal.customInterval,
              planAmount: goal.planAmount,
            )
            case final line?) ...[
          const SizedBox(height: 12),
          GoalPlanNote(line),
        ],
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Set aside from',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textBody,
            ),
          ),
          const SizedBox(height: 2),
          GoalFundingList(sources: sources),
        ] else if (goal.fundedBy != null) ...[
          const SizedBox(height: 10),
          Text(
            'From ${goal.fundedBy}',
            style: TextStyle(fontSize: 13, color: colors.primaryText),
          ),
        ],
        if (sources.isEmpty && goal.fundedBy == null && _wallets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Nothing set aside yet. Tap the pencil to add money you '
              'already have.',
              style: TextStyle(fontSize: 12, color: colors.textBody),
            ),
          ),
      ],
    );
  }

  Future<void> _editOnboardingSavingsAccount(int index) async {
    final existing = _onboardingSavingsAccounts[index];
    final updated = await showModalBottomSheet<OnboardingSavingsAccount>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OnboardingSavingsSheet(existing: existing),
    );
    if (updated == null || !mounted) return;

    setState(() {
      _onboardingSavingsAccounts[index] = updated;
      // Goals pointing at the old name follow it, and an allocation larger
      // than the new balance is trimmed rather than left impossible.
      for (var i = 0; i < _onboardingGoals.length; i++) {
        final goal = _onboardingGoals[i];
        if (goal.fundedBy != existing.name) continue;
        final room = unallocatedSavings(
          updated,
          _onboardingGoals,
          ignoring: goal,
        );
        _onboardingGoals[i] = goal.copyWith(
          fundedBy: updated.name,
          allocated: goal.allocated > room ? room : goal.allocated,
        );
      }
    });
  }

  Future<void> _removeOnboardingSavingsAccount(int index) async {
    final account = _onboardingSavingsAccounts[index];
    final funded = _onboardingGoals
        .where((goal) => goal.fundedBy == account.name)
        .toList();

    final delete = await _confirmDelete(
      account.name,
      funded.isEmpty
          ? 'This savings record will be removed. You can add it again later.'
          : 'This savings record will be removed. '
                '${funded.length} goal${funded.length == 1 ? '' : 's'} '
                'draw${funded.length == 1 ? 's' : ''} on it, and '
                '${funded.length == 1 ? 'it stays' : 'they stay'} with '
                'nothing set aside yet.',
    );
    if (!delete) return;

    setState(() {
      _onboardingSavingsAccounts.removeAt(index);
      for (var i = 0; i < _onboardingGoals.length; i++) {
        if (_onboardingGoals[i].fundedBy == account.name) {
          _onboardingGoals[i] = _onboardingGoals[i].copyWith(
            clearFunding: true,
          );
        }
      }
    });
  }

  /// Takes back everything set aside for the goal at [index]. It is one tap
  /// on the card, so it can be undone for a few seconds instead of being
  /// asked about first.
  void _releaseFunding(int index) {
    final before = _onboardingGoals[index];
    final released = before.copyWith(clearFunding: true);
    setState(() => _onboardingGoals[index] = released);

    showUndoSnackBar(
      context,
      iconAsset: 'assets/icons/icons8-goal-96.png',
      title: 'Released from ${before.name}',
      message: '${formatPeso(before.allocated)} is no longer set aside for it.',
      onUndo: () {
        if (!mounted) return;
        final at = _onboardingGoals.indexOf(released);
        // Removed or changed since: there is nothing to put back.
        if (at < 0) return;
        setState(
          () => _onboardingGoals[at] = _withFunding(
            before,
            before.fundingByWalletDraftId,
          ),
        );
      },
    );
  }

  void _movePriority(int oldIndex, int newIndex) {
    setState(() {
      _priorities.insert(newIndex, _priorities.removeAt(oldIndex));
    });
  }

  /// The Add button under each step's list. One look on every step, the
  /// same as the button that saves a wallet: solid green, bold, full width.
  Widget _addButton({
    required String label,
    required VoidCallback onPressed,
    Key? key,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        key: key,
        onPressed: onPressed,
        style: confirmButtonStyle(),
        child: Text(label, style: _saveLabelStyle),
      ),
    );
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
  // STEP 3 - STARTING WALLETS
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
                Text(
                  'Add at least one wallet to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          )
        else
          for (var index = 0; index < _wallets.length; index++)
            _WalletDraftCard(
              wallet: _wallets[index],
              onEdit: () => _editWallet(index),
              onRemove: () => _confirmRemoveWallet(index),
            ),
        const SizedBox(height: 12),
        _addButton(
          label: _wallets.isEmpty ? 'Add a Wallet' : 'Add Another',
          onPressed: _addWallet,
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
  // STEP 4 - CASH SUMMARY
  // =========================================================

  Widget _buildCashSummary() {
    final cashOnHand = _availableTotal(
      _wallets.where((wallet) => wallet.type == WalletType.cash),
    );
    final accounts = _bankAndEWalletDrafts;
    final cashInBank = _availableTotal(accounts);
    final totalAvailable = cashOnHand + cashInBank;
    final forGoals = _wallets.fold<double>(
      0,
      (total, wallet) =>
          total + (wallet.balanceRecorded ? _goalMoneyIn(wallet) : 0),
    );
    // What reaches the accounts once the bank keeps its tax.
    final annualInterestEstimates = accounts
        .map((wallet) => wallet.estimatedAnnualInterestIncome)
        .whereType<double>()
        .map(afterTax)
        .toList(growable: false);
    final estimatedInterestText =
        annualInterestEstimates.isEmpty && accounts.isNotEmpty
        ? 'Unavailable'
        : formatPeso(
            annualInterestEstimates.fold<double>(
              0,
              (total, estimate) => total + estimate,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('Cash Summary'),
        const SizedBox(height: 8),
        _subtitle(
          forGoals > 0.005
              ? 'Here is the money you listed in cash wallets, bank accounts, '
                    'and e-wallets, less the ${formatPeso(forGoals)} set aside '
                    'for your goals.'
              : 'Here is the money you listed in cash wallets, bank accounts, '
                    'and e-wallets.',
        ),
        const SizedBox(height: 24),
        // Every line that adds wallets up opens the wallets behind it.
        _cashSummaryRow(
          iconAssets: [WalletType.cash.iconAsset],
          label: 'Cash on Hand',
          amount: cashOnHand,
          onTap: _showCashDetails,
        ),
        _cashSummaryRow(
          iconAssets: [WalletType.bank.iconAsset],
          label: 'Cash in Bank',
          amount: cashInBank,
          onTap: _showBankDetails,
        ),
        _cashSummaryRow(
          // Cash in hand plus cash in bank, so both their icons.
          iconAssets: [WalletType.cash.iconAsset, WalletType.bank.iconAsset],
          label: 'Total Available Money',
          amount: totalAvailable,
          emphasized: true,
          onTap: _showTotalDetails,
        ),
        _cashSummaryRow(
          iconAssets: ['assets/icons/icons8-combo-chart-100.png'],
          label: 'Interest in a Year (after tax)',
          amount: 0,
          amountText: estimatedInterestText,
        ),
        const SizedBox(height: 8),
        // The same tiles as the other setup notes: a bank for the accounts,
        // the interest chart for the interest.
        _featureRow(WalletType.bank.iconAsset, _interestCoverageText(accounts)),
        _featureRow(
          'assets/icons/icons8-combo-chart-100.png',
          'Interest is not in Cash in Bank or Total Available Money until it '
              'is paid. It is an estimate after the '
              '${(interestTaxRate * 100).round()}% tax banks keep, and FinAssist '
              'reminds you to add it as income when it comes.',
        ),
      ],
    );
  }

  /// Which accounts the yearly interest counts, naming any left out, so the
  /// user knows which rate is missing instead of only how many.
  String _interestCoverageText(List<WalletDraft> accounts) {
    if (accounts.isEmpty) return 'No bank accounts or e-wallets were added.';

    final missing = [
      for (final wallet in accounts)
        if (wallet.estimatedAnnualInterestIncome == null) wallet.name,
    ];
    final counted = accounts.length - missing.length;
    if (missing.isEmpty) {
      return accounts.length == 1
          ? 'Interest counts your 1 account.'
          : 'Interest counts all ${accounts.length} of your accounts.';
    }
    if (counted == 0) {
      return 'None of your accounts has a rate yet, so no interest is '
          'counted.';
    }

    final names = missing.length == 1
        ? missing.single
        : '${missing.sublist(0, missing.length - 1).join(', ')} and '
              '${missing.last}';
    return 'Interest counts $counted of your ${accounts.length} accounts. '
        '$names ${missing.length == 1 ? 'has' : 'have'} no rate, so '
        '${missing.length == 1 ? "it's" : "they're"} left out.';
  }

  Widget _cashSummaryRow({
    required List<String> iconAssets,
    required String label,
    required double amount,
    String? amountText,
    VoidCallback? onTap,
    bool emphasized = false,
  }) {
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: emphasized ? colors.primaryTint : colors.pageBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: emphasized ? colors.primaryText : colors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // The same colored icons the wallets and goals use. Two
                // overlap, so a total still fits the same space.
                SizedBox(
                  width: 34,
                  height: 28,
                  child: iconAssets.length == 1
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Image.asset(
                            iconAssets.first,
                            width: 28,
                            height: 28,
                          ),
                        )
                      : Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              child: Image.asset(
                                iconAssets[0],
                                width: 22,
                                height: 22,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Image.asset(
                                iconAssets[1],
                                width: 22,
                                height: 22,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: emphasized
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  amountText ?? formatPeso(amount),
                  style: TextStyle(
                    fontSize: emphasized ? 18 : 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: colors.textBody),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // STEP 7 - GOALS

  Widget _buildGoalsPlan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _title('Set up your goals'),
        const SizedBox(height: 8),
        _subtitle(
          'Choose a cash, bank, or e-wallet account and earmark money already '
          'there. This does not move money or change the account balance.',
        ),
        const SizedBox(height: 18),
        if (_onboardingGoals.isEmpty)
          _emptyListState(
            iconAsset: 'assets/icons/icons8-goal-96.png',
            title: 'No goals added yet',
            message: 'You can create one now or add it later.',
          )
        else ...[
          for (final (index, goal) in _onboardingGoals.indexed)
            _onboardingGoalCard(index, goal),
          const SizedBox(height: 6),
        ],
        _addButton(
          key: const Key('add-onboarding-goal'),
          label: 'Add Goal',
          onPressed: _addOnboardingGoal,
        ),
      ],
    );
  }

  // =========================================================
  // RECAP - YOU'RE READY
  // =========================================================

  // =========================================================
  // STEP 10 - REVIEW
  // =========================================================

  /// A last look before anything is saved. Each line jumps back to the step
  /// that set it, so a wrong answer is two taps from being fixed.
  Widget _buildReview() {
    final walletTotal = _availableTotal(_wallets);
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
          "Nothing is saved yet. Tap the pencil to fix anything. You'll "
          'come right back here.',
        ),
        const SizedBox(height: 20),
        _reviewRow('Your name', _nameController.text.trim(), _nameStep),
        // The same order the steps asked in.
        _reviewRow(
          'Wallets',
          _wallets.isEmpty
              ? 'None added'
              : '${plural(_wallets.length, 'wallet')} · '
                    '${formatPeso(walletTotal)} available',
          _walletsStep,
        ),
        _reviewRow(
          'Savings',
          plural(_onboardingSavingsAccounts.length, 'account'),
          _savingsStep,
        ),
        _reviewRow(
          'Bills',
          _onboardingBills.isEmpty
              ? 'None added'
              : '${plural(_onboardingBills.length, 'bill')} · '
                    '${formatPeso(billsTotal)}',
          _billsStep,
        ),
        _reviewRow(
          'Goals',
          plural(_onboardingGoals.length, 'goal'),
          _goalsStep,
        ),
        _reviewRow(
          'Reminders',
          _notificationsEnabled ? 'On' : 'Off',
          _remindersStep,
        ),
        if (_notificationsEnabled)
          _reviewRow(
            'Remind me most about',
            _priorities.first.label,
            _planStep,
          ),
      ],
    );
  }

  /// One answer, with the way back to the step that set it.
  Widget _reviewRow(String label, String value, int step) {
    final colors = context.appColors;
    // Marked only when the edit really changed the answer.
    final updated =
        _editedStep == step &&
        _editedValueBefore != null &&
        _editedValueBefore != value;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: updated ? colors.successTint : colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: updated ? confirmColorOn(context) : colors.border,
          width: updated ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Shrinks and wraps on a narrow screen or with large
                    // text, instead of running past the edge.
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 12, color: colors.textBody),
                      ),
                    ),
                    if (updated) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: confirmColorOn(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Updated',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: context.isDarkMode
                                ? const Color(0xFF0F2E12)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
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
          // The same blue pencil the goal cards use for Edit.
          IconButton(
            tooltip: 'Edit $label',
            onPressed: () => _editFromReview(step, value),
            icon: const Icon(
              Icons.edit_outlined,
              size: 20,
              color: appPrimaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReady() {
    final colors = context.appColors;
    final name = _nameController.text.trim();
    final walletTotal = _availableTotal(_wallets);
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
              // The same order the steps asked in.
              _summaryRow(
                'assets/icons/icons8-wallet-96.png',
                'Wallets',
                '${_wallets.length} wallet${_wallets.length == 1 ? '' : 's'}'
                    ' · ${formatPeso(walletTotal)} available',
              ),
              _summaryRow(
                'assets/icons/icons8-money-box-96.png',
                'Savings',
                '${_onboardingSavingsAccounts.length} account${_onboardingSavingsAccounts.length == 1 ? '' : 's'}',
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
                'Goals',
                '${_onboardingGoals.length} goal${_onboardingGoals.length == 1 ? '' : 's'}',
              ),
              _summaryRow(
                'assets/icons/icons8-bell-96.png',
                'Reminders',
                _notificationsEnabled
                    ? 'On · ${_priorities.first.label} first'
                    : 'Off',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // What comes next, in one card: a heading that says where, then the
        // two things to try first. The bulb is the app's tip icon.
        Container(
          key: const Key('setup-next-steps'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          decoration: BoxDecoration(
            color: colors.primaryTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/icons/icons8-idea-96.png',
                    width: 22,
                    height: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Next, on your dashboard',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _nextStepRow(
                'assets/icons/icons8-money-transfer-96.png',
                'Tap + anytime to add an expense or income',
              ),
              // The same icon as Reports on the dashboard.
              _nextStepRow(
                'assets/icons/icons8-combo-chart-100.png',
                'See where your money goes in Reports',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One thing to try next, inside the tinted card: its icon on the card's
  /// own color so it stands out from the tint.
  Widget _nextStepRow(String iconAsset, String text) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(iconAsset),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: colors.textBody,
              ),
            ),
          ),
        ],
      ),
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
      style: TextStyle(
        fontSize: 15,
        color: context.appColors.textMuted,
        height: 1.4,
      ),
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
                style: TextStyle(
                  fontSize: 13,
                  color: context.appColors.textMuted,
                ),
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
  const _OnboardingSavingsSheet({this.existing});

  /// The record being changed, or null when adding a new one.
  final OnboardingSavingsAccount? existing;

  @override
  State<_OnboardingSavingsSheet> createState() =>
      _OnboardingSavingsSheetState();
}

/// Adds or changes one savings record. Laid out like the wallet form: the
/// kind as three picture tiles, one short line about the chosen kind, then
/// only the fields that kind needs, each with its label above it.
class _OnboardingSavingsSheetState extends State<_OnboardingSavingsSheet>
    with CheckAfterSave {
  final _formKey = GlobalKey<FormState>();
  late final _balanceController = TextEditingController(
    text: widget.existing == null || widget.existing!.balance == 0
        ? ''
        : formatAmountInput(widget.existing!.balance),
  );
  late final _rateController = TextEditingController(
    text: widget.existing?.annualInterestRatePercent?.toString() ?? '',
  );
  late SavingsKind _kind = widget.existing?.kind ?? SavingsKind.savingsDeposit;
  late DateTime? _depositStartDate = widget.existing?.depositStartDate;
  late DateTime? _maturityDate = widget.existing?.maturityDate;
  late InterestPayout _payout =
      widget.existing?.interestPayout ?? InterestPayout.monthly;

  // What is missing from the dates: shown once Save has been tapped, and
  // gone as soon as the right date is picked.
  String? get _startError =>
      triedToSave && _needsRateAndStart && _depositStartDate == null
      ? 'Choose the start date.'
      : null;

  String? get _endError =>
      triedToSave &&
          _kind == SavingsKind.timeDeposit &&
          (_maturityDate == null ||
              (_depositStartDate != null &&
                  !_maturityDate!.isAfter(_depositStartDate!)))
      ? 'Choose an end date after the start date.'
      : null;

  bool get _isEditing => widget.existing != null;
  bool get _needsRateAndStart => _kind.isInterestBearing;

  @override
  void dispose() {
    _balanceController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  double? _parseBalance(String value) =>
      double.tryParse(value.trim().replaceAll(',', ''));

  /// The plain-language guide to one kind, from its "Read about" link.
  Future<void> _explain(SavingsKind kind) async {
    await showSavingsOptionSheet(
      context,
      option: savingsOptionFor(kind),
      actionLabel: 'Use this',
      onAct: () => setState(() => _kind = kind),
    );
  }

  Future<void> _pickDepositStart() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _depositStartDate ?? today,
      firstDate: DateTime(today.year - 20),
      lastDate: DateTime(today.year + 20),
      helpText: 'When did it start earning interest?',
    );
    if (picked != null) {
      setState(() {
        _depositStartDate = picked;
        if (_maturityDate != null && !_maturityDate!.isAfter(picked)) {
          _maturityDate = null;
        }
      });
    }
  }

  Future<void> _pickMaturity() async {
    final today = DateTime.now();
    final earliest = _depositStartDate ?? today;
    final suggested = DateTime(earliest.year, earliest.month + 6, earliest.day);
    final selected = _maturityDate;
    final initial = selected != null && selected.isAfter(earliest)
        ? selected
        : suggested;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day + 1),
      lastDate: DateTime(today.year + 40),
      helpText: 'When can you take it out?',
    );
    if (picked != null) setState(() => _maturityDate = picked);
  }

  void _save() {
    // Every problem shows at once, not one per tap.
    final fieldsOk = checkForm(_formKey);
    if (!fieldsOk || _startError != null || _endError != null) return;

    Navigator.pop(
      context,
      OnboardingSavingsAccount(
        name: widget.existing?.name ?? _kind.label,
        kind: _kind,
        balance: _parseBalance(_balanceController.text)!,
        annualInterestRatePercent: _needsRateAndStart
            ? double.parse(_rateController.text.trim())
            : null,
        depositStartDate: _needsRateAndStart ? _depositStartDate : null,
        maturityDate: _kind == SavingsKind.timeDeposit ? _maturityDate : null,
        note: widget.existing?.note,
        interestPayout: _payout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
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
          autovalidateMode: checkMode,
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit Savings' : 'Add Savings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                "Money you've already put aside. FinAssist isn't connected "
                'to your bank, so you enter the amount yourself.',
                style: TextStyle(fontSize: 13, color: colors.textBody),
              ),
              // The same pieces as Add Savings on the Savings screen.
              SavingsKindPicker(
                kind: _kind,
                onChanged: (kind) => setState(() => _kind = kind),
                onLearnMore: _explain,
              ),
              const FieldLabel('Current balance'),
              TextFormField(
                key: const Key('onboarding-savings-balance'),
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [ThousandsSeparatorFormatter()],
                decoration: outlinedFieldDecoration(
                  hint: '0.00',
                  prefix: '₱ ',
                  helper:
                      "Check your bank app or passbook. Enter 0 if it's "
                      'empty.',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Enter the balance, or 0 if empty.';
                  final amount = _parseBalance(text);
                  if (amount == null || !amount.isFinite || amount < 0) {
                    return 'Enter an amount of zero or more.';
                  }
                  // A time deposit is opened with its money in it, all at
                  // once; it can't start empty and be filled later.
                  if (_kind == SavingsKind.timeDeposit && amount <= 0) {
                    return 'A time deposit is opened with its money in it. '
                        'Enter the amount you placed.';
                  }
                  if (amount > 999999999) return 'That amount is too large.';
                  return null;
                },
              ),
              if (_needsRateAndStart) ...[
                const FieldLabel('Interest rate per year'),
                TextFormField(
                  key: const Key('onboarding-savings-rate'),
                  controller: _rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [RateInputFormatter()],
                  decoration: outlinedFieldDecoration(
                    hint: 'e.g. 5',
                    suffix: '%',
                    helper: 'Found in your bank app or account papers.',
                  ),
                  validator: (value) {
                    final rate = double.tryParse((value ?? '').trim());
                    if (rate == null ||
                        !isValidAnnualInterestRatePercent(rate)) {
                      return 'Enter a rate from 0% to '
                          '${maximumAnnualInterestRatePercent.toInt()}%.';
                    }
                    return null;
                  },
                ),
                const FieldLabel('Start date'),
                PickDateField(
                  key: const Key('savings-deposit-start'),
                  date: _depositStartDate,
                  onTap: _pickDepositStart,
                  helper: 'When this money started earning interest.',
                  error: _startError,
                ),
              ],
              // A savings deposit pays now and then; a time deposit pays at
              // its end date.
              if (_kind == SavingsKind.savingsDeposit)
                InterestPayoutPicker(
                  payout: _payout,
                  onChanged: (payout) => setState(() => _payout = payout),
                ),
              if (_kind == SavingsKind.timeDeposit) ...[
                const FieldLabel('End date'),
                PickDateField(
                  key: const Key('savings-maturity'),
                  date: _maturityDate,
                  onTap: _pickMaturity,
                  helper: 'When you can take it out without a penalty.',
                  error: _endError,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('save-onboarding-savings'),
                  style: confirmButtonStyle(),
                  onPressed: _save,
                  child: Text(
                    _isEditing ? 'Save Changes' : 'Add Savings',
                    style: _saveLabelStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletDraftCard extends StatelessWidget {
  const _WalletDraftCard({
    required this.wallet,
    required this.onEdit,
    required this.onRemove,
  });
  final WalletDraft wallet;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        decoration: BoxDecoration(
          color: colors.pageBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
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
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textMuted,
                    ),
                  ),
                  Text(
                    wallet.balanceRecorded
                        ? formatPeso(wallet.startingBalance)
                        : 'Balance not recorded',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // The same blue pencil and red trash can as every card in
            // setup; deleting asks first.
            IconButton(
              tooltip: 'Edit ${wallet.name}',
              icon: const Icon(
                Icons.edit_outlined,
                size: 20,
                color: appPrimaryBlue,
              ),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Delete ${wallet.name}',
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: dangerColorOn(context),
              ),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// ADD WALLET SHEET
// =========================================================

/// Every setup answer at one moment, kept while a step is edited from
/// Review. Answers are never changed in place, only replaced, so a list
/// that holds the same items in the same order is unchanged.
class _SetupAnswers {
  _SetupAnswers.of(_FinancialSetupScreenState setup)
    : name = setup._nameController.text,
      notificationsEnabled = setup._notificationsEnabled,
      remindersAnswered = setup._remindersAnswered,
      priorities = [...setup._priorities],
      bills = [...setup._onboardingBills],
      savings = [...setup._onboardingSavingsAccounts],
      goals = [...setup._onboardingGoals],
      wallets = [...setup._wallets];

  final String name;
  final bool notificationsEnabled;
  final bool remindersAnswered;
  final List<FinancialPriority> priorities;
  final List<OnboardingBill> bills;
  final List<OnboardingSavingsAccount> savings;
  final List<OnboardingGoal> goals;
  final List<WalletDraft> wallets;

  bool sameAs(_SetupAnswers other) =>
      name.trim() == other.name.trim() &&
      notificationsEnabled == other.notificationsEnabled &&
      remindersAnswered == other.remindersAnswered &&
      _same(priorities, other.priorities) &&
      _same(bills, other.bills) &&
      _same(savings, other.savings) &&
      _same(goals, other.goals) &&
      _same(wallets, other.wallets);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  void restoreTo(_FinancialSetupScreenState setup) {
    setup._nameController.text = name;
    setup._notificationsEnabled = notificationsEnabled;
    setup._remindersAnswered = remindersAnswered;
    setup._priorities
      ..clear()
      ..addAll(priorities);
    setup._onboardingBills
      ..clear()
      ..addAll(bills);
    setup._onboardingSavingsAccounts
      ..clear()
      ..addAll(savings);
    setup._onboardingGoals
      ..clear()
      ..addAll(goals);
    setup._wallets
      ..clear()
      ..addAll(wallets);
  }
}
