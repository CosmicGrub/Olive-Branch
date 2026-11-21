// The review gate and the loader. UNVERIFIED until CI runs it.
//
// The rule under test: a guide whose status is not REVIEWED is never returned in a default or release build; drafts
// can be previewed only with the debug switch ON in a non-release build; a REVIEWED guide still needs a complete
// review record, a covered region and clean parent wording.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_guide_gate.dart';
import 'package:olive_client/care_guide_loader.dart';
import 'package:olive_client/care_guide_models.dart';

import 'care_guide_fixtures.dart';

const List<String> _ids = <String>['who-to-call', 'choking', 'head-injury', 'high-fever', 'childproofing-home'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('default and release builds show no draft', () {
    test('the preview switch is off by default', () {
      expect(careGuidesDraftPreview, false);
      expect(CareGuidePolicy.current().draftPreview, false);
      expect(const CareGuidePolicy().showsDrafts, false);
    });

    test('the real bundled assets hold no guide at all: the drafts are not in the app (not even for a debug preview)', () async {
      final CareGuideLibrary lib = await CareGuideLoader().load(); // rootBundle = the real bundled assets
      expect(lib.guides, isEmpty);
      expect(lib.rejected, isEmpty);
      final CareGuideLibrary preview = await CareGuideLoader(policy: const CareGuidePolicy(draftPreview: true)).load();
      expect(preview.guides, isEmpty);
    });

    test('the five real drafts, if they were bundled, would all be refused as not reviewed', () async {
      final CareGuideLibrary lib = await CareGuideLoader(bundle: realDraftBundle()).load();
      expect(lib.guides, isEmpty);
      expect(lib.rejected.map((RejectedGuide r) => r.id).toList(), _ids);
      expect(lib.rejected.every((RejectedGuide r) => r.reason == GateRefusal.notReviewed), true);
    });

    test('a release build ignores the preview switch: still nothing', () async {
      final CareGuideLibrary lib = await CareGuideLoader(policy: const CareGuidePolicy(draftPreview: true, releaseMode: true)).load();
      expect(lib.guides, isEmpty);
      expect(const CareGuidePolicy(draftPreview: true, releaseMode: true).showsDrafts, false);
    });

    test('a draft is not even parsed when the gate is closed (a malformed draft is simply refused)', () async {
      final Map<String, Object?> bad = <String, Object?>{'id': 'broken-draft', 'status': 'DRAFT_UNREVIEWED'};
      final CareGuideLibrary lib = await CareGuideLoader(bundle: bundleOf(<Map<String, Object?>>[bad])).load();
      expect(lib.guides, isEmpty);
      expect(lib.rejected.single.reason, GateRefusal.notReviewed);
    });
  });

  group('the debug preview', () {
    test('with the switch on in a non-release build all five drafts load, each marked as a draft', () async {
      final CareGuideLibrary lib = await CareGuideLoader(bundle: realDraftBundle(), policy: const CareGuidePolicy(draftPreview: true)).load();
      expect(lib.guides.map((CareGuide g) => g.id).toList(), _ids);
      expect(lib.draftIds, _ids.toSet());
      expect(lib.guides.every((CareGuide g) => g.status == kStatusDraft && lib.isDraft(g)), true);
    });

    test('only DRAFT_UNREVIEWED can be previewed: any other status is refused even then', () async {
      for (final String s in <String>['REJECTED', 'RETIRED', 'reviewed', '', 'APPROVED']) {
        final CareGuideLibrary lib = await CareGuideLoader(
          bundle: bundleOf(<Map<String, Object?>>[fixtureGuide(status: s)]),
          policy: const CareGuidePolicy(draftPreview: true),
        ).load();
        expect(lib.guides, isEmpty, reason: 'status "$s" must never show');
      }
    });
  });

  group('a REVIEWED guide still has to earn it', () {
    CareGuidePolicy release() => const CareGuidePolicy(releaseMode: true);

    test('a complete, clean record is allowed (and is not a draft)', () {
      final GateDecision d = decideGuide(fixtureCareGuide(), release());
      expect(d.allowed, true);
      expect(d.isDraft, false);
    });

    test('through the loader in a release build a complete REVIEWED guide is returned', () async {
      final CareGuideLibrary lib = await CareGuideLoader(bundle: bundleOf(<Map<String, Object?>>[fixtureGuide()]), policy: release()).load();
      expect(lib.guides.single.id, 'sample-guide');
      expect(lib.draftIds, isEmpty);
    });

    test('no review date, no reviewer role, a malformed date or no regions: refused', () {
      for (final Map<String, Object?> g in <Map<String, Object?>>[
        fixtureGuide(reviewedOn: null),
        fixtureGuide(reviewedOn: '2030-1-2'),
        fixtureGuide(reviewedBy: null),
        fixtureGuide(reviewedBy: '   '),
        fixtureGuide(regions: <String>[]),
      ]) {
        expect(decideGuide(CareGuide.fromJson(g), release()).refusal, GateRefusal.incompleteReviewRecord);
      }
    });

    test('a reviewer who did not cover the region of the guide: refused', () {
      final GateDecision d = decideGuide(CareGuide.fromJson(fixtureGuide(region: 'XX', regions: <String>['YY'])), release());
      expect(d.refusal, GateRefusal.regionNotCovered);
    });

    test('parent wording that talks to the reviewer: refused', () {
      for (final String bad in <String>[' per the clinician guide', ' (Source 3)', ' see Disagreement 2', ' as stated [10]', ' also [2, 3]', ' DRAFT only', ' this is not reviewed']) {
        final CareGuide g = CareGuide.fromJson(fixtureGuide(extraText: bad));
        expect(decideGuide(g, release()).refusal, GateRefusal.wordingLint, reason: bad);
      }
    });

    test('pointers to material that is not bundled, and reviewer vocabulary: refused', () {
      for (final String bad in <String>[
        ' (see disagreements)',
        ' (other figures are in the disagreements block)',
        ' (see the emergency list)',
        ' (see the get-medical-help-now list)',
        ' see the list above',
        ' Needs review by a qualified paediatric reviewer before any use in an app',
        ' needs a review first',
        ' this is unverified',
      ]) {
        final CareGuide g = CareGuide.fromJson(fixtureGuide(extraText: bad));
        expect(decideGuide(g, release()).refusal, GateRefusal.wordingLint, reason: bad);
      }
    });

    test('a review date must be a real calendar date, not just date-shaped', () {
      for (final String bad in <String>['9999-99-99', '2030-02-31', '2030-13-01', '2029-02-29', '0000-00-00']) {
        expect(decideGuide(CareGuide.fromJson(fixtureGuide(reviewedOn: bad)), release()).refusal, GateRefusal.incompleteReviewRecord, reason: bad);
      }
      for (final String ok in <String>['2030-02-28', '2028-02-29']) {
        expect(decideGuide(CareGuide.fromJson(fixtureGuide(reviewedOn: ok)), release()).allowed, true, reason: ok);
      }
    });

    test('a phone number field is digits and dialling punctuation only', () {
      for (final String ok in <String>['555-0100', '999 / 111', '+44 20 7946 0000', '1-800-222-1222', '(02) 5550 0100']) {
        expect(isPlainNumber(ok), true, reason: ok);
      }
      for (final String bad in <String>['1-800-222-1222 (also online tool at example.org)', 'call 999', '', 'https://x.org', '999 or 111']) {
        expect(isPlainNumber(bad), false, reason: bad);
        final CareGuide g = CareGuide.fromJson(fixtureGuide(helplines: <Map<String, Object?>>[
          <String, Object?>{'region': 'XX', 'name': 'Line', 'number': bad, 'sources': <int>[1]},
        ]));
        expect(decideGuide(g, release()).refusal, GateRefusal.wordingLint, reason: bad);
      }
    });

    test('helplines are shown only for regions the review covers; a draft shows only its own region', () {
      final List<Map<String, Object?>> lines = <Map<String, Object?>>[
        <String, Object?>{'region': 'XX', 'name': 'Own line', 'number': '555-0100', 'sources': <int>[1]},
        <String, Object?>{'region': 'YY', 'name': 'Other line', 'number': '555-0200', 'sources': <int>[1]},
      ];
      CareGuide g(List<String> regions, {String status = 'REVIEWED'}) =>
          fixtureCareGuide(status: status, helplines: lines, regions: regions);
      expect(helplinesToShow(g(<String>['XX']), draft: false).map((Helpline h) => h.region).toList(), <String>['XX']);
      expect(helplinesToShow(g(<String>['XX', 'YY']), draft: false).map((Helpline h) => h.region).toList(), <String>['XX', 'YY']);
      expect(helplinesToShow(g(<String>['XX', 'YY'], status: 'DRAFT_UNREVIEWED'), draft: true).map((Helpline h) => h.region).toList(), <String>['XX']);
    });

    test('wording that merely looks similar is fine', () {
      final CareGuide g = CareGuide.fromJson(fixtureGuide(extraText: ' and 2 sources of heat, in [brackets]'));
      expect(decideGuide(g, release()).allowed, true);
    });

    test('a REVIEWED file that does not match the schema is dropped, not shown', () async {
      final Map<String, Object?> g = fixtureGuide()..['blocks'] = <Object?>[<String, Object?>{'kind': 'madeUpKind', 'items': <Object?>[]}];
      final CareGuideLibrary lib = await CareGuideLoader(bundle: bundleOf(<Map<String, Object?>>[g]), policy: release()).load();
      expect(lib.guides, isEmpty);
      expect(lib.rejected.single.reason, isNull);
    });

    test('a missing asset or an unreadable index yields an empty library, not an error', () async {
      expect((await CareGuideLoader(bundle: MapBundle(<String, String>{})).load()).guides, isEmpty);
      expect((await CareGuideLoader(bundle: MapBundle(<String, String>{'assets/care_guides/index.json': 'not json'})).load()).guides, isEmpty);
    });

    test('an id in the index that is a path is ignored', () async {
      final MapBundle b = MapBundle(<String, String>{
        'assets/care_guides/index.json': jsonEncode(<String, Object?>{'guides': <Object?>['../secret', 'a/b']}),
      });
      expect((await CareGuideLoader(bundle: b, policy: const CareGuidePolicy(draftPreview: true)).load()).rejected, isEmpty);
    });
  });

  group('the five real drafts cannot be promoted by flipping the status alone', () {
    for (final String id in _ids) {
      test('$id: flipping the status alone is refused; with a complete record the wording lint still refuses it', () {
        final Map<String, Object?> m = jsonDecode(File('$kDraftDir/$id.json').readAsStringSync()) as Map<String, Object?>;
        m['status'] = 'REVIEWED';
        expect(decideGuide(CareGuide.fromJson(m), const CareGuidePolicy(releaseMode: true)).refusal, GateRefusal.incompleteReviewRecord);
        m['review'] = <String, Object?>{'reviewedOn': '2030-01-02', 'reviewedBy': 'role', 'regions': <String>[m['region']! as String]};
        final CareGuide g = CareGuide.fromJson(m);
        final List<String> v = wordingViolations(g);
        // ignore: avoid_print
        print('$id: ${v.length} parent-facing strings need rewriting before review can pass');
        expect(v, isNotEmpty);
        expect(decideGuide(g, const CareGuidePolicy(releaseMode: true)).refusal, GateRefusal.wordingLint);
      });
    }

    test('every parent-facing string in the drafts that points at a section, list or the disagreements is caught by the lint', () {
      // A deliberately broader net than the lint itself: anything that reads like "see ..." or names a section that
      // the app does not bundle. Whatever it finds, the lint must also refuse, so a reviewer who rewrites only part of a
      // guide cannot get a REVIEWED guide with a dangling pointer past the gate.
      final RegExp pointer = RegExp(r'disagree|\bsee\b[^.;:]{0,80}\b(list|block|section|rule|above|below)\b|\b(list|block) above|reviewer|unverified', caseSensitive: false);
      int total = 0;
      for (final String id in _ids) {
        final CareGuide g = CareGuide.fromJson(jsonDecode(File('$kDraftDir/$id.json').readAsStringSync()) as Map<String, Object?>);
        final Set<String> caught = wordingViolations(g).toSet();
        for (final String s in parentFacingStrings(g)) {
          if (pointer.hasMatch(s)) {
            total++;
            expect(caught.contains(s), true, reason: '$id: "$s"');
          }
        }
      }
      expect(total, greaterThan(20), reason: 'the drafts really do carry these pointers');
    });
  });

  group('the dose rule (ISS-093): no amount, no per-weight amount, no dosing interval', () {
    CareGuide withText(String t) => CareGuide.fromJson(fixtureGuide(extraText: ' $t'));

    // Everything here must be REFUSED: a dose, in any of the shapes a dose takes.
    const List<String> doses = <String>[
      'Give 5 mg now.', 'give 10mg', 'Give 250 mg every 6 hours.', 'Give 2.5 ml.', 'Give 5 mL of the liquid.', 'Give 1,5 ml.',
      'Give one tablet.', 'Give two tablets.', 'Give half a teaspoon.', 'Give 1 tsp.', 'Give 2 tablespoons.', 'Give 2 puffs.',
      'Give 3 drops.', 'Give one spoonful.', 'Give a capsule.', 'Give 100 mcg.', 'Give 400 IU.', 'Give 2 units.', 'Give 5 grams.',
      '15 mg/kg', '10 mg per kg', 'Give per kilogram of body weight.', 'Give per pound of body weight.', 'Give 5/kg.',
      'Repeat every 4 hours.', 'Repeat every 4 to 6 hours.', 'Repeat every six hours.', 'Repeat every 8 hrs.', 'Repeat q6h.',
      'Repeat 4-6 hourly.', 'Give twice a day.', 'Give three times a day.', 'Give three times daily.', 'Give once daily.',
      'Give four times per day.', 'Give twice daily.', 'Give it bid.', 'No more than maximum 4 doses.', 'max of 5 doses',
      'Give a suppository.', 'Give 2 lozenges.', 'Apply a patch.',
      // deliberately eager: it only LOOKS like a dose, and the reviewer rewords it
      'There was a drop in temperature.',
    ];
    // Everything here must PASS: times, counts, weights and phone numbers that are not doses.
    const List<String> notDoses = <String>[
      'Call 911 now.', 'Call 000 if life is in danger.', 'If the fever lasts more than 24 hours, call the doctor.',
      'Check on the baby every 5 to 10 minutes.', 'Apply firm pressure for 10 minutes.', 'A child under 5 kg needs a doctor today.',
      'Give 5 back blows, then 5 chest thrusts.', 'Do about 2 minutes of CPR: 30 compressions then 2 breaths.', 'Call 9-8-8.',
      'The thermometer beeps after about 1 minute.', 'A temperature of 38 C (100.4 F) is a fever.', 'No urine for 8 hours.',
      'Poisons Information Centre 13 11 26.', 'Keep them upright and watch their breathing.', 'Do not give a double dose.',
      'Children under 6 months should see a doctor.', 'A seizure lasting more than 5 minutes needs 911.', 'About 2 inches deep.',
      'Cool a burn under running water for 20 minutes.', 'Stay with them for at least the first 24 hours.', 'Sleep 12 to 16 hours a day.',
    ];

    test('every positive vector has the shape of a dose', () {
      for (final String s in doses) {
        expect(hasDosePattern(s), true, reason: s);
      }
    });

    test('every negative vector is not a dose shape', () {
      for (final String s in notDoses) {
        expect(hasDosePattern(s), false, reason: s);
      }
    });

    test('a REVIEWED guide carrying any positive vector is refused with the wording lint (fail closed)', () {
      for (final String s in doses) {
        final CareGuide g = withText(s);
        expect(wordingViolations(g), isNotEmpty, reason: s);
        expect(decideGuide(g, release()).refusal, GateRefusal.wordingLint, reason: s);
      }
    });

    test('a REVIEWED guide carrying only negative vectors is allowed', () {
      for (final String s in notDoses) {
        expect(decideGuide(withText(s), release()).allowed, true, reason: s);
      }
    });

    test('the rule reads every parent-facing field: a dose hidden in a title, a note or a sign is found', () {
      final Map<String, Object?> base = fixtureGuide();
      final Map<String, Object?> inTitle = <String, Object?>{...base, 'title': 'Give 5 mg'};
      expect(wordingViolations(CareGuide.fromJson(inTitle)), isNotEmpty);
      final Map<String, Object?> inNote = <String, Object?>{...base, 'notes': <Object?>[<String, Object?>{'text': 'Repeat every 4 hours.', 'sources': <int>[1]}]};
      expect(wordingViolations(CareGuide.fromJson(inNote)), isNotEmpty);
    });

    test('the rule needs no medicine name: an unheard-of medicine with an amount is still caught', () {
      expect(hasDosePattern('Give 7.5 mg of Zzzquil-X.'), true);
      expect(hasDosePattern('Zzzquil-X is a medicine.'), false);
    });

    test('the patterns are exposed for the structure test and are non-empty', () {
      expect(doseLintPatterns.length, greaterThanOrEqualTo(8));
    });
  });

  group('the models never see reviewer-only material', () {
    test('the bundled files carry no reviewer-only key anywhere', () {
      for (final String id in _ids) {
        final Set<String> keys = <String>{};
        void walk(Object? o) {
          if (o is Map<String, Object?>) {
            for (final MapEntry<String, Object?> e in o.entries) {
              keys.add(e.key);
              walk(e.value);
            }
          } else if (o is List<Object?>) {
            o.forEach(walk);
          }
        }

        walk(jsonDecode(File('$kDraftDir/$id.json').readAsStringSync()));
        for (final String k in <String>[
          'reviewOnly', 'displayToParents', 'clinicianOnly', 'honeyDoseConflict', 'reviewQuestions', 'unverified', 'disagreements', 'changeLog',
        ]) {
          expect(keys.contains(k), false, reason: '$id carries "$k"');
        }
      }
    });

    test('even if a file carried reviewOnly, the parsed guide has nowhere to put it', () {
      final Map<String, Object?> m = fixtureGuide()..['reviewOnly'] = <String, Object?>{'clinicianOnly': <String, Object?>{'secret': 'DO NOT SHOW'}};
      final CareGuide g = CareGuide.fromJson(m);
      expect(parentFacingStrings(g).any((String s) => s.contains('DO NOT SHOW')), false);
    });
  });
}
