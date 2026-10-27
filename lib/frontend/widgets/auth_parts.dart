import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_logo.dart';

/// The top of Log In and Create Account: the logo on the page, and what
/// the app is for.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Center(child: AppLogo.trimmed(width: 180)),
      const SizedBox(height: 14),
      Text(
        // Two even lines, not one word left on its own.
        'Track spending, pay bills on time,\n'
        'and save for your goals.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: context.appColors.textMuted,
        ),
      ),
    ],
  );
}

/// A line with a few words in the middle, such as "or use another account".
class OrDivider extends StatelessWidget {
  const OrDivider(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(child: Divider(color: colors.inputBorder)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
        ),
        Expanded(child: Divider(color: colors.inputBorder)),
      ],
    );
  }
}

/// "Continue with Google", the same on Log In and Create Account.
class GoogleButton extends StatelessWidget {
  const GoogleButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const GoogleLogo(),
      label: Text(
        'Continue with Google',
        style: TextStyle(color: colors.textBody, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: colors.inputBorder),
      ),
    );
  }
}

/// Google's "G" in its four colours, drawn so it stays sharp at any size.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CustomPaint(painter: _GoogleLogoPainter()),
  );
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  /// Google's "G" as published for sign-in buttons, on a 48 × 48 grid.
  static const _parts = [
    (
      Color(0xFFEA4335),
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
          '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 '
          '9.5z',
    ),
    (
      Color(0xFF4285F4),
      'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
          '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
    ),
    (
      Color(0xFFFBBC05),
      'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
          'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
    ),
    (
      Color(0xFF34A853),
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
          '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 '
          '48z',
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    for (final (color, data) in _parts) {
      canvas.drawPath(_svgPath(data), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter oldDelegate) => false;
}

/// A path from SVG path data, for the few commands the "G" uses: M, L, H,
/// V, C, S and Z, each in absolute (capital) or relative form.
Path _svgPath(String data) {
  final path = Path();
  final tokens = RegExp(
    r'[MmLlHhVvCcSsZz]|-?(?:\d+\.?\d*|\.\d+)',
  ).allMatches(data).map((match) => match[0]!).toList();
  var i = 0;
  var command = '';
  var x = 0.0, y = 0.0;
  // The second control point of the last curve, for S.
  var controlX = 0.0, controlY = 0.0;
  double next() => double.parse(tokens[i++]);
  bool numberNext() =>
      i < tokens.length && !RegExp(r'^[A-Za-z]$').hasMatch(tokens[i]);

  while (i < tokens.length) {
    if (!numberNext()) command = tokens[i++];
    final relative = command == command.toLowerCase();
    final dx = relative ? x : 0.0, dy = relative ? y : 0.0;
    switch (command.toUpperCase()) {
      case 'M':
        x = next() + dx;
        y = next() + dy;
        path.moveTo(x, y);
        // More points after M are lines.
        command = relative ? 'l' : 'L';
      case 'L':
        x = next() + dx;
        y = next() + dy;
        path.lineTo(x, y);
      case 'H':
        x = next() + dx;
        path.lineTo(x, y);
      case 'V':
        y = next() + dy;
        path.lineTo(x, y);
      case 'C':
        final x1 = next() + dx, y1 = next() + dy;
        controlX = next() + dx;
        controlY = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.cubicTo(x1, y1, controlX, controlY, x, y);
      case 'S':
        // The first control point mirrors the last curve's second.
        final x1 = 2 * x - controlX, y1 = 2 * y - controlY;
        controlX = next() + dx;
        controlY = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.cubicTo(x1, y1, controlX, controlY, x, y);
      case 'Z':
        path.close();
    }
    if (command.toUpperCase() != 'C' && command.toUpperCase() != 'S') {
      controlX = x;
      controlY = y;
    }
  }
  return path;
}
