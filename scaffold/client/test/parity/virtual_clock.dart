// OLIVE BRANCH — parity harness: the virtual clock. No longer UNVERIFIED — verified by CI
// (client/test/parity/fake_server_test.dart and scenario_parity_test.dart).
//
// The prototype runs on a VIRTUAL clock that starts on Monday 9 Nov 2026, 17:30 in Chicago. The Flutter
// replay does the same, and the clock is DRIVEN BY tester.pump: it reads flutter_test's fake clock
// (`tester.binding.clock`), so `await tester.pump(d)` advances it by exactly `d` and nothing else does.
//
// Her wall clock is the prototype's home zone (America/Chicago). Dart has no zone database in a test, so the
// harness uses a fixed UTC-6 offset (CST, right for the week the scenarios start in); a scenario that jumps
// across the March change would be an hour out, and none of the seven does for a play-window assertion.
import 'package:flutter_test/flutter_test.dart';

class VirtualClock {
  VirtualClock(this._tester, {DateTime? start})
      : _start = start ?? DateTime.utc(2026, 11, 9, 23, 30),
        _fakeStart = _tester.binding.clock.now();

  final WidgetTester _tester;
  final DateTime _start;
  final DateTime _fakeStart;

  /// The virtual instant, UTC.
  DateTime get nowUtc => _start.add(_tester.binding.clock.now().difference(_fakeStart));

  /// Her local wall clock as a plain (non-UTC) DateTime, which is what the stores' `now` callbacks expect.
  DateTime get herLocal {
    final DateTime d = nowUtc.subtract(const Duration(hours: 6));
    return DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second);
  }

  /// Advances the virtual clock by [d] by pumping the tester that long. Long jumps are one pump: with no
  /// periodic timers mounted (the runner unmounts first) FakeAsync elapses them instantly.
  Future<void> advance(Duration d) async {
    if (d <= Duration.zero) return;
    await _tester.pump(d);
  }
}
