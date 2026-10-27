import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/voice_command.dart';
import '../providers/app_settings_provider.dart';
import '../services/user_profile_service.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/back_to_home.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/transfer_sheet.dart';
import '../services/bill_service.dart';
import '../services/debt_service.dart';
import '../services/goal_service.dart';
import '../services/reminder_scheduler.dart';
import '../services/reminder_service.dart';
import '../services/saved_accounts.dart';
import '../services/wallet_service.dart';
import '../widgets/interest_sheet.dart';
import 'add_expense_screen.dart';
import 'bill_calendar_screen.dart';
import 'bill_detail_screen.dart';
import 'categories_screen.dart';
import 'chatbot_screen.dart';
import 'goal_detail_screen.dart';
import 'goals_screen.dart';
import 'help_screen.dart';
import 'home_screen.dart';
import 'income_waterfall_screen.dart';
import 'ocr_screen.dart';
import 'profile_screen.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';
import 'set_aside_screen.dart';
import 'voice_recognition_screen.dart';
import 'history_screen.dart';
import 'transactions_screen.dart';
import 'wallets_screen.dart';

/// The signed-in app: four bottom tabs (Home / Transactions / Goals / Wallet)
/// with a center "+" button that opens the quick-add grid.
class MainShell extends StatefulWidget {
  const MainShell({this.pages, this.quickAddActions, super.key});

  /// Replaces the four tab pages. Used by tests, which can't load Firebase.
  final List<Widget>? pages;

  /// Replaces the quick-add shortcuts. Used by tests.
  final List<QuickAddAction>? quickAddActions;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const _homeIndex = 0;
  static const _transactionsIndex = 1;
  static const _reportsIndex = 2;
  static const _walletIndex = 3;

  /// Preserves the legacy controller for saved Goals screen routes.
  final _goalsTab = GoalsTabController();

  /// Keeps phone reminders in step with the data. Not run by tests, which
  /// pass their own pages and can't reach Firebase.
  final _reminders = ReminderScheduler();

  bool get _live => widget.pages == null;
  StreamSubscription? _profileSubscription;

