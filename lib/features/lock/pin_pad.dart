import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// PIN dots + keypad. Calls [onComplete] when [length] digits are entered.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onComplete,
    this.length = 4,
    this.message,
    this.error = false,
    this.enabled = true,
    this.onBiometric,
  });

  final Future<void> Function(String pin) onComplete;
  final int length;
  final String? message;
  final bool error;
  final bool enabled;
  final VoidCallback? onBiometric;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  Future<void> _press(String d) async {
    if (!widget.enabled || _busy || _pin.length >= widget.length) return;
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      setState(() => _busy = true);
      final pin = _pin;
      await widget.onComplete(pin);
      if (mounted) {
        setState(() {
          _pin = '';
          _busy = false;
        });
      }
    }
  }

  void _back() {
    if (_pin.isNotEmpty && !_busy) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Widget _key(Widget child, VoidCallback? onTap, {String? label}) => SizedBox(
        width: 72,
        height: 72,
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: label == null ? MedhaColors.surface : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Center(child: child)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final color = widget.error ? const Color(0xFFFF8A80) : MedhaColors.accent;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < widget.length; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _pin.length ? color : Colors.transparent,
              border: Border.all(color: widget.error ? color : (i < _pin.length ? color : MedhaColors.faint), width: 2),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 20,
        child: Text(widget.message ?? '',
            style: TextStyle(fontSize: 13, color: widget.error ? const Color(0xFFFF8A80) : MedhaColors.muted)),
      ),
      const SizedBox(height: 12),
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final d in row)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _key(Text(d, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)), () => _press(d)),
              ),
          ]),
        ),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: widget.onBiometric == null
              ? const SizedBox(width: 72, height: 72)
              : _key(const Icon(Icons.fingerprint, color: MedhaColors.accent, size: 30), widget.onBiometric, label: 'Use fingerprint'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _key(const Text('0', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)), () => _press('0')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _key(const Icon(Icons.backspace_outlined, color: MedhaColors.muted), _back, label: 'Delete digit'),
        ),
      ]),
    ]);
  }
}
