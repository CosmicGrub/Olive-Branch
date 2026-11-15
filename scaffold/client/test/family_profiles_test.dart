// OLIVE BRANCH — the permission-profile table of the village design (4.1 to 4.4), checked cell by cell. Verified by CI,
// headless. The table is DATA in lib/family_profiles.dart; these tests are generated from it, so a cell that drifts
// from its meaning fails here.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_profiles.dart';

void main() {
  group('the table, cell by cell', () {
    for (final Preset p in Preset.values) {
      if (p == Preset.helperPage) continue;
      for (final Capability c in Capability.values) {
        final Cell cell = kProfileTable[p]![c]!;
        test('${p.name} / C${c.number}: ${cell.fixed ? 'fixed ${cell.on ? 'on' : 'off'}' : 'set (default ${cell.on ? 'on' : 'off'})'}', () {
          final MemberProfile base = MemberProfile.defaults(p,
              fromMs: p == Preset.visit ? 1000 : null, untilMs: p == Preset.visit ? 1000 + kMsPerDay : null);
          expect(base.violation(), isNull, reason: 'the preset\'s own defaults are always allowed');
          expect(base.has(c), cell.on);
          final Set<Capability> flipped = base.caps.toSet();
          if (cell.on) {
            flipped.remove(c);
          } else {
            flipped.add(c);
          }
          final MemberProfile other = MemberProfile(
              preset: p, caps: flipped, fromMs: base.fromMs, untilMs: base.untilMs);
          if (cell.fixed) {
            expect(other.violation(), isNotNull, reason: 'a fixed cell cannot be flipped by the proposer');
          } else {
            expect(other.violation(), isNull, reason: 'a settable cell can be flipped');
          }
        });
      }
    }

    test('the Helper page has no capabilities at all and is never a member', () {
      for (final Capability c in Capability.values) {
        expect(kProfileTable[Preset.helperPage]![c]!.available, isFalse);
      }
      expect(MemberProfile.defaults(Preset.helperPage).violation(), 'helper-page-has-no-member');
      expect(tierOf(Preset.helperPage), MemberTier.helperPage);
    });
  });

  group('who can ever have what (by design, at any preset)', () {
    test('only a parent preset can have C11 (start a welcome) or C13 (pause a carer); only a parent can have C12', () {
      for (final Preset p in <Preset>[Preset.trustedCarer, Preset.visit, Preset.viewOnly]) {
        for (final Capability c in <Capability>[Capability.startWelcome, Capability.voteWelcome, Capability.pauseCarer]) {
          expect(kProfileTable[p]![c]!.on && kProfileTable[p]![c]!.available, isFalse, reason: '${p.name} C${c.number}');
          expect(kProfileTable[p]![c]!.fixed, isTrue);
        }
      }
    });

    test('no carer preset can ever have expenses (C5) or settings (C6): P6 and the family\'s own settings', () {
      for (final Preset p in <Preset>[Preset.trustedCarer, Preset.visit, Preset.viewOnly]) {
        expect(kProfileTable[p]![Capability.expenses]!.on, isFalse);
        expect(kProfileTable[p]![Capability.expenses]!.fixed, isTrue);
        expect(kProfileTable[p]![Capability.settings]!.on, isFalse);
        expect(kProfileTable[p]![Capability.settings]!.fixed, isTrue);
      }
    });

    test('a parent with limits keeps the hard floors: history, calendar, emergency card, own PIN, a voice, pause', () {
      for (final Capability c in <Capability>[
        Capability.history, Capability.calendar, Capability.emergencyCard, Capability.ownPin, Capability.voteWelcome,
        Capability.pauseCarer,
      ]) {
        final Cell cell = kProfileTable[Preset.parentWithLimits]![c]!;
        expect(cell.fixed && cell.on, isTrue, reason: 'C${c.number}');
      }
    });
  });

  group('reach is computed, never chosen', () {
    test('parent tier is Parent; a trusted carer with defaults is Act; view only is Look', () {
      expect(MemberProfile.defaults(Preset.parent).reach, Reach.parent);
      expect(MemberProfile.defaults(Preset.parentWithLimits).reach, Reach.parent);
      expect(MemberProfile.defaults(Preset.trustedCarer).reach, Reach.act);
      expect(MemberProfile.defaults(Preset.viewOnly).reach, Reach.look);
    });

    test('a Visit is Act while any of C4, C6, C8, C9, C10 is on, and Look only when all are off', () {
      MemberProfile visit(Iterable<Capability> caps) =>
          MemberProfile(preset: Preset.visit, caps: caps, fromMs: 0, untilMs: kMsPerDay);
      const List<Capability> base = <Capability>[Capability.emergencyCard, Capability.ownPin];
      expect(visit(<Capability>[...base, Capability.unlockPlay]).reach, Reach.act);
      expect(visit(<Capability>[...base, Capability.messageChild]).reach, Reach.act);
      expect(visit(<Capability>[...base, Capability.careNotes]).reach, Reach.act, reason: 'the Notes rule, the stricter reading');
      expect(visit(<Capability>[...base, Capability.calendar]).reach, Reach.look);
      expect(visit(base).reach, Reach.look);
    });
  });

  group('time boxes and children', () {
    test('a Visit needs a time box of at most 14 days; the end must be after the start', () {
      expect(MemberProfile.defaults(Preset.visit).violation(), 'visit-needs-time-box');
      expect(MemberProfile.defaults(Preset.visit, fromMs: 0, untilMs: 15 * kMsPerDay).violation(), 'visit-too-long');
      expect(MemberProfile.defaults(Preset.visit, fromMs: 0, untilMs: 14 * kMsPerDay).violation(), isNull);
      expect(MemberProfile.defaults(Preset.trustedCarer, fromMs: 5, untilMs: 5).violation(), 'time-box-backwards');
    });

    test('a Parent has every child; a carer may have a chosen list but not an empty or repeated one', () {
      expect(MemberProfile.defaults(Preset.parent, children: <String>['a']).violation(), 'parent-has-all-children');
      expect(MemberProfile.defaults(Preset.trustedCarer, children: <String>[]).violation(), 'children-empty');
      expect(MemberProfile.defaults(Preset.trustedCarer, children: <String>['a', 'a']).violation(), 'children-duplicate');
      expect(MemberProfile.defaults(Preset.trustedCarer, children: <String>['a', 'b']).violation(), isNull);
    });
  });

  group('the stored form is strict', () {
    test('a profile round-trips', () {
      final MemberProfile p = MemberProfile.defaults(Preset.trustedCarer, children: <String>['x']);
      final MemberProfile? back = MemberProfile.fromValue(p.toValue());
      expect(back!.toValue(), p.toValue());
      expect(back.reach, p.reach);
    });

    test('capabilities must be strictly ascending and known; extra keys are refused', () {
      final Map<String, Object?> v = MemberProfile.defaults(Preset.parent).toValue();
      expect(MemberProfile.fromValue(<String, Object?>{...v, 'caps': <Object?>[2, 1]}), isNull);
      expect(MemberProfile.fromValue(<String, Object?>{...v, 'caps': <Object?>[1, 1]}), isNull);
      expect(MemberProfile.fromValue(<String, Object?>{...v, 'caps': <Object?>[14]}), isNull);
      expect(MemberProfile.fromValue(<String, Object?>{...v, 'extra': 1}), isNull);
      expect(MemberProfile.fromValue(<String, Object?>{...v, 'preset': 'godMode'}), isNull);
    });
  });
}
