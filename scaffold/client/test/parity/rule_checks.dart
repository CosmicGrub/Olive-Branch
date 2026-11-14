// OLIVE BRANCH — parity harness: the prototype's RULE TABLE against the Flutter rules. No longer
// UNVERIFIED — verified by CI (client/test/parity/rules_parity_test.dart, scenario_parity_test.dart).
//
// scenarios.json `rules` is probed from the prototype by tools/gen-parity-scenarios.mjs (it exercises the
// prototype's own routes and logic). Each check below compares ONE rule with the Flutter side and returns
// implemented (equal), differs (Flutter has the rule and it is not the same: the note says how) or pending
// (Flutter has no such rule yet). Each check also DECLARES the verdict it expects today, so a silent change on
// either side fails rules_parity_test.dart and has to be recorded on purpose. No product code changes here.
//
// Rules that live on the SERVER (the PIN lockout) are checked against the server source the client talks to,
// read as text, because the client has no copy of them.
import 'dart:io';

import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/expiry_digest.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/meds_care.dart';
import 'package:olive_client/offline_outbox.dart';

import 'parity_ledger.dart';
import 'scenario_runner.dart' show Res;

class RuleCheck {
  const RuleCheck(this.id, this.rows, this.declared, this.run);
  final String id;
  final List<String> rows;
  final UnitStatus declared;
  final Future<Res> Function(Map<String, Object?> rules) run;
}

Map<String, Object?> _m(Object? o) => o! as Map<String, Object?>;
String _text(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
bool _libHas(Pattern p) => Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).any((File f) => f.readAsStringSync().contains(p));

const GrownupContact _mom = GrownupContact(id: 'mom', guardianLabel: 'Mom', kind: GrownupKind.mom);
const GrownupContact _dad = GrownupContact(id: 'dad', guardianLabel: 'Dad', kind: GrownupKind.dad);

