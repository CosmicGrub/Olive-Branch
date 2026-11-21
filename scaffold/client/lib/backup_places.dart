// OLIVE BRANCH — where this device's backups live and how the app runs them, with no screens in it. UNVERIFIED on a
// device; pure Dart (client/test/backup_places_test.dart). Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// [BackupPlaces] is the one seam between the backup engine and the phone: the folder a backup is written to, the family's
// server if there is one, and reading a backup file a grown-up brought. The engine and the screens talk only to this, so
// they are tested without a phone and a different place can be added without touching either.
//
// THE FOLDER. On Android the app's own folder on shared storage (reachable with a file manager or a USB cable, so a
// grown-up can copy it off the phone), falling back to the app's documents folder. Nothing in it can be read without a
// recovery sheet or a tablet's keys.
//
// RUNNING IT. [runFamilyBackupIfDue] and [runChildBackupsIfDue] are what the app calls at start-up and when it comes
// back to the front: they back up only when one is due, never show anything, and never throw. [recoverRestoreAtStart]
// finishes or undoes a restore that was interrupted, before anything reads the store.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'backup_classes.dart';
import 'backup_keys.dart';
import 'backup_service.dart';
import 'backup_targets.dart';
import 'local_services.dart';
import 'restore_engine.dart';

abstract class BackupPlaces {
  /// Whether the family's own server can be used from here (a signed-in, connected build).
  bool get serverAvailable;

  /// Where backups are written for [settings].
  Map<String, BackupDestination> destinations(BackupSettings settings);

  /// A target to restore FROM.
  BackupTarget? sourceFor(String id, BackupSettings settings);

  /// Reads a backup file a grown-up brought (a single `.olivebackup` file) into a throwaway place a restore can read.
  Future<BackupTarget> targetFromFile(String path);

  /// Writes the newest [kind] backup as ONE file to carry, and says its name. Null when there is none yet.
  Future<String?> saveCopyFile(BackupKind kind, BackupSettings settings);
}

class DeviceBackupPlaces implements BackupPlaces {
  DeviceBackupPlaces({required this.root, this.wire});
  final Directory root;
  final BackupWire? wire;

  static Future<DeviceBackupPlaces> forDevice({BackupWire? wire}) async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    return DeviceBackupPlaces(root: Directory('${base.path}${Platform.pathSeparator}olive_backups'), wire: wire);
  }

  @override
  bool get serverAvailable => wire != null;

  Directory _folderDir(BackupSettings s) => s.folderPath == null ? Directory('${root.path}${Platform.pathSeparator}kept') : Directory(s.folderPath!);
  DirectoryBackupTarget _spool(String id) =>
      DirectoryBackupTarget(Directory('${root.path}${Platform.pathSeparator}staging${Platform.pathSeparator}$id'));

  @override
  Map<String, BackupDestination> destinations(BackupSettings settings) => <String, BackupDestination>{
        'folder': BackupDestination(
            id: 'folder', target: DirectoryBackupTarget(_folderDir(settings)), spool: _spool('folder'), verifyEveryChunk: true),
        if (wire != null) 'server': BackupDestination(id: 'server', target: ServerBackupTarget(wire!), spool: _spool('server')),
      };

  @override
  BackupTarget? sourceFor(String id, BackupSettings settings) => switch (id) {
        'folder' => DirectoryBackupTarget(_folderDir(settings)),
        'server' => wire == null ? null : ServerBackupTarget(wire!),
        _ => null,
      };

  @override
  Future<BackupTarget> targetFromFile(String path) async {
    final File f = File(path);
    if (!await f.exists()) throw const BackupTargetException('missing', 'That file is not there.');
    final MemoryBackupTarget t = MemoryBackupTarget();
    await BackupBundle.unpackInto(t, await f.readAsBytes());
    return t;
  }

  @override
  Future<String?> saveCopyFile(BackupKind kind, BackupSettings settings) async {
    final DirectoryBackupTarget t = DirectoryBackupTarget(_folderDir(settings));
    final List<CommittedSet> sets = await t.committed(kind);
    if (sets.isEmpty) return null;
    final Uint8List bytes = await BackupBundle.pack(t, kind, sets.first.setId);
    await root.create(recursive: true);
    final String name = 'olive-${kind.word}-backup.olivebackup';
    final File out = File('${root.path}${Platform.pathSeparator}$name');
    final File tmp = File('${out.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(out.path);
    return name;
  }
}

