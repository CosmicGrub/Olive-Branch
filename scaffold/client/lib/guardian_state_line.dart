// OLIVE BRANCH — the one sentence under the guardian home's hero (the
// prototype's stateLine). No longer UNVERIFIED — verified by CI
// (client/test/guardian_hub_parity_test.dart). MASTERFILE §8.2.
//
// A pure function. When a caller has a real sentence about her ("Ivy is just home
// from school") that wins. Otherwise the home falls back to one honest line: the
// part of her day when this home has a live family behind it, else whether her
// tablet is paired with this phone. It never invents a mood, a place or a status it
// was not given (P3, and the "never fake success" rule).
//
// "Not connected yet" is a claim about a list, so it is made ONLY when that list was
// read in full and is verifiably empty (ISS-059): [tabletPaired] is tri-state, true
// (the paired-tablet list holds one), false (read, and empty) or null (could not be
// read, or not read yet). With null the line says nothing at all rather than guess.
import 'calendar_day_logic.dart' show dayPartLabel;

/// [sentence] is a caller-supplied sentence, if any. [connected] is whether this
/// home has a live family behind it; [dayPart] is `/now`'s day-part kind, null when
/// it could not be loaded. [tabletPaired] is the on-phone paired-tablet list's
/// verdict (tri-state, see the header) and [serverTabletPresent] the server's, when
/// this home asked it (null = not asked or not answered). Returns null when there is
/// nothing honest to say: the caller then shows no line.
String? guardianStateLine({
  required String childName,
  String? sentence,
  required bool connected,
  String? dayPart,
  bool? tabletPaired,
  bool? serverTabletPresent,
}) {
  final String? given = sentence?.trim();
  if (given != null && given.isNotEmpty) return given;
  final bool tabletKnown = tabletPaired == true || serverTabletPresent == true;
  // Verifiably no tablet anywhere: the phone's list was read and is empty, and (with a live family) the server
  // says so too. A live family whose server has not answered is NOT verifiably empty.
  final bool verifiablyNone = tabletPaired == false && (!connected || serverTabletPresent == false);
  if (verifiablyNone) {
    return '$childName’s tablet isn’t connected yet. What you set up here stays on this phone.';
  }
  if (connected) {
    if (dayPart == null || dayPart.isEmpty) {
      return 'You are offline, so $childName’s time is not showing. It will when you reconnect.';
    }
    return 'It is ${dayPartLabel(dayPart).toLowerCase()} for $childName.';
  }
  if (tabletKnown) return '$childName’s tablet is paired with this phone.';
  return null;
}
