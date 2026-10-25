import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../theme/app_theme.dart';

/// Shared pieces for the app's small "enter an amount" dialogs, so Add Income
/// and Add Budget look like the same app rather than two different forms.

/// Rounded corners matching the cards and sheets elsewhere.
const dialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(18)),
);

/// Title row: a colored icon in a tinted square, then the heading.
class DialogTitle extends StatelessWidget {
  const DialogTitle({required this.text, required this.iconAsset, super.key});

  final String text;
  final String iconAsset;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.primaryTint,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Image.asset(iconAsset),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The amount being entered, with its peso sign. The same size as every
/// other field, wherever it is, so no form looks unlike the rest.
class AmountField extends StatelessWidget {
  const AmountField({
    required this.controller,
    required this.label,
    this.hint = '0.00',
    this.helper,
    this.errorText,
    this.alwaysShowHint = false,
    this.enabled = true,
    this.autofocus = true,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  /// Grey example inside the field, such as `20000`.
  final String hint;

  /// A short line under the field saying what goes in it.
  final String? helper;

  /// What is wrong with the amount, in red under it in place of [helper].
  final String? errorText;

  /// Keeps the label above the field so the example shows before it is
  /// tapped. The peso sign then waits for the first digit, so the example
  /// can't be taken for an amount already filled in. The screen showing the
  /// field rebuilds it as the user types.
  final bool alwaysShowHint;
  final bool enabled;
  final bool autofocus;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [ThousandsSeparatorFormatter()],
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: dialogFieldDecoration(context, label, helper: helper)
          .copyWith(
            prefixText: alwaysShowHint && controller.text.isEmpty ? null : '₱ ',
            hintText: hint,
            errorText: errorText,
            // Wraps rather than trailing off, so the sentence can be read.
            helperMaxLines: 3,
            floatingLabelBehavior: alwaysShowHint
                ? FloatingLabelBehavior.always
                : null,
          ),
    );
  }
}

/// One look for every field in these dialogs.
InputDecoration dialogFieldDecoration(
  BuildContext context,
  String label, {
  String? hint,
  String? helper,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    filled: true,
    fillColor: context.appColors.inputFill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.appColors.inputBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.appColors.inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: appPrimaryBlue, width: 1.6),
    ),
  );
}

/// The button that commits the dialog. Green, like every other button
/// that saves something.
class DialogSaveButton extends StatelessWidget {
  const DialogSaveButton({
    required this.onPressed,
    required this.isSaving,
    this.label = 'Save',
    super.key,
  });

  final VoidCallback? onPressed;
  final bool isSaving;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: isSaving ? null : onPressed,
        // Green: this is the button that commits.
        style: confirmButtonStyle(height: 44).copyWith(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24),
          ),
        ),
        child: isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

/// A quiet line of context above the fields, e.g. the current daily limit.
class DialogNote extends StatelessWidget {
  const DialogNote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: colors.textBody, height: 1.3),
      ),
    );
  }
}

/// Says something was just taken away and gives a few seconds to put it
/// back. A bar along the bottom shrinks as the time runs out, so the user
/// can see how long Undo stays. [iconAsset] names what was changed, in the
/// same colored icons the rest of the app uses.
void showUndoSnackBar(
  BuildContext context, {
  required String title,
  required String message,
  required VoidCallback onUndo,
  String? iconAsset,
  Duration duration = const Duration(seconds: 5),
}) {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.appColors;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: EdgeInsets.zero,
        elevation: 6,
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border),
        ),
        content: _UndoNotice(
          title: title,
          message: message,
          iconAsset: iconAsset,
          duration: duration,
          onUndo: () {
            messenger.hideCurrentSnackBar();
            onUndo();
          },
        ),
      ),
    );
}

class _UndoNotice extends StatelessWidget {
  const _UndoNotice({
    required this.title,
    required this.message,
    required this.iconAsset,
    required this.duration,
    required this.onUndo,
  });

  final String title;
  final String message;
  final String? iconAsset;
  final Duration duration;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  child: iconAsset == null
                      ? Icon(Icons.undo, color: colors.primaryText, size: 20)
                      : Image.asset(iconAsset!, width: 24, height: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: TextStyle(fontSize: 12, color: colors.textBody),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: onUndo,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primaryText,
                    minimumSize: const Size(64, 44),
                  ),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text(
                    'Undo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // How long Undo stays, shrinking to nothing.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: duration,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 3,
              backgroundColor: Colors.transparent,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one warning before anything is removed: a red icon, what will
/// happen, a blue Cancel and a red button that does it. Returns true only
/// when the user chose to go ahead.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
  IconData icon = Icons.delete_outline,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: dialogShape,
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: dangerColorOn(context).withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: dangerColorOn(context), size: 26),
      ),
      title: Text(title),
      content: Text(
        message,
        style: TextStyle(color: context.appColors.textBody, height: 1.4),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        // Blue, so the only red button is the one that removes.
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: appPrimaryBlue,
            minimumSize: const Size(64, 44),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: dangerButtonStyle(height: 44),
          child: Text(
            action,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}
