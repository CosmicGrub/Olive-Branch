// OLIVE BRANCH — read-aloud for the child's screens: the controller, the scope
// and the two affordances (a speaker button, and long-press on a tile). No
// longer UNVERIFIED — verified by CI (client/test/read_aloud_test.dart).
// MASTERFILE §8.8.5, §8.4, §8.13.
//
// ON-DEVICE, NEVER AUTONOMOUS, NEVER LOGGED. The engine behind this is
// tts_channel.dart (the OS's own offline synthesizer). This file has no plugin
// import and no network client: it is the policy around that engine.
//
//   * Speech starts only from a tap or a long-press. [ReadAloudController.speak]
//     runs every request through a11y_speech.dart's admitSpeech(), which refuses
//     SpeechTrigger.autonomous unconditionally; there is no switch that lets it
//     through, and nothing in this file ever passes it.
//   * Speech stops when the screen goes: a speaker button stops its own reading
//     when it is removed from the tree or its text changes (a story page turns),
//     and [ReadAloudRouteObserver] stops it on any route change.
//   * When there is no engine, or it fails, the speaker goes quiet: the icon
//     changes to a muted one and nothing else happens. No error string is ever
//     shown to the child, and the text she asked to hear is never logged.
//   * The guardian's "read aloud everywhere" switch (access_settings.dart)
//     removes the affordances entirely when off.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'a11y_speech.dart';
import 'access_scope.dart';

/// What actually makes sound. tts_channel.dart's TtsChannel implements this;
/// tests use a fake.
abstract class ReadAloudEngine {
  Future<void> speak(String text);
  Future<void> stop();
}

class ReadAloudController extends ChangeNotifier {
  ReadAloudController({ReadAloudEngine? engine}) {
    _engine = engine;
  }

  ReadAloudEngine? _engine;
  bool _failed = false;
  Object? _owner;

  /// Swaps the engine (the app installs the real one at boot).
  set engine(ReadAloudEngine? e) {
    _engine = e;
    _failed = false;
    notifyListeners();
  }

  /// False when there is no engine or the last attempt failed. The speaker
  /// shows a quiet icon; nothing else changes.
  bool get available => _engine != null && !_failed;

  /// Who is speaking right now (an opaque token), or null.
  Object? get speakingOwner => _owner;
  bool isSpeaking(Object owner) => identical(_owner, owner);

  /// Speaks [text]. Returns whether speech was started. Never throws: a refused
  /// trigger, a missing engine and an engine failure all return false quietly.
  Future<bool> speak(String text, {Object? owner, SpeechTrigger trigger = SpeechTrigger.tap}) async {
    if (admitSpeech(trigger) != null) return false;
    final ReadAloudEngine? e = _engine;
    if (e == null || text.trim().isEmpty) return false;
    _owner = owner ?? this;
    notifyListeners();
    try {
      await e.speak(text);
      return true;
    } catch (_) {
      _failed = true;
      _owner = null;
      notifyListeners();
      return false;
    }
  }

