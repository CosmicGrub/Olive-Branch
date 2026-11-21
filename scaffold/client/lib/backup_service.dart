// OLIVE BRANCH — the one front door the screens use for backup: set up a recovery sheet, back up now, say how it is
// going, and make a phone ready to restore. UNVERIFIED on a device; pure Dart, runs headless in CI.
// See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// A grown-up's phone makes the FAMILY backup; a child's tablet makes only the KEEPSAKE backup (her home and the things
// that are hers, never the journal, worry box, feelings or teen areas). The role decides, and the engine refuses the
// other combination, so a tablet can never be asked to read grown-up records and a phone can never take her private
// areas.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'backup_crypto.dart';
import 'backup_engine.dart';
import 'backup_restore.dart';
import 'backup_server.dart';
import 'backup_sink.dart';
import 'backup_state.dart';
import 'backup_words.dart';
import 'device_keys.dart' show DeviceKey;
import 'local_services.dart';

/// The one thing a grown-up most needs to hear about, most urgent first.
enum BackupAttention { notSetUp, sheetNotChecked, lastTryFailed, overdue, sheetOld, fine }

class BackupStatus {
  const BackupStatus({
    required this.kind,
    required this.setUp,
    required this.attention,
    this.lastOk,
    this.lastFailureCode,
    this.sheetMadeMs,
    this.sheetCheckedMs,
    this.folderSet = false,
    this.serverOn = false,
    this.lastRestoredMs,
  });
  final BackupKind kind;
  final bool setUp;
  final BackupAttention attention;
  final BackupRecord? lastOk;
  final String? lastFailureCode;
  final int? sheetMadeMs, sheetCheckedMs, lastRestoredMs;
  final bool folderSet, serverOn;

  /// Whether any place is chosen to keep backups.
  bool get hasPlace => folderSet || serverOn;
}

const int kOverdueHours = 36;
const int kSheetLookDays = 183; // about six months

enum SheetOutcome { ok, wrongCount, unknownWord, checkFailed, resting }

class BackupService {
  BackupService({
    required this.services,
    required this.writer,
    required this.role,
    BackupStaging? staging,
    BackupServerApi? Function()? serverApi,
    DateTime Function()? clock,
    this.random,
  })  : state = BackupStateStore(services.area('backupstate')),
        staging = staging ?? MemoryBackupStaging(),
        // ignore: prefer_initializing_formals
        _serverApi = serverApi,
        _clock = clock ?? DateTime.now;

  final LocalServices services;
  final DeviceKey writer;
  final BackupRole role;
  final BackupStateStore state;
  final BackupStaging staging;
  final Random? random;
  final BackupServerApi? Function()? _serverApi;
  final DateTime Function() _clock;

  int get _nowMs => _clock().millisecondsSinceEpoch;

  /// The kind of backup this phone or tablet makes.
  BackupKind get kind => role == BackupRole.guardian ? BackupKind.family : BackupKind.keepsake;

  /// The family's server client when one is signed in (for the restore screen), else null.
  BackupServerApi? serverApiForScreens() => _serverApi?.call();

  /// Whether the family's server can be asked from here at all (a grown-up's phone with a signed-in session).
  bool get canUseServer => role == BackupRole.guardian && _serverApi?.call() != null;

  BackupEngine get engine => BackupEngine(
      services: services, state: state, staging: staging, writer: writer, role: role, clock: _clock, random: random);

  RestoreEngine restoreEngine({RestoreClearanceGate? gate}) =>
      RestoreEngine(services: services, state: state, role: role, gate: gate, clock: _clock, random: random);

  // --- the sheet ------------------------------------------------------------------------------------------------------

  /// Makes a NEW recovery sheet. The returned key's words are shown once and are kept nowhere; only the public half is
  /// stored, so this phone can make backups all day and cannot open one. A new sheet locks FUTURE backups only: the
  /// old ones still open with the old sheet.
  Future<RecoveryKey> setUp() async {
    final RecoveryKey key = RecoveryKey.generate(random: random);
    await _adopt(key);
    await state.markSheetMade(kind, _nowMs);
    return key;
  }

  Future<void> _adopt(RecoveryKey key) async {
    final BackupKeyPair pair = await deriveBackupKeyPair(key, kind);
    final BackupAuthority authority = await deriveBackupAuthority(key, kind);
    await state.setPublicKey(kind, pair.publicKey);
    await state.setWriterCert(kind, writer.publicKey, await authority.certifyWriter(writer.publicKey, kind));
  }

  /// A phone that is typing a sheet it already has (a second grown-up, a new phone after a restore) becomes a phone
  /// that can write backups for that sheet. Wrong tries rest after five.
  Future<SheetOutcome> joinWithSheet(String typed) async {
    if (await state.restLeftMs(_nowMs) > 0) return SheetOutcome.resting;
    final SheetParse p = RecoveryKey.parse(typed);
    if (!p.ok) {
      // A typing mistake the check words catch is not a guess: it does not count toward the rest.
      return switch (p.problem!) {
        SheetProblem.wrongCount => SheetOutcome.wrongCount,
        SheetProblem.unknownWord => SheetOutcome.unknownWord,
        SheetProblem.checkFailed => SheetOutcome.checkFailed,
      };
    }
    await adoptSheet(p.key!);
    return SheetOutcome.ok;
  }

