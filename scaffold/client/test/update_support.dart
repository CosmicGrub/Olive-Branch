// Shared test doubles for the updater: a signer (a throwaway Ed25519 key made in the test), deterministic fake APK
// bytes, a fake network that can lie in every way a network can, a fake Android installer, a fake Google Play and a
// fake phone. Nothing here touches a real network, a real key or a real device. Documentation-range addresses only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:olive_client/sha256.dart';
import 'package:olive_client/update_controller.dart';
import 'package:olive_client/update_download.dart';
import 'package:olive_client/update_manifest.dart';
import 'package:olive_client/update_platform.dart';
import 'package:olive_client/update_store.dart';
import 'package:olive_client/update_transport.dart';

/// "Now" for every test: a day after the sample manifest was published.
final DateTime kNow = DateTime.utc(2026, 11, 22, 12);

class TestSigner {
  TestSigner._(this.keyPair, this.rawPublic);
  final SimpleKeyPair keyPair;
  final List<int> rawPublic;

  static Future<TestSigner> create([int seed = 1]) async {
    final SimpleKeyPair kp = await Ed25519().newKeyPairFromSeed(List<int>.generate(32, (int i) => (seed * 31 + i) & 0xff));
    final SimplePublicKey pub = await kp.extractPublicKey();
    return TestSigner._(kp, pub.bytes);
  }

  /// The label the release tools use: 16 hex digits of SHA-256 of the raw key.
  String get kid => sha256Hex(String.fromCharCodes(rawPublic)).substring(0, 16);

  /// One `--dart-define=OLIVE_UPDATE_PUBKEYS=` entry.
  String get trustEntry => '$kid:${toBase64Url(rawPublic)}';
  UpdateTrust get trust => UpdateTrust.parse(trustEntry);

  /// A signed document `{manifest, signature}` for the payload [draft].
  Future<Map<String, Object?>> sign(Map<String, Object?> draft, {String? kid, String? domain}) async {
    final Uint8List bytes = domain == null
        ? signingBytes(draft)
        : Uint8List.fromList(utf8.encode('$domain${canonicalJson(draft)}'));
    final Signature s = await Ed25519().sign(bytes, keyPair: keyPair);
    return <String, Object?>{
      'manifest': draft,
      'signature': <String, Object?>{'alg': 'ed25519', 'kid': kid ?? this.kid, 'sig': toBase64Url(s.bytes)},
    };
  }
}

Uint8List encodeDoc(Map<String, Object?> doc) => Uint8List.fromList(utf8.encode(jsonEncode(doc)));

/// Deterministic pseudo-random bytes (a fake APK that starts like a zip).
Uint8List fakeApk(int size, [int seed = 7]) {
  final Uint8List b = Uint8List(size);
  int x = seed * 2654435761 & 0xffffffff;
  for (int i = 0; i < size; i++) {
    x = (x * 1664525 + 1013904223) & 0xffffffff;
    b[i] = (x >> 16) & 0xff;
  }
  if (size > 4) {
    b[0] = 0x50;
    b[1] = 0x4b;
  }
  return b;
}

const String kPrimary = 'https://updates.example.org/olive/olive-0.52.0-direct-arm64-v8a.apk';
const String kMirror = 'https://mirror.example.net/olive/olive-0.52.0-direct-arm64-v8a.apk';
const String kManifestUrl = 'https://updates.example.org/olive/manifest.json';
const String kManifestMirror = 'https://mirror.example.net/olive/manifest.json';

String certHash(String label) => sha256Hex('certificate $label');

/// The first (usually only) file entry of a payload, for tests that tweak it.
Map<String, Object?> apk0(Map<String, Object?> payload) => (payload['apks']! as List<Object?>).first! as Map<String, Object?>;

/// The sample manifest payload for [apk] (the object under "manifest"). Everything can be overridden; chunk hashes and
/// sizes follow the bytes.
Future<Map<String, Object?>> draftFor(
  Uint8List apk, {
  String versionName = '0.52.0',
  int? versionCode,
  int minSupported = 5100,
  String channel = 'stable',
  String app = kUpdateAppId,
  int sequence = 1795255200,
  String issuedAt = '2026-11-21T10:00:00Z',
  String expiresAt = '2027-05-20T10:00:00Z',
  String publishedAt = '2026-11-21T10:00:00Z',
  int chunkSize = 65536,
  List<String> urls = const <String>[kPrimary, kMirror],
  String abi = 'arm64-v8a',
  String? signer,
  String? wholeSha,
  String headline = 'Calmer messages',
  List<String> items = const <String>['Messages open a little faster.', 'A quieter morning screen.'],
}) async {
  final List<String> chunks = <String>[
    for (int o = 0; o < apk.length; o += chunkSize) await sha256OfBytes(apk.sublist(o, (o + chunkSize).clamp(0, apk.length))),
  ];
  final List<int> parts = versionName.split('.').map(int.parse).toList();
  return <String, Object?>{
    'schema': 1,
    'app': app,
    'channel': channel,
    'versionName': versionName,
    'versionCode': versionCode ?? parts[0] * 10000 + parts[1] * 100 + parts[2],
    'minSupportedVersionCode': minSupported,
    'sequence': sequence,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'publishedAt': publishedAt,
    'headline': headline,
    'notes': items,
    'apks': <Object?>[
      <String, Object?>{
        'abi': abi,
        'size': apk.length,
        'sha256': wholeSha ?? await sha256OfBytes(apk),
        'signerSha256': signer ?? certHash('owner'),
        'chunkSize': chunkSize,
        'chunks': chunks,
        'urls': urls,
      },
    ],
  };
}

