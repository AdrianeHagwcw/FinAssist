import 'finance_snapshot.dart';
import 'wallet.dart';

enum ChatActionType { expense, income, transfer, savingsGoal }

class ChatAction {
  const ChatAction({
    required this.type,
    this.amount,
    this.description,
    this.name,
    this.sourceWalletId,
    this.destinationWalletId,
    this.incomeWalletId,
    this.initialSource,
  });

  final ChatActionType type;
  final double? amount;
  final String? description;
  final String? name;
  final String? sourceWalletId;
  final String? destinationWalletId;
  final String? incomeWalletId;
  final String? initialSource;

  String get label => switch (type) {
    ChatActionType.expense => 'Complete expense details',
    ChatActionType.income => 'Review income',
    ChatActionType.transfer => 'Review transfer',
    ChatActionType.savingsGoal => 'Review savings goal',
  };
}

/// Recognizes explicit requests for common FinAssist actions.
///
/// This parser only proposes opening an existing form. It never writes data,
/// and a request's values remain editable in that form before saving.
ChatAction? parseChatAction(String text, {FinanceSnapshot? records}) {
  final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty || RegExp(r'^(how|what|why)\b').hasMatch(normalized)) {
    return null;
  }

  final amount = _amountFrom(normalized);

  final isTransfer = RegExp(
    r'\b(transfer|move|send|ilipat|itabi)\b',
  ).hasMatch(normalized);
  if (isTransfer) {
    final destination = _destinationWallet(normalized, records);
    final mentionsTransferPurpose = RegExp(
      r'\b(bills?|bayarin|savings?|ipon)\b',
    ).hasMatch(normalized);
    if (destination != null || mentionsTransferPurpose) {
      return ChatAction(
        type: ChatActionType.transfer,
        amount: amount,
        sourceWalletId: _sourceWallet(normalized, records),
        destinationWalletId: destination?.id,
      );
    }
  }

  final isExpense = RegExp(
    r'\b(add|record|log)\s+(?:(?:an?\s+)?expense\b|'
    r'\d[\d,]*(?:\.\d{1,2})?\s+(?:in|to)\s+(?:the\s+)?expenses?\b)|'
    r'\b(?:i spent|spent|nagastos ko)\b',
  ).hasMatch(normalized);
  if (isExpense) {
    return ChatAction(
      type: ChatActionType.expense,
      amount: amount,
      description: _expenseDescription(text, normalized),
    );
  }

  final isIncome = RegExp(
    r'\b(add|record|log)\s+(?:an?\s+)?income\b|'
    r'\b(received|got paid|sweldo ko|sahod ko)\b|'
    r'\b(add|put|record|log)\b.*\b(salary|paycheck|sweldo|sahod)\b',
  ).hasMatch(normalized);
  if (isIncome) {
    final source =
        RegExp(r'\b(salary|paycheck|sweldo|sahod)\b').hasMatch(normalized)
        ? 'Salary'
        : null;
    return ChatAction(
      type: ChatActionType.income,
      amount: amount,
      initialSource: source,
      incomeWalletId: _incomeWallet(normalized, records),
    );
  }

  final isGoal = RegExp(
    r'\b(create|add|make|set up)\s+(?:a\s+)?(?:savings?\s+)?goal\b|'
    r'\b(create|add|make)\s+(?:a\s+)?goal\b',
  ).hasMatch(normalized);
  if (isGoal) {
    return ChatAction(
      type: ChatActionType.savingsGoal,
      amount: amount,
      name: _goalName(text, normalized),
    );
  }

  return null;
}

String? _incomeWallet(String text, FinanceSnapshot? records) {
  final wallets = records?.wallets.where((wallet) => !wallet.archived) ?? [];
  final requested = RegExp(
    r'\bin\s+([a-z0-9 _-]+?)(?:\s+wallet)?$',
  ).firstMatch(text)?.group(1)?.trim();
  if (requested == null || requested.isEmpty) return null;

  final normalizedRequested = _walletSearchText(requested);
  if (normalizedRequested.isEmpty) return null;

  final matches = wallets.where((wallet) {
    final walletName = _walletSearchText(wallet.name);
    return walletName == normalizedRequested ||
        walletName.startsWith(normalizedRequested) ||
        normalizedRequested.startsWith(walletName);
  }).toList();
  return matches.length == 1 ? matches.single.id : null;
}

String _walletSearchText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\b(wallet|account|bank)\b'), '')
    .replaceAll(RegExp(r'[^a-z0-9]'), '')
    .replaceFirst(RegExp(r'(wallet|account|bank)$'), '');

double? _amountFrom(String text) {
  final match = RegExp(
    r'(?:₱|php\s*)\s*(\d[\d,]*(?:\.\d{1,2})?)|'
    r'\b(\d[\d,]*(?:\.\d{1,2})?)\b(?!\s*(?:years?|months?|weeks?|days?))',
  ).firstMatch(text);
  final raw = match?.group(1) ?? match?.group(2);
  if (raw == null) return null;
  final value = double.tryParse(raw.replaceAll(',', ''));
  return value != null && value > 0 ? value : null;
}

