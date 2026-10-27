import 'package:flutter/material.dart';

import '../../backend/models/wallet.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../backend/utils/date_format.dart';

/// The pieces both Add Savings sheets are built from, setup's and the one on
/// the Savings screen, so the two always look and read the same.

/// The kinds offered, in the order shown.
const savingsKindChoices = [
  SavingsKind.savingsDeposit,
  SavingsKind.timeDeposit,
  SavingsKind.demandDeposit,
];

/// The picture for each kind, from the icons the app already uses.
String savingsKindIcon(SavingsKind kind) => switch (kind) {
  SavingsKind.timeDeposit => 'assets/icons/icons8-lock-96.png',
  SavingsKind.demandDeposit => WalletType.bank.iconAsset,
  _ => 'assets/icons/icons8-money-box-96.png',
};

/// The two things that tell the kinds apart: what each pays, and how easily
/// the money comes back out.
({String interest, String access}) savingsKindFacts(SavingsKind kind) =>
    switch (kind) {
      SavingsKind.savingsDeposit => (
        interest: 'Earns interest',
        access: "Follows your bank's rules",
      ),
      SavingsKind.timeDeposit => (
        interest: 'Earns interest',
        access: 'Locked until the end date. Taking it out early may cost you.',
      ),
      SavingsKind.demandDeposit => (interest: 'None', access: 'Anytime'),
    };

/// One labeled fact with its icon. Two side by side, as a [FactPair], say
/// what something is at a glance; Add Savings and the savings explainer
/// both use them, so the two read the same.
class FactCard extends StatelessWidget {
  const FactCard({
    required this.iconAsset,
    required this.label,
    required this.value,
    this.tinted = false,
    super.key,
  });

  final String iconAsset;
  final String label;
  final String value;

  /// Blue-tinted, to tie it to the choice above it that it describes.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tinted ? colors.primaryTint : colors.pageBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tinted
              ? colors.primaryText.withValues(alpha: 0.35)
              : colors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(iconAsset, width: 22, height: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textBody,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two [FactCard]s side by side, always the same height.
class FactPair extends StatelessWidget {
  const FactPair({required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: 10),
          Expanded(child: second),
        ],
      ),
    );
  }
}

/// What the chosen kind pays and how the money comes out, as two fact
/// cards. They fade over when another kind is picked, so the change is seen.
class SavingsKindFacts extends StatelessWidget {
  const SavingsKindFacts({required this.kind, super.key});

  final SavingsKind kind;

  @override
  Widget build(BuildContext context) {
    final facts = savingsKindFacts(kind);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: FactPair(
        key: ValueKey(kind),
        first: FactCard(
          // The app's interest icon, as on the Cash Summary.
          iconAsset: 'assets/icons/icons8-combo-chart-100.png',
          label: 'Interest',
          value: facts.interest,
          tinted: true,
        ),
        second: FactCard(
          iconAsset: 'assets/icons/icons8-wallet-96.png',
          label: 'Taking money out',
          value: facts.access,
          tinted: true,
        ),
      ),
    );
  }
}

/// The outlined field every savings form uses. Its label sits above it, as
/// a [FieldLabel], so it never hides inside the box.
InputDecoration outlinedFieldDecoration({
  String? hint,
  String? prefix,
  String? suffix,
  String? helper,
  String? error,
}) {
  return InputDecoration(
    hintText: hint,
    prefixText: prefix,
    suffixText: suffix,
    helperText: helper,
    helperMaxLines: 3,
    errorText: error,
    errorMaxLines: 3,
    counterText: '',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// A field's name, above it.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: context.appColors.textPrimary,
      ),
    ),
  );
}

/// The three kinds as picture tiles, then one short line about the chosen
/// kind only, and a link to read more about it when [onLearnMore] is given.
class SavingsKindPicker extends StatelessWidget {
  const SavingsKindPicker({
    required this.kind,
    required this.onChanged,
    this.onLearnMore,
    this.keyPrefix = 'savings-kind-',
    super.key,
  });

  final SavingsKind kind;
  final ValueChanged<SavingsKind> onChanged;
  final ValueChanged<SavingsKind>? onLearnMore;

