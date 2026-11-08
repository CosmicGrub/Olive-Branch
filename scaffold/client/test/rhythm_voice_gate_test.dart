// OLIVE BRANCH — who gets which Rhythm and Voice tile: the family-structure
// model's age band and More hub, the guardian's switches, and what exists.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_voice_gate.dart';
import 'package:olive_client/voice_logic.dart';

const FamilyStructure oneHome = FamilyStructure(
    homes: <Home>[Home(id: 'h1', name: 'Mom', childSleeps: true)]);
const FamilyStructure twoHomes = FamilyStructure(homes: <Home>[
  Home(id: 'h1', name: 'Mom', childSleeps: true),
  Home(id: 'h2', name: 'Dad', childSleeps: true),
]);

ChildView view(FamilyStructure s, String band, {Map<String, bool>? suites}) =>
    deriveChildView(s, band, suites, null, today: '2026-11-08');

Routine routine() => addStep(const Routine(), newStep('a', 'bath'));
FirstThenBoard board() => makeBoard(boardCard('bath'), boardCard('play'));
PackingList packing() => addPackItem(const PackingList(), newPackItem('o', 'owl'));
PlacePlan place() => makePlan('Dad\'s', <PlaceStop>[newStop('s', 'door', 'The door')], const <String>[]);
List<Helper> helpers({bool yes = true}) => <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: yes)];

RhythmVoiceTiles all(ChildView? v, {Object? years, bool rhythmOn = true, bool voiceOn = true}) => tilesFor(
    view: v, yearsOld: years, rhythmOn: rhythmOn, voiceOn: voiceOn, routine: routine(), board: board(),
    packing: packing(), place: place(), helpers: helpers());

