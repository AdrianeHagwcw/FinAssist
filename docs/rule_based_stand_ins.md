# Rule-based stand-ins

These features work today with plain rules, so they can be demonstrated before the team's machine-learning models are ready. Each one has a single place where a trained model takes over later; no screen needs to change.

| Feature | Where the rules live | What a model replaces later |
| --- | --- | --- |
| Category suggestion (typing an expense, Voice Entry, Scan Receipt) | `suggestCategory` in `lib/models/expense_guess.dart`, words in `lib/utils/category_keywords.dart` | The category guess. The keyword version stays as the fallback and as the baseline to compare the model against. |
| Amount, description and date from speech or a receipt | `guessFromSpeech` and `guessFromReceipt` in `lib/models/expense_guess.dart` | Nothing needed for amounts and dates; rules find them reliably. A model may improve the store name. |
| Assistant answers (spending, Safe to Spend, bills, balance, savings, debts, income, tips) | `answerChat` in `lib/models/chat_answers.dart`, reading `FinanceSnapshot` | The wording and understanding of free-form questions. The numbers keep coming from the app's own calculations. |
| "Can I buy it?" | `answerChat` in `lib/models/chat_answers.dart` | The price lookup (web scraping) and more natural questions. The affordability math stays. |
| Financial tips in Reports | `moneyTipsFor` in `lib/models/money_tips.dart` | Tips gathered by web scraping or a trained model, instead of or beside these. The rules stay useful offline. |

## How the rules behave

- **Categories** match whole words and phrases, longest first ("grab food" is Food, "grab" is Transportation). With a ride in the text, places gone to don't count ("Grab papunta sa school" is Transportation). A tie suggests nothing, and a hidden category is never suggested. A category the user picks is never changed by typing. Occasions such as "date with" or "nag-date" suggest Entertainment only when nothing else names what was paid for, so "dinner date" stays Food; "date" alone is never a clue, since receipts print it.
- **Amounts:** a number said as money wins ("₱150", "150 pesos"); otherwise the largest. A number stuck to letters ("PS5", "500mg", "16GB") is never an amount, a time such as 3:30 isn't either, and plural words count ("burgers" is Food). In "Can I buy…", a plain number under ₱100 is taken as part of the name ("iPhone 16"), not the price.
- **Receipts:** the total comes from the TOTAL or AMOUNT DUE line, never CASH or CHANGE; no total line means no amount. The store is the first top line that isn't a heading or greeting. Numeric dates are read month first, and only a date in the past year is used. A long receipt can be taken in any number of parts; they are read as one, top to bottom, with lines repeated where photos overlap (two or more in a row, allowing a misread character) left out. A photo taken out of order goes where it overlaps; otherwise a part starting with "Official Receipt" goes first and a part without the total goes before the one with it. The user can move parts by hand. A photo that looks like another receipt (its own store name on a whole receipt, a different total or date, or a second "Official Receipt" heading, without overlapping) is asked about before it is added. A line with a price is never taken as the store name. Dates read as "09/18/ 2026" are accepted.
- **The assistant** answers from the records saved on the phone, so it also works offline. "Can I buy it?" asks for the brand (names only, from a short built-in list) and then the price, at most twice, then answers with one of: yes; yes if daily spending drops by a stated amount; or not yet, with a weekly saving amount within 30% of the user's usual weekly spending and a Create Goal button.
- **Tagalog word forms:** the assistant recognises a root inside a word, so "napautang", "pinautang" and "hiniram" are debt questions, and "naipon" and "gumastos" are about savings and spending. A question that names someone the user lent to ("Nagbayad na ba si Ana?") is answered about that person's debt, including what has been paid back.
- **Financial tips** show at most two at a time, and always one. They say what to do and leave the figures to Insights: many small buys this week, going over a daily limit the user set, payday, money still owed to the user, the category with the biggest share (never health, school or pets), and an emergency fund when there is none.
- Nothing is ever saved automatically: Voice Entry and Scan Receipt open the expense form filled in for the user to check.

## Adding words

Add store names or Taglish words to `lib/utils/category_keywords.dart`, one per line, lowercase, with punctuation written as a space (`7-eleven` becomes `7 eleven`). Tests for the rules are in `test/expense_guess_test.dart`, `test/chat_answers_test.dart` and `test/money_tips_test.dart`.
