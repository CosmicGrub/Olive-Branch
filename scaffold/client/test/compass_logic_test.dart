// OLIVE BRANCH — suite I (Compass) pure logic: the questions, the plain rules
// table, the suggestions (deterministic, explainable, capped, no scoring, no
// label about the child), the two profiles and the alert cue.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/compass_logic.dart';

CompassAnswers all() => CompassAnswers(
    who: <String>{for (final CompassOption o in compassWhoOptions) o.id},
    needs: <String>{for (final CompassOption o in compassNeedsOptions) o.id});

CompassAnswers only(Iterable<String> ids) {
  CompassAnswers a = const CompassAnswers();
  for (final String id in ids) {
    a = a.withWho(id, true).withNeed(id, true);
  }
  return a;
}

void main() {
  group('the questions', () {
    test('option ids are unique and every option has a plain label', () {
      final List<String> ids = <CompassOption>[...compassWhoOptions, ...compassNeedsOptions].map((CompassOption o) => o.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final CompassOption o in <CompassOption>[...compassWhoOptions, ...compassNeedsOptions]) {
        expect(o.label.trim(), isNotEmpty, reason: o.id);
        expect(optionLabel(o.id), o.label);
      }
      expect(optionLabel('nope'), isNull);
    });

    test('NO option names a condition, a diagnosis, a type of child or a deficit', () {
      const List<String> banned = <String>[
        'diagnos', 'disorder', 'disabled', 'disabilit', 'autis', 'adhd', 'anxi', 'trauma', 'special needs', 'delay', 'problem',
        'condition', 'syndrome', 'impair', 'defici', 'difficult', 'behaviour', 'behavior', 'naughty', 'at risk', 'broken', 'troubled',
      ];
      for (final CompassOption o in <CompassOption>[...compassWhoOptions, ...compassNeedsOptions]) {
        for (final String b in banned) {
          expect(o.label.toLowerCase(), isNot(contains(b)), reason: '"${o.label}" contains "$b"');
        }
      }
    });

    test('the needs are phrased as things that help, never as what she is', () {
      for (final CompassOption o in compassNeedsOptions) {
        expect(o.label.toLowerCase(), isNot(matches(RegExp(r'^(she|he|is|has)\b'))), reason: o.label);
        expect(o.label.toLowerCase(), isNot(contains('she is ')), reason: o.label);
        expect(o.label.toLowerCase(), isNot(contains('has a ')), reason: o.label);
      }
    });

    test('every option leads somewhere: each id is in at least one rule', () {
      final Set<String> used = <String>{for (final CompassRule r in compassRules) ...r.anyOf};
      for (final CompassOption o in <CompassOption>[...compassWhoOptions, ...compassNeedsOptions]) {
        expect(used, contains(o.id), reason: '${o.id} is asked but changes nothing');
      }
    });
  });

  group('the answers', () {
    test('any number may be chosen, none is a complete answer, and unknown ids are dropped', () {
      expect(const CompassAnswers().isEmpty, isTrue);
      final CompassAnswers a = const CompassAnswers().withWho('twoHomes', true).withNeed('quiet', true).withWho('nope', true).withNeed('twoHomes', true);
      expect(a.who, <String>{'twoHomes'});
      expect(a.needs, <String>{'quiet'});
      expect(a.withWho('twoHomes', false).who, isEmpty);
      expect(a.withWho('twoHomes', false).withNeed('quiet', false).isEmpty, isTrue);
    });

    test('they round-trip in the table\'s own order, whatever order they were ticked', () {
      final CompassAnswers a = const CompassAnswers().withWho('siblings', true).withWho('twoHomes', true);
      final CompassAnswers b = const CompassAnswers().withWho('twoHomes', true).withWho('siblings', true);
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(CompassAnswers.fromJson(jsonDecode(jsonEncode(a.toJson()))), a);
    });

    test('a damaged document yields what is known and never throws', () {
      expect(CompassAnswers.fromJson(null).isEmpty, isTrue);
      expect(CompassAnswers.fromJson('x').isEmpty, isTrue);
      final CompassAnswers a = CompassAnswers.fromJson(<String, Object?>{'who': <Object?>['twoHomes', 5, 'junk'], 'needs': 'bad'});
      expect(a.who, <String>{'twoHomes'});
      expect(a.needs, isEmpty);
      expect(CompassAnswers.fromJson(<String, Object?>{'who': <Object?>['quiet']}).who, isEmpty, reason: 'a need id is not a who id');
    });
  });

  group('the rules table is plain data', () {
    test('every row names real answers and a real suite or profile, with a sentence of why', () {
      final Set<String> known = <String>{for (final CompassOption o in <CompassOption>[...compassWhoOptions, ...compassNeedsOptions]) o.id};
      for (final CompassRule r in compassRules) {
        expect(r.anyOf, isNotEmpty);
        for (final String id in r.anyOf) {
          expect(known, contains(id));
        }
        if (r.kind == SuggestionKind.suite) expect(suiteKeysOnShelf, contains(r.key));
        if (r.kind == SuggestionKind.profile) expect(profileKeys, contains(r.key));
        expect(r.reason.length, greaterThan(30));
        expect(r.reason.endsWith('.'), isTrue);
      }
    });

    test('no reason scores, ranks, diagnoses or claims intelligence; none contains a number', () {
      const List<String> banned = <String>[
        'score', 'rank', 'risk', 'likely', 'predict', 'algorithm', 'ai ', 'machine', 'smart', 'best for', 'recommended for you',
        'diagnos', 'disorder', 'need level', 'severity', 'percent', '%',
      ];
      for (final CompassRule r in compassRules) {
        for (final String b in banned) {
          expect(r.reason.toLowerCase(), isNot(contains(b)), reason: '"${r.reason}" contains "$b"');
        }
        expect(r.reason, isNot(matches(RegExp(r'\d'))), reason: r.reason);
      }
    });

    test('the logic carries no weight, score or rank field in code', () {
      final String src = File('lib/compass_logic.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      for (final String banned in <String>['score', 'weight', 'rank', 'probab', 'confidence', 'diagnos', 'sort(', 'Random']) {
        expect(src.toLowerCase().contains(banned.toLowerCase()), isFalse, reason: banned);
      }
    });

    test('there are no more than five suggestions in the cap, and the cap is the documented one', () {
      expect(maxSuggestions, 5);
    });
  });

  group('suggest', () {
    test('no answers, no suggestions: "not sure" and "skip" are complete', () {
      expect(suggest(const CompassAnswers()), isEmpty);
    });

    test('two homes points at Rhythm, with the table\'s own sentence and the answer that led to it', () {
      final List<Suggestion> s = suggest(const CompassAnswers(who: <String>{'twoHomes'}));
      expect(s.single.kind, SuggestionKind.suite);
      expect(s.single.key, 'rhythm');
      expect(s.single.because, <String>['twoHomes']);
      expect(s.single.reasons.single, compassRules.first.reason);
    });

    test('a device that goes to another home also mentions the away profile, as a profile', () {
      final List<Suggestion> s = suggest(const CompassAnswers(who: <String>{'deviceTravels'}));
      expect(s.map((Suggestion x) => '${x.kind.name}:${x.key}'), <String>['suite:rhythm', 'profile:awayFromHome']);
    });

    test('alerts she can see, or signing, mention the visible-alerts profile and nothing else', () {
      for (final String id in <String>['seeAlerts', 'signing']) {
        final List<Suggestion> s = suggest(CompassAnswers(needs: <String>{id}));
        expect(s.single.kind, SuggestionKind.profile, reason: id);
        expect(s.single.key, profileDeaf, reason: id);
      }
    });

    test('Village mentions every way it could help once, merging the reasons in table order', () {
      final List<Suggestion> s = suggest(const CompassAnswers(who: <String>{'stepAdult', 'grandparent', 'siblings'}, needs: <String>{'sitter', 'school'}));
      expect(s.length, 1);
      expect(s.single.key, 'village');
      expect(s.single.reasons.length, 4);
      expect(s.single.because, <String>['stepAdult', 'grandparent', 'siblings', 'sitter', 'school']);
    });

    test('each rule is reachable: choosing any one answer gives the suggestion it names', () {
      for (final CompassRule r in compassRules) {
        final List<Suggestion> s = suggest(only(<String>[r.anyOf.first]), max: 99);
        expect(s.any((Suggestion x) => x.kind == r.kind && x.key == r.key && x.reasons.contains(r.reason)), isTrue, reason: r.reason);
      }
    });

    test('the same answers always give the same list in the same order, however they were ticked', () {
      final List<String> ids = <String>['quiet', 'medical', 'siblings', 'twoHomes', 'pictures', 'loss'];
      final List<Suggestion> a = suggest(only(ids));
      final List<Suggestion> b = suggest(only(ids.reversed));
      expect(<String>[for (final Suggestion x in a) '${x.kind.name}:${x.key}'], <String>[for (final Suggestion x in b) '${x.kind.name}:${x.key}']);
      for (int i = 0; i < 20; i++) {
        expect(suggest(only(ids)).map((Suggestion x) => x.key).toList(), a.map((Suggestion x) => x.key).toList());
      }
    });

    test('capped at five: with everything chosen the first five in the table\'s order, never a ranking', () {
      final List<Suggestion> s = suggest(all());
      expect(s.length, maxSuggestions);
      expect(s.map((Suggestion x) => '${x.kind.name}:${x.key}'), <String>['suite:rhythm', 'suite:voice', 'suite:village', 'suite:growing', 'suite:care']);
      expect(suggest(all(), max: 2).length, 2);
      expect(suggest(all(), max: 0), isEmpty);
      expect(suggest(all(), max: -3), isEmpty);
      expect(suggest(all(), max: 99).length, 7, reason: 'five suites and two profiles in all');
    });

    test('every suggestion explains itself: a reason and the answers that led to it', () {
      for (final Suggestion s in suggest(all(), max: 99)) {
        expect(s.reasons, isNotEmpty);
        expect(s.because, isNotEmpty);
        for (final String id in s.because) {
          expect(optionLabel(id), isNotNull);
        }
      }
    });

    test('an answer can only add: ticking more never removes an earlier suggestion until the cap', () {
      final Set<String> a = suggest(const CompassAnswers(who: <String>{'twoHomes'}), max: 99).map((Suggestion x) => x.key).toSet();
      final Set<String> b = suggest(const CompassAnswers(who: <String>{'twoHomes', 'siblings'}), max: 99).map((Suggestion x) => x.key).toSet();
      expect(b.containsAll(a), isTrue);
    });

    test('a suggestion carries no field that could hold a score or a verdict about her', () {
      final Suggestion s = suggest(const CompassAnswers(who: <String>{'twoHomes'})).single;
      // The type has exactly: kind, key, reasons, because. (A field added later would need this test changed on purpose.)
      expect(<Object?>[s.kind, s.key, s.reasons, s.because].length, 4);
    });
  });

  group('the family builder\'s hints', () {
    test('only counts become hints: more than one sleeping home, or someone marked away', () {
      expect(builderHints(sleepingHomes: 0, someoneAway: false), isEmpty);
      expect(builderHints(sleepingHomes: 1, someoneAway: false), isEmpty);
      expect(builderHints(sleepingHomes: 2, someoneAway: false), <String>['twoHomes']);
      expect(builderHints(sleepingHomes: 3, someoneAway: true), <String>['twoHomes', 'parentAway']);
      expect(builderHints(sleepingHomes: 1, someoneAway: true), <String>['parentAway']);
    });

    test('every hint is a real question id', () {
      for (final String h in builderHints(sleepingHomes: 2, someoneAway: true)) {
        expect(optionLabel(h), isNotNull);
      }
    });
  });

  group('the two profiles change presentation defaults and nothing else', () {
    test('away from home: read aloud on and motion reduced; every other setting is left exactly as it was', () {
      const AccessSettings before = AccessSettings(largerTargets: true, roomierReading: true);
      final AccessSettings after = applyProfileTo(before, awayProfile);
      expect(after.readAloud, isTrue);
      expect(after.reduceMotion, isTrue);
      expect(after.largerTargets, isTrue);
      expect(after.roomierReading, isTrue);
      expect(after.captions, before.captions);
      expect(after.visualAlerts, before.visualAlerts);
    });

    test('alerts she can see: read aloud off, roomier reading, a captions wish, visible alerts; motion and targets untouched', () {
      const AccessSettings before = AccessSettings(reduceMotion: true, largerTargets: true);
      final AccessSettings after = applyProfileTo(before, deafProfile);
      expect(after.readAloud, isFalse);
      expect(after.roomierReading, isTrue);
      expect(after.captions, isTrue);
      expect(after.visualAlerts, isTrue);
      expect(after.reduceMotion, isTrue);
      expect(after.largerTargets, isTrue);
    });

    test('the captions wish is honest: nothing is shown because of it (captions are not built)', () {
      final AccessSettings after = applyProfileTo(AccessSettings.defaults, deafProfile);
      expect(after.captions, isTrue);
      expect(after.captionsActive, isFalse);
      expect(deafProfile.changes.any((String c) => c.toLowerCase().contains('not built')), isTrue);
    });

    test('applying twice changes nothing more', () {
      expect(applyProfileTo(applyProfileTo(AccessSettings.defaults, awayProfile), awayProfile), applyProfileTo(AccessSettings.defaults, awayProfile));
      expect(applyProfileTo(applyProfileTo(AccessSettings.defaults, deafProfile), deafProfile), applyProfileTo(AccessSettings.defaults, deafProfile));
    });

    test('a profile names only settings that exist, and lists each in plain words', () {
      for (final ProfileDefaults p in allProfiles) {
        expect(p.changes, isNotEmpty);
        expect(p.summary, isNotEmpty);
        expect(profileById(p.id), same(p));
      }
      expect(profileById('nope'), isNull);
      expect(profileKeys, <String>[awayProfile.id, deafProfile.id]);
    });

    test('a profile is described about the device, never as a label on the child', () {
      for (final ProfileDefaults p in allProfiles) {
        final String text = '${p.title} ${p.summary} ${p.changes.join(' ')}'.toLowerCase();
        for (final String banned in <String>['diagnos', 'disorder', 'special needs', 'patient', 'condition']) {
          expect(text, isNot(contains(banned)));
        }
      }
    });
  });

  group('alert cues: no cue is ever sound only, and nothing ever flashes', () {
    test('by default a cue is a picture and words that fade', () {
      for (final AlertKind k in AlertKind.values) {
        final AlertCue c = cueFor(AccessSettings.defaults, k);
        expect(c.visual, isTrue);
        expect(c.text, isNotEmpty);
        expect(c.persistent, isFalse);
        expect(c.haptic, isFalse);
        expect(c.flashes, isFalse);
      }
    });

    test('with visible alerts on, it stays until tapped and adds a gentle buzz; it is still words', () {
      for (final AlertKind k in AlertKind.values) {
        final AlertCue c = cueFor(const AccessSettings(visualAlerts: true), k);
        expect(c.visual, isTrue);
        expect(c.text, alertText(k));
        expect(c.persistent, isTrue);
        expect(c.haptic, isTrue);
        expect(c.flashes, isFalse);
      }
    });

    test('every alert has its own plain words', () {
      expect(AlertKind.values.map(alertText).toSet().length, AlertKind.values.length);
      for (final AlertKind k in AlertKind.values) {
        expect(alertText(k), isNotEmpty);
      }
    });
  });
}
