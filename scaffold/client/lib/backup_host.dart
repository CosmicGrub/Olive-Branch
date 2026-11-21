// OLIVE BRANCH — wires the backup screens to the real app: the on-device store, this device's own writing key, a staging
// folder, and a folder on the phone a family can copy backups out of. UNVERIFIED on a device; needs the platform
// channels (path_provider), so tests build a BackupHost by hand (backup_screens.dart).
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'api_client.dart' show OliveApi;
import 'backup_engine.dart';
import 'backup_screens.dart';
import 'backup_server.dart';
import 'backup_service.dart';
import 'backup_state.dart' show DirectoryBackupStaging;
import 'device_keys.dart';
import 'local_services.dart';

/// Builds the host for this app run. A grown-up's phone passes [api] when a signed-in session exists, which is what
/// makes "your family's server" a choice; a tablet never does.
Future<BackupHost> backupHostForApp({required BackupRole role, OliveApi? api, String? userId, String? deviceId}) async {
  final LocalServices services = LocalServices.current;
  final DeviceKey writer = await DeviceKey.loadOrCreate(LocalStoreDeviceKeyRepository(services.area('devicekey')));
  final Directory support = await getApplicationSupportDirectory();
  final BackupService svc = BackupService(
    services: services,
    writer: writer,
    role: role,
    staging: DirectoryBackupStaging(Directory('${support.path}${Platform.pathSeparator}olive_backup_staging')),
    serverApi: () => api == null || role != BackupRole.guardian ? null : OliveBackupServerApi(api),
  );
  return BackupHost(
    service: svc,
    defaultFolder: _defaultFolder,
    identity: userId == null || deviceId == null ? null : () async => (userId: userId, deviceId: deviceId),
  );
}

/// `Olive backups` in the phone's own app-files area on shared storage (so a file manager or a USB cable can copy it),
/// falling back to the app's documents folder. Created on first use.
Future<String?> _defaultFolder() async {
  try {
    final Directory? ext = Platform.isAndroid ? await getExternalStorageDirectory() : null;
    final Directory base = ext ?? await getApplicationDocumentsDirectory();
    final Directory d = Directory('${base.path}${Platform.pathSeparator}Olive backups');
    await d.create(recursive: true);
    return d.path;
  } catch (_) {
    return null;
  }
}

/// Run at every app start, before a screen reads the store: undoes a restore that was cut off, or tidies one that had
/// finished. Safe to run any number of times.
Future<void> recoverBackupRestoreOnStart(LocalServices services, {required BackupRole role}) async {
  try {
    final DeviceKey writer = await DeviceKey.loadOrCreate(LocalStoreDeviceKeyRepository(services.area('devicekey')));
    await BackupService(services: services, writer: writer, role: role).recoverOnStart();
  } catch (_) {
    // Never let this stop the app opening its store: the journal stays and the next start tries again.
  }
}

/// Time for a backup? Called when the app comes to the front: makes one quietly when set up, a place is chosen and none
/// ran in the last day. Never throws; a failure is recorded for the status line.
Future<void> backUpIfDue(BackupHost host) async {
  try {
    if (await host.service.due()) await host.service.backUpNow();
  } catch (_) {
    // recorded by the engine; the screen says what to do
  }
}

