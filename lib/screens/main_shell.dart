import 'package:flutter/material.dart';

import '../models/debt.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/back_to_home.dart';
import '../widgets/debt_form_sheet.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/transfer_sheet.dart';
import 'add_expense_screen.dart';
import 'goals_screen.dart';
import 'home_screen.dart';
import 'income_waterfall_screen.dart';
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

class _MainShellState extends State<MainShell> {
  static const _homeIndex = 0;
  static const _transactionsIndex = 1;
  static const _goalsIndex = 2;
  static const _walletIndex = 3;

  /// Opens the Goals tab on savings or on a debts list.
  final _goalsTab = GoalsTabController();

  @override
  void dispose() {
    _goalsTab.dispose();
    super.dispose();
  }

  void _openSavings() {
    _selectTab(_goalsIndex);
    _goalsTab.openSavings();
  }

  void _openDebts(DebtDirection direction) {
    _selectTab(_goalsIndex);
    _goalsTab.openDebts(direction);
  }

  /// Adds an installment or a loan, then shows the list it went to.
  Future<void> _addDebt(DebtDirection direction) async {
    final saved = await showDebtFormSheet(context, direction: direction);
    if (saved != null && mounted) _openDebts(saved);
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
            onOpenSavings: _openSavings,
            onOpenDebts: () => _openDebts(DebtDirection.iOwe),
          ),
          const TransactionsScreen(),
          GoalsScreen(controller: _goalsTab),
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
          QuickAddAction(
            icon: Icons.receipt_long_outlined,
            iconAsset: 'assets/icons/icons8-receipt-96.png',
            label: 'Installment',
            color: appPrimaryBlue,
            onSelected: () => _addDebt(DebtDirection.iOwe),
          ),
          QuickAddAction(
            icon: Icons.handshake_outlined,
            iconAsset: 'assets/icons/lend-96.png',
            label: 'Lend',
            color: appPrimaryBlue,
            onSelected: () => _addDebt(DebtDirection.owedToMe),
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
                selected: _currentIndex == 0,
                onTap: () => _selectTab(0),
              ),
              _NavItem(
                iconAsset: 'assets/icons/icons8-transactions-96.png',
                label: 'Transactions',
                selected: _currentIndex == 1,
                onTap: () => _selectTab(1),
              ),
              // Space for the "+" button docked in the middle.
              const SizedBox(width: 72),
              _NavItem(
                iconAsset: 'assets/icons/icons8-goal-96.png',
                label: 'Goals',
                selected: _currentIndex == 2,
                onTap: () => _selectTab(2),
              ),
              _NavItem(
                iconAsset: 'assets/icons/icons8-wallet-96.png',
                label: 'Wallet',
                selected: _currentIndex == 3,
                onTap: () => _selectTab(3),
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
