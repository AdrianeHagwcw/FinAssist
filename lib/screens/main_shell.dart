import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/add_income_dialog.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/quick_add_sheet.dart';
import 'add_expense_screen.dart';
import 'chatbot_screen.dart';
import 'expenses_screen.dart';
import 'home_screen.dart';

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
          const ExpensesScreen(),
          const _ComingSoonTab(
            title: 'Goals',
            icon: Icons.savings_outlined,
            emptyTitle: 'Savings goals are coming soon',
            emptyMessage:
                'Soon you can set savings goals here and track your progress '
                'toward each one.',
          ),
          const _ComingSoonTab(
            title: 'Wallet',
            icon: Icons.account_balance_wallet_outlined,
            emptyTitle: 'Wallets are coming soon',
            emptyMessage:
                'Soon you can add your Cash, GCash, Maya and bank wallets here, '
                'each with its own balance.',
          ),
        ];
  }

  // Transfer, Bills and Goal shortcuts are added when those features exist.
  List<QuickAddAction> _quickAddActions() {
    return widget.quickAddActions ??
        [
          QuickAddAction(
            icon: Icons.arrow_upward,
            label: 'Expense',
            color: Colors.red,
            onSelected: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddExpenseScreen()),
            ),
          ),
          QuickAddAction(
            icon: Icons.arrow_downward,
            label: 'Income',
            color: Colors.green,
            onSelected: () async {
              final saved = await showAddIncomeDialog(context);
              if (saved && mounted) setState(() => _homeRefreshKey++);
            },
          ),
          QuickAddAction(
            icon: Icons.smart_toy_outlined,
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
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'Home',
                selected: _currentIndex == 0,
                onTap: () => _selectTab(0),
              ),
              _NavItem(
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long,
                label: 'Transactions',
                selected: _currentIndex == 1,
                onTap: () => _selectTab(1),
              ),
              // Space for the "+" button docked in the middle.
              const SizedBox(width: 72),
              _NavItem(
                icon: Icons.savings_outlined,
                selectedIcon: Icons.savings,
                label: 'Goals',
                selected: _currentIndex == 2,
                onTap: () => _selectTab(2),
              ),
              _NavItem(
                icon: Icons.account_balance_wallet_outlined,
                selectedIcon: Icons.account_balance_wallet,
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
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
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
              Icon(selected ? selectedIcon : icon, color: color, size: 26),
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
    required this.icon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final String title;
  final IconData icon;
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
        icon: icon,
        title: emptyTitle,
        message: emptyMessage,
      ),
    );
  }
}
