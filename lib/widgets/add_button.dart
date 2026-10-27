import 'package:flutter/material.dart';

import '../theme/app_buttons.dart';

/// The green Add button under a list, full width: Add Bill, Add Installment,
/// Add Debt, the same as Add Goal and Add Savings. One look on every screen,
/// so adding something always reads the same.
class AddButton extends StatelessWidget {
  const AddButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: confirmButtonStyle(),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
