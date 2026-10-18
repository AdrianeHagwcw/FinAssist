/// A local allow-list gate for deciding whether to send a question to Gemini.
///
/// This reduces accidental off-topic requests; it is not a security boundary.
/// Enforceable policy requires validation in a trusted backend.
bool isFinancialTopic(String message, {bool hasFinancialContext = false}) {
  final normalized = message.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.trim().isEmpty) return false;

  if (RegExp(
    r"\bwhat(?:'s| is) the weather\b|"
    r'\b(?:write|compose|tell me) (?:a )?(?:poem|joke|story|song)\b|'
    r'\b(?:give me|share) (?:a )?recipe\b|'
    r'\b(?:sports score|political debate|programming help|write code|debug)\b',
  ).hasMatch(normalized)) {
    return false;
  }

  if (hasFinancialContext && isFinancialFollowUp(normalized)) return true;

  final asksPurchaseAffordability = RegExp(
    r'\b(kaya ko|kaya kong|kaya ko bang|kaya ko ba|kakayanin ko|'
    r'makakaya ko|afford|affordable|can i buy|can i get|should i buy|'
    r'could i buy)\b',
  ).hasMatch(normalized);
  final mentionsPurchase = RegExp(
    r'\b(buy|buying|purchase|purchasing|bumili|bibili|mabili|bilhin|'
    r'makabili|airpods|ipad|tablet|headphones|earbuds|cellphone|cellphones|'
    r'phone|phones|computer|computers|'
    r'laptop|laptops|house|home|bahay|car|sasakyan)\b',
  ).hasMatch(normalized);
  if (asksPurchaseAffordability && mentionsPurchase) return true;

  if (RegExp(
    r'\bhow much (?:is|are|does|do)\b|'
    r'\b(?:current|latest|retail)?\s*price (?:of|for)\b|'
    r'\bmagkano (?:ang )?(?!(?:ang )?(?:ipon|maipon|'
    r'savings?|gastos?|expenses?|income|kita|sahod|sweldo|budget|'
    r'pera|wallet|utang|debt)\b)',
  ).hasMatch(normalized)) {
    return true;
  }

  if (RegExp(
    r'\b(insights?|analysis|analyze|analyse|financial planning|'
    r'money management|spending pattern|spending trend|'
    r'financial advice|money advice)\b',
  ).hasMatch(normalized)) {
    return true;
  }

  return RegExp(
    r'\b('
    r'money|finance|financial|budget|expense|expenses|spend|spending|spent|'
    r'income|salary|payday|paycheck|savings?|saving|save|saved|'
    r'save for|save toward|save towards|cash flow|net worth|'
    r'wallet|bill|bills|debt|loan|borrow|interest|inflation|credit|investment|invest|'
    r'bank|transaction|transactions|afford|affordable|cost|price|'
    r'financial health|health score|emergency fund|retirement|tax|'
    r'allowance|stipend|pension|freelance|remittance|fund|funding|purchase|purchases|overspend|'
    r'pera|gastos|gastusin|ipon|mag-ipon|kita|sahod|sweldo|bayad|utang|'
    r'bahay|bumili|bibili|mabili|bilhin|makabili|araw-araw|araw araw|'
    r'badyet|budgeting|finassist|pensiyon|padala|baon|'
    r'my records|my transactions|my expenses|my budget|my finances'
    r')\b',
  ).hasMatch(normalized);
}

/// Only short, explicit references inherit the previous financial topic.
/// Unrelated questions cannot become financial just because chat has history.
bool isFinancialFollowUp(String message) {
  final trimmed = message.trim();
  if (RegExp(
    r'^(why|why is that|how come|explain( that| more| it)?|'
    r'what does that mean|tell me more|bakit( naman| po)?|'
    r'paano( po)?|paki(paliwanag| explain))\s*[?!.]*$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return true;
  }
  if (RegExp(
    r'^(what about|how about|paano kung)\s+'
    r'(next week|next month|weekly|monthly|bukas|sa susunod na buwan)'
    r'\s*[?!.]*$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return true;
  }
  if (RegExp(
    r'^(?:pero\s+)?(?:gusto ko ring|gusto ko rin|what about|how about)'
    r'.*\b(?:buy|bumili|bibili|mabili|cellphone|cellphones|computer|'
    r'computers|laptop|bahay|house|car|sasakyan)\b',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return true;
  }
  return RegExp(
    r'^(and|at|then|what about|how about|paano kung)\s+'
    r'(₱|\$)?[0-9][0-9,]*(\.[0-9]+)?\s*[?!.]*$',
    caseSensitive: false,
  ).hasMatch(trimmed);
}
