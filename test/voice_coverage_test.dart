import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/voice_command.dart';
import 'package:testapp/backend/utils/categories.dart';

/// What a panel might say to Voice Entry, in English, Tagalog and Taglish,
/// and what each must open: the kind of form, the category and the amount.
/// A null category or amount is not checked: no category fits ("gupit",
/// "laundry") or nothing was said.
const said = <(String, VoiceCommandType, String?, double?)>[
  // Food.
  ('Lunch sa Jollibee 150', VoiceCommandType.expense, 'Food', 150),
  ('nagkape ako sa Starbucks 180', VoiceCommandType.expense, 'Food', 180),
  ('bumili ako ng siopao 35', VoiceCommandType.expense, 'Food', 35),
  ('ulam 120', VoiceCommandType.expense, 'Food', 120),
  ('palengke limandaan', VoiceCommandType.expense, 'Food', 500),
  ('groceries sa Puregold 1250', VoiceCommandType.expense, 'Food', 1250),
  ('milk tea 120', VoiceCommandType.expense, 'Food', 120),
  ('bigas isang libo dalawang daan', VoiceCommandType.expense, 'Food', 1200),
  ('merienda singkwenta', VoiceCommandType.expense, 'Food', 50),
  ("kumain kami sa Max's 900", VoiceCommandType.expense, 'Food', 900),
  ('Jolly Hotdog 45', VoiceCommandType.expense, 'Food', 45),
  ('corndog 85', VoiceCommandType.expense, 'Food', 85),
  ('tubig na mineral 25', VoiceCommandType.expense, 'Food', 25),
  ('bottled water 20', VoiceCommandType.expense, 'Food', 20),
  // Transportation.
  ('pamasahe sa jeep 13', VoiceCommandType.expense, 'Transportation', 13),
  ('nag grab ako 250', VoiceCommandType.expense, 'Transportation', 250),
  ('angkas 120', VoiceCommandType.expense, 'Transportation', 120),
  ('tricycle bente', VoiceCommandType.expense, 'Transportation', 20),
  ('bus papuntang Baguio 750', VoiceCommandType.expense, 'Transportation', 750),
  ('nagpa gas ako 1500', VoiceCommandType.expense, 'Transportation', 1500),
  ('toll 120', VoiceCommandType.expense, 'Transportation', 120),
  ('LRT 30', VoiceCommandType.expense, 'Transportation', 30),
  ('beep card load 100', VoiceCommandType.expense, 'Transportation', 100),
  (
    'plane ticket papuntang Cebu 3500',
    VoiceCommandType.expense,
    'Transportation',
    3500,
  ),
  ('UV express 60', VoiceCommandType.expense, 'Transportation', 60),
  ('padyak 15', VoiceCommandType.expense, 'Transportation', 15),
  ('change oil 1800', VoiceCommandType.expense, 'Transportation', 1800),
  ('vulcanizing 100', VoiceCommandType.expense, 'Transportation', 100),
  // Bacoor's colour-coded multicabs, told apart from Yellow Cab Pizza.
  ('yellow cab 15', VoiceCommandType.expense, 'Transportation', 15),
  (
    'sumakay ako ng yellow cab 20',
    VoiceCommandType.expense,
    'Transportation',
    20,
  ),
  (
    'yellow cab papuntang SM Bacoor 25',
    VoiceCommandType.expense,
    'Transportation',
    25,
  ),
  ('pamasahe sa yellow cab 13', VoiceCommandType.expense, 'Transportation', 13),
  ('blue cab 13', VoiceCommandType.expense, 'Transportation', 13),
  (
    'green cab papuntang Molino 18',
    VoiceCommandType.expense,
    'Transportation',
    18,
  ),
  ('multicab 20', VoiceCommandType.expense, 'Transportation', 20),
  ('yellow cab pizza 499', VoiceCommandType.expense, 'Food', 499),
  ('pizza sa yellow cab 650', VoiceCommandType.expense, 'Food', 650),
  ('kumain kami sa yellow cab 1200', VoiceCommandType.expense, 'Food', 1200),
  ('yellow cab 899', VoiceCommandType.expense, 'Food', 899),
  // Shopping.
  ('bumili ako ng damit 500', VoiceCommandType.expense, 'Shopping', 500),
  ('toothpaste 95', VoiceCommandType.expense, 'Shopping', 95),
  ('deodorant 120', VoiceCommandType.expense, 'Shopping', 120),
  ('medyas 99', VoiceCommandType.expense, 'Shopping', 99),
  ('cellphone 8999', VoiceCommandType.expense, 'Shopping', 8999),
  ('laptop 35000', VoiceCommandType.expense, 'Shopping', 35000),
  ('power bank 799', VoiceCommandType.expense, 'Shopping', 799),
  ('electric fan 1200', VoiceCommandType.expense, 'Shopping', 1200),
  ('kaldero 450', VoiceCommandType.expense, 'Shopping', 450),
  ('regalo kay mama 1000', VoiceCommandType.expense, 'Shopping', 1000),
  // Bills.
  ('kuryente 2500', VoiceCommandType.expense, 'Bills', 2500),
  ('tubig 450', VoiceCommandType.expense, 'Bills', 450),
  ('Globe load 50', VoiceCommandType.expense, 'Bills', 50),
  ('nagpaload ako 100', VoiceCommandType.expense, 'Bills', 100),
  ('upa 3500', VoiceCommandType.expense, 'Bills', 3500),
  ('dorm 3000', VoiceCommandType.expense, 'Bills', 3000),
  ('LPG 1000', VoiceCommandType.expense, 'Bills', 1000),
  ('gasul 950', VoiceCommandType.expense, 'Bills', 950),
  ('credit card bill 5000', VoiceCommandType.bill, null, 5000),
  // Entertainment.
  ('Netflix 549', VoiceCommandType.expense, 'Entertainment', 549),
  ('ML diamonds 100', VoiceCommandType.expense, 'Entertainment', 100),
  ('bowling 300', VoiceCommandType.expense, 'Entertainment', 300),
  ('Enchanted Kingdom 1500', VoiceCommandType.expense, 'Entertainment', 1500),
  ('hotel 3500', VoiceCommandType.expense, 'Entertainment', 3500),
  // Healthcare.
  ('paracetamol 20', VoiceCommandType.expense, 'Healthcare', 20),
  ('Decolgen 15', VoiceCommandType.expense, 'Healthcare', 15),
  ('salonpas 66', VoiceCommandType.expense, 'Healthcare', 66),
  ('blood test 800', VoiceCommandType.expense, 'Healthcare', 800),
  ('gym membership 1500', VoiceCommandType.expense, 'Healthcare', 1500),
  // Education, supplies, pets and fees.
  ('tuition 15000', VoiceCommandType.expense, 'Education', 15000),
  ('field trip 1200', VoiceCommandType.expense, 'Education', 1200),
  ('tutor 500', VoiceCommandType.expense, 'Education', 500),
  ('bond paper 250', VoiceCommandType.expense, 'Supplies', 250),
  ('anti rabies 400', VoiceCommandType.expense, 'Pets', 400),
  ('cash in fee 15', VoiceCommandType.expense, 'Service Charge', 15),
  ('transfer fee 25', VoiceCommandType.expense, 'Service Charge', 25),
  // Amounts said every way.
  ('pagkain isang libo limandaan', VoiceCommandType.expense, 'Food', 1500),
  ('pagkain 1.5k', VoiceCommandType.expense, 'Food', 1500),
  ('pagkain one hundred fifty', VoiceCommandType.expense, 'Food', 150),
  ('pagkain tatlong daan at limampu', VoiceCommandType.expense, 'Food', 350),
  ('pagkain P250', VoiceCommandType.expense, 'Food', 250),
  ('pagkain two thousand five hundred', VoiceCommandType.expense, 'Food', 2500),
  // Income, transfers and other commands.
  ('bonus 5000', VoiceCommandType.income, null, 5000),
  ('13th month pay 20000', VoiceCommandType.income, null, 20000),
  ('padala ni papa 3000', VoiceCommandType.income, null, 3000),
  ('commission 2500', VoiceCommandType.income, null, 2500),
  ('cash in 500 sa GCash', VoiceCommandType.transfer, null, 500),
  ('withdraw 2000 sa ATM', VoiceCommandType.transfer, null, 2000),
  ('transfer 500 from GCash to BDO', VoiceCommandType.transfer, null, 500),
  ('add bill Meralco 2500', VoiceCommandType.bill, null, 2500),
  ('mag ipon para sa laptop 30000', VoiceCommandType.goal, null, 30000),
  ('add wallet GCash 500', VoiceCommandType.wallet, null, 500),
  ('buksan ang reports', VoiceCommandType.navigation, null, null),
  // Snacks, biscuits and candies, as speech writes them.
  ('fudgee bar 10', VoiceCommandType.expense, 'Food', 10),
  ('mamon 15', VoiceCommandType.expense, 'Food', 15),
  ('haw flakes 5', VoiceCommandType.expense, 'Food', 5),
  ('hello panda 25', VoiceCommandType.expense, 'Food', 25),
  ('choco pie 12', VoiceCommandType.expense, 'Food', 12),
  ('pic a 20', VoiceCommandType.expense, 'Food', 20),
  ('bingo biscuit 10', VoiceCommandType.expense, 'Food', 10),
  ('ding dong 15', VoiceCommandType.expense, 'Food', 15),
  ('piattos at nova 50', VoiceCommandType.expense, 'Food', 50),
  ('skyflakes 8', VoiceCommandType.expense, 'Food', 8),
  ('choc nut 2', VoiceCommandType.expense, 'Food', 2),
  ('mik mik 5', VoiceCommandType.expense, 'Food', 5),
  ('piattos 25', VoiceCommandType.expense, 'Food', 25),
  ('tattoos 20', VoiceCommandType.expense, 'Food', 20),
  ('piatos 25', VoiceCommandType.expense, 'Food', 25),
  ('potato chips 35', VoiceCommandType.expense, 'Food', 35),
  ('potato fries 60', VoiceCommandType.expense, 'Food', 60),
  ('banana chips 30', VoiceCommandType.expense, 'Food', 30),
  ('corn chips 25', VoiceCommandType.expense, 'Food', 25),
  ('snowbear 1', VoiceCommandType.expense, 'Food', 1),
  ('snow bear 1', VoiceCommandType.expense, 'Food', 1),
  // Said the way people talk.
  (
    'Nagbayad ako ng 2500 sa Meralco kahapon',
    VoiceCommandType.expense,
    'Bills',
    2500,
  ),
  ('gumastos ako ng 300 sa grocery', VoiceCommandType.expense, 'Food', 300),
  (
    'bumili ako ng gamot sa Watsons 450',
    VoiceCommandType.expense,
    'Healthcare',
    450,
  ),
  ('nag taxi ako pauwi 280', VoiceCommandType.expense, 'Transportation', 280),
  ('nanood kami ng sine 600', VoiceCommandType.expense, 'Entertainment', 600),
  ('nagpa check up ako 700', VoiceCommandType.expense, 'Healthcare', 700),
  (
    'pinagawa ko yung motor 1500',
    VoiceCommandType.expense,
    'Transportation',
    1500,
  ),
  ('pambili ng gatas 300', VoiceCommandType.expense, 'Food', 300),
  ('formula milk ni baby 900', VoiceCommandType.expense, 'Food', 900),
  ('diaper ni baby 500', VoiceCommandType.expense, 'Shopping', 500),
  ('nag grab food ako 350', VoiceCommandType.expense, 'Food', 350),
  ('nag lalamove ako 200', VoiceCommandType.expense, 'Transportation', 200),
  ('Shopee checkout 1299', VoiceCommandType.expense, 'Shopping', 1299),
  ('bayad sa doktor 500', VoiceCommandType.expense, 'Healthcare', 500),
  ('ospital 5000', VoiceCommandType.expense, 'Healthcare', 5000),
  ('kumain sa labas 800', VoiceCommandType.expense, 'Food', 800),
  ('date night sa Vikings 3000', VoiceCommandType.expense, 'Food', 3000),
  ('pang load 100', VoiceCommandType.expense, 'Bills', 100),
  (
    'pang tuition ng kapatid ko 5000',
    VoiceCommandType.expense,
    'Education',
    5000,
  ),
  ('nagpa xerox ako ng reviewer 45', VoiceCommandType.expense, 'Education', 45),
  (
    'bumili ng notebook at ballpen 120',
    VoiceCommandType.expense,
    'Supplies',
    120,
  ),
  ('pagkain ng aso 450', VoiceCommandType.expense, 'Pets', 450),
  ('nagpavet si brownie 800', VoiceCommandType.expense, 'Pets', 800),
  ('nag cash in ako ng 1000 sa GCash', VoiceCommandType.transfer, null, 1000),
  ('nag withdraw ako ng 3000', VoiceCommandType.transfer, null, 3000),
  ('ilipat mo 500 sa savings', VoiceCommandType.transfer, null, 500),
  ('sweldo ko ngayon 18000', VoiceCommandType.income, null, 18000),
  ('binigyan ako ni lola ng 500', VoiceCommandType.income, null, 500),
  ('nabenta ko yung cellphone 5000', VoiceCommandType.income, null, 5000),
  ('kinita ko sa sideline 2000', VoiceCommandType.income, null, 2000),
  ('refund galing Shopee 299', VoiceCommandType.income, null, 299),
  ('nagbayad ako ng upa 4000', VoiceCommandType.expense, 'Bills', 4000),
  ('internet bill 1599', VoiceCommandType.bill, null, 1599),
  ('Spotify Premium 149', VoiceCommandType.expense, 'Entertainment', 149),
  ('nag Netflix ako 549', VoiceCommandType.expense, 'Entertainment', 549),
  ('bumili ng load para sa wifi 999', VoiceCommandType.expense, 'Bills', 999),
  ('gasolina 1000', VoiceCommandType.expense, 'Transportation', 1000),
  (
    'pamasahe papuntang school 50',
    VoiceCommandType.expense,
    'Transportation',
    50,
  ),
  ('ticket sa concert 2500', VoiceCommandType.expense, 'Entertainment', 2500),
  ('nag Jollibee kami 650', VoiceCommandType.expense, 'Food', 650),
  ('McDo breakfast 180', VoiceCommandType.expense, 'Food', 180),
  ('nag Starbucks ako 210', VoiceCommandType.expense, 'Food', 210),
  ('bigas sampung kilo 550', VoiceCommandType.expense, 'Food', 550),
  ('isang kilong manok 220', VoiceCommandType.expense, 'Food', 220),
  ('itlog isang tray 240', VoiceCommandType.expense, 'Food', 240),
  ('sabon at shampoo 180', VoiceCommandType.expense, 'Shopping', 180),
  ('Lazada 799', VoiceCommandType.expense, 'Shopping', 799),
  ('bagong sapatos 2500', VoiceCommandType.expense, 'Shopping', 2500),
  ('gupit 150', VoiceCommandType.expense, null, 150),
  ('laundry 200', VoiceCommandType.expense, null, 200),
  ('vitamins ni lola 600', VoiceCommandType.expense, 'Healthcare', 600),
  ('dentista 1500', VoiceCommandType.expense, 'Healthcare', 1500),
  ('salamin sa mata 2500', VoiceCommandType.expense, 'Healthcare', 2500),
  ('pang gym 1200', VoiceCommandType.expense, 'Healthcare', 1200),
  ('bayad sa SSS 570', VoiceCommandType.expense, 'Bills', 570),
  ('Pag IBIG contribution 200', VoiceCommandType.expense, 'Bills', 200),
  ('insurance 2000', VoiceCommandType.expense, 'Bills', 2000),
  ('padala kay mama 3000', VoiceCommandType.expense, null, 3000),
  ('regalo sa birthday ni ate 800', VoiceCommandType.expense, 'Shopping', 800),
  ('pa load ng 50', VoiceCommandType.expense, 'Bills', 50),
  ('bayad sa tricycle 30', VoiceCommandType.expense, 'Transportation', 30),
  ('kape 45', VoiceCommandType.expense, 'Food', 45),
  ('softdrinks at chichirya 85', VoiceCommandType.expense, 'Food', 85),
  ('yosi 150', VoiceCommandType.expense, null, 150),
  ('alak 300', VoiceCommandType.expense, 'Entertainment', 300),
  ('San Miguel 120', VoiceCommandType.expense, 'Entertainment', 120),
  ('Red Horse 140', VoiceCommandType.expense, 'Entertainment', 140),
  ('pamasahe sa bangka 100', VoiceCommandType.expense, 'Transportation', 100),
  ('electric bill 2800', VoiceCommandType.bill, null, 2800),
  ('nagpaayos ng cellphone 800', VoiceCommandType.expense, 'Shopping', 800),
];

