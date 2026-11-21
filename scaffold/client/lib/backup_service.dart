// OLIVE BRANCH — making a backup: read, seal, stage, send what is missing, commit, check, and only then forget the
// older ones. UNVERIFIED on a device; pure Dart, runs headless in CI (client/test/backup_service_test.dart and
// backup_kill_test.dart). Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// WHAT IT NEVER DOES. It never writes to the family's data: the only thing it writes on the phone is the small
// `backup` area (settings, the last result, a note that a backup is part way). A backup that dies at ANY point leaves
// the phone's data exactly as it was and the previous backup exactly as it was: a new set only counts once its commit
// lands, and an older set is removed only after the newer one has been read back.
//
// THE STEPS, AND WHAT A KILL AT EACH LEAVES.
//   1 note       the `backup` area says "preparing set S". Kill: nothing sealed yet; next run clears S's leftovers.
//   2 seal       read the snapshot, seal each chunk into a local staging folder. Kill: S is incomplete; next run clears it
//                and starts again (the data may have changed; a fresh snapshot is better than finishing a stale one).
//   3 stage      the staging folder commits S ("prepared"), the note says so. Kill: S is whole and waiting.
//   4 send       every chunk the destination lacks is sent (a chunk is content-named, so sending twice is harmless).
//                Kill: next run finds S prepared and sends only what is still missing (resume), if S is under a day old.
//   5 commit     the destination commits S. Before this the destination sees no new set; after, S is the newest.
//   6 check      S is read back from the destination (names, sizes and, for a folder, every chunk's bytes).
//   7 record     the `backup` area records the success. Older sets beyond the newest three are removed.
// The secret half of the key is never here: [run] takes the PUBLIC key.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'backup_classes.dart';
import 'backup_format.dart';
import 'backup_keys.dart';
import 'backup_targets.dart';
import 'device_keys.dart' show b64, unb64;
import 'local_services.dart';
import 'local_store.dart';

/// How long a staged set may wait before it is thrown away and a fresh one made.
const Duration kStagedMaxAge = Duration(hours: 24);

/// A phone is "behind" after this long without a successful backup.
const Duration kBackupBehindAfter = Duration(days: 7);

/// A successful backup is due after this long; a failed try waits [kBackupRetryAfter] before the next automatic one.
const Duration kBackupDueAfter = Duration(hours: 24);
const Duration kBackupRetryAfter = Duration(minutes: 30);

/// How many committed sets each destination keeps.
const int kKeepSets = 3;

// ------------------------------------------------------------------ the small records in the `backup` area

class BackupSettings {
  const BackupSettings({this.auto = true, this.folderOn = true, this.folderPath, this.serverOn = false});

  /// Back up by itself when due. On by default: "once a place exists, it just happens".
  final bool auto;
  final bool folderOn;

  /// Null means the app's own backup folder.
  final String? folderPath;
  final bool serverOn;

  bool get hasDestination => folderOn || serverOn;

  Map<String, Object?> toJson() =>
      <String, Object?>{'auto': auto, 'folderOn': folderOn, 'folderPath': folderPath, 'serverOn': serverOn};

  static BackupSettings fromJson(Object? j) {
    if (j is! Map) return const BackupSettings();
    return BackupSettings(
      auto: j['auto'] != false,
      folderOn: j['folderOn'] != false,
      folderPath: j['folderPath'] is String ? j['folderPath'] as String : null,
      serverOn: j['serverOn'] == true,
    );
  }

  BackupSettings copyWith({bool? auto, bool? folderOn, String? folderPath, bool clearFolderPath = false, bool? serverOn}) =>
      BackupSettings(
        auto: auto ?? this.auto,
        folderOn: folderOn ?? this.folderOn,
        folderPath: clearFolderPath ? null : (folderPath ?? this.folderPath),
        serverOn: serverOn ?? this.serverOn,
      );
}

