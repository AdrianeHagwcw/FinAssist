import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/models/chat_action.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/wallet.dart';

Wallet _wallet({
  required String id,
  required String name,
  WalletPurpose purpose = WalletPurpose.spending,
  bool receivesIncome = false,
}) => Wallet(
  id: id,
  name: name,
  type: WalletType.bank,
  balance: 1000,
  startingBalance: 1000,
  receivesIncome: receivesIncome,
  archived: false,
  sortOrder: 0,
  purpose: purpose,
);

void main() {
  final records = FinanceSnapshot(
    now: DateTime(2026, 10, 14),
    wallets: [
      _wallet(id: 'salary', name: 'Main Account', receivesIncome: true),
      _wallet(id: 'eastwest', name: 'EastWest Bank'),
      _wallet(id: 'bills', name: 'Bills', purpose: WalletPurpose.bills),
    ],
  );

  test('parses a transfer request and resolves its existing wallets', () {
    final action = parseChatAction(
      'Transfer ₱500 from salary to bills',
      records: records,
    );

    expect(action?.type, ChatActionType.transfer);
    expect(action?.amount, 500);
    expect(action?.sourceWalletId, 'salary');
    expect(action?.destinationWalletId, 'bills');
  });

  test('prepares a missing savings wallet without submitting the transfer', () {
    final action = parseChatAction(
      'Move 250 from salary to savings',
      records: records,
    );

    expect(action?.type, ChatActionType.transfer);
    expect(action?.destinationWalletId, savingsPlaceholderWalletId);
  });

  test('leaves a choice blank when more than one destination is requested', () {
    final action = parseChatAction(
      'Transfer 250 from salary to bills or savings',
      records: records,
    );

    expect(action?.type, ChatActionType.transfer);
    expect(action?.sourceWalletId, 'salary');
    expect(action?.destinationWalletId, isNull);
  });

  test('recognizes expense, income, and goal form requests', () {
    final expense = parseChatAction('Add expense ₱300 for lunch');
    final income = parseChatAction('Record income 2500 from salary');
    final goal = parseChatAction(
      'Create a savings goal for a laptop worth 40000',
    );

    expect(expense?.type, ChatActionType.expense);
    expect(expense?.amount, 300);
    expect(expense?.description, 'lunch');
    expect(income?.type, ChatActionType.income);
    expect(income?.amount, 2500);
    expect(income?.initialSource, 'Salary');
    expect(goal?.type, ChatActionType.savingsGoal);
    expect(goal?.amount, 40000);
    expect(goal?.name, 'laptop');
  });

  test('recognizes an expense amount even when the user says expenses plural', () {
    final action = parseChatAction('I want to add 500 in the expenses');

    expect(action?.type, ChatActionType.expense);
    expect(action?.amount, 500);
    expect(action?.description, isNull);
    expect(action?.label, 'Complete expense details');
  });

  test('recognizes salary income assigned to a named wallet', () {
    final action = parseChatAction(
      'Add 500 into salary in Eastbank wallet',
      records: records,
    );

    expect(action?.type, ChatActionType.income);
    expect(action?.amount, 500);
    expect(action?.initialSource, 'Salary');
    expect(action?.incomeWalletId, 'eastwest');
  });

  test('keeps an explicit expense description but does not guess category', () {
    final action = parseChatAction('Add 500 to expenses for lunch');

    expect(action?.type, ChatActionType.expense);
    expect(action?.amount, 500);
    expect(action?.description, 'lunch');
  });

  test('does not turn how-to questions into action proposals', () {
    expect(parseChatAction('How do I transfer money to savings?'), isNull);
    expect(parseChatAction('How do I add an expense?'), isNull);
  });
}
