# Phase 10: History and Settings

Implemented against the Phase 10 scope in `FinAssist_Progress_Report.pdf`.

## What is available

- **Pay-cycle history:** open from Settings, the Transactions history icon, or the Home tip. Cycles are newest first with income, bill allocations, goal allocations, remaining funds and the leftover decision. Filter to **Needs review** and reopen an unfinished cycle, including cycles outside Home's recent window.
- **Statuses:** In progress while the period is open; Pending when a review is due; Done for saving/splitting; Declined when saving was declined and money was kept available for spending. Statuses include text and icons as well as color.
- **Financial preferences:** edit the income source, frequency and optional usual amount. The income entry form starts with these values. A default leftover choice preselects the review but never saves or moves money automatically.
- **Expense categories:** add custom labels and hide/show categories. Others stays available. New expenses, bill forms and transaction editing use these choices. Filters retain hidden and historical labels; old records are not renamed.
- **Privacy:** Settings controls whether amounts are hidden at launch on this device. The eye toggles visibility only for the current session.
- **Settings navigation:** shortcuts to wallets and history; password reset for password accounts, Google account guidance for Google users, and practical in-app help.
- **Home:** an offline product tip with a history shortcut for accounts with records.
- **Ledger cleanup:** new expenses are recorded only in the wallet ledger. Description and optional notes are retained together in the ledger note. Existing legacy import and historical-copy handling remain supported.

## Persistence and compatibility

Financial preferences live on the existing user profile (`incomeSource`, `incomeFrequency`, `income`, `defaultLeftover`, `customCategories`, `hiddenCategories`) and use the existing offline write helper. The signed-in shell listens for changes; categories and defaults reset when a new account session starts. Theme and launch masking remain device preferences.

New allocation cycles save `periodStart` and `periodEnd` in the same batch as the income plan. Changing frequency does not alter these saved periods. Older records did not save period dates: they use the existing frequency-based calculation and are labelled accordingly. Allocation totals represent the original plan, not a recalculation of later edits to the ledger. Resolved leftover amounts come from the stored decision.

History reads all allocation cycles rather than the dashboard's six most recent. Rendering is lazy; server pagination can be added if account histories become large. The existing leftover calculation and offline savings-reserve write strategy are retained; this phase does not add cross-device transactional reconciliation.

## Deferred by decision

- Receipt-photo attachments: deferred by the user until storage is decided. No storage dependency, upload path or billing configuration was added.
- Filipino/English translation: optional in the report, outside this implementation.
- Receipt/voice transaction parsing and generated AI content remain in later phases.
- Published Firebase rules were not changed or deployed.

## Validation

`test/phase10_test.dart` covers period preservation, statuses, category validation and integration, account reset, privacy persistence, history filtering/review, empty/error states, form validation and saving, explicit leftover confirmation, and a 320-pixel layout at 150% text size.

Run `flutter test --no-pub` and `flutter analyze --no-pub`.

To generate widget-rendered visual previews using the SDK's fonts:

```powershell
flutter test --no-pub --dart-define=PHASE10_CAPTURE=true test/phase10_test.dart
```

Previews are written to ignored `build/phase10/`. These use fixed test data; they do not connect to Firebase. Live device/Firebase acceptance remains a separate check.
