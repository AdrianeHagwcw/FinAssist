# Rebuilds docs/FinAssist_Progress_Report.pdf.
#
#   pip install reportlab
#   python docs/build_progress_report.py     (run from the project root)
#
# Uses Segoe UI from the Windows font folder, because the peso sign is not in
# the fonts built into PDF.
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle,
    KeepTogether,
)

FONTS = 'C:/Windows/Fonts/'
pdfmetrics.registerFont(TTFont('Segoe', FONTS + 'segoeui.ttf'))
pdfmetrics.registerFont(TTFont('Segoe-Bold', FONTS + 'segoeuib.ttf'))
pdfmetrics.registerFont(TTFont('Segoe-Semi', FONTS + 'seguisb.ttf'))
pdfmetrics.registerFont(TTFont('Segoe-Italic', FONTS + 'segoeuii.ttf'))
pdfmetrics.registerFontFamily(
    'Segoe', normal='Segoe', bold='Segoe-Bold', italic='Segoe-Italic')

BLUE = colors.HexColor('#1976D2')
INK = colors.HexColor('#16202B')
BODY = colors.HexColor('#3A4654')
LINE = colors.HexColor('#D7E3F0')
TINT = colors.HexColor('#EAF2FB')

styles = getSampleStyleSheet()


def style(name, **kw):
    base = dict(name=name, fontName='Segoe', fontSize=9.5, leading=13.6,
                textColor=BODY, alignment=TA_LEFT, spaceAfter=5)
    base.update(kw)
    return ParagraphStyle(**base)


S = {
    'title': style('title', fontName='Segoe-Bold', fontSize=23, leading=27,
                   textColor=BLUE, spaceAfter=2),
    'subtitle': style('subtitle', fontSize=11.5, leading=15, spaceAfter=14),
    'h1': style('h1', fontName='Segoe-Bold', fontSize=14.5, leading=19,
                textColor=INK, spaceBefore=15, spaceAfter=6),
    'h2': style('h2', fontName='Segoe-Semi', fontSize=11, leading=15,
                textColor=INK, spaceBefore=9, spaceAfter=3),
    'body': style('body'),
    'bullet': style('bullet', leftIndent=11, bulletIndent=1, spaceAfter=2.5),
    'cell': style('cell', fontSize=9, leading=12.4, spaceAfter=0),
    'cellb': style('cellb', fontName='Segoe-Semi', fontSize=9, leading=12.4,
                   spaceAfter=0, textColor=INK),
    'cellh': style('cellh', fontName='Segoe-Bold', fontSize=9, leading=12.4,
                   spaceAfter=0, textColor=INK),
    'note': style('note', fontSize=8.6, leading=12, textColor=colors.HexColor('#5A6875')),
}


def P(text, s='body'):
    return Paragraph(text, S[s])


def bullets(items, s='bullet'):
    return [Paragraph(t, S[s], bulletText='•') for t in items]


def table(rows, widths, header=True):
    data = []
    for r, row in enumerate(rows):
        cells = []
        for c, text in enumerate(row):
            kind = 'cellh' if (header and r == 0) else (
                'cellb' if c == 0 else 'cell')
            cells.append(Paragraph(text, S[kind]))
        data.append(cells)

    t = Table(data, colWidths=widths, repeatRows=1 if header else 0)
    commands = [
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 7),
        ('RIGHTPADDING', (0, 0), (-1, -1), 7),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LINEBELOW', (0, 0), (-1, -2), 0.4, LINE),
        ('BOX', (0, 0), (-1, -1), 0.6, LINE),
    ]
    if header:
        commands += [('BACKGROUND', (0, 0), (-1, 0), TINT),
                     ('LINEBELOW', (0, 0), (-1, 0), 0.8, LINE)]
    t.setStyle(TableStyle(commands))
    return t


story = []
add = story.append

