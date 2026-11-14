// OLIVE BRANCH — after a pairing: settle in, keeping watch, the refusal lock, hostile names, and the hash-chained
// history. UNVERIFIED until CI runs it; clocks are injected. Design: docs/planning/PERSISTENT-QR-PAIRING.md layers 4-5.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/pairing_trust.dart';

Uint8List _k(int f) => Uint8List.fromList(List<int>.filled(32, f));

class _Clock {
  DateTime t = DateTime.utc(2026, 11, 14, 9);
  DateTime call() => t;
  void add(Duration d) => t = t.add(d);
}

Future<(TrustBook, _Clock, MemoryTrustRepository)> _book() async {
  final _Clock c = _Clock();
  final MemoryTrustRepository repo = MemoryTrustRepository();
  return (TrustBook(repo, now: c.call), c, repo);
}

void main() {
  group('settle in', () {
    test('a new device is New for 24 hours by default, then ordinary', () async {
      final (TrustBook b, _Clock c, _) = await _book();
      final TrustedDevice d = (await b.add(certId: 'c1', deviceKey: _k(1), deviceName: 'Ivy tablet', role: PairedRole.child, addedBy: 'Sam'))!;
      expect(d.isNew(c.t.millisecondsSinceEpoch), isTrue);
      expect(d.newTimeLeft(c.t.millisecondsSinceEpoch), const Duration(hours: 24));
      c.add(const Duration(hours: 24));
      expect((await b.devices()).single.isNew(c.t.millisecondsSinceEpoch), isFalse);
    });

    test('the period is the adult setting: none, a day, three days', () async {
      for (final (SettleIn s, Duration d) in <(SettleIn, Duration)>[(SettleIn.none, Duration.zero), (SettleIn.day, const Duration(hours: 24)), (SettleIn.threeDays, const Duration(days: 3))]) {
        final (TrustBook b, _Clock c, _) = await _book();
        await b.setSettleIn(s);
        final TrustedDevice dev = (await b.add(certId: 'c', deviceKey: _k(2), deviceName: 'T', role: PairedRole.child, addedBy: 'Sam'))!;
        expect(dev.newTimeLeft(c.t.millisecondsSinceEpoch), d);
      }
    });

    test('a New grown-up phone cannot approve others; a child device never can', () async {
      final (TrustBook b, _Clock c, _) = await _book();
      await b.add(certId: 'g', deviceKey: _k(3), deviceName: 'Phone', role: PairedRole.grownUp, addedBy: 'Sam');
      await b.add(certId: 'k', deviceKey: _k(4), deviceName: 'Tablet', role: PairedRole.child, addedBy: 'Sam');
      expect(await b.mayApproveOthers('g'), isFalse, reason: 'still New');
      c.add(const Duration(hours: 25));
      expect(await b.mayApproveOthers('g'), isTrue);
      expect(await b.mayApproveOthers('k'), isFalse, reason: 'a child device never approves');
      expect(await b.mayApproveOthers('nobody'), isFalse);
    });
  });

  group('keep watch', () {
    test('the same key keeps the connection and refreshes contact; a different key pauses it', () async {
      final (TrustBook b, _Clock c, _) = await _book();
      await b.add(certId: 'c1', deviceKey: _k(1), deviceName: 'Ivy tablet', role: PairedRole.child, addedBy: 'Sam');
      c.add(const Duration(days: 3));
      expect(await b.observe('c1', _k(1)), TrustStatus.active);
      expect((await b.devices()).single.lastContactMs, c.t.millisecondsSinceEpoch);
      expect(await b.observe('c1', _k(9)), TrustStatus.paused, reason: 'a changed device is never silently trusted');
      expect((await b.devices()).single.status, TrustStatus.paused);
      expect(await b.observe('c1', _k(1)), TrustStatus.paused, reason: 'pausing is sticky until the adult re-approves');
    });

    test('still yours appears at 60 days without contact and goes away once confirmed', () async {
      final (TrustBook b, _Clock c, _) = await _book();
      await b.add(certId: 'c1', deviceKey: _k(1), deviceName: 'T', role: PairedRole.child, addedBy: 'Sam');
      c.add(const Duration(days: 59));
      expect((await b.devices()).single.needsStillYours(c.t.millisecondsSinceEpoch), isFalse);
      c.add(const Duration(days: 1));
      expect((await b.devices()).single.needsStillYours(c.t.millisecondsSinceEpoch), isTrue);
      await b.confirmStillYours('c1');
      expect((await b.devices()).single.needsStillYours(c.t.millisecondsSinceEpoch), isFalse);
    });

    test('stop refuses the key from then on, leaves other devices alone, and cannot be re-added silently', () async {
      final (TrustBook b, _, _) = await _book();
      await b.add(certId: 'c1', deviceKey: _k(1), deviceName: 'One', role: PairedRole.child, addedBy: 'Sam');
      await b.add(certId: 'c2', deviceKey: _k(2), deviceName: 'Two', role: PairedRole.child, addedBy: 'Sam');
      expect(await b.stop('c1'), isTrue);
      expect(await b.isRefused(_k(1)), isTrue);
      expect(await b.observe('c1', _k(1)), isNull);
      expect(await b.observe('c2', _k(2)), TrustStatus.active, reason: 'the other device is still connected');
      expect(await b.add(certId: 'c3', deviceKey: _k(1), deviceName: 'One again', role: PairedRole.child, addedBy: 'Sam'), isNull);
      expect(await b.stop('missing'), isFalse);
    });
  });

  group('refusal lock', () {
    test('a miss locks adding for 10 minutes and then frees it', () {
      final _Clock c = _Clock();
      final AddingLock l = AddingLock(now: c.call);
      expect(l.blockedFor(), isNull);
      l.lock();
      expect(l.blockedFor(), const Duration(minutes: 10));
      c.add(const Duration(minutes: 9, seconds: 59));
      expect(l.blockedFor(), isNotNull);
      c.add(const Duration(seconds: 2));
      expect(l.blockedFor(), isNull);
    });
  });

  group('hostile names', () {
    test('control, bidi and zero-width characters are removed, length is capped, empty becomes Unknown device', () {
      expect(sanitizeDeviceName('Ivy\u202e gnp.exe'), 'Ivy gnp.exe'.replaceAll(' gnp', ' gnp'));
      expect(sanitizeDeviceName('A\u0000B\u200bC\u2066D\u2069'), 'ABCD');
      expect(sanitizeDeviceName('   '), 'Unknown device');
      expect(sanitizeDeviceName(null), 'Unknown device');
      expect(sanitizeDeviceName(42), 'Unknown device');
      expect(sanitizeDeviceName('x' * 100).length, 32);
      expect(sanitizeDeviceName("Ivy's  \n tablet"), "Ivy's tablet");
    });

    test('a hostile name is cleaned on the way into the list', () async {
      final (TrustBook b, _, _) = await _book();
      final TrustedDevice d = (await b.add(certId: 'c', deviceKey: _k(5), deviceName: '\u202eevil\u0007', role: PairedRole.child, addedBy: 'Sam'))!;
      expect(d.name, 'evil');
    });
  });

  group('history', () {
    test('plain words, never key / certificate / fingerprint', () async {
      final (TrustBook b, _, _) = await _book();
      await b.add(certId: 'c1', deviceKey: _k(1), deviceName: 'Ivy tablet', role: PairedRole.child, addedBy: 'Sam');
      await b.note(HistoryKind.refusedOtherFamily);
      await b.note(HistoryKind.refusedMatch);
      await b.stop('c1');
      final List<HistoryEntry> h = (await b.repo.load()).history;
      expect(h.map((HistoryEntry e) => e.text).first, 'Ivy tablet was added.');
      for (final HistoryEntry e in h) {
        for (final String w in <String>['key', 'certificate', 'fingerprint', 'handshake', 'pairing']) {
          expect(e.text.toLowerCase(), isNot(contains(w)), reason: e.text);
        }
      }
    });

    test('the chain detects a removed, reordered, edited or inserted entry', () async {
      final PairingHistory h = PairingHistory();
      for (int i = 0; i < 5; i++) {
        await h.append(HistoryKind.added, 1000 + i, who: 'T$i');
      }
      expect(await h.verify(), isTrue);
      final List<HistoryEntry> e = h.entries;
      expect(await PairingHistory.verifyEntries(<HistoryEntry>[...e.sublist(0, 2), ...e.sublist(3)]), isFalse, reason: 'removed');
      expect(await PairingHistory.verifyEntries(<HistoryEntry>[e[1], e[0], ...e.sublist(2)]), isFalse, reason: 'reordered');
      final HistoryEntry x = e[2];
      final HistoryEntry edited = HistoryEntry(seq: x.seq, atMs: x.atMs, kind: HistoryKind.stopped, who: x.who, prev: x.prev, hash: x.hash);
      expect(await PairingHistory.verifyEntries(<HistoryEntry>[e[0], e[1], edited, e[3], e[4]]), isFalse, reason: 'edited');
      expect(await PairingHistory.verifyEntries(<HistoryEntry>[...e, e[1]]), isFalse, reason: 'duplicated');
      expect(await PairingHistory.verifyEntries(const <HistoryEntry>[]), isTrue);
    });

    test('the book keeps an intact chain across many events', () async {
      final (TrustBook b, _, _) = await _book();
      await b.add(certId: 'c1', deviceKey: _k(1), deviceName: 'A', role: PairedRole.child, addedBy: 'Sam');
      await b.observe('c1', _k(8));
      await b.note(HistoryKind.newCode);
      await b.stop('c1');
      expect(await b.historyIntact(), isTrue);
      expect((await b.repo.load()).history.map((HistoryEntry e) => e.kind), <HistoryKind>[HistoryKind.added, HistoryKind.paused, HistoryKind.newCode, HistoryKind.stopped]);
    });
  });
}
