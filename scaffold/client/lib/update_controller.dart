// OLIVE BRANCH — the app updater: finds an update, helps a grown-up download it, and hands it to Android to install.
// Verified headless (test/update_controller_test.dart: a fake transport, a fake installer and a fake phone, with every
// hostile case). MASTERFILE 7.24.
//
// WHO SEES IT. Only a grown-up, in the grown-up's app (Settings > App updates, and a gentle line on the home screen).
// This controller is created by the guardian shell and by nothing else; the child's shell and the kiosk never import it
// (test/update_source_test.dart holds that). It never opens a screen by itself, never interrupts, never sends a
// notification, and a failure of any kind only changes what a grown-up sees if they look.
//
// WHAT IT WILL NOT DO. No silent install, ever: the system's own confirmation is the only way a file is installed. No
// download over mobile data, in roaming or with Data Saver on unless a grown-up pressed "Download now". No install of
// anything that is not (1) described by a manifest signed by the owner's offline key, (2) strictly newer than what is
// installed, (3) complete and exactly the signed size and hashes, and (4) signed by the same certificate as the
// installed app. A failure at any step deletes the file and says so honestly.
//
// NEVER A LOCK, NEVER A LOSS. A phone below the manifest's minimum gets a clear, kind "Please update" notice and
// nothing else: no feature is disabled, no screen is blocked, nothing is deleted. Before an install the pending writes
// are flushed and a note is kept (how many sealed areas the phone holds); after it, the app confirms they are all still
// there and shows "what's new" once.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'local_services.dart';
import 'server_transport_policy.dart' show OliveTransportPolicy, kAllowDevCleartext;
import 'update_download.dart';
import 'update_manifest.dart';
import 'update_platform.dart';
import 'update_policy.dart';
import 'update_store.dart';
import 'update_transport.dart';

/// What the build was told. All three are --dart-define values; none is a secret (the public key is public by design).
class UpdateConfig {
  const UpdateConfig({
    this.manifestUrls = const <String>[],
    this.channel = 'stable',
    required this.trust,
    this.allowLoopbackHttp = false,
  });

  /// The primary manifest address first, then mirrors. Empty means "no source built in".
  final List<String> manifestUrls;
  final String channel;
  final UpdateTrust trust;
  final bool allowLoopbackHttp;

  factory UpdateConfig.fromEnvironment() => UpdateConfig(
        manifestUrls: <String>[
          for (final String u in const String.fromEnvironment('OLIVE_UPDATE_MANIFEST_URL').split(','))
            if (u.trim().isNotEmpty) u.trim(),
        ],
        channel: const String.fromEnvironment('OLIVE_UPDATE_CHANNEL', defaultValue: 'stable'),
        trust: UpdateTrust.fromEnvironment(),
        allowLoopbackHttp: kAllowDevCleartext,
      );
}

enum UpdatePhase {
  /// Not built in, nothing configured, or no native side: the feature is simply absent.
  off,
  idle,
  checking,
  upToDate,
  available,
  waitingForWifi,
  downloading,
  ready,
  needsPermission,
  installing,
  failed,
}

/// Throttled phone readings used between chunks.
const int kLowBatteryPercent = 15;
const int kSpaceMarginBytes = 48 * 1024 * 1024;
const Duration kCheckEvery = Duration(hours: 24);
const Duration kRetryAfterFailure = Duration(hours: 6);
const Duration kLaterFor = Duration(days: 3);

/// What is kept in step with an install: pending writes are flushed, and the number of sealed areas is noted.
class UpdateSafety {
  UpdateSafety({this.flushers = const <Future<void> Function()>[], this.areaCounter});
  final List<Future<void> Function()> flushers;
  final Future<int> Function()? areaCounter;

  /// Returns how many sealed areas this phone holds now (the note kept for after the restart), or null if unknown.
  Future<int?> prepare() async {
    for (final Future<void> Function() f in flushers) {
      await f();
    }
    return areaCounter == null ? null : await areaCounter!();
  }

  static UpdateSafety forApp() => UpdateSafety(
        areaCounter: () async => (await LocalServices.current.store.namespaces()).length,
        flushers: <Future<void> Function()>[
          // Every namespace write is already atomic and awaited; asking for the list waits behind any write in flight.
          () async => LocalServices.current.store.namespaces().then((_) {}),
        ],
      );
}

/// A verified file and the signed document that describes it, ready to be handed to another of the family's phones.
class StagedUpdate {
  const StagedUpdate({required this.manifestDocument, required this.apk, required this.manifest});
  final Uint8List manifestDocument;
  final File apk;
  final UpdateManifest manifest;
}