# ----------------------------------------------------------------- cover
add(P('FinAssist — Revision Progress Report', 'title'))
add(P('Where the app stands against the FinAssist Front-End Development Plan '
      '(Flutter) · Branch <b>revisedfrontend</b> · 18 September 2026', 'subtitle'))

add(table([
    ['Where we are', 'Detail'],
    ['Core track (Phases 1–10)',
     '<b>Phases 1 to 9 are built and in the app.</b> Phase 10 (History &amp; '
     'Reconciliation Timeline and the rest of the Settings polish) is the only '
     'core phase left.'],
    ['ML track (Phases 11–16)',
     'Not started. Receipt scanning and voice input already work as standalone '
     'screens from the earlier app, and the chatbot answers from fixed keyword '
     'rules; none of them create transactions yet.'],
    ['Quality',
     '231 automated tests pass and the Flutter analyzer reports no issues. '
     'Every phase was also opened and used on an Android emulator.'],
    ['Code',
     'Phases 1–8 are pushed to the branch (latest pushed commit 29191ca). '
     'Phase 9 and this report are committed together with it.'],
], [34*mm, 130*mm]))

add(P('This report lists what is already in the app, what was deliberately '
      'left out or removed, what is still missing, and the plan for each '
      'remaining phase.', 'body'))

# ------------------------------------------------------------ foundations
add(P('1. Foundations and decisions behind the build', 'h1'))
add(P('These were settled before Phase 1 and every later phase follows them:', 'body'))
story += bullets([
    '<b>Accounts and data:</b> Firebase Authentication with email or Google, '
    'and Cloud Firestore for storage. Writes are not waited on and reads use '
    "Firestore's local cache, so recording money works with no signal and "
    'syncs later.',
    '<b>One wallet ledger:</b> every income, expense and transfer belongs to a '
    "wallet, and the wallet's balance is written in the same batch as the "
    'entry, so a balance can never disagree with its history.',
    '<b>Peso only</b>, no currency picker, as the plan requires. Amounts show '
    'centavos only when there are any (₱20,000 and ₱270.25).',
    '<b>Four tabs</b> (Home, Transactions, Goals, Wallet) with a centre + '
    'button, and Settings and the AI assistant as header icons.',
    '<b>One colour rule for buttons:</b> green commits, red destroys or backs '
    'out, blue only opens or edits.',
    '<b>Light and dark mode</b> from a shared colour set, pulled forward from '
    'Phase 10 on request.',
    '<b>Nothing was rewritten from scratch:</b> existing screens were revised, '
    'and only features the plan removes were deleted.',
])

# --------------------------------------------------------- done phases
add(P('2. Phases already built and integrated', 'h1'))

