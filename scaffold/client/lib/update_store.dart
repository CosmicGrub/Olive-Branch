// OLIVE BRANCH — what the updater remembers, kept on THIS device in the sealed device area `updates` (catalogued in
// local_services.dart, MASTERFILE 8.16.4). Verified headless (test/update_store_test.dart). MASTERFILE 7.24.
//
// It holds: when the last check was and how it ended (a word, never an address or an error text), the newest manifest
// this phone has accepted (so an older one can never be replayed to it), the adult's choices (Wi-Fi only, automatic
// checks, a source and a channel they typed), a "Later" they chose, an install in flight (so the app can tell, the next
// time it opens, whether Android finished it), and the plain-words notes of an update that just finished, until a grown-up
// has seen them once. It holds no key, no address query, no file path, and nothing about a child or a family: it is not
// shared, not uploaded and not part of any export.
import 'dart:convert';

import 'local_services.dart';
import 'local_store.dart';

const int kUpdateStateSchema = 1;

/// An install handed to Android and not yet confirmed from the other side of the restart.
class PendingInstall {
  const PendingInstall({
    required this.fromVersionCode,
    required this.toVersionCode,
    required this.versionName,
    required this.atMs,
    this.areaCount,
    this.headline = '',
    this.notes = const <String>[],
  });

  final int fromVersionCode;
  final int toVersionCode;
  final String versionName;
  final int atMs;

  /// How many sealed areas this phone held before the update (the pre-update safety note): the same number, or more,
  /// must be there afterwards.
  final int? areaCount;
  final String headline;
  final List<String> notes;

  Map<String, Object?> toJson() => <String, Object?>{
        'from': fromVersionCode,
        'to': toVersionCode,
        'name': versionName,
        'at': atMs,
        if (areaCount != null) 'areas': areaCount,
        'headline': headline,
        'notes': notes,
      };

  static PendingInstall? fromJson(Object? o) {
    if (o is! Map) return null;
    final Object? from = o['from'], to = o['to'], name = o['name'], at = o['at'];
    if (from is! int || to is! int || name is! String || at is! int) return null;
    return PendingInstall(
      fromVersionCode: from,
      toVersionCode: to,
      versionName: name,
      atMs: at,
      areaCount: o['areas'] is int ? o['areas'] as int : null,
      headline: o['headline'] is String ? o['headline'] as String : '',
      notes: <String>[for (final Object? n in (o['notes'] is List ? o['notes'] as List : const <Object?>[])) if (n is String) n],
    );
  }
}

/// The plain-words notes of an update that finished, shown to a grown-up once.
class WhatsNew {
  const WhatsNew({required this.versionName, required this.headline, required this.notes, this.dataNote = ''});
  final String versionName;
  final String headline;
  final List<String> notes;

  /// Set only when the pre-update safety note and the phone disagree (fewer sealed areas afterwards).
  final String dataNote;

  Map<String, Object?> toJson() =>
      <String, Object?>{'name': versionName, 'headline': headline, 'notes': notes, if (dataNote.isNotEmpty) 'data': dataNote};

  static WhatsNew? fromJson(Object? o) {
    if (o is! Map) return null;
    final Object? name = o['name'];
    if (name is! String) return null;
    return WhatsNew(
      versionName: name,
      headline: o['headline'] is String ? o['headline'] as String : '',
      notes: <String>[for (final Object? n in (o['notes'] is List ? o['notes'] as List : const <Object?>[])) if (n is String) n],
      dataNote: o['data'] is String ? o['data'] as String : '',
    );
  }
}

class UpdateState {
  const UpdateState({
    this.lastAttemptMs,
    this.lastCheckMs,
    this.lastResult = '',
    this.lastSeenVersionName = '',
    this.highestSeenSequence,
    this.wifiOnly = true,
    this.autoCheck = true,
    this.manifestUrl,
    this.channel,
    this.laterVersionCode,
    this.laterUntilMs,
    this.queuedVersionCode,
    this.pending,
    this.whatsNew,
    this.lastUpdatedName = '',
    this.lastUpdatedMs,
  });

