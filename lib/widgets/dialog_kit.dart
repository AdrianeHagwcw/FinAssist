import 'package:flutter/material.dart';

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

/// The amount being entered, shown larger than the other fields because it is
/// the one number the user came here to type.
class AmountField extends StatelessWidget {
  const AmountField({
    required this.controller,
    required this.label,
    this.hint = '0.00',
    this.helper,
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
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: context.appColors.textPrimary,
      ),
      decoration: dialogFieldDecoration(context, label, helper: helper)
          .copyWith(
            prefixText: alwaysShowHint && controller.text.isEmpty ? null : '₱ ',
            hintText: hint,
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
