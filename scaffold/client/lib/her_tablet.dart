// OLIVE BRANCH — what the grown-up's phone knows about HER TABLET, in one place, in plain words. Pure logic and one reader;
// headless in CI (client/test/her_tablet_test.dart). MASTERFILE 8.13.
//
// One question, three honest answers, used by the "Her tablet" screen, the home's banner and its one sentence:
//   connected     the phone's own list holds a tablet that was really handed its credential (pairing_protocol.dart records a
//                 tablet only when the credential leaves the phone), with the name and when the phone last met it;
//   notConnected  the list was read in FULL and holds none (never a guess from "nothing came back");
//   unknown       the list could not be read (a damaged store): the screen says it cannot tell right now and offers nothing
//                 that would act on a list it has not seen.
// Never a code, a status number or a certificate in a sentence the grown-up reads.
import 'pairing_protocol.dart' show PairedKid;
import 'pairing_records.dart';
import 'pairing_trust.dart';

enum HerTabletStatus { connected, notConnected, unknown }

class HerTabletView {
  const HerTabletView.connected(PairedKid this.kid, {this.lastSeenMs, this.addedMs, this.others = 0})
      : status = HerTabletStatus.connected,
        toldNothing = false;
  const HerTabletView.notConnected({this.toldNothing = false})
      : status = HerTabletStatus.notConnected,
        kid = null,
        lastSeenMs = null,
        addedMs = null,
        others = 0;
  const HerTabletView.unknown()
      : status = HerTabletStatus.unknown,
        kid = null,
        lastSeenMs = null,
        addedMs = null,
        toldNothing = false,
        others = 0;

  final HerTabletStatus status;

  /// The tablet shown (the most recently connected one when, rarely, more than one is listed).
  final PairedKid? kid;

  /// When this phone last met the tablet (a connect, an unlock, a renewal), and when it was connected. Null = not recorded.
  final int? lastSeenMs, addedMs;

  /// How many OTHER tablets are listed beside [kid] (siblings share a phone): said as "and one more", never hidden.
  final int others;

  /// Not connected, but this phone disconnected a tablet earlier that has not been told yet (it finds out the next time it
  /// meets this phone). Said plainly so a grown-up is not surprised when the tablet still looks connected.
  final bool toldNothing;

  bool get isConnected => status == HerTabletStatus.connected;
}

/// Reads the list and the trust book into one view. Never throws: a store that cannot be read is [HerTabletStatus.unknown].
Future<HerTabletView> readHerTablet({required PairedKidsRepository kids, TrustBook? trust}) async {
  try {
    final PairedKidsLoad l = await kids.loadChecked();
    if (l.kids.isEmpty) {
      if (!l.verifiablyEmpty) return const HerTabletView.unknown();
      bool told = false;
      try {
        told = trust != null && (await trust.revokedKeyList()).isNotEmpty;
      } catch (_) {}
      return HerTabletView.notConnected(toldNothing: told);
    }
    final PairedKid k = l.kids.last;
    int? seen, added;
    try {
      for (final TrustedDevice d in await (trust?.devices() ?? Future<List<TrustedDevice>>.value(const <TrustedDevice>[]))) {
        if (d.certId == k.certId) {
          seen = d.lastContactMs;
          added = d.addedAtMs;
        }
      }
    } catch (_) {}
    return HerTabletView.connected(k, lastSeenMs: seen ?? k.issuedAtMs, addedMs: added ?? k.issuedAtMs, others: l.kids.length - 1);
  } catch (_) {
    return const HerTabletView.unknown();
  }
}

/// "just now", "today", "yesterday", "3 days ago": plain, never a clock time or a date a child could misread.
String lastSeenWords(int? ms, int nowMs) {
  if (ms == null) return 'not seen yet';
  final Duration d = Duration(milliseconds: nowMs - ms < 0 ? 0 : nowMs - ms);
  if (d.inMinutes < 2) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} minutes ago';
  if (d.inHours < 24) return d.inHours == 1 ? 'an hour ago' : '${d.inHours} hours ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}

/// The big status sentence for [view].
String herTabletHeadline(HerTabletView v, String childName) => switch (v.status) {
      HerTabletStatus.connected => "$childName's tablet is connected",
      HerTabletStatus.notConnected => "$childName's tablet is not connected yet",
      HerTabletStatus.unknown => "Can't tell right now",
    };
