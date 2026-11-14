// OLIVE BRANCH — her colour: where the screens get colour of the day, the art
// style and the play window from. No longer UNVERIFIED — verified by CI (a
// Flutter toolchain runs for real in tools/verify.sh's automated pipeline).
// MASTERFILE §8.6.5, §8.6.6.
//
// LOCAL-FIRST. Nothing in this file touches a network. State sits behind two
// narrow interfaces; the implementation today is [MemoryColourStore], which is
// in-process (it survives navigation, not an app restart). [LocalColourStore]
// (below) is the durable on-device implementation of the same two interfaces,
// over LocalStore; the screens did not change when it was swapped in.
// THE SEAM, in full: every method below is a plain async read or write of one
// small value (today's colour, the art settings, the play window). No method
// takes or returns a socket, a token, a URL or a device id.
//
// Two interfaces, deliberately separate. [ChildColourStore] is everything HER
// device may do: read today's colour, answer the one question, and read how
// drawings should look and when games are open. It has no setter for anything
// else — the child shell has no controls (§8.1) and this type cannot grow one
// by accident. [GuardianColourStore] is the guardian's side: see her colour as
// a fact, set or clear a colour day, choose the art style, set the play
// window.
//
// [MemoryColourStore] runs the REAL rules (colour_day_logic.dart, held to the
// TypeScript module by golden vectors), so the offline build and every widget
// test behave exactly as a durable store will.
import 'colour_day_logic.dart';
import 'local_services.dart';
import 'local_store.dart';
import 'palette_logic.dart';

/// What today's colour is, from her point of view.
class TodayColour {
  const TodayColour({
    required this.localDate, required this.ask,
    this.colourId, this.chosenBy, this.override = false, this.carriedOver = false,
  });

  /// Her home-zone date, this device’s own local date.
  final String localDate;
  /// Null until she has ever answered.
  final String? colourId;
  /// 'child' | 'guardian'
  final String? chosenBy;
  /// A guardian's colour day is in force. Shown as her colour, never as a rule.
  final bool override;
  /// True when this is yesterday's (or older) colour carried into today.
  final bool carriedOver;
  /// Whether the one daily question should be asked now.
  final bool ask;

  Swatch? get swatch => swatchFor(colourId);

}

/// Today's colour as a guardian sees it: a fact in one sentence, nothing more.
class GuardianColourView {
  const GuardianColourView({
    required this.today, required this.dailyQuestion,
    this.line, this.chosenAtLocal, this.devicesAgree = true,
  });
  final TodayColour today;
  final bool dailyQuestion;
  /// One neutral sentence (parentView()). Null if she has never answered.
  final String? line;
  /// 'HH:mm' in her zone, when she chose it today.
  final String? chosenAtLocal;
  /// Her devices all read one row, so this is true by construction.
  final bool devicesAgree;
}

class PlayWindowInfo {
  const PlayWindowInfo({required this.window, required this.state, this.line, this.beforeOpen = false});
  final PlayWindow? window;
  /// True when the games are resting because the window has not opened yet today (so the goodnight
  /// card must not say "back tomorrow"). Never a number: it is only used to pick a calm sentence.
  final bool beforeOpen;
  /// 'open' | 'winding_down' | 'resting' — in HER local time.
  final String state;
  final String? line;

}

class ArtSaveResult {
  const ArtSaveResult.ok(this.settings) : reason = null;
  const ArtSaveResult.err(this.reason) : settings = null;
  bool get ok => reason == null;
  final ArtSettings? settings;
  final String? reason;
}

class WindowSaveResult {
  const WindowSaveResult.ok({required this.lengthened}) : reason = null;
  const WindowSaveResult.err(this.reason) : lengthened = false;
  bool get ok => reason == null;
  final bool lengthened;
  final String? reason;
}

/// Everything her device may do. No other setter exists, by design (§8.1).
abstract class ChildColourStore {
  Future<TodayColour> today();
  /// Her one answer for the day. Returns what stands afterwards — which may be
  /// a guardian's colour day or a later answer from another device.
  Future<TodayColour> answer(String colourId);
  /// How drawings look and which styles she may pick between.
  Future<ArtSettings> artStyle();
  /// When games are open on this device, and the gentle ending.
  Future<PlayWindowInfo> playWindow();
}

abstract class GuardianColourStore {
  Future<GuardianColourView> view();
  Future<TodayColour> setColourDay(String colourId);
  /// Hands the question back to her. Her own answer is never removed.
  Future<bool> clearColourDay();
  Future<ArtSettings> art();
  Future<ArtSaveResult> saveArt(Map<String, dynamic> patch);
  Future<PlayWindowInfo> playWindow();
  Future<WindowSaveResult> savePlayWindow(PlayWindow w);
  /// "Use a play window" switched off: games are open all day again.
  Future<void> clearPlayWindow();
}