/// What the phone remembers about the family recovery sheet: never the secret, only that it was made and checked.
class SheetRecord {
  const SheetRecord({required this.sheetId, required this.publicKey, required this.madeMs, this.confirmedMs, this.remindedMs});
  final String sheetId;
  final Uint8List publicKey;
  final int madeMs;
  final int? confirmedMs;
  final int? remindedMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': sheetId,
        'pub': b64(publicKey),
        'made': madeMs,
        'ok': confirmedMs,
        'rem': remindedMs,
      };

  static SheetRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final Uint8List pub = unb64(j['pub'] as String);
      if (pub.length != 32) return null;
      return SheetRecord(
          sheetId: j['id'] as String,
          publicKey: pub,
          madeMs: j['made'] as int,
          confirmedMs: j['ok'] as int?,
          remindedMs: j['rem'] as int?);
    } catch (_) {
      return null;
    }
  }
}

class BackupLast {
  const BackupLast({required this.kind, required this.ok, required this.atMs, this.setId, this.areas = 0, this.bytes = 0,
      this.hash, this.dest, this.code, this.unreadable = 0});
  final BackupKind kind;
  final bool ok;
  final int atMs;
  final String? setId;
  final int areas;
  final int bytes;
  final String? hash;
  final String? dest;
  final String? code;
  final int unreadable;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.word,
        'ok': ok,
        'at': atMs,
        'set': setId,
        'areas': areas,
        'bytes': bytes,
        'hash': hash,
        'dest': dest,
        'code': code,
        'unreadable': unreadable,
      };

  static BackupLast? fromJson(Object? j) {
    if (j is! Map) return null;
    final BackupKind? k = BackupKind.fromWord(j['kind']);
    if (k == null || j['at'] is! int) return null;
    return BackupLast(
        kind: k,
        ok: j['ok'] == true,
        atMs: j['at'] as int,
        setId: j['set'] as String?,
        areas: (j['areas'] as int?) ?? 0,
        bytes: (j['bytes'] as int?) ?? 0,
        hash: j['hash'] as String?,
        dest: j['dest'] as String?,
        code: j['code'] as String?,
        unreadable: (j['unreadable'] as int?) ?? 0);
  }
}

/// All reads and writes of the `backup` area, in one place.
class BackupJournal {
  BackupJournal(this._ns);
  final LocalNamespace _ns;

  Future<BackupSettings> settings() async => BackupSettings.fromJson(await _ns.get('settings'));
  Future<void> saveSettings(BackupSettings s) => _ns.put('settings', s.toJson());

  Future<SheetRecord?> familySheet() async => SheetRecord.fromJson(await _ns.get('sheet.family'));
  Future<void> saveFamilySheet(SheetRecord r) => _ns.put('sheet.family', r.toJson());

  /// The last SUCCESS per kind and destination, and the last TRY per kind (success or not).
  Future<BackupLast?> lastSuccess(BackupKind k, String dest) async => BackupLast.fromJson(await _ns.get('ok.${k.word}.$dest'));
  Future<BackupLast?> lastTry(BackupKind k) async => BackupLast.fromJson(await _ns.get('try.${k.word}'));
  Future<void> recordTry(BackupLast l) => _ns.put('try.${l.kind.word}', l.toJson());
  Future<void> recordSuccess(BackupLast l) async {
    await _ns.put('ok.${l.kind.word}.${l.dest}', l.toJson());
    await _ns.put('try.${l.kind.word}', l.toJson());
  }

  /// The newest success on any destination.
  Future<BackupLast?> newestSuccess(BackupKind k) async {
    BackupLast? best;
    for (final String d in const <String>['folder', 'server']) {
      final BackupLast? l = await lastSuccess(k, d);
      if (l != null && (best == null || l.atMs > best.atMs)) best = l;
    }
    return best;
  }

  Future<int> nextSeq(BackupKind k) async {
    final Object? v = await _ns.get('seq.${k.word}');
    final int n = (v is int ? v : 0) + 1;
    await _ns.put('seq.${k.word}', n);
    return n;
  }

  Future<Map<String, Object?>?> inflight(BackupKind k, String dest) async {
    final Object? v = await _ns.get('inflight.${k.word}.$dest');
    return v is Map ? Map<String, Object?>.from(v) : null;
  }

  Future<void> setInflight(BackupKind k, String dest, Map<String, Object?>? v) =>
      v == null ? _ns.delete('inflight.${k.word}.$dest') : _ns.put('inflight.${k.word}.$dest', v);
}

// ------------------------------------------------------------------ the service

