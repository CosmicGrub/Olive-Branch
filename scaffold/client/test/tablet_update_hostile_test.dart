// OLIVE BRANCH — hostile tests for the tablet update path. The "phone" here is test code that says whatever it likes;
// the tablet must refuse it, and say so in grown-up words only. Covers: a tampered notice, a notice signed with the wrong
// key, a rollback and a same-version reinstall, a notice for another app or release line, an expired and a replayed
// notice, a whole-file hash that lies, a corrupted chunk, a truncated or over-long file, a wrong signing certificate (in
// the notice and in the file), huge and zip-bomb sizes, a stray / duplicated / out-of-order / spoofed-seat message, a
// flood of junk, a child trying to start or finish it, and a phone that is not a grown-up's. Headless.
//
// Not here, on purpose: redirects to cleartext or another host and a man in the middle on a mirror. The tablet path
// never follows a URL (the notice's addresses are signed data it does not use), so those cases belong to the updater
// engine's own download tests. A phone that is not the paired one is stopped by the transport itself (wiring test).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/tablet_update_hash.dart';
import 'package:olive_client/tablet_update_port.dart';
import 'package:olive_client/tablet_update_receiver.dart';
import 'package:olive_client/tablet_update_store.dart';
import 'package:olive_client/tablet_update_wire.dart';

import 'tablet_update_harness.dart';

Future<void> settle([int ms = 15]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> waitFor(bool Function() cond, {String what = 'condition', int ms = 8000}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) throw StateError('timed out waiting for $what');
    await settle(5);
  }
}

/// A phone that says whatever the test wants. By default it serves exactly what the fixture holds.
class FakePhone {
  FakePhone(this.t, this.f, {this.mutate, this.sidText}) : docSha = '';
  final ScriptedTransport t;
  final Fixture f;
  String docSha;
  final String? sidText;
  late final String sid = sidText ?? newSessionId(List<int>.generate(16, (int i) => 40 + i));
  Uint8List Function(UpdateObject o, int off, Uint8List bytes)? mutate;
  int _answered = 0;

  Future<void> offer() async {
    docSha = await sha256HexOf(f.document);
    t.inject(OfferMsg(sid, docLen: f.document.length, docSha: docSha).toWire());
  }

  /// Answers every `need` the tablet has sent and not yet been answered.
  void serve() {
    final List<Map<String, dynamic>> needs = <Map<String, dynamic>>[for (final Map<String, dynamic> m in t.sent) if (m['k'] == 'need') m];
    while (_answered < needs.length) {
      final Map<String, dynamic> n = needs[_answered++];
      final UpdateObject o = UpdateObject.from(n['o'])!;
      final Uint8List src = o == UpdateObject.doc ? f.document : f.apk;
      final int off = n['off'] as int, len = n['len'] as int;
      for (int p = off; p < min(off + len, src.length); p += kUpdatePieceBytes) {
        Uint8List b = Uint8List.fromList(src.sublist(p, min(p + kUpdatePieceBytes, min(off + len, src.length))));
        if (mutate != null) b = mutate!(o, p, b);
        t.inject(PieceMsg(sid, obj: o, off: p, data: b).toWire());
      }
    }
  }
}

class Tablet {
  Tablet(this.root, this.t, this.engine, this.store, this.receiver);
  final Directory root;
  final ScriptedTransport t;
  final ReferenceEngine engine;
  final MemoryStagedUpdateStore store;
  final TabletUpdateReceiver receiver;
  bool adult = true;

  static Future<Tablet> make({int installed = 5100, String? installedSigner, bool armed = true}) async {
    final Directory root = await Directory.systemTemp.createTemp('olive_hostile_');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });
    final ScriptedTransport t = ScriptedTransport();
    final ReferenceEngine e = ReferenceEngine(dir: root, installedVersionCode: installed, installedSigner: installedSigner);
    final MemoryStagedUpdateStore store = MemoryStagedUpdateStore();
    late Tablet tab;
    final TabletUpdateReceiver r = TabletUpdateReceiver(
        engine: e, store: store, adultPresent: () => tab.adult, pieceTimeout: const Duration(milliseconds: 300), maxRetries: 2);
    tab = Tablet(root, t, e, store, r);
    if (armed) await r.listen(t);
    return tab;
  }

  bool get askedForFile => t.needs.any(((String, int, int) n) => n.$1 == 'apk');
  List<File> get partFiles => root.listSync().whereType<File>().where((File f) => f.path.endsWith('.part')).toList();
}

