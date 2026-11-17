enum FinancialChartType { bar, pie, line, progress }

String financialChartExplanation(FinancialChartData data, String language) {
  if (!data.available) {
    return language == 'Tagalog'
        ? 'Hindi makagawa ng chart: ${data.unavailableReason}'
        : 'I could not create this chart because ${data.unavailableReason}';
  }
  final largest = data.totals.entries
      .where((entry) => entry.key != 'Remaining')
      .fold<MapEntry<String, double>?>(null, (best, entry) {
        if (best == null || entry.value > best.value) return entry;
        return best;
      });
  final largestText = largest == null
      ? ''
      : data.totals.length == 1
      ? ' Recorded ${largest.key.toLowerCase()} total: '
            '₱${largest.value.toStringAsFixed(2)}.'
      : ' ${largest.key} is the largest recorded value at '
            '₱${largest.value.toStringAsFixed(2)}.';
  return language == 'Tagalog'
      ? 'Narito ang chart batay sa iyong verified records para sa '
            '${data.periodLabel}.$largestText'
      : 'This chart uses your verified records for ${data.periodLabel}.$largestText';
}

class FinancialChartData {
  const FinancialChartData({
    required this.type,
    required this.title,
    required this.periodLabel,
    required this.labels,
    required this.series,
    required this.totals,
    this.available = true,
    this.unavailableReason,
    this.currency = 'PHP',
  });

  const FinancialChartData.unavailable({
    required this.title,
    required this.periodLabel,
    required String reason,
  }) : type = FinancialChartType.bar,
       labels = const [],
       series = const {},
       totals = const {},
       available = false,
       unavailableReason = reason,
       currency = 'PHP';

  final FinancialChartType type;
  final String title;
  final String periodLabel;
  final List<String> labels;
  final Map<String, List<double>> series;
  final Map<String, double> totals;
  final bool available;
  final String? unavailableReason;
  final String currency;
}
