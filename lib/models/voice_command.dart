import 'expense_guess.dart';
import '../utils/income_sources.dart';

enum VoiceDestination {
  home,
  transactions,
  bills,
  wallet,
  savings,
  debts,
  goals,
  reports,
  settings,
  scanReceipt,
  assistant,
  expenseCategories,
  payCycleHistory,
  reminders,
  help,
}

enum VoiceCommandType { expense, income, navigation }

class VoiceCommand {
  const VoiceCommand({
    required this.type,
    required this.expense,
    this.incomeSource,
    this.destination,
  });

  final VoiceCommandType type;
  final ExpenseGuess expense;
  final String? incomeSource;
  final VoiceDestination? destination;

  double? get amount => expense.amount;
}

VoiceCommand interpretVoiceCommand(
  String words, {
  required Iterable<String> categories,
}) {
  final expense = guessFromSpeech(words, categories: categories);
  final normalized = words.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  final destination = _destinationFor(normalized, expense.amount);

  if (destination != null) {
    return VoiceCommand(
      type: VoiceCommandType.navigation,
      expense: expense,
      destination: destination,
    );
  }

  final source = _incomeSourceFor(normalized);
  final incomeCommand = RegExp(
    r'\b(income|paycheck|payday|wages|salary)\b',
  ).hasMatch(normalized);
  if (source != null || incomeCommand) {
    return VoiceCommand(
      type: VoiceCommandType.income,
      expense: expense,
      incomeSource: source ?? otherIncomeSource,
    );
  }

  return VoiceCommand(type: VoiceCommandType.expense, expense: expense);
}

String? _incomeSourceFor(String words) {
  // Pay by the day or the hour is a wage; checked first, so "daily wage"
  // is never read as a salary.
  if (RegExp(r'\b(wage|wages|arawan|daily pay)\b').hasMatch(words)) {
    return 'Wage';
  }
  if (RegExp(r'\b(salary|paycheck|payday)\b').hasMatch(words)) {
    return 'Salary';
  }
  if (RegExp(r'\b(allowance|allowances)\b').hasMatch(words)) {
    return 'Allowance';
  }
  if (RegExp(r'\b(part time job|part time|parttime)\b').hasMatch(words)) {
    return 'Part-time Job';
  }
  if (RegExp(r'\b(business)\b').hasMatch(words)) return 'Business';
  if (RegExp(r'\b(freelance|freelancing)\b').hasMatch(words)) {
    return 'Freelance';
  }
  if (RegExp(r'\b(scholarship)\b').hasMatch(words)) return 'Scholarship';
  if (RegExp(r'\b(gift)\b').hasMatch(words)) return 'Gift';
  if (RegExp(r'\b(refund)\b').hasMatch(words)) return 'Refund';
  if (RegExp(r'\b(sold something|sold item|sale)\b').hasMatch(words)) {
    return 'Sold Something';
  }
  return null;
}

VoiceDestination? _destinationFor(String words, double? amount) {
  if (RegExp(
    r'\b(pay cycle|pay period|paycheck|income) history\b',
  ).hasMatch(words)) {
    return VoiceDestination.payCycleHistory;
  }

  const destinations = <VoiceDestination, List<String>>{
    VoiceDestination.home: ['home', 'dashboard'],
    VoiceDestination.transactions: [
      'transactions',
      'transaction history',
      'history',
      'expenses',
    ],
    VoiceDestination.bills: ['bill planner', 'bills', 'bill calendar'],
    VoiceDestination.wallet: ['wallets', 'wallet'],
    VoiceDestination.savings: ['savings', 'set aside'],
    // The screen is called Installments now. The older words stay, because
    // people still say them and they cost nothing to keep listening for.
    VoiceDestination.debts: [
      'installments',
      'installment',
      'instalments',
      'instalment',
      'debts',
      'debt',
      'loan',
      'loans',
    ],
    VoiceDestination.goals: ['goals', 'goal'],
    VoiceDestination.reports: ['reports', 'report'],
    VoiceDestination.settings: ['settings', 'profile'],
    VoiceDestination.scanReceipt: [
      'scan receipt',
      'scan a receipt',
      'receipt scanner',
      'receipt scan',
    ],
    VoiceDestination.assistant: [
      'assistant',
      'ai assistant',
      'chatbot',
      'chat bot',
    ],
    VoiceDestination.expenseCategories: [
      'expense categories',
      'manage categories',
      'categories',
    ],
    VoiceDestination.payCycleHistory: [
      'pay cycle history',
      'paycheck history',
      'pay period history',
    ],
    VoiceDestination.reminders: ['reminders', 'notifications'],
    VoiceDestination.help: ['help', 'support'],
  };
  final hasNavigationVerb = RegExp(
    r'\b(open|show|view|go|navigate|visit|switch|take me|scan|start|launch)\b',
  ).hasMatch(words);

  for (final entry in destinations.entries) {
    final matches = entry.value.any(
      (phrase) => RegExp(
        '\\b${phrase.split(' ').map(RegExp.escape).join(r'\s+')}\\b',
      ).hasMatch(words),
    );
    if (matches && (hasNavigationVerb || amount == null)) return entry.key;
  }
  return null;
}
