// OLIVE BRANCH — 'your home grows': what happens to her home on a birthday. No longer UNVERIFIED —
// verified by CI (client/test/child_home_growth_test.dart). Prototype: mod-child.js growCheck / GROW /
// kid.growLater / kid.birthday; parity scenario `birthday`.
//
// THE RULES (all from the prototype):
//   - Her age moves by itself at LOCAL MIDNIGHT on her birthday ([ageAtLocalDay]); never past 17 here (the
//     18 handover is wave 2b). A Feb 29 birthday falls on Mar 1 in a common year, as birthdayInfo does.
//   - When the age she is SHOWN crosses one of [kGrowKeys] (5, 8, 10, 13..18), a 'your home grows' page is
//     READY. When the crossing also changes her band the page is a 'band' page, otherwise a 'rung' page.
//     Several keys crossed at once: the band key wins, else the last one.
//   - The page is shown INSTEAD of her home until she taps the button (seen) or Not now (later). A 'later'
//     page leaves a quiet 'Your home grew' row on every home; tapping it opens the page again.
//   - The page is information. No badge, no count, no confetti, no reward (P1-P11): [ChildGrowth] holds no
//     number a child could see except the age on the page's own eyebrow.
//   - A held band keeps the old home: the shown age follows the band the guardian holds, never ahead of it.
//   - Nothing here needs a server. State is kept on this device ([GrowthRepository]).
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'child_home_bands.dart';
import 'local_store.dart';

/// The prototype's bandOf: 3-4, 5-7, 8-12, 13-17 (and over).
String protoBandOfAge(int a) => a <= 4 ? 't34' : a <= 7 ? 't57' : a <= 12 ? 't812' : 't1317';

/// The oldest age the home understands as a child's band; the 18 handover is wave 2b.
const int kMaxHomeAge = 17;

/// Her age on [today] (a local date), given her age on [lastDay] and her birthday's month and day. One year is
/// added for every birthday that fell after [lastDay] up to and including [today], never past [kMaxHomeAge], never going back.
int ageAtLocalDay({required int age, required int month, required int day, required DateTime lastDay, required DateTime today}) {
  final DateTime from = DateTime(lastDay.year, lastDay.month, lastDay.day);
  final DateTime to = DateTime(today.year, today.month, today.day);
  int a = age;
  for (int y = from.year; y <= to.year; y++) {
    final DateTime b = birthdayOnYear(y, month, day);
    if (b.isAfter(from) && !b.isAfter(to) && a < kMaxHomeAge) a++;
  }
  return a;
}

/// Her birthday in [year]; Feb 29 is Mar 1 in a common year (the same rule as birthdayInfo).
DateTime birthdayOnYear(int year, int month, int day) {
  final bool leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  if (month == 2 && day == 29 && !leap) return DateTime(year, 3, 1);
  return DateTime(year, month, day);
}

/// The time from [now] to the next local midnight.
Duration untilLocalMidnight(DateTime now) => DateTime(now.year, now.month, now.day + 1).difference(now);

enum GrowState { ready, seen, later }

class GrowthMark {
  const GrowthMark({required this.from, required this.to, required this.key, required this.kind, required this.state});
  final int from;
  final int to;
  final int key;

  /// 'band' (her band changed) or 'rung' (a step inside her band).
  final String kind;
  final GrowState state;

  GrowthMark withState(GrowState s) => GrowthMark(from: from, to: to, key: key, kind: kind, state: s);

  Map<String, Object?> toJson() => <String, Object?>{'from': from, 'to': to, 'key': key, 'kind': kind, 'state': state.name};

  static GrowthMark? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? from = j['from'], to = j['to'], key = j['key'], kind = j['kind'], state = j['state'];
    if (from is! int || to is! int || key is! int || (kind != 'band' && kind != 'rung') || state is! String) return null;
    final GrowState? s = GrowState.values.where((GrowState x) => x.name == state).firstOrNull;
    if (s == null || !kGrowPages.containsKey(key)) return null;
    return GrowthMark(from: from, to: to, key: key, kind: kind as String, state: s);
  }
}

/// growCheck(prev, age): the page her crossing earns, or null when it crosses no key.
GrowthMark? growCheck(int prev, int age) {
  final List<int> cross = kGrowKeys.where((int x) => x > prev && x <= age).toList();
  if (cross.isEmpty) return null;
  final List<int> bandC = cross.where((int x) => protoBandOfAge(x) != protoBandOfAge(x - 1)).toList();
  final int key = bandC.isNotEmpty ? bandC.last : cross.last;
  return GrowthMark(from: prev, to: age, key: key, kind: bandC.isNotEmpty ? 'band' : 'rung', state: GrowState.ready);
}

