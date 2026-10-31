import 'package:flutter/material.dart';

import '../../app/theme.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return 'None';
  const gb = 1000 * 1000 * 1000;
  const mb = 1000 * 1000;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / mb).round()} MB';
}

/// Medha's mark: a ring with a centre dot and an orbiting dot.
class MedhaLogo extends StatelessWidget {
  const MedhaLogo({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _LogoPainter()),
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 28;
    final ring = Paint()
      ..color = MedhaColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s;
    canvas.drawCircle(Offset(14 * s, 14 * s), 11 * s, ring);
    canvas.drawCircle(Offset(14 * s, 14 * s), 3.5 * s, Paint()..color = MedhaColors.accent);
    canvas.drawCircle(Offset(23.5 * s, 8.5 * s), 2.4 * s, Paint()..color = MedhaColors.text);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: MedhaColors.muted),
        ),
      );
}

/// Small rounded label, e.g. "Offline" or "Coming soon".
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = MedhaColors.textSoft, this.background = MedhaColors.ink, this.icon});
  final String text;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 5)],
            Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      );
}

const aiDisclosure = 'Medha is an AI and can make mistakes. Check important answers.';