/// Memory-backed places for tests and the offline preview.
class MemoryBackupPlaces implements BackupPlaces {
  MemoryBackupPlaces({this.withServer = false});
  final bool withServer;
  final MemoryBackupTarget folder = MemoryBackupTarget();
  final MemoryBackupTarget server = MemoryBackupTarget();
  final Map<String, MemoryBackupTarget> files = <String, MemoryBackupTarget>{};
  final Map<String, MemoryBackupTarget> spools = <String, MemoryBackupTarget>{};

  @override
  bool get serverAvailable => withServer;

  @override
  Map<String, BackupDestination> destinations(BackupSettings settings) => <String, BackupDestination>{
        'folder': BackupDestination(id: 'folder', target: folder, spool: spools.putIfAbsent('folder', MemoryBackupTarget.new), verifyEveryChunk: true),
        if (withServer) 'server': BackupDestination(id: 'server', target: server, spool: spools.putIfAbsent('server', MemoryBackupTarget.new)),
      };

  @override
  BackupTarget? sourceFor(String id, BackupSettings settings) => switch (id) {
        'folder' => folder,
        'server' => withServer ? server : null,
        _ => null,
      };

  @override
  Future<BackupTarget> targetFromFile(String path) async {
    final MemoryBackupTarget? t = files[path];
    if (t == null) throw const BackupTargetException('missing', 'That file is not there.');
    return t;
  }

  @override
  Future<String?> saveCopyFile(BackupKind kind, BackupSettings settings) async {
    final List<CommittedSet> sets = await folder.committed(kind);
    if (sets.isEmpty) return null;
    final String name = 'olive-${kind.word}-backup.olivebackup';
    final MemoryBackupTarget t = MemoryBackupTarget();
    await BackupBundle.unpackInto(t, await BackupBundle.pack(folder, kind, sets.first.setId));
    files[name] = t;
    return name;
  }
}

// ------------------------------------------------------------------ what the app runs

/// Backs up the family's records if a backup is due and a recovery sheet has been made and checked. Never throws, never
/// shows anything. Returns what ran (for tests).
Future<Map<String, BackupOutcome>> runFamilyBackupIfDue(LocalServices services, BackupPlaces places) async {
  try {
    final BackupService svc = BackupService(services: services);
    final SheetRecord? sheet = await svc.journal.familySheet();
    if (sheet == null || sheet.confirmedMs == null) return const <String, BackupOutcome>{};
    final BackupSettings s = await svc.journal.settings();
    return await svc.runIfDue(BackupKind.family, places.destinations(s), sheet.publicKey);
  } catch (_) {
    return const <String, BackupOutcome>{};
  }
}

/// On her tablet: makes her two secrets the first time, then backs up her keepsakes and her private areas, each under
/// its own key. Silent: she sees nothing, and a failure is only ever recorded for a grown-up's status screen.
Future<void> runChildBackupsIfDue(LocalServices services, BackupPlaces places) async {
  try {
    final ChildSecrets secrets = await ChildKeyKeeper(services.area('childkeys')).ensure();
    final BackupService svc = BackupService(services: services, deviceLabel: "Her tablet");
    final BackupSettings s = await svc.journal.settings();
    final BackupKeyPair keep = await BackupKeyPair.fromSecret(secrets.keep, BackupPurpose.keep);
    final BackupKeyPair priv = await BackupKeyPair.fromSecret(secrets.private, BackupPurpose.private);
    final Map<String, BackupDestination> d = places.destinations(s);
    await svc.runIfDue(BackupKind.hersKeep, d, keep.publicKey);
    await svc.runIfDue(BackupKind.hersPrivate, d, priv.publicKey);
  } catch (_) {
    // recorded by the service where it matters; never surfaced to her
  }
}

/// Run once at start-up, before anything reads the store. Finishes (by undoing) a restore that was cut short.
Future<RecoverResult> recoverRestoreAtStart(LocalServices services) async {
  try {
    return await RestoreEngine(services: services).recoverInterrupted();
  } catch (_) {
    return RecoverResult.nothingToDo;
  }
}

/// Starts the quiet backup for this device without waiting for it and without ever throwing: on her tablet her keepsakes and
/// private areas, on a grown-up's phone the family backup (only once a recovery sheet has been made and checked).
void startBackupsInBackground(LocalServices services, {required bool tablet}) {
  unawaited(() async {
    try {
      final BackupPlaces places = await DeviceBackupPlaces.forDevice();
      if (tablet) {
        await runChildBackupsIfDue(services, places);
      } else {
        await runFamilyBackupIfDue(services, places);
      }
    } catch (_) {
      // a backup that cannot start leaves the previous one exactly as it was
    }
  }());
}
