// OLIVE BRANCH — who may take a picture of what is on the screen. Verified by CI headless
// (client/test/screen_privacy_test.dart). Spec: docs/planning/QR-VETTING-BRAINSTORM.md, "Screenshots: a setting for
// grown-ups, and sharing between grown-ups only"; owner decisions in docs/planning/DECISIONS.md.
//
// ONE RULE, in one function: [secureFlagWanted]. Android treats "blank in the recents list", "no screenshot" and "no
// screen recording" as one window flag (FLAG_SECURE), so the app asks for it whenever ANY of these is true:
//
//   * this is a CHILD device (or a device that has not yet been told who uses it). A child's device always blocks
//     screenshots. There is no setting for it and none in her app; [ChildScreenShield] sets it and nothing in the child
//     shell can clear it.
//   * the grown-up chose Private for this phone (the default). Their choice is "Screens on this phone" in Settings,
//     under App lock and privacy: Private or Screenshots allowed.
//   * a SENSITIVE screen is showing (PIN and lock screens, the locked health history and moods in About her, the
//     pairing picture and codes). A sensitive screen blocks capture whatever the setting is: [SensitiveScreen].
//   * the app is covered by the PIN screen or the quick-hide page.
//
// The one exception is the developer switch, --dart-define=OLIVE_ALLOW_SCREENSHOTS=true ([kAllowScreenshotsDev] in
// app_lock.dart). A development build then never sets the flag at all, so a tester can see the screens. A store or
// release cut never passes it. This file does not change that switch; it only reads it.
//
// ONLY the grown-up's [AppLockController] ever clears the flag (app_lock.dart). A test reads the library source and
// fails if any other file calls `.set(false)` on the secure-screen channel.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_lock.dart';

/// Whether the window must be marked secure right now. Pure, so the rule is testable without a phone.
bool secureFlagWanted({
  required bool childDevice,
  required bool privateChoice,
  required int sensitiveHolds,
  required bool covered,
  required bool devAllow,
}) =>
    !devAllow && (childDevice || privateChoice || sensitiveHolds > 0 || covered);

/// Sits at the root of every screen a child (or a not-yet-assigned) device can show. Marks the window secure when it
/// first builds and never clears it. A grown-up's phone never builds this: the grown-up shell is a different tree.
class ChildScreenShield extends StatefulWidget {
  const ChildScreenShield({super.key, required this.child, this.secure, this.devAllow = kAllowScreenshotsDev});
  final Widget child;

  /// For a test; the real channel otherwise.
  final SecureScreen? secure;

  /// The developer switch. A test passes it explicitly.
  final bool devAllow;

  @override
  State<ChildScreenShield> createState() => _ChildScreenShieldState();
}

class _ChildScreenShieldState extends State<ChildScreenShield> {
  @override
  void initState() {
    super.initState();
    final bool on = secureFlagWanted(
        childDevice: true, privateChoice: true, sensitiveHolds: 0, covered: false, devAllow: widget.devAllow);
    unawaited((widget.secure ?? SecureScreen()).set(on));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A `MaterialApp.builder` for the roots of the child side and the first-run screens.
Widget childShieldBuilder(BuildContext context, Widget? child) =>
    ChildScreenShield(child: child ?? const SizedBox.shrink());

/// Wraps a screen that must never be captured, whatever "Screens on this phone" says. While it is on screen the app
/// asks for the secure flag; when it goes away the flag goes back to what the grown-up chose. It also tells the
/// "Share this screen" action to stay hidden (see screen_share_ui.dart), so a sensitive screen cannot be shared either.
class SensitiveScreen extends StatefulWidget {
  const SensitiveScreen({super.key, required this.child, this.controller, this.active = true});
  final Widget child;

  /// False for a screen that is only sometimes sensitive (the locked part of About her, the doctor sheet once health
  /// history or moods are on it). The tree does not change when it flips, so nothing typed is lost.
  final bool active;

  /// For a test. By default the app-lock controller above the Navigator.
  final AppLockController? controller;

  @override
  State<SensitiveScreen> createState() => _SensitiveScreenState();
}

class _SensitiveScreenState extends State<SensitiveScreen> {
  VoidCallback? _release;
  AppLockController? _held;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SensitiveScreen old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final AppLockController? c = widget.controller ?? AppLockScope.maybeOf(context);
    if (widget.active && c != null && identical(c, _held) && _release != null) return;
    _release?.call();
    _release = null;
    _held = null;
    if (widget.active && c != null) {
      _held = c;
      _release = c.holdSecure();
    }
  }

  @override
  void dispose() {
    _release?.call();
    _release = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