/// Somewhere a backup goes, and the local staging folder that goes with it.
class BackupDestination {
  BackupDestination({required this.id, required this.target, required this.spool, this.verifyEveryChunk = false});

  /// 'folder' or 'server'.
  final String id;
  final BackupTarget target;

  /// Local staging for sealed chunks until the destination has committed them. One per destination.
  final BackupTarget spool;

  /// A folder is read back byte by byte; a server is checked by names and sizes (it would mean downloading it all).
  final bool verifyEveryChunk;
}

class BackupOutcome {
  const BackupOutcome({required this.ok, this.code, this.setId, this.sentChunks = 0, this.totalChunks = 0,
      this.resumed = false, this.areas = 0, this.bytes = 0, this.nothingToBackUp = false, this.unreadable = const <String>[]});
  final bool ok;

  /// For a failure: 'offline', 'refused', 'full', 'io', 'verify', 'busy'.
  final String? code;
  final String? setId;
  final int sentChunks;
  final int totalChunks;
  final bool resumed;
  final int areas;
  final int bytes;
  final bool nothingToBackUp;
  final List<String> unreadable;
}

final Set<String> _running = <String>{};

class BackupService {
  BackupService({required this.services, DateTime Function()? clock, Random? random, this.deviceLabel = "A grown-up's phone"})
      : _clock = clock ?? DateTime.now,
        _random = random;
  final LocalServices services;
  final DateTime Function() _clock;
  final Random? _random;
  final String deviceLabel;

  LocalStore get store => services.store;
  BackupJournal get journal => BackupJournal(services.area('backup'));
  int get _nowMs => _clock().millisecondsSinceEpoch;

  /// Takes the family sheet's PUBLIC half and the sheet's id and remembers them. The secret is never passed in.
  Future<void> rememberFamilySheet(RecoverySheet sheet) =>
      journal.saveFamilySheet(SheetRecord(sheetId: sheet.sheetId, publicKey: sheet.publicKey, madeMs: _nowMs));

  /// Marks the sheet as checked (the "type the first and last words" step passed).
  Future<void> confirmFamilySheet() async {
    final SheetRecord? r = await journal.familySheet();
    if (r == null) return;
    await journal.saveFamilySheet(SheetRecord(
        sheetId: r.sheetId, publicKey: r.publicKey, madeMs: r.madeMs, confirmedMs: _nowMs, remindedMs: r.remindedMs));
  }

  /// One backup of [kind] to [dest], locked to [recipientPublicKey]. Safe to call again after any interruption.
  Future<BackupOutcome> run(BackupKind kind, BackupDestination dest, Uint8List recipientPublicKey,
      {void Function(int done, int total)? onProgress}) async {
    final String lockKey = '${identityHashCode(store)}/${kind.word}/${dest.id}';
    if (!_running.add(lockKey)) return const BackupOutcome(ok: false, code: 'busy');
    try {
      return await _run(kind, dest, recipientPublicKey, onProgress);
    } finally {
      _running.remove(lockKey);
    }
  }

