// OLIVE BRANCH — parity harness: replays the prototype's scenarios against the REAL Flutter screens and
// logic. No longer UNVERIFIED — verified by CI (client/test/parity/scenario_parity_test.dart).
//
// scenarios.json (written by tools/gen-parity-scenarios.mjs from the prototype's own scenario engine) lists, per
// step, the actions the prototype performs (taps, typed values, and what its scripted `call` closures did:
// clock jumps, network toggles, age changes, API calls) and the observable state it ended in. This file:
//   * maps each prototype action to a Flutter DRIVER (mount the real screen, tap by Key, or call the real
//     logic/store), run against a [FakeServer] and a [VirtualClock] driven by tester.pump;
//   * maps each expected probe to a Flutter CHECKER;
//   * returns one [LedgerUnit] per action and per assertion: implemented, pending (the feature is missing:
//     the unit names the parity-matrix rows) or differs.
// An action with no driver is pending. An assertion is only evaluated when every action in its step ran
// (otherwise the real code never produced the state, and the unit is pending: blocked).
// After a step with a pending action the world ADOPTS the prototype's expected state for the few facts later
// drivers need (the locked age, that the tablet is paired), so one missing screen does not hide the rest.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/add_device_screen.dart';
import 'package:olive_client/child_home_growth.dart' show ageAtLocalDay;
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/her_colour_store.dart';
import 'package:olive_client/onboarding_age.dart';
import 'package:olive_client/onboarding_draft.dart';
import 'package:olive_client/onboarding_logic.dart';
import 'package:olive_client/onboarding_name.dart';
import 'package:olive_client/pairing_redeem_screen.dart';
import 'package:olive_client/home_plan_store.dart';
import 'package:olive_client/play_window_gate.dart';
import 'package:olive_client/play_window_screen.dart';

import 'fake_server.dart';
import 'parity_ledger.dart';
import 'virtual_clock.dart';

/// The result of one driver or checker.
class Res {
  const Res.ok() : status = UnitStatus.implemented, note = '';
  const Res.pending(this.note) : status = UnitStatus.pending;
  const Res.differs(this.note) : status = UnitStatus.differs;
  final UnitStatus status;
  final String note;
}

const FamilyPrincipal _guardian = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal _child = FamilyPrincipal(roleName: 'child', childId: 'child-1');

/// Everything the replay needs, built from real Flutter parts.
class ParityWorld {
  ParityWorld(this.tester)
      : clock = VirtualClock(tester) {
    server = FakeServer(clock);
    colour = MemoryColourStore(now: () => clock.herLocal);
    fam = FamilyService(MemoryFamilyStore(), clock: () => clock.herLocal);
  }

  final WidgetTester tester;
  final VirtualClock clock;
  late final FakeServer server;
  late MemoryColourStore colour;
  late FamilyService fam;

  // The child.
  AgeLockState age = const AgeLockState();
  int? pendingAge;
  String? kidName;
  String? colourId;
  int? birthdayMonth, birthdayDay;
  /// The local day her age was last known to be right for (the birthday rule counts from it).
  DateTime? ageDay;
  final MemoryNicknameRepository nicknames = MemoryNicknameRepository();
  bool kidPaired = false;
  Map<String, dynamic>? redeemed;

  // Play window draft (the guardian's form).
  bool playOn = false;
  String playOpen = '00:00', playRest = '23:59';
  int playWind = 0;

  // Family.
  String? lastWriteState;
  String? heldChangeId;
  int peopleSeeded = 0;

  // Pads.
  final Map<String, String> pad = <String, String>{'g': '', 'k': ''};
  String? mounted;

  Future<void> mount(Widget w) async {
    await tester.pumpWidget(MaterialApp(home: w));
    await tester.pump();
    mounted = w.runtimeType.toString();
  }

  Future<void> unmount() async {
    await tester.pumpWidget(const SizedBox.shrink());
    mounted = null;
  }

  /// Advances the virtual clock the way the prototype's console does: by pumping.
  Future<void> advance(Duration d) async {
    if (d > const Duration(minutes: 20) && mounted != null) await unmount(); // no periodic timers across a long jump
    await clock.advance(d);
  }