phases = [
    ('Phase 1 — Login, onboarding and the app shell', [
        'Splash screen with auto-login, real Firebase password-reset email, and '
        'Google sign-in.',
        'Onboarding: welcome, name, reminders question, income and ranked '
        'priorities, starting wallets and balances, then a recap. It stops at '
        'wallets, which is what the plan asks of Phase 1.',
        'Main shell with the four tabs, the + quick-add sheet, and the chat and '
        'settings icons in the Home header.',
    ]),
    ('Phase 2 — Wallets and money entry', [
        'Wallets list with the combined balance, each wallet\'s balance, and '
        'which wallet receives the income; add, edit and remove wallets.',
        'Wallet detail: balance, who pays into it, and that wallet\'s history, '
        'with transfers readable from both sides.',
        'Expense, income and transfer entry, each tagged to a wallet.',
        'A one-time, user-started import of records from before wallets '
        'existed. They appear in history without moving any balance.',
    ]),
    ('Phase 3 — Bill Planner', [
        'Bill schedules plus a record for each occurrence, so one month can be '
        'changed without touching the schedule.',
        'Due dates are worked out from the first due date; a bill due on the '
        '31st still falls due in February.',
        'Month grid with colour-coded status dots, a list view and a day filter.',
        'Mark paid, pay part of it, skip, undo, and a breakdown of each payment '
        'with the wallet it came from. Paying writes the bill status, the '
        'expense and the wallet balance in one batch.',
    ]),
    ('Phase 4 — Income Allocation Waterfall', [
        'Adding income is three steps: amount, source, wallet and date; then '
        'the open bills with editable amounts (pay in full, pay part, leave for '
        'later, skip); then what is left, and Confirm.',
        'Everything is saved in one batch: the income, every bill payment, '
        'every skip, the goal contribution and a record of the cycle.',
        'If the chosen bills cost more than came in, the summary says the '
        'difference comes out of what the wallet already held.',
    ]),
    ('Phase 5 — Transactions', [
        'One list of every income, expense and transfer across all wallets, '
        'grouped by day, with bill payments and pre-wallet records labelled.',
        'Money in and money out for what is on screen; filters by type, wallet, '
        'category and date range; a spending-by-category sheet.',
        'Tap an entry to edit or delete it. Deleting a bill payment also undoes '
        'it on the bill.',
        'Money lent, borrowed or paid back is listed separately as "Loans in" '
        'and "Loans out", since it is neither earning nor spending.',
    ]),
    ('Phase 6 — Safe to Spend and the leftover review', [
        'Home\'s main card: what can be spent today against a daily limit, with '
        'a progress bar, today\'s spending, a privacy eye, and an explanation of '
        'how the figure is reached.',
        'Recommended limit = (wallet balances − bills due this pay period − '
        'savings set aside − money set aside for goals) ÷ days left in the '
        'period. Leaving the limit box empty uses that recommendation; typing a '
        'number sets your own.',
        'Pay periods come from the onboarding income frequency, anchored to the '
        'day income actually arrived.',
        'On a pay period\'s last day Home offers the leftover review: save it, '
        'spend it, split it, or decide later, with a status badge kept for the '
        'record.',
    ]),
    ('Phase 7 — Goals, plus Debts (added)', [
        'Goals tab: active and completed goals, priority order, progress, '
        'target date, and a goal step inside the income waterfall.',
        'Money set aside for a goal stays in its wallet, so wallet balances keep '
        'matching real life, while Safe to Spend stops counting it.',
        'Goal detail: progress ring, projected finish date from the pace of past '
        'contributions, contribution history, add or take out money.',
        'Goal planning: money already saved, a weekly, twice-monthly or monthly '
        'plan, what is needed each time to hit the target date, and whether you '
        'are on track or behind.',
        '<b>Debts (beyond the plan):</b> installments you pay, whose payments '
        'become a bill schedule that ends after the last payment, and money '
        'others owe you, with repayments recorded into a wallet.',
        '<b>Grow Your Money guide (beyond the plan):</b> a suggested monthly '
        'saving of 20% of income and plain-language cards on emergency funds, '
        'savings accounts and time deposits, labelled as education, not advice.',
    ]),
    ('Phase 8 — Reports, and Home rebuilt on the ledger', [
        'Reports: this week, this month or a custom range, with arrows to step '
        'back and forth.',
        'Totals for income, expenses, money saved to goals, and the net change.',
        'A spending donut by category; tapping a category opens Transactions '
        'filtered to it for that period.',
        'A money-in versus money-out bar chart that starts at your first record, '
        'so months before you used the app are not drawn as zero.',
        'Plain-language insights, e.g. "Food spending is 20% higher than your '
        '3-month average", only once there are earlier periods to compare with.',
        'Home was rebuilt on the same ledger: Safe to Spend first, then Total '
        'Balance, this month\'s spending as a split bar, recent transactions, '
        'and the top insight.',
    ]),
    ('Phase 9 — Reminders (this phase)', [
        'Notifications scheduled on the phone itself, so they arrive with the '
        'app closed and with no internet.',
        '<b>Bills:</b> a heads-up before the due date and one on the day, both '
        'at 9 AM, for anything unpaid.',
        '<b>Saving plans:</b> on the goal\'s own saving days at 9 AM, repeating '
        'the planned amount, or what is needed to reach the target date.',
        '<b>Leftover money:</b> 7 PM on the last day of the pay period, and 9 AM '
        'the next day while a finished period is still undecided.',
        '<b>Logging:</b> 8 PM on days nothing has been recorded yet.',
        'Tapping a reminder opens what it is about: the bill, the goal, the Add '
        'Expense form, or Home for the leftover question.',
        'Home also shows a "Bills due soon" notice for anything overdue or due '
        'within three days, so nothing is missed even with notifications off.',
    ]),
]

