import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/models/voice_command.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/utils/categories.dart';

VoiceCommand heard(String words) =>
    interpretVoiceCommand(words, categories: expenseCategories);

Wallet wallet(
  String id,
  String name, {
  WalletType type = WalletType.bank,
  WalletPurpose purpose = WalletPurpose.spending,
}) => Wallet(
  id: id,
  name: name,
  type: type,
  purpose: purpose,
  balance: 1000,
  startingBalance: 1000,
  receivesIncome: false,
  archived: false,
  sortOrder: 0,
);

void main() {
  group('amounts said as words', () {
    test('Tagalog, English and the Spanish way of saying prices', () {
      const said = {
        'limandaan': '500',
        'isang libo': '1000',
        "isang libo't dalawang daan": '1200',
        'dalawang daan at limampu': '250',
        'apat na raan': '400',
        'sanlibo': '1000',
        'dalawang libo limandaan': '2500',
        'labindalawa pesos': '12 pesos',
        'two hundred fifty': '250',
        'one thousand five hundred': '1500',
        'twenty five pesos': '25 pesos',
        'bente singko': '25',
        '2 libo': '2000',
      };
      said.forEach((words, digits) {
        expect(spokenNumbersToDigits(words), digits, reason: words);
      });
    });

    test('a small number on its own stays a word', () {
      expect(spokenNumbersToDigits('isang kape'), 'isang kape');
      expect(spokenNumbersToDigits('two coffees'), 'two coffees');
      expect(spokenNumbersToDigits('lima na lang'), 'lima na lang');
    });

    test('fills the amount of an expense said in Tagalog', () {
      final command = heard('gumastos ako ng limandaan sa grocery');
      expect(command.type, VoiceCommandType.expense);
      expect(command.amount, 500);
    });
  });

  group('opens a section', () {
    test('in English, Tagalog or both', () {
      const commands = <(String, VoiceDestination)>[
        ('go home', VoiceDestination.home),
        ('open transaction history', VoiceDestination.transactions),
        ('ipakita ang mga gastos ko', VoiceDestination.transactions),
        ('open bill planner', VoiceDestination.bills),
        ('buksan ang bayarin', VoiceDestination.bills),
        ('open wallets', VoiceDestination.wallet),
        ('buksan ang pitaka', VoiceDestination.wallet),
        ('open savings', VoiceDestination.savings),
        ('ipakita ang ipon ko', VoiceDestination.savings),
        ('open installments', VoiceDestination.installments),
        ('patingin ng hulugan', VoiceDestination.installments),
        ('open debts', VoiceDestination.debts),
        ('show my loans', VoiceDestination.debts),
        ('buksan ang utang', VoiceDestination.debts),
        ('open goals', VoiceDestination.goals),
        ('open reports', VoiceDestination.reports),
        ('open settings', VoiceDestination.settings),
        ('scan receipt', VoiceDestination.scanReceipt),
        ('i-scan ang resibo', VoiceDestination.scanReceipt),
        ('open AI assistant', VoiceDestination.assistant),
        ('manage expense categories', VoiceDestination.expenseCategories),
        ('open pay cycle history', VoiceDestination.payCycleHistory),
        ('show income', VoiceDestination.payCycleHistory),
        ('open reminders', VoiceDestination.reminders),
        ('open help and support', VoiceDestination.help),
        ('pumunta sa tulong', VoiceDestination.help),
      ];
      for (final (words, destination) in commands) {
        final command = heard(words);
        expect(command.type, VoiceCommandType.navigation, reason: words);
        expect(command.destination, destination, reason: words);
      }
    });

    test('paying a bill, installment or debt goes to the Bill Planner', () {
      for (final words in [
        'pay my bills',
        'paid meralco bill 2500',
        'nagbayad ako ng hulugan sa phone 1500',
        'bayad utang 500',
      ]) {
        final command = heard(words);
        expect(command.type, VoiceCommandType.navigation, reason: words);
        expect(command.destination, VoiceDestination.bills, reason: words);
      }
    });

    test('money for a goal goes to Goals, where the goal is picked', () {
      final command = heard('add 500 to my laptop goal');
      expect(command.destination, VoiceDestination.goals);
    });
  });

  group('starts a form, filled in', () {
    test('income, in English or Tagalog', () {
      final english = heard('add salary 500');
      expect(english.type, VoiceCommandType.income);
      expect(english.amount, 500);
      expect(english.incomeSource, 'Salary');

      final tagalog = heard('natanggap ko na ang sweldo 15000');
      expect(tagalog.type, VoiceCommandType.income);
      expect(tagalog.amount, 15000);
      expect(tagalog.incomeSource, 'Salary');

      final sold = heard('nabenta ko ang lumang phone 3000');
      expect(sold.type, VoiceCommandType.income);
      expect(sold.incomeSource, 'Sold Something');

      expect(heard('baon 200').incomeSource, 'Allowance');
    });

    test('buying a gift or a business lunch is spending, not income', () {
      expect(heard('bought a gift for mom 500').type, VoiceCommandType.expense);
      expect(heard('business lunch 300').type, VoiceCommandType.expense);
      expect(heard('bumili ng regalo 800').type, VoiceCommandType.expense);
    });

    test('a transfer, with the wallets as said', () {
      final english = heard('transfer 500 from gcash to bdo');
      expect(english.type, VoiceCommandType.transfer);
      expect(english.amount, 500);
      expect(english.from, 'GCash');
      expect(english.to, 'BDO');

      final tagalog = heard('ilipat ang 1000 mula sa cash papunta sa gcash');
      expect(tagalog.type, VoiceCommandType.transfer);
      expect(tagalog.amount, 1000);
      expect(tagalog.from, 'Cash');
      expect(tagalog.to, 'GCash');

      final plain = heard('ilipat ang 300 sa bdo');
      expect(plain.from, isNull);
      expect(plain.to, 'BDO');
    });

    test('money into savings', () {
      for (final words in [
        'ipon 500',
        'itabi ang 500',
        'transfer 500 to savings',
        'add 500 to savings',
      ]) {
        final command = heard(words);
        expect(command.type, VoiceCommandType.transfer, reason: words);
        expect(command.toSavings, isTrue, reason: words);
        expect(command.amount, 500, reason: words);
      }
    });

    test('a bill, with its name', () {
      final english = heard('add bill meralco 2500');
      expect(english.type, VoiceCommandType.bill);
      expect(english.name, 'Meralco');
      expect(english.amount, 2500);

      final tagalog = heard('magdagdag ng bayarin na kuryente 1500 kada buwan');
      expect(tagalog.type, VoiceCommandType.bill);
      expect(tagalog.name, 'Kuryente');
      expect(tagalog.amount, 1500);
    });

    test('a goal, with its name and target', () {
      final english = heard('new goal emergency fund 50000');
      expect(english.type, VoiceCommandType.goal);
      expect(english.name, 'Emergency fund');
      expect(english.amount, 50000);

      final tagalog = heard('mag-ipon para sa laptop 30000');
      expect(tagalog.type, VoiceCommandType.goal);
      expect(tagalog.name, 'Laptop');
      expect(tagalog.amount, 30000);
    });

    test('an installment: each payment and how many', () {
      final english = heard('add installment phone 1500 a month 12 months');
      expect(english.type, VoiceCommandType.installment);
      expect(english.name, 'Phone');
      expect(english.amount, 1500);
      expect(english.perPayment, isTrue);
      expect(english.count, 12);

      final tagalog = heard('hulugan ng cellphone 15000 12 na buwan');
      expect(tagalog.type, VoiceCommandType.installment);
      expect(tagalog.name, 'Cellphone');
      expect(tagalog.amount, 15000);
      expect(tagalog.perPayment, isFalse, reason: 'the price, not a payment');
      expect(tagalog.count, 12);
    });

    test('a debt, named after who lent it', () {
      final tagalog = heard('may utang ako sa sss 20000 24 months');
      expect(tagalog.type, VoiceCommandType.debt);
      expect(tagalog.name, 'SSS');
      expect(tagalog.amount, 20000);
      expect(tagalog.count, 24);

      final english = heard('add loan from bdo 50000');
      expect(english.type, VoiceCommandType.debt);
      expect(english.name, 'BDO');
    });

    test('a wallet, with its name', () {
      final english = heard('add wallet gcash');
      expect(english.type, VoiceCommandType.wallet);
      expect(english.name, 'GCash');

      final tagalog = heard('magdagdag ng wallet na bdo');
      expect(tagalog.type, VoiceCommandType.wallet);
      expect(tagalog.name, 'BDO');
    });

    test('an expense is still the usual case', () {
      final command = heard('lunch at jollibee 150 pesos');
      expect(command.type, VoiceCommandType.expense);
      expect(command.amount, 150);
      expect(command.expense.category, 'Food');

      expect(heard('pamasahe 50').type, VoiceCommandType.expense);
    });
  });

  group('finds the wallet that was named', () {
    final wallets = [
      wallet('cash', 'Cash', type: WalletType.cash),
      wallet('gcash', 'GCash', type: WalletType.ewallet),
      wallet('bdo', 'BDO Unibank'),
      wallet(
        'save',
        'Savings',
        type: WalletType.bank,
        purpose: WalletPurpose.savings,
      ),
    ];

    test('by its name or the start of it', () {
      expect(matchSpokenWallet('GCash', wallets)?.id, 'gcash');
      expect(matchSpokenWallet('BDO', wallets)?.id, 'bdo');
      expect(matchSpokenWallet('bdo unibank', wallets)?.id, 'bdo');
    });

    test('by what it is, when there is only one', () {
      expect(matchSpokenWallet('cash', wallets)?.id, 'cash');
      expect(matchSpokenWallet('pera', wallets)?.id, 'cash');
      expect(matchSpokenWallet('bangko', wallets)?.id, 'bdo');
      expect(matchSpokenWallet('ipon', wallets)?.id, 'save');
    });

    test('none when nothing fits', () {
      expect(matchSpokenWallet('Maya', wallets), isNull);
      expect(matchSpokenWallet(null, wallets), isNull);
    });
  });
}