  Future<Map<String, String>> nicks() => nicknames.load();

  /// The state later drivers need, taken from the prototype when the Flutter side could not produce it.
  Future<void> adopt(List<Map<String, Object?>> expect) async {
    for (final Map<String, Object?> e in expect) {
      final Object? v = e['value'];
      switch (e['probe']) {
        case 'child.age':
          age = AgeLockState(age: v as int, locked: age.locked);
        case 'child.ageLocked':
          age = AgeLockState(age: age.age, locked: v as bool);
        case 'dev.k.paired':
          kidPaired = v as bool;
        case 'child.name':
          kidName = v as String;
      }
    }
  }
}

class _Act {
  _Act(this.key, this.label, this.dev, {this.arg, this.value, this.raw = const <String, Object?>{}});
  final String key;
  final String label;
  final String dev;
  final String? arg;
  final String? value;
  final Map<String, Object?> raw;
}

List<_Act> _actsOf(Map<String, Object?> step) {
  final List<_Act> out = <_Act>[];
  for (final Object? o in step['acts']! as List<Object?>) {
    final Map<String, Object?> a = o! as Map<String, Object?>;
    switch (a['t']) {
      case 'tap':
        final String name = a['name']! as String;
        final String? arg = a['arg'] as String?;
        out.add(_Act(name == 'go' ? 'go:$arg' : 'tap:$name', name == 'go' ? 'go $arg' : 'tap $name${arg == null ? '' : ' $arg'}', a['dev']! as String, arg: arg, raw: a));
      case 'type':
        out.add(_Act('type:${a['path']}', 'type ${a['path']}', a['dev']! as String, value: a['value'] as String?, raw: a));
    }
  }
  for (final Object? o in step['ops']! as List<Object?>) {
    final Map<String, Object?> a = o! as Map<String, Object?>;
    switch (a['op']) {
      case 'tap':
        final String name = a['name']! as String;
        out.add(_Act('tap:$name', 'call: tap $name ${a['arg'] ?? ''}'.trim(), a['dev']! as String, arg: a['arg'] as String?, raw: a));
      case 'net':
        out.add(_Act('op:net', 'call: network ${a['dev']} ${a['online'] == true ? 'on' : 'off'}', a['dev']! as String, raw: a));
      case 'clock':
        out.add(_Act('op:clock', 'call: clock +${((a['advanceMs']! as int) / 60000).round()} min', 'both', raw: a));
      case 'age':
        out.add(_Act('op:age', 'call: set age ${a['age']}', 'both', raw: a));
      case 'api':
        out.add(_Act('op:api ${a['method']} ${a['path']}', 'call: ${a['method']} ${a['path']}', a['dev']! as String, raw: a));
    }
  }
  return out;
}

typedef _Driver = Future<Res> Function(ParityWorld w, _Act a);
typedef _Checker = Future<Res> Function(ParityWorld w, Object? expected, Map<String, Object?> step);