  Future<BackupOutcome> _run(BackupKind kind, BackupDestination dest, Uint8List pub, void Function(int, int)? onProgress) async {
    final BackupJournal j = journal;
    String? setId;
    try {
      // Resume a staged set that is whole and not stale.
      SealedHeaderInfo? staged = await _findStaged(j, kind, dest);
      bool resumed = staged != null;
      int areas = 0, bytes = 0;
      List<String> unreadable = const <String>[];
      String hash = '';
      if (staged == null) {
        final BackupSnapshot snap = await captureSnapshot(store, kind);
        if (snap.isEmpty && snap.unreadable.isEmpty) {
          return const BackupOutcome(ok: true, nothingToBackUp: true);
        }
        areas = snap.areas.length;
        bytes = snap.totalBytes;
        unreadable = snap.unreadable;
        hash = snap.contentHash;
        final Random r = _random ?? Random.secure();
        setId = _hex(List<int>.generate(16, (_) => r.nextInt(256)));
        await j.setInflight(kind, dest.id, <String, Object?>{'set': setId, 'phase': 'preparing', 'at': _nowMs});
        final int seq = await j.nextSeq(kind);
        final SealedSet sealed = await sealSnapshot(snap, pub,
            onChunk: (String id, Uint8List b) => dest.spool.putChunk(kind, setId!, id, b),
            createdMs: _nowMs,
            seq: seq,
            from: deviceLabel,
            setId: setId,
            random: _random);
        await dest.spool.commit(kind, setId, sealed.header, sealed.manifest);
        await j.setInflight(kind, dest.id, <String, Object?>{
          'set': setId,
          'phase': 'prepared',
          'at': _nowMs,
          'areas': areas,
          'bytes': bytes,
          'hash': hash,
          'unreadable': unreadable.length,
        });
        staged = SealedHeaderInfo(setId, sealed.header, sealed.manifest, areas, bytes, hash, unreadable.length);
      } else {
        setId = staged.setId;
        areas = staged.areas;
        bytes = staged.bytes;
        hash = staged.hash;
      }

      // Send what the destination lacks.
      final BackupHeader h = BackupHeader.parse(staged.header);
      final Set<String> have = await dest.target.chunkIds(kind, setId);
      final List<String> missing = <String>[for (final String id in h.chunkIds) if (!have.contains(id)) id];
      int sent = 0;
      onProgress?.call(h.chunks.length - missing.length, h.chunks.length);
      for (final String id in missing) {
        final Uint8List? b = await dest.spool.getChunk(kind, setId, id);
        if (b == null) {
          // The staged copy lost a chunk: this set cannot finish. Start again next time with a fresh one.
          await dest.spool.remove(kind, setId);
          await j.setInflight(kind, dest.id, null);
          return const BackupOutcome(ok: false, code: 'io');
        }
        await dest.target.putChunk(kind, setId, id, b);
        sent++;
        onProgress?.call(h.chunks.length - missing.length + sent, h.chunks.length);
      }
      await dest.target.commit(kind, setId, staged.header, staged.manifest);

      // Read it back before trusting it, and before forgetting anything older.
      if (!await _verify(dest, kind, setId, staged.header)) {
        await _recordFailure(j, kind, dest, 'verify');
        return BackupOutcome(ok: false, code: 'verify', setId: setId, sentChunks: sent, totalChunks: h.chunks.length);
      }
      await j.recordSuccess(BackupLast(
          kind: kind, ok: true, atMs: _nowMs, setId: setId, areas: areas, bytes: bytes, hash: hash, dest: dest.id,
          unreadable: staged.unreadable));
      await j.setInflight(kind, dest.id, null);
      await dest.spool.remove(kind, setId);
      await _prune(dest, kind, setId);
      return BackupOutcome(ok: true, setId: setId, sentChunks: sent, totalChunks: h.chunks.length, resumed: resumed,
          areas: areas, bytes: bytes, unreadable: unreadable);
    } on BackupTargetException catch (e) {
      await _recordFailure(j, kind, dest, e.code);
      return BackupOutcome(ok: false, code: e.code, setId: setId);
    } on SocketException {
      await _recordFailure(j, kind, dest, 'offline');
      return BackupOutcome(ok: false, code: 'offline', setId: setId);
    } on FileSystemException {
      await _recordFailure(j, kind, dest, 'io');
      return BackupOutcome(ok: false, code: 'io', setId: setId);
    } on LocalStoreException {
      await _recordFailure(j, kind, dest, 'io');
      return BackupOutcome(ok: false, code: 'io', setId: setId);
    }
    // An Error (a kill, a bug) is not caught here on purpose: nothing may pretend to have finished.
  }

  Future<void> _recordFailure(BackupJournal j, BackupKind kind, BackupDestination dest, String code) =>
      j.recordTry(BackupLast(kind: kind, ok: false, atMs: _nowMs, dest: dest.id, code: code));

