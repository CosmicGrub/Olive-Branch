// OLIVE BRANCH — family sync, the hand-carried update ("road E" of the design): a short sealed text one grown-up
// copies and the other pastes, over any messenger, with no server and no shared Wi-Fi. UNVERIFIED on a device; pure
// Dart, runs headless in CI. Spec: docs/planning/FAMILY-SYNC-DESIGN.md sections 4.1 and 5.4 (first slice, "S4" road E).
//
// WHAT TRAVELS. Sealed events (family_sync_event.dart) plus a short summary of what the sender holds, all sealed once
// more under the guardian key GK, so whoever carries the text (a messenger app, a clipboard manager, a backup) sees
// only ciphertext: not the events, not the stream ids, not the senders. The only plain parts are a version label, the
// key epoch and the text prefix. A child device has no GK and cannot open one.
//
// SIZE. Not padded (the design pads events, not bundles). An update is bounded: at most [kBundleMaxEvents] events and
// about 240 KiB of events; when there is more, `more` says so and the sender shares again. Pasting more than
// [kBundleMaxTextChars] characters is refused before any work is done.
//
// THE SEAL ALONE DOES NOT SAY WHO SENT IT. It proves "someone holding GK made this", and a grown-up who has left may
// still hold an old GK. The events inside are each signed by their own device, which is what matters for the record.
// The sender's header (`from`, and `have`, the summary of what they hold) is therefore signed too: Ed25519 by the
// sending device over the family, the key epoch, `from` and `have` ([bundleHeaderMessage]). An update whose header does
// not verify is refused whole and changes nothing, so a former grown-up cannot make this phone believe the other phone
// holds something it does not (which would silently stall sharing). What stays true: a captured genuine update can be
// replayed under an old key, which shows an OLDER summary (a phone only ever holds more over time), so the worst case
// is a repeat of events already held, or "Both phones have this card." turning back into "This phone has the shared
// card." until the next update. Only a listed grown-up's phone is remembered as a peer.
import 'dart:convert';
import 'dart:typed_data';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart' show DeviceKey, b64, unb64;
import 'family_keys.dart';
import 'family_ledger.dart' show bytesEqual, decodeValue, encodeValue, hexOf;
import 'family_ledger_state.dart';
import 'family_sync_engine.dart';

const String kBundleLabel = 'olive-update-v1';
const String kBundleSigLabel = 'olive-update-sig-v1';
const String kBundlePrefix = 'OLIVE-UPDATE-1.';
const int kBundleMaxEvents = 200;
const int kBundleMaxTextChars = 2 * 1024 * 1024;

class SyncBundleOut {
  const SyncBundleOut(this.text, this.count, this.more);

  /// The text to copy. Empty when there was nothing the other phone lacks.
  final String text;
  final int count;
  final bool more;
}

class SyncBundleIn {
  const SyncBundleIn.ok(this.ingest, this.fromHex) : reason = null;
  const SyncBundleIn.no(this.reason)
      : ingest = null,
        fromHex = null;
  final SyncIngest? ingest;
  final String? fromHex;

  /// 'text' (not an update at all), 'size', 'no_key' (not sealed for a key this phone holds), 'seal' (damaged or not
  /// from this family), 'shape', 'sender' (the sender's signed header does not verify).
  final String? reason;
}