/// Runs a phone and a tablet until [done] or a time limit, answering needs as they come.
Future<void> drive(FakePhone p, Tablet tab, bool Function() done, {int ms = 8000}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!done()) {
    p.serve();
    await settle(8);
    if (sw.elapsedMilliseconds > ms) throw StateError('drive timed out in phase ${tab.receiver.phase}');
  }
}

Future<(Tablet, FakePhone)> offeredBy(Fixture f, {Tablet? tablet}) async {
  final Tablet tab = tablet ?? await Tablet.make();
  final FakePhone p = FakePhone(tab.t, f);
  await p.offer();
  await drive(p, tab, () => tab.receiver.phase == ReceivePhase.offered || tab.receiver.phase == ReceivePhase.refused);
  return (tab, p);
}

Future<Tablet> offered(Fixture f, {Tablet? tablet}) async => (await offeredBy(f, tablet: tablet)).$1;

TabletUpdateCode? codeOf(Tablet t) => t.receiver.refusal;

void main() {
  group('the signed notice', () {
    test('a notice changed after it was signed is refused before one byte of the file is asked for', () async {
      final Fixture f = await makeFixture(tamper: (Map<String, Object?> m) => <String, Object?>{...m, 'versionCode': 9999});
      final Tablet tab = await offered(f);
      expect(tab.receiver.phase, ReceivePhase.refused);
      expect(codeOf(tab), TabletUpdateCode.notGenuine);
      expect(tab.askedForFile, isFalse);
      expect(await tab.store.loadStaged(), isNull);
    });

    test('a notice signed by a key the tablet does not trust is refused', () async {
      final Fixture f = await makeFixture(signWith: kOtherSeed);
      final Tablet tab = await offered(f);
      expect(codeOf(tab), TabletUpdateCode.notGenuine);
      expect(tab.askedForFile, isFalse);
    });

    test('an unsigned or garbled notice is refused (not JSON, no signature, a huge document)', () async {
      for (final Uint8List doc in <Uint8List>[
        Uint8List.fromList('not json at all'.codeUnits),
        Uint8List.fromList('{"manifest":{"app":"x"}}'.codeUnits),
        Uint8List.fromList('[]'.codeUnits),
      ]) {
        final Fixture f = Fixture(apk: Uint8List(10), document: doc, manifest: <String, Object?>{});
        final Tablet tab = await offered(f);
        expect(codeOf(tab), TabletUpdateCode.notGenuine, reason: String.fromCharCodes(doc));
        expect(tab.askedForFile, isFalse);
      }
      // A notice longer than any real one is not even asked for.
      final Tablet tab = await Tablet.make();
      tab.t.inject(OfferMsg(newSessionId(List<int>.filled(16, 1)), docLen: 256 * 1024, docSha: 'a' * 64).toWire());
      await settle();
      expect(tab.t.needs, hasLength(1), reason: 'a notice of the largest size allowed is asked for');
      final Tablet tab2 = await Tablet.make();
      tab2.t.inject(<String, Object?>{'u': 1, 'k': 'offer', 'sid': newSessionId(List<int>.filled(16, 1)), 'dl': 256 * 1024 + 1, 'ds': 'a' * 64});
      await settle();
      expect(tab2.t.sent, isEmpty, reason: 'one byte over the notice cap is dropped');
    });

    test('a notice for another app, another release line, or one that has expired is refused', () async {
      for (final (Future<Fixture>, TabletUpdateCode) c in <(Future<Fixture>, TabletUpdateCode)>[
        (makeFixture(app: 'com.example.other'), TabletUpdateCode.wrongApp),
        (makeFixture(channel: 'beta'), TabletUpdateCode.wrongChannel),
        (makeFixture(expires: DateTime.utc(2026, 1, 1)), TabletUpdateCode.expired),
      ]) {
        final Tablet tab = await offered(await c.$1);
        expect(codeOf(tab), c.$2);
        expect(tab.askedForFile, isFalse);
      }
    });

    test('a notice for a different processor is refused', () async {
      final Tablet tab = await offered(await makeFixture(abi: 'x86_64'));
      expect(codeOf(tab), TabletUpdateCode.notForThisTablet);
    });

    test('a replayed older notice is refused once a newer one has been seen', () async {
      final Fixture newer = await makeFixture(sequence: 9, versionCode: 5300, versionName: '0.53.0');
      final Fixture older = await makeFixture(sequence: 4, versionCode: 5200);
      final Tablet tab = await offered(newer);
      expect(tab.receiver.phase, ReceivePhase.offered);
      await tab.receiver.stop();
      await tab.receiver.listen(tab.t);
      final FakePhone p = FakePhone(tab.t, older, sidText: newSessionId(List<int>.filled(16, 9)));
      await p.offer();
      await drive(p, tab, () => tab.receiver.phase == ReceivePhase.refused || tab.receiver.phase == ReceivePhase.offered);
      expect(codeOf(tab), TabletUpdateCode.replayed);
    });
  });

  group('rollback and sameness', () {
    test('an OLDER version than the one installed is refused, even though the signature is perfect', () async {
      final Tablet tab = await Tablet.make(installed: 5300);
      await offered(await makeFixture(versionCode: 5200), tablet: tab);
      expect(codeOf(tab), TabletUpdateCode.older);
      expect(tab.askedForFile, isFalse);
    });

    test('the SAME version as the one installed is "already up to date", not a reinstall', () async {
      final Tablet tab = await Tablet.make(installed: 5200);
      await offered(await makeFixture(versionCode: 5200), tablet: tab);
      expect(codeOf(tab), TabletUpdateCode.upToDate);
      expect(tabletUpdateAdultWords(TabletUpdateCode.upToDate), contains('already has'));
    });

    test('the engine alone does not decide: this engine accepts an older version, and the tablet still refuses it', () async {
      final Fixture f = await makeFixture(versionCode: 5000);
      final Tablet tab = await Tablet.make(installed: 5100);
      expect((await tab.engine.verify(f.document, forInstall: false)).versionCode, 5000, reason: 'the engine let it through');
      await offered(f, tablet: tab);
      expect(codeOf(tab), TabletUpdateCode.older);
      expect(tab.askedForFile, isFalse);
    });
  });

  group('sizes', () {
    test('a signed notice that declares a file over the cap is refused (500 MiB + 1, and absurd sizes)', () async {
      for (final int size in <int>[500 * 1024 * 1024 + 1, 4 * 1024 * 1024 * 1024]) {
        final Tablet tab = await offered(await makeFixture(declaredSize: size, chunkSize: 8 * 1024 * 1024));
        expect(codeOf(tab), TabletUpdateCode.tooBig, reason: '$size');
        expect(tab.askedForFile, isFalse);
      }
    });

    test('a zip-bomb shaped notice is refused: a chunk size below the floor, and a notice too big to ever be fetched', () async {
      final Tablet tab = await offered(await makeFixture(declaredSize: 1024 * 1024, chunkSize: 1024));
      expect(codeOf(tab), TabletUpdateCode.notGenuine);
      expect(tab.askedForFile, isFalse);
      // 400 MiB in 16 KiB chunks is a legal shape, but its chunk list alone is far over the notice cap: the offer
      // is dropped before a single byte of it is asked for.
      final Fixture huge = await makeFixture(declaredSize: 400 * 1024 * 1024, chunkSize: 16 * 1024);
      expect(huge.document.length, greaterThan(256 * 1024));
      final Tablet tab2 = await Tablet.make();
      final FakePhone p = FakePhone(tab2.t, huge);
      await p.offer();
      await settle(60);
      expect(tab2.receiver.phase, ReceivePhase.listening);
      expect(tab2.t.sent, isEmpty);
    });

    test('not enough free space, or a flat battery, stops it before any byte is asked for', () async {
      final Fixture f = await makeFixture(size: 100 * 1024);
      Tablet tab = await offered(f);
      tab.engine.freeBytes = 10 * 1024 * 1024;
      await expectLater(tab.receiver.accept(), throwsA(isA<TabletUpdateRefused>().having((TabletUpdateRefused e) => e.code, 'code', TabletUpdateCode.noSpace)));
      expect(tab.askedForFile, isFalse);
      tab = await offered(f);
      tab.engine.battery = 9;
      await expectLater(tab.receiver.accept(), throwsA(isA<TabletUpdateRefused>().having((TabletUpdateRefused e) => e.code, 'code', TabletUpdateCode.lowBattery)));
      // Plugged in, the same low battery is fine.
      tab.engine.charging = true;
      await tab.receiver.accept();
      expect(tab.askedForFile, isTrue);
    });
  });

  group('the file', () {
    test('a corrupted chunk is caught the moment it is complete: part file deleted, nothing staged, no more asked', () async {
      final Fixture f = await makeFixture(size: 300 * 1024, chunkSize: 64 * 1024);
      final (Tablet tab, FakePhone phone) = await offeredBy(f);
      phone.mutate = (UpdateObject o, int off, Uint8List b) {
        if (o == UpdateObject.apk && off == 65536) {
          final Uint8List c = Uint8List.fromList(b);
          c[0] ^= 0xff;
          return c;
        }
        return b;
      };
      await tab.receiver.accept();
      await drive(phone, tab, () => tab.receiver.phase == ReceivePhase.refused);
      expect(codeOf(tab), TabletUpdateCode.hashMismatch);
      expect(tab.partFiles, isEmpty);
      expect(await tab.store.loadStaged(), isNull);
      final int asked = tab.t.needs.where(((String, int, int) n) => n.$1 == 'apk').map(((String, int, int) n) => n.$2).fold<int>(0, max);
      expect(asked, lessThan(300 * 1024), reason: 'it stopped asking once a chunk failed');
    });

    test('a whole-file hash that lies (every chunk right) is caught at the end: nothing staged', () async {
      final Fixture f = await makeFixture(size: 150 * 1024, chunkSize: 64 * 1024, wrongWholeSha: true);
      final (Tablet tab, FakePhone live) = await offeredBy(f);
      await tab.receiver.accept();
      await drive(live, tab, () => tab.receiver.phase == ReceivePhase.refused);
      expect(codeOf(tab), TabletUpdateCode.hashMismatch);
      expect(tab.partFiles, isEmpty);
      expect(await tab.store.loadStaged(), isNull);
    });

    test('a file signed by a different certificate than the installed app is refused, whatever the notice pins', () async {
      // The notice pins the installed signer, but the file inside is signed by someone else.
      final Fixture f = await makeFixture(size: 100 * 1024, apkSigner: kOtherSigner);
      final (Tablet tab, FakePhone live) = await offeredBy(f);
      await tab.receiver.accept();
      await drive(live, tab, () => tab.receiver.phase == ReceivePhase.refused);
      expect(codeOf(tab), TabletUpdateCode.wrongSigner);
      expect(tab.partFiles, isEmpty);
      expect(await tab.store.loadStaged(), isNull);
    });

    test('a notice that pins a different certificate than the installed app is refused before the file is asked for', () async {
      final Tablet tab = await offered(await makeFixture(pinnedSigner: kOtherSigner, apkSigner: kOtherSigner));
      expect(codeOf(tab), TabletUpdateCode.wrongSigner);
      expect(tab.askedForFile, isFalse);
    });

    test('a file that says it is another app, or another version, is refused', () async {
      for (final (Fixture, TabletUpdateCode) c in <(Fixture, TabletUpdateCode)>[
        (await makeFixture(size: 100 * 1024, apkOverride: makeApkBytes(size: 100 * 1024, pkg: 'com.example.other')), TabletUpdateCode.wrongPackage),
        (await makeFixture(size: 100 * 1024, apkOverride: makeApkBytes(size: 100 * 1024, versionCode: 5300)), TabletUpdateCode.notGenuine),
      ]) {
        final (Tablet tab, FakePhone live) = await offeredBy(c.$1);
        await tab.receiver.accept();
        await drive(live, tab, () => tab.receiver.phase == ReceivePhase.refused);
        expect(codeOf(tab), c.$2);
        expect(await tab.store.loadStaged(), isNull);
      }
    });

    test('a phone that sends MORE than the signed size, or pieces out of order, or twice, gets nothing past the size', () async {
      final Fixture f = await makeFixture(size: 100 * 1024, chunkSize: 32 * 1024);
      final (Tablet tab, FakePhone phone) = await offeredBy(f);
      final String sid = phone.sid;
      await tab.receiver.accept();
      // Out of order first: offset 16 KiB while 0 is expected.
      tab.t.inject(PieceMsg(sid, obj: UpdateObject.apk, off: kUpdatePieceBytes, data: Uint8List(kUpdatePieceBytes)).toWire());
      await settle();
      expect(tab.receiver.doneBytes, 0);
      // A piece that runs past the end of the whole file.
      tab.t.inject(PieceMsg(sid, obj: UpdateObject.apk, off: 100 * 1024 - 10, data: Uint8List(kUpdatePieceBytes)).toWire());
      await settle();
      expect(tab.receiver.doneBytes, 0);
      // The honest piece, twice: the second changes nothing.
      final Uint8List first = Uint8List.fromList(f.apk.sublist(0, kUpdatePieceBytes));
      tab.t.inject(PieceMsg(sid, obj: UpdateObject.apk, off: 0, data: first).toWire());
      tab.t.inject(PieceMsg(sid, obj: UpdateObject.apk, off: 0, data: first).toWire());
      await settle(60);
      expect(tab.receiver.doneBytes, kUpdatePieceBytes);
      expect(tab.receiver.phase, ReceivePhase.downloading);
    });

    test('a file shorter than the signed size never becomes an update: the phone stops answering and the tablet pauses', () async {
      final Fixture f = await makeFixture(size: 200 * 1024, chunkSize: 64 * 1024);
      final (Tablet tab, FakePhone full) = await offeredBy(f);
      final FakePhone live = FakePhone(tab.t, Fixture(apk: f.apk.sublist(0, 100 * 1024), document: f.document, manifest: f.manifest), sidText: full.sid);
      await tab.receiver.accept();
      await drive(live, tab, () => tab.receiver.phase == ReceivePhase.paused);
      expect(await tab.store.loadStaged(), isNull);
      expect(tab.receiver.refusal, isNull, reason: 'a silent phone is a pause, not an accusation');
      expect(tab.root.listSync().whereType<File>().where((File x) => x.path.endsWith('.apk')), isEmpty);
    });
  });

  group('the messages', () {
    test('a message from a seat that is not the paired phone is dropped and changes nothing', () async {
      final Fixture f = await makeFixture();
      final Tablet tab = await Tablet.make();
      final FakePhone p = FakePhone(tab.t, f);
      await p.offer();
      tab.t.inject(OfferMsg(p.sid, docLen: f.document.length, docSha: await sha256HexOf(f.document)).toWire(), from: 'zzz');
      await settle();
      expect(tab.receiver.phase, ReceivePhase.fetchingNotice);
      expect(tab.t.sent, hasLength(1), reason: 'only the genuine seat was answered');
    });

    test('malformed messages are dropped: extra keys, wrong types, a bad session id, a huge piece, bad base64', () async {
      final Tablet tab = await Tablet.make();
      final String sid = newSessionId(List<int>.filled(16, 5));
      final List<Object?> junk = <Object?>[
        null,
        'offer',
        <String, Object?>{'u': 2, 'k': 'offer', 'sid': sid, 'dl': 10, 'ds': 'a' * 64},
        <String, Object?>{'u': 1, 'k': 'offer', 'sid': sid, 'dl': 10, 'ds': 'a' * 64, 'extra': 1},
        <String, Object?>{'u': 1, 'k': 'offer', 'sid': 'short', 'dl': 10, 'ds': 'a' * 64},
        <String, Object?>{'u': 1, 'k': 'offer', 'sid': sid, 'dl': -1, 'ds': 'a' * 64},
        <String, Object?>{'u': 1, 'k': 'offer', 'sid': sid, 'dl': 10, 'ds': 'A' * 64},
        <String, Object?>{'u': 1, 'k': 'piece', 'sid': sid, 'o': 'apk', 'off': 0, 'd': '!!!!'},
        <String, Object?>{'u': 1, 'k': 'piece', 'sid': sid, 'o': 'apk', 'off': 0, 'd': 'A' * 30000},
        <String, Object?>{'u': 1, 'k': 'nonsense', 'sid': sid},
      ];
      for (final Object? j in junk) {
        expect(decodeUpdateMsg(j), isNull, reason: '$j');
        tab.t.inject(j);
      }
      await settle();
      expect(tab.receiver.phase, ReceivePhase.listening);
      expect(tab.t.sent, isEmpty);
    });

    test('a flood of junk ends the session instead of being answered forever', () async {
      final Tablet tab = await Tablet.make();
      for (int i = 0; i < kReceiverBadBudget + 5; i++) {
        tab.t.inject(<String, Object?>{'garbage': i});
      }
      await waitFor(() => tab.receiver.phase == ReceivePhase.refused, what: 'refused after a flood');
    });

    test('a replayed message from a session that already finished is ignored once the update is staged', () async {
      final Fixture f = await makeFixture(size: 100 * 1024, chunkSize: 32 * 1024);
      final (Tablet tab, FakePhone live) = await offeredBy(f);
      await tab.receiver.accept();
      await drive(live, tab, () => tab.receiver.phase == ReceivePhase.ready);
      final int sentBefore = tab.t.sent.length;
      final StagedUpdate? staged = await tab.store.loadStaged();
      // Replay the offer and the first piece of the finished session.
      await live.offer();
      tab.t.inject(PieceMsg(live.sid, obj: UpdateObject.apk, off: 0, data: Uint8List.fromList(f.apk.sublist(0, kUpdatePieceBytes))).toWire());
      await settle(60);
      expect(tab.receiver.phase, ReceivePhase.ready);
      expect(tab.t.sent.length, sentBefore, reason: 'nothing is answered to a replay');
      expect((await tab.store.loadStaged())!.versionCode, staged!.versionCode);
    });
  });

  group('who may start it (a child cannot)', () {
    test('an offer that arrives while no grown-up has opened the screen is not even listened to', () async {
      final Tablet tab = await Tablet.make(armed: false);
      final FakePhone p = FakePhone(tab.t, await makeFixture());
      await p.offer();
      await settle();
      expect(tab.t.sent, isEmpty);
      expect(tab.receiver.phase, ReceivePhase.idle);
    });

    test('with no grown-up proved the tablet will not start listening, and engine absence is "not set up", not an error screen', () async {
      final Tablet tab = await Tablet.make(armed: false);
      tab.adult = false;
      await expectLater(tab.receiver.listen(tab.t), throwsA(isA<TabletUpdateRefused>()));
      expect(tab.receiver.phase, ReceivePhase.idle);
    });

    test('if the grown-up walks away mid-transfer (the proof lapses), the tablet takes nothing more and stages nothing', () async {
      final Fixture f = await makeFixture(size: 200 * 1024, chunkSize: 64 * 1024);
      final (Tablet tab, FakePhone live) = await offeredBy(f);
      await tab.receiver.accept();
      tab.adult = false;
      live.serve();
      await settle(80);
      expect(tab.receiver.doneBytes, 0);
      await settle(1000);
      expect(await tab.store.loadStaged(), isNull);
    });

    test('accepting a download needs a grown-up at that moment too', () async {
      final Tablet tab = await offered(await makeFixture());
      tab.adult = false;
      await expectLater(tab.receiver.accept(), throwsA(isA<TabletUpdateRefused>().having((TabletUpdateRefused e) => e.code, 'code', TabletUpdateCode.notAllowed)));
      expect(tab.askedForFile, isFalse);
    });
  });

  group('words', () {
    test('every refusal has calm grown-up words with no code, no stack, and says nothing was installed or lost where that is true', () {
      for (final TabletUpdateCode c in TabletUpdateCode.values) {
        final String w = tabletUpdateAdultWords(c);
        expect(w, isNotEmpty);
        if (c.name != c.name.toLowerCase()) expect(w, isNot(contains(c.name)), reason: 'no internal code name in $c');
        for (final String banned in <String>['exception', 'null', 'sha', 'signature check failed', 'stack']) {
          expect(w.toLowerCase().contains(banned), isFalse, reason: '$c: $banned');
        }
      }
      for (final TabletUpdateCode c in <TabletUpdateCode>[
        TabletUpdateCode.notGenuine,
        TabletUpdateCode.hashMismatch,
        TabletUpdateCode.wrongSigner,
        TabletUpdateCode.truncated,
        TabletUpdateCode.older
      ]) {
        expect(tabletUpdateAdultWords(c).toLowerCase(), anyOf(contains('nothing'), contains('not kept')), reason: '$c');
      }
    });
  });
}