abstract class GrowthRepository {
  Future<({int? shownAge, GrowthMark? mark})> load();
  Future<void> save({required int? shownAge, required GrowthMark? mark});
}

class MemoryGrowthRepository implements GrowthRepository {
  int? _age;
  GrowthMark? _mark;
  @override
  Future<({int? shownAge, GrowthMark? mark})> load() async => (shownAge: _age, mark: _mark);
  @override
  Future<void> save({required int? shownAge, required GrowthMark? mark}) async {
    _age = shownAge;
    _mark = mark;
  }
}

/// On this device, in the child's own 'homegrowth' area. A damaged or unreadable file reads as nothing.
class LocalGrowthRepository implements GrowthRepository {
  LocalGrowthRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'growth';

  @override
  Future<({int? shownAge, GrowthMark? mark})> load() async {
    try {
      final Object? raw = await _ns.get(_key);
      if (raw is! Map) return (shownAge: null, mark: null);
      final Object? a = raw['shownAge'];
      return (shownAge: a is int ? a : null, mark: GrowthMark.fromJson(raw['mark']));
    } catch (_) {
      return (shownAge: null, mark: null);
    }
  }

  @override
  Future<void> save({required int? shownAge, required GrowthMark? mark}) async {
    try {
      await _ns.put(_key, <String, Object?>{'shownAge': shownAge, 'mark': mark?.toJson()});
    } catch (_) {
      // A failed save is never shown to her; the page simply shows again next time.
    }
  }
}

/// The state behind the grow page and the Later card. A listenable the home rebuilds from.
class ChildGrowth extends ChangeNotifier {
  ChildGrowth({GrowthRepository? repository}) : _repo = repository ?? MemoryGrowthRepository();
  final GrowthRepository _repo;

  int? _shownAge;
  GrowthMark? _mark;
  bool _loaded = false;
  Future<void>? _loading;

  int? get shownAge => _shownAge;
  GrowthMark? get mark => _mark;

  /// The page to show instead of her home, or null.
  GrowthMark? get pageReady => _mark != null && _mark!.state == GrowState.ready ? _mark : null;

  /// The 'Your home grew' row is on her home.
  bool get laterCard => _mark != null && _mark!.state == GrowState.later;

  Future<void> _ensureLoaded() => _loading ??= () async {
        final ({int? shownAge, GrowthMark? mark}) s = await _repo.load();
        _shownAge = s.shownAge;
        _mark = s.mark;
        _loaded = true;
      }();

  /// Tells it which age her home shows now. The first time it only remembers the age (no page for an age she
  /// started at); after that, a rise across a key readies a page and a fall (a guardian's correction) clears it.
  Future<void> observe(int age) async {
    await _ensureLoaded();
    if (!_loaded) return;
    final int? was = _shownAge;
    if (was == null) {
      _shownAge = age;
    } else if (age > was) {
      _mark = growCheck(was, age) ?? _mark;
      _shownAge = age;
    } else if (age < was) {
      _mark = null;
      _shownAge = age;
    } else {
      return;
    }
    await _repo.save(shownAge: _shownAge, mark: _mark);
    notifyListeners();
  }

  /// 'Show me': she has seen it.
  Future<void> markSeen() => _set(GrowState.seen);

  /// 'Not now': the page goes away and a quiet row stays on her home.
  Future<void> markLater() => _set(GrowState.later);

  /// The 'Your home grew' row was tapped: the page is ready again.
  Future<void> reopen() => _set(GrowState.ready);

  /// A page for her current age on demand (the prototype's kid.birthday force); a no-op for ages with none.
  Future<void> showFor(int age) async {
    await _ensureLoaded();
    int? key;
    for (final int k in kGrowKeys.reversed) {
      if (age >= k) {
        key = k;
        break;
      }
    }
    _mark = GrowthMark(from: age - 1, to: age, key: key ?? 5, kind: 'band', state: GrowState.ready);
    _shownAge = age;
    await _repo.save(shownAge: _shownAge, mark: _mark);
    notifyListeners();
  }

  Future<void> _set(GrowState s) async {
    await _ensureLoaded();
    final GrowthMark? m = _mark;
    if (m == null) return;
    _mark = m.withState(s);
    await _repo.save(shownAge: _shownAge, mark: _mark);
    notifyListeners();
  }
}
