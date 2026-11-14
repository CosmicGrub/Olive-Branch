// OLIVE BRANCH — adult safety on THIS device: the app lock, the hidden recents
// preview and the quick-hide cover. No longer UNVERIFIED — verified by CI
// (client/test/app_lock_test.dart). MASTERFILE §8.5.9 (adult safety).
//
// THREE THINGS, all for the grown-up's app only. The child's app never loads
// this file (the child shell is kiosk-locked and has no settings, §8.1).
//
//  1. APP LOCK. When a grown-up leaves the app (Home, another app, screen off) and
//     comes back after the chosen delay, the app is covered by a PIN screen until the
//     device's own guardian PIN (local_pin.dart) is typed. It also asks on a fresh start,
//     because Android may have ended the app while it was away. No PIN set means nothing
//     to ask: the lock is never "on" without one. Delay choices: right away, 1, 5 or 15
//     minutes. The short default (1 minute) lets a photo picker or a permission box open
//     and close without locking the app on its owner.
//  2. HIDE IN RECENT APPS. On Android this sets FLAG_SECURE on the window so the recent
//     apps list shows a blank card instead of the family's screens. Honest cost, said in
//     the settings screen: it also blocks screenshots in this app. Nothing happens on
//     other platforms or where the native side is missing.
//  3. QUICK HIDE. One tap covers everything with a plain notes page. Coming back needs the
//     PIN when one is set. DRAFT CONTENT: the wording and the way back are flagged for
//     the owner's review (see the PR); change them in [kQuickHideNotes] only.
//
// HONEST LIMITS. The lock is a deterrent against someone picking the phone up, not
// against someone with the unlocked phone in hand who is already inside the app, and not
// against someone who knows the PIN. A wrong PIN has the same five-tries, 15-minute pause
// as everywhere else. There is no biometric unlock yet (it needs a native plugin and a
// different Activity base class; left for a later pass).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_pin.dart';
import 'local_services.dart';
import 'local_store.dart';

/// How long a grown-up can be away before the app asks for the PIN again.
enum AppLockDelay {
  immediately(Duration.zero, 'Right away'),
  oneMinute(Duration(minutes: 1), 'After 1 minute'),
  fiveMinutes(Duration(minutes: 5), 'After 5 minutes'),
  fifteenMinutes(Duration(minutes: 15), 'After 15 minutes');

  const AppLockDelay(this.after, this.label);
  final Duration after;
  final String label;
}

class AppLockPrefs {
  const AppLockPrefs({this.lockOnLeave = true, this.delay = AppLockDelay.oneMinute, this.hideRecents = true});
  final bool lockOnLeave;
  final AppLockDelay delay;
  final bool hideRecents;

  AppLockPrefs copyWith({bool? lockOnLeave, AppLockDelay? delay, bool? hideRecents}) => AppLockPrefs(
        lockOnLeave: lockOnLeave ?? this.lockOnLeave,
        delay: delay ?? this.delay,
        hideRecents: hideRecents ?? this.hideRecents,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'v': 1,
        'lock': lockOnLeave,
        'delay': delay.name,
        'recents': hideRecents,
      };

  /// Anything unreadable is the safe default (lock on, hide on), never "off".
  static AppLockPrefs fromJson(Object? raw) {
    if (raw is! Map) return const AppLockPrefs();
    final Object? l = raw['lock'], d = raw['delay'], r = raw['recents'];
    return AppLockPrefs(
      lockOnLeave: l is bool ? l : true,
      delay: AppLockDelay.values.where((AppLockDelay e) => e.name == d).firstOrNull ?? AppLockDelay.oneMinute,
      hideRecents: r is bool ? r : true,
    );
  }
}

abstract class AppLockPrefsRepository {
  Future<AppLockPrefs> load();
  Future<void> save(AppLockPrefs prefs);
}

class MemoryAppLockPrefsRepository implements AppLockPrefsRepository {
  MemoryAppLockPrefsRepository([this._p = const AppLockPrefs()]);
  AppLockPrefs _p;
  @override
  Future<AppLockPrefs> load() async => _p;
  @override
  Future<void> save(AppLockPrefs prefs) async => _p = prefs;
}

