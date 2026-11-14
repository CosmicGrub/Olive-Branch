// OLIVE BRANCH — who gets which tile from suites B and C. No longer UNVERIFIED —
// verified by CI (client/test/rhythm_voice_gate_test.dart).
//
// One pure decision: given what the family-structure model says (her derived
// [ChildView]: her age band and the tiles and features it turned on), the
// guardian's suite switches and what a guardian has authored, which Rhythm and
// Voice tiles does she see? This file REUSES `deriveChildView`'s answer; it does
// not compute an age band or a feature of its own, and it never edits
// family_structure_logic.dart (whose suite keys are pinned to the TS twin's
// golden vectors). Rhythm and Voice have their own two switches, kept in their
// own documents and read here as a plain map.
//
// FAIL-CLOSED TO FIVE. With no family snapshot the age comes from `yearsOld`;
// when that is missing, negative or not a number she is treated as FIVE (the
// youngest age these suites are for), never as older. The youngest band (3 to 4,
// "three big pictures") gets nothing from these suites: its home has no More and
// no settings, by the age-band design.
//
// WHAT THE MODEL DECIDES, AND WHAT IT DOES NOT. The model decides the band
// (nothing below 5), whether the More hub exists for her at all, and — for the
// packing buddy — whether she sleeps in more than one home (`features
// ['packingBuddy']`, which also honours the model's own `weeks` suite switch).
// With no snapshot the structure is unknown, so the packing buddy stays off
// rather than guessing, unless a guardian set the local "two homes" fallback. Content a guardian has to AUTHOR (a routine, a bag list,
// a place plan, helpers) is shown only once it exists, so she is never handed an
// empty screen.
library;

import 'family_structure_logic.dart' show ChildView, bandForYears;
import 'rhythm_logic.dart';
import 'voice_logic.dart';

/// The two switches a guardian owns for these suites. Rhythm: absent means on.
/// Voice: absent means OFF until a guardian turns it on.
const List<String> rhythmVoiceSuiteKeys = <String>['rhythm', 'voice'];

/// What is on for her right now.
class RhythmVoiceTiles {
  const RhythmVoiceTiles({
    this.routine = false, this.firstThen = false, this.packingBuddy = false, this.newPlace = false,
    this.weather = false, this.worryBox = false, this.helpers = false, this.symbols = false,
  });
  final bool routine, firstThen, packingBuddy, newPlace;
  final bool weather, worryBox, helpers, symbols;

  bool get anyRhythm => routine || firstThen || packingBuddy || newPlace;
  bool get anyVoice => weather || worryBox || helpers || symbols;
  bool get any => anyRhythm || anyVoice;

  static const RhythmVoiceTiles none = RhythmVoiceTiles();
}

/// Her age in whole years, failing closed to five.
int ageOrFive(Object? yearsOld) =>
    yearsOld is num && yearsOld.isFinite && yearsOld >= 0 ? yearsOld.floor() : 5;

/// The band these suites act on: the model's own when it has one, else the one
/// for [yearsOld] (fail-closed to five).
String bandFor({ChildView? view, Object? yearsOld}) => view?.band ?? bandForYears(ageOrFive(yearsOld));

RhythmVoiceTiles tilesFor({
  ChildView? view,
  Object? yearsOld,
  bool rhythmOn = true,
  bool voiceOn = false,
  bool feelingsOn = true,
  bool twoHomesSetting = false,
  Routine? routine,
  FirstThenBoard? board,
  PackingList packing = const PackingList(),
  PlacePlan? place,
  List<Helper> helpers = const <Helper>[],
}) {
  final String band = bandFor(view: view, yearsOld: yearsOld);
  // The youngest band has no More hub and no suites of this kind; a model that
  // says there is no More tile for her means these tiles have nowhere to live.
  final bool hasRoom = band != 't34' && (view == null || view.hasTile('more'));
  if (!hasRoom) return RhythmVoiceTiles.none;
  // With a family snapshot the model alone decides. Without one the structure is
  // unknown, so only a guardian's own local "two homes" setting (off by default)
  // can turn the packing buddy on.
  final bool twoHomes = view != null ? view.features['packingBuddy'] == true : twoHomesSetting;
  return RhythmVoiceTiles(
    routine: rhythmOn && (routine?.steps.isNotEmpty ?? false),
    firstThen: rhythmOn && board != null,
    packingBuddy: rhythmOn && twoHomes && packing.items.isNotEmpty,
    newPlace: rhythmOn && place != null && !place.isEmpty,
    weather: voiceOn && feelingsOn,
    worryBox: voiceOn,
    helpers: voiceOn && helpersForChild(helpers).isNotEmpty,
    symbols: voiceOn,
  );
}

/// The same suite switches in the shape `deriveChildView` takes (`suites`), so a
/// caller holding one map can pass it to both.
bool suiteSwitch(Map<String, bool>? suites, String key) => suites == null || suites[key] != false;
