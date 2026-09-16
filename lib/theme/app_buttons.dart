import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme.dart';

/// One colour rule for every button in the app, so a colour always means the
/// same thing and the user can read a screen without reading every label:
///
/// * **Green** — this commits what you came to do: Save, Add, Record Payment,
///   Mark as Paid, Confirm.
/// * **Red** — this destroys something: Delete, Remove, Log Out, Undo.
/// * **Blue** — this opens or edits something, and nothing is decided yet:
///   Add Wallet, Add Budget, Edit, the "+" button.
///
/// The split that matters is *opening* versus *committing*. "Add Wallet" on
/// the wallets screen is blue because it only opens a form; "Add Wallet"
/// inside that form is green because it is the one that saves.
const Color appConfirmGreen = Color(0xFF2E7D32);
const Color appDangerRed = Color(0xFFD32F2F);

/// Green and red for text and outlines, lightened in dark mode where the
/// solid shades are too dark to read.
Color confirmColorOn(BuildContext context) =>
    context.isDarkMode ? const Color(0xFF66BB6A) : appConfirmGreen;

Color dangerColorOn(BuildContext context) =>
    context.isDarkMode ? const Color(0xFFEF5350) : appDangerRed;

/// A filled button in one of the three meanings.
ButtonStyle _filledStyle(Color color, {double height = 52}) {
  return ElevatedButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    disabledBackgroundColor: color.withValues(alpha: 0.5),
    disabledForegroundColor: Colors.white70,
    elevation: 0,
    minimumSize: Size(0, height),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// The button that saves, pays or confirms.
ButtonStyle confirmButtonStyle({double height = 52}) =>
    _filledStyle(appConfirmGreen, height: height);

/// The button that deletes or removes.
ButtonStyle dangerButtonStyle({double height = 52}) =>
    _filledStyle(appDangerRed, height: height);

/// The button that opens a form or starts an edit. Nothing is decided by
/// pressing it.
ButtonStyle openButtonStyle({double height = 52}) =>
    _filledStyle(appPrimaryBlue, height: height);

/// Dialog actions, where a filled button would shout. The colour still
/// carries the meaning.
ButtonStyle confirmTextStyle(BuildContext context) =>
    TextButton.styleFrom(foregroundColor: confirmColorOn(context));

ButtonStyle dangerTextStyle(BuildContext context) =>
    TextButton.styleFrom(foregroundColor: dangerColorOn(context));

/// Cancel backs out, so it is red like the other buttons that undo or stop
/// something.
ButtonStyle cancelTextStyle(BuildContext context) =>
    TextButton.styleFrom(foregroundColor: dangerColorOn(context));

/// A red outlined button, for a destructive action that isn't the main thing
/// on the screen.
ButtonStyle dangerOutlineStyle(BuildContext context, {double height = 46}) {
  return OutlinedButton.styleFrom(
    foregroundColor: dangerColorOn(context),
    side: BorderSide(color: dangerColorOn(context).withValues(alpha: 0.5)),
    minimumSize: Size(0, height),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// A blue outlined button, for a secondary action that only opens something.
ButtonStyle openOutlineStyle(BuildContext context, {double height = 46}) {
  return OutlinedButton.styleFrom(
    foregroundColor: appPrimaryBlue,
    side: BorderSide(color: appPrimaryBlue.withValues(alpha: 0.5)),
    minimumSize: Size(0, height),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// Menu entries carry the same meaning as buttons, so they get the same
/// colours on their icons.
PopupMenuItem<T> menuItem<T>({
  required T value,
  required String label,
  required IconData icon,
  Color? color,
}) {
  return PopupMenuItem<T>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: color == null ? null : TextStyle(color: color)),
      ],
    ),
  );
}
