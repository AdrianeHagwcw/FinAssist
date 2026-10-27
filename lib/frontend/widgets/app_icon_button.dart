import 'package:flutter/material.dart';

/// The eye that hides and shows every amount, as one of the app's colored
/// icons: open while amounts show, crossed out while they are hidden.
const String amountsShownIcon = 'assets/icons/icons8-visible-96.png';
const String amountsHiddenIcon = 'assets/icons/icons8-invisible-96.png';

/// What a figure means: the app's bulb, the same icon as its other tips
/// and "Read about" links.
const String infoIcon = 'assets/icons/icons8-idea-96.png';

/// A round button showing one of the app's colored icons, the way icons look
/// everywhere else in FinAssist, rather than a plain outline.
///
/// The icon sits straight on the card, with no disc behind it: its own
/// colors read on the blue balance card and on a plain one alike. The tap
/// area is the full 48 points.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.iconAsset,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final String iconAsset;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Image.asset(iconAsset, width: 26, height: 26),
    );
  }
}
