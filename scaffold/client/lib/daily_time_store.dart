// OLIVE BRANCH — what today has used, kept on THIS device. No longer UNVERIFIED —
// verified by CI (client/test/daily_time_test.dart). MASTERFILE §8.6.6, §8.16.4.
//
// One small document per child per device (LocalStore area `daytime`): today's date, the seconds
// spent reading and watching, and any minutes a grown-up allowed on top. It holds ONE day:
// the first read on a new local day starts a fresh, empty one, so yesterday is never kept
// and there is no history, streak or total to show anyone (P2). It is never sent anywhere.
//
// Same shape as home_plan_store.dart: an abstract repository, an in-memory one for tests, and
// the LocalStore one for the app.
import 'daily_time_logic.dart';
import 'local_services.dart';
import 'local_store.dart';

abstract class DayUseRepository {
  /// What [today] has used. A document from another day reads as a fresh one for [today].
  Future<DayUse> load(String today);

  /// Throws if it cannot be kept; the caller carries on counting in memory.
  Future<void> save(DayUse use);
}

class MemoryDayUseRepository implements DayUseRepository {
  MemoryDayUseRepository([this._doc]);
  DayUse? _doc;
  int saves = 0;
  bool failSaves = false;

  @override
  Future<DayUse> load(String today) async => (_doc != null && _doc!.day == today) ? _doc! : DayUse(day: today);

  @override
  Future<void> save(DayUse use) async {
    if (failSaves) throw const LocalStoreFull('child.test.daytime', 0);
    _doc = use;
    saves++;
  }
}

/// Durable, on this device, per child (LocalStore area `daytime`).
class LocalStoreDayUseRepository implements DayUseRepository {
  LocalStoreDayUseRepository(LocalNamespace ns) : _fixed = ns;

  /// Bound lazily to [LocalServices.current].
  LocalStoreDayUseRepository.shared([this._childId]) : _fixed = null;

  final LocalNamespace? _fixed;
  String? _childId;

  LocalNamespace get _ns => _fixed ?? LocalServices.current.area('daytime', ownerId: _childId);

  static const String _key = 'today';

  @override
  Future<DayUse> load(String today) async {
    try {
      return DayUse.fromJson(await _ns.get(_key), today);
    } catch (_) {
      return DayUse(day: today);
    }
  }

  @override
  Future<void> save(DayUse use) => _ns.put(_key, use.toJson());
}
