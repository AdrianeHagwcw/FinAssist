import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/models/financial_ai_guardrails.dart';
import 'package:testapp/models/financial_topic_validator.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/bill.dart';
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
    expect(
      isUsableFinancialExplanation(
        'Protect essential expenses before choosing an optional savings contribution.',
      ),
      isTrue,
    );
    expect(
      isUsableFinancialExplanation(
        'Unahin ang mahahalagang gastusin bago magtabi para sa gusto mong bilhin.',
      ),
      isTrue,
    );
  });

  test(
    'follow-ups require context and explicit unrelated requests stay blocked',
    () {
      expect(isFinancialTopic('Bakit?'), isFalse);
      expect(isFinancialTopic('Bakit?', hasFinancialContext: true), isTrue);
      expect(
        isFinancialTopic('What about next month?', hasFinancialContext: true),
        isTrue,
      );
      expect(
        isFinancialTopic('Write a poem about money', hasFinancialContext: true),
        isFalse,
      );
      expect(
        isFinancialTopic('Who won the game?', hasFinancialContext: true),
        isFalse,
      );
      expect(isFinancialTopic('Who are you?'), isFalse);
      expect(isFinancialTopic('Tell me about yourself'), isFalse);
      for (final question in [
        'How should I manage my pension?',
        'Paano pagkasyahin ang baon?',
        'How should I handle freelance payments?',
        'I keep running out of money before payday. What should I do?',
      ]) {
        expect(isFinancialTopic(question), isTrue);
      }
    },
  );

  test('recognizes the requested financial question examples', () {
    for (final question in [
      'I earn ₱500 daily. How much will I earn in 30 days?',
      'I spent ₱150 on lunch and ₱50 on transportation. Categorize my expenses.',
      'I want to save ₱6,000 in 6 months. How much should I save monthly?',
      'I earn ₱10,000 monthly and spend ₱8,500. Assess my financial situation.',
      'Can I afford to buy a new phone if I have ₱3,000 left?',
    ]) {
      expect(isFinancialTopic(question), isTrue, reason: question);
    }
    expect(
      isFinancialTopic('Can you teach me how to create a video game?'),
      isFalse,
    );
    expect(isFinancialTopic('What should I do with this situation?'), isTrue);
  });

  test(
    'retries transient AI failures only a bounded number of times',
    () async {
      var attempts = 0;
      final result = await requestFinancialAssistant(() async {
        attempts++;
        if (attempts < 3) {
          throw const FinancialAssistantFailure('busy', null, true);
        }
        return 'success';
      });

      expect(result, 'success');
      expect(attempts, 3);
    },
  );

  test('Gemini overload signatures are classified as transient failures', () {
    expect(
      isGeminiOverloadError(
        Exception(
          'Overloaded prefill queue, preempted by higher priority '
          'PREFILL_QUEUE_PREEMPTED',
        ),
      ),
      isTrue,
    );
    expect(isGeminiOverloadError(Exception('invalid request')), isFalse);
    expect(
      const FinancialAssistantFailure('busy', null, true).transient,
      isTrue,
    );
    expect(
      classifyGeminiFailure(Exception('Firebase App Check token rejected')),
      FinancialAssistantFailureKind.appCheck,
    );
    expect(
      classifyGeminiFailure(TimeoutException('request timed out')),
      FinancialAssistantFailureKind.network,
    );
    expect(
      failureMessageFor(FinancialAssistantFailureKind.quota),
      contains('usage limit'),
    );
  });

  test(
    'financial summary uses shared calculations and excludes names and notes',
    () {
      final records = FinanceSnapshot(
        now: DateTime(2026, 10, 15),
        incomeFrequency: 'Irregular',
        wallets: const [
          Wallet(
            id: 'private-id',
            name: 'Private wallet',
            type: WalletType.cash,
            balance: 1600,
            startingBalance: 1600,
            receivesIncome: false,
            archived: false,
            sortOrder: 0,
          ),
        ],
      );
      final summary = FirebaseFinancialAssistant.financialSummary(records);
      expect(summary['spendingWalletBalance'], 1600);
      expect(summary['safeToSpendToday'], records.safeToSpend.leftToday);
      expect(
        summary['planningEndExclusive'],
        DateTime(2026, 11, 1).toIso8601String(),
      );
      expect(summary['planningEndIsGuaranteedPayday'], false);
      expect(
        summary['recordCompleteness'],
        contains('completeness is not verified'),
      );
      expect(summary['recordLevelFacts'], isA<Map>());
      expect(summary.toString(), isNot(contains('Private wallet')));
      expect(summary.toString(), isNot(contains('private-id')));
      expect(FirebaseFinancialAssistant.financialSummary(null), {
        'available': false,
      });
    },
  );

  test('financial summary includes like-for-like spending comparisons', () {
    final summary = FirebaseFinancialAssistant.financialSummary(
      FinanceSnapshot(
        now: DateTime(2026, 10, 14),
        transactions: [
          AppTransaction(
            id: 'recent',
            type: TransactionType.expense,
            amount: 200,
            label: 'Food',
            date: DateTime(2026, 10, 14),
            note: 'private note',
          ),
          AppTransaction(
            id: 'previous',
            type: TransactionType.expense,
            amount: 100,
            label: 'Bills',
            date: DateTime(2026, 10, 10),
          ),
        ],
      ),
    );

    final periods =
        (summary['recentSpendingComparisons'] as Map)['periods'] as List;
    final threeDayComparison = periods.first as Map;
    expect(threeDayComparison['daysPerPeriod'], 3);
    expect((threeDayComparison['recent'] as Map)['recordedSpending'], 200);
    expect((threeDayComparison['previous'] as Map)['recordedSpending'], 100);
    final recordLevelFacts = summary['recordLevelFacts'] as Map;
    final transactionFacts = recordLevelFacts['transactions'] as Map;
    final transactionRecords = transactionFacts['records'] as List;
    expect(transactionRecords, isNotEmpty);
    final latestRecord = transactionRecords.first as Map;
    expect(latestRecord['amount'], 200);
    expect(latestRecord['label'], 'Food');
    expect(latestRecord['type'], 'expense');
    expect(summary.toString(), isNot(contains('private note')));
  });

  test(
    'record-level facts identify repeated bill pressure without IDs or notes',
    () {
      final summary = FirebaseFinancialAssistant.financialSummary(
        FinanceSnapshot(
          now: DateTime(2026, 10, 14),
          bills: [
            BillInstance(
              id: 'rent-1',
              billId: 'rent',
              name: 'Rent',
              amount: 5000,
              category: 'Housing',
              dueDate: DateTime(2026, 10, 1),
              status: BillStatus.unpaid,
            ),
            BillInstance(
              id: 'rent-2',
              billId: 'rent',
              name: 'Rent',
              amount: 5000,
              category: 'Housing',
              dueDate: DateTime(2026, 11, 1),
              status: BillStatus.partial,
              amountPaid: 1000,
            ),
          ],
        ),
      );

      final facts = summary['recordLevelFacts'] as Map;
      final signals = facts['recurringBillSignals'] as List;
      expect(signals, hasLength(1));
      expect((signals.single as Map)['name'], 'Rent');
      expect((signals.single as Map)['totalRemaining'], 9000);
      expect(summary.toString(), isNot(contains('rent-1')));
      expect(summary.toString(), isNot(contains('rent-2')));
    },
  );
}
