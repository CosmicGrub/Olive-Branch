// OLIVE BRANCH — the seam between "an update the app trusts" and the family mesh that hands it to the child's tablet.
// Verified headless (test/tablet_update_*_test.dart). MASTERFILE section 7.25 (A grown-up's phone updates the tablet).
//
// WHY THIS FILE EXISTS. The in-app updater (the client-updater lane: signed manifest, polite checks, resumable
// download, PackageInstaller) decides what is a genuine update. The tablet path must repeat every one of those checks
// ON THE TABLET and may never trust the phone, so it needs the engine's answers, but it must not copy the engine's
// code (two copies of a signature check drift apart). This file is the whole of what the tablet path asks of the
// engine, written as an interface. THAT ENGINE HAD NOT LANDED WHEN THIS WAS WRITTEN, so the interface is defined here
// and the tablet path is built and tested against it with a test double that does the real Ed25519, hash and rollback
// work. Wiring it to the real engine is one small adapter class (docs/planning/ANDROID-ROADMAP.md, tablet update row).
// Until that adapter is installed ([TabletUpdateService.current] stays null) the feature is simply absent: no row, no
// card, no listener, no socket.
//
// WHAT THE TABLET PATH ADDS ON TOP OF THE ENGINE, and tests on its own: the wire, the resumable chunked transfer, the
// per-chunk and whole-file hashes, the size caps, the re-check of the signer and the version against what is
// installed, the adult-only rule, and the kiosk-safe handover to the system installer.
import 'dart:io';
import 'dart:typed_data';

/// Why an update, or one step of getting it, was refused. The words for a grown-up are in [tabletUpdateAdultWords].
/// Nothing here is ever shown to a child: the child's tablet has no screen that can reach these (P1 to P11).
enum TabletUpdateCode {
  /// Signature, key, shape or document was not what the owner signed.
  notGenuine,
  wrongApp,
  wrongChannel,
  expired,

  /// An older signed manifest than one already seen.
  replayed,

  /// The offered version is lower than what is installed (a rollback).
  older,

  /// The offered version is the one already installed.
  upToDate,
  notForThisTablet,
  tooBig,
  noSpace,
  lowBattery,

  /// A chunk or the whole file did not match its hash.
  hashMismatch,

  /// The file was shorter or longer than the manifest says.
  truncated,

  /// The APK is signed by a different certificate than the installed app (or than the manifest pins).
  wrongSigner,
  wrongPackage,

  /// The phone went away or stopped answering. Nothing is lost; the transfer can be resumed.
  lostTouch,
  busy,

  /// No grown-up was proved at the moment of the step.
  notAllowed,

  /// There is no update machinery in this build.
  noEngine,
  installDeclined,
  installFailed,

  /// Android needs "Install unknown apps" allowed for this app first.
  needsPermission,

  /// The file on the tablet is no longer the file that was checked.
  changedOnDisk,
  cancelled,
}

/// A refusal. [detail] is for logs and tests; it never carries a path, a URL query or a key.
class TabletUpdateRefused implements Exception {
  const TabletUpdateRefused(this.code, [this.detail = '']);
  final TabletUpdateCode code;
  final String detail;
  @override
  String toString() => 'TabletUpdateRefused(${code.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// The facts about the one file a manifest offers this device, taken from a manifest whose signature already checked
/// out. All of it is data the owner signed, so a transfer is held to it exactly.
class ApkFacts {
  const ApkFacts({
    required this.abi,
    required this.size,
    required this.sha256,
    required this.chunkSize,
    required this.chunkSha256,
    required this.signerSha256,
  });

  final String abi;
  final int size;

  /// Lower-case hex SHA-256 of the whole file.
  final String sha256;
  final int chunkSize;

  /// Lower-case hex SHA-256 of each chunk in order; the last chunk is the remainder.
  final List<String> chunkSha256;

  /// Lower-case hex SHA-256 of the certificate the APK must be signed with.
  final String signerSha256;
}

/// A manifest the engine verified (signature, channel, validity, not older than one already seen) and chose a file
/// from for THIS device. The signed document is kept as it arrived, byte for byte, because that is what is handed on.
class VerifiedUpdate {
  const VerifiedUpdate({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSupportedVersionCode,
    required this.sequence,
    required this.headline,
    required this.notes,
    required this.apk,
    required this.document,
  });

  final String packageName;
  final String versionName;
  final int versionCode;
  final int minSupportedVersionCode;
  final int sequence;
  final String headline;

  /// Plain words for a grown-up, one line each.
  final List<String> notes;
  final ApkFacts apk;
  final Uint8List document;
}

/// What an APK file says about itself, read from the file by the platform (not from the manifest).
class ApkInspection {
  const ApkInspection({required this.packageName, required this.versionCode, required this.signerSha256});
  final String packageName;
  final int versionCode;

  /// Lower-case hex SHA-256 of the signing certificate.
  final String signerSha256;
}

/// What is installed right now.
class InstalledFacts {
  const InstalledFacts({required this.packageName, required this.versionCode, required this.signerSha256});
  final String packageName;
  final int versionCode;
  final String signerSha256;
}

/// A verified update together with the verified file the device holds. The phone offers one of these.
class HeldUpdate {
  const HeldUpdate({required this.update, required this.apk});
  final VerifiedUpdate update;
  final File apk;
}

/// Storage and battery as the engine measures them.
class DeviceGuards {
  const DeviceGuards({required this.freeBytes, required this.batteryPercent, required this.charging});
  final int freeBytes;