  /// Each tile's key is this plus the kind's name.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('What kind of savings?'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, choice) in savingsKindChoices.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _KindTile(
                    key: Key('$keyPrefix${choice.name}'),
                    label: choice.label,
                    iconAsset: savingsKindIcon(choice),
                    selected: kind == choice,
                    onTap: () => onChanged(choice),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Only the chosen kind is explained, as two facts to compare with
        // the next, instead of a sentence for each of the three.
        SavingsKindFacts(kind: kind),
        if (onLearnMore != null)
          TextButton.icon(
            key: Key('explain-savings-${kind.name}'),
            onPressed: () => onLearnMore!(kind),
            style: TextButton.styleFrom(
              foregroundColor: colors.primaryText,
              padding: EdgeInsets.zero,
            ),
            // A bulb, as the app's tips use: there is something to learn.
            icon: Image.asset(
              'assets/icons/icons8-idea-96.png',
              width: 20,
              height: 20,
            ),
            label: Text('Read about ${kind.label}'),
          ),
      ],
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.label,
    required this.iconAsset,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final String iconAsset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? colors.primaryText : colors.border,
        width: selected ? 1.5 : 1,
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.primaryTint : colors.pageBackground,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(iconAsset, width: 28, height: 28),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A date that opens the calendar, styled like the other fields, with its
/// own error under it.
class PickDateField extends StatelessWidget {
  const PickDateField({
    required this.date,
    required this.onTap,
    required this.helper,
    this.error,
    super.key,
  });

  final DateTime? date;
  final VoidCallback onTap;
  final String helper;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: outlinedFieldDecoration(helper: helper, error: error),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null ? 'Pick a date' : formatShortDate(date!),
                style: TextStyle(
                  color: date == null ? colors.textMuted : colors.textPrimary,
                ),
              ),
            ),
            Image.asset(
              'assets/icons/icons8-calendar-96.png',
              width: 22,
              height: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// How often an account pays its interest, so its reminders come when the
/// money does. The usual answers are one tap; any other bank's schedule is
/// set under Custom, as every so many months. It starts on every month, as
/// most banks pay, so nobody has to know the answer to move on.
class InterestPayoutPicker extends StatefulWidget {
  const InterestPayoutPicker({
    required this.payout,
    required this.onChanged,
    super.key,
  });

  final InterestPayout payout;
  final ValueChanged<InterestPayout> onChanged;

  @override
  State<InterestPayoutPicker> createState() => _InterestPayoutPickerState();
}

class _InterestPayoutPickerState extends State<InterestPayoutPicker> {
  /// Custom stays open while its months are changed, even past a number
  /// that is also a preset.
  late bool _custom = !widget.payout.isPreset;

  void _pick(InterestPayout payout, {required bool custom}) {
    setState(() => _custom = custom);
    widget.onChanged(payout);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final payout = widget.payout;
    final months = payout.isDaily ? 1 : payout.months;

    Widget step(IconData icon, String tooltip, int? next) =>
        IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: next == null
              ? null
              : () => _pick(InterestPayout.everyMonths(next), custom: true),
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            backgroundColor: colors.primaryTint,
            foregroundColor: colors.primaryText,
            disabledBackgroundColor: colors.card,
            disabledForegroundColor: colors.textMuted,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('How often does it pay interest?'),
        // A fixed grid, three to a row, so the choices never move around
        // when one is picked and its check mark makes it wider.
        for (final row in [
          InterestPayout.presets.sublist(0, 3),
          [...InterestPayout.presets.sublist(3), null],
        ]) ...[
          Row(
            children: [
              for (final (index, choice) in row.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: choice == null
                      ? _tile(
                          context,
                          key: const Key('interest-payout-custom'),
                          label: 'Custom',
                          selected: _custom,
                          // Starts on every 2 months, the first not above.
                          onTap: () => _pick(
                            payout.isPreset
                                ? const InterestPayout.everyMonths(2)
                                : payout,
                            custom: true,
                          ),
                        )
                      : _tile(
                          context,
                          key: Key('interest-payout-${choice.id}'),
                          label: choice.label,
                          selected: !_custom && choice == payout,
                          onTap: () => _pick(choice, custom: false),
                        ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (_custom) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: colors.pageBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Pays every',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                step(
                  Icons.remove,
                  'One month less',
                  months > 1 ? months - 1 : null,
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$months',
                    key: const Key('interest-payout-months'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                step(
                  Icons.add,
                  'One month more',
                  months < 12 ? months + 1 : null,
                ),
                const SizedBox(width: 8),
                Text(
                  months == 1 ? 'month' : 'months',
                  style: TextStyle(fontSize: 15, color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Check your bank\'s terms. Most banks pay every month; e-wallet '
          'savings like GSave and Maya add it every day. Not sure? Leave it '
          'on Every month.',
          style: TextStyle(fontSize: 12, color: colors.textBody),
        ),
        const SizedBox(height: 4),
        Text(
          payout.isDaily
              ? 'FinAssist reminds you on the 1st of each month to add the '
                    "month's total as income."
              : 'FinAssist reminds you on the 1st after it pays, so you can '
                    'add it as income.',
          style: TextStyle(fontSize: 12, color: colors.textBody),
        ),
      ],
    );
  }

  /// One choice in the grid, the same as the Days / Weeks / Months buttons:
  /// the chosen one solid blue with a check.
  Widget _tile(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? appPrimaryBlue : colors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? appPrimaryBlue : colors.border,
              ),
            ),
            // Shrinks rather than cuts off on a narrow phone or large text.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    const Icon(Icons.check, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: selected ? Colors.white : colors.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