Uint8List _u32(int v) => Uint8List.fromList(<int>[(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);

/// The bytes the sending device signs: this family, the key epoch, who is sending and the canonical encoding of what
/// they say they hold. Public so tests can build a forged header and show it is refused.
Uint8List bundleHeaderMessage(List<int> fid, int epoch, List<int> from, List<int> haveEncoded) =>
    cat(<List<int>>[lv(utf8.encode(kBundleSigLabel)), lv(fid), _u32(epoch), lv(from), lv(haveEncoded)]);

/// Builds an update for [peerHex]'s phone (the others' last summary is used when [peerHex] is null and exactly one is
/// known; otherwise everything is offered). Never throws; an empty [SyncBundleOut.text] means "nothing new".
Future<SyncBundleOut> exportBundle(SyncEngine engine, {String? peerHex, bool force = false}) async {
  if (!engine.ring.guardianDevice || engine.ring.gkEpochs.isEmpty) return const SyncBundleOut('', 0, false);
  final Map<String, SyncSummary> peers = engine.peers;
  final String? who = peerHex ?? (peers.length == 1 ? peers.keys.first : null);
  final SyncSummary? peer = who == null ? null : peers[who];
  final ({List<Uint8List> wires, bool more}) pick = engine.eventsFor(peer, maxEvents: kBundleMaxEvents);
  // Nothing new for them: still worth sending when they have never told us what they hold (so they learn what we do).
  if (pick.wires.isEmpty && !force && peer != null) return const SyncBundleOut('', 0, false);
  final int epoch = engine.ring.gkEpochs.last;
  final Uint8List outer = cat(<List<int>>[lv(utf8.encode(kBundleLabel)), _u32(epoch)]);
  final List<Object?> have = engine.summary().toValue();
  final Uint8List sig = await engine.device.sign(bundleHeaderMessage(engine.fid, epoch, engine.device.publicKey, encodeValue(have)));
  final Uint8List plain = encodeValue(<String, Object?>{
    'v': 1,
    'from': engine.device.publicKey,
    'have': have,
    'sig': sig,
    'events': pick.wires,
  });
  final Uint8List sealed = await guardianSeal(engine.ring, epoch, plain, aad: outer);
  return SyncBundleOut(kBundlePrefix + b64(cat(<List<int>>[outer, sealed])), pick.wires.length, pick.more);
}

/// Reads pasted text. Whitespace anywhere is ignored (messengers wrap lines). Hostile or damaged text yields a
/// reason, never an exception, and changes nothing.
Future<SyncBundleIn> importBundle(SyncEngine engine, String text, {required LedgerState state}) async {
  try {
    final String t = text.replaceAll(RegExp(r'\s+'), '');
    if (t.length > kBundleMaxTextChars) return const SyncBundleIn.no('size');
    if (!t.startsWith(kBundlePrefix)) return const SyncBundleIn.no('text');
    final Uint8List raw = unb64(t.substring(kBundlePrefix.length));
    final Uint8List label = lv(utf8.encode(kBundleLabel));
    if (raw.length < label.length + 4 + 28 || !bytesEqual(raw.sublist(0, label.length), label)) return const SyncBundleIn.no('text');
    final int epoch = (raw[label.length] << 24) | (raw[label.length + 1] << 16) | (raw[label.length + 2] << 8) | raw[label.length + 3];
    if (!engine.ring.guardianDevice || engine.ring.gk(epoch) == null) return const SyncBundleIn.no('no_key');
    final Uint8List outer = Uint8List.fromList(raw.sublist(0, label.length + 4));
    final Uint8List? plain = await guardianOpen(engine.ring, epoch, raw.sublist(outer.length), aad: outer);
    if (plain == null) return const SyncBundleIn.no('seal');
    final Object? v = decodeValue(plain);
    if (v is! Map<String, Object?> || v.length != 5 || v['v'] != 1 || !bytesEqual(encodeValue(v), plain)) return const SyncBundleIn.no('shape');
    final Object? from = v['from'], have = v['have'], sig = v['sig'], events = v['events'];
    final SyncSummary? summary = SyncSummary.fromValue(have);
    if (from is! Uint8List || from.length != 32 || sig is! Uint8List || sig.length != 64 || summary == null ||
        events is! List || events.length > kBundleMaxEvents) {
      return const SyncBundleIn.no('shape');
    }
    // The header must be signed by the device it names, before anything is taken from the update.
    if (!await DeviceKey.verify(from, bundleHeaderMessage(engine.fid, epoch, from, encodeValue(have)), sig)) {
      return const SyncBundleIn.no('sender');
    }
    final List<Uint8List> wires = <Uint8List>[];
    for (final Object? e in events) {
      if (e is! Uint8List) return const SyncBundleIn.no('shape');
      wires.add(e);
    }
    final SyncIngest r = await engine.ingest(wires, state: state);
    final String fromHex = hexOf(from);
    // Remember what they hold only if they are a listed grown-up's phone and not this one.
    final bool member = state.ok && state.devices.any((LedgerDevice d) => d.kind == 'guardian' && bytesEqual(d.key, from));
    if (member && fromHex != engine.selfHex) await engine.notePeer(fromHex, summary);
    return SyncBundleIn.ok(r, member ? fromHex : null);
  } catch (_) {
    return const SyncBundleIn.no('text');
  }
}
