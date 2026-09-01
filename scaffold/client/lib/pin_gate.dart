// OLIVE BRANCH — PIN gate. Verified by CI (a Flutter toolchain now runs
// for real — CHANGELOG v0.49.61). §8.3, §5.20.
//
// Rendered one frame after a kiosk defeat. Never shows an error, never shows an
// adult surface. The keypad order is SHUFFLED because the child is watching the
// adult type (§8.3) — and the shuffle must come from the platform CSPRNG, not
// from a seeded or time-based source.
import 'dart:math';
import 'package:flutter/material.dart';

class PinGate extends StatefulWidget {
  const PinGate({super.key, required this.digits, required this.onComplete,
    this.shuffle = true});
  final int digits;
  final ValueChanged<String> onComplete;
  final bool shuffle;
  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  late List<int> keys;
  String entered = '';

  @override
  void initState() {
    super.initState();
    keys = List<int>.generate(9, (i) => i + 1);
    // Random.secure() — a predictable shuffle is no shuffle.
    if (widget.shuffle) keys.shuffle(Random.secure());
  }

  void _tap(int d) {
    if (entered.length >= widget.digits) return;
    setState(() => entered += '$d');
    if (entered.length == widget.digits) {
      widget.onComplete(entered);
      // Re-shuffle after every attempt so repeated observation gains nothing.
      setState(() { entered = ''; if (widget.shuffle) keys.shuffle(Random.secure()); });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF12172B),
    body: SafeArea(child: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Welcome back', style: TextStyle(
          color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Type your code to keep going',
          style: TextStyle(color: Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.digits, (i) => Container(
            width: 11, height: 11, margin: const EdgeInsets.symmetric(horizontal: 4.5),
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: i < entered.length ? Colors.white : Colors.transparent,
              border: Border.all(color: Colors.white54, width: 1.5))))),
        const SizedBox(height: 20),
        SizedBox(width: 188, child: Wrap(spacing: 9, runSpacing: 9,
          children: keys.map((d) => SizedBox(width: 52, height: 48,
            child: TextButton(onPressed: () => _tap(d),
              child: Text('$d', style: const TextStyle(
                color: Colors.white, fontSize: 16)))))
            .toList())),
        const SizedBox(height: 14),
        const Text('keypad order changes every time',
          style: TextStyle(color: Colors.white38, fontSize: 9)),
      ]))),
  );
}