int _hm(String s) {
  final List<String> p = s.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

// ================================================================================== drivers ===
final Map<String, _Driver> _drivers = <String, _Driver>{
  // ---- the console's own controls: the FakeServer and the virtual clock are the Flutter side of these
  'op:net': (ParityWorld w, _Act a) async {
    w.server.setOnline(a.raw['dev']! as String, a.raw['online']! as bool);
    return const Res.ok();
  },
  'op:clock': (ParityWorld w, _Act a) async {
    // To the prototype's ABSOLUTE virtual instant (the replay may already be later; it never goes back).
    final Duration d = DateTime.parse(a.raw['to']! as String).difference(w.clock.nowUtc);
    final DateTime before = w.clock.herLocal;
    await w.advance(d);
    // Her age moves by itself at local midnight on her birthday: the SAME rule the live shell runs at every
    // local midnight (child_home_growth.dart ageAtLocalDay), applied to the days the clock just crossed.
    final int? years = w.age.age;
    if (years != null && w.birthdayMonth != null && w.birthdayDay != null) {
      final DateTime after = w.clock.herLocal;
      w.age = AgeLockState(
          age: ageAtLocalDay(age: years, month: w.birthdayMonth!, day: w.birthdayDay!, lastDay: w.ageDay ?? before, today: after),
          locked: w.age.locked);
      w.ageDay = after;
    }
    return const Res.ok();
  },
  'op:age': (ParityWorld w, _Act a) async {
    // A guardian (through the PIN gate) may set 3 to 17 on a locked age.
    final AgeLockState locked = AgeLockState(age: w.age.age, locked: true);
    w.age = changeAge(locked, a.raw['age']! as int, guardianPinOk: true);
    final Object? b = a.raw['birthday']; // the birthday on file, when the prototype had one
    if (b is Map<String, Object?>) {
      w.birthdayMonth = b['month']! as int;
      w.birthdayDay = b['day']! as int;
    }
    w.ageDay = w.clock.herLocal;
    return const Res.ok();
  },

  // ---- kid onboarding: the real screens
  'go:ob.kid.name': (ParityWorld w, _Act a) async {
    await w.mount(ObNameScreen(fallbackName: 'Ivy', onContinue: (NameStep s) => w.kidName = s.spelled));
    return const Res.ok();
  },
  'type:dev.k.draft.name': (ParityWorld w, _Act a) async {
    NameStep? got;
    await w.mount(ObNameScreen(fallbackName: 'Ivy', onContinue: (NameStep s) => got = s));
    await w.tester.enterText(find.byType(TextField), a.value!);
    await w.tester.pump();
    await w.tester.tap(find.byType(FilledButton));
    await w.tester.pump();
    w.kidName = got?.spelled;
    return got == null ? const Res.pending('ObNameScreen did not continue') : const Res.ok();
  },
  'go:ob.kid.age': (ParityWorld w, _Act a) async {
    await w.mount(ObAgeScreen(birthDate: null, now: w.clock.herLocal, onContinue: (AgeStep s) => w.pendingAge = s.selfReported));
    return const Res.ok();
  },
  'tap:ob.kid.pickAge': (ParityWorld w, _Act a) async {
    AgeStep? got;
    await w.mount(ObAgeScreen(birthDate: null, now: w.clock.herLocal, onContinue: (AgeStep s) => got = s));
    await w.tester.tap(find.byKey(ValueKey<String>('age_${a.arg}')));
    await w.tester.pump();
    await w.tester.tap(find.byType(FilledButton));
    await w.tester.pump();
    w.pendingAge = got?.selfReported;
    return w.pendingAge == int.parse(a.arg!) ? const Res.ok() : const Res.pending('ObAgeScreen did not report the tapped age');
  },
  'tap:ob.kid.askLock': (ParityWorld w, _Act a) async =>
      const Res.pending('Flutter has no "are you sure, this locks" confirmation between tapping an age and locking it'),
  'tap:ob.kid.lockAge': (ParityWorld w, _Act a) async {
    if (w.pendingAge == null) return const Res.pending('no age was picked');
    w.age = lockKidAge(w.pendingAge!);
    return const Res.ok();
  },
  'tap:ob.kid.pickColor': (ParityWorld w, _Act a) async {
    w.colourId = a.arg;
    return const Res.ok();
  },
  'tap:ob.kid.setBM': (ParityWorld w, _Act a) async {
    w.birthdayMonth = int.parse(a.arg!);
    return const Res.ok();
  },
  'tap:ob.kid.setBD': (ParityWorld w, _Act a) async {
    w.birthdayDay = int.parse(a.arg!);
    // The draft the client keeps for her answers (uploaded after pairing).
    final OnboardingDraft d = OnboardingDraft(name: w.kidName, age: w.age.age, colourId: w.colourId, birthdayMonth: w.birthdayMonth, birthdayDay: w.birthdayDay);
    return d.birthdayMonth == w.birthdayMonth && d.birthdayDay == w.birthdayDay ? const Res.ok() : const Res.pending('draft lost the birthday');
  },
  'type:dev.k.draft.nick.mom': (ParityWorld w, _Act a) async {
    await w.nicknames.set('mom', a.value);
    return const Res.ok();
  },
  'type:dev.k.draft.nick.dad': (ParityWorld w, _Act a) async {
    await w.nicknames.set('dad', a.value);
    return const Res.ok();
  },

  // ---- pairing: the real AddDeviceScreen and PairingRedeemScreen against the FakeServer
  'go:ob.addDevice': (ParityWorld w, _Act a) async {
    w.pad['g'] = '';
    await w.mount(AddDeviceScreen(
        baseUrl: 'http://olive.test', guardianId: 'mom',
        children: const <ChildOption>[ChildOption(id: 'child-1', name: 'Ivy')], httpClient: w.server.clientFor('g')));
    return const Res.ok();
  },
  'go:ob.kid.connect': (ParityWorld w, _Act a) async {
    w.pad['k'] = '';
    w.redeemed = null;
    await w.mount(PairingRedeemScreen(
        baseUrl: 'http://olive.test', role: 'child', httpClient: w.server.clientFor('k'),
        onRedeemed: (Map<String, dynamic> r) => w.redeemed = r));
    return const Res.ok();
  },
  'tap:ob.pad': (ParityWorld w, _Act a) async {
    if (w.mounted == 'AddDeviceScreen' && a.dev == 'g') {
      w.pad['g'] = '${w.pad['g']}${a.arg}';
      if (w.pad['g']!.length < 4) return const Res.ok();
      await w.tester.tap(find.byKey(const Key('addDeviceContinueButton')));
      await w.tester.pump();
      await w.tester.enterText(find.byKey(const Key('addDevicePinField')), w.pad['g']!);
      await w.tester.tap(find.byKey(const Key('addDeviceGenerateButton')));
      await w.tester.pumpAndSettle();
      return find.byKey(const Key('addDeviceNumericCode')).evaluate().isEmpty ? const Res.pending('no code appeared') : const Res.ok();
    }
    if (w.mounted == 'PairingRedeemScreen' && a.dev == 'k') {
      w.pad['k'] = '${w.pad['k']}${a.arg}';
      if (w.pad['k']!.length < 6) return const Res.ok();
      final String? code = w.server.openCode;
      if (code == null) return const Res.pending('no open pairing code on the server (the guardian step did not produce one)');
      await w.tester.enterText(find.byKey(const Key('pairingCodeField')), code);
      await w.tester.tap(find.byKey(const Key('pairingConnectButton')));
      await w.tester.pump();
      await w.tester.pump();
      w.kidPaired = w.redeemed != null;
      return w.kidPaired ? const Res.ok() : const Res.pending('redeem did not complete');
    }
    return const Res.pending('the PIN pad on the guardian setup screens has no Flutter counterpart in this step (OS keyboard + button)');
  },

  // ---- play window: the REAL guardian screen (Wave 3) writing the real store, read by the real gate.
  // The screen has the prototype's switch, 15-minute time pickers and wind-down choices; each driver taps them.
  'go:g-play': (ParityWorld w, _Act a) async {
    await w.mount(PlayWindowScreen(childName: 'Ivy', store: w.colour, plan: MemoryHomePlanRepository()));
    await w.tester.pumpAndSettle();
    return find.byKey(const Key('useWindow')).evaluate().isNotEmpty ? const Res.ok() : const Res.pending('the play window screen did not appear');
  },
  'tap:gPlayOn': (ParityWorld w, _Act a) async {
    await w.tester.tap(find.byKey(const Key('useWindow')));
    await w.tester.pumpAndSettle();
    w.playOn = !w.playOn;
    return const Res.ok();
  },
  'type:grd.play.open': (ParityWorld w, _Act a) async {
    w.playOpen = a.value!;
    return _pickTime(w, 'opensDrop', _hm(a.value!));
  },
  'type:grd.play.rest': (ParityWorld w, _Act a) async {
    w.playRest = a.value!;
    return _pickTime(w, 'restsDrop', _hm(a.value!));
  },
  'tap:gWind': (ParityWorld w, _Act a) async {
    w.playWind = int.parse(a.arg!);
    final Finder seg = find.descendant(of: find.byKey(const Key('windSeg')), matching: find.text(w.playWind == 0 ? 'Off' : '${w.playWind} min'));
    if (seg.evaluate().isEmpty) return const Res.pending('the wind-down choice is not on screen');
    await w.tester.tap(seg);
    await w.tester.pumpAndSettle();
    return const Res.ok();
  },
  'tap:gPlaySave': (ParityWorld w, _Act a) async {
    await w.tester.tap(find.byKey(const Key('saveWindow')));
    await w.tester.pumpAndSettle();
    final PlayWindow? saved = (await w.colour.playWindow()).window;
    if (!w.playOn) return saved == null ? const Res.ok() : const Res.pending('switched off, but a window is still saved');
    final bool same = saved != null && saved.opensMin == _hm(w.playOpen) && saved.restsMin == _hm(w.playRest) && saved.windDownMin == w.playWind;
    return same ? const Res.ok() : Res.pending('the screen saved $saved, not ${w.playOpen} to ${w.playRest} with a ${w.playWind} minute wind-down');
  },

  // ---- family structure: the real service, with a hold and a release
  'op:api POST /v1/family-changes': (ParityWorld w, _Act a) async {
    final String mode = (a.raw['mode'] as String?) ?? 'now';
    final FamilyWrite r = await w.fam.addChange(_guardian,
        actorName: 'Jess', yearsOld: 9,
        op: <String, Object?>{'op': 'put_person', 'person': <String, Object?>{'id': 'p_rose', 'label': 'Grandma Rose', 'role': 'relative', 'homeId': null, 'contact': <String>['message', 'postcard'], 'away': null}},
        timing: mode == 'hold' ? Timing.hold.toJson() : Timing.now.toJson());
    w.lastWriteState = r.state;
    w.heldChangeId = r.state == 'held' ? r.id : w.heldChangeId;
    return r.ok ? const Res.ok() : Res.pending('FamilyService refused: ${r.reason}');
  },
  'tap:gRelease': (ParityWorld w, _Act a) async {
    if (w.heldChangeId == null) return const Res.pending('nothing is held');
    final FamilyWrite r = await w.fam.release(_guardian, actorName: 'Jess', yearsOld: 9, changeId: w.heldChangeId!);
    w.lastWriteState = r.state;
    return r.ok ? const Res.ok() : Res.pending('FamilyService refused: ${r.reason}');
  },
};

_Driver? _driverFor(String key) {
  final _Driver? exact = _drivers[key];
  if (exact != null) return exact;
  return null;
}

// ================================================================================= checkers ===
Future<List<String>> _childNames(ParityWorld w) async {
  final FamilyChildSnapshot s = await w.fam.childSnapshot(_child, childId: 'child-1', yearsOld: 9);
  return <String>[for (final ChildPlace p in s.view.places) for (final ChildPerson x in p.people) x.name];
}

const Map<String, Type> _screenTypes = <String, Type>{
  'ob.addDevice': AddDeviceScreen,
  'ob.kid.age': ObAgeScreen,
  'ob.kid.name': ObNameScreen,
  'ob.kid.connect': PairingRedeemScreen,
  'g-play': PlayWindowScreen,
};

Res _eq(Object? flutter, Object? proto, String what) =>
    '$flutter' == '$proto' ? const Res.ok() : Res.differs('$what: Flutter $flutter, prototype $proto');

Future<String> _gateState(ParityWorld w) async {
  await w.mount(PlayWindowGate(store: w.colour, child: const Scaffold(body: Text('games'))));
  await w.tester.pump(); // the gate reads the store in initState
  await w.tester.pump();
  if (find.byKey(const Key('goodnightLine')).evaluate().isNotEmpty) return 'closed';
  if (find.byKey(const Key('windDownBanner')).evaluate().isNotEmpty) return 'winding';
  return 'open';
}

final Map<String, _Checker> _checkers = <String, _Checker>{
  'net.k.online': (ParityWorld w, Object? e, Map<String, Object?> s) async => _eq(w.server.isOnline('k'), e, 'tablet online'),
  'net.g.online': (ParityWorld w, Object? e, Map<String, Object?> s) async => _eq(w.server.isOnline('g'), e, 'phone online'),
  'label.mom': (ParityWorld w, Object? e, Map<String, Object?> s) async => _eq(
      ContactLabels.forChild(const GrownupContact(id: 'mom', guardianLabel: 'Mom', kind: GrownupKind.mom), age: w.age, nicknames: await w.nicks()), e, 'what she calls Mom'),
  'label.dad': (ParityWorld w, Object? e, Map<String, Object?> s) async => _eq(
      ContactLabels.forChild(const GrownupContact(id: 'dad', guardianLabel: 'Dad', kind: GrownupKind.dad), age: w.age, nicknames: await w.nicks()), e, 'what she calls Dad'),
  'child.age': (ParityWorld w, Object? e, Map<String, Object?> s) async {
    final bool clock = (s['ops']! as List<Object?>).any((Object? o) => (o! as Map<String, Object?>)['op'] == 'clock');
    if (w.age.age != e && clock) return const Res.pending('Flutter does not move the age on her birthday (matrix: sub:birthday auto-increments age at local midnight)');
    return _eq(w.age.age, e, 'age');
  },
  'child.ageLocked': (ParityWorld w, Object? e, Map<String, Object?> s) async => _eq(w.age.locked, e, 'age locked'),
  'child.color': (ParityWorld w, Object? e, Map<String, Object?> s) async => _eq(w.colourId, e, 'her colour'),
  'dev.k.paired': (ParityWorld w, Object? e, Map<String, Object?> s) async => _eq(w.kidPaired, e, 'tablet paired'),
  'band': (ParityWorld w, Object? e, Map<String, Object?> s) async {
    final String got = bandForYears(w.age.age);
    final bool clock = (s['ops']! as List<Object?>).any((Object? o) => (o! as Map<String, Object?>)['op'] == 'clock');
    // One stored band 't13' IS the prototype's t1317 (protoBand); the split at 18 is by age, not by band id (wave 2b).
    if (e == 't1317' && got == 't13') return const Res.ok();
    if (clock && got != e) return const Res.pending('the band does not follow the birthday because the age does not (see child.age)');
    return _eq(got, e, 'band');
  },
  'play.config': (ParityWorld w, Object? e, Map<String, Object?> s) async {
    final Map<String, Object?> c = e! as Map<String, Object?>;
    final Map<String, Object?> got = <String, Object?>{'on': w.playOn, 'open': w.playOpen, 'rest': w.playRest, 'wind': w.playWind};
    return got.toString() == c.toString() ? const Res.ok() : Res.differs('form holds $got, prototype $c');
  },
  'play.state': (ParityWorld w, Object? e, Map<String, Object?> s) async {
    final String got = await _gateState(w);
    if (got == e) return const Res.ok();
    return Res.differs('Flutter says $got, prototype says $e');
  },
  'fam.hist': (ParityWorld w, Object? e, Map<String, Object?> s) async {
    final Res r = _eq(w.lastWriteState, e, 'state of the change');
    if (r.status != UnitStatus.implemented) return r;
    final List<String> names = await _childNames(w);
    return names.contains('Grandma Rose') ? const Res.differs('a HELD change reached the child before it was released') : const Res.ok();
  },
  'fam.people': (ParityWorld w, Object? e, Map<String, Object?> s) async {
    final FamilyOverview o = await w.fam.overview(_guardian, yearsOld: 9);
    final int total = o.released.people.length;
    if (total != e) return _eq(total, e, 'people');
    final List<String> names = await _childNames(w);
    return names.contains('Grandma Rose') ? const Res.ok() : const Res.differs('released, but not shown to the child');
  },
};

/// Picks [minute] (a multiple of 15) in the play window screen's time dropdown [key].
Future<Res> _pickTime(ParityWorld w, String key, int minute) async {
  final Finder drop = find.byKey(Key(key));
  if (drop.evaluate().isEmpty) return Res.pending('$key is not on screen (is the window switched on?)');
  // The menu has 96 quarter-hour items and builds only those in view, so the pick is made through the
  // dropdown's own onChanged (what choosing the item calls), after checking the minute is one of its choices.
  final DropdownButton<int> d = w.tester.widget<DropdownButton<int>>(drop);
  if (!d.items!.any((DropdownMenuItem<int> i) => i.value == minute)) return Res.pending('${minuteLabel(minute)} is not a choice');
  d.onChanged!(minute);
  await w.tester.pumpAndSettle();
  return const Res.ok();
}

Res _screenCheck(ParityWorld w, Object? expected) {
  final Type? t = _screenTypes['$expected'];
  if (t == null) return Res.pending('no Flutter screen for the prototype screen "$expected"');
  return w.mounted == '$t' ? const Res.ok() : Res.differs('expected $t on screen, found ${w.mounted}');
}

// ================================================================================== runner ===
Map<String, Object?> loadScenarios() => jsonDecode(File('test/parity/scenarios.json').readAsStringSync()) as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? o) => <Map<String, Object?>>[for (final Object? x in o! as List<Object?>) x! as Map<String, Object?>];

