import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/expense_guess.dart';

/// Philippine receipts of many kinds, as the phone's reader gives their text
/// back: rows top to bottom, a label and its amount on one line. Each must
/// fill in the amount actually paid, never the cash, the change, the VAT or
/// a balance.
void main() {
  double? amountOf(String text) => guessFromReceipt(
    text,
    categories: const ['Food', 'Transportation', 'Healthcare', 'Others'],
    now: DateTime(2026, 11, 22),
  ).amount;

  test('a handwritten sales invoice with a VAT table', () {
    expect(
      amountOf('''
CAR CARE PRODUCTS AND SCENTS STORE
VAT Reg. TIN: 231-456-444-00000
SALES INVOICE  No 1306
QTY  UNIT  ARTICLES  UNIT PRICE  AMOUNT
1  UNIT  ENGINE DEGREASER 20L  P2,050  P2,050
Total Sales (VAT Inclusive)  P2,050
Less: VAT  P219.64
Amount: Net of VAT  P1,830.36
VATable Sales  P1,830.36  Less: Discount
VAT - Exempt Sales  Amount Due  P1,830.36
Zero Rated Sales  Add: 12% VAT  P219.64
VAT Amount  P219.64  TOTAL AMOUNT DUE  P2,050'''),
      2050,
    );
  });

  test('a supermarket receipt with a points balance below the total', () {
    expect(
      amountOf('''
Robinsons Supermarket
VAT REG TIN 000-405-340-020
CHARMEE AN LONG 10S  62.00 V
04800488961475
TOTAL  P62.00
CASH  P1,000.00
Change  P938.00
Vatable  55.36
VAT Exempt Sales  0.00
Zero Rated Sales  0.00
VAT  6.64
Total  62.00
Available Balance :  402.19
Earned Points :  0.15
Current Balance :  402.34
Total Items: 1'''),
      62,
    );
  });

  test('a card payment, with the card line repeating the total', () {
    expect(
      amountOf('''
THE MARKETPLACE
MAXX FRESH 50S  50.00 V
RICOLA SF LEMON 40G  82.00 V
SALONPAS GEL 15G  90.00 V
SALONPAS PAIN REL 3S  66.00 V
SALONPAS PATCH 40S  217.00 V
TOTAL  P505.00
RBANK  P505.00
Card Number: 00000*******6845
Vatable  450.89
VAT  54.11
Total  505.00
Available Balance :  208.96'''),
      505,
    );
  });

  test('a pharmacy receipt: amount due, not the payment handed over', () {
    expect(
      amountOf('''
MERCURY DRUG - QC ARANETA CENTER
VITASOY CHO300mL  28.75T
TOTAL  28.75
AMOUNT TENDERED
CASH  100.00
TOTAL PAYMENT  100.00
CHANGE  71.25
** 1 item(s) **
VATable  (T)  25.67
VAT-Exempt Sale  (X)  0.00
VAT - 12%  3.08
Amount Due  28.75'''),
      28.75,
    );
  });

  test('with Amount Due unreadable, the total, not the payment', () {
    expect(
      amountOf('''
VITASOY CHO300mL  28.75T
TOTAL  28.75
AMOUNT TENDERED
CASH  100.00
TOTAL PAYMENT  100.00
CHANGE  71.25'''),
      28.75,
    );
  });

  test("a total whose amount the reader put on a row of its own", () {
    expect(
      amountOf('''
1.00 Mega Fries  127.00 V
Sub Total  127.00
TOTAL
127.00
Tendered:
CASH  127.00
Change:  0.00'''),
      127,
    );
  });

  test('a gas station receipt in Php with litres times price', () {
    expect(
      amountOf('''
ROLLINGHILLS GASOLINE STATION
Sales Receipt
Date: 2/4/2015  Time: 5:47:03 PM
Description  Amount
Petron XTRA ADVANCE (D# 3)  Php200.00
6.3291 @ Php31.60
Sub Total (12% Vatable)  Php176.57
Sub Total (Vat Exempt)  Php0.00
Plus 12% VAT  Php21.43
TOTAL AMOUNT TO BE PAID  Php200.00
Cash (PHP) Tendered  Php200.00
Change Cash  Php0.00'''),
      200,
    );
  });

  test('an official receipt with colons between label and amount', () {
    expect(
      amountOf('''
CEBU AIR, INC.
OFFICIAL RECEIPT
OR No. : 05199309
Airfare & Others  :  5604.48
Discount  :  0.00
DPSC  :  600.00
Total  :  6204.48
Vatable Sale  :  5499.54
VAT-Exempt  :  45.00
Sub Total  :  5544.54
VAT Amount  :  659.94
Total  :  6204.48'''),
      6204.48,
    );
  });

  test('a restaurant with a senior discount: the amount due after it', () {
    expect(
      amountOf('''
OFFICIAL RECEIPT
Item  Qty  Price  Amount
Midnight Dream  1.00  1065.00  1065.00
ECO  1.00  55.00  55.00
Sub Total  1120.00
Price w/o VAT&SC  1012.48
Discount  -223.99
Net Amount  788.49
12%VAT  107.52
AMOUNT DUE  896.01
VAT Amount  107.52
Cash  896.01'''),
      896.01,
    );
  });

  test('a service charge added on top of the subtotal', () {
    expect(
      amountOf('''
XIN YE BEIJING ROAST DUCK
Receipt No.: 003515
BEIJING ROAST DUCK @2,180x1  2,180.00
Yang Chow Fried Rice @480x1  480.00
Coke @108x1  108.00
Subtotal  2,768.00
Service  276.80
TOTAL  3,044.80
Payment Type  gcash
Total Qty  3'''),
      3044.80,
    );
  });

  test('a bill-out with a PWD discount: the amount due after it', () {
    expect(
      amountOf('''
BILL-OUT
3 MERRY MEAL DEAL GOLD 2024  7197.00
1 CAESAR SALAD SOLO  295.00
1 EXTRA RICE  100.00
3 MOZZARELLA CHEESE STICK  830.00
SUB-TOTAL  9110.00
PERSON WITH DISABILITY DI (2)  -85.40
VAT-EXEMPT (2)  -244.02
AMOUNT DUE  8780.58
BALANCE POINTS :  0'''),
      8780.58,
    );
  });

  test('a fast-food sales invoice paid in exact cash', () {
    expect(
      amountOf('''
WOW BRAND HOLDINGS INC.
SALES INVOICE
Qty  Description(s)  Price
1.00 Mega Fries  127.00 V
1.00 item(s)
Sub Total  127.00
TOTAL  127.00
Tendered:
CASH  127.00
Change:  0.00
VATable Sales(V)  113.39
VAT Amount  13.61'''),
      127,
    );
  });
}