// ================================================================= memory ===
/// The real rules, in memory. Used by the offline demo build and by tests.
class MemoryColourStore implements ChildColourStore, GuardianColourStore {
  MemoryColourStore({
    this.ageYears = 7,
    DateTime Function()? now,
    List<DayColour>? days,
    ArtSettings? art,
    PlayWindow? window,
  })  : _now = now ?? DateTime.now,
        _days = [...?days],
        _art = art ?? defaultArtSettings {
    _window = window;
  }

  final int? ageYears;
  final DateTime Function() _now;
  final List<DayColour> _days;
  ArtSettings _art;
  PlayWindow? _window;

  /// Read-only views of what this store holds, so a durable wrapper can write it down.
  List<DayColour> get days => List<DayColour>.unmodifiable(_days);
  ArtSettings get artSettings => _art;
  PlayWindow? get window => _window;

  String get _date {
    final n = _now();
    String p(int v, int w) => v.toString().padLeft(w, '0');
    return '${p(n.year, 4)}-${p(n.month, 2)}-${p(n.day, 2)}';
  }

  int get _minute => _now().hour * 60 + _now().minute;

  TodayColour _todayRow() {
    final d = colourToday(_days, _date);
    return TodayColour(
      localDate: _date, colourId: d?.colourId, chosenBy: d?.chosenBy,
      override: d?.override ?? false, carriedOver: d != null && d.localDate != _date,
      ask: needsQuestion(_days, _date, _art.dailyQuestion));
  }

  DayColour? _rowFor(String date) {
    for (final d in _days) {
      if (d.localDate == date) return d;
    }
    return null;
  }

  void _write(DayColour incoming) {
    final existing = _rowFor(incoming.localDate);
    final r = mergeDay(existing, incoming);
    if (!r.ok || r.kept != 'incoming') return;
    _days.removeWhere((d) => d.localDate == incoming.localDate);
    _days.add(r.row!);
  }

  @override
  Future<TodayColour> today() async => _todayRow();

  @override
  Future<TodayColour> answer(String colourId) async {
    if (_art.dailyQuestion) {
      _write(DayColour(localDate: _date, colourId: colourId, chosenBy: 'child',
        override: false, chosenAtMs: _now().millisecondsSinceEpoch));
    }
    return _todayRow();
  }

  @override
  Future<ArtSettings> artStyle() async => _art;

  @override
  Future<PlayWindowInfo> playWindow() async {
    final s = playWindowState(_window, _minute);
    final w = _window;
    return PlayWindowInfo(
      window: w, state: s, line: playWindowLine(s),
      beforeOpen: w != null && s == 'resting' && _minute < w.opensMin);
  }

  @override
  Future<GuardianColourView> view() async {
    final t = _todayRow();
    final row = _rowFor(_date);
    String? at;
    if (row != null) {
      final d = DateTime.fromMillisecondsSinceEpoch(row.chosenAtMs.toInt());
      at = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return GuardianColourView(
      today: t, dailyQuestion: _art.dailyQuestion,
      line: guardianView(_days, _date)?.line, chosenAtLocal: at);
  }

  @override
  Future<TodayColour> setColourDay(String colourId) async {
    _write(DayColour(localDate: _date, colourId: colourId, chosenBy: 'guardian',
      override: true, chosenAtMs: _now().millisecondsSinceEpoch));
    return _todayRow();
  }

  @override
  Future<bool> clearColourDay() async {
    final row = _rowFor(_date);
    if (row == null || !row.override) return false;
    _days.remove(row);
    return true;
  }

  @override
  Future<ArtSettings> art() async => _art;

  @override
  Future<ArtSaveResult> saveArt(Map<String, dynamic> patch) async {
    final r = mergeArtSettings(_art, patch, ageYears);
    if (!r.ok) return ArtSaveResult.err(r.reason!);
    _art = r.settings!;
    return ArtSaveResult.ok(_art);
  }

  @override
  Future<WindowSaveResult> savePlayWindow(PlayWindow w) async {
    final c = checkPlayWindow(w.toJson());
    if (!c.ok) return WindowSaveResult.err(c.reason!);
    final longer = isLonger(_window, w);
    _window = w;
    return WindowSaveResult.ok(lengthened: longer);
  }

  @override
  Future<void> clearPlayWindow() async {
    _window = null;
  }
}

// ================================================================ durable ===
/// How many days of colour are kept on the device. The rules only need the last
/// colour to carry it over; nothing older is ever shown, so nothing older is kept.
const int keptColourDays = 14;

/// The same real rules as [MemoryColourStore], made durable on this device
/// (LocalStore area `colour`, scoped to the child): her colour days, the art
/// style and the play window survive a restart. Reads and writes go through a
/// [MemoryColourStore] rebuilt from what was stored, so the rules cannot differ;
/// after every write the result is saved. A write that cannot be saved still
/// takes effect for this run (the rules ran) and is retried by the next write.
///
/// Bound lazily to [LocalServices.current] when built with [LocalColourStore.shared]
/// (rebinding if the device/child scope changes), or to one namespace for tests.
class LocalColourStore implements ChildColourStore, GuardianColourStore {
  LocalColourStore(LocalNamespace ns, {this.ageYears, this.now}) : _fixed = ns;
  LocalColourStore.shared({this.ageYears})
      : _fixed = null,
        now = null;