/// Every screen and form reachable by voice: the bottom tabs, each
/// Quick Action, the + menu, the assistant and settings. A destination
/// is checked only when the words should open a screen.
const opens = <(String, VoiceCommandType, VoiceDestination?)>[
  // Bottom tabs.
  ('go home', VoiceCommandType.navigation, VoiceDestination.home),
  ('buksan ang home', VoiceCommandType.navigation, VoiceDestination.home),
  (
    'open transactions',
    VoiceCommandType.navigation,
    VoiceDestination.transactions,
  ),
  (
    'ipakita ang mga transaksyon',
    VoiceCommandType.navigation,
    VoiceDestination.transactions,
  ),
  (
    'show my transaction history',
    VoiceCommandType.navigation,
    VoiceDestination.transactions,
  ),
  ('open reports', VoiceCommandType.navigation, VoiceDestination.reports),
  ('buksan ang reports', VoiceCommandType.navigation, VoiceDestination.reports),
  ('ipakita ang ulat', VoiceCommandType.navigation, VoiceDestination.reports),
  ('open wallets', VoiceCommandType.navigation, VoiceDestination.wallet),
  ('buksan ang wallet', VoiceCommandType.navigation, VoiceDestination.wallet),
  (
    'pakita ang mga account ko',
    VoiceCommandType.navigation,
    VoiceDestination.wallet,
  ),
  // Quick actions that open screens.
  ('open bill planner', VoiceCommandType.navigation, VoiceDestination.bills),
  ('buksan ang bills', VoiceCommandType.navigation, VoiceDestination.bills),
  ('open savings', VoiceCommandType.navigation, VoiceDestination.savings),
  ('buksan ang ipon', VoiceCommandType.navigation, VoiceDestination.savings),
  ('open goals', VoiceCommandType.navigation, VoiceDestination.goals),
  ('ipakita ang goals ko', VoiceCommandType.navigation, VoiceDestination.goals),
  (
    'open installments',
    VoiceCommandType.navigation,
    VoiceDestination.installments,
  ),
  (
    'buksan ang hulugan',
    VoiceCommandType.navigation,
    VoiceDestination.installments,
  ),
  ('open debts', VoiceCommandType.navigation, VoiceDestination.debts),
  ('buksan ang utang', VoiceCommandType.navigation, VoiceDestination.debts),
  ('scan receipt', VoiceCommandType.navigation, VoiceDestination.scanReceipt),
  (
    'mag scan ng resibo',
    VoiceCommandType.navigation,
    VoiceDestination.scanReceipt,
  ),
  (
    'open scan receipt',
    VoiceCommandType.navigation,
    VoiceDestination.scanReceipt,
  ),
  // Chatbot and settings.
  ('open chatbot', VoiceCommandType.navigation, VoiceDestination.assistant),
  (
    'open the AI assistant',
    VoiceCommandType.navigation,
    VoiceDestination.assistant,
  ),
  ('kausapin si Fin', VoiceCommandType.navigation, VoiceDestination.assistant),
  ('open Fin', VoiceCommandType.navigation, VoiceDestination.assistant),
  ('open settings', VoiceCommandType.navigation, VoiceDestination.settings),
  (
    'buksan ang settings',
    VoiceCommandType.navigation,
    VoiceDestination.settings,
  ),
  ('open my profile', VoiceCommandType.navigation, VoiceDestination.settings),
  (
    'open categories',
    VoiceCommandType.navigation,
    VoiceDestination.expenseCategories,
  ),
  (
    'open cash inflows',
    VoiceCommandType.navigation,
    VoiceDestination.payCycleHistory,
  ),
  ('open reminders', VoiceCommandType.navigation, VoiceDestination.reminders),
  (
    'buksan ang paalala',
    VoiceCommandType.navigation,
    VoiceDestination.reminders,
  ),
  ('open help', VoiceCommandType.navigation, VoiceDestination.help),
  (
    'kailangan ko ng tulong',
    VoiceCommandType.navigation,
    VoiceDestination.help,
  ),
  // Forms from Quick Actions and the + button.
  ('add expense', VoiceCommandType.expense, null),
  ('magdagdag ng gastos', VoiceCommandType.expense, null),
  ('add income', VoiceCommandType.income, null),
  ('magdagdag ng kita', VoiceCommandType.income, null),
  ('transfer money', VoiceCommandType.transfer, null),
  ('maglipat ng pera', VoiceCommandType.transfer, null),
  ('add bill', VoiceCommandType.bill, null),
  ('magdagdag ng bill', VoiceCommandType.bill, null),
  ('add goal', VoiceCommandType.goal, null),
  ('gumawa ng goal', VoiceCommandType.goal, null),
  ('add installment', VoiceCommandType.installment, null),
  ('add debt', VoiceCommandType.debt, null),
  ('magdagdag ng utang', VoiceCommandType.debt, null),
  ('add wallet', VoiceCommandType.wallet, null),
  ('magdagdag ng wallet', VoiceCommandType.wallet, null),
  ('add savings', VoiceCommandType.navigation, VoiceDestination.savings),
  ('open chat', VoiceCommandType.navigation, VoiceDestination.assistant),
  ('go to my wallets', VoiceCommandType.navigation, VoiceDestination.wallet),
  (
    'tingnan ang reports',
    VoiceCommandType.navigation,
    VoiceDestination.reports,
  ),
  ('go to settings', VoiceCommandType.navigation, VoiceDestination.settings),
  (
    'open the bill planner',
    VoiceCommandType.navigation,
    VoiceDestination.bills,
  ),
  (
    'open transaksyon',
    VoiceCommandType.navigation,
    VoiceDestination.transactions,
  ),
  ('mahal kita', VoiceCommandType.expense, null),
  (
    'buksan ang kita',
    VoiceCommandType.navigation,
    VoiceDestination.payCycleHistory,
  ),
  (
    'ipakita ang mga kita ko',
    VoiceCommandType.navigation,
    VoiceDestination.payCycleHistory,
  ),
  ('kita tayo mamaya', VoiceCommandType.expense, null),
  ('pay now', VoiceCommandType.payNow, null),
  ('pay in advance', VoiceCommandType.payInAdvance, null),
];

void main() {
  test('a real tattoo is not the Tattoos chips', () {
    for (final words in [
      'tattoo 2000',
      'nagpatattoo ako 1500',
      'tattoo shop 3000',
    ]) {
      final command = interpretVoiceCommand(
        words,
        categories: expenseCategories,
      );
      expect(command.expense.category, isNot('Food'), reason: words);
    }
  });

  for (final (words, type, destination) in opens) {
    test(words, () {
      final command = interpretVoiceCommand(
        words,
        categories: expenseCategories,
      );
      expect(command.type, type);
      if (destination != null) expect(command.destination, destination);
    });
  }

  for (final (words, type, category, amount) in said) {
    test(words, () {
      final command = interpretVoiceCommand(
        words,
        categories: expenseCategories,
      );
      expect(command.type, type);
      if (category != null) expect(command.expense.category, category);
      if (amount != null) expect(command.expense.amount, amount);
    });
  }
}