  /// The last time a check was TRIED (so a failing one is not retried every time the app opens) and the last time one
  /// SUCCEEDED, as milliseconds since the epoch.
  final int? lastAttemptMs, lastCheckMs;

  /// `ok`, `offline`, or `refused:<code>`: a word, never a message from the network.
  final String lastResult;

  /// The version name of the newest manifest accepted, and the largest sequence number of any manifest accepted (the
  /// replay guard: a manifest with a lower one is refused).
  final String lastSeenVersionName;
  final int? highestSeenSequence;

  /// Choices. Wi-Fi only is ON until an adult turns it off.
  final bool wifiOnly, autoCheck;

  /// Typed by an adult (a source of their own); null means the one built into the app.
  final String? manifestUrl;

  /// Null means the build's default channel.
  final String? channel;

  /// "Later": the banner for this versionCode stays quiet until this time.
  final int? laterVersionCode, laterUntilMs;

  /// "Download on Wi-Fi" was chosen for this versionCode: it starts by itself the next time the phone is on Wi-Fi and
  /// the app is open. An adult's choice, never automatic.
  final int? queuedVersionCode;
  final PendingInstall? pending;
  final WhatsNew? whatsNew;

  /// The version this phone last finished updating to, and when.
  final String lastUpdatedName;
  final int? lastUpdatedMs;

  static const Object _keep = Object();

  UpdateState copyWith({
    Object? lastAttemptMs = _keep,
    Object? lastCheckMs = _keep,
    String? lastResult,
    String? lastSeenVersionName,
    Object? highestSeenSequence = _keep,
    bool? wifiOnly,
    bool? autoCheck,
    Object? manifestUrl = _keep,
    Object? channel = _keep,
    Object? laterVersionCode = _keep,
    Object? laterUntilMs = _keep,
    Object? queuedVersionCode = _keep,
    Object? pending = _keep,
    Object? whatsNew = _keep,
    String? lastUpdatedName,
    Object? lastUpdatedMs = _keep,
  }) =>
      UpdateState(
        lastAttemptMs: identical(lastAttemptMs, _keep) ? this.lastAttemptMs : lastAttemptMs as int?,
        lastCheckMs: identical(lastCheckMs, _keep) ? this.lastCheckMs : lastCheckMs as int?,
        lastResult: lastResult ?? this.lastResult,
        lastSeenVersionName: lastSeenVersionName ?? this.lastSeenVersionName,
        highestSeenSequence: identical(highestSeenSequence, _keep) ? this.highestSeenSequence : highestSeenSequence as int?,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        autoCheck: autoCheck ?? this.autoCheck,
        manifestUrl: identical(manifestUrl, _keep) ? this.manifestUrl : manifestUrl as String?,
        channel: identical(channel, _keep) ? this.channel : channel as String?,
        laterVersionCode: identical(laterVersionCode, _keep) ? this.laterVersionCode : laterVersionCode as int?,
        laterUntilMs: identical(laterUntilMs, _keep) ? this.laterUntilMs : laterUntilMs as int?,
        queuedVersionCode: identical(queuedVersionCode, _keep) ? this.queuedVersionCode : queuedVersionCode as int?,
        pending: identical(pending, _keep) ? this.pending : pending as PendingInstall?,
        whatsNew: identical(whatsNew, _keep) ? this.whatsNew : whatsNew as WhatsNew?,
        lastUpdatedName: lastUpdatedName ?? this.lastUpdatedName,
        lastUpdatedMs: identical(lastUpdatedMs, _keep) ? this.lastUpdatedMs : lastUpdatedMs as int?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': kUpdateStateSchema,
        if (lastAttemptMs != null) 'attempt': lastAttemptMs,
        if (lastCheckMs != null) 'check': lastCheckMs,
        'result': _clip(lastResult, 60),
        'seenName': _clip(lastSeenVersionName, 40),
        if (highestSeenSequence != null) 'seenSeq': highestSeenSequence,
        'wifiOnly': wifiOnly,
        'auto': autoCheck,
        if (manifestUrl != null) 'url': _clip(manifestUrl!, 512),
        if (channel != null) 'channel': _clip(channel!, 32),
        if (laterVersionCode != null) 'later': laterVersionCode,
        if (laterUntilMs != null) 'laterUntil': laterUntilMs,
        if (queuedVersionCode != null) 'queued': queuedVersionCode,
        if (pending != null) 'pending': pending!.toJson(),
        if (whatsNew != null) 'new': whatsNew!.toJson(),
        'updatedName': _clip(lastUpdatedName, 40),
        if (lastUpdatedMs != null) 'updatedAt': lastUpdatedMs,
      };

