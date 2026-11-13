import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme.dart';

/// One colour rule for every button in the app, so a colour always means the
/// same thing and the user can read a screen without reading every label:
///
/// * **Green** — this adds, commits or completes: Add, Save, Record Payment,
///   Pay, Mark as Paid, Confirm, Done.
/// * **Red** — this removes, cancels, stops or takes back: Delete, Remove,
///   Log Out, Undo, Cancel, Discard. Only things that lose something.
/// * **Blue** — this continues the process: opens a form, sheet or screen,
///   starts an edit, or moves on to the next step (Pay in advance, Pay part
///   of it, Review, Next).
/// * **Grey** — this is the second answer, not a decision: "not now",
///   "dismiss", "leave it as it is" (Skip this one, Not yet, Close, Keep
///   Editing, Keep My Account).
///
/// Grey is not a fourth meaning, it is the second *weight*: colour says what
/// kind of thing a press does, fill says how much it matters. A grey button
/// is still obviously a button and still easy to tap, it just steps back
/// beside the coloured one. Red stays honest that way — it only appears where
/// something is actually lost, so it still reads as a warning instead of an
/// everyday "skip this".
///
/// The same meanings carry through the filled buttons, the outlined buttons
/// and the text buttons in dialogs, so a blue outline and a solid blue button
/// are the same blue, and a button never carries a colour of its own.
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

/// The grey button: the second answer on a screen, not a decision of its own.
/// Same size and shape as the coloured fills so a pair of buttons line up,
/// with the page's own grey behind it and a thin edge so it still reads as a
/// button on a white card, in both modes.
ButtonStyle neutralButtonStyle(BuildContext context, {double height = 46}) {
  final colors = context.appColors;
  return ElevatedButton.styleFrom(
    backgroundColor: colors.track,
    foregroundColor: colors.textPrimary,
    disabledBackgroundColor: colors.track.withValues(alpha: 0.5),
    disabledForegroundColor: colors.textMuted,
    elevation: 0,
    minimumSize: Size(0, height),
    side: BorderSide(color: colors.inputBorder),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

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

/// Blue text, for a text action that opens or continues: a link, a review
/// step, the way on to another screen.
ButtonStyle openTextStyle(BuildContext context, {bool compact = false}) =>
    TextButton.styleFrom(
      foregroundColor: context.appColors.primaryText,
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8)
          : null,
    );

/// Quiet text, for a show/hide toggle or a soft "not now" inside a row. These
/// carry no decision of their own, so they stay colourless rather than
/// borrowing a colour that would suggest one.
ButtonStyle neutralTextStyle(BuildContext context, {bool compact = false}) =>
    TextButton.styleFrom(
      foregroundColor: context.appColors.textBody,
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8)
          : null,
    );

/// A red outlined button, for a destructive action that isn't the main thing
/// on the screen.
ButtonStyle dangerOutlineStyle(BuildContext context, {double height = 46}) {
  return OutlinedButton.styleFrom(
    foregroundColor: dangerColorOn(context),
    side: BorderSide(color: dangerColorOn(context), width: 1.2),
    minimumSize: Size(0, height),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// A green outlined button, for a secondary action that commits or completes
/// without being the main button on the screen.
ButtonStyle confirmOutlineStyle(BuildContext context, {double height = 46}) {
  return OutlinedButton.styleFrom(
    foregroundColor: confirmColorOn(context),
    side: BorderSide(color: confirmColorOn(context), width: 1.2),
    minimumSize: Size(0, height),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// A blue outlined button, for a secondary action that only opens something.
ButtonStyle openOutlineStyle(BuildContext context, {double height = 46}) {
  // The app's blue for text: the brand blue in light mode, a lighter one in
  // dark mode, where the brand blue is too dark to read on the background.
  final blue = context.appColors.primaryText;
  return OutlinedButton.styleFrom(
    foregroundColor: blue,
    side: BorderSide(color: blue, width: 1.2),
    minimumSize: Size(0, height),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// A grey outlined button, for the quiet full-width twin of a grey fill: the
/// way back from something that was set aside (Put this bill back).
ButtonStyle neutralOutlineStyle(BuildContext context, {double height = 46}) {
  final colors = context.appColors;
  return OutlinedButton.styleFrom(
    foregroundColor: colors.textPrimary,
    side: BorderSide(color: colors.inputBorder, width: 1.2),
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
        // The label wraps rather than running past the menu's edge, which a
        // long entry did on a narrow screen or at a large text size.
        Flexible(
          child: Text(
            label,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    ),
  );
}