final List<RuleCheck> ruleChecks = <RuleCheck>[
  RuleCheck('labels.ageRule', <String>['labels.age-defaults'], UnitStatus.differs, (Map<String, Object?> r) async {
    final Map<String, Object?> table = _m(_m(_m(r['labels'])['table']));
    final List<String> bad = <String>[];
    for (final String lock in <String>['unlocked', 'locked']) {
      final Map<String, Object?> t = _m(table[lock]);
      for (int age = 3; age <= 17; age++) {
        final List<Object?> want = t['$age']! as List<Object?>;
        final AgeLockState st = AgeLockState(age: age, locked: lock == 'locked');
        final List<String> got = <String>[ContactLabels.forChild(_mom, age: st), ContactLabels.forChild(_dad, age: st)];
        if (got.join('/') != want.join('/')) bad.add('$lock $age: ${got.join('/')} vs ${want.join('/')}');
      }
    }
    return bad.isEmpty ? const Res.ok() : Res.differs('${bad.length} ages differ: ${bad.take(4).join('; ')} (owner decision open: Mommy/Daddy at 3 and 4)');
  }),
  RuleCheck('labels.nicknameWins', <String>['sub:label rule L.labels.forChild'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final bool ok = ContactLabels.forChild(_mom, age: const AgeLockState(age: 9, locked: true), nicknames: <String, String>{'mom': 'Mama'}) == 'Mama';
    return ok && _m(r['labels'])['nicknameWins'] == true ? const Res.ok() : const Res.differs('a nickname does not win');
  }),
  RuleCheck('labels.guardianView', <String>['sub:labels.forGuardian (\'Ivy calls you Dada\')'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final String got = ContactLabels.forGuardian(_mom, childName: 'Ivy', nicknames: <String, String>{'mom': 'Dada'});
    return got == 'Ivy calls you Dada' ? const Res.ok() : Res.differs('Flutter shows "$got", the prototype "Ivy calls you Dada"');
  }),
  RuleCheck('bands.boundaries', <String>['sub:age bands bandOf'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final Map<String, Object?> first = _m(_m(r['bands'])['firstAgeOfBand']);
    final Map<String, int> flutter = <String, int>{};
    for (int a = 3; a <= 17; a++) {
      flutter.putIfAbsent(bandForYears(a), () => a);
    }
    final Map<String, int> proto = <String, int>{for (final MapEntry<String, Object?> e in first.entries) (e.key == 't1317' ? 't13' : e.key): e.value! as int};
    if (flutter.toString() != proto.toString()) return Res.differs('band starts differ: Flutter $flutter, prototype $proto');
    // The stored id 't13' is the prototype's t1317 (protoBand); the 18 handover is by age, not a fifth band (wave 2b).
    return const Res.ok();
  }),
  RuleCheck('ageLock.pickerRange', <String>['action:ob.kid.pickAge / askLock / lockAge'], UnitStatus.differs, (Map<String, Object?> r) async {
    // LIVE-API.md: the kid picker is 5 to 15; a guardian sets 3 to 17.
    final bool logic = kKidAgeMin == 5 && kKidAgeMax == 15 && kGuardianAgeMin == 3 && kGuardianAgeMax == 17;
    final String screen = _text('lib/onboarding_logic.dart');
    final bool screenRange = RegExp(r'const int minAge = 5, maxAge = 15').hasMatch(screen);
    if (!logic) return const Res.differs('contact_labels.dart age constants differ');
    return screenRange ? const Res.ok() : const Res.differs('the lock logic is 5 to 15 but the onboarding age screen offers 2 to 17 (minAge/maxAge) and does not lock');
  }),
  RuleCheck('ageLock.lockedStaysLocked', <String>['action:ob.kid.pickAge / askLock / lockAge'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final AgeLockState locked = lockKidAge(9);
    final AgeLockState tried = changeAge(locked, 14, guardianPinOk: false);
    final AgeLockState viaPin = changeAge(locked, 14, guardianPinOk: true);
    final bool ok = tried.age == 9 && viaPin.age == 14 && _m(r['session'])['lockedAgeNeverOverwritten'] == true;
    return ok ? const Res.ok() : const Res.differs('a locked age changed without the PIN');
  }),
  RuleCheck('pin.lockoutThresholds', <String>['sub:PIN rate limit (5 wrong)'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final String pool = _text('../packages/db/src/pool.ts');
    final int? tries = int.tryParse(RegExp(r'export const PIN_MAX_ATTEMPTS = (\d+);').firstMatch(pool)?.group(1) ?? '');
    final String ms = RegExp(r'export const PIN_LOCKOUT_MS = ([\d \*]+);').firstMatch(pool)?.group(1) ?? '';
    final int lockMin = ms.split('*').map((String s) => int.parse(s.trim())).fold(1, (int a, int b) => a * b) ~/ 60000;
    final Map<String, Object?> p = _m(r['pinLockout']);
    return tries == p['wrongTriesToLock'] && lockMin == p['lockMinutes']
        ? const Res.ok()
        : Res.differs('server locks after $tries wrong tries for $lockMin min; prototype ${p['wrongTriesToLock']} for ${p['lockMinutes']}');
  }),
  RuleCheck('pin.lockedAnswer', <String>['sub:PIN rate limit (5 wrong)'], UnitStatus.differs, (Map<String, Object?> r) async {
    final String routes = _text('../server/routes.mjs');
    final bool is403 = routes.contains("status: 403, error: 'pin_locked'");
    final Map<String, Object?> fifth = _m((_m(r['pinLockout'])['attempts']! as List<Object?>)[4]);
    return is403 && fifth['status'] == 403 ? const Res.ok() : Res.differs('real server answers 403 pin_locked and pin_incorrect; the prototype answers ${fifth['status']} ${fifth['code']} and invalid_pin');
  }),
  RuleCheck('pairing.codeShape', <String>['sub:pairing-code rules'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final String s = _text('lib/pairing_redeem_screen.dart');
    final bool six = s.contains('maxLength: 6');
    final bool anyDigit = s.contains('FilteringTextInputFormatter.digitsOnly');
    final Map<String, Object?> p = _m(r['pairing']);
    if (!six || p['codeLength'] != 6) return const Res.differs('code length differs');
    // RESOLVED (owner, 2026-11-08): 0-9. The server issues 0-9 (pool.ts generateNumericCode) and the field accepts 0-9;
    // the prototype generator's 1-9 is a prototype simplification, not the rule.
    return anyDigit ? const Res.ok() : const Res.differs('the code field no longer accepts digits');
  }),
  RuleCheck('messages.watchedMeansPlayedThrough', <String>['rule:watched-played-through'], UnitStatus.pending, (Map<String, Object?> r) async {
    final bool built = _libHas('not_played_through') || _libHas('playedThrough');
    return built ? const Res.differs('a played-through rule now exists: record it') : const Res.pending('no played-through logic in lib/: inbox_screen.dart marks watched on open');
  }),
  RuleCheck('messages.retryCadence', <String>['rule:delivery-worker'], UnitStatus.differs, (Map<String, Object?> r) async {
    final Map<String, Object?> c = _m(r['retryCadence']);
    final int firstMin = backoffMs(0) ~/ 60000;
    final String note = 'Flutter outbox backs off ${firstMin}min doubling to 6h; the prototype retries after ${c['firstRetryAfterMinutes']}min then every ${c['laterRetryAfterMinutes']}min';
    return maxAttempts == c['maxAttempts'] && firstMin == c['firstRetryAfterMinutes'] && backoffMs(1) ~/ 60000 == c['laterRetryAfterMinutes']
        ? const Res.ok()
        : Res.differs('$note; both give up after $maxAttempts tries: ${maxAttempts == c['maxAttempts']}');
  }),
  RuleCheck('messages.lengthLimits', <String>['msg.gBank.trim'], UnitStatus.pending, (Map<String, Object?> r) async =>
      _libHas('message_too_short') ? const Res.differs('a length rule now exists: record it') : const Res.pending('no 3 second / 10 minute message length rule in lib/')),
  RuleCheck('expiry.fourteenDays', <String>['rule:expiry'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final int days = _m(r['expiry'])['replyKeptDays']! as int;
    return digestLeadDays == days ? const Res.ok() : Res.differs('digest lead is $digestLeadDays days, prototype keeps replies $days');
  }),
  RuleCheck('playWindow.states', <String>['play.window'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final Map<String, Object?> states = _m(_m(r['playWindow'])['states']);
    const PlayWindow w = PlayWindow(opensMin: 7 * 60 + 30, restsMin: 19 * 60 + 30, windDownMin: 15);
    const Map<String, String> name = <String, String>{'open': 'open', 'winding_down': 'winding', 'resting': 'closed'};
    final List<String> bad = <String>[];
    for (final MapEntry<String, Object?> e in states.entries) {
      final List<String> hm = e.key.split(':');
      final String got = name[playWindowState(w, int.parse(hm[0]) * 60 + int.parse(hm[1]))]!;
      if (got != e.value) bad.add('${e.key}: Flutter $got, prototype ${e.value}');
    }
    return bad.isEmpty ? const Res.ok() : Res.differs('wind-down is placed differently from the prototype (rest time first, wind-down AFTER it): ${bad.join('; ')}');
  }),
  RuleCheck('deletion.recoveryWindow', <String>['row:Account/Delete my account'], UnitStatus.pending, (Map<String, Object?> r) async =>
      RegExp(r'6 (to|and) 12 month|six to twelve').hasMatch(_text('lib/deletion_screen.dart'))
          ? const Res.differs('a recovery window is now stated: record it')
          : const Res.pending('deletion_screen.dart states what deletion means but has no 6 to 12 month recovery window')),
  RuleCheck('emergencyCard.staleVersion', <String>['g-emergency/edit-merge'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final EmergencyCardService svc = EmergencyCardService.memory();
    const FamilyPrincipal g = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
    const LocalEmergencyCard a = LocalEmergencyCard(allergies: <String>['peanuts']), b = LocalEmergencyCard(allergies: <String>['eggs']);
    final EcResult first = await svc.save(g, a, expectedVersion: 0, byName: 'Jess');
    final EcResult stale = await svc.save(g, b, expectedVersion: 0, byName: 'Marcus');
    final bool ok = first.ok && !stale.ok && stale.reason == 'stale_version' && _m(r['emergencyCard'])['staleBase'] != null;
    return ok ? const Res.ok() : Res.differs('stale save answered "${stale.reason}"');
  }),
  RuleCheck('medications.noDoubleDose', <String>['g-med/double-dose'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final DoseKey k = doseKey('m1', 'morning', DateTime(2026, 11, 9));
    final RecordDoseResult one = recordDose(<DoseRecord>[], k, administeredAt: DateTime(2026, 11, 9, 8), byUserName: 'Jess', status: DoseStatus.given);
    final RecordDoseResult two = recordDose(<DoseRecord>[one.record!], k, administeredAt: DateTime(2026, 11, 9, 8, 5), byUserName: 'Marcus', status: DoseStatus.given);
    final bool prn = !prnAllowed(<DoseRecord>[one.record!], 'm1', DateTime(2026, 11, 9, 8, 5), (_m(_m(r['medications'])['doubleDose'])['prnGapMinutes']! as int) / 60);
    return one.ok && !two.ok && prn ? const Res.ok() : const Res.differs('a second dose was allowed');
  }),
  RuleCheck('family.limits', <String>['row:Family/Family structure'], UnitStatus.implemented, (Map<String, Object?> r) async {
    final Map<String, Object?> f = _m(r['familyChanges']);
    return maxDateAheadDays == f['maxDateAheadDays'] && maxHomes == f['maxHomes'] ? const Res.ok() : const Res.differs('limits differ');
  }),
  RuleCheck('calls.onlyGuardiansRingOnlyChildKnocks', <String>['rule:knock-only-child'], UnitStatus.pending, (Map<String, Object?> r) async =>
      _libHas("'child_cannot_start_call'") ? const Res.differs('the rule now exists: record it') : const Res.pending('call_knock.dart has the knock; no client-visible refusal code to compare')),
];
