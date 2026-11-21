// OLIVE BRANCH — test support for the tablet update path: a REFERENCE ENGINE that does the real work (Ed25519 over the
// signed notice, replay floor, rollback, signer pin) with a small test-only notice format, a fake installer, and a
// fixture maker that builds a signed notice and an APK-shaped file. The shipped adapter delegates to the client
// updater's own verification instead; what is tested here is the tablet path's use of the port, byte for byte.
//
// Documentation-range data only: no real key, address or name. The signing key is a fixed test seed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:olive_client/play_transport.dart';
import 'package:olive_client/tablet_update_hash.dart';
import 'package:olive_client/tablet_update_port.dart';

const String kTestPackage = 'com.olivebranch.olive_client';
final String kTestSigner = 'a' * 64;
final String kOtherSigner = 'b' * 64;

/// A fixed TEST seed. Not a secret: it signs only these fixtures.
final Uint8List kTestSeed = Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));
final Uint8List kOtherSeed = Uint8List.fromList(List<int>.generate(32, (int i) => 200 - i));

Future<SimpleKeyPair> keyFromSeed(Uint8List seed) => Ed25519().newKeyPairFromSeed(seed);

String canonical(Object? v) {
  if (v is Map) {
    final List<String> keys = v.keys.cast<String>().toList()..sort();
    return '{${keys.map((String k) => '${jsonEncode(k)}:${canonical(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(canonical).join(',')}]';
  return jsonEncode(v);
}

/// An APK-shaped file: a one-line header the test inspector reads, then deterministic filler.
Uint8List makeApkBytes({required int size, String pkg = kTestPackage, int versionCode = 5200, String? signer, int seed = 7}) {
  final String head = 'OLIVEAPK|$pkg|$versionCode|${signer ?? kTestSigner}\n';
  final Random r = Random(seed);
  final Uint8List out = Uint8List(size);
  final List<int> h = utf8.encode(head);
  for (int i = 0; i < size; i++) {
    out[i] = i < h.length ? h[i] : r.nextInt(256);
  }
  return out;
}

class Fixture {
  Fixture({required this.apk, required this.document, required this.manifest});
  final Uint8List apk;
  final Uint8List document;
  final Map<String, Object?> manifest;
  String get sha => (manifest['apks']! as List<Object?>).cast<Map<String, Object?>>().first['sha256']! as String;
}

Future<Fixture> makeFixture({
  int size = 100 * 1024,
  int chunkSize = 32 * 1024,
  int versionCode = 5200,
  String versionName = '0.52.0',
  int sequence = 5,
  String channel = 'stable',
  String app = kTestPackage,
  String? apkSigner,
  String pinnedSigner = '',
  Uint8List? signWith,
  Uint8List? apkOverride,
  DateTime? expires,
  String abi = 'arm64-v8a',
  List<String> notes = const <String>['Calmer pairing.', 'Fixes a crash when the tablet sleeps.'],
  Map<String, Object?> Function(Map<String, Object?>)? tamper,

  /// The signed whole-file hash is wrong although every chunk hash is right (a notice that lies about the whole).
  bool wrongWholeSha = false,

  /// Sign a notice that DECLARES this size (with a matching, made-up chunk list) without building such a file.
  int? declaredSize,
}) async {
  final Uint8List apk = apkOverride ?? makeApkBytes(size: size, versionCode: versionCode, signer: apkSigner);
  final List<String> chunks = <String>[];
  for (int o = 0; o < apk.length; o += chunkSize) {
    chunks.add(await sha256HexOf(apk.sublist(o, min(o + chunkSize, apk.length))));
  }
  final int declared = declaredSize ?? apk.length;
  if (declaredSize != null) {
    chunks
      ..clear()
      ..addAll(List<String>.filled((declared + chunkSize - 1) ~/ chunkSize, 'c' * 64));
  }
  final Map<String, Object?> m = <String, Object?>{
    'schema': 1,
    'app': app,
    'channel': channel,
    'versionName': versionName,
    'versionCode': versionCode,
    'minSupportedVersionCode': 5000,
    'sequence': sequence,
    'issuedAt': '2026-11-01T00:00:00Z',
    'expiresAt': (expires ?? DateTime.utc(2027, 6, 1)).toIso8601String(),
    'headline': 'A calmer Olive Branch',
    'notes': notes,
    'apks': <Object?>[
      <String, Object?>{
        'abi': abi,
        'size': declared,
        'sha256': wrongWholeSha || declaredSize != null ? 'd' * 64 : await sha256HexOf(apk),
        'chunkSize': chunkSize,
        'chunks': chunks,
        'signerSha256': pinnedSigner.isEmpty ? kTestSigner : pinnedSigner,
      }
    ],
  };
  final Map<String, Object?> shown = tamper == null ? m : tamper(m);
  final SimpleKeyPair kp = await keyFromSeed(signWith ?? kTestSeed);
  // The signature is made over the UNtampered notice; a tamper test changes what is sent after signing.
  final Signature sig = await Ed25519().sign(utf8.encode('olive-test-notice\n${canonical(m)}'), keyPair: kp);
  final Map<String, Object?> doc = <String, Object?>{'manifest': shown, 'sig': base64.encode(sig.bytes)};
  return Fixture(apk: apk, document: Uint8List.fromList(utf8.encode(jsonEncode(doc))), manifest: shown);
}

/// The reference engine: real Ed25519, real rollback and replay rules, a fake installer, a temp staging folder.
class ReferenceEngine implements UpdateEnginePort {
  ReferenceEngine({
    required this.dir,
    this.installedVersionCode = 5100,
    String? installedSigner,
    this.channel = 'stable',
    DateTime? now,
    this.freeBytes = 4 * 1024 * 1024 * 1024,
    this.battery = 80,
    this.charging = false,
    this.hasKey = true,
  })  : installedSigner = installedSigner ?? kTestSigner,
        _now = now ?? DateTime.utc(2026, 11, 21);

  final Directory dir;
  int installedVersionCode;
  final String installedSigner;
  final String channel;
  final DateTime _now;
  int freeBytes;
  int battery;
  bool charging;
  bool hasKey;
  SimplePublicKey? _trusted;

  /// The highest sequence a verified notice carried: a lower one is a replay.
  int sequenceFloor = 0;
  final List<String> installs = <String>[];
  InstallOutcome nextOutcome = InstallOutcome.handedToSystem;
  int verifyCalls = 0;
  int inspectCalls = 0;
  HeldUpdate? heldUpdate;
  OwnUpdateOffer? own;
  Fixture? ownFixture;

  @override
  bool get available => hasKey;

  Future<SimplePublicKey> trustedKey() async => _trusted ??= await (await keyFromSeed(kTestSeed)).extractPublicKey();

  @override
  Future<InstalledFacts> installed() async =>
      InstalledFacts(packageName: kTestPackage, versionCode: installedVersionCode, signerSha256: installedSigner);

  @override
  Future<VerifiedUpdate> verify(Uint8List document, {required bool forInstall}) async {
    verifyCalls++;
    if (document.length > 256 * 1024) throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
    final Object? doc;
    try {
      doc = jsonDecode(utf8.decode(document));
    } catch (_) {
      throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
    }
    if (doc is! Map<String, Object?> || doc['manifest'] is! Map<String, Object?> || doc['sig'] is! String) {
      throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
    }
    final Map<String, Object?> m = doc['manifest']! as Map<String, Object?>;
    final bool ok = await Ed25519().verify(utf8.encode('olive-test-notice\n${canonical(m)}'),
        signature: Signature(base64.decode(doc['sig']! as String), publicKey: await trustedKey()));
    if (!ok) throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
    if (m['app'] != kTestPackage) throw const TabletUpdateRefused(TabletUpdateCode.wrongApp);
    if (m['channel'] != channel) throw const TabletUpdateRefused(TabletUpdateCode.wrongChannel);
    if (DateTime.parse(m['expiresAt']! as String).isBefore(_now)) throw const TabletUpdateRefused(TabletUpdateCode.expired);
    final int seq = m['sequence']! as int;
    if (seq < sequenceFloor) throw const TabletUpdateRefused(TabletUpdateCode.replayed);
    final List<Map<String, Object?>> apks = (m['apks']! as List<Object?>).cast<Map<String, Object?>>();
    final Map<String, Object?> a = apks.firstWhere((Map<String, Object?> e) => e['abi'] == 'arm64-v8a',
        orElse: () => throw const TabletUpdateRefused(TabletUpdateCode.notForThisTablet));
    if (!forInstall) sequenceFloor = seq;
    return VerifiedUpdate(
      packageName: m['app']! as String,
      versionName: m['versionName']! as String,
      versionCode: m['versionCode']! as int,
      minSupportedVersionCode: m['minSupportedVersionCode']! as int,
      sequence: seq,
      headline: m['headline']! as String,
      notes: (m['notes']! as List<Object?>).cast<String>(),
      apk: ApkFacts(
        abi: a['abi']! as String,
        size: a['size']! as int,
        sha256: a['sha256']! as String,
        chunkSize: a['chunkSize']! as int,
        chunkSha256: (a['chunks']! as List<Object?>).cast<String>(),
        signerSha256: a['signerSha256']! as String,
      ),
      document: document,
    );
  }

  @override
  Future<ApkInspection> inspect(File apk) async {
    inspectCalls++;
    final RandomAccessFile f = await apk.open();
    try {
      final Uint8List head = await f.read(200);
      final String line = utf8.decode(head, allowMalformed: true).split('\n').first;
      final List<String> p = line.split('|');
      if (p.length != 4 || p[0] != 'OLIVEAPK') throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
      return ApkInspection(packageName: p[1], versionCode: int.parse(p[2]), signerSha256: p[3]);
    } finally {
      await f.close();
    }
  }

  @override
  Future<Directory> stagingDirectory() async => dir;

  @override
  Future<DeviceGuards> guards() async => DeviceGuards(freeBytes: freeBytes, batteryPercent: battery, charging: charging);

  @override
  Future<InstallOutcome> install(File apk, VerifiedUpdate update) async {
    installs.add(apk.path);
    return nextOutcome;
  }

  @override
  Future<HeldUpdate?> held() async => heldUpdate;

  @override
  Future<OwnUpdateOffer?> ownOffer() async => own;

  @override
  Future<HeldUpdate> fetchOwn(OwnUpdateOffer offer, {void Function(int done, int total)? onProgress}) async {
    final Fixture f = ownFixture!;
    final File out = File('${dir.path}${Platform.pathSeparator}own-download.apk');
    await out.writeAsBytes(f.apk);
    onProgress?.call(f.apk.length, f.apk.length);
    return HeldUpdate(update: offer.update, apk: out);
  }
}

/// Makes the held update the phone offers from a fixture, writing the file into [dir].
Future<HeldUpdate> heldFrom(Fixture f, ReferenceEngine phoneEngine, Directory dir) async {
  final VerifiedUpdate u = await phoneEngine.verify(f.document, forInstall: false);
  final File file = File('${dir.path}${Platform.pathSeparator}held.apk');
  await file.writeAsBytes(f.apk);
  return HeldUpdate(update: u, apk: file);
}

/// A transport a test fully controls: it records what this end sends and lets the test inject what "arrives", from any
/// seat it likes. Used for hostile peers (the real twin only ever delivers what the real other end sent).
class ScriptedTransport implements PlayTransport {
  ScriptedTransport({this.mySeatId = 'b', this.peerSeatId = 'a'});
  final String mySeatId, peerSeatId;
  final StreamController<PlayInbound> _in = StreamController<PlayInbound>.broadcast(sync: true);
  final StreamController<PeerPresence> _pres = StreamController<PeerPresence>.broadcast(sync: true);
  PeerPresence presenceNow = PeerPresence.present;
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  bool accept = true;

  @override
  String get mySeat => mySeatId;
  @override
  String get peerSeat => peerSeatId;
  @override
  Stream<PlayInbound> get incoming => _in.stream;
  @override
  Stream<PeerPresence> get presence => _pres.stream;
  @override
  PeerPresence get currentPresence => presenceNow;
  @override
  Future<bool> send(Map<String, dynamic> wire) async {
    if (!accept) return false;
    sent.add(jsonDecode(jsonEncode(wire)) as Map<String, dynamic>);
    return true;
  }

  void inject(Object? raw, {String? from}) => _in.add(PlayInbound(raw, from ?? peerSeatId));

  /// Every `need` this end has sent, as (object, offset, length).
  List<(String, int, int)> get needs => <(String, int, int)>[
        for (final Map<String, dynamic> m in sent)
          if (m['k'] == 'need') (m['o'] as String, m['off'] as int, m['len'] as int)
      ];

  @override
  void dispose() {
    unawaited(_in.close());
    unawaited(_pres.close());
  }
}
