// OLIVE BRANCH — the guided first run's engine: a small state machine over a resolved list of entries.
// MASTERFILE §8.5.13. Pure Dart plus a progress store; no widgets, so every rule is unit-tested.
//
// Slow-walk: nothing here ever advances by itself. Every transition is a method a person's tap calls. Each transition
// writes the step name FIRST and then moves, so a killed app resumes at the right place.
//
// The five controls (script document, "Kinds of step"):
//   next   goes on.             back   goes back one step (never past the first).
//   skip   goes on to the next PART (the next phase; for a tour stop, past the end of the tour). Not offered on a
//          form (the answer is needed) or the end.
//   later  marks the part "for later" and goes on; on a form it is the same as "I need a minute"; not offered at the end.
//   pause  "I need a minute": saves the place and shows a calm card; [resume] comes back to the same step.
import 'package:flutter/foundation.dart';

import 'guided_progress.dart';
import 'guided_script.dart';

class GuidedController extends ChangeNotifier {
  GuidedController({
    required this.half,
    required this.steps,
    required this.store,
    GuidedProgress? progress,
    int startIndex = 0,
    this.mini = false,
  })  : assert(steps.isNotEmpty),
        _progress = progress ?? const GuidedProgress(),
        _index = startIndex.clamp(0, steps.length - 1);

  final GuidedHalf half;
  final List<GuidedEntry> steps;
  final GuidedProgressStore store;

  /// A "What's new" mini-tour: it never changes the first-run progress, only the version last seen.
  final bool mini;
  GuidedProgress _progress;
  int _index;
  bool _paused = false;
  bool _finished = false;

  GuidedProgress get progress => _progress;
  int get index => _index;
  GuidedEntry get current => steps[_index];
  bool get paused => _paused;
  bool get finished => _finished;
  bool get isFirst => _index == 0;
  bool get isLast => _index == steps.length - 1;

  /// Where a relaunch should start: the saved step if it is still in [steps], else the start.
  static int resumeIndex(List<GuidedEntry> steps, String? savedId) {
    if (savedId == null) return 0;
    final int i = steps.indexWhere((GuidedEntry e) => e.id == savedId);
    return i < 0 ? 0 : i;
  }

  bool get canBack => !isFirst;
  bool get canSkip => current.kind != GuidedKind.form && current.kind != GuidedKind.end && !isLast;
  bool get canLater => current.kind != GuidedKind.end && !isLast;

  Future<void> _persist() async {
    final String id = current.id;
    _progress = half == GuidedHalf.adult
        ? _progress.copyWith(adultStep: mini ? _progress.adultStep : id)
        : _progress.copyWith(
            childStep: id, child: _finished ? ChildWelcomeState.done : ChildWelcomeState.inProgress);
    await store.save(_progress);
  }

  Future<void> _go(int i) async {
    _index = i.clamp(0, steps.length - 1);
    _paused = false;
    await _persist();
    notifyListeners();
  }

  Future<void> start() async {
    await _persist();
    notifyListeners();
  }

  Future<void> next() async {
    if (isLast) return finish();
    await _go(_index + 1);
  }

  Future<void> back() async {
    if (canBack) await _go(_index - 1);
  }

  /// The index of the first step after the current PART (a different phase). For a tour stop: past the whole tour.
  int _afterPart() {
    final String p = current.phase;
    if (p.isEmpty) return (_index + 1).clamp(0, steps.length - 1);
    for (int i = _index + 1; i < steps.length; i++) {
      if (steps[i].phase != p) return i;
    }
    return steps.length - 1;
  }

  Future<void> skip() async {
    if (!canSkip) return;
    await _go(_afterPart());
  }

  Future<void> later() async {
    if (!canLater) return;
    if (current.kind == GuidedKind.form) return pause();
    if (half == GuidedHalf.adult && current.phase.isNotEmpty && !_progress.deferred.contains(current.phase)) {
      _progress = _progress.copyWith(deferred: <String>[..._progress.deferred, current.phase]);
    }
    await _go(_afterPart());
  }

  Future<void> pause() async {
    _paused = true;
    await _persist();
    notifyListeners();
  }

  Future<void> resume() async {
    _paused = false;
    notifyListeners();
  }

  Future<void> finish() async {
    _finished = true;
    if (half == GuidedHalf.adult) {
      _progress = _progress.copyWith(adultDone: true, adultStep: mini ? _progress.adultStep : current.id);
    } else {
      _progress = _progress.copyWith(child: ChildWelcomeState.done, childStep: current.id);
    }
    _progress = _progress.copyWith(seenVersion: kGuidedScriptVersion);
    await store.save(_progress);
    notifyListeners();
  }

  /// A part that really got done after "Do this later" is no longer waiting.
  Future<void> partDone(String phase) async {
    if (!_progress.deferred.contains(phase)) return;
    _progress = _progress.copyWith(deferred: <String>[..._progress.deferred.where((String p) => p != phase)]);
    await store.save(_progress);
    notifyListeners();
  }

  /// A grown-up who has had "Later" on a part can see its names on the last screen.
  List<String> get deferredParts => _progress.deferred;
}