/// Kept in the sealed `localpin` area beside the PIN hash, under its own key, so a device
/// wipe removes both and the data catalogue gains no new area.
class LocalStoreAppLockPrefsRepository implements AppLockPrefsRepository {
  LocalStoreAppLockPrefsRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'applock';
  @override
  Future<AppLockPrefs> load() async => AppLockPrefs.fromJson(await _ns.get(_key));
  @override
  Future<void> save(AppLockPrefs prefs) => _ns.put(_key, prefs.toJson());

  static LocalStoreAppLockPrefsRepository over(LocalServices s) =>
      LocalStoreAppLockPrefsRepository(s.area('localpin', ownerId: kLocalGuardianScope));
}

/// The Android side of "hide in recent apps" (MainActivity.kt, channel below).
class SecureScreen {
  SecureScreen([MethodChannel? channel]) : _channel = channel ?? const MethodChannel(kSecureScreenChannel);
  static const String kSecureScreenChannel = 'olive/secure_screen';
  final MethodChannel _channel;

  /// Best effort: a missing native side (tests, other platforms) is not an error.
  Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('set', on);
    } on MissingPluginException {
      // No native side here.
    } on PlatformException {
      // Could not set it; nothing else to do.
    }
  }
}

/// Plain content for the quick-hide cover. DRAFT, for the owner's review.
const String kQuickHideTitle = 'Notes';
const List<String> kQuickHideNotes = <String>[
  'Shopping',
  'Milk, bread, eggs',
  'Batteries',
  'Bin day is Thursday',
  'Call the dentist',
];

class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController({
    required this.pin,
    required this.repo,
    SecureScreen? secure,
    DateTime Function()? now,
    this.observe = true,
  })  : secure = secure ?? SecureScreen(),
        _now = now ?? DateTime.now;

  final LocalPinService pin;
  final AppLockPrefsRepository repo;
  final SecureScreen secure;
  final DateTime Function() _now;
  final bool observe;

  AppLockPrefs _prefs = const AppLockPrefs();
  AppLockPrefs get prefs => _prefs;
  bool _locked = false;
  bool _hidden = false;
  bool _ready = false;
  bool _started = false;
  bool _disposed = false;
  DateTime? _leftAt;

  /// True while the PIN screen must cover the app.
  bool get locked => _locked;

  /// True while the quick-hide cover is up.
  bool get hidden => _hidden;

  /// The app's own screens are not drawn while this is true (not yet loaded counts, so a
  /// fresh start never flashes family screens before the lock is decided).
  bool get covered => _locked || _hidden || !_ready;

  /// Loads the settings, applies them and takes the first-start lock. Safe to await in a test.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (observe) WidgetsBinding.instance.addObserver(this);
    try {
      _prefs = await repo.load();
    } catch (_) {
      _prefs = const AppLockPrefs();
    }
    final bool hasPin = await pin.isSet();
    if (_disposed) return;
    _locked = _prefs.lockOnLeave && hasPin;
    _ready = true;
    unawaited(secure.set(_prefs.hideRecents));
    notifyListeners();
  }

  Future<void> update(AppLockPrefs next) async {
    await repo.save(next);
    _prefs = next;
    unawaited(secure.set(next.hideRecents));
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= _now();
    } else if (state == AppLifecycleState.resumed) {
      final DateTime? left = _leftAt;
      _leftAt = null;
      if (left != null) unawaited(_afterAway(_now().difference(left)));
    }
  }

  Future<void> _afterAway(Duration away) async {
    if (!_prefs.lockOnLeave || away < _prefs.delay.after) return;
    if (!await pin.isSet() || _disposed) return;
    _locked = true;
    notifyListeners();
  }

  /// Covers the app now. Coming back asks for the PIN when one is set.
  void quickHide() {
    _hidden = true;
    notifyListeners();
  }

  /// Checks [code]; on success lifts the PIN cover and the quick-hide cover.
  Future<PinCheck> unlockWith(String code) async {
    final PinCheck c = await pin.verify(code);
    if (c.ok && !_disposed) {
      _locked = false;
      _hidden = false;
      notifyListeners();
    }
    return c;
  }

  /// Leaves quick hide without a PIN, only when no PIN exists on this device.
  Future<bool> leaveQuickHideWithoutPin() async {
    if (await pin.isSet()) return false;
    _hidden = false;
    notifyListeners();
    return true;
  }

  /// Stops watching the app's lifecycle (the guard leaving the tree). [start] can run again.
  void stop() {
    if (observe) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

class AppLockScope extends InheritedNotifier<AppLockController> {
  const AppLockScope({super.key, required AppLockController controller, required super.child})
      : super(notifier: controller);
  static AppLockController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}

/// Sits above the Navigator. Content stays alive underneath (so a lock never loses a
/// half-written form) but is neither drawn nor reachable while covered.
class AppLockGuard extends StatefulWidget {
  const AppLockGuard({super.key, required this.controller, required this.child});
  final AppLockController controller;
  final Widget child;

  @override
  State<AppLockGuard> createState() => _AppLockGuardState();
}

class _AppLockGuardState extends State<AppLockGuard> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.start());
  }

  @override
  void dispose() {
    widget.controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppLockScope(
        controller: widget.controller,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (BuildContext context, Widget? _) {
            final AppLockController c = widget.controller;
            return Stack(textDirection: TextDirection.ltr, children: <Widget>[
              Positioned.fill(
                child: Visibility(visible: !c.covered, maintainState: true, child: widget.child),
              ),
              if (c.hidden)
                Positioned.fill(child: QuickHideCover(controller: c))
              else if (c.locked)
                Positioned.fill(child: AppLockScreen(controller: c)),
            ]);
          },
        ),
      );
}

