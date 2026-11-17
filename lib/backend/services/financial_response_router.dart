enum FinancialResponseMode { ruleBased, gemini, hybrid }

class FinancialResponseRoute {
  const FinancialResponseRoute({
    required this.mode,
    required this.intent,
    required this.requiresFinancialData,
    required this.requiresInterpretation,
  });

  final FinancialResponseMode mode;
  final String intent;
  final bool requiresFinancialData;
  final bool requiresInterpretation;
}

FinancialResponseRoute routeFinancialResponse(String question) {
  final text = question.toLowerCase().trim();

  if (RegExp(
    r'\b(explain|what is|teach me|how does).*\b(budget|budgeting|finance|'
    r'money management|ipaliwanag|ano ang)\b',
  ).hasMatch(text)) {
    return const FinancialResponseRoute(
      mode: FinancialResponseMode.gemini,
      intent: 'financial_education',
      requiresFinancialData: false,
      requiresInterpretation: true,
    );
  }

  if (RegExp(
    r'\b(how am i progressing|progress|why did|why is|how can i|how do i|'
    r'what should i|improv|manage .*better|prioriti[sz]|compare|'
    r'financially improving|based on my|based on your|'
    r'paano ako.*(?:progress|umunlad|goal)|bakit.*(?:gastos|ipon)|'
    r'paano ko.*(?:ipon|utang|gastos)|ano ang dapat kong unahin|'
    r'ikumpara|paghahambing)\b',
  ).hasMatch(text)) {
    return const FinancialResponseRoute(
      mode: FinancialResponseMode.hybrid,
      intent: 'personalized_financial_analysis',
      requiresFinancialData: true,
      requiresInterpretation: true,
    );
  }

  if (RegExp(
        r'^(?:how much|what is|what are|how many)\b.*\b(?:saved|save|income|'
        r'expenses?|spent|balance|money|debt|owe|savings?)\b',
      ).hasMatch(text) ||
      RegExp(
        r'\b(?:total income|current savings?|current balance|outstanding debt|'
        r'how much have i saved|magkano.*(?:naipon|ipon|kita|gastos|'
        r'utang|balanse))\b',
      ).hasMatch(text)) {
    return const FinancialResponseRoute(
      mode: FinancialResponseMode.ruleBased,
      intent: 'financial_fact',
      requiresFinancialData: true,
      requiresInterpretation: false,
    );
  }

  return const FinancialResponseRoute(
    mode: FinancialResponseMode.hybrid,
    intent: 'uncertain_financial_analysis',
    requiresFinancialData: true,
    requiresInterpretation: true,
  );
}
