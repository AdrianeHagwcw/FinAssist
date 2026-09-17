import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/transfer_sheet.dart';
import 'add_expense_screen.dart';
import 'chatbot_screen.dart';
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
          ),
          const TransactionsScreen(),
          const _ComingSoonTab(
            title: 'Goals',
            iconAsset: 'assets/icons/icons8-goal-96.png',
            emptyTitle: 'Savings goals are coming soon',
            emptyMessage:
                'Soon you can set savings goals here and track your progress '
                'toward each one.',
          ),
          const WalletsScreen(),
        ];
  }

  // Bills and Goal shortcuts are added when those features exist.
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
            icon: Icons.smart_toy_outlined,
            iconAsset: 'assets/icons/icons8-robot-48.png',
            label: 'AI Chat',
            color: appPrimaryBlue,
            onSelected: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ChatbotScreen()),
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
        body: IndexedStack(index: _currentIndex, children: _pages()),
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

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({
    required this.title,
    required this.iconAsset,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final String title;
  final String iconAsset;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: EmptyStateView(
        iconAsset: iconAsset,
        title: emptyTitle,
        message: emptyMessage,
      ),
    );
  }
}
