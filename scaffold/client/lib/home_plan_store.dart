// OLIVE BRANCH — the grown-up's plan for her home: the daily time total and the
// per-age planner choices. No longer UNVERIFIED — verified by CI
// (client/test/home_plan_store_test.dart). MASTERFILE §8.1, §8.6.6.
//
// LOCAL-FIRST. A handful of choices a guardian made, kept on this device in
// LocalStore (area `plan`, namespaced per child, not encrypted: nothing here is
// private to her, and nothing is about what she did). Same shape as
// access_settings.dart: an abstract repository, an in-memory implementation for
// tests and the preview, and the LocalStore one for the app.
//
// What is deliberately NOT here: a child-side reader that counts anything (P2).
// The daily total is a ceiling a grown-up chose, never a tally of what she used;
// no part of this file records minutes, sessions or streaks. And nothing is sent:
// "tell the other guardian" waits for the network (the screens say so).
import 'package:flutter/foundation.dart';

import 'local_services.dart';
import 'local_store.dart';

/// The ages the planner is built around: the band starts after the first (3 to 4).
const List<int> plannerAges = <int>[5, 8, 13];

/// The band ids those ages open (family_structure_logic.dart's [ageBands]).
const Map<int, String> plannerBandOfAge = <int, String>{5: 't57', 8: 't812', 13: 't13'};

/// The daily-time choices in hours; 0 is off.
const List<int> dailyHourChoices = <int>[0, 1, 2, 3];

@immutable
class HomePlan {
  const HomePlan({
    this.dailyHours = 0,
    this.dailyNote,
    this.holdAt = const <int, bool>{},
    this.remind = const <int, bool>{},
  });

  /// Reading and watching share one daily total across both homes; 0 is off.
  final int dailyHours;

  /// One plain sentence about the last change, for the guardian only
  /// ("You raised this from 1 h to 2 h"). Never shown to her.
  final String? dailyNote;

  /// Per age: her home waits until a grown-up has told her. Absent means the
  /// default, which is to hold (the prototype's default): see [holdWhenArrives].
  final Map<int, bool> holdAt;

  /// Per age: a note to the grown-up a week before. Default off.
  final Map<int, bool> remind;

  static const HomePlan defaults = HomePlan();

  bool holdWhenArrives(int age) => holdAt[age] ?? true;
  bool remindBefore(int age) => remind[age] ?? false;

  HomePlan copyWith({int? dailyHours, String? dailyNote, bool clearNote = false,
      Map<int, bool>? holdAt, Map<int, bool>? remind}) =>
      HomePlan(
        dailyHours: dailyHours ?? this.dailyHours,
        dailyNote: clearNote ? null : (dailyNote ?? this.dailyNote),
        holdAt: holdAt ?? this.holdAt,
        remind: remind ?? this.remind,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'dailyHours': dailyHours,
        if (dailyNote != null) 'dailyNote': dailyNote,
        'holdAt': <String, bool>{for (final MapEntry<int, bool> e in holdAt.entries) '${e.key}': e.value},
        'remind': <String, bool>{for (final MapEntry<int, bool> e in remind.entries) '${e.key}': e.value},
      };

  /// Tolerant: junk falls back to the default rather than failing a screen.
  factory HomePlan.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    Map<int, bool> ages(Object? m) {
      final Map<int, bool> out = <int, bool>{};
      if (m is Map) {
        for (final MapEntry<Object?, Object?> e in m.entries) {
          final int? a = int.tryParse('${e.key}');
          if (a != null && plannerAges.contains(a) && e.value is bool) out[a] = e.value! as bool;
        }
      }
      return out;
    }

    final Object? h = raw['dailyHours'];
    return HomePlan(
      dailyHours: h is int && dailyHourChoices.contains(h) ? h : 0,
      dailyNote: raw['dailyNote'] is String && (raw['dailyNote']! as String).length <= 200 ? raw['dailyNote']! as String : null,
      holdAt: ages(raw['holdAt']),
      remind: ages(raw['remind']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HomePlan &&
      other.dailyHours == dailyHours &&
      other.dailyNote == dailyNote &&
      mapEquals(other.holdAt, holdAt) &&
      mapEquals(other.remind, remind);

  @override
  int get hashCode => Object.hash(dailyHours, dailyNote, Object.hashAll(holdAt.entries.map((e) => '${e.key}${e.value}')),
      Object.hashAll(remind.entries.map((e) => '${e.key}${e.value}')));
}

/// "Off", "1 h", "2 h", "3 h".
String dailyHoursWords(int h) => h == 0 ? 'Off' : '$h h';

/// What a daily-time change says to the guardian who made it. A raise is the
/// one that would be shown to the other guardian once the network exists.
String dailyChangeNote(int from, int to) {
  if (to == from) return '';
  if (to > from) return 'You raised this from ${dailyHoursWords(from)} to ${dailyHoursWords(to)}.';
  return 'You changed this from ${dailyHoursWords(from)} to ${dailyHoursWords(to)}.';
}

abstract class HomePlanRepository {
  Future<HomePlan> load();

  /// Throws if the plan cannot be kept; callers say so and carry on.
  Future<void> save(HomePlan p);
}

class MemoryHomePlanRepository implements HomePlanRepository {
  MemoryHomePlanRepository([HomePlan initial = HomePlan.defaults]) : _p = initial;
  HomePlan _p;
  int saves = 0;
  bool failSaves = false;

  @override
  Future<HomePlan> load() async => _p;

  @override
  Future<void> save(HomePlan p) async {
    if (failSaves) throw const LocalStoreFull('child.test.plan', 0);
    _p = p;
    saves++;
  }
}

/// Durable, on this device, per child (LocalStore area `plan`).
class LocalStoreHomePlanRepository implements HomePlanRepository {
  LocalStoreHomePlanRepository(LocalNamespace ns) : _fixed = ns;

  /// Bound lazily to [LocalServices.current].
  LocalStoreHomePlanRepository.shared([this._childId]) : _fixed = null;

  final LocalNamespace? _fixed;
  String? _childId;

  LocalNamespace get _ns => _fixed ?? LocalServices.current.area('plan', ownerId: _childId);

  static const String _key = 'plan';

  @override
  Future<HomePlan> load() async {
    try {
      return HomePlan.fromJson(await _ns.get(_key));
    } catch (_) {
      return HomePlan.defaults;
    }
  }

  @override
  Future<void> save(HomePlan p) => _ns.put(_key, p.toJson());
}