  Future<SealedHeaderInfo?> _findStaged(BackupJournal j, BackupKind kind, BackupDestination dest) async {
    final Map<String, Object?>? note = await j.inflight(kind, dest.id);
    if (note == null) return null;
    final String? id = note['set'] as String?;
    final int at = (note['at'] as int?) ?? 0;
    if (id == null) {
      await j.setInflight(kind, dest.id, null);
      return null;
    }
    CommittedSet? c;
    if (note['phase'] == 'prepared') {
      for (final CommittedSet s in await dest.spool.committed(kind)) {
        if (s.setId == id) c = s;
      }
    }
    final bool fresh = _nowMs - at <= kStagedMaxAge.inMilliseconds;
    if (c != null && fresh) {
      // Whole and recent: resume it.
      return SealedHeaderInfo(id, c.header, c.manifest, (note['areas'] as int?) ?? 0, (note['bytes'] as int?) ?? 0,
          (note['hash'] as String?) ?? '', (note['unreadable'] as int?) ?? 0);
    }
    // Part-made or stale: clear what it left and start again.
    await dest.spool.remove(kind, id);
    await j.setInflight(kind, dest.id, null);
    return null;
  }

  Future<bool> _verify(BackupDestination dest, BackupKind kind, String setId, Uint8List header) async {
    CommittedSet? found;
    for (final CommittedSet s in await dest.target.committed(kind)) {
      if (s.setId == setId) found = s;
    }
    if (found == null || !_same(found.header, header)) return false;
    final BackupHeader h = BackupHeader.parse(header);
    final Set<String> have = await dest.target.chunkIds(kind, setId);
    for (final MapEntry<String, int> c in h.chunks) {
      if (!have.contains(c.key)) return false;
      if (dest.verifyEveryChunk) {
        final Uint8List? b = await dest.target.getChunk(kind, setId, c.key);
        if (b == null || b.length != c.value || await sha256Hex(b) != c.key) return false;
      }
    }
    return true;
  }

  Future<void> _prune(BackupDestination dest, BackupKind kind, String justMade) async {
    final List<CommittedSet> all = await dest.target.committed(kind);
    if (all.length <= kKeepSets) return;
    int kept = 0;
    for (final CommittedSet s in all) {
      if (s.setId == justMade || kept < kKeepSets) {
        kept++;
        continue;
      }
      await dest.target.remove(kind, s.setId);
    }
  }

  /// Runs every backup that is due for the destinations in [dests], if automatic backup is on. Returns what ran.
  Future<Map<String, BackupOutcome>> runIfDue(BackupKind kind, Map<String, BackupDestination> dests, Uint8List pub) async {
    final BackupSettings s = await journal.settings();
    final Map<String, BackupOutcome> out = <String, BackupOutcome>{};
    if (!s.auto) return out;
    final BackupLast? lastTry = await journal.lastTry(kind);
    for (final MapEntry<String, BackupDestination> d in dests.entries) {
      if (d.key == 'folder' && !s.folderOn) continue;
      if (d.key == 'server' && !s.serverOn) continue;
      final BackupLast? ok = await journal.lastSuccess(kind, d.key);
      final bool due = ok == null || _nowMs - ok.atMs >= kBackupDueAfter.inMilliseconds;
      final bool coolingOff = lastTry != null && !lastTry.ok && _nowMs - lastTry.atMs < kBackupRetryAfter.inMilliseconds;
      if (due && !coolingOff) out[d.key] = await run(kind, d.value, pub);
    }
    return out;
  }
}

class SealedHeaderInfo {
  SealedHeaderInfo(this.setId, this.header, this.manifest, this.areas, this.bytes, this.hash, this.unreadable);
  final String setId;
  final Uint8List header;
  final Uint8List manifest;
  final int areas;
  final int bytes;
  final String hash;
  final int unreadable;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(List<int> b) => b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

// ------------------------------------------------------------------ her tablet's two secrets

/// The two secrets a child's tablet holds, in the `childkeys` area. They are made on first need, never shown to her,
/// never part of a backup, and read only by a grown-up behind the grown-up gate to move her to a new tablet.
class ChildKeyKeeper {
  ChildKeyKeeper(this._ns);
  final LocalNamespace _ns;

  Future<ChildSecrets?> read() async => ChildSecrets.fromJson(await _ns.get('secrets'));

  Future<ChildSecrets> ensure({Random? random}) async {
    final ChildSecrets? have = await read();
    if (have != null) return have;
    final ChildSecrets made = ChildSecrets.make(random);
    await _ns.put('secrets', made.toJson());
    return made;
  }

