import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/models/financial_ai_guardrails.dart';
import 'package:testapp/models/financial_topic_validator.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/services/financial_ai_service.dart';

void main() {
  test('generated explanations cannot supply financial numbers or guarantees', () {
    for (final response in [
      'You have ₱500 left.',
      'Save twenty percent of your income.',
      'Magtabi ng dalawang libo.',
      'You can afford the purchase.',
      'This return is guaranteed.',
      '',
    ]) {
      expect(isUsableFinancialExplanation(response), isFalse, reason: response);
    }
    expect(isUsableFinancialExplanation('Protect essential expenses before choosing an optional savings contribution.'), isTrue);
    expect(isUsableFinancialExplanation('Unahin ang mahahalagang gastusin bago magtabi para sa gusto mong bilhin.'), isTrue);
  });

  test('follow-ups require context and explicit unrelated requests stay blocked', () {
    expect(isFinancialTopic('Bakit?'), isFalse);
    expect(isFinancialTopic('Bakit?', hasFinancialContext: true), isTrue);
    expect(isFinancialTopic('What about next month?', hasFinancialContext: true), isTrue);
    expect(isFinancialTopic('Write a poem about money', hasFinancialContext: true), isFalse);
    expect(isFinancialTopic('Who won the game?', hasFinancialContext: true), isFalse);
    for (final question in ['How should I manage my pension?', 'Paano pagkasyahin ang baon?', 'How should I handle freelance payments?']) {
      expect(isFinancialTopic(question), isTrue);
    }
  });

  test('financial summary uses shared calculations and excludes names and notes', () {
    final records = FinanceSnapshot(
      now: DateTime(2026, 10, 15),
      incomeFrequency: 'Irregular',
      wallets: const [Wallet(id: 'private-id', name: 'Private wallet', type: WalletType.cash,
        balance: 1600, startingBalance: 1600, receivesIncome: false, archived: false, sortOrder: 0)],
    );
    final summary = FirebaseFinancialAssistant.financialSummary(records);
    expect(summary['spendingWalletBalance'], 1600);
    expect(summary['safeToSpendToday'], records.safeToSpend.leftToday);
    expect(summary['planningEndExclusive'], DateTime(2026, 11, 1).toIso8601String());
    expect(summary['planningEndIsGuaranteedPayday'], false);
    expect(summary['recordCompleteness'], contains('completeness is not verified'));
    expect(summary.toString(), isNot(contains('Private wallet')));
    expect(summary.toString(), isNot(contains('private-id')));
    expect(FirebaseFinancialAssistant.financialSummary(null), {'available': false});
  });
}