for title, points in phases:
    add(P(title, 'h2'))
    story += bullets(points)

# ---------------------------------------------------- reminders detail
add(P('3. How reminders follow each user\'s priorities', 'h1'))
add(P('Onboarding asks people to rank what matters most to them. Until this '
      'phase that answer was stored and never used. Now it decides which '
      'reminders start on, so two users with different priorities get '
      'different reminders.', 'body'))

add(table([
    ['Priority ranked by the user', 'Reminder it controls', 'On by default?'],
    ['Pay bills on time', 'Bills due',
     'Always on. Ranked first, the heads-up comes 3 days early; otherwise 1 day.'],
    ['Save toward a goal', 'Saving plans', 'On when ranked 1st or 2nd'],
    ['Build general savings', 'Leftover money', 'On when ranked 1st or 2nd'],
    ['Just track my spending', 'Log your spending', 'On when ranked 1st or 2nd'],
], [45*mm, 38*mm, 81*mm]))

story += bullets([
    '<b>Settings → Reminders</b> holds a master switch, the priority order with '
    'arrows to re-rank it, a switch and a plain reason for each reminder, the '
    'bill timing (on the day, 1, 3 or 7 days before), and a test reminder that '
    'arrives about 10 seconds later.',
    '<b>Re-ranking updates the reminders you never touched</b> and leaves the '
    'ones you set by hand alone. Setting a switch back to its suggested state '
    'hands it back to the priorities.',
    '<b>Nothing is sent if reminders are off</b> in onboarding or in Settings, '
    'or if Android has blocked notifications for FinAssist.',
])

add(P('Checked on the emulator: Android asked for notification permission, the '
      'app scheduled its reminders, a test reminder arrived while the app was '
      'closed, and tapping it opened FinAssist.', 'note'))

# ------------------------------------------------------ removed / changed
add(P('4. What was removed or replaced along the way', 'h1'))
add(table([
    ['Removed or replaced', 'Reason'],
    ['Facebook sign-in', 'Never configured on any platform.'],
    ['Currency picker', 'The plan is peso-only.'],
    ['Financial health score', 'Not in the plan; Reports shows real figures instead.'],
    ['Separate expenses list', 'Merged into the one Transactions screen (Phase 5).'],
    ['Add Income dialog, Add Budget dialog',
     'Replaced by the income waterfall and the Safe to Spend editor.'],
    ['Category Budgets', 'Removed on request: Safe to Spend already limits daily '
     'spending, and category budgets are not in the plan.'],
    ['Old Insights screen', 'Replaced by Reports, which reads the wallet ledger.'],
    ['Notifications screen and bell',
     'Removed in Phase 1; real phone reminders replace it in Phase 9.'],
], [45*mm, 119*mm]))