  /// Takes the secrets from the old tablet so this tablet's later backups, and the old tablet's backups, share keys.
  Future<void> adopt(ChildSecrets s) => _ns.put('secrets', s.toJson());
}

// ------------------------------------------------------------------ plain words for the status line

enum BackupMood { none, ok, behind, failed, paused }

class BackupStatusView {
  const BackupStatusView(this.mood, this.headline, this.detail, {this.action});
  final BackupMood mood;
  final String headline;
  final String detail;

  /// The one button that fits ('Back up now', 'Set up backup'), or null.
  final String? action;
}

String _ago(int ms) {
  final int mins = ms ~/ 60000;
  if (mins < 2) return 'just now';
  if (mins < 60) return '$mins minutes ago';
  final int hours = mins ~/ 60;
  if (hours < 24) return hours == 1 ? 'an hour ago' : '$hours hours ago';
  final int days = hours ~/ 24;
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  final int weeks = days ~/ 7;
  return '$weeks weeks ago';
}

String _where(String? dest) => switch (dest) {
      'server' => "on your family's Olive server",
      'folder' => 'in the backup folder on this phone',
      _ => '',
    };

/// The adult-words status for a kind of backup. [last] is the newest success; [lastTry] the newest try.
BackupStatusView describeBackupStatus({
  required BackupSettings settings,
  required BackupLast? last,
  required BackupLast? lastTry,
  required SheetRecord? sheet,
  required int nowMs,
}) {
  if (!settings.hasDestination) {
    return const BackupStatusView(BackupMood.paused, 'Backup is off',
        'Choose a place to keep your backup. Until then your records are only on this phone.',
        action: 'Choose a place');
  }
  final bool failedSince = lastTry != null && !lastTry.ok && (last == null || lastTry.atMs > last.atMs);
  if (last == null) {
    return BackupStatusView(
        failedSince ? BackupMood.failed : BackupMood.none,
        'No backup yet',
        failedSince
            ? 'The last try did not finish. ${_failWords(lastTry.code)} Nothing on this phone was changed.'
            : 'Your records are only on this phone for now. It takes a minute to back them up.',
        action: 'Back up now');
  }
  final int age = nowMs - last.atMs;
  final String where = _where(last.dest);
  final String skipped = last.unreadable > 0
      ? ' ${last.unreadable == 1 ? 'One thing' : '${last.unreadable} things'} on this phone could not be read, so '
          '${last.unreadable == 1 ? 'it was' : 'they were'} left out.'
      : '';
  final String sheetNote = sheet == null || sheet.confirmedMs == null
      ? ' You have not checked your recovery sheet yet.'
      : '';
  if (failedSince) {
    return BackupStatusView(BackupMood.failed, 'Your last backup is safe, but the newest try did not finish',
        'Your last good backup was ${_ago(age)} $where. ${_failWords(lastTry.code)}$skipped',
        action: 'Try again');
  }
  if (age >= kBackupBehindAfter.inMilliseconds) {
    return BackupStatusView(BackupMood.behind, 'Your backup is a little old',
        'The last backup was ${_ago(age)} $where. It will update the next time this phone can reach it.$skipped$sheetNote',
        action: 'Back up now');
  }
  return BackupStatusView(BackupMood.ok, 'Backed up ${_ago(age)}',
      'Kept $where, sealed on this phone so nobody who keeps it can read it.$skipped$sheetNote');
}

String _failWords(String? code) => switch (code) {
      'offline' => "It could not reach the server. It will try again when it can.",
      'refused' => 'The place you chose said no. Check that it is still switched on.',
      'full' => 'The place you chose is full. Free some room, or choose another place.',
      'io' => 'The folder could not be written to. Check that it still exists and has room.',
      'verify' => 'It sent the backup but could not read it back to check it, so it does not count yet.',
      'busy' => 'A backup was already running.',
      _ => 'It did not finish.',
    };

/// The plain reminder wording for the twice-a-year check of the paper (shown quietly, never as a pop-up).
bool sheetReminderDue(SheetRecord? sheet, int nowMs) {
  if (sheet == null) return false;
  const int sixMonths = 182 * 24 * 60 * 60 * 1000;
  final int since = sheet.remindedMs ?? sheet.confirmedMs ?? sheet.madeMs;
  return nowMs - since >= sixMonths;
}