  /// Makes this phone a writer for [key]'s sheet, and marks the sheet as made and checked (the person just typed it).
  Future<void> adoptSheet(RecoveryKey key) async {
    await _adopt(key);
    await state.markSheetMade(kind, _nowMs);
    await state.markSheetChecked(kind, _nowMs);
  }

  /// "Type the first and last words" (the paper check). True when they match; only then is the sheet counted as
  /// written down. Nothing is sent anywhere.
  Future<bool> confirmSheet(RecoveryKey key, String first, String last) async {
    if (!key.paperMatches(first, last)) return false;
    await state.markSheetChecked(kind, _nowMs);
    return true;
  }

  /// The grown-up looked at the paper again (the six-month reminder).
  Future<void> sheetLookedAt() => state.markSheetChecked(kind, _nowMs);

  // --- places ---------------------------------------------------------------------------------------------------------

  Future<void> chooseFolder(String? path) => state.setFolderPath(path);

  /// Turns the family's server on: makes or joins the family's vault with the person's own PIN and the sheet's PUBLIC
  /// signing key. Needs the sheet typed again (the words are not kept), and refuses a sheet that is not this phone's.
  Future<void> turnOnServer({required RecoveryKey key, required String pin}) async {
    final BackupServerApi? api = _serverApi?.call();
    if (api == null || role != BackupRole.guardian) throw const BackupSinkException('signed_out');
    final BackupKeyPair pair = await deriveBackupKeyPair(key, kind);
    final Uint8List? mine = await state.publicKey(kind);
    if (mine == null || hexString(mine) != hexString(pair.publicKey)) throw const BackupSinkException('refused', 'other_sheet');
    await setUpServerVault(api: api, state: state, authority: await deriveBackupAuthority(key, kind), pin: pin);
    await state.setServerOn(true);
  }

  Future<void> turnOffServer() => state.setServerOn(false);

  Future<List<BackupSink>> sinks() async {
    final List<BackupSink> out = <BackupSink>[];
    final String? folder = await state.folderPath();
    if (folder != null) out.add(DirectoryBackupSink(Directory(folder)));
    if (role == BackupRole.guardian && await state.serverOn()) {
      final BackupServerApi? api = _serverApi?.call();
      if (api != null) out.add(ServerBackupSink(api: api, state: state, writer: writer));
    }
    return out;
  }

  // --- making a backup ----------------------------------------------------------------------------------------------

  /// Backs up to every chosen place. Throws [BackupNotSetUp] with no sheet, and [StateError] with no place.
  Future<BackupReport> backUpNow({List<BackupSink>? extraSinks}) async {
    final List<BackupSink> all = <BackupSink>[...await sinks(), ...?extraSinks];
    if (all.isEmpty) throw StateError('no place to keep a backup has been chosen');
    return engine.backUp(kind: kind, sinks: all);
  }

  /// Time for a backup: set up, somewhere to put it, and none in the last day.
  Future<bool> due() async {
    if (await state.publicKey(kind) == null) return false;
    if ((await sinks()).isEmpty) return false;
    final BackupRecord? ok = await state.lastSuccess(kind);
    if (ok == null) return true;
    return _nowMs - ok.atMs >= 24 * 3600 * 1000;
  }

  // --- how it is going -------------------------------------------------------------------------------------------------

  Future<BackupStatus> status() async {
    final Uint8List? pk = await state.publicKey(kind);
    final BackupRecord? ok = await state.lastSuccess(kind);
    final BackupAttempt? fail = await state.lastFailure(kind);
    final sheet = await state.sheet(kind);
    final bool folder = await state.folderPath() != null;
    final bool server = role == BackupRole.guardian && await state.serverOn();
    final BackupAttention a;
    if (pk == null) {
      a = BackupAttention.notSetUp;
    } else if (sheet.checkedMs == null) {
      a = BackupAttention.sheetNotChecked;
    } else if (fail != null && (ok == null || fail.atMs > ok.atMs)) {
      a = BackupAttention.lastTryFailed;
    } else if (ok == null || _nowMs - ok.atMs > kOverdueHours * 3600 * 1000) {
      a = BackupAttention.overdue;
    } else if (_nowMs - sheet.checkedMs! > kSheetLookDays * 24 * 3600 * 1000) {
      a = BackupAttention.sheetOld;
    } else {
      a = BackupAttention.fine;
    }
    return BackupStatus(
      kind: kind,
      setUp: pk != null,
      attention: a,
      lastOk: ok,
      lastFailureCode: fail?.code,
      sheetMadeMs: sheet.madeMs,
      sheetCheckedMs: sheet.checkedMs,
      folderSet: folder,
      serverOn: server,
      lastRestoredMs: await state.lastRestoredMs(),
    );
  }

  /// Run at every start: undoes a restore that was cut off before it finished, or tidies one that had.
  Future<RecoveryReport> recoverOnStart() => restoreEngine().recoverInterrupted();
}
