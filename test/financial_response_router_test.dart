import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/backend/services/financial_response_router.dart';

void main() {
  test('routes factual questions to deterministic calculations', () {
    expect(
      routeFinancialResponse('How much have I saved?').mode,
      FinancialResponseMode.ruleBased,
    );
    expect(
      routeFinancialResponse('What is my total income this month?').mode,
      FinancialResponseMode.ruleBased,
    );
    expect(
      routeFinancialResponse('What is my outstanding debt?').mode,
      FinancialResponseMode.ruleBased,
    );
  });

  test('routes personalized questions to hybrid interpretation', () {
    for (final question in [
      'How am I progressing toward my savings goal?',
      'How can I save more money?',
      'Why did my expenses increase?',
      'Compare my income and expenses over three months.',
      'What should I prioritize financially?',
    ]) {
      expect(
        routeFinancialResponse(question).mode,
        FinancialResponseMode.hybrid,
        reason: question,
      );
    }
  });

  test('routes education questions to Gemini', () {
    expect(
      routeFinancialResponse('Explain how budgeting works.').mode,
      FinancialResponseMode.gemini,
    );
  });

  test('routes equivalent Tagalog questions by intent', () {
    expect(
      routeFinancialResponse('Magkano ang naipon ko?').mode,
      FinancialResponseMode.ruleBased,
    );
    expect(
      routeFinancialResponse('Paano ako umuunlad sa savings goal ko?').mode,
      FinancialResponseMode.hybrid,
    );
    expect(
      routeFinancialResponse('Paano ko pamahalaan ang utang ko?').mode,
      FinancialResponseMode.hybrid,
    );
  });
}
