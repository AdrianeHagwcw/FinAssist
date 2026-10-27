import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/models/safe_to_spend.dart';
import '../../backend/utils/money_format.dart';
import '../providers/app_settings_provider.dart';

/// Today's Safe to Spend as a slim bar along the bottom of the Available
/// Balance card: what is spent of today's safe amount, filling as the day
/// goes on. The card's light bulb explains how it is worked out.
class SafeToSpendBar extends StatelessWidget {
  const SafeToSpendBar({required this.safeToSpend, this.onTap, super.key});

  final SafeToSpend safeToSpend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = safeToSpend;
    final over = s.isOverLimit;
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );
    final spent = formatPeso(s.spentToday, masked: masked);
    final limit = formatPeso(s.dailyLimit, masked: masked);
    // Light shades, so the bar reads on the blue card.
    final barColor = over
        ? const Color(0xFFFF8A80)
        : s.usedFraction >= 0.75
        ? const Color(0xFFFFD54F)
        : const Color(0xFFB2F296);

    return Semantics(
      button: onTap != null,
      label: over
          ? 'Over what is safe to spend today: $spent spent of $limit.'
          : 'Safe to spend today: $spent spent of $limit, '
                '${formatPeso(s.leftToday, masked: masked)} left.',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('safe-to-spend-bar'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      over ? "Over today's safe amount" : 'Safe to spend today',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Text(
                    '$spent / $limit',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: s.usedFraction,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
