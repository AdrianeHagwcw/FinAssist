import 'package:flutter/material.dart';

/// Lets the tabs below the bottom bar go back to Home.
///
/// Placed by the main shell around its tab pages. A tab page shown on its
/// own, like in a test, finds no scope and shows no back arrow.
class BackToHomeScope extends InheritedWidget {
  const BackToHomeScope({
    required this.goHome,
    required super.child,
    super.key,
  });

  final VoidCallback goHome;

  static BackToHomeScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackToHomeScope>();

  @override
  bool updateShouldNotify(BackToHomeScope oldWidget) => false;
}

/// The back arrow for a tab's app bar, or null outside the main shell.
Widget? backToHomeButton(BuildContext context) {
  final scope = BackToHomeScope._of(context);
  if (scope == null) return null;

  return IconButton(
    tooltip: 'Back to Home',
    icon: const Icon(Icons.arrow_back),
    onPressed: scope.goHome,
  );
}