# ----------------------------------------------------------- known gaps
add(P('5. Known gaps and things still to verify', 'h1'))
story += bullets([
    '<b>Dashboard tip banner (plan 8.4, marked build now):</b> not built. The '
    'rule-based insight card and the "Bills due soon" notice cover part of it.',
    '<b>Attaching a receipt photo to a bill payment (plan 8.10):</b> not built. '
    'It needs a decision on where photos are stored.',
    '<b>Scan Receipt and Voice Log buttons inside the Add Expense form (plan '
    '8.8):</b> not there yet. Both features exist as their own screens from '
    'Home, but they only show the text they read.',
    '<b>The old <font face="Segoe-Italic">expenses</font> records are still '
    'written</b> alongside the wallet ledger. Nothing reads them now, so the '
    'duplicate write can be dropped.',
    '<b>Security and Help &amp; Support</b> in Settings still say "coming soon".',
    '<b>Firestore rules:</b> the repository\'s <font face="Segoe-Italic">'
    'firestore.rules</font> limits each user to their own data, but the '
    'published rules live in a Firebase project owned by a classmate and have '
    'not been compared against the file.',
    '<b>The import of pre-wallet records has never been run on real old data</b>, '
    'only on test data.',
    '<b>Reminders arrive a few minutes late at worst.</b> Exact-to-the-minute '
    'alarms need a permission most users deny, so the app uses the relaxed kind. '
    'Bills are scheduled about a month ahead and re-planned whenever the app is '
    'opened or the data changes.',
])

# ------------------------------------------------------ remaining phases
add(P('6. What is left, and the plan for each', 'h1'))

add(P('Phase 10 — History &amp; Reconciliation Timeline and Settings polish '
      '(last core phase)', 'h2'))
story += bullets([
    'A history timeline of pay cycles, newest first: the period, what came in, '
    'what went to bills and goals, what was left, and the decision made, with '
    'its done, declined or pending badge. Tapping a pending one opens the '
    'leftover review so it can still be settled.',
    'Settings: edit the income profile (source, frequency, usual amount), a '
    'default choice for leftover money, manage expense categories, a shortcut '
    'to wallets, and a default for the privacy mask. Re-ranking priorities and '
    'light/dark mode are already there.',
    'Close the core gaps listed above: the Dashboard tip banner, and the '
    'receipt photo on a bill payment once storage is decided.',
    'Optional, and needs a decision: a Filipino/English toggle. The plan calls '
    'it a nice-to-have, and it means translating every screen.',
])

add(P('Phases 11–16 — the AI and ML track', 'h2'))
add(table([
    ['Phase', 'Plan'],
    ['11 — Receipt scanning',
     'The app already reads text from a receipt photo on the phone. The work '
     'left is pulling the total, date and shop name out of that text and '
     'filling in the Add Expense form for the user to check and save, plus the '
     'same button on a bill payment.'],
    ['12 — Voice logging',
     'Speech to text already works on the phone. The work left is understanding '
     'a sentence such as "spent 150 on food from GCash", filling in the form, '
     'and asking the user to confirm before saving.'],
    ['13 — AI insights',
     'Replace the rule-based insight lines and the tip banner with generated '
     'ones, sending only totals and category summaries, never raw transactions. '
     'The current rule-based lines stay as the fallback when offline.'],
    ['14 — AI chatbot',
     'The assistant answers from fixed keyword rules today. Connecting it to a '
     'real model needs a small server (for example Firebase Cloud Functions, '
     'which requires the paid plan) so the API key is never inside the app. The '
     'finance-only guard and the offline notice stay.'],
    ['15 — Financial tips',
     'A server job collects tips from trusted Philippine sources, saves them '
     'with their source and date, and the Reports tips panel shows the saved '
     'copy, including offline.'],
    ['16 — Offline assistant',
     'When there is no connection, answer from the rules and the user\'s own '
     'figures instead of the model, so the assistant is never simply dead.'],
], [30*mm, 134*mm]))

add(P('Decisions the team needs to make before Phases 11–16', 'h2'))
story += bullets([
    'Which AI service the chatbot and insights will use, and who pays for it.',
    'Whether we may add a small server for API keys and the tips job. The '
    'Firebase project is owned by a classmate and would need its plan upgraded.',
    'Where receipt photos are stored, since that also costs money once there '
    'are many of them.',
    'Which Philippine sources the financial tips may be taken from.',
    'Whether the app must also run on iOS. Everything so far is set up and '
    'tested for Android.',
])

