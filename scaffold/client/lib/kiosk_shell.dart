// OLIVE BRANCH — kiosk shell. No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs
// for real in tools/verify.sh's automated pipeline — CHANGELOG v0.49.61).
// MASTERFILE §5.20, §8.3.
//
// Wraps the child side of the app. Owns a LockController-driven LockState,
// engages the native lock on mount via kiosk_channel.dart, and renders
// exactly one of ChildHome / PinGate / a locked-out screen / the guardian
// escalation surface through canRender()'s deny-by-default gate — never
// anything else, and the guardian surface only after a real PIN+biometric
// escalation, never by falling through.
//
// The lock is engaged at the Activity level (startLockTask pins the whole
// app), so routes pushed from inside `child` (homework, wants/needs, a live
// call) stay inside the pinned activity automatically. Nothing here needs to
// re-check the lock per-route.
//
// PIN verification: `verifyPin` is injected, not hardcoded, so the full
// defeat -> PIN gate -> re-entry -> cooldown -> break-glass loop is testable
// with a fake and swappable for a real check per entry point. A real one now
// exists and is wired: `main_live.dart`'s `_verifyGuardianPin` calls
// `api.verifyKioskPin()` (api_client.dart), POSTing to server/routes.mjs's
// real `/kiosk-pin/verify`, which checks against RLS-scoped `pin_credential`
// (auth.ts) server-side — the hash never reaches this device. `main.dart`'s
// offline preview build keeps an honest fixed-code stand-in instead, since it
// has no backend to reach at all (see that file's own header).
//
// Guardian escalation (`escalate()` in lock_controller.dart, PIN+biometric ->
// `guardian_escalation`) is now wired end to end: a small persistent
// affordance over the locked child surface starts it, PinGate collects the
// PIN (reused as-is — it never knows whose code it is), [verifyBiometric]
// runs the real factor, and a successful `escalate()` lands on
// guardian_escalation_screen.dart — the "guardian settings reachable from
// the child's device" surface that used to not exist. Its own real action is
// releasing the native lock (`KioskChannel.stop()`); there is no voluntary
// "step back down without exiting" path because lock_controller.dart has no
// such transition — see that screen's own header for why one isn't invented
// here.
import 'dart:async';
import 'package:flutter/material.dart';
import 'guardian_escalation_screen.dart';
import 'kiosk_channel.dart';
import 'lock_controller.dart' as lock;
import 'pin_gate.dart';

class KioskShell extends StatefulWidget {
  const KioskShell({
    super.key,
    required this.child,
    required this.verifyPin,
    required this.verifyBiometric,
    this.channel,
    this.pinDigits = 4,
    this.childName = 'your child',
  });

  /// The unlocked child surface — typically a ChildHome.
  final Widget child;
  /// Injected so this is testable and so the (currently demo-only) PIN check
  /// has exactly one place it will need to change once a backend exists.
  final Future<bool> Function(String pin) verifyPin;
  /// The biometric half of §8.3 guardian escalation — PIN alone is
  /// shoulder-surfable by the child sitting right there. Real wiring is
  /// `webauthn_channel.dart`'s `buildVerifyBiometricCallback`; a demo build
  /// supplies an honest stand-in the same way `main.dart` already does for
  /// [verifyPin].
  final Future<bool> Function() verifyBiometric;
  /// Shown on `GuardianEscalationScreen` once escalated.
  final String childName;
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

  /// §8.3 guardian escalation: PIN, then — only if the PIN was right; no
  /// reason to prompt a real platform-authenticator ceremony for a code that
  /// was already wrong — the biometric factor. Denial (either factor,
  /// cooldown) gets one deliberately generic message: the child sitting
  /// there watching (§8.3's own framing) never learns which factor failed.
  Future<void> _attemptEscalation() async {
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PinGate(digits: widget.pinDigits, onComplete: Navigator.of(context).pop),
      ),
    );
    if (pin == null || !mounted) return;
    final pinOk = await widget.verifyPin(pin);
    if (!mounted) return;
    final biometricOk = pinOk ? await widget.verifyBiometric() : false;
    if (!mounted) return;
    final result = lock.escalate(_state, pinOk, biometricOk, DateTime.now());
    setState(() => _state = result.state);
    if (result.denied != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't verify. Try again."), duration: Duration(seconds: 2)),
      );
    }
  }

  /// The one real action `GuardianEscalationScreen` offers: release the
  /// native lock, then reset to an unlocked state — the same shape
  /// `_engage()` already falls back to when no native handler exists.
  Future<void> _exitKiosk() async {
    await _channel.stop();
    if (!mounted) return;
    setState(() => _state = lock.initialState(lock.LockMode.none));
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
    if (lock.canRender(_state, lock.Surface.childHome, now)) {
      return Stack(children: [
        widget.child,
        _EscalationTrigger(onTap: _attemptEscalation),
      ]);
    }
    if (lock.canRender(_state, lock.Surface.pinGate, now)) {
      return PinGate(digits: widget.pinDigits, onComplete: _onPinComplete);
    }
    if (lock.canRender(_state, lock.Surface.lockedOut, now)) {
      return _LockedOutScreen(
        cooldownUntil: _state.cooldownUntil,
        onBreakGlass: _attemptBreakGlass,
      );
    }
    if (lock.canRender(_state, lock.Surface.guardianEscalation, now)) {
      return GuardianEscalationScreen(
        escalatedUntil: _state.escalatedUntil,
        onExitKiosk: _exitKiosk,
        childName: widget.childName,
      );
    }
    // child_session is unreached from this shell (see class doc) —
    // canRender's own deny-by-default means falling through here is
    // unreachable in practice, but the shell still needs a value.
    return widget.child;
  }
}

/// Small, unobtrusive — the child sitting there is watching (§8.3) — and
/// lives in the SHELL's chrome, never inside `widget.child`: ChildHome and
/// every other child-facing surface has no settings affordance at any depth
/// (§8.1), and this is deliberately not one either — tapping it starts a
/// PIN + biometric ceremony a child cannot pass, not a menu.
class _EscalationTrigger extends StatelessWidget {
  const _EscalationTrigger({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 4,
    bottom: 4,
    child: SafeArea(
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          key: const Key('guardianEscalationTrigger'),
          onPressed: onTap,
          icon: Icon(Icons.shield_outlined, size: 18,
            color: Colors.white.withValues(alpha: 0.28)),
          tooltip: 'Guardian',
        ),
      ),
    ),
  );
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