void main() {
  group('age: fail-closed to five', () {
    test('missing, negative, NaN and infinite ages are treated as five, never older', () {
      for (final Object? bad in <Object?>[null, -1, double.nan, double.infinity, 'ten', <int>[]]) {
        expect(ageOrFive(bad), 5, reason: '$bad');
        expect(bandFor(yearsOld: bad), 't57', reason: '$bad');
      }
      expect(ageOrFive(9.7), 9);
      expect(ageOrFive(0), 0);
    });

    test('the band comes from the model when there is one, else from the age', () {
      expect(bandFor(view: view(oneHome, 't812'), yearsOld: 5), 't812');
      expect(bandFor(yearsOld: 4), 't34');
      expect(bandFor(yearsOld: 9), 't812');
    });
  });

  group('the youngest band gets nothing', () {
    test('three-to-four: no tiles at all, whatever a guardian wrote', () {
      expect(all(view(twoHomes, 't34')).any, isFalse);
      expect(all(null, years: 4).any, isFalse);
      expect(all(null, years: 3).any, isFalse);
      expect(all(null, years: 0).any, isFalse);
    });

    test('a model that gives her no More tile leaves these tiles nowhere to live', () {
      final ChildView v = view(twoHomes, 't57');
      final ChildView noMore = ChildView(
          band: v.band, homeVariant: v.homeVariant, tiles: v.tiles.where((String t) => t != 'more').toList(),
          heroPersonId: null, wordsBesidePictures: false, speakEveryWord: true, plainGreeting: false,
          places: const <ChildPlace>[], features: v.features, areas: v.areas, ladder: v.ladder, birthdayVisible: true);
      expect(v.hasTile('more'), isTrue);
      expect(noMore.hasTile('more'), isFalse);
      expect(all(noMore).any, isFalse);
    });
  });

  group('five and up', () {
    test('with the model, a five-year-old with two homes gets every tile once content exists', () {
      final RhythmVoiceTiles t = all(view(twoHomes, 't57'));
      expect(t.routine && t.firstThen && t.packingBuddy && t.newPlace, isTrue);
      expect(t.weather && t.worryBox && t.helpers && t.symbols, isTrue);
    });

    test('with no model and no age she is treated as five: picture tiles on, structure-led ones off', () {
      final RhythmVoiceTiles t = all(null);
      expect(t.weather && t.worryBox && t.symbols && t.routine, isTrue);
      expect(t.packingBuddy, isFalse, reason: 'the structure is unknown, so no guessing about two homes');
    });

    test('the packing buddy follows the model: one home, or the weeks suite off, means no tile', () {
      expect(all(view(oneHome, 't57')).packingBuddy, isFalse);
      expect(all(view(twoHomes, 't57', suites: <String, bool>{'weeks': false})).packingBuddy, isFalse);
      expect(all(view(twoHomes, 't57', suites: <String, bool>{'weeks': true})).packingBuddy, isTrue);
    });

    test('older bands keep them (the suites are for her growing years)', () {
      expect(all(view(twoHomes, 't812')).any, isTrue);
      expect(all(view(twoHomes, 't13')).any, isTrue);
    });
  });

  group('the guardian\'s switches', () {
    test('rhythm off removes every Rhythm tile and no Voice tile', () {
      final RhythmVoiceTiles t = all(view(twoHomes, 't57'), rhythmOn: false);
      expect(t.anyRhythm, isFalse);
      expect(t.anyVoice, isTrue);
    });

    test('voice off removes every Voice tile and no Rhythm tile', () {
      final RhythmVoiceTiles t = all(view(twoHomes, 't57'), voiceOn: false);
      expect(t.anyVoice, isFalse);
      expect(t.anyRhythm, isTrue);
    });

    test('both off: nothing', () {
      expect(all(view(twoHomes, 't57'), rhythmOn: false, voiceOn: false).any, isFalse);
    });

    test('the switch map reads like the model\'s suites: absent means on, only false means off', () {
      expect(suiteSwitch(null, 'rhythm'), isTrue);
      expect(suiteSwitch(<String, bool>{}, 'voice'), isTrue);
      expect(suiteSwitch(<String, bool>{'rhythm': false}, 'rhythm'), isFalse);
      expect(suiteSwitch(<String, bool>{'rhythm': false}, 'voice'), isTrue);
      expect(rhythmVoiceSuiteKeys, <String>['rhythm', 'voice']);
      for (final String k in rhythmVoiceSuiteKeys) {
        expect(suiteKeys.contains(k), isFalse, reason: 'the model\'s own pinned suite keys are untouched');
      }
    });
  });

  group('Voice starts OFF until a guardian turns it on', () {
    test('with nothing set up, no Voice tile shows for any age five and up, with or without the model', () {
      for (final ChildView? v in <ChildView?>[view(twoHomes, 't57'), view(oneHome, 't812'), view(twoHomes, 't13'), null]) {
        final RhythmVoiceTiles t = tilesFor(view: v, yearsOld: 9);
        expect(t.anyVoice, isFalse);
        expect(t.weather || t.worryBox || t.helpers || t.symbols, isFalse);
      }
      // Even with a helper written, the switch decides.
      expect(tilesFor(view: view(twoHomes, 't57'), helpers: helpers()).helpers, isFalse);
    });

    test('a guardian turning it on shows weather, worry box and symbols (age and structure gates still apply)', () {
      final RhythmVoiceTiles t = tilesFor(view: view(twoHomes, 't57'), voiceOn: true);
      expect(t.weather && t.worryBox && t.symbols, isTrue);
      expect(tilesFor(view: view(twoHomes, 't34'), voiceOn: true).any, isFalse, reason: 'the youngest band still gets nothing');
      expect(tilesFor(yearsOld: 4, voiceOn: true).any, isFalse);
    });

    test('Rhythm is not affected by the Voice default', () {
      expect(tilesFor(view: view(twoHomes, 't57'), routine: routine()).routine, isTrue);
    });
  });

  group('the packing buddy "two homes" fallback (a guardian\'s local setting)', () {
    test('with no family snapshot it appears only when the setting is on, a bag list exists and Rhythm is on', () {
      expect(tilesFor(yearsOld: 7, packing: packing()).packingBuddy, isFalse, reason: 'off by default');
      expect(tilesFor(yearsOld: 7, packing: packing(), twoHomesSetting: true).packingBuddy, isTrue);
      expect(tilesFor(yearsOld: 7, twoHomesSetting: true).packingBuddy, isFalse, reason: 'no list, nothing to show');
      expect(tilesFor(yearsOld: 7, packing: packing(), twoHomesSetting: true, rhythmOn: false).packingBuddy, isFalse);
      expect(tilesFor(yearsOld: 4, packing: packing(), twoHomesSetting: true).packingBuddy, isFalse,
          reason: 'the youngest band still gets nothing');
    });

    test('with a snapshot the model alone decides: the setting cannot override it', () {
      expect(tilesFor(view: view(oneHome, 't57'), packing: packing(), twoHomesSetting: true).packingBuddy, isFalse);
      expect(tilesFor(view: view(twoHomes, 't57'), packing: packing()).packingBuddy, isTrue);
    });
  });

  group('what a guardian has not written does not appear', () {
    test('no routine, board, bag, place or helpers means no tile for them; weather, worry and symbols stay', () {
      final RhythmVoiceTiles t = tilesFor(view: view(twoHomes, 't57'), voiceOn: true);
      expect(t.routine || t.firstThen || t.packingBuddy || t.newPlace || t.helpers, isFalse);
      expect(t.weather && t.worryBox && t.symbols, isTrue);
    });

    test('an empty routine or an empty place is not content', () {
      final RhythmVoiceTiles t = tilesFor(view: view(twoHomes, 't57'), routine: const Routine(), place: const PlacePlan());
      expect(t.routine, isFalse);
      expect(t.newPlace, isFalse);
    });

    test('a helper who has not said yes does not make the tile appear', () {
      expect(tilesFor(view: view(twoHomes, 't57'), voiceOn: true, helpers: helpers(yes: false)).helpers, isFalse);
      expect(tilesFor(view: view(twoHomes, 't57'), voiceOn: true, helpers: helpers()).helpers, isTrue);
    });
  });
}