class AppUpdater extends ChangeNotifier {
  AppUpdater({
    required UpdateEnvironmentSource environment,
    required this._config,
    required UpdateStateRepository repository,
    required this._transport,
    this._staging,
    this._direct,
    this._play,
    UpdateSafety? safety,
    DateTime Function()? clock,
    this._sleep,
  })  : _envSource = environment,
        _repo = repository,
        _safety = safety ?? UpdateSafety(),
        _clock = clock ?? DateTime.now;

  /// The real one: the platform channel, the real transport, a folder inside the app's own files.
  static Future<AppUpdater> forApp({UpdateConfig? config}) async {
    final UpdateNativeChannel native = UpdateNativeChannel();
    final Directory support = await getApplicationSupportDirectory();
    final UpdateFlavor f = await native.flavor();
    return AppUpdater(
      environment: native,
      config: config ?? UpdateConfig.fromEnvironment(),
      repository: LocalStoreUpdateStateRepository(),
      transport: HttpUpdateTransport(policy: const OliveTransportPolicy(release: kReleaseMode)),
      staging: f == UpdateFlavor.direct ? UpdateStaging(Directory('${support.path}${Platform.pathSeparator}olive_updates')) : null,
      direct: f == UpdateFlavor.direct ? native : null,
      play: f == UpdateFlavor.play ? native : null,
      safety: UpdateSafety.forApp(),
    );
  }

  final UpdateEnvironmentSource _envSource;
  final UpdateConfig _config;
  final UpdateStateRepository _repo;
  final UpdateTransport _transport;
  final UpdateStaging? _staging;
  final DirectInstaller? _direct;
  final PlayUpdater? _play;
  final UpdateSafety _safety;
  final DateTime Function() _clock;
  final Future<void> Function(Duration)? _sleep;

  // ---- what a screen reads ----------------------------------------------------

  UpdatePhase _phase = UpdatePhase.off;
  UpdatePhase get phase => _phase;
  UpdateState _state = const UpdateState();
  UpdateState get state => _state;
  UpdateEnvironment? _env;
  UpdateEnvironment? get environment => _env;
  UpdateVerdict? _verdict;

  /// The update that was found, if any.
  UpdateManifest? get manifest => _verdict?.manifest;

  /// The file for this phone (null in the Play flavor, which never downloads one).
  ApkEntry? get apk => _verdict?.apk;

  /// This phone is older than the manifest's minimum: a calm notice, nothing locked (see the file header).
  bool get belowMinimum => _verdict?.belowMinimum ?? _playBelowMinimum;
  bool _playBelowMinimum = false;
  PlayUpdateInfo? _playInfo;
  PlayUpdateInfo? get playInfo => _playInfo;
  DownloadProgress? _progress;
  DownloadProgress? get progress => _progress;
  UpdateRefusalCode? _failure;

  /// Why the last attempt did not work (a code; update_screens.dart turns it into words).
  UpdateRefusalCode? get failure => _failure;
  UpdateFlavor _flavor = UpdateFlavor.none;
  UpdateFlavor get flavor => _flavor;
  bool get enabled => _phase != UpdatePhase.off;

  /// What an adult may change.
  String get channel => _state.channel ?? _config.channel;
  List<String> get manifestUrls => _state.manifestUrl != null ? <String>[_state.manifestUrl!] : _config.manifestUrls;

  /// Whether an update is waiting for a grown-up and has not been put off ("Later").
  bool get bannerWanted {
    if (belowMinimum) return true;
    if (_phase == UpdatePhase.available || _phase == UpdatePhase.waitingForWifi || _phase == UpdatePhase.ready) {
      final int? later = _state.laterVersionCode;
      final int? until = _state.laterUntilMs;
      final int code = _verdict?.manifest.versionCode ?? _playInfo?.versionCode ?? 0;
      if (later == code && until != null && _clock().millisecondsSinceEpoch < until) return false;
      return true;
    }
    return false;
  }

  WhatsNew? get whatsNew => _state.whatsNew;

  UpdateCancel? _cancel;
  bool _busy = false;
  StreamSubscription<InstallEvent>? _installSub;
  StreamSubscription<PlayEvent>? _playSub;
  int _lastGuardMs = 0;

  void _set(UpdatePhase p, {UpdateRefusalCode? failure}) {
    _phase = p;
    _failure = failure;
    notifyListeners();
  }

  Future<void> _save(UpdateState s) async {
    _state = s;
    try {
      await _repo.save(s);
    } catch (_) {
      // Kept in memory for this run; the updater must never be why the app misbehaves.
    }
  }

