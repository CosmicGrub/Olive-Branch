// OLIVE BRANCH — what the tablet keeps about an update it has staged: one sealed record in the device-scoped
// `updatestage` area (see localDataCatalogue). Verified headless (test/tablet_update_store_test.dart).
//
// What is kept: the stage (receiving, ready, installing), the version, the signed notice exactly as it arrived (so the
// checks can be repeated at the moment of installing), the staged file's name inside the app's own private folder,
// when an install was started and from which version (the "update began" marker), the plain-words result of the last
// attempt, and a one-time "what is new" for a grown-up. Never a path outside the app's folder, never a key, never
// anything about the child. The file itself lives in the private staging folder, not in this record.
import 'dart:typed_data';

import 'device_keys.dart' show b64, unb64;
import 'local_store.dart';

enum StageState { receiving, ready, installing }

class StagedUpdate {
  const StagedUpdate({
    required this.stage,
    required this.versionName,
    required this.versionCode,
    required this.fileName,
    required this.document,
    this.installStartedAtMs,
    this.fromVersionCode,
  });

  final StageState stage;
  final String versionName;
  final int versionCode;

  /// A bare file name inside the staging folder (no separators).
  final String fileName;

  /// The signed notice, byte for byte.
  final Uint8List document;

  /// The "update began" marker: when the grown-up started the install and which version was running.
  final int? installStartedAtMs;
  final int? fromVersionCode;

  StagedUpdate copyWith({StageState? stage, int? installStartedAtMs, int? fromVersionCode}) => StagedUpdate(
        stage: stage ?? this.stage,
        versionName: versionName,
        versionCode: versionCode,
        fileName: fileName,
        document: document,
        installStartedAtMs: installStartedAtMs ?? this.installStartedAtMs,
        fromVersionCode: fromVersionCode ?? this.fromVersionCode,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        's': stage.name,
        'vn': versionName,
        'vc': versionCode,
        'f': fileName,
        'doc': b64(document),
        if (installStartedAtMs != null) 'at': installStartedAtMs,
        if (fromVersionCode != null) 'from': fromVersionCode,
      };

  static final RegExp _bareName = RegExp(r'^[A-Za-z0-9._-]{1,80}$');

  static StagedUpdate? tryParse(Object? j) {
    if (j is! Map) return null;
    final StageState? st = StageState.values.where((StageState s) => s.name == j['s']).firstOrNull;
    final Object? vn = j['vn'], vc = j['vc'], f = j['f'], doc = j['doc'], at = j['at'], from = j['from'];
    if (st == null || vn is! String || vn.isEmpty || vn.length > 40 || vc is! int || vc < 1) return null;
    if (f is! String || !_bareName.hasMatch(f) || f.contains('..') || doc is! String) return null;
    if (at != null && at is! int) return null;
    if (from != null && from is! int) return null;
    final Uint8List bytes;
    try {
      bytes = unb64(doc);
    } catch (_) {
      return null;
    }
    if (bytes.isEmpty || bytes.length > 256 * 1024) return null;
    return StagedUpdate(
        stage: st,
        versionName: vn,
        versionCode: vc,
        fileName: f,
        document: bytes,
        installStartedAtMs: at as int?,
        fromVersionCode: from as int?);
  }
}

/// A grown-up sees this once after an update landed. Plain words, from the signed notice.
class WhatsNew {
  const WhatsNew({required this.versionName, required this.headline, required this.notes});
  final String versionName;
  final String headline;
  final List<String> notes;

  Map<String, Object?> toJson() => <String, Object?>{'vn': versionName, 'h': headline, 'n': notes};

  static WhatsNew? tryParse(Object? j) {
    if (j is! Map) return null;
    final Object? vn = j['vn'], h = j['h'], n = j['n'];
    if (vn is! String || h is! String || n is! List || n.length > 12 || n.any((Object? x) => x is! String)) return null;
    return WhatsNew(versionName: vn, headline: h, notes: <String>[for (final Object? x in n) x! as String]);
  }
}

abstract class StagedUpdateStore {
  Future<StagedUpdate?> loadStaged();
  Future<void> saveStaged(StagedUpdate s);
  Future<void> clearStaged();

  /// The code name of the last attempt's refusal (a [TabletUpdateCode] name), or null.
  Future<String?> loadLastResult();
  Future<void> saveLastResult(String? code);

  Future<WhatsNew?> loadWhatsNew();
  Future<void> saveWhatsNew(WhatsNew w);
  Future<void> clearWhatsNew();
}

class MemoryStagedUpdateStore implements StagedUpdateStore {
  StagedUpdate? _s;
  String? _r;
  WhatsNew? _w;
  @override
  Future<StagedUpdate?> loadStaged() async => _s;
  @override
  Future<void> saveStaged(StagedUpdate s) async => _s = s;
  @override
  Future<void> clearStaged() async => _s = null;
  @override
  Future<String?> loadLastResult() async => _r;
  @override
  Future<void> saveLastResult(String? code) async => _r = code;
  @override
  Future<WhatsNew?> loadWhatsNew() async => _w;
  @override
  Future<void> saveWhatsNew(WhatsNew w) async => _w = w;
  @override
  Future<void> clearWhatsNew() async => _w = null;
}

/// The durable one: the sealed `updatestage` area.
class LocalStoreStagedUpdateStore implements StagedUpdateStore {
  LocalStoreStagedUpdateStore(this._ns);
  final LocalNamespace _ns;

  @override
  Future<StagedUpdate?> loadStaged() async => StagedUpdate.tryParse(await _ns.get('staged'));
  @override
  Future<void> saveStaged(StagedUpdate s) => _ns.put('staged', s.toJson());
  @override
  Future<void> clearStaged() => _ns.delete('staged');
  @override
  Future<String?> loadLastResult() async {
    final Object? v = await _ns.get('last');
    return v is String && v.length <= 40 ? v : null;
  }

  @override
  Future<void> saveLastResult(String? code) => code == null ? _ns.delete('last') : _ns.put('last', code);
  @override
  Future<WhatsNew?> loadWhatsNew() async => WhatsNew.tryParse(await _ns.get('new'));
  @override
  Future<void> saveWhatsNew(WhatsNew w) => _ns.put('new', w.toJson());
  @override
  Future<void> clearWhatsNew() => _ns.delete('new');
}
