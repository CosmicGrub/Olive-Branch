// OLIVE BRANCH - the allergy field has THREE states, and an empty list is not "none". UNVERIFIED on a real device until the hardware pass.
//
// An allergy list that is empty can mean two very different things: nobody ever asked, or somebody asked and
// the answer was no. Reading the first as the second ("None on file", "No allergies written down") tells a
// sitter, a school or a paramedic that a child is safe to feed anything. This file is the one place that
// decides what each case says, so the card screen, the spoken card, the local card, the meds screen and the
// doctor-sheet export can never disagree:
//
//   unknown        nothing recorded, nothing confirmed. The default. Says [kAllergiesNotRecorded] and nothing else.
//   confirmedNone  a named guardian confirmed "no known allergies" on a date. Says so, with the name and the date.
//   entries        what a guardian wrote, in their own words. A confirmation never coexists with entries.
//
// The words are structure, not advice: they state what is and is not recorded. They are listed for clinician and
// counsel sign-off before a store release (docs/planning/OPEN-DECISIONS.md), like every other fixed phrase.
//
// Pure: no I/O, no widgets.

/// What an unrecorded allergy field says, everywhere. Neutral: it does not say "none", "no known" or "clear".
const String kAllergiesNotRecorded = 'Not recorded';

/// "No known allergies" was asked and answered, by a named guardian, on a date.
class AllergyNone {
  const AllergyNone({required this.by, required this.on});

  /// The guardian's name as they gave it.
  final String by;

  /// The calendar date (YYYY-MM-DD) of the confirmation.
  final String on;

  /// A confirmation needs a name and a real-looking date; anything less is not a confirmation.
  bool get isComplete => by.trim().isNotEmpty && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(on.trim());

  Map<String, Object?> toJson() => <String, Object?>{'by': by, 'on': on};

  /// Tolerant: anything that is not a complete confirmation reads as no confirmation (so the field falls back to
  /// "Not recorded", never to "none").
  static AllergyNone? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? by = j['by'], on = j['on'];
    if (by is! String || on is! String) return null;
    final AllergyNone c = AllergyNone(by: by.trim(), on: on.trim());
    return c.isComplete ? c : null;
  }

  @override
  bool operator ==(Object other) => other is AllergyNone && other.by == by && other.on == on;
  @override
  int get hashCode => Object.hash(by, on);
}

enum AllergyState { unknown, confirmedNone, entries }

/// The state, derived (never stored), so it cannot contradict the data: entries win over a confirmation, and an
/// incomplete confirmation does not count.
AllergyState allergyState(List<String> entries, AllergyNone? none) {
  if (entries.any((String e) => e.trim().isNotEmpty)) return AllergyState.entries;
  if (none != null && none.isComplete) return AllergyState.confirmedNone;
  return AllergyState.unknown;
}

/// The line the card and the meds screen show.
String allergyDisplay(List<String> entries, AllergyNone? none, {String separator = ', '}) =>
    switch (allergyState(entries, none)) {
      AllergyState.entries => <String>[for (final String e in entries) if (e.trim().isNotEmpty) e.trim()].join(separator),
      AllergyState.confirmedNone => 'None. Confirmed by ${none!.by.trim()} on ${none.on.trim()}',
      AllergyState.unknown => kAllergiesNotRecorded,
    };

/// The sentence read aloud (and printed on the doctor sheet), first on the card.
String allergySpoken(List<String> entries, AllergyNone? none) => switch (allergyState(entries, none)) {
      AllergyState.entries =>
        'Allergies: ${<String>[for (final String e in entries) if (e.trim().isNotEmpty) e.trim()].join('. ')}. ',
      AllergyState.confirmedNone => 'Allergies: none. Confirmed by ${none!.by.trim()} on ${none.on.trim()}. ',
      AllergyState.unknown => 'Allergies: ${kAllergiesNotRecorded.toLowerCase()}. ',
    };

/// The one-line export form (the doctor sheet): "Allergies: ...".
String allergyExportLine(List<String> entries, AllergyNone? none) {
  final AllergyState s = allergyState(entries, none);
  return 'Allergies: ${s == AllergyState.entries ? <String>[for (final String e in entries) if (e.trim().isNotEmpty) e.trim()].join('; ') : allergyDisplay(entries, none)}';
}

/// Parses the server card's optional confirmation (`allergyNoneConfirmed: {by, on}`), when a server sends one.
AllergyNone? allergyNoneFromServer(Map<String, dynamic> card) => AllergyNone.tryFromJson(card['allergyNoneConfirmed']);