  // ---- start ------------------------------------------------------------------

  /// Reads the saved state and the phone, settles what an earlier run left (an install Android may have finished), and
  /// restores an update that was already found and downloaded, without the network.
  Future<void> start() async {
    _state = await _repo.load();
    try {
      _env = await _envSource.read();
    } catch (_) {
      _set(UpdatePhase.off);
      return;
    }
    _flavor = flavorFromWord(_env!.flavor);
    final bool haveSource = _config.manifestUrls.isNotEmpty || _state.manifestUrl != null;
    if (_flavor == UpdateFlavor.none ||
        (_flavor == UpdateFlavor.direct && (!haveSource || _config.trust.isEmpty || _direct == null || _staging == null)) ||
        (_flavor == UpdateFlavor.play && _play == null)) {
      _set(UpdatePhase.off);
      return;
    }
    _installSub = _direct?.installEvents.listen(_onInstallEvent);
    _playSub = _play?.playEvents.listen(_onPlayEvent);
    await _reconcile();
    await _restoreStaged();
    if (_phase == UpdatePhase.off) _set(UpdatePhase.idle, failure: _failure);
    notifyListeners();
  }

  @override
  void dispose() {
    _installSub?.cancel();
    _playSub?.cancel();
    _cancel?.cancel();
    super.dispose();
  }

  /// The next time the app opens after an install was handed to Android: did it finish?
  Future<void> _reconcile() async {
    final PendingInstall? p = _state.pending;
    if (p == null) return;
    final int now = _env!.installedVersionCode;
    if (now >= p.toVersionCode) {
      String dataNote = '';
      if (p.areaCount != null && _safety.areaCounter != null) {
        final int after = await _safety.areaCounter!();
        if (after < p.areaCount!) {
          dataNote = 'Olive found fewer saved items on this phone than before the update. Nothing was sent anywhere. '
              'You can see what is kept under Settings, Data on this phone.';
        }
      }
      await _save(_state.copyWith(
        pending: null,
        queuedVersionCode: null,
        whatsNew: WhatsNew(versionName: p.versionName, headline: p.headline, notes: p.notes, dataNote: dataNote),
        lastUpdatedName: p.versionName,
        lastUpdatedMs: _clock().millisecondsSinceEpoch,
        laterVersionCode: null,
        laterUntilMs: null,
      ));
      await _staging?.sweep();
    } else {
      // Android did not finish it (the grown-up said no, or it was interrupted). Nothing was changed; it is offered again.
      await _save(_state.copyWith(pending: null));
      _failure = UpdateRefusalCode.installNotFinished;
    }
  }

  File get _manifestCopy => File('${_staging!.dir.path}${Platform.pathSeparator}manifest.json');

  Future<void> _restoreStaged() async {
    if (_staging == null || _flavor != UpdateFlavor.direct) return;
    try {
      if (!await _manifestCopy.exists()) return;
      final Uint8List doc = await _manifestCopy.readAsBytes();
      final VerifiedManifest v = await verifyManifestDocument(doc, _config.trust, allowLoopbackHttp: _config.allowLoopbackHttp);
      final UpdateVerdict d = decideUpdate(v.manifest, _context());
      if (d.status != UpdateStatus.updateAvailable) {
        await _staging.sweep();
        return;
      }
      _verdict = d;
      // Cheap look only (the start of the app never waits on hashing a big file): the finished name only ever exists
      // after a full check, and install() checks the whole file again before anything is handed to Android.
      final ApkEntry file = d.apk!;
      final File done = _staging.finalFor(file);
      final bool have = await done.exists() && await done.length() == file.size;
      _set(have ? UpdatePhase.ready : UpdatePhase.available, failure: _failure);
    } on UpdateRefusal {
      await _staging.sweep();
    } catch (_) {
      // Unreadable leftovers are never trusted and never block anything.
    }
  }

  UpdateContext _context() => UpdateContext(
        channel: channel,
        installedVersionCode: _env!.installedVersionCode,
        now: _clock(),
        highestSeenSequence: _state.highestSeenSequence,
        deviceAbis: _env!.abis,
        requireApk: _flavor == UpdateFlavor.direct,
      );

  // ---- checking ---------------------------------------------------------------

