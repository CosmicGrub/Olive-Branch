// OLIVE BRANCH — the care profile's pure rules: the tone guard, both-versions grouping, who may be shown what,
// the review prompts, the doctor sheet, the teen sheet and a tolerant read. UNVERIFIED until CI runs this file.
// MASTERFILE section 8.24.8.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_local.dart';
import 'package:olive_client/care_profile_logic.dart';
import 'package:olive_client/emergency_card_local.dart';

CpEntry _e(String id, CareProfilePart part, String text, {String title = '', String by = 'mom', String name = 'Sam', DateTime? at}) =>
    CpEntry(id: id, part: part, title: title, text: text, at: at ?? DateTime.utc(2026, 11, 14, 12), byId: by, byName: name);

void main() {
  group('the child sees none of it', () {
    test('every part is invisible to her, and stays so', () {
      for (final CareProfilePart p in CareProfilePart.values) {
        expect(careProfileVisibleToChild(p), isFalse, reason: p.name);
      }
    });

    test('health history and moods can never be shared, with anyone', () {
      for (final CpPersonKind k in CpPersonKind.values) {
        expect(cpMayGrant(k, CareProfilePart.health), isFalse);
        expect(cpMayGrant(k, CareProfilePart.moods), isFalse);
      }
      expect(CareProfilePart.health.locked && CareProfilePart.moods.locked, isTrue);
    });

    test('a view-only person can be given Keep-safe and nothing else', () {
      for (final CareProfilePart p in CareProfilePart.values) {
        expect(cpMayGrant(CpPersonKind.viewOnly, p), p == CareProfilePart.safe, reason: p.name);
      }
    });
  });

  group('the tone guard', () {
    test('refuses the care-note phrases and the labels, and names what it found', () {
      expect(careProfileToneFound('You never listen'), contains('you never'));
      expect(careProfileToneFound('She is in a bad mood after school'), contains('bad mood'));
      expect(careProfileToneFound('Obviously her fault'), containsAll(<String>['obviously']));
    });

    test('lets a description of need through', () {
      expect(careProfileToneFound('Needs quiet after school. Blue blanket helps.'), isEmpty);
    });

    test('runs on the parts that describe her, not on a doctor\'s wording', () {
      expect(CareProfilePart.helps.tone && CareProfilePart.moods.tone && CareProfilePart.heads.tone && CareProfilePart.everyday.tone, isTrue);
      expect(CareProfilePart.safe.tone || CareProfilePart.health.tone, isFalse);
    });
  });

  group('both versions', () {
    test('two writers, same title, different words: one group with both; the same writer or the same words: none', () {
      final CareProfileDoc d = CareProfileDoc(entries: <CpEntry>[
        _e('a', CareProfilePart.everyday, 'Bed at 7:30', title: 'Bedtime'),
        _e('b', CareProfilePart.everyday, 'Bed at 8:00', title: 'Bedtime', by: 'dad', name: 'Alex'),
        _e('c', CareProfilePart.everyday, 'Oats', title: 'Breakfast'),
        _e('d', CareProfilePart.everyday, 'oats', title: 'Breakfast', by: 'dad', name: 'Alex'),
        _e('f', CareProfilePart.everyday, 'No title one'),
        _e('g', CareProfilePart.everyday, 'No title two', by: 'dad'),
        _e('h', CareProfilePart.everyday, 'Rice', title: 'Lunch'),
        _e('i', CareProfilePart.everyday, 'Pasta', title: 'Lunch'),
      ]);
      final List<List<CpEntry>> g = cpDisagreements(d, CareProfilePart.everyday);
      expect(g, hasLength(1));
      expect(g.single.map((CpEntry e) => e.id).toSet(), <String>{'a', 'b'});
    });

    test('a put-away version is not in the group', () {
      final CareProfileDoc d = CareProfileDoc(entries: <CpEntry>[
        _e('a', CareProfilePart.helps, 'Quiet', title: 'Hard day'),
        _e('b', CareProfilePart.helps, 'Walk outside', title: 'Hard day', by: 'dad', name: 'Alex').copyWith(retired: true),
      ]);
      expect(cpDisagreements(d, CareProfilePart.helps), isEmpty);
    });
  });

  group('who may be shown what', () {
    final DateTime now = DateTime.utc(2026, 11, 14, 20);

    test('a grant works until it ends and not after', () {
      final CpPerson p = CpPerson(
        id: 'p1',
        name: 'Nan',
        kind: CpPersonKind.visit,
        grants: <CareProfilePart, CpGrant>{CareProfilePart.safe: CpGrant(until: now.add(const Duration(hours: 1)))},
      );
      expect(cpCanSee(p, CareProfilePart.safe, now), isTrue);
      expect(cpCanSee(p, CareProfilePart.safe, now.add(const Duration(hours: 1))), isFalse);
      expect(cpCanSee(p, CareProfilePart.everyday, now), isFalse);
    });

    test('a grant for a part that cannot be shared is dropped when read back', () {
      final CpPerson? p = CpPerson.tryFromJson(<String, Object?>{
        'id': 'p1', 'name': 'Nan', 'kind': 'carer', 'grants': <String, Object?>{'health': '', 'moods': '', 'safe': ''},
      });
      expect(p!.grants.keys, <CareProfilePart>[CareProfilePart.safe]);
    });

    test('the defaults match the table: a carer, a visit until 6 in the morning, the other two nothing', () {
      expect(cpDefaultGrants(CpPersonKind.carer, now).keys.toSet(), <CareProfilePart>{CareProfilePart.safe, CareProfilePart.everyday, CareProfilePart.heads});
      final Map<CareProfilePart, CpGrant> visit = cpDefaultGrants(CpPersonKind.visit, now);
      expect(visit.keys.toSet(), <CareProfilePart>{CareProfilePart.safe, CareProfilePart.heads});
      expect(visit[CareProfilePart.safe]!.until, isNotNull);
      expect(cpDefaultGrants(CpPersonKind.viewOnly, now), isEmpty);
      expect(cpDefaultGrants(CpPersonKind.helperPage, now), isEmpty);
    });

    test('"tonight" ends at the next 6 in the morning, local time', () {
      final DateTime evening = DateTime(2026, 11, 14, 21);
      final DateTime end = cpTonightEnds(evening).toLocal();
      expect(end, DateTime(2026, 11, 15, 6));
      final DateTime earlyMorning = DateTime(2026, 11, 14, 3);
      expect(cpTonightEnds(earlyMorning).toLocal(), DateTime(2026, 11, 14, 6));
    });

    test('the view holds only granted parts, never a parents-only one, the heads-up only today, never a put-away entry', () {
      final DateTime t = DateTime(2026, 11, 14, 20);
      final CareProfileDoc d = CareProfileDoc(
        entries: <CpEntry>[
          _e('s', CareProfilePart.safe, 'Peanut allergy'),
          _e('x', CareProfilePart.everyday, 'Oats'),
          _e('gone', CareProfilePart.safe, 'Old').copyWith(retired: true),
          _e('h', CareProfilePart.health, 'A history'),
          _e('m', CareProfilePart.moods, 'A pattern'),
        ],
        heads: CpHeads(text: 'Slept badly', day: cpDay(t), at: t.toUtc()),
      );
      const CpPerson p = CpPerson(
        id: 'p', name: 'Sitter', kind: CpPersonKind.carer,
        grants: <CareProfilePart, CpGrant>{
          CareProfilePart.safe: CpGrant(),
          CareProfilePart.heads: CpGrant(),
        },
      );
      final List<CpPartView> v = cpViewFor(d, p, t);
      expect(v.map((CpPartView x) => x.part).toList(), <CareProfilePart>[CareProfilePart.safe, CareProfilePart.heads]);
      expect(v.first.entries.map((CpEntry e) => e.text).toList(), <String>['Peanut allergy']);
      // Tomorrow the heads-up is not today, so it is not in the view.
      final List<CpPartView> tomorrow = cpViewFor(d, p, t.add(const Duration(days: 1)));
      expect(tomorrow.map((CpPartView x) => x.part).toList(), <CareProfilePart>[CareProfilePart.safe]);
    });
  });

  group("today's heads-up", () {
    test('is today at 23:59 and is gone one minute later', () {
      final CareProfileDoc d = CareProfileDoc(heads: CpHeads(text: 'x', day: '2026-11-14', at: DateTime.utc(2026, 11, 14)));
      expect(cpHeadsToday(d, DateTime(2026, 11, 14, 23, 59)), isNotNull);
      expect(cpHeadsToday(d, DateTime(2026, 11, 15, 0, 0)), isNull);
    });
  });

  group('review prompts', () {
    CareProfileDoc doc({DateTime? created, DateTime? reviewed, int? m, int? d, String? fp}) => CareProfileDoc(
          entries: <CpEntry>[_e('a', CareProfilePart.safe, 'Allergy')],
          createdAt: created,
          lastReviewedAt: reviewed,
          birthMonth: m,
          birthDay: d,
          reviewedMedFingerprint: fp,
        );

    test('an empty profile asks nothing', () {
      expect(cpReviewReasons(const CareProfileDoc(), DateTime(2027), medFingerprint: 'x'), isEmpty);
    });

    test('every 90 days: not at 89, at 90', () {
      final DateTime start = DateTime(2026, 1, 1);
      final CareProfileDoc d = doc(created: start);
      expect(cpReviewReasons(d, start.add(const Duration(days: 89)), medFingerprint: 'x'), isEmpty);
      final List<CpReviewReason> r = cpReviewReasons(d, start.add(const Duration(days: 90)), medFingerprint: 'x');
      expect(r.map((CpReviewReason x) => x.kind), <CpReviewKind>[CpReviewKind.ninetyDays]);
    });

    test('a review restarts the count', () {
      final CareProfileDoc d = doc(created: DateTime(2026, 1, 1), reviewed: DateTime(2026, 6, 1));
      expect(cpReviewReasons(d, DateTime(2026, 7, 1), medFingerprint: 'x'), isEmpty);
    });

    test('a birthday since the last look prompts once, with her age; a birthday before the profile existed does not', () {
      final CareProfileDoc d = doc(created: DateTime(2026, 5, 1), reviewed: DateTime(2026, 5, 1), m: 6, d: 10);
      expect(cpReviewReasons(d, DateTime(2026, 6, 9), medFingerprint: 'x'), isEmpty);
      final List<CpReviewReason> r = cpReviewReasons(d, DateTime(2026, 6, 10), medFingerprint: 'x', child: 'Mia', childAge: 8);
      expect(r.single.kind, CpReviewKind.birthday);
      expect(r.single.text, contains('Mia is 8'));
      final CareProfileDoc after = doc(created: DateTime(2026, 5, 1), reviewed: DateTime(2026, 6, 11), m: 6, d: 10);
      expect(cpReviewReasons(after, DateTime(2026, 7, 1), medFingerprint: 'x'), isEmpty);
      // Created after this year's birthday: this year's does not count.
      final CareProfileDoc late = doc(created: DateTime(2026, 7, 1), m: 6, d: 10);
      expect(cpReviewReasons(late, DateTime(2026, 8, 1), medFingerprint: 'x'), isEmpty);
    });

    test('a 29 February birthday falls on 1 March in a common year', () {
      expect(cpLastBirthday(2, 29, DateTime(2027, 3, 1)), DateTime(2027, 3, 1));
      expect(cpLastBirthday(2, 29, DateTime(2027, 2, 28)), DateTime(2026, 3, 1));
      expect(cpLastBirthday(2, 29, DateTime(2028, 2, 29)), DateTime(2028, 2, 29));
    });

    test('a medicine change prompts; no baseline yet prompts nothing', () {
      final DateTime t = DateTime(2026, 2, 1);
      expect(cpReviewReasons(doc(created: t, fp: 'old'), t, medFingerprint: 'new').single.kind, CpReviewKind.medicineChange);
      expect(cpReviewReasons(doc(created: t, fp: 'same'), t, medFingerprint: 'same'), isEmpty);
      expect(cpReviewReasons(doc(created: t), t, medFingerprint: 'new'), isEmpty);
    });

    test('the medicine fingerprint moves for a list change and not for a dose given', () {
      CareDoc withMeds(List<CareMedication> m) => CareDoc(meds: m);
      const CareMedication a = CareMedication(id: 'm1', name: 'Inhaler', kind: MedKind.prn, gapHours: 4);
      final String base = cpMedicineFingerprint(withMeds(<CareMedication>[a]));
      final CareMedication dosed = a.copyWith(doses: <CareDose>[CareDose(at: DateTime.utc(2026), byId: 'mom', byName: 'Sam')]);
      expect(cpMedicineFingerprint(withMeds(<CareMedication>[dosed])), base);
      expect(cpMedicineFingerprint(withMeds(<CareMedication>[a.copyWith(dose: '2 puffs')])), isNot(base));
      expect(cpMedicineFingerprint(withMeds(<CareMedication>[a.copyWith(retired: true)])), isNot(base));
      expect(cpMedicineFingerprint(withMeds(<CareMedication>[a, const CareMedication(id: 'm2', name: 'Other')])), isNot(base));
    });
  });

  group('the doctor sheet', () {
    final DateTime now = DateTime(2026, 11, 14, 10);
    final CareProfileDoc doc = CareProfileDoc(entries: <CpEntry>[
      _e('s', CareProfilePart.safe, 'Peanuts: hives', title: 'Allergy'),
      _e('x', CareProfilePart.everyday, 'Oats', title: 'Breakfast'),
      _e('h', CareProfilePart.health, 'Asthma since 2024'),
      _e('m', CareProfilePart.moods, 'Tired at four'),
      _e('b1', CareProfilePart.helps, 'Quiet', title: 'Hard day'),
      _e('b2', CareProfilePart.helps, 'A walk', title: 'Hard day', by: 'dad', name: 'Alex'),
    ]);
    const CareDoc meds = CareDoc(meds: <CareMedication>[
      CareMedication(id: 'm1', name: 'Inhaler', dose: '2 puffs', kind: MedKind.prn, gapHours: 4, note: 'blue'),
      CareMedication(id: 'm2', name: 'Old', retired: true),
    ]);
    const LocalEmergencyCard card = LocalEmergencyCard(
      allergies: <String>['Peanuts'],
      doctor: EcDoctor(name: 'Dr Okoye', phone: '555-0100'),
    );

    test('has Keep-safe, the card, the medicines as written and who wrote each line; nothing locked by default', () {
      final String t = cpDoctorSheetText(childName: 'Mia', doc: doc, meds: meds, card: card, now: now);
      expect(t, contains('Mia: sheet for the doctor'));
      expect(t, contains('Allergy: Peanuts: hives (written by Sam, 14 Nov 2026)'));
      expect(t, contains('Allergies: Peanuts'));
      expect(t, contains('Doctor: Dr Okoye, 555-0100'));
      expect(t, contains('Inhaler | 2 puffs | when needed, with the 4 hour gap set in Medications | blue'));
      expect(t, isNot(contains('Old')));
      expect(t, isNot(contains('Oats')));
      expect(t, isNot(contains('Asthma')));
      expect(t, isNot(contains('Tired')));
      expect(t.toLowerCase(), contains('the app adds no medical advice'));
    });

    test('health history and moods appear only when asked AND the PIN was given', () {
      const CpSheetOptions all = CpSheetOptions(everyday: true, helps: true, health: true, moods: true);
      final String locked = cpDoctorSheetText(childName: 'Mia', doc: doc, options: all, now: now);
      expect(locked, contains('Oats'));
      expect(locked, isNot(contains('Asthma')));
      expect(locked, isNot(contains('Tired')));
      final String open = cpDoctorSheetText(childName: 'Mia', doc: doc, options: all, unlocked: true, now: now);
      expect(open, contains('Asthma since 2024'));
      expect(open, contains('Tired at four'));
    });

    test('where two versions differ, both are on the sheet and it says so', () {
      final String t = cpDoctorSheetText(childName: 'Mia', doc: doc, options: const CpSheetOptions(helps: true), now: now);
      expect(t, contains('Quiet'));
      expect(t, contains('A walk'));
      expect(t, contains('the grown-ups wrote this differently'));
    });

    test('plan photos are listed by the label a grown-up typed, never opened', () {
      final String t = cpDoctorSheetText(childName: 'Mia', doc: doc, planPhotoLabels: <String>['Asthma plan'], now: now);
      expect(t, contains('Asthma plan'));
    });

    test('it computes no dose: no number appears that a grown-up did not write', () {
      final String t = cpDoctorSheetText(childName: 'Mia', doc: const CareProfileDoc(), meds: const CareDoc(meds: <CareMedication>[
        CareMedication(id: 'm1', name: 'Vitamin D'),
      ]), now: now);
      expect(t, contains('Vitamin D'));
      expect(RegExp(r'\bmg\b|\bml\b', caseSensitive: false).hasMatch(t), isFalse);
    });
  });

  group("a teen's own sheet", () {
    final CareProfileDoc off = CareProfileDoc(entries: <CpEntry>[_e('s', CareProfilePart.safe, 'Peanuts'), _e('x', CareProfilePart.everyday, 'Oats')]);

    test('is off by default and gives nothing at any age', () {
      for (int age = 0; age < 20; age++) {
        expect(cpTeenSheet(off, null, age: age), isNull, reason: '$age');
      }
    });

    test('when the flag is on it is for 13 to 17 only and holds Keep-safe and medicines, nothing else', () {
      final CareProfileDoc on = off.copyWith(teenPreview: true);
      expect(cpTeenSheet(on, null, age: 12), isNull);
      expect(cpTeenSheet(on, null, age: 18), isNull);
      expect(cpTeenSheet(on, null, age: null), isNull);
      final s = cpTeenSheet(on, null, age: 14)!;
      expect(s.entries.map((CpEntry e) => e.text), <String>['Peanuts']);
    });
  });

  group('a tolerant read', () {
    test('garbage reads as an empty profile, never a crash', () {
      for (final Object? j in <Object?>[null, 7, 'x', <Object?>[], <String, Object?>{'entries': 'no'}, <String, Object?>{'entries': <Object?>[7, null, <String, Object?>{}]}]) {
        expect(CareProfileDoc.fromJson(j).entries, isEmpty);
      }
    });

    test('a round trip keeps everything, and an entry in a part that holds no entries is dropped', () {
      final CareProfileDoc d = CareProfileDoc(
        entries: <CpEntry>[_e('a', CareProfilePart.safe, 'Allergy', title: 'Nuts').copyWith(revisions: <CpRevision>[
          CpRevision(at: DateTime.utc(2026), byId: 'mom', byName: 'Sam', title: 'Nuts', text: 'old'),
        ])],
        people: <CpPerson>[const CpPerson(id: 'p1', name: 'Nan', kind: CpPersonKind.carer, grants: <CareProfilePart, CpGrant>{CareProfilePart.safe: CpGrant()})],
        birthMonth: 6, birthDay: 10, teenPreview: true,
      );
      final CareProfileDoc back = CareProfileDoc.fromJson(d.toJson());
      expect(back.toJson(), d.toJson());
      expect(CpEntry.tryFromJson(<String, Object?>{'id': 'z', 'part': 'heads', 'text': 'x', 'at': '2026-01-01T00:00:00Z'}), isNull);
    });
  });

  group('plan photos', () {
    test('only a JPEG or a PNG is an image', () {
      expect(cpLooksLikeImage(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])), isTrue);
      expect(cpLooksLikeImage(Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0])), isTrue);
      expect(cpLooksLikeImage(Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8])), isFalse);
      expect(cpLooksLikeImage(Uint8List(3)), isFalse);
    });
  });
}