  @override
  void initState() {
    super.initState();
    if (!_live) return;

    // Listed in Switch account from now on.
    SavedAccounts.remember(SavedAccount.of(FirebaseAuth.instance.currentUser));

    final settings = context.read<AppSettingsProvider>();
    // Subscribe per signed-in shell so another account never inherits categories.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      settings.updateCategoryPreferences(null);
      _profileSubscription = UserProfileService.watchProfile().listen(
        (snapshot) => settings.updateCategoryPreferences(snapshot.data()),
        onError: (Object error) => debugPrint('Profile preferences: $error'),
      );
    });

    WidgetsBinding.instance.addObserver(this);
    _reminders.start();
    // Older installments get their interest kept apart, once each.
    DebtService.fillInterestShares();
    ReminderService.opened.addListener(_openReminder);
    // A reminder may have opened the app before this screen existed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openReminder());
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    if (_live) {
      WidgetsBinding.instance.removeObserver(this);
      ReminderService.opened.removeListener(_openReminder);
      _reminders.stop();
    }
    _goalsTab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A new day may have started, so "nothing logged today" is planned again.
    if (state == AppLifecycleState.resumed) _reminders.refresh();
  }

  /// Opens what a tapped reminder is about.
  Future<void> _openReminder() async {
    final payload = ReminderService.opened.value;
    if (payload == null || !mounted) return;
    ReminderService.opened.value = null;

    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);

    if (payload.startsWith('bill:')) {
      _selectTab(_homeIndex);
      final instance = await BillService.loadInstance(payload.substring(5));
      if (instance != null && mounted) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => BillDetailScreen(instance: instance),
          ),
        );
      }
    } else if (payload == 'bills') {
      // Several bills in one reminder: show them all together.
      _selectTab(_homeIndex);
      navigator.push(
        MaterialPageRoute(builder: (context) => const BillCalendarScreen()),
      );
    } else if (payload.startsWith('goal:')) {
      _openSavings();
      final goal = await GoalService.watchGoal(payload.substring(5)).first;
      if (goal != null && mounted) {
        navigator.push(
          MaterialPageRoute(builder: (context) => GoalDetailScreen(goal: goal)),
        );
      }
    } else if (payload == 'log') {
      _selectTab(_homeIndex);
      navigator.push(
        MaterialPageRoute(builder: (context) => const AddExpenseScreen()),
      );
    } else if (payload.startsWith('interest:')) {
      // Interest: the user checks the account and says what came in.
      _selectTab(_homeIndex);
      final id = payload.substring(9);
      final wallets = await WalletService.loadWallets();
      final wallet = wallets.where((w) => w.id == id && !w.archived);
      if (wallet.isNotEmpty && mounted) {
        final added = await showAddInterestSheet(context, wallet: wallet.first);
        if (added && mounted) setState(() => _homeRefreshKey++);
      }
    } else if (payload == 'installments') {
      // The year's interest: each installment shows what it has cost.
      _openDebts();
    } else {
      // The leftover notice waits on Home.
      _selectTab(_homeIndex);
    }
  }

  /// Goals and debts have no tab of their own any more, so they open as a
  /// screen on top of Home.
  void _openGoals() {
    _selectTab(_homeIndex);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoalsScreen(controller: _goalsTab)),
    );
  }

  void _openSavings() {
    _goalsTab.openSavings();
    _openGoals();
  }

  /// Bill Planner and Installments open over the tabs, with a back arrow:
  /// Reports took the Bills place in the bottom bar.
  void _openBills() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BillCalendarScreen()),
    );
  }

  void _openDebts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BillCalendarScreen(initialShowDebts: true),
      ),
    );
  }

  void _navigateFromVoice(VoiceDestination destination) {
    switch (destination) {
      case VoiceDestination.home:
        _selectTab(_homeIndex);
        return;
      case VoiceDestination.transactions:
        _selectTab(_transactionsIndex);
        return;
      case VoiceDestination.bills:
        _openBills();
        return;
      case VoiceDestination.wallet:
        _selectTab(_walletIndex);
        return;
      case VoiceDestination.savings:
        _selectTab(_homeIndex);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SetAsideScreen()),
        );
        return;
      case VoiceDestination.debts:
        _openDebts();
        return;
      case VoiceDestination.goals:
        _openSavings();
        return;
      case VoiceDestination.reports:
        _selectTab(_reportsIndex);
        return;
      case VoiceDestination.settings:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        return;
      case VoiceDestination.scanReceipt:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OcrScreen()),
        );
        return;
      case VoiceDestination.assistant:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatbotScreen()),
        );
        return;
      case VoiceDestination.expenseCategories:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CategoriesScreen()),
        );
        return;
      case VoiceDestination.payCycleHistory:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        );
        return;
      case VoiceDestination.reminders:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RemindersScreen()),
        );
        return;
      case VoiceDestination.help:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HelpScreen()),
        );
        return;
    }
  }

  int _currentIndex = _homeIndex;

  // Changing this key rebuilds Home so its balance cards reload after income
  // is added from the "+" sheet.
  int _homeRefreshKey = 0;

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  List<Widget> _pages() {
    return widget.pages ??
        [
          HomeScreen(
            key: ValueKey(_homeRefreshKey),
            onOpenTransactions: () => _selectTab(_transactionsIndex),
            onOpenWallets: () => _selectTab(_walletIndex),
            onOpenBills: _openBills,
            // Savings on Home opens the savings balance; Goals has its own
            // shortcut, where goals are added.
            onOpenGoals: _openGoals,
            onOpenDebts: _openDebts,
            onVoiceNavigate: _navigateFromVoice,
          ),
          const TransactionsScreen(),
          const ReportsScreen(),
          const WalletsScreen(),
        ];
  }

  // Things to record, one tap from anywhere, and Goals, where money is
  // saved toward a goal. Other places live on Home's Quick Actions and the
  // bottom bar instead.
  List<QuickAddAction> _quickAddActions() {
    return widget.quickAddActions ??
        [
          QuickAddAction(
            icon: Icons.arrow_upward,
            iconAsset: 'assets/icons/icons8-money-out-96.png',
            label: 'Expense',
            color: Colors.red,
            onSelected: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddExpenseScreen()),
            ),
          ),
          QuickAddAction(
            icon: Icons.arrow_downward,
            iconAsset: 'assets/icons/icons8-money-transfer-96.png',
            label: 'Income',
            color: Colors.green,
            onSelected: () async {
              final saved = await showIncomeWaterfall(context);
              if (saved && mounted) setState(() => _homeRefreshKey++);
            },
          ),
          QuickAddAction(
            icon: Icons.swap_horiz,
            iconAsset: 'assets/icons/icons8-exchange-96.png',
            label: 'Transfer',
            color: appPrimaryBlue,
            onSelected: () async {
              final saved = await showTransferSheet(context);
              if (saved && mounted) setState(() => _homeRefreshKey++);
            },
          ),
          // Scanning a receipt and speaking an expense are ways of recording
          // one, so they belong here rather than only on Home. Adding an
          // installment is set up once and becomes bills afterwards, so it
          // lives with the debts instead.
          QuickAddAction(
            icon: Icons.photo_camera_outlined,
            iconAsset: 'assets/icons/scan-receipt-96.png',
            label: 'Scan Receipt',
            color: appPrimaryBlue,
            onSelected: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const OcrScreen()),
            ),
          ),
          QuickAddAction(
            icon: Icons.mic_none_outlined,
            iconAsset: 'assets/icons/icons8-microphone-96.png',
            label: 'Voice Entry',
            color: appPrimaryBlue,
            onSelected: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VoiceRecognitionScreen(
                  autoStart: true,
                  onNavigate: _navigateFromVoice,
                  onIncomeSaved: () {
                    if (mounted) setState(() => _homeRefreshKey++);
                  },
                ),
              ),
            ),
          ),
          // Goals, as on Home: a goal is added there, and money is saved
          // toward one from its own page.
          QuickAddAction(
            icon: Icons.flag_outlined,
            iconAsset: 'assets/icons/icons8-goal-96.png',
            label: 'Goals',
            color: appPrimaryBlue,
            onSelected: _openGoals,
          ),
        ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return PopScope(
      // Back from another tab returns to Home before leaving the app.
      canPop: _currentIndex == _homeIndex,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _selectTab(_homeIndex);
      },
      child: Scaffold(
        backgroundColor: colors.pageBackground,
        body: BackToHomeScope(
          goHome: () => _selectTab(_homeIndex),
          child: IndexedStack(index: _currentIndex, children: _pages()),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => showQuickAddSheet(context, _quickAddActions()),
          tooltip: 'Quick add',
          backgroundColor: appPrimaryBlue,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 30),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          color: colors.card,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          height: 68,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              _NavItem(
                iconAsset: 'assets/icons/icons8-home-96.png',
                label: 'Home',
                selected: _currentIndex == _homeIndex,
                onTap: () => _selectTab(_homeIndex),
              ),
              _NavItem(
                iconAsset: 'assets/icons/icons8-transactions-96.png',
                label: 'Transactions',
                selected: _currentIndex == _transactionsIndex,
                onTap: () => _selectTab(_transactionsIndex),
              ),
              // Space for the "+" button docked in the middle.
              const SizedBox(width: 72),
              _NavItem(
                iconAsset: 'assets/icons/icons8-combo-chart-100.png',
                label: 'Reports',
                selected: _currentIndex == _reportsIndex,
                onTap: () => _selectTab(_reportsIndex),
              ),
              _NavItem(
                iconAsset: 'assets/icons/icons8-wallet-96.png',
                label: 'Wallets',
                selected: _currentIndex == _walletIndex,
                onTap: () => _selectTab(_walletIndex),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.iconAsset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String iconAsset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.appColors.primaryText
        : const Color(0xFF8A8A8A);

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Colored icons can't be tinted, so the selected tab is shown
              // with a highlight pill and a bold blue label instead.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? context.appColors.primaryTint
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Opacity(
                  opacity: selected ? 1 : 0.55,
                  child: Image.asset(iconAsset, width: 24, height: 24),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