  /// 0 to 100, or -1 when unknown.
  final int batteryPercent;
  final bool charging;
}

enum InstallOutcome {
  /// The system confirmation was shown. On success the app is replaced and this process ends, so the future may never
  /// return; on a cancel it returns [declined].
  handedToSystem,
  declined,
  failed,
  needsPermission,
}

/// An update this device found on its own (it is online and the engine's own check saw it).
class OwnUpdateOffer {
  const OwnUpdateOffer({required this.update});
  final VerifiedUpdate update;
}

/// Everything the tablet path asks of the update engine. A test double implements it with real cryptography; the
/// shipped adapter delegates to the client-updater's verification, installer and downloader.
abstract class UpdateEnginePort {
  /// False when this build has no update machinery or no key (the feature is then absent, not broken).
  bool get available;

  /// The shipped application id, signature of record, and version code of the running app.
  Future<InstalledFacts> installed();

  /// Verifies [document] exactly as the engine verifies a manifest it downloaded itself: size cap, signature against
  /// a built-in key, channel, validity window, not older than the highest sequence seen, the right application id,
  /// and a file for this device's ABI. Throws [TabletUpdateRefused] and returns nothing that failed.
  ///
  /// [forInstall] is true when it is repeated at the moment of installing.
  Future<VerifiedUpdate> verify(Uint8List document, {required bool forInstall});

  /// Reads the APK file's own package name, version code and signing certificate. Throws when it cannot (fail closed).
  Future<ApkInspection> inspect(File apk);

  /// A directory inside the app's own private storage for partial and staged files.
  Future<Directory> stagingDirectory();

  Future<DeviceGuards> guards();

  /// Hands [apk] to Android's installer with the system confirmation. Never silent.
  Future<InstallOutcome> install(File apk, VerifiedUpdate update);

  /// The verified update this device holds and could hand on (null when it holds none).
  Future<HeldUpdate?> held();

  /// An update this device found itself and could fetch directly now (null when offline, off, or nothing newer).
  Future<OwnUpdateOffer?> ownOffer();

  /// Downloads [offer] with the engine's own resumable downloader and returns the verified file.
  Future<HeldUpdate> fetchOwn(OwnUpdateOffer offer, {void Function(int done, int total)? onProgress});
}

/// Plain words for a grown-up for each refusal. Calm, no blame, no jargon, says what is safe and what to do next.
String tabletUpdateAdultWords(TabletUpdateCode code) => switch (code) {
      TabletUpdateCode.notGenuine =>
        "This update did not check out as a genuine Olive Branch update, so nothing was kept. Nothing on the tablet has changed.",
      TabletUpdateCode.wrongApp => 'That file is for a different app, so nothing was kept.',
      TabletUpdateCode.wrongChannel => "That update is from a different release line than this tablet follows, so nothing was kept.",
      TabletUpdateCode.expired => 'That update has gone out of date. Ask the phone for the current one.',
      TabletUpdateCode.replayed => 'That is an older copy of an update notice, so it was ignored.',
      TabletUpdateCode.older => 'That version is older than the one on the tablet, so it was not kept. Nothing has changed.',
      TabletUpdateCode.upToDate => 'The tablet already has this version.',
      TabletUpdateCode.notForThisTablet => "That update is not built for this tablet's kind of processor.",
      TabletUpdateCode.tooBig => 'That file is bigger than an update should ever be, so it was stopped.',
      TabletUpdateCode.noSpace => 'The tablet does not have enough free space for this update. Free some space and try again.',
      TabletUpdateCode.lowBattery => 'The tablet battery is low. Plug it in, then try again.',
      TabletUpdateCode.hashMismatch => 'Part of the file arrived damaged, so it was thrown away. Nothing was installed. Try again.',
      TabletUpdateCode.truncated => 'The file was not the size it should be, so it was thrown away. Nothing was installed.',
      TabletUpdateCode.wrongSigner =>
        'That file was not signed by the same maker as the app on this tablet, so it was not kept. Nothing has changed.',
      TabletUpdateCode.wrongPackage => 'That file is not Olive Branch, so it was not kept.',
      TabletUpdateCode.lostTouch => 'Lost touch with the phone. Nothing is lost: stay close and it carries on where it stopped.',
      TabletUpdateCode.busy => 'An update is already being handled. Wait for it to finish.',
      TabletUpdateCode.notAllowed => 'A grown-up has to do this. Open Guardian mode and try again.',
      TabletUpdateCode.noEngine => 'Updates are not set up on this build.',
      TabletUpdateCode.installDeclined => 'The update was not installed. Nothing has changed, and it is still ready when you want it.',
      TabletUpdateCode.installFailed => 'Android could not install the update. Nothing has changed, and it is still ready to try again.',
      TabletUpdateCode.needsPermission =>
        'Android needs you to allow Olive Branch to install updates. Choose Allow on the next screen, then come back and tap Install again.',
      TabletUpdateCode.changedOnDisk => 'The saved update changed after it was checked, so it was thrown away. Ask the phone again.',
      TabletUpdateCode.cancelled => 'Stopped. Nothing was installed.',
    };
