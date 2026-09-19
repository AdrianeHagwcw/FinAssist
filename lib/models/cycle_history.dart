import 'allocation.dart';

enum CycleStatus { active, pending, done, declined }

CycleStatus cycleStatus(
  AllocationCycle cycle,
  String? frequency,
  DateTime now,
) {
  if (cycle.decision == LeftoverDecision.spent) return CycleStatus.declined;
  if (cycle.isResolved) return CycleStatus.done;
  final period = periodOf(cycle, frequency);
  return period.isLastDay(now) || !now.isBefore(period.end)
      ? CycleStatus.pending
      : CycleStatus.active;
}

List<AllocationCycle> newestCycles(Iterable<AllocationCycle> cycles) =>
    cycles.toList()..sort((a, b) {
      final date = b.receivedAt.compareTo(a.receivedAt);
      return date == 0 ? b.id.compareTo(a.id) : date;
    });
