# Phase 10: History and Settings

Implemented against the Phase 10 scope in `FinAssist_Progress_Report.pdf`, then
revised after review. This describes the app as it behaves now.

## What is available

- **Pay-cycle history:** open from Settings, the history icon on Transactions, or the Home tip when it shows the payday review. Cycles are newest first with income, bill allocations, goal allocations, remaining funds and the leftover decision. Filter to **Needs review** and reopen an unfinished cycle, including cycles outside Home's recent window.
- **Statuses:** In progress while the period is open; Pending when a review is due; Done for saving or splitting; Declined when saving was declined and the money was kept for spending. Statuses include text and icons as well as colour.
- **Financial preferences:** edit the income source, frequency and optional usual amount; amounts may be typed with commas, such as `10,000`. The income entry form starts with the saved source only. The amount is always typed fresh, so tapping through can never record a wrong figure. A default leftover choice preselects the review but never saves or moves money automatically.
- **Expense categories:** a fixed list of Food, Transportation, Shopping, Bills, Entertainment, Healthcare, Education, Pets and Others, each with its own icon and colour. Users hide the ones they do not use, one at a time or with **Hide all** / **Show all**. Others cannot be hidden, so an expense always has a category. New categories cannot be added; any added on an earlier build are still shown and can be hidden. New expenses, bill forms and transaction editing offer the visible categories. Filters keep hidden and historical labels, and old records are never renamed.
- **Privacy:** the eye on the Safe to Spend card is the only control. Whether amounts are hidden is remembered on this device and still applies after the app restarts. A choice made with the earlier "Hide amounts on launch" setting is still honoured.
- **Settings navigation:** a "Your money" section with income and leftover preferences, pay-cycle history, manage expense categories and manage wallets; password reset for password accounts, Google account guidance for Google users, and in-app help.
- **Home:** a rule-based tip that works offline. In order, it suggests adding a first wallet, recording a first entry, dealing with a bill that is overdue or due within three days, recording income when every wallet is empty, logging today's spending, or reviewing the pay cycle (with a shortcut to history).
- **Ledger cleanup:** new expenses are recorded only in the wallet ledger. Description and optional notes are kept together in the ledger note. The legacy import and historical-copy handling still work.
- **Accessibility:** every icon-only button has a spoken label, including the Settings back button, which uses Flutter's `BackButton`.

## Persistence and compatibility

Financial preferences live on the existing user profile (`incomeSource`, `incomeFrequency`, `income`, `defaultLeftover`, `hiddenCategories`, and the legacy `customCategories`) and use the existing offline write helper. The signed-in shell listens for changes, and categories and defaults reset when a new account session starts. The theme and the eye's hidden-amounts choice are device preferences.

New allocation cycles save `periodStart` and `periodEnd` in the same batch as the income plan, so changing the income frequency later does not alter them. Older records did not save period dates: they use the frequency-based calculation and are labelled accordingly. Allocation totals show the original plan, not a recalculation after later ledger edits. Resolved leftover amounts come from the stored decision, and a leftover already decided elsewhere shows a message instead of failing.

History reads every allocation cycle, not just the dashboard's six most recent. Rendering is lazy; server pagination can be added if histories grow large. The existing leftover calculation and offline savings-reserve write strategy are unchanged; this phase does not add cross-device transactional reconciliation.

## Deferred by decision

- Receipt-photo attachments: deferred by the user until storage is decided. No storage dependency, upload path or billing configuration was added.
- Filipino/English translation: optional in the report and outside this implementation.
- Receipt/voice transaction parsing and generated AI content remain in later phases.
- Published Firebase rules were not changed or deployed.

## Validation

271 automated tests pass and `flutter analyze` reports no issues. `test/phase10_test.dart` covers period preservation, statuses, hiding categories while keeping Others and old labels, account reset, the remembered privacy choice, history filtering and review, empty and error states, form validation and saving, explicit leftover confirmation, and a 320-pixel layout at 150% text size. `test/widget_test.dart` checks Flutter's labelled-tap-target guideline on the Log In screen.

Run `flutter test --no-pub` and `flutter analyze --no-pub`.

To generate widget-rendered visual previews using the SDK's fonts:

```powershell
flutter test --no-pub --dart-define=PHASE10_CAPTURE=true test/phase10_test.dart
```

Previews are written to the ignored `build/phase10/` folder. They use fixed test data and do not connect to Firebase. Live device and Firebase acceptance remains a separate check.