  /// The polite check: when the app opens, at most once a day (six hours after one that failed), never offline, never on
  /// mobile data or roaming or with Data Saver on, and only if an adult has not turned automatic checks off.
  Future<void> maybeCheckAtOpen() async {
    if (!enabled || _busy || _phase == UpdatePhase.installing) return;
    final UpdateState s = _state;
    if (!s.autoCheck) return;
    final int now = _clock().millisecondsSinceEpoch;
    final int? last = s.lastAttemptMs;
    final Duration gap = s.lastResult == 'ok' ? kCheckEvery : kRetryAfterFailure;
    if (last != null && now >= last && now - last < gap.inMilliseconds) {
      await pollQueuedDownload();
      return;
    }
    if (!await _refreshEnv()) return;
    final UpdateEnvironment e = _env!;
    if (e.isOffline || e.roaming || e.dataSaver) return;
    if (s.wifiOnly && !e.onUnmeteredWifi) return;
    await checkNow(manual: false);
    await pollQueuedDownload();
  }

  Future<bool> _refreshEnv() async {
    try {
      _env = await _envSource.read();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A grown-up asked ("Check now"): allowed on any connection (it is a few kilobytes), refused only when offline.
  Future<void> checkNow({bool manual = true}) async {
    if (!enabled || _busy || _phase == UpdatePhase.installing) return;
    _busy = true;
    final UpdatePhase before = _phase;
    try {
      if (!await _refreshEnv()) {
        return;
      }
      if (_env!.isOffline) {
        await _save(_state.copyWith(lastAttemptMs: _clock().millisecondsSinceEpoch, lastResult: 'offline'));
        _set(before == UpdatePhase.checking ? UpdatePhase.idle : before, failure: manual ? UpdateRefusalCode.offline : null);
        return;
      }
      _set(UpdatePhase.checking);
      if (_flavor == UpdateFlavor.play) {
        await _checkPlay();
      } else {
        await _checkManifests(before);
      }
    } finally {
      _busy = false;
    }
  }

  /// Asks EVERY source and believes the newest validly signed answer. A mirror (or anyone on the path to it) can only
  /// ever hold the phone back by serving an old, validly signed manifest; asking the others defeats that, and a
  /// manifest older than one already accepted is refused outright.
  Future<List<UpdateVerdict>> _fetchVerdicts(List<UpdateRefusal> refusals) async {
    final List<UpdateVerdict> verdicts = <UpdateVerdict>[];
    final Map<UpdateVerdict, Uint8List> docs = <UpdateVerdict, Uint8List>{};
    for (final String u in manifestUrls) {
      try {
        final Uri uri = Uri.parse(u);
        final UpdateResponse r = await _transport.get(uri, maxBytes: kMaxManifestBytes);
        final VerifiedManifest v =
            await verifyManifestDocument(r.body, _config.trust, allowLoopbackHttp: _config.allowLoopbackHttp);
        final UpdateVerdict d = decideUpdate(v.manifest, _context());
        verdicts.add(d);
        docs[d] = v.document;
      } on UpdateRefusal catch (e) {
        refusals.add(e);
      } on FormatException {
        refusals.add(const UpdateRefusal(UpdateRefusalCode.badUrl));
      }
    }
    _lastDocs = docs;
    return verdicts;
  }

  Map<UpdateVerdict, Uint8List> _lastDocs = <UpdateVerdict, Uint8List>{};

  UpdateVerdict _best(List<UpdateVerdict> vs) {
    vs.sort((UpdateVerdict a, UpdateVerdict b) {
      final int c = b.manifest.sequence.compareTo(a.manifest.sequence);
      return c != 0 ? c : b.manifest.versionCode.compareTo(a.manifest.versionCode);
    });
    return vs.first;
  }

  Future<void> _checkManifests(UpdatePhase before) async {
    final List<UpdateRefusal> refusals = <UpdateRefusal>[];
    final List<UpdateVerdict> vs = await _fetchVerdicts(refusals);
    final int now = _clock().millisecondsSinceEpoch;
    if (vs.isEmpty) {
      // Offline outranks everything (nothing was said); otherwise the first thing that was wrong. A check that fails
      // never takes away an update that was already found: the phone goes back to what it was showing.
      final UpdateRefusal? why = refusals.where((UpdateRefusal r) => r.code != UpdateRefusalCode.offline).firstOrNull ??
          refusals.firstOrNull;
      final bool ignorable = why != null &&
          (why.code == UpdateRefusalCode.rollback || why.code == UpdateRefusalCode.replayed);
      await _save(_state.copyWith(
          lastAttemptMs: now,
          lastResult: ignorable ? 'ok' : (why?.code == UpdateRefusalCode.offline ? 'offline' : 'refused:${why?.code.name ?? 'none'}'),
          lastCheckMs: ignorable ? now : _state.lastCheckMs));
      final UpdatePhase back = (before == UpdatePhase.checking || before == UpdatePhase.off || before == UpdatePhase.failed)
          ? (ignorable ? UpdatePhase.upToDate : UpdatePhase.idle)
          : before;
      _set(back, failure: ignorable ? null : why?.code);
      return;
    }
    final UpdateVerdict best = _best(vs);
    final UpdateManifest m = best.manifest;
    await _save(_state.copyWith(
      lastAttemptMs: now,
      lastCheckMs: now,
      lastResult: 'ok',
      lastSeenVersionName: m.versionName,
      highestSeenSequence: m.sequence,
    ));
    _verdict = best;
    if (best.status == UpdateStatus.upToDate) {
      await _staging?.sweep();
      _set(UpdatePhase.upToDate);
      return;
    }
    // Keep the signed document so the update survives a restart without the network.
    try {
      await _staging!.ensure();
      await _manifestCopy.writeAsBytes(_lastDocs[best]!, flush: true);
    } catch (_) {}
    final File? f = best.apk == null ? null : await _staging!.verifiedFile(best.apk!);
    _set(f != null ? UpdatePhase.ready : UpdatePhase.available);
  }

  Future<void> _checkPlay() async {
    final int now = _clock().millisecondsSinceEpoch;
    try {
      final PlayUpdateInfo info = await _play!.check();
      _playInfo = info;
      await _save(_state.copyWith(lastAttemptMs: now, lastCheckMs: now, lastResult: 'ok'));
      if (!info.supported) {
        _set(UpdatePhase.off);
        return;
      }
      // The manifest, when one is configured, only adds the plain-words notes and the minimum: Play does the update.
      if (manifestUrls.isNotEmpty && !_config.trust.isEmpty) {
        final List<UpdateRefusal> refusals = <UpdateRefusal>[];
        final List<UpdateVerdict> vs = await _fetchVerdicts(refusals);
        if (vs.isNotEmpty) {
          _verdict = _best(vs);
          _playBelowMinimum = _verdict!.belowMinimum;
        }
      }
      _set(info.available ? UpdatePhase.available : UpdatePhase.upToDate);
    } catch (_) {
      await _save(_state.copyWith(lastAttemptMs: now, lastResult: 'offline'));
      _set(UpdatePhase.idle, failure: UpdateRefusalCode.offline);
    }
  }

  // ---- downloading ------------------------------------------------------------

  /// "Download on Wi-Fi": remembered, and started now if the phone is on Wi-Fi already.
  Future<void> downloadOnWifi() async {
    final UpdateManifest? m = manifest;
    if (m == null || _flavor != UpdateFlavor.direct) return;
    await _save(_state.copyWith(queuedVersionCode: m.versionCode));
    await pollQueuedDownload();
  }

  /// Starts a queued download when the phone is on Wi-Fi (called when the app opens, resumes, or by a timer while the
  /// updates screen is open).
  Future<void> pollQueuedDownload() async {
    final UpdateManifest? m = manifest;
    if (m == null || _busy || _flavor != UpdateFlavor.direct) return;
    if (_state.queuedVersionCode != m.versionCode) return;
    if (_phase != UpdatePhase.available && _phase != UpdatePhase.waitingForWifi) return;
    if (!await _refreshEnv()) return;
    if (_env!.onUnmeteredWifi && !_env!.dataSaver) {
      await _download(enforceWifi: true);
    } else {
      _set(UpdatePhase.waitingForWifi);
    }
  }

  /// "Download now": an adult pressed it, so mobile data is allowed (the screen says how big it is first).
  Future<void> downloadNow() async {
    if (manifest == null || _flavor != UpdateFlavor.direct || _busy) return;
    await _download(enforceWifi: false);
  }

  /// Stops a running download. What was downloaded is kept and checked again when it continues.
  void stopDownload() => _cancel?.cancel();

  Future<void> _download({required bool enforceWifi}) async {
    final ApkEntry file = apk!;
    final UpdateStaging staging = _staging!;
    _busy = true;
    final UpdateCancel cancel = _cancel = UpdateCancel();
    try {
      if (!await _refreshEnv()) {
        _set(UpdatePhase.failed, failure: UpdateRefusalCode.offline);
        return;
      }
      final UpdateEnvironment e = _env!;
      if (e.isOffline) {
        _set(enforceWifi ? UpdatePhase.waitingForWifi : UpdatePhase.failed,
            failure: enforceWifi ? null : UpdateRefusalCode.offline);
        return;
      }
      _guardCheck(e, enforceWifi: enforceWifi, file: file, haveBytes: 0);
      _progress = DownloadProgress(0, file.size);
      _set(UpdatePhase.downloading);
      final UpdateDownloader dl = UpdateDownloader(
        transport: _transport,
        staging: staging,
        sleep: _sleep,
      );
      await dl.download(
        file,
        cancel: cancel,
        onProgress: (DownloadProgress p) {
          _progress = p;
          notifyListeners();
        },
        guard: () async {
          final int t = _clock().millisecondsSinceEpoch;
          if (t - _lastGuardMs < 3000 && t >= _lastGuardMs) return;
          _lastGuardMs = t;
          if (!await _refreshEnv()) return;
          _guardCheck(_env!, enforceWifi: enforceWifi, file: file, haveBytes: _progress?.doneBytes ?? 0);
        },
      );
      _progress = DownloadProgress(file.size, file.size);
      await _save(_state.copyWith(queuedVersionCode: null));
      _set(UpdatePhase.ready);
    } on UpdateRefusal catch (r) {
      await _onDownloadRefusal(r, enforceWifi);
    } finally {
      _busy = false;
    }
  }

  void _guardCheck(UpdateEnvironment e, {required bool enforceWifi, required ApkEntry file, required int haveBytes}) {
    if (e.batteryPercent != null && e.batteryPercent! < kLowBatteryPercent && !e.charging) {
      throw const UpdateRefusal(UpdateRefusalCode.lowBattery);
    }
    if (enforceWifi && (!e.onUnmeteredWifi || e.dataSaver)) throw const UpdateRefusal(UpdateRefusalCode.needsWifi);
    if (e.freeBytes != null) {
      // The file itself (what is not yet on disk) plus Android's own copy while it installs, plus a margin.
      final int need = (file.size - haveBytes) + file.size + kSpaceMarginBytes;
      if (e.freeBytes! < need) throw const UpdateRefusal(UpdateRefusalCode.noSpace);
    }
  }

  Future<void> _onDownloadRefusal(UpdateRefusal r, bool enforceWifi) async {
    switch (r.code) {
      case UpdateRefusalCode.cancelled:
        _set(UpdatePhase.available);
      case UpdateRefusalCode.needsWifi:
        _set(UpdatePhase.waitingForWifi);
      case UpdateRefusalCode.offline when enforceWifi:
        _set(UpdatePhase.waitingForWifi);
      default:
        // A file that failed a check is never kept; one that merely stopped is (it is checked again before use).
        final bool bad = r.code == UpdateRefusalCode.hashMismatch ||
            r.code == UpdateRefusalCode.sizeMismatch ||
            r.code == UpdateRefusalCode.tooMuchData;
        if (bad && apk != null) await _staging!.discard(apk!);
        _set(UpdatePhase.failed, failure: r.code);
    }
  }

  /// "Later": the gentle line on the home screen stays away for three days (or until a newer update).
  Future<void> later() async {
    final int? code = manifest?.versionCode ?? _playInfo?.versionCode;
    if (code == null) return;
    await _save(_state.copyWith(
        laterVersionCode: code, laterUntilMs: _clock().add(kLaterFor).millisecondsSinceEpoch, queuedVersionCode: null));
    if (_phase == UpdatePhase.waitingForWifi) _set(UpdatePhase.available);
    notifyListeners();
  }

  // ---- installing -------------------------------------------------------------

  /// Checks the finished file a last time and hands it to Android, which asks the person to confirm. Returns normally
  /// whatever happens; the result is [phase] and [failure].
  Future<void> install() async {
    final UpdateManifest? m = manifest;
    final ApkEntry? file = apk;
    final DirectInstaller? inst = _direct;
    if (m == null || file == null || inst == null || _staging == null || _busy) return;
    _busy = true;
    try {
      if (!await _refreshEnv()) return;
      final UpdateEnvironment e = _env!;
      if (e.batteryPercent != null && e.batteryPercent! < kLowBatteryPercent && !e.charging) {
        _set(UpdatePhase.failed, failure: UpdateRefusalCode.lowBattery);
        return;
      }
      // 1. The file on disk is still exactly what was signed (a second look: it could have been touched since).
      final File? f = await _staging.verifiedFile(file);
      if (f == null) {
        _set(UpdatePhase.available, failure: UpdateRefusalCode.hashMismatch);
        return;
      }
      // 2. Android's own reading of the file: the right app, the version the manifest promised, strictly newer, and
      //    signed by the same certificate as the installed app (and the pinned one, when the owner pinned one).
      final ApkInspection ins;
      try {
        ins = await inst.inspect(f.path);
      } catch (_) {
        await _staging.discard(file);
        _set(UpdatePhase.failed, failure: UpdateRefusalCode.apkMismatch);
        return;
      }
      if (ins.packageName != kUpdateAppId ||
          ins.versionCode != m.versionCode ||
          !strictlyNewer(ins.versionCode, e.installedVersionCode)) {
        await _staging.discard(file);
        _set(UpdatePhase.failed, failure: UpdateRefusalCode.apkMismatch);
        return;
      }
      if (!ins.signedLikeInstalled(pinned: file.signerSha256)) {
        await _staging.discard(file);
        _set(UpdatePhase.failed, failure: UpdateRefusalCode.certMismatch);
        return;
      }
      // 3. May Olive ask Android to install? If not, say so and show where to allow it. Nothing is installed.
      if (!await inst.canRequestInstalls()) {
        _set(UpdatePhase.needsPermission, failure: UpdateRefusalCode.needsPermission);
        return;
      }
      // 4. Pre-update safety: pending writes flushed, a note kept for the other side of the restart.
      int? areas;
      try {
        areas = await _safety.prepare();
      } catch (_) {
        areas = null;
      }
      await _save(_state.copyWith(
        pending: PendingInstall(
          fromVersionCode: e.installedVersionCode,
          toVersionCode: m.versionCode,
          versionName: m.versionName,
          atMs: _clock().millisecondsSinceEpoch,
          areaCount: areas,
          headline: m.headline,
          notes: m.notes,
        ),
      ));
      _set(UpdatePhase.installing);
      final InstallStart start = await inst.install(path: f.path, sha256: file.sha256, size: file.size, versionCode: m.versionCode);
      switch (start) {
        case InstallStart.waitingForYou:
          break; // the system dialog is up; its answer arrives as an event (or the app restarts as the new version)
        case InstallStart.needsPermission:
          await _save(_state.copyWith(pending: null));
          _set(UpdatePhase.needsPermission, failure: UpdateRefusalCode.needsPermission);
        case InstallStart.kioskLocked:
          await _save(_state.copyWith(pending: null));
          _set(UpdatePhase.ready, failure: UpdateRefusalCode.kioskLocked);
        case InstallStart.refused:
          await _save(_state.copyWith(pending: null));
          await _staging.discard(file);
          _set(UpdatePhase.failed, failure: UpdateRefusalCode.apkMismatch);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> openInstallSettings() async {
    try {
      await _direct?.openInstallSettings();
    } catch (_) {}
  }

  /// Back from the settings page: try again when the permission is there.
  Future<void> recheckPermission() async {
    if (_phase != UpdatePhase.needsPermission) return;
    if (await _direct?.canRequestInstalls() ?? false) _set(UpdatePhase.ready);
  }

  void _onInstallEvent(InstallEvent ev) {
    switch (ev.outcome) {
      case InstallOutcome.success:
        // Normally the app is replaced before this is seen; if it is, the next start reconciles.
        _set(UpdatePhase.installing);
      case InstallOutcome.declined:
        unawaited(_save(_state.copyWith(pending: null)));
        _set(UpdatePhase.ready, failure: UpdateRefusalCode.installNotFinished);
      default:
        unawaited(_save(_state.copyWith(pending: null)));
        _set(UpdatePhase.failed, failure: UpdateRefusalCode.installRefused);
    }
  }

  // ---- Google Play ------------------------------------------------------------

  /// The Play flavor's "Update": flexible (downloads quietly, then a restart) or immediate (Play's own full-screen
  /// flow) as Play and the update's priority allow.
  Future<void> startPlayUpdate() async {
    final PlayUpdateInfo? i = _playInfo;
    if (_play == null || i == null || !i.available || _busy) return;
    _busy = true;
    try {
      final bool ok = await _play.start(immediate: i.preferImmediate);
      if (!ok) {
        _set(UpdatePhase.available);
        return;
      }
      await _save(_state.copyWith(
          pending: PendingInstall(
        fromVersionCode: _env?.installedVersionCode ?? 0,
        toVersionCode: i.versionCode ?? ((_env?.installedVersionCode ?? 0) + 1),
        versionName: manifest?.versionName ?? '',
        atMs: _clock().millisecondsSinceEpoch,
        areaCount: await _safety.prepare(),
        headline: manifest?.headline ?? '',
        notes: manifest?.notes ?? const <String>[],
      )));
      _set(UpdatePhase.downloading);
    } finally {
      _busy = false;
    }
  }

  Future<void> finishPlayUpdate() async {
    await _play?.complete();
  }

  void _onPlayEvent(PlayEvent ev) {
    switch (ev.status) {
      case PlayStatus.downloading:
        _progress = DownloadProgress(ev.doneBytes, ev.totalBytes);
        _set(UpdatePhase.downloading);
      case PlayStatus.downloaded:
        _set(UpdatePhase.ready);
      case PlayStatus.installing:
      case PlayStatus.installed:
        _set(UpdatePhase.installing);
      case PlayStatus.pending:
        break;
      case PlayStatus.cancelled:
        unawaited(_save(_state.copyWith(pending: null)));
        _set(UpdatePhase.available);
      case PlayStatus.failed:
        unawaited(_save(_state.copyWith(pending: null)));
        _set(UpdatePhase.failed, failure: UpdateRefusalCode.installRefused);
    }
  }

  // ---- choices and notes ------------------------------------------------------

  Future<void> setWifiOnly(bool v) async {
    await _save(_state.copyWith(wifiOnly: v));
    notifyListeners();
  }

  Future<void> setAutoCheck(bool v) async {
    await _save(_state.copyWith(autoCheck: v));
    notifyListeners();
  }

  /// A source an adult typed. null clears it (the one built into the app is used again). Returns why it was refused, or
  /// null when it was taken: https only (the developer loopback define is the single exception), no credentials.
  Future<String?> setManifestUrl(String? raw) async {
    final String? v = raw?.trim();
    if (v == null || v.isEmpty) {
      await _save(_state.copyWith(manifestUrl: null));
      notifyListeners();
      return null;
    }
    final String? why = updateUrlProblem(v, allowLoopbackHttp: _config.allowLoopbackHttp);
    if (why != null) return why;
    await _save(_state.copyWith(manifestUrl: v));
    notifyListeners();
    return null;
  }

  Future<void> setChannel(String? c) async {
    final String? v = (c == null || c.isEmpty || c == _config.channel) ? null : c;
    await _save(_state.copyWith(channel: v));
    notifyListeners();
  }

  Future<void> dismissWhatsNew() async {
    await _save(_state.copyWith(whatsNew: null));
    notifyListeners();
  }

  // ---- over the family's own link ---------------------------------------------

  /// The verified file and its signed document, for handing to another family phone (the phone that has it is the one
  /// that serves the tablet; the tablet checks everything again for itself: [acceptHandedOver]).
  Future<StagedUpdate?> stagedForHandover() async {
    final UpdateManifest? m = manifest;
    final ApkEntry? file = apk;
    if (m == null || file == null || _staging == null || _flavor != UpdateFlavor.direct) return null;
    final File? f = await _staging.verifiedFile(file);
    if (f == null || !await _manifestCopy.exists()) return null;
    return StagedUpdate(manifestDocument: await _manifestCopy.readAsBytes(), apk: f, manifest: m);
  }

  /// Takes an update handed over by another family phone: the signed manifest and the file's bytes. Everything is checked
  /// here exactly as if the phone had fetched it itself (signature under the built-in key, channel, freshness, strictly
  /// newer than what is installed, size, every chunk and the whole-file hash). Returns the refusal, or null when the
  /// file is now ready to install.
  Future<UpdateRefusal?> acceptHandedOver(Uint8List manifestDocument, Stream<List<int>> apkBytes) async {
    if (_staging == null || _flavor != UpdateFlavor.direct || _busy || _env == null) {
      return const UpdateRefusal(UpdateRefusalCode.installRefused, 'updates are not available here');
    }
    _busy = true;
    try {
      await _refreshEnv();
      final VerifiedManifest v =
          await verifyManifestDocument(manifestDocument, _config.trust, allowLoopbackHttp: _config.allowLoopbackHttp);
      final UpdateVerdict d = decideUpdate(v.manifest, _context());
      if (d.status != UpdateStatus.updateAvailable) return const UpdateRefusal(UpdateRefusalCode.rollback, 'not newer');
      final UpdateDownloader dl = UpdateDownloader(transport: _transport, staging: _staging, sleep: _sleep);
      await dl.stageFromStream(d.apk!, apkBytes);
      await _manifestCopy.writeAsBytes(v.document, flush: true);
      await _save(_state.copyWith(
        highestSeenSequence: d.manifest.sequence,
        lastSeenVersionName: d.manifest.versionName,
      ));
      _verdict = d;
      _set(UpdatePhase.ready);
      return null;
    } on UpdateRefusal catch (r) {
      return r;
    } finally {
      _busy = false;
    }
  }

  /// For tests: the message the screen would show for [failure] is in update_screens.dart; this is only the cached copy
  /// of the signed document last fetched, as text.
  @visibleForTesting
  String debugState() => jsonEncode(_state.toJson());
}
