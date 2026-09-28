import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings_provider.dart';
import '../services/user_profile_service.dart';

import '../models/debt.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/back_to_home.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/transfer_sheet.dart';
import '../services/bill_service.dart';
import '../services/goal_service.dart';
import '../services/reminder_scheduler.dart';
import '../services/reminder_service.dart';
import 'add_expense_screen.dart';
import 'bill_calendar_screen.dart';
import 'bill_detail_screen.dart';
import 'goal_detail_screen.dart';
import 'goals_screen.dart';
import 'home_screen.dart';
import 'income_waterfall_screen.dart';
import 'ocr_screen.dart';
import 'voice_recognition_screen.dart';
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
  static const _billsIndex = 2;
  static const _walletIndex = 3;

  /// Opens the Goals tab on savings or on a debts list.
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

    final settings = context.read<AppSettingsProvider>();
    // Subscribe per signed-in shell so another account never inherits categories.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      settings.updateFinancialProfile(null);
      _profileSubscription = UserProfileService.watchProfile().listen(
        (snapshot) => settings.updateFinancialProfile(snapshot.data()),
        onError: (Object error) => debugPrint('Profile preferences: $error'),
      );
    });

    WidgetsBinding.instance.addObserver(this);
    _reminders.start();
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
    } else if (payload == 'income') {
      // Payday: the user confirms the amount; nothing is added by itself.
      _selectTab(_homeIndex);
      final saved = await showIncomeWaterfall(context);
      if (saved && mounted) setState(() => _homeRefreshKey++);
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

  void _openDebts(DebtDirection direction) {
    _goalsTab.openDebts(direction);
    _openGoals();
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
            onOpenBills: () => _selectTab(_billsIndex),
            // Savings on Home opens the savings balance; the goals behind it
            // are one tap further in.
            onOpenDebts: () => _openDebts(DebtDirection.iOwe),
          ),
          const TransactionsScreen(),
          const BillCalendarScreen(),
          const WalletsScreen(),
        ];
  }

  // Things to record, one tap from anywhere. Places to go live on Home's
  // Quick Actions and the bottom bar instead.
  List<QuickAddAction> _quickAddActions() {
    return widget.quickAddActions ??
        [
          QuickAddAction(
            icon: Icons.arrow_upward,
            iconAsset: 'assets/icons/icons8-expenses-64.png',
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
            iconAsset: 'assets/icons/icons8-transactions-96.png',
            label: 'Transfer',
            color: appPrimaryBlue,
            onSelected: () async {
              final saved = await showTransferSheet(context);
              if (saved && mounted) setState(() => _homeRefreshKey++);
            },
          ),
          QuickAddAction(
            icon: Icons.savings_outlined,
            iconAsset: 'assets/icons/icons8-money-box-96.png',
            label: 'Save to Goal',
            color: appPrimaryBlue,
            onSelected: () async {
              final saved = await showSaveToGoal(context);
              if (saved && mounted) _openSavings();
            },
          ),
          // Scanning a receipt and speaking an expense are ways of recording
          // one, so they belong here rather than only on Home. Adding an
          // installment is set up once and becomes bills afterwards, so it
          // lives with the debts instead.
          QuickAddAction(
            icon: Icons.photo_camera_outlined,
            iconAsset: 'assets/icons/icons8-camera-96.png',
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
                builder: (context) =>
                    const VoiceRecognitionScreen(autoStart: true),
              ),
            ),
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
                iconAsset: 'assets/icons/icons8-calendar-96.png',
                label: 'Bills',
                selected: _currentIndex == _billsIndex,
                onTap: () => _selectTab(_billsIndex),
              ),
              _NavItem(
                iconAsset: 'assets/icons/icons8-wallet-96.png',
                label: 'Wallet',
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
