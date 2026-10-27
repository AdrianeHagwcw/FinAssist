import 'package:flutter/material.dart';

import '../../backend/models/goal.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';

/// The icon a goal shows once it is reached, in place of the target.
const goalReachedIcon = 'assets/icons/icons8-verified-96.png';

/// Whole percent saved, from [progress] (0 to 1). Only a reached goal reads
/// 100, and saving past the target never reads more.
int goalPercent(double progress, {required bool reached}) {
  if (reached) return 100;
  final percent = (progress * 100).floor();
  return percent.clamp(0, 99);
}

/// The color for a goal at [percent]: amber getting started, blue on the
/// way, teal almost there, green once reached. Never red: having saved a
/// little is not a warning. Light mode takes darker shades of the same
/// colors so the percent and label stay readable on white.
Color getProgressColor(int percent, {required bool dark}) {
  if (percent >= 100) {
    return dark ? const Color(0xFF22C55E) : const Color(0xFF15803D);
  }
  if (percent >= 75) {
    return dark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E);
  }
  if (percent >= 25) {
    return dark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
  }
  return dark ? const Color(0xFFF59E0B) : const Color(0xFFB45309);
}

/// A few words for how far along [percent] is, under the bar.
String getProgressLabel(int percent) {
  if (percent >= 100) return 'Goal reached';
  if (percent >= 75) return 'Almost there!';
  if (percent >= 25) return 'On the way';
  return 'Getting started';
}

/// A goal's progress bar, colored by how far along it is, with the percent
/// on the right and a few words under it, all in the bar's color. The width
/// and color ease into a new amount instead of jumping.
class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({
    required this.progress,
    required this.reached,
    this.height = 8,
    this.showPercent = true,
    this.showLabel = true,
    super.key,
  });

  /// 0 to 1.
  final double progress;
  final bool reached;
  final double height;
  final bool showPercent;
  final bool showLabel;

  static const _duration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final percent = goalPercent(progress, reached: reached);
    final color = getProgressColor(percent, dark: context.isDarkMode);
    // A reached goal fills the bar, however far past the target it went.
    final value = reached ? 1.0 : progress.clamp(0.0, 1.0);

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: _duration,
      curve: Curves.easeOut,
      builder: (context, shade, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: _duration,
        curve: Curves.easeOut,
        builder: (context, filled, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: filled,
                      minHeight: height,
                      backgroundColor: context.appColors.track,
                      color: shade,
                    ),
                  ),
                ),
                if (showPercent) ...[
                  const SizedBox(width: 10),
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: shade,
                    ),
                  ),
                ],
              ],
            ),
            if (showLabel) ...[
              const SizedBox(height: 6),
              Text(
                getProgressLabel(percent),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: shade,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A goal's plan under its progress bar, from [goalPlanLine]: how much a
/// month reaches it by its finish date. Shown once the goal is set up, so
/// it counts what is already set aside.
class GoalPlanNote extends StatelessWidget {
  const GoalPlanNote(this.line, {super.key});

  final ({String text, GoalPlanTone tone}) line;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (background, foreground) = switch (line.tone) {
      GoalPlanTone.plan ||
      GoalPlanTone.needsDate => (colors.primaryTint, colors.textBody),
      GoalPlanTone.onTrack => (
        confirmColorOn(context).withValues(alpha: 0.12),
        confirmColorOn(context),
      ),
      GoalPlanTone.behind || GoalPlanTone.datePassed => (
        dangerColorOn(context).withValues(alpha: 0.12),
        dangerColorOn(context),
      ),
    };

    return Container(
      key: const Key('goal-plan-note'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/icons/icons8-calendar-96.png',
            width: 18,
            height: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
