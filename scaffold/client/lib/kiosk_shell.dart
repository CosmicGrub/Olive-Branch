// OLIVE BRANCH — kiosk shell. MASTERFILE §5.20, §8.3.
//
// Wraps the child side of the app. Owns a LockController-driven LockState,
// engages the native lock on mount via kiosk_channel.dart, and renders
// exactly one of ChildHome / PinGate / a locked-out screen through
// canRender()'s deny-by-default gate — never anything else, never the
// guardian surface.
//
// The lock is engaged at the Activity level (startLockTask pins the whole
// app), so routes pushed from inside `child` (homework, wants/needs, a live
// call) stay inside the pinned activity automatically. Nothing here needs to
// re-check the lock per-route.
//
// PIN verification: there is no backend to check a real guardian PIN against
// yet (see api_client.dart, auth.ts) — RLS on `pin_credential` deliberately
// keeps the hash off-device even when a backend exists. `verifyPin` is
// injected so the full defeat -> PIN gate -> re-entry -> cooldown ->
// break-glass loop is actually exercisable end-to-end on a real device today,
// with the real check to swap in once a backend exists. Mirrors this
// codebase's existing convention for stubbed capabilities (§8.5.0's
// `guardianSetup`: an honest stub, not a faked capability grant).
//
// Guardian escalation (`escalate()` in lock_controller.dart, PIN+biometric ->
// `guardian_escalation`) is ported and unit-tested but deliberately not wired
// to any UI here: there is no "guardian settings reachable from the child's
// device" screen anywhere in this app yet to escalate into. Wiring escalate()
// to nothing would be exactly the "declaration with nothing behind it"
// MASTERFILE §0 warns against, so it stays logic-only until that surface
// exists — same posture as §17.1's `isSingleGuardianViable()`.
import 'dart:async';
import 'package:flutter/material.dart';
import 'kiosk_channel.dart';
import 'lock_controller.dart' as lock;
import 'pin_gate.dart';

class KioskShell extends StatefulWidget {
  const KioskShell({
    super.key,
    required this.child,
    required this.verifyPin,
    this.channel,
    this.pinDigits = 4,
  });

  /// The unlocked child surface — typically a ChildHome.
  final Widget child;
  /// Injected so this is testable and so the (currently demo-only) PIN check
  /// has exactly one place it will need to change once a backend exists.
  final Future<bool> Function(String pin) verifyPin;
  /// Injectable for widget tests; defaults to the real platform channel.
  final KioskChannel? channel;
  final int pinDigits;

  @override
  State<KioskShell> createState() => _KioskShellState();
}

class _KioskShellState extends State<KioskShell> with WidgetsBindingObserver {
  late final KioskChannel _channel;
  StreamSubscription<String>? _sub;
  lock.LockState _state = lock.initialState(lock.LockMode.none);

  @override
  void initState() {
    super.initState();
    _channel = widget.channel ?? KioskChannel();
    WidgetsBinding.instance.addObserver(this);
    _engage();
  }

  Future<void> _engage() async {
    // No native handler exists under `flutter test`, and won't on a platform
    // without a kiosk bridge yet either (this app is Android-only so far).
    // Falls back to LockMode.none — a real, honestly-reported mode, not a
    // crash — rather than letting a MissingPluginException take down the
    // child's home screen.
    var modeWire = 'none';
    try {
      modeWire = await _channel.start();
    } on Object {
      // ignore
    }
    if (!mounted) return;
    setState(() => _state = lock.initialState(lock.LockMode.fromWire(modeWire)));
    _sub = _channel.events().listen(_onNativeEvent, onError: (Object _) {});
  }

  void _onNativeEvent(String event) {
    final now = DateTime.now();
    switch (event) {
      case KioskChannel.eExited:
        // effects.revokeSessionTokens / notifyOtherGuardian have no live
        // backend to call yet — see the class doc. The state transition
        // itself (drop escalation, land on pin_gate) is real regardless.
        setState(() => _state = lock.onLockTaskExited(_state, now).state);
      case KioskChannel.eBackground:
        setState(() => _state = lock.onBackgrounded(_state, now).state);
      case KioskChannel.eResumed:
        break; // informational only; nothing in lock_controller reacts to it
    }
  }

  // Secondary signal alongside the native EventChannel: WidgetsBindingObserver
  // fires at the Flutter framework level even if a platform-channel event is
  // delayed or (on a non-Android platform, once one exists) never arrives.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      setState(() => _state = lock.onBackgrounded(_state, DateTime.now()).state);
    }
  }

  Future<void> _onPinComplete(String pin) async {
    final correct = await widget.verifyPin(pin);
    if (!mounted) return;
    setState(() => _state = lock.submitChildPin(_state, correct, DateTime.now()));
  }

  Future<void> _attemptBreakGlass() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PinGate(digits: widget.pinDigits, onComplete: Navigator.of(context).pop),
      ),
    );
    if (code == null || !mounted) return;
    if (await widget.verifyPin(code) && mounted) {
      setState(() => _state = lock.breakGlass(_state, DateTime.now()).state);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (lock.canRender(_state, lock.Surface.childHome, now)) return widget.child;
    if (lock.canRender(_state, lock.Surface.pinGate, now)) {
      return PinGate(digits: widget.pinDigits, onComplete: _onPinComplete);
    }
    if (lock.canRender(_state, lock.Surface.lockedOut, now)) {
      return _LockedOutScreen(
        cooldownUntil: _state.cooldownUntil,
        onBreakGlass: _attemptBreakGlass,
      );
    }
    // guardian_escalation / child_session are unreached from this shell (see
    // class doc) — canRender's own deny-by-default means falling through
    // here is unreachable in practice, but the shell still needs a value.
    return widget.child;
  }
}

class _LockedOutScreen extends StatelessWidget {
  const _LockedOutScreen({required this.cooldownUntil, required this.onBreakGlass});
  final DateTime? cooldownUntil;
  final VoidCallback onBreakGlass;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF12172B),
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_bottom, color: Colors.white54, size: 32),
            const SizedBox(height: 14),
            const Text(
              'Take a little break',
              style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ask a grown-up if you need back in sooner',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: onBreakGlass,
              child: const Text(
                "I'm the grown-up",
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
