// OLIVE BRANCH — the one sentence under the guardian home's hero (the
// prototype's stateLine). No longer UNVERIFIED — verified by CI
// (client/test/guardian_hub_parity_test.dart). MASTERFILE §8.2.
//
// A pure function. When a caller has a real sentence about her ("Ivy is just home
// from school") that wins. Otherwise the home falls back to one honest line, in the
// prototype's priority: the tablet is not connected, else we are offline, else the
// part of her day. It never invents a mood, a place or a status it was not given
// (P3, and the "never fake success" rule): with nothing known it says what it does
// not know.
import 'calendar_day_logic.dart' show dayPartLabel;

/// [sentence] is a caller-supplied sentence, if any. [connected] is whether this
/// home has a live family behind it; [dayPart] is `/now`'s day-part kind, null when
/// it could not be loaded.
String guardianStateLine({
  required String childName,
  String? sentence,
  required bool connected,
  String? dayPart,
}) {
  final String? given = sentence?.trim();
  if (given != null && given.isNotEmpty) return given;
  if (!connected) {
    return '$childName’s tablet isn’t connected yet. What you set up here stays on this phone.';
  }
  if (dayPart == null || dayPart.isEmpty) {
    return 'You are offline, so $childName’s time is not showing. It will when you reconnect.';
  }
  return 'It is ${dayPartLabel(dayPart).toLowerCase()} for $childName.';
}