# ---------------------------------------------------------- how to run
add(P('7. How to run and check the app', 'h1'))
story += bullets([
    '<b>Run it:</b> <font face="Segoe-Italic">flutter emulators --launch '
    'FinAssist_Pixel</font>, wait for the phone to start, then <font '
    'face="Segoe-Italic">flutter run -d emulator-5554</font> from the project '
    'folder.',
    '<b>Run the tests:</b> <font face="Segoe-Italic">flutter test</font> — 231 '
    'tests covering the money rules, pay periods, bills, goals, debts, reports '
    'and reminders, plus the screens themselves.',
    '<b>Check the code:</b> <font face="Segoe-Italic">flutter analyze</font> — '
    'currently clean.',
    '<b>Reminders:</b> Settings → Reminders → Send a Test Reminder, then leave '
    'the app; the reminder arrives about 10 seconds later.',
])


# ------------------------------------------------- handover to a developer
folders = table([
    ['Folder', 'What is in it'],
    ['lib/models',
     'The money rules as plain Dart with no Firebase: pay periods and Safe to '
     'Spend, bills and their occurrences, the income plan, goals, debts, '
     'reports and reminders. This is where logic belongs, because it can be '
     'tested directly.'],
    ['lib/services',
     'Everything that talks to Firestore, one file per area, plus '
     'firestore_write.dart, which records without waiting so the app works '
     'offline.'],
    ['lib/screens', 'One file per screen.'],
    ['lib/widgets',
     'Pieces shared between screens: the Safe to Spend card, the transaction '
     'row, sheets for bills, goals and debts, the charts, and the dialog kit.'],
    ['lib/theme',
     'Colours for light and dark mode and the button styles that carry the '
     'green, red and blue rule.'],
    ['test/widget_test.dart',
     'All 231 tests in one file, grouped by feature.'],
], [40*mm, 124*mm])
# One page: a heading with nothing under it, or a folder map split in half,
# both read badly.
add(KeepTogether([
    P('8. For the developer taking the next phase', 'h1'),
    P('Where things live', 'h2'),
    folders,
]))

add(P('Conventions worth keeping', 'h2'))
story += bullets([
    '<b>Put the thinking in lib/models.</b> Screens read data and draw; the '
    'rules sit in functions that take plain values and a date, which is why '
    'they can be tested without a phone.',
    '<b>Screens take their data as optional streams</b> and their actions as '
    'optional callbacks, with the live Firebase versions as the defaults. '
    'Tests pass fixed data instead.',
    '<b>Write money changes in one batch</b> with the wallet balance, the way '
    'paying a bill or confirming income already does, so nothing can half-save.',
    '<b>Never await a Firestore write</b> in the UI. Use commitFirestoreWrite, '
    'so recording works offline.',
    '<b>Keep the button colours:</b> green commits, red destroys or backs out, '
    'blue opens or edits. Amounts go through formatPeso or MoneyText, which '
    'also respects the privacy mask.',
    '<b>Add tests with the work.</b> Run flutter test and flutter analyze '
    'before committing; both are clean today.',
])


def decorate(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.6)
    canvas.line(18*mm, 14*mm, A4[0] - 18*mm, 14*mm)
    canvas.setFont('Segoe', 8)
    canvas.setFillColor(colors.HexColor('#7A8795'))
    canvas.drawString(18*mm, 9.5*mm, 'FinAssist — Revision Progress Report')
    canvas.drawRightString(A4[0] - 18*mm, 9.5*mm, 'Page %d' % doc.page)
    canvas.restoreState()


doc = BaseDocTemplate(
    'docs/FinAssist_Progress_Report.pdf', pagesize=A4,
    leftMargin=18*mm, rightMargin=18*mm, topMargin=17*mm, bottomMargin=20*mm,
    title='FinAssist — Revision Progress Report',
    author='FinAssist team', subject='Front-end plan progress, September 2026')
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='body')
doc.addPageTemplates([PageTemplate(id='all', frames=[frame], onPage=decorate)])
doc.build(story)
print('written')