  /// A widget leaving the tree calls release() while the framework is mid-build,
  /// when listeners cannot be told synchronously; tell them after the frame.
  void _notifySafely() {
    final SchedulerBinding b = SchedulerBinding.instance;
    if (b.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      b.addPostFrameCallback((Duration _) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final bool was = _owner != null;
    _owner = null;
    if (was) _notifySafely();
    try {
      await _engine?.stop();
    } catch (_) {
      // Stopping something that is already quiet is not worth a word.
    }
  }

  /// Stops only if [owner] is the one speaking (a widget leaving the tree must
  /// not cut off someone else's reading).
  Future<void> release(Object owner) async {
    if (identical(_owner, owner)) await stop();
  }
}

/// Makes a controller available below it, and with it the guardian's switch.
class ReadAloudScope extends InheritedNotifier<ReadAloudController> {
  const ReadAloudScope({super.key, required ReadAloudController controller, required super.child})
      : super(notifier: controller);

  /// The controller when a scope exists, regardless of the guardian's switch.
  static ReadAloudController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReadAloudScope>()?.notifier;

  /// The controller only when read-aloud is ON for her: a scope exists and the
  /// guardian's setting (or, with no choice, her age) says yes. Null otherwise,
  /// which is how every affordance disappears when it is off.
  static ReadAloudController? enabledOf(BuildContext context) {
    final ReadAloudController? c = maybeOf(context);
    if (c == null) return null;
    final bool on = AccessScope.of(context).readAloudFor(AccessScope.ageOf(context));
    return on ? c : null;
  }

  /// Like [speakFnOf] but null unless read-aloud is ON for her (guardian switch / age): what a
  /// child screen's optional `speak` seam falls back to, so it shows no speaker when it is off.
  static Future<void> Function(String)? speakFnIfEnabled(BuildContext context) {
    final ReadAloudController? c = enabledOf(context);
    if (c == null) return null;
    return (String text) async {
      await c.speak(text);
    };
  }

  /// A `speak` callback in the shape the older screens take (call knock,
  /// emergency card, handover notes), or null with no scope. Explicit taps on
  /// those screens do not depend on the "everywhere" switch.
  static Future<void> Function(String)? speakFnOf(BuildContext context) {
    final ReadAloudController? c = maybeOf(context);
    if (c == null) return null;
    return (String text) async {
      await c.speak(text);
    };
  }
}

/// Stops speech on any route change: a screen opening or closing is the end of
/// whatever was being read.
class ReadAloudRouteObserver extends NavigatorObserver {
  ReadAloudRouteObserver(this.controller);
  final ReadAloudController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => controller.stop();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => controller.stop();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => controller.stop();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => controller.stop();
}

/// A small speaker for [text]. At least 48dp to touch, drawn quietly (no fill,
/// the muted text colour) so it never competes with what it sits beside. Renders
/// nothing when read-aloud is off for her or there is no scope.
class SpeakerButton extends StatefulWidget {
  const SpeakerButton({super.key, required this.text, this.size = 48, this.label = 'Read this out loud'});
  final String text;
  final double size;

  /// What a screen reader calls it.
  final String label;

  @override
  State<SpeakerButton> createState() => _SpeakerButtonState();
}

class _SpeakerButtonState extends State<SpeakerButton> {
  ReadAloudController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = ReadAloudScope.maybeOf(context);
  }

  @override
  void didUpdateWidget(SpeakerButton old) {
    super.didUpdateWidget(old);
    // A story page turned: the old page's reading ends with it.
    if (old.text != widget.text) _c?.release(this);
  }

  @override
  void dispose() {
    _c?.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ReadAloudController? c = ReadAloudScope.enabledOf(context);
    if (c == null) return const SizedBox.shrink();
    final double side = widget.size < 48 ? 48 : widget.size;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, Widget? _) {
        final bool speaking = c.isSpeaking(this);
        final bool available = c.available;
        final IconData icon = !available
            ? Icons.volume_off_outlined
            : speaking
                ? Icons.stop_circle_outlined
                : Icons.volume_up_outlined;
        return Semantics(
          container: true,
          button: true,
          label: available ? (speaking ? 'Stop reading' : widget.label) : 'Reading out loud is not available here',
          excludeSemantics: true,
          onTap: () => _toggle(c, speaking),
          child: SizedBox(
            width: side, height: side,
            child: InkResponse(
              key: const Key('speakerButton'),
              radius: side / 2,
              onTap: () => _toggle(c, speaking),
              child: Center(child: Icon(icon, size: 24,
                  color: available ? scheme.onSurfaceVariant : scheme.outline)),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggle(ReadAloudController c, bool speaking) async {
    if (speaking) {
      await c.stop();
    } else {
      await c.speak(widget.text, owner: this);
    }
  }
}

/// Long-press to hear [text], for a control that already owns its tap (a tile).
/// A tap-gated, user-initiated path like the speaker button: it calls speak()
/// with SpeechTrigger.tap and nothing else.
Future<bool> speakOnLongPress(BuildContext context, String text, {Object? owner}) async {
  final ReadAloudController? c = ReadAloudScope.enabledOf(context);
  if (c == null) return false;
  return c.speak(text, owner: owner);
}