/// The PIN cover. Plain adult words; no child name, no family detail.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, required this.controller});
  final AppLockController controller;
  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final TextEditingController _c = TextEditingController();
  String? _message;
  bool _working = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) return;
    setState(() => _working = true);
    final PinCheck r = await widget.controller.unlockWith(_c.text);
    if (!mounted) return;
    _c.clear();
    setState(() {
      _working = false;
      _message = switch (r.outcome) {
        PinOutcome.ok => null,
        PinOutcome.locked => kLocalPinLockedMessage,
        PinOutcome.notSet => 'No PIN is set on this device.',
        PinOutcome.wrong => 'That is not your PIN.',
      };
    });
  }

  @override
  Widget build(BuildContext context) => Material(
        key: const Key('appLockScreen'),
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  const Icon(Icons.lock_outline, size: 40),
                  const SizedBox(height: 12),
                  Text('Olive is locked', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text('Enter your PIN to open it.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('appLockPinField'),
                    controller: _c,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                    maxLength: kLocalPinMaxDigits,
                    decoration: const InputDecoration(labelText: 'PIN', counterText: '', border: OutlineInputBorder()),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_message!,
                          key: const Key('appLockMessage'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                      key: const Key('appLockOpen'), onPressed: _working ? null : _submit, child: const Text('Open')),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// A plain notes page. Looks like nothing in particular. A long press on the title is the
/// way back (it asks for the PIN when one is set); no button names Olive.
class QuickHideCover extends StatefulWidget {
  const QuickHideCover({super.key, required this.controller});
  final AppLockController controller;
  @override
  State<QuickHideCover> createState() => _QuickHideCoverState();
}

class _QuickHideCoverState extends State<QuickHideCover> {
  bool _asking = false;

  Future<void> _back() async {
    if (await widget.controller.leaveQuickHideWithoutPin()) return;
    if (mounted) setState(() => _asking = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_asking) return AppLockScreen(controller: widget.controller);
    final ThemeData t = Theme.of(context);
    return Material(
      key: const Key('quickHideCover'),
      color: const Color(0xFFFFFBEF),
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: <Widget>[
          Semantics(
            label: 'Notes. Long press to go back.',
            child: GestureDetector(
              key: const Key('quickHideTitle'),
              behavior: HitTestBehavior.opaque,
              onLongPress: _back,
              child: Text(kQuickHideTitle, style: t.textTheme.headlineMedium?.copyWith(color: const Color(0xFF333333))),
            ),
          ),
          const SizedBox(height: 16),
          for (final String line in kQuickHideNotes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(line, style: t.textTheme.bodyLarge?.copyWith(color: const Color(0xFF333333))),
            ),
        ]),
      ),
    );
  }
}
