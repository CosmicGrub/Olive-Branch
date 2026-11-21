// OLIVE BRANCH - who is on the call, in the open (MASTERFILE section 5.15, 8.14; ISS-099, ISS-100).
//
// A call used to remember ONE name ("the other person"): a second person joining overwrote the first, a third was
// never shown, and nobody was told when anyone arrived or left. That is the wrong shape for a family call and an unsafe
// one for a child: somebody could be on the line without anyone in the room knowing.
//
// The rules this file holds, pure and tested:
//   * The roster is a LIST of the other participants. Joining adds one, leaving removes that one; nobody replaces anybody.
//   * Every join and every leave becomes one plain sentence ("Dad joined", "Mum left"), shown on screen and announced
//     to the screen reader. An observer who is only watching is named too ("Gran is watching").
//   * The line that stays on screen counts EVERYONE present, you included and observers included: "3 people here,
//     1 watching". There is no way for the count to leave anyone out.
//   * An unnamed participant is "Someone", never an internal id.
// The words state facts about presence. They carry no advice and no judgement.

/// One other person on the call.
class CallParticipant {
  const CallParticipant({required this.id, required this.name, this.observer = false});

  /// The engine's identifier for this participant (never shown).
  final String id;

  /// The display name the person joined with; empty when none was given.
  final String name;

  /// True for somebody who can watch and listen but not speak or show video (the observer tier, section 17.3).
  final bool observer;

  /// What the screen calls this person.
  String get label => name.trim().isEmpty ? kUnnamedParticipant : name.trim();

  @override
  bool operator ==(Object other) =>
      other is CallParticipant && other.id == id && other.name == name && other.observer == observer;
  @override
  int get hashCode => Object.hash(id, name, observer);
}

/// Used when a participant has no display name. Never an id.
const String kUnnamedParticipant = 'Someone';

/// [list] with [p] added, or replaced in place if the same id is already there (a name arriving late). Nobody is dropped.
List<CallParticipant> rosterWith(List<CallParticipant> list, CallParticipant p) {
  final int i = list.indexWhere((CallParticipant x) => x.id == p.id);
  if (i < 0) return <CallParticipant>[...list, p];
  return <CallParticipant>[...list]..[i] = p;
}

/// [list] without the participant whose id is [id]. Everyone else stays.
List<CallParticipant> rosterWithout(List<CallParticipant> list, String id) =>
    <CallParticipant>[for (final CallParticipant x in list) if (x.id != id) x];

/// The plain sentences for everything that changed between [before] and [after], joins first, then leaves.
List<String> rosterAnnouncements(List<CallParticipant> before, List<CallParticipant> after) {
  final Set<String> was = <String>{for (final CallParticipant p in before) p.id};
  final Set<String> is_ = <String>{for (final CallParticipant p in after) p.id};
  return <String>[
    for (final CallParticipant p in after)
      if (!was.contains(p.id)) p.observer ? '${p.label} is watching' : '${p.label} joined',
    for (final CallParticipant p in before)
      if (!is_.contains(p.id)) p.observer ? '${p.label} stopped watching' : '${p.label} left',
  ];
}

/// The count line that stays on screen: everyone present, [you] included, observers included and counted.
String rosterCountLine(List<CallParticipant> others) {
  final int total = others.length + 1;
  final int watching = others.where((CallParticipant p) => p.observer).length;
  if (total == 1) return 'Just you here';
  final String base = '$total people here';
  return watching == 0 ? base : '$base, $watching watching';
}

/// A spoken form of who is here, for the screen reader's description of the count line.
String rosterSpokenLine(List<CallParticipant> others) {
  if (others.isEmpty) return rosterCountLine(others);
  final String names = others.map((CallParticipant p) => p.observer ? '${p.label} (watching)' : p.label).join(', ');
  return '${rosterCountLine(others)}. With you: $names';
}