  final LocalNamespace? _fixed;
  final int? ageYears;
  /// Injectable clock for tests.
  final DateTime Function()? now;
  LocalNamespace? _boundTo;
  Future<MemoryColourStore>? _pending;

  Future<MemoryColourStore> _inner() {
    final LocalNamespace ns = _fixed ?? LocalServices.current.area('colour');
    if (_pending == null || !identical(ns, _boundTo)) {
      _boundTo = ns;
      _pending = _load(ns);
    }
    return _pending!;
  }

  Future<MemoryColourStore> _load(LocalNamespace ns) async {
    List<DayColour> days = <DayColour>[];
    ArtSettings? art;
    PlayWindow? window;
    try {
      final Object? d = await ns.get('days');
      if (d is List) {
        for (final Object? o in d) {
          try {
            if (o is Map) days.add(DayColour.fromJson(o));
          } catch (_) {}
        }
      }
      art = ArtSettings.fromJson(await ns.get('art'));
      window = PlayWindow.fromJson(await ns.get('window'));
    } catch (_) {
      days = <DayColour>[]; // unreadable: the store quarantined it; start fresh
    }
    return MemoryColourStore(ageYears: ageYears ?? 7, now: now, days: days, art: art, window: window);
  }

  Future<void> _save(MemoryColourStore m) async {
    final LocalNamespace? ns = _boundTo;
    if (ns == null) return;
    try {
      final List<DayColour> sorted = m.days.toList()
        ..sort((DayColour a, DayColour b) => b.localDate.compareTo(a.localDate));
      await ns.put('days', <Object?>[for (final DayColour d in sorted.take(keptColourDays)) d.toJson()]);
      await ns.put('art', m.artSettings.toJson());
      if (m.window == null) {
        await ns.delete('window');
      } else {
        await ns.put('window', m.window!.toJson());
      }
    } catch (_) {
      // Full or unwritable: this run is unaffected; the next write tries again.
    }
  }

  Future<T> _write<T>(Future<T> Function(MemoryColourStore m) op) async {
    final MemoryColourStore m = await _inner();
    final T r = await op(m);
    await _save(m);
    return r;
  }

  @override
  Future<TodayColour> today() async => (await _inner()).today();
  @override
  Future<TodayColour> answer(String colourId) => _write((MemoryColourStore m) => m.answer(colourId));
  @override
  Future<ArtSettings> artStyle() async => (await _inner()).artStyle();
  @override
  Future<PlayWindowInfo> playWindow() async => (await _inner()).playWindow();
  @override
  Future<GuardianColourView> view() async => (await _inner()).view();
  @override
  Future<TodayColour> setColourDay(String colourId) => _write((MemoryColourStore m) => m.setColourDay(colourId));
  @override
  Future<bool> clearColourDay() => _write((MemoryColourStore m) => m.clearColourDay());
  @override
  Future<ArtSettings> art() async => (await _inner()).art();
  @override
  Future<ArtSaveResult> saveArt(Map<String, dynamic> patch) => _write((MemoryColourStore m) => m.saveArt(patch));
  @override
  Future<WindowSaveResult> savePlayWindow(PlayWindow w) => _write((MemoryColourStore m) => m.savePlayWindow(w));
  @override
  Future<void> clearPlayWindow() => _write((MemoryColourStore m) => m.clearPlayWindow());
}

/// One store for the whole process, so the child’s shell and the guardian’s
/// shell in the same build see the same colour. Durable: it is bound to this
/// device's child in [LocalServices] (in memory in the offline preview and in
/// tests, so there nothing survives a restart).
final LocalColourStore sharedColourStore = LocalColourStore.shared();
