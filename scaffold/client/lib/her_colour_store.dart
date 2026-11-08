// OLIVE BRANCH — her colour: where the screens get colour of the day, the art
// style and the play window from. No longer UNVERIFIED — verified by CI (a
// Flutter toolchain runs for real in tools/verify.sh's automated pipeline).
// MASTERFILE §8.6.5, §8.6.6.
//
// LOCAL-FIRST. Nothing in this file touches a network. State sits behind two
// narrow interfaces; the implementation today is [MemoryColourStore], which is
// in-process (it survives navigation, not an app restart). A durable on-device
// store (client/lib's LocalStore) is being built separately and will implement
// the same two interfaces; the screens do not change when it is swapped in.
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
  const PlayWindowInfo({required this.window, required this.state, this.line});
  final PlayWindow? window;
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
    return PlayWindowInfo(window: _window, state: s, line: playWindowLine(s));
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
}

/// One store for the whole process, so the child’s shell and the guardian’s
/// shell in the same build see the same colour. Replaced by the durable on-device
/// store behind the same two interfaces when that lands; nothing else changes.
final MemoryColourStore sharedColourStore = MemoryColourStore();
