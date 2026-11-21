// OLIVE BRANCH — backup client, the family's server: the chain and proof agree with the real server's code (golden
// vectors made by server/backup_chain.mjs), a backup goes up in pieces and carries on after a cut-off, a restore waits
// for the server's gate and then verifies everything it is given, and a server (or a stolen sign-in) that tampers is
// noticed here.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart' show ApiException;
import 'package:olive_client/backup_crypto.dart';
import 'package:olive_client/backup_engine.dart';
import 'package:olive_client/backup_restore.dart';
import 'package:olive_client/backup_server.dart';
import 'package:olive_client/backup_service.dart';
import 'package:olive_client/backup_sink.dart';
import 'package:olive_client/backup_words.dart';
import 'package:olive_client/sha256.dart';

import 'support/backup_rig.dart';

const String _vault = '11111111-2222-4333-8444-555555555555';
const String _user = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const String _device = '99999999-8888-4777-8666-555555555555';

Uint8List _unhex(String h) =>
    Uint8List.fromList(<int>[for (int i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

typedef _Fam = ({Rig phone, RecoveryKey key, FakeBackupServer server});

Future<_Fam> _serverFamily() async {
  final FakeBackupServer server = FakeBackupServer()
    ..maxChunk = 2048
    ..deviceOfRestore = _device;
  final Rig phone = await Rig.make(seed: 1, api: server);
  await phone.put(
      'care',
      <String, Object?>{
        'n1': List<String>.generate(40, (int i) => 'a long note number $i with some words in it').join(' / ')
      },
      owner: 'ivy');
  await phone.put('emergencycard', <String, Object?>{'card': <String, Object?>{'v': 3, 'who': 'Mom'}}, owner: 'ivy');
  await phone.put('learn', <String, Object?>{'read': <Object?>['x', 'y']});
  final RecoveryKey key = await phone.svc.setUp();
  await phone.svc.turnOnServer(key: key, pin: '2468');
  return (phone: phone, key: key, server: server);
}

Future<List<ServerVersion>> _list(FakeBackupServer s) async {
  final Map<String, dynamic> listed = await s.send('GET', '/v1/backup/vaults/$_vault/versions',
      query: <String, String>{'after': '0', 'limit': '10'});
  return <ServerVersion>[for (final Object? o in listed['versions'] as List) ServerVersion.fromJson(o)!];
}

Future<({ServerRestore sr, ServerRestoreStatus asked, BackupAuthority auth, Rig fresh})> _ask(_Fam f,
    {BackupAuthority? authority, bool wait = true}) async {
  final Rig fresh = await Rig.make(seed: 4, api: f.server);
  final ServerRestore sr = ServerRestore(api: f.server, state: fresh.state);
  final BackupAuthority auth = authority ?? await deriveBackupAuthority(f.key, BackupKind.family);
  final ServerRestoreStatus asked =
      await sr.request(vaultId: _vault, authority: auth, userId: _user, deviceId: _device, pin: '2468');
  if (wait) f.server.clock = f.server.clock.add(const Duration(hours: 73));
  return (sr: sr, asked: asked, auth: auth, fresh: fresh);
}

void main() {
  group('the wire formats agree with the real server code', () {
    test('the chain value and the restore challenge are byte for byte what server/backup_chain.mjs makes', () {
      final Uint8List prev = _unhex('148de9c5a7a44d19e56cd9ae1a554bf67847afb0c58f6e12fa29ac7ddfca9940');
      final Uint8List blob = _unhex('3e23e8160039594a33894f6564e1b1348bbd7a0088d42c4acb73eeaed59c009d');
      expect(hex(sha256Bytes(Uint8List.fromList(utf8.encode('p')))), hex(prev));
      expect(
          hex(backupChainHash(
              vaultId: _vault, seq: 3, prevChain: prev, blobSha256: blob, size: 1234, manifest: utf8.encode('manifest-bytes'))),
          '4f0de024f411fffa2d7e0014427ebcdd75bb753b564f14614cc1e161e2750b18');
      expect(
          hex(restoreChallengeMessage(
              vaultId: _vault, userId: _user, deviceId: _device, nonce: Uint8List(32)..fillRange(0, 32, 7))),
          '6f6c6976652d6261636b75702d726573746f72652d76310011111111222243338444555555555555aaaaaaaabbbb4ccc8dddeeeeeeeeeeee999999998888477786665555555555550707070707070707070707070707070707070707070707070707070707070707');
    });

    test('a route template fills only safe parts', () {
      expect(backupPath(BackupRoutes.uploadChunk, <String, Object>{'vaultId': _vault, 'uploadId': 'up-1', 'index': 3}),
          '/v1/backup/vaults/$_vault/uploads/up-1/chunks/3');
      expect(() => backupPath(BackupRoutes.upload, <String, Object>{'vaultId': '../x', 'uploadId': 'a'}), throwsArgumentError);
    });
  });

  group('the one sealed file', () {
    test('a staged backup packs and unpacks exactly, and anything else is refused', () async {
      final _Fam f = await _serverFamily();
      expect((await f.phone.svc.backUpNow()).ok, isTrue);
      final Uint8List blob = f.server.blobOf(1);
      final UnpackedBlob u = unpackBackupBlob(blob)!;
      expect(u.header.chunks.length, greaterThan(0));
      expect(u.chunks.length, u.header.chunks.length);
      expect(unpackBackupBlob(Uint8List.fromList(<int>[...blob, 0])), isNull, reason: 'trailing bytes');
      expect(unpackBackupBlob(blob.sublist(0, blob.length - 1)), isNull, reason: 'cut short');
      expect(unpackBackupBlob(Uint8List.fromList(blob)..[0] ^= 1), isNull, reason: 'wrong magic');
      expect(unpackBackupBlob(Uint8List(0)), isNull);
      expect(unpackBackupBlob(Uint8List.fromList(blob)..[blob.length - 5] ^= 1), isNull,
          reason: 'a chunk whose hash is not its name');
    });
  });

  group('backing up to the server', () {
    test('goes up in pieces, the chain and the writer\'s signature verify from the phone\'s side, and the high-water mark is kept',
        () async {
      final _Fam f = await _serverFamily();
      final BackupReport r = await f.phone.svc.backUpNow();
      expect(r.ok, isTrue);
      expect(f.server.versions.length, 1);
      expect(f.server.versions.single.chunkCount, greaterThan(1), reason: 'a real multi piece upload');
      final v = await f.phone.state.vault();
      expect(v.vaultId, _vault);
      expect(v.highSeq, 1);
      expect(v.highChain, f.server.versions.single.chain);
      final BackupAuthority auth = await deriveBackupAuthority(f.key, BackupKind.family);
      final HistoryVerdict verdict = await verifyServerHistory(
          vaultId: _vault, versions: await _list(f.server), authority: auth, kind: BackupKind.family);
      expect(verdict.ok, isTrue);
      expect(verdict.skipped, isEmpty);
    });

    test('the server sees no area name, no key, no word and no readable record', () async {
      final _Fam f = await _serverFamily();
      await f.phone.svc.backUpNow();
      final String seen = <String>[
        latin1.decode(f.server.blobOf(1)),
        latin1.decode(f.server.versions.single.manifest),
        f.server.log.join('\n'),
      ].join();
      for (final String s in <String>['a long note', 'emergencycard', 'learn', 'ivy', ...f.key.words.take(3).map((String w) => ' $w ')]) {
        expect(seen.contains(s), isFalse, reason: s);
      }
    });

    test('several backups chain one to the next and the newest few stay live', () async {
      final _Fam f = await _serverFamily();
      for (int i = 0; i < 5; i++) {
        await f.phone.put('learn', <String, Object?>{'k$i': i});
        await f.phone.svc.backUpNow();
      }
      expect(f.server.seqs, <int>[1, 2, 3, 4, 5]);
      expect(f.server.versions.where((FakeVersion v) => v.state == 'live').length, 3);
    });

    test('a connection that drops partway is carried on: the same upload, only the missing pieces', () async {
      final _Fam f = await _serverFamily();
      f.server.failPutAt = 2;
      final BackupReport first = await f.phone.svc.backUpNow();
      expect(first.ok, isFalse);
      expect(first.sinks.single.code, 'unreachable');
      expect(f.server.versions, isEmpty);
      expect((await f.phone.state.lastFailure(BackupKind.family))!.code, 'unreachable');
      final BackupReport second = await f.phone.svc.backUpNow();
      expect(second.ok, isTrue);
      expect(second.resumed, isTrue);
      expect(second.sinks.single.skipped, 1, reason: 'the piece that arrived is not sent again');
      expect(f.server.versions.length, 1);
      expect(f.server.uploads.length, 1, reason: 'one upload, not two');
    });

    test('another phone committing first makes this one start again on the new history instead of failing', () async {
      final _Fam f = await _serverFamily();
      final Rig other = await Rig.make(seed: 2, api: f.server);
      expect(await other.svc.joinWithSheet(f.key.words.join(' ')), SheetOutcome.ok);
      await other.state.setVault(_vault);
      await other.state.setServerOn(true);
      await other.put('learn', <String, Object?>{'other': 'phone'});
      f.server.beforeCommit = () async {
        f.server.beforeCommit = null;
        await other.svc.backUpNow();
      };
      final BackupReport r = await f.phone.svc.backUpNow();
      expect(r.ok, isTrue);
      expect(f.server.seqs, <int>[1, 2], reason: 'both backups are in, one after the other');
      final BackupAuthority auth = await deriveBackupAuthority(f.key, BackupKind.family);
      expect((await verifyServerHistory(vaultId: _vault, versions: await _list(f.server), authority: auth, kind: BackupKind.family)).ok,
          isTrue);
    });

    test('an answer that is not the version we signed is not believed', () async {
      final _Fam f = await _serverFamily();
      final _Lying liar = _Lying(f.server);
      final Rig p = await Rig.make(seed: 3, api: liar);
      await p.svc.joinWithSheet(f.key.words.join(' '));
      await p.state.setVault(_vault);
      await p.state.setServerOn(true);
      await p.put('learn', <String, Object?>{'a': 1});
      final BackupReport r = await p.svc.backUpNow();
      expect(r.ok, isFalse);
      expect(r.sinks.single.code, 'damaged');
    });

    test('plain words for signed out, feature off, no vault, paused and full', () {
      for (final (int, String, String) c in <(int, String, String)>[
        (401, 'expired', 'signed_out'),
        (404, 'backup_not_enabled', 'not_enabled'),
        (403, 'reach_paused', 'paused'),
        (404, 'vault_not_found', 'no_vault'),
        (507, 'quota_exceeded', 'full'),
        (429, 'rate_limited', 'unreachable'),
        (500, 'x', 'unreachable'),
      ]) {
        expect(backupErrorFrom(ApiException(c.$1, c.$2)).code, c.$3, reason: '${c.$1} ${c.$2}');
      }
      expect(backupErrorFrom(StateError('socket')).code, 'unreachable');
    });

    test('a grown-up with no sign-in never reaches the server', () async {
      final Rig p = await Rig.make();
      await p.svc.setUp();
      expect(p.svc.canUseServer, isFalse);
      await expectLater(p.svc.turnOnServer(key: RecoveryKey.generate(), pin: '2468'), throwsA(isA<BackupSinkException>()));
      expect(await p.svc.sinks(), isEmpty);
    });

    test('turning the server on with a sheet that is not this phone\'s is refused', () async {
      final FakeBackupServer s = FakeBackupServer();
      final Rig p = await Rig.make(api: s);
      await p.svc.setUp();
      await expectLater(p.svc.turnOnServer(key: RecoveryKey.generate(), pin: '2468'),
          throwsA(isA<BackupSinkException>().having((BackupSinkException e) => e.detail, 'detail', 'other_sheet')));
      expect(s.vaultExists, isFalse);
    });

    test('a wrong PIN does not make a vault', () async {
      final FakeBackupServer s = FakeBackupServer();
      final Rig p = await Rig.make(api: s);
      final RecoveryKey k = await p.svc.setUp();
      await expectLater(p.svc.turnOnServer(key: k, pin: '0000'), throwsA(isA<BackupSinkException>()));
      expect(s.vaultExists, isFalse);
      expect(await p.state.serverOn(), isFalse);
    });

    test('a second grown-up joins the family\'s one vault instead of making another', () async {
      final _Fam f = await _serverFamily();
      final Rig second = await Rig.make(seed: 2, api: f.server, guardian: 'dad');
      expect(await second.svc.joinWithSheet(f.key.words.join(' ')), SheetOutcome.ok);
      await second.svc.turnOnServer(key: f.key, pin: '2468');
      expect((await second.state.vault()).vaultId, _vault);
      expect(await second.state.serverOn(), isTrue);
    });
  });

  group('restoring from the server onto a new phone', () {
    Future<void> seedHistory(_Fam f) async {
      await f.phone.svc.backUpNow();
      await f.phone.put('learn', <String, Object?>{'later': 'yes'});
      await f.phone.svc.backUpNow();
    }

    test('the whole path: a signed request, the server\'s wait, then a verified download that restores hash for hash', () async {
      final _Fam f = await _serverFamily();
      await seedHistory(f);
      final Map<String, String> before = await f.phone.hashes();
      final Rig fresh = await Rig.make(seed: 4, api: f.server);
      final ServerRestore sr = ServerRestore(api: f.server, state: fresh.state);
      final BackupAuthority auth = await deriveBackupAuthority(f.key, BackupKind.family);

      expect(await sr.findVault(), _vault);
      await expectLater(
          sr.request(vaultId: _vault, authority: auth, userId: _user, deviceId: _device, pin: '0000'), throwsA(isA<BackupSinkException>()),
          reason: 'the person\'s own PIN is needed too');
      final ServerRestoreStatus asked =
          await sr.request(vaultId: _vault, authority: auth, userId: _user, deviceId: _device, pin: '2468');
      expect(asked.phase, ServerRestorePhase.waiting);
      expect(asked.waitHours, 72);
      await expectLater(sr.fetch(vaultId: _vault, restoreId: asked.restoreId!, authority: auth, kind: BackupKind.family),
          throwsA(isA<BackupSinkException>()),
          reason: 'the server releases nothing during the wait');

      f.server.clock = f.server.clock.add(const Duration(hours: 73));
      expect((await sr.status(_vault)).phase, ServerRestorePhase.ready);
      final ServerFetch got =
          await sr.fetch(vaultId: _vault, restoreId: asked.restoreId!, authority: auth, kind: BackupKind.family);
      expect(got.headSeq, 2);
      final RestoreEngine re = fresh.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: got.source, key: f.key, kind: BackupKind.family);
      await re.apply(o);
      expect(await fresh.hashes(), before);
      await sr.complete(_vault, asked.restoreId!, got);
      expect((await sr.status(_vault)).phase, ServerRestorePhase.completed);
      expect((await fresh.state.vault()).highSeq, 2, reason: 'the new phone now knows the newest history it has seen');
    });

    test('with a second grown-up the server wants their yes as well as the wait, and any grown-up can stop it', () async {
      final _Fam f = await _serverFamily();
      await seedHistory(f);
      f.server.approvalRequired = true;
      f.server.waitHours = 48;
      final a = await _ask(f, wait: false);
      f.server.clock = f.server.clock.add(const Duration(hours: 49));
      expect((await a.sr.status(_vault)).phase, ServerRestorePhase.needsYes);
      await expectLater(a.sr.fetch(vaultId: _vault, restoreId: a.asked.restoreId!, authority: a.auth, kind: BackupKind.family),
          throwsA(isA<BackupSinkException>()));
      f.server.approve();
      expect((await a.sr.status(_vault)).phase, ServerRestorePhase.ready);
      await a.sr.cancel(_vault, a.asked.restoreId!);
      expect((await a.sr.status(_vault)).phase, ServerRestorePhase.cancelled);
      await expectLater(a.sr.fetch(vaultId: _vault, restoreId: a.asked.restoreId!, authority: a.auth, kind: BackupKind.family),
          throwsA(isA<BackupSinkException>()));
    });

    test('a request signed with another family\'s sheet is refused by the server', () async {
      final _Fam f = await _serverFamily();
      final Rig fresh = await Rig.make(seed: 4, api: f.server);
      final ServerRestore sr = ServerRestore(api: f.server, state: fresh.state);
      final BackupAuthority wrong = await deriveBackupAuthority(RecoveryKey.generate(), BackupKind.family);
      await expectLater(sr.request(vaultId: _vault, authority: wrong, userId: _user, deviceId: _device, pin: '2468'),
          throwsA(isA<BackupSinkException>()));
      expect(f.server.restore, isNull);
    });

    test('a changed byte in a stored backup is caught by the hash the chain covers', () async {
      final _Fam f = await _serverFamily();
      await seedHistory(f);
      f.server.flipBlobByte(2, 100);
      final a = await _ask(f);
      await expectLater(a.sr.fetch(vaultId: _vault, restoreId: a.asked.restoreId!, authority: a.auth, kind: BackupKind.family),
          throwsA(isA<BackupSinkException>().having((BackupSinkException e) => e.detail, 'detail', 'blob')));
    });

    test('a server that hides the newest backup from a phone that has seen it is a rollback; the other tampering is named too', () async {
      final _Fam f = await _serverFamily();
      await seedHistory(f);
      await f.phone.put('learn', <String, Object?>{'third': 3});
      await f.phone.svc.backUpNow();
      final BackupAuthority auth = await deriveBackupAuthority(f.key, BackupKind.family);
      final List<ServerVersion> all = await _list(f.server);
      final v = await f.phone.state.vault();
      Future<HistoryVerdict> check(List<ServerVersion> vs, {int hs = 0, String? hc}) =>
          verifyServerHistory(vaultId: _vault, versions: vs, authority: auth, kind: BackupKind.family, highSeq: hs, highChain: hc);
      expect((await check(all.take(2).toList(), hs: v.highSeq, hc: v.highChain)).problem, HistoryProblem.rollback);
      expect((await check(<ServerVersion>[all[0], all[2]])).problem, HistoryProblem.gap);
      expect((await check(all, hs: 2, hc: 'f' * 64)).problem, HistoryProblem.highWaterChanged);
      ServerVersion copy(ServerVersion s, {String? prev, int? size}) => ServerVersion(
          seq: s.seq, prevChain: prev ?? s.prevChain, chain: s.chain, blobSha256: s.blobSha256, size: size ?? s.size,
          chunkSize: s.chunkSize, chunkCount: s.chunkCount, manifest: s.manifest, signature: s.signature, live: true);
      expect((await check(<ServerVersion>[all[0], copy(all[1], size: all[1].size + 1)])).problem, HistoryProblem.chainValueWrong);
      expect((await check(<ServerVersion>[all[0], copy(all[1], prev: 'a' * 64)])).problem, HistoryProblem.chainBroken);
      expect((await check(all, hs: v.highSeq, hc: v.highChain)).ok, isTrue);
    });

    test('a version appended with a stolen sign-in by a phone the sheet never certified is left out and does not stop the family\'s own backups being found',
        () async {
      final _Fam f = await _serverFamily();
      await f.phone.svc.backUpNow();
      // The thief has the session (so can append) and the family's public key, but not the words.
      final Rig thief = await Rig.make(seed: 9, api: f.server);
      await thief.state.setPublicKey(BackupKind.family, (await f.phone.state.publicKey(BackupKind.family))!);
      final BackupAuthority theirs = await deriveBackupAuthority(RecoveryKey.generate(), BackupKind.family);
      await thief.state.setWriterCert(
          BackupKind.family, thief.writer.publicKey, await theirs.certifyWriter(thief.writer.publicKey, BackupKind.family));
      await thief.put('care', <String, Object?>{'n': 'forged'}, owner: 'ivy');
      await thief.state.setVault(_vault);
      await thief.state.setServerOn(true);
      expect((await thief.svc.backUpNow()).ok, isTrue, reason: 'the server cannot tell; it holds no family key');
      expect(f.server.seqs, <int>[1, 2]);

      final a = await _ask(f);
      final ServerFetch got =
          await a.sr.fetch(vaultId: _vault, restoreId: a.asked.restoreId!, authority: a.auth, kind: BackupKind.family);
      expect(got.versions, 1, reason: 'only the family\'s own backup was taken');
      final RestoreEngine re = a.fresh.svc.restoreEngine();
      await re.apply(await re.open(source: got.source, key: f.key, kind: BackupKind.family));
      expect(await a.fresh.services.area('care', ownerId: 'ivy').get('n'), isNull, reason: 'nothing the thief wrote');
    });

    test('a backup of another sheet in the same vault is not taken as ours', () async {
      final _Fam f = await _serverFamily();
      await f.phone.svc.backUpNow();
      final RecoveryKey newer = await f.phone.svc.setUp();
      await f.phone.svc.backUpNow();
      final a = await _ask(f);
      final ServerFetch got =
          await a.sr.fetch(vaultId: _vault, restoreId: a.asked.restoreId!, authority: a.auth, kind: BackupKind.family);
      expect(got.versions, 1);
      expect(newer, isNot(f.key));
    });
  });
}

/// A server that answers every commit with a version whose chain value is not the one the phone signed.
class _Lying implements BackupServerApi {
  _Lying(this.inner);
  final FakeBackupServer inner;
  @override
  Future<Map<String, dynamic>> send(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query, Map<String, String>? headers}) async {
    final Map<String, dynamic> r = await inner.send(method, path, body: body, query: query, headers: headers);
    if (path.endsWith('/commit')) {
      final Map<String, dynamic> v = Map<String, dynamic>.of(r['version'] as Map<String, dynamic>);
      v['chainHash'] = 'e' * 64;
      return <String, dynamic>{...r, 'version': v};
    }
    return r;
  }
}
