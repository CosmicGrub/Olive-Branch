// OLIVE BRANCH — where the guided first run keeps its place. MASTERFILE §8.5.13, §8.16.4 (`device.guidedtour`).
//
// What is kept: the script version this install last saw, the grown-up half's step and whether it is done, the parts
// left "for later" (names only), and her half's state. NEVER a name, an age, a PIN or any answer: those are saved by
// the existing first-run steps, and only when they already were. A write that fails never traps anyone: the caller
// carries on for this run (see [GuidedProgressStore.save]).
import 'local_store.dart';

/// Her half, on her tablet.
enum ChildWelcomeState {
  /// Never offered (an install that paired before the welcome existed, or a phone).
  none,

  /// A grown-up paired this tablet just now: the welcome may be started, by a grown-up, at the tablet.
  offered,
  inProgress,

  /// Finished, or a grown-up chose "Go to my home". Not offered again unless a grown-up asks.
  done,
}

class GuidedProgress {
  const GuidedProgress({
    this.seenVersion = 0,
    this.adultStep,
    this.adultDone = false,
    this.deferred = const <String>[],
    this.child = ChildWelcomeState.none,
    this.childStep,
  });

  /// The script version this install has seen (0 = none yet).
  final int seenVersion;
  final String? adultStep;
  final bool adultDone;

  /// Phase names (for example `tablet`) a grown-up chose "Do this later" on.
  final List<String> deferred;
  final ChildWelcomeState child;
  final String? childStep;

  /// True when this install has a record at all. An install with none (every install made before the guided first
  /// run) is never shown it.
  bool get exists => seenVersion > 0 || adultStep != null || adultDone || child != ChildWelcomeState.none;

  GuidedProgress copyWith({
    int? seenVersion,
    Object? adultStep = _keep,
    bool? adultDone,
    List<String>? deferred,
    ChildWelcomeState? child,
    Object? childStep = _keep,
  }) =>
      GuidedProgress(
        seenVersion: seenVersion ?? this.seenVersion,
        adultStep: identical(adultStep, _keep) ? this.adultStep : adultStep as String?,
        adultDone: adultDone ?? this.adultDone,
        deferred: deferred ?? this.deferred,
        child: child ?? this.child,
        childStep: identical(childStep, _keep) ? this.childStep : childStep as String?,
      );

  static const Object _keep = Object();

  Map<String, Object?> toJson() => <String, Object?>{
        'v': 1,
        'seen': seenVersion,
        'aStep': adultStep,
        'aDone': adultDone,
        'later': deferred,
        'child': child.name,
        'cStep': childStep,
      };

  /// Reads a stored document; anything unreadable is "no record" (the safe answer: nothing is shown).
  static GuidedProgress fromJson(Object? raw) {
    if (raw is! Map) return const GuidedProgress();
    final Object? seen = raw['seen'];
    final Object? later = raw['later'];
    final String childWord = raw['child'] is String ? raw['child'] as String : 'none';
    return GuidedProgress(
      seenVersion: seen is int && seen >= 0 && seen < 100000 ? seen : 0,
      adultStep: raw['aStep'] is String && (raw['aStep'] as String).length <= 64 ? raw['aStep'] as String : null,
      adultDone: raw['aDone'] == true,
      deferred: later is List
          ? <String>[for (final Object? s in later) if (s is String && s.length <= 32) s].take(16).toList()
          : const <String>[],
      child: ChildWelcomeState.values.firstWhere((ChildWelcomeState s) => s.name == childWord,
          orElse: () => ChildWelcomeState.none),
      childStep: raw['cStep'] is String && (raw['cStep'] as String).length <= 64 ? raw['cStep'] as String : null,
    );
  }
}

abstract class GuidedProgressStore {
  Future<GuidedProgress> load();

  /// Never throws: a store that cannot be written is held for this run only.
  Future<void> save(GuidedProgress p);
}

class MemoryGuidedProgressStore implements GuidedProgressStore {
  MemoryGuidedProgressStore([GuidedProgress? initial]) : _p = initial ?? const GuidedProgress();
  GuidedProgress _p;
  bool failWrites = false;
  @override
  Future<GuidedProgress> load() async => _p;
  @override
  Future<void> save(GuidedProgress p) async {
    if (failWrites) return;
    _p = p;
  }
}

class LocalGuidedProgressStore implements GuidedProgressStore {
  LocalGuidedProgressStore(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'progress';
  GuidedProgress? _held;

  @override
  Future<GuidedProgress> load() async {
    if (_held != null) return _held!;
    try {
      return GuidedProgress.fromJson(await _ns.get(_key));
    } catch (_) {
      return const GuidedProgress();
    }
  }

  @override
  Future<void> save(GuidedProgress p) async {
    _held = p;
    try {
      await _ns.put(_key, p.toJson());
    } catch (_) {
      // Held for this run only; never reported, never a trap.
    }
  }
}
