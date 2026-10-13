# Revision handoff - 14 October 2026

This continues the interrupted revisions in the existing workspace. Earlier
uncommitted changes were retained. The older PDF is a checklist, not evidence
that an item is still missing or that a live integration has been tested.

## Implemented and checked in this continuation

- Income-wallet guidance describes the actual default destination. The countdown
  comes from the saved income date and frequency, not the wallet selection.
- Other income, expense, bill and installment options explain what to enter and
  give examples. Irregular income guidance correctly describes the calendar-month
  fallback; recording income does not let users choose a custom end date.
- Savings shows an optional suggestion using current spending-wallet balances,
  uncovered bills (including scheduled installments), existing goal commitments
  and estimated daily expenses. Bills and savings balances are not counted twice.
- The suggestion reserves daily costs through the next expected income date
  (month end for irregular income), then offers 10% of the remainder, rounded
  down to a centavo. The remaining 90% is a buffer. Seven distinct days with
  ordinary spending in the last 30 days are required. This is an explicit product
  rule, not a trained prediction or a professional financial recommendation.
- Savings transfers require review, source/destination selection and confirmation.
  The amount remains editable. A single spending wallet can start a savings wallet.
- Chat recognizes English and Tagalog formula questions and explains Safe to
  Spend, savings suggestions, goals, installments, reports and wallet balances.
  Personal Safe to Spend and savings figures use the shared calculation models.
- The shared snapshot waits for bills, goals and other required records. Read
  failures do not silently turn missing obligations into zero. Chat clears stale
  figures after a read error; Savings hides its suggestion on error.
- Home's calculation explanation deducts only the uncovered bill amount.
- Home has an information icon opening the guide. Registration explains that the
  password is not saved in financial records or shown to other users.
- User-facing history/report wording uses Income history and Between payments.
  Old voice-navigation phrases remain accepted; income history is also recognized.
- Positive monetary entries use the shared minimum of PHP 0.01 and error text.
  Amounts below a centavo are rejected instead of rounded up for validation.
  An empty wallet balance and an optional allocation of zero remain valid:
  they represent no money, rather than a zero-value transaction.

## Existing implementations preserved

The savings destination picker, installment statement of account, Government loan
label, bank choices, setup review, editable starting wallets, recurring bill
frequencies, transaction filters and installment creation without moving wallet
money were already present. They were not replaced.

## Items that need external verification or a product decision

- Password reset is wired to Firebase and has automated UI coverage. Actual email
  delivery, reset-link configuration and sign-in with a changed password still
  need a real test account. No reset email was sent during this work.
- Email verification takes an email/user, not a password. No live registration or
  mailbox verification was performed.
- The requested professional review of the financial flow is not an automated
  test. This work does not claim financial-adviser approval.
- Bill-payment “probability” has no defined outcome, time window, model or
  calibration requirement in the supplied notes. Existing calculations and tips
  are rule based; this revision does not invent a probability score.
- Setup currently uses Income -> priorities -> bills/installments -> savings ->
  wallets -> reminders -> review. “Plan each payment” is not a current setup
  action. Any further reordering or replacement of that flow needs a concrete
  product decision.
- “All add actions on the page” and “dashboard editing only” remain ambiguous.
  Existing navigation and edit flows were retained; no broad redesign was inferred.

## Validation

Run `flutter analyze --no-pub` and `flutter test --no-pub`.
The full run on 14 October 2026 passed all 542 tests; analysis reported no issues.
The subsequent continuation checked the remaining revisions individually: the
3 Other-income tests and 16 savings-related tests passed without further flow
changes. Formula routing was corrected in the newly added explanations so a
named calculation takes priority over generic words such as balance or expenses.
The original debt-answer routing still handles ordinary Tagalog questions about
money taken. All 55 tests in the chatbot and remaining-revision files passed,
including 5 new regressions for these cases.
Regression coverage includes the savings arithmetic, protected bills and goals,
insufficient history, irregular income, spending above today's estimate, centavo
rounding, formula routing, data-load failures, editable transfer review and guide
navigation. Automated UI checks are not a substitute for a real-device review
with representative users.
