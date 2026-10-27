import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/models/dashboard_tip.dart';
import '../../backend/models/safe_to_spend.dart';
import '../providers/app_settings_provider.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../../backend/utils/money_format.dart';
import 'money_text.dart';

/// Home's light bulb: what is safe to spend today, then a short rule-based
/// tip, with no AI service and no connection.
class DashboardTipCard extends StatelessWidget {
  const DashboardTipCard({
    required this.tip,
    required this.onOpenHistory,
    this.safeToSpend,
    this.onExplain,
    super.key,
  });

  final DashboardTip tip;
  final VoidCallback onOpenHistory;

  /// Today's Safe to Spend, shown first. Null while it loads; left out
  /// while the wallets hold nothing, when the tip says what to do instead.
  final SafeToSpend? safeToSpend;

  /// Opens how Safe to Spend is worked out.
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final figure = safeToSpend;
    final showFigure = figure != null && figure.walletBalance > 0;

    return Material(
      color: colors.primaryTint,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(AppIcons.idea, width: 24, height: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showFigure) ...[
                    _SafeToSpendToday(safeToSpend: figure, onTap: onExplain),
                    Divider(height: 24, color: colors.border),
                  ],
                  Text(
                    tip.title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tip.message,
                    style: TextStyle(color: colors.textBody, height: 1.5),
                  ),
                  if (tip.showHistory)
                    TextButton(
                      onPressed: onOpenHistory,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primaryText,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('View Cash Inflows'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What can still be spent today without touching bills or goal money: the
/// amount, a bar that fills as the day's share is spent, and a tap to see
/// how it is worked out.
class _SafeToSpendToday extends StatelessWidget {
  const _SafeToSpendToday({required this.safeToSpend, this.onTap});

  final SafeToSpend safeToSpend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = safeToSpend;
    final over = s.isOverLimit;
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );
    final barColor = over
        ? dangerColorOn(context)
        : s.usedFraction >= 0.75
        ? Colors.amber.shade700
        : confirmColorOn(context);

    return Semantics(
      button: onTap != null,
      label: over
          ? 'Safe to spend today: '
                '${formatPeso(-s.leftToday, masked: masked)} over. '
                'Tap to see how it is worked out.'
          : 'Safe to spend today: '
                '${formatPeso(s.leftToday, masked: masked)} left. '
                'Tap to see how it is worked out.',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('tip-safe-to-spend'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Safe to spend today',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                MoneyText(
                  s.leftToday.abs(),
                  sign: over ? '-' : null,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: over ? dangerColorOn(context) : colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: s.usedFraction,
                minHeight: 7,
                backgroundColor: colors.track,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    over
                        ? 'Spent ${formatPeso(s.spentToday, masked: masked)}, '
                              'over the ${formatPeso(s.dailyLimit, masked: masked)} '
                              'for today'
                        : '${formatPeso(s.spentToday, masked: masked)} spent '
                              'of ${formatPeso(s.dailyLimit, masked: masked)} '
                              'for today',
                    style: TextStyle(fontSize: 12, color: colors.textBody),
                  ),
                ),
                Text(
                  'See how',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