// ---- the fake network -------------------------------------------------------------

/// How one file address behaves.
class FileBehavior {
  FileBehavior(this.bytes,
      {this.honorRange = true, this.dropAfter, this.dropTimes = 1, this.corrupt, this.declaredLength, this.endless = false, this.error, this.onPiece});

  Uint8List bytes;
  bool honorRange;

  /// The connection drops after this many bytes of the body, for the first [dropTimes] requests.
  int? dropAfter;
  int dropTimes;

  /// Flips a byte at this absolute offset in what is served.
  int? corrupt;

  /// Content-Length to claim instead of the real one.
  int? declaredLength;

  /// Never stops sending.
  bool endless;

  /// Throws this on open (a 404, a bad redirect, an offline).
  UpdateRefusal? error;

  /// Called after each piece of the body is sent, with how many bytes of this response have gone (a test uses it to
  /// change the phone mid-download).
  void Function(int sent)? onPiece;
}

class FakeTransport implements UpdateTransport {
  final Map<String, Uint8List> manifests = <String, Uint8List>{};
  final Map<String, UpdateRefusal> manifestErrors = <String, UpdateRefusal>{};
  final Map<String, FileBehavior> files = <String, FileBehavior>{};
  final List<String> getLog = <String>[];
  final List<(String, int?)> openLog = <(String, int?)>[];
  int pieceSize = 30000;

  /// A real pause after each piece, so a test can look at the screen while a download is running.
  Duration pieceDelay = Duration.zero;
  int _drops = 0;

  @override
  Future<UpdateResponse> get(Uri url, {required int maxBytes, UpdateCancel? cancel}) async {
    getLog.add(url.toString());
    final UpdateRefusal? e = manifestErrors[url.toString()];
    if (e != null) throw e;
    final Uint8List? b = manifests[url.toString()];
    if (b == null) throw const UpdateRefusal(UpdateRefusalCode.httpError, 'status 404');
    if (b.length > maxBytes) throw const UpdateRefusal(UpdateRefusalCode.tooMuchData);
    return UpdateResponse(status: 200, body: b, finalUrl: url);
  }

  @override
  Future<UpdateStream> open(Uri url, {int? rangeStart, UpdateCancel? cancel}) async {
    openLog.add((url.toString(), rangeStart));
    final FileBehavior? f = files[url.toString()];
    if (f == null) throw const UpdateRefusal(UpdateRefusalCode.httpError, 'status 404');
    if (f.error != null) throw f.error!;
    final bool ranged = rangeStart != null && rangeStart > 0 && f.honorRange;
    final int start = ranged ? rangeStart : 0;
    Uint8List body = Uint8List.fromList(f.bytes.sublist(start));
    if (f.corrupt != null && f.corrupt! >= start && f.corrupt! < f.bytes.length) {
      body[f.corrupt! - start] ^= 0xff;
    }
    final int dropAt = f.dropAfter ?? -1;
    final bool drop = f.dropAfter != null && _drops < f.dropTimes;
    if (drop) _drops++;
    Stream<List<int>> gen() async* {
      int sent = 0;
      while (sent < body.length || f.endless) {
        if (drop && sent >= dropAt) throw const SocketException('connection reset');
        if (sent >= body.length && f.endless) {
          yield Uint8List(pieceSize);
          sent += pieceSize;
          continue;
        }
        int end = (sent + pieceSize).clamp(0, body.length);
        if (drop && end > dropAt) end = dropAt;
        yield body.sublist(sent, end);
        sent = end;
        f.onPiece?.call(sent);
        await Future<void>.delayed(pieceDelay);
      }
    }

    return UpdateStream(
      status: ranged ? 206 : 200,
      body: gen(),
      finalUrl: url,
      contentLength: f.declaredLength ?? (f.endless ? null : body.length),
      contentRangeStart: ranged ? start : null,
    );
  }
}

// ---- the fake phone ----------------------------------------------------------------

class FakeInstaller implements DirectInstaller {
  bool canInstall = true;
  String packageName = kUpdateAppId;
  int? inspectedVersionCode;
  List<String> signers = <String>[certHash('owner')];
  List<String> installedSigners = <String>[certHash('owner')];
  InstallStart startResult = InstallStart.waitingForYou;
  Object? inspectError;
  final List<Map<String, Object?>> installs = <Map<String, Object?>>[];
  int settingsOpened = 0;
  int inspects = 0;
  final StreamController<InstallEvent> events = StreamController<InstallEvent>.broadcast();