Wallet? _destinationWallet(String text, FinanceSnapshot? records) {
  final wallets = records?.wallets.where((wallet) => !wallet.archived) ?? [];
  final requestsBills = RegExp(r'\b(bills?|bayarin)\b').hasMatch(text);
  final requestsSavings = RegExp(r'\b(savings?|ipon)\b').hasMatch(text);
  if (requestsBills && requestsSavings) return null;

  if (requestsBills) {
    return wallets.cast<Wallet?>().firstWhere(
          (wallet) => wallet?.purpose == WalletPurpose.bills,
          orElse: () => null,
        ) ??
        _placeholderWallet(
          billsPlaceholderWalletId,
          'Bills',
          WalletPurpose.bills,
        );
  }
  if (requestsSavings) {
    return wallets.cast<Wallet?>().firstWhere(
          (wallet) => wallet?.purpose == WalletPurpose.savings,
          orElse: () => null,
        ) ??
        _placeholderWallet(
          savingsPlaceholderWalletId,
          'Savings',
          WalletPurpose.savings,
        );
  }

  final match = RegExp(r'\bto\s+([a-z0-9 _-]+)$').firstMatch(text);
  final requestedName = match?.group(1)?.trim();
  if (requestedName == null || requestedName.isEmpty) return null;
  for (final wallet in wallets) {
    if (wallet.name.toLowerCase() == requestedName) return wallet;
  }
  return null;
}

String? _sourceWallet(String text, FinanceSnapshot? records) {
  final wallets = records?.wallets.where((wallet) => !wallet.archived) ?? [];
  final match = RegExp(
    r'\bfrom\s+([a-z0-9 _-]+?)(?=\s+to\b|$)',
  ).firstMatch(text);
  final requestedName = match?.group(1)?.trim();
  if (requestedName == null &&
      RegExp(r'\b(salary|paycheck|income|sweldo|sahod)\b').hasMatch(text)) {
    for (final wallet in wallets) {
      if (wallet.receivesIncome) return wallet.id;
    }
  }
  if (requestedName == null || requestedName.isEmpty) return null;

  if (RegExp(
    r'\b(salary|paycheck|income|sweldo|sahod)\b',
  ).hasMatch(requestedName)) {
    for (final wallet in wallets) {
      if (wallet.receivesIncome) return wallet.id;
    }
  }
  for (final wallet in wallets) {
    if (wallet.name.toLowerCase() == requestedName) return wallet.id;
  }
  return null;
}

Wallet _placeholderWallet(String id, String name, WalletPurpose purpose) =>
    Wallet(
      id: id,
      name: name,
      type: WalletType.other,
      balance: 0,
      startingBalance: 0,
      receivesIncome: false,
      archived: false,
      sortOrder: 1000,
      purpose: purpose,
    );

String? _expenseDescription(String original, String normalized) {
  var description = original
      .replaceFirst(
        RegExp(
          r'\b(?:i\s+want\s+to\s+)?(?:add|record|log)\s+'
          r'(?:(?:an?\s+)?expenses?\b|)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceFirst(
        RegExp(r'\b(?:in|to)\s+(?:the\s+)?expenses?\b', caseSensitive: false),
        '',
      )
      .replaceFirst(RegExp(r'\b(?:i\s+)?spent\b', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\bnagastos ko\b', caseSensitive: false), '');
  description = description.replaceFirst(
    RegExp(r'(?:₱|php\s*)?\s*\d[\d,]*(?:\.\d{1,2})?', caseSensitive: false),
    '',
  );
  description = description
      .replaceFirst(
        RegExp(
          r'^\s*(?:on|for|at|in|to|sa)\s+(?:the\s+)?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceFirst(
        RegExp(
          r'^\s*(?:i\s+)?(?:want\s+to\s+)?(?:add|record|log)\s+',
          caseSensitive: false,
        ),
        '',
      )
      .trim()
      .replaceAll(RegExp(r'^[,.\s]+|[,.\s]+$'), '');
  if (description.isEmpty ||
      RegExp(r'^(expenses?|expense|the|my)$', caseSensitive: false).hasMatch(
        description,
      )) {
    return null;
  }
  return description;
}

String? _goalName(String original, String normalized) {
  final match = RegExp(
    r'\b(?:for|toward|towards|para sa)\s+(.+?)(?=\s+(?:worth|for|of)\b|$)',
    caseSensitive: false,
  ).firstMatch(original);
  final name = match?.group(1)?.trim().replaceAll(RegExp(r'[.!?]+$'), '');
  final normalizedName = name?.replaceFirst(
    RegExp(r'^(?:a|an|the)\s+', caseSensitive: false),
    '',
  );
  if (normalizedName != null && normalizedName.isNotEmpty) {
    return normalizedName;
  }

  if (normalized.contains('emergency')) return 'Emergency fund';
  return null;
}
