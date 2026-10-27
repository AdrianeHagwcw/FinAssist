import 'package:flutter/material.dart';

/// The app's colored icons, for things: what something is, a field's kind,
/// a tip, an empty screen. What a tap does (back, close, add, edit, delete,
/// check, search, send) stays a plain line icon on purpose, so actions never
/// compete with the content.
abstract final class AppIcons {
  static const email = 'assets/icons/icons8-email-96.png';
  static const lock = 'assets/icons/icons8-lock-96.png';
  static const person = 'assets/icons/icons8-user-96.png';
  static const profile = 'assets/icons/icons8-profile-94.png';
  static const shown = 'assets/icons/icons8-visible-96.png';
  static const hidden = 'assets/icons/icons8-invisible-96.png';
  static const idea = 'assets/icons/icons8-idea-96.png';
  static const help = 'assets/icons/icons8-help-96.png';
  static const chart = 'assets/icons/icons8-combo-chart-100.png';
  static const moneyBox = 'assets/icons/icons8-money-box-96.png';
  static const shopping = 'assets/icons/icons8-cat-shopping-96.png';
  static const split = 'assets/icons/icons8-pie-chart-96.png';
  static const cashInflow = 'assets/icons/icons8-banknotes-96.png';
}

/// A text field's icon, before what is typed: the app's colored icon for
/// what the field is for.
class FieldIcon extends StatelessWidget {
  const FieldIcon(this.asset, {super.key});

  final String asset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Image.asset(asset, width: 22, height: 22),
  );
}

/// The eye on a password field. It shows what a tap will do: an open eye
/// while the password is hidden ("show it"), a crossed-out one while it can
/// be read ("hide it"), matching what it says to a screen reader.
class PasswordEye extends StatelessWidget {
  const PasswordEye({
    required this.hidden,
    required this.onPressed,
    this.what = 'password',
    super.key,
  });

  final bool hidden;
  final VoidCallback? onPressed;
  final String what;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: hidden ? 'Show $what' : 'Hide $what',
    onPressed: onPressed,
    icon: Image.asset(
      hidden ? AppIcons.shown : AppIcons.hidden,
      width: 24,
      height: 24,
    ),
  );
}