  @override
  Stream<InstallEvent> get installEvents => events.stream;

  @override
  Future<bool> canRequestInstalls() async => canInstall;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<ApkInspection> inspect(String path) async {
    inspects++;
    if (inspectError != null) throw inspectError!;
    return ApkInspection(
      packageName: packageName,
      versionCode: inspectedVersionCode ?? 5200,
      signerSha256: signers,
      installedSignerSha256: installedSigners,
    );
  }

  @override
  Future<InstallStart> install({required String path, required String sha256, required int size, required int versionCode}) async {
    installs.add(<String, Object?>{'path': path, 'sha256': sha256, 'size': size, 'versionCode': versionCode});
    return startResult;
  }
}

class FakePlay implements PlayUpdater {
  PlayUpdateInfo info = const PlayUpdateInfo(available: false);
  bool startResult = true;
  Object? checkError;
  final List<bool> starts = <bool>[];
  int completes = 0;
  final StreamController<PlayEvent> events = StreamController<PlayEvent>.broadcast();

  @override
  Stream<PlayEvent> get playEvents => events.stream;

  @override
  Future<PlayUpdateInfo> check() async {
    if (checkError != null) throw checkError!;
    return info;
  }

  @override
  Future<bool> start({required bool immediate}) async {
    starts.add(immediate);
    return startResult;
  }

  @override
  Future<void> complete() async => completes++;
}

UpdateEnvironment wifiPhone({
  int versionCode = 5100,
  String versionName = '0.51.0',
  NetworkKind network = NetworkKind.wifi,
  bool? metered = false,
  bool roaming = false,
  bool dataSaver = false,
  int? battery = 80,
  bool charging = false,
  int? freeBytes = 4 * 1024 * 1024 * 1024,
  List<String> abis = const <String>['arm64-v8a', 'armeabi-v7a'],
  String flavor = 'direct',
}) =>
    UpdateEnvironment(
      installedVersionCode: versionCode,
      installedVersionName: versionName,
      network: network,
      metered: metered,
      roaming: roaming,
      dataSaver: dataSaver,
      batteryPercent: battery,
      charging: charging,
      freeBytes: freeBytes,
      abis: abis,
      flavor: flavor,
    );

/// Everything a controller test needs, wired together.
class Rig {
  Rig._(this.signer, this.transport, this.env, this.installer, this.play, this.repo, this.dir, this.config, this.clock);

  final TestSigner signer;
  final FakeTransport transport;
  final FixedEnvironment env;
  final FakeInstaller installer;
  final FakePlay play;
  final MemoryUpdateStateRepository repo;
  final Directory dir;
  final UpdateConfig config;
  final List<DateTime> clock;
  final List<String> flushed = <String>[];
  int areas = 12;

  DateTime now() => clock.single;
  set time(DateTime t) => clock[0] = t;

  static Future<Rig> create({
    TestSigner? signer,
    List<String> manifestUrls = const <String>[kManifestUrl],
    UpdateEnvironment? environment,
    String channel = 'stable',
    bool withKey = true,
  }) async {
    final TestSigner who = signer ?? await TestSigner.create();
    final Directory dir = await Directory.systemTemp.createTemp('olive_update_test_');
    return Rig._(
      who,
      FakeTransport(),
      FixedEnvironment(environment ?? wifiPhone()),
      FakeInstaller(),
      FakePlay(),
      MemoryUpdateStateRepository(),
      dir,
      UpdateConfig(manifestUrls: manifestUrls, channel: channel, trust: withKey ? who.trust : UpdateTrust(const <List<int>>[])),
      <DateTime>[kNow],
    );
  }

  Directory get staging => Directory('${dir.path}${Platform.pathSeparator}olive_updates');

  AppUpdater updater({bool withInstaller = true, bool play = false, UpdateStateRepository? repository, UpdateEnvironmentSource? environment}) {
    return AppUpdater(
      environment: environment ?? env,
      config: config,
      repository: repository ?? repo,
      transport: transport,
      staging: play ? null : UpdateStaging(staging),
      direct: play || !withInstaller ? null : installer,
      play: play ? this.play : null,
      safety: UpdateSafety(
        flushers: <Future<void> Function()>[() async => flushed.add('flushed')],
        areaCounter: () async => areas,
      ),
      clock: now,
      sleep: (Duration d) async {},
    );
  }

  /// Publishes [apk] under the primary and mirror addresses with a manifest signed by [signer].
  Future<Map<String, Object?>> publish(Uint8List apk,
      {Map<String, Object?> Function(Map<String, Object?>)? tweak, bool files = true, String url = kManifestUrl}) async {
    Map<String, Object?> d = await draftFor(apk);
    if (tweak != null) d = tweak(d);
    final Map<String, Object?> doc = await signer.sign(d);
    transport.manifests[url] = encodeDoc(doc);
    if (files) {
      transport.files[kPrimary] = FileBehavior(apk);
      transport.files[kMirror] = FileBehavior(apk);
    }
    return doc;
  }

  Future<void> dispose() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