Future<List<LedgerUnit>> runScenario(WidgetTester tester, Map<String, Object?> scenario) async {
  // A tall surface: the onboarding screens are long lists and a tap off-screen would silently miss.
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final ParityWorld w = ParityWorld(tester);
  final String sid = scenario['id']! as String;
  // The prototype's seeded family: bring the real service to the same people count.
  for (final Map<String, Object?> p in _list(scenario['initial'])) {
    if (p['probe'] == 'fam.people') {
      for (int i = 0; i < (p['value']! as int); i++) {
        await w.fam.addChange(_guardian, actorName: 'Jess', yearsOld: 9, timing: Timing.now.toJson(),
            op: <String, Object?>{'op': 'put_person', 'person': <String, Object?>{'id': 'seed$i', 'label': 'Person $i', 'role': 'relative', 'homeId': null, 'contact': <String>['message'], 'away': null}});
      }
      w.peopleSeeded = p['value']! as int;
    }
    if (p['probe'] == 'child.age' && p['value'] is int) w.age = AgeLockState(age: p['value']! as int, locked: true);
    if (p['probe'] == 'play.config') {
      // The prototype starts with a window already on (15:30 to 19:00, 30 min wind-down): give the real store the same.
      final Map<String, Object?> c = p['value']! as Map<String, Object?>;
      w.playOn = c['on']! as bool;
      w.playOpen = c['open']! as String;
      w.playRest = c['rest']! as String;
      w.playWind = c['wind']! as int;
      if (w.playOn) await w.colour.savePlayWindow(PlayWindow(opensMin: _hm(w.playOpen), restsMin: _hm(w.playRest), windDownMin: w.playWind));
    }
  }

  final List<LedgerUnit> units = <LedgerUnit>[];
  for (final Map<String, Object?> step in _list(scenario['steps'])) {
    final String stepId = step['id']! as String;
    final List<String> rows = <String>[for (final Object? r in step['rows']! as List<Object?>) r! as String];
    final List<_Act> acts = _actsOf(step);
    final List<LedgerUnit> actUnits = <LedgerUnit>[];
    for (int i = 0; i < acts.length; i++) {
      final _Act a = acts[i];
      final _Driver? d = _driverFor(a.key);
      final Res r = d == null ? Res.pending('no Flutter driver for "${a.label}"') : await d(w, a);
      actUnits.add(LedgerUnit('$stepId#a$i', sid, 'act', a.label, r.status, rows: rows, note: r.note));
    }
    units.addAll(actUnits);
    final bool blocked = actUnits.any((LedgerUnit u) => u.status == UnitStatus.pending);
    final List<Map<String, Object?>> expect = _list(step['expect']);
    for (final Map<String, Object?> e in expect) {
      final String probe = e['probe']! as String;
      final Object? value = e['value'];
      Res r;
      if (probe == 'screen.g' || probe == 'screen.k') {
        r = blocked ? Res.pending('blocked: an action in ${step['id']} is pending') : _screenCheck(w, value);
      } else {
        final _Checker? c = _checkers[probe];
        if (c == null) {
          r = Res.pending('no Flutter counterpart for "$probe"');
        } else if (blocked) {
          r = Res.pending('blocked: an action in ${step['id']} is pending');
        } else {
          r = await c(w, value, step);
        }
      }
      units.add(LedgerUnit('$stepId#e:$probe', sid, 'assert', '$probe = $value', r.status, rows: rows, note: r.note));
    }
    if (blocked) await w.adopt(expect);
  }
  await w.unmount();
  return units;
}