  /// Anything unreadable becomes the defaults: the updater must never be the reason the app does not start.
  static UpdateState fromJson(Object? o) {
    if (o is! Map || o['schema'] != kUpdateStateSchema) return const UpdateState();
    int? i(String k) => o[k] is int ? o[k] as int : null;
    String s(String k) => o[k] is String ? o[k] as String : '';
    return UpdateState(
      lastAttemptMs: i('attempt'),
      lastCheckMs: i('check'),
      lastResult: s('result'),
      lastSeenVersionName: s('seenName'),
      highestSeenSequence: i('seenSeq'),
      wifiOnly: o['wifiOnly'] is bool ? o['wifiOnly'] as bool : true,
      autoCheck: o['auto'] is bool ? o['auto'] as bool : true,
      manifestUrl: o['url'] is String && (o['url'] as String).isNotEmpty ? o['url'] as String : null,
      channel: o['channel'] is String && (o['channel'] as String).isNotEmpty ? o['channel'] as String : null,
      laterVersionCode: i('later'),
      laterUntilMs: i('laterUntil'),
      queuedVersionCode: i('queued'),
      pending: PendingInstall.fromJson(o['pending']),
      whatsNew: WhatsNew.fromJson(o['new']),
      lastUpdatedName: s('updatedName'),
      lastUpdatedMs: i('updatedAt'),
    );
  }

  static String _clip(String v, int n) => v.length <= n ? v : v.substring(0, n);

  @override
  String toString() => jsonEncode(toJson());
}

abstract class UpdateStateRepository {
  Future<UpdateState> load();

  /// Throws if it cannot be kept; the updater carries on in memory.
  Future<void> save(UpdateState s);
}

class MemoryUpdateStateRepository implements UpdateStateRepository {
  MemoryUpdateStateRepository([this._doc]);
  Object? _doc;
  int saves = 0;
  bool failSaves = false;

  /// What is "on disk", for tests.
  Object? get raw => _doc;

  @override
  Future<UpdateState> load() async => UpdateState.fromJson(_doc);

  @override
  Future<void> save(UpdateState s) async {
    if (failSaves) throw const LocalStoreFull('device.updates', 0);
    _doc = jsonDecode(jsonEncode(s.toJson()));
    saves++;
  }
}

/// Durable: the sealed device area `updates`.
class LocalStoreUpdateStateRepository implements UpdateStateRepository {
  LocalStoreUpdateStateRepository([LocalNamespace? ns]) : _fixed = ns;
  final LocalNamespace? _fixed;

  LocalNamespace get _ns => _fixed ?? LocalServices.current.area('updates');

  static const String _key = 'state';

  @override
  Future<UpdateState> load() async {
    try {
      return UpdateState.fromJson(await _ns.get(_key));
    } catch (_) {
      return const UpdateState();
    }
  }

  @override
  Future<void> save(UpdateState s) => _ns.put(_key, s.toJson());
}
