// OLIVE BRANCH — the app-wide owner of the tablet update path: what is staged, the link to the phone, the install
// handover that does not break the kiosk, and the result a grown-up is told. Verified headless
// (test/tablet_update_service_test.dart, tablet_update_hostile_test.dart, tablet_update_wiring_test.dart).
// MASTERFILE section 7.25.
//
// WHERE IT LIVES. One instance per app run, in [TabletUpdateService.current], installed by the boot of a build that has
// the update engine (see tablet_update_port.dart). With none installed (today's shipped state: the engine had not
// landed) every screen of this feature draws nothing and no listener, socket or advertisement exists. It outlives any
// screen on purpose: when a grown-up installs an update the kiosk's own rules send the app back to the PIN gate the
// moment the installer takes the screen, and the result must still be there when they are proved again.
//
// WHO MAY DO WHAT. Every step that has an effect takes a `adultPresent` closure that the CALLER supplies from the
// proof it holds (the Guardian-mode escalation on the tablet; the grown-up's own phone), and it is read again AFTER the
// slow checks, so a grown-up who walked away while a 100 MB file was being re-hashed does not leave an install armed.
// A child has no way to reach any of this: the only screens are inside Guardian mode and the grown-up's Settings.
//
// THE KIOSK RULE. Screen pinning blocks Android's installer, so an install on a locked tablet releases the pin FIRST,
// deliberately and only after every check passed, and puts it back when the app comes forward again unchanged
// (KioskBridge.kt). The tablet is never left unpinned by this path except for the moments the installer is on screen
// with a grown-up in front of it. If the install replaces the app, the new version pins itself at start as it always
// does; the grown-up taps "Open" on Android's own "App installed" screen, and Android may ask once more whether to pin.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'kiosk_channel.dart';
import 'local_pairing.dart';
import 'play_transport.dart';
import 'tablet_update_checks.dart';
import 'tablet_update_port.dart';
import 'tablet_update_receiver.dart';
import 'tablet_update_sender.dart';
import 'tablet_update_store.dart';

/// The lock handover an install needs. The real one is the kiosk channel; a test supplies a recording fake.
abstract class InstallKioskHandoff {
  /// Releases the lock and returns the mode it was in ('pinned', 'locked', 'none').
  Future<String> begin();

  /// Puts the lock back after an install that did not replace the app.
  Future<void> end();
}

class KioskChannelHandoff implements InstallKioskHandoff {
  KioskChannelHandoff([KioskChannel? channel]) : _k = channel ?? KioskChannel();
  final KioskChannel _k;
  @override
  Future<String> begin() => _k.beginInstallHandoff();
  @override
  Future<void> end() => _k.endInstallHandoff();
}

/// The two ends' link: a [PlayTransport] to the one paired device, and how to close it. [pairing] is set on the real
/// link so the grown-up's phone can show the "let them in" card the first time a tablet connects.
class UpdateLink {
  const UpdateLink(this.transport, this.close, {this.pairing});
  final PlayTransport transport;
  final Future<void> Function() close;
  final LocalPairingController? pairing;
}

typedef UpdateLinkFactory = Future<UpdateLink> Function({required bool grownUp});

/// The real link: the Play-together stack (mDNS between the two paired devices, sealed hello between their pinned keys,
/// encrypted padded frames). Opens a lobby only while this is running, and closes it with [UpdateLink.close].
Future<UpdateLink> playUpdateLink({required bool grownUp}) async {
  final LocalPairingController c = LocalPairingController(role: grownUp ? 'dad' : 'ivy', displayName: 'Player');
  final LocalPairingTransport t = LocalPairingTransport(c);
  await c.start();
  return UpdateLink(t, () async {
    t.dispose();
    c.dispose();
  }, pairing: c);
}

/// What the grown-up's screen says right now, in one place.
enum TabletUpdateView {
  /// Nothing to say (no engine, nothing staged, not listening).
  none,
  listening,
  offered,
  downloading,
  paused,
  verifying,
  ready,
  checkingInstall,
  installing,
  refused,
}

class TabletUpdateService extends ChangeNotifier {
  TabletUpdateService({
    required this.engine,
    required this.store,
    UpdateLinkFactory? linkFactory,
    InstallKioskHandoff? kiosk,
    DateTime Function()? now,
    this.pieceTimeout = const Duration(seconds: 20),
  })  : _linkFactory = linkFactory ?? playUpdateLink,
        _kiosk = kiosk ?? KioskChannelHandoff(),
        _now = now ?? DateTime.now;

  /// The one in use, or null when this build has no update machinery (the feature is then absent everywhere).
  static TabletUpdateService? current;

  final UpdateEnginePort engine;
  final StagedUpdateStore store;
  final UpdateLinkFactory _linkFactory;
  final InstallKioskHandoff _kiosk;
  final DateTime Function() _now;
  final Duration pieceTimeout;

  bool get available => engine.available;

  // ---- state a screen reads ----------------------------------------------------------------------------------------

  StagedUpdate? _staged;
  StagedUpdate? get staged => _staged;
  WhatsNew? _whatsNew;
  WhatsNew? get whatsNew => _whatsNew;
  OwnUpdateOffer? _own;

  /// An update this tablet found itself and can fetch directly (it is online and the engine's own check saw one).
  OwnUpdateOffer? get ownOffer => _own;

  TabletUpdateReceiver? _receiver;
  TabletUpdateReceiver? get receiver => _receiver;
  UpdateLink? _link;
  UpdateLink? get link => _link;
  TabletUpdateSender? _sender;
  TabletUpdateSender? get sender => _sender;

  TabletUpdateCode? _result;

  /// The last thing that went wrong, or null. Plain words: [tabletUpdateAdultWords].
  TabletUpdateCode? get result => _result;

  int _ownDone = 0, _ownTotal = 0;
  bool _fetchingOwn = false;
  bool _checking = false;
  bool _installing = false;

  /// Set when Android's confirmation was shown; cleared when the app comes forward again (see [appResumed]) or the
  /// process restarts. While set, a staged update that says "installing" is believed, not reconciled.
  DateTime? _handedOverAt;
  bool get busy => _fetchingOwn || _checking || _installing || (_receiver != null && _isLive(_receiver!.phase));

  static bool _isLive(ReceivePhase p) =>
      p == ReceivePhase.listening || p == ReceivePhase.fetchingNotice || p == ReceivePhase.downloading || p == ReceivePhase.verifying;

  double? get progress {
    if (_fetchingOwn && _ownTotal > 0) return _ownDone / _ownTotal;
    final TabletUpdateReceiver? r = _receiver;
    if (r != null && r.totalBytes > 0 && (r.phase == ReceivePhase.downloading || r.phase == ReceivePhase.paused)) {
      return r.doneBytes / r.totalBytes;
    }
    return null;
  }

  TabletUpdateView get view {
    if (_checking) return TabletUpdateView.checkingInstall;
    if (_installing || _staged?.stage == StageState.installing) return TabletUpdateView.installing;
    if (_fetchingOwn) return TabletUpdateView.downloading;
    final TabletUpdateReceiver? r = _receiver;
    if (r != null) {
      switch (r.phase) {
        case ReceivePhase.listening || ReceivePhase.fetchingNotice:
          return TabletUpdateView.listening;
        case ReceivePhase.offered:
          return TabletUpdateView.offered;
        case ReceivePhase.downloading:
          return TabletUpdateView.downloading;
        case ReceivePhase.paused:
          return TabletUpdateView.paused;
        case ReceivePhase.verifying:
          return TabletUpdateView.verifying;
        case ReceivePhase.refused:
          return TabletUpdateView.refused;
        case ReceivePhase.ready || ReceivePhase.idle || ReceivePhase.stopped:
          break;
      }
    }
    if (_staged?.stage == StageState.ready) return TabletUpdateView.ready;
    if (_result != null) return TabletUpdateView.refused;
    return TabletUpdateView.none;
  }

  void _changed() => notifyListeners();

  // ---- start of the app, and every time a grown-up opens the screen ----------------------------------------------------

  /// Reads what is kept and reconciles it with what is installed. Safe to call as often as wanted. If a grown-up began an
  /// install and the app now IS that version, the staged file is deleted and a one-time "what is new" is kept; if the app
  /// is NOT that version, the staged update goes back to "ready" with a calm result. Never throws.
  Future<void> refresh() async {
    if (!engine.available) return;
    try {
      StagedUpdate? s = await store.loadStaged();
      if (s != null) {
        final InstalledFacts inst = await engine.installed();
        final Directory dir = await engine.stagingDirectory();
        if (inst.versionCode >= s.versionCode) {
          if (s.stage == StageState.installing) {
            await store.saveWhatsNew(WhatsNew(versionName: s.versionName, headline: s.headline, notes: s.notes));
          }
          await _deleteIfExists(File('${dir.path}${Platform.pathSeparator}${s.fileName}'));
          await store.clearStaged();
          await store.saveLastResult(null);
          _result = null;
          s = null;
        } else if (s.stage == StageState.installing && _handedOverAt != null) {
          // The installer is on screen right now; the answer is not in yet.
        } else if (s.stage == StageState.installing) {
          s = s.copyWith(stage: StageState.ready);
          await store.saveStaged(s);
          await store.saveLastResult(TabletUpdateCode.installDeclined.name);
        } else if (s.stage == StageState.receiving) {
          await store.clearStaged();
          s = null;
        } else if (!await File('${dir.path}${Platform.pathSeparator}${s.fileName}').exists()) {
          await store.clearStaged();
          s = null;
        }
      }
      _staged = s;
      _whatsNew = await store.loadWhatsNew();
      // A result already in memory (something that just went wrong in this run) is not overwritten by an older one.
      final String? last = await store.loadLastResult();
      if (_result == null && last != null) {
        _result = TabletUpdateCode.values.where((TabletUpdateCode c) => c.name == last).firstOrNull;
      }
      _own = await engine.ownOffer();
    } catch (_) {
      // Reading is best effort: a failure here shows nothing rather than something wrong.
    }
    _changed();
  }

  Future<void> _deleteIfExists(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// A grown-up has seen "what is new".
  Future<void> dismissWhatsNew() async {
    await store.clearWhatsNew();
    _whatsNew = null;
    _changed();
  }

  // ---- the tablet: listening to the phone -----------------------------------------------------------------------------

  /// A grown-up at the tablet chose "Get the update from the phone". Opens the link and starts listening.
  Future<void> startReceiving({required bool Function() adultPresent}) async {
    if (!engine.available) {
      _fail(TabletUpdateCode.noEngine);
      return;
    }
    if (!adultPresent()) {
      _fail(TabletUpdateCode.notAllowed);
      return;
    }
    if (busy) {
      _fail(TabletUpdateCode.busy);
      return;
    }
    await stopReceiving();
    _result = null;
    try {
      final UpdateLink l = await _linkFactory(grownUp: false);
      _link = l;
      final TabletUpdateReceiver r = TabletUpdateReceiver(
          engine: engine, store: store, adultPresent: adultPresent, pieceTimeout: pieceTimeout);
      r.addListener(_onReceiver);
      _receiver = r;
      await r.listen(l.transport);
    } on TabletUpdateRefused catch (e) {
      await stopReceiving();
      _fail(e.code);
      return;
    } catch (_) {
      await stopReceiving();
      _fail(TabletUpdateCode.lostTouch);
      return;
    }
    _changed();
  }

  void _onReceiver() {
    final TabletUpdateReceiver? r = _receiver;
    if (r != null && r.phase == ReceivePhase.ready) {
      unawaited(refresh());
    }
    _changed();
  }

  /// "Get it": the grown-up accepts what the phone offered.
  Future<void> acceptOffer() async {
    final TabletUpdateReceiver? r = _receiver;
    if (r == null) return;
    try {
      await r.accept();
    } on TabletUpdateRefused catch (e) {
      _fail(e.code);
    }
    _changed();
  }

  /// The refusal the receiver ended on, if it ended on one.
  TabletUpdateCode? get receiverRefusal => _receiver?.refusal;

  Future<void> stopReceiving() async {
    final TabletUpdateReceiver? r = _receiver;
    final UpdateLink? l = _link;
    _receiver = null;
    _link = null;
    if (r != null) {
      r.removeListener(_onReceiver);
      await r.stop();
      r.dispose();
    }
    if (l != null) await l.close();
    _changed();
  }

  // ---- the tablet: fetching it itself (the fallback) -------------------------------------------------------------------

  /// The tablet is online and the engine found an update itself: fetch it with the engine's own downloader, then take it
  /// through the SAME checks as a file from the phone before it counts as staged.
  Future<void> fetchOwn({required bool Function() adultPresent}) async {
    if (!engine.available) {
      _fail(TabletUpdateCode.noEngine);
      return;
    }
    if (!adultPresent()) {
      _fail(TabletUpdateCode.notAllowed);
      return;
    }
    if (busy) {
      _fail(TabletUpdateCode.busy);
      return;
    }
    final OwnUpdateOffer? offer = _own ?? await engine.ownOffer();
    if (offer == null) {
      _fail(TabletUpdateCode.upToDate);
      return;
    }
    _fetchingOwn = true;
    _result = null;
    _ownDone = 0;
    _ownTotal = offer.update.apk.size;
    _changed();
    try {
      final InstalledFacts inst = await engine.installed();
      checkNoticeAgainstInstalled(offer.update, inst);
      await checkGuards(engine, offer.update.apk.size, margin: kTabletSpaceMargin);
      final HeldUpdate got = await engine.fetchOwn(offer, onProgress: (int done, int total) {
        _ownDone = done;
        _ownTotal = total;
        _changed();
      });
      await _stageHeld(got);
    } on TabletUpdateRefused catch (e) {
      _fail(e.code);
    } catch (_) {
      _fail(TabletUpdateCode.lostTouch);
    } finally {
      _fetchingOwn = false;
    }
    await refresh();
  }

  /// Takes a verified file from the engine through the tablet's own checks into the staging folder.
  Future<void> _stageHeld(HeldUpdate h) async {
    final VerifiedUpdate u = await engine.verify(h.update.document, forInstall: false);
    checkNoticeAgainstInstalled(u, await engine.installed());
    await checkApkFileAgainstNotice(engine: engine, update: u, file: h.apk);
    final Directory dir = await engine.stagingDirectory();
    final String name = 'update-${u.versionCode}.apk';
    final File staged = File('${dir.path}${Platform.pathSeparator}$name');
    if (h.apk.path != staged.path) {
      if (await staged.exists()) await staged.delete();
      await h.apk.copy(staged.path);
    }
    await store.saveStaged(StagedUpdate(
        stage: StageState.ready,
        versionName: u.versionName,
        versionCode: u.versionCode,
        fileName: name,
        document: u.document,
        headline: u.headline,
        notes: u.notes));
    await store.saveLastResult(null);
  }

  // ---- the tablet: installing --------------------------------------------------------------------------------------------

  /// Installs the staged update. Every check is repeated first; the lock is released only after they all pass and a
  /// grown-up is still proved; the result is the code of what stopped it, or null when Android's confirmation was shown.
  Future<TabletUpdateCode?> install({required bool Function() adultPresent}) async {
    if (!engine.available) return _fail(TabletUpdateCode.noEngine);
    if (!adultPresent()) return _fail(TabletUpdateCode.notAllowed);
    if (_installing || _checking) return _fail(TabletUpdateCode.busy);
    _checking = true;
    _result = null;
    _changed();
    StagedUpdate? s;
    File? apk;
    VerifiedUpdate? u;
    InstalledFacts? inst;
    try {
      s = await store.loadStaged();
      if (s == null || s.stage == StageState.receiving) throw const TabletUpdateRefused(TabletUpdateCode.cancelled);
      final Directory dir = await engine.stagingDirectory();
      apk = File('${dir.path}${Platform.pathSeparator}${s.fileName}');
      if (!await apk.exists()) {
        await store.clearStaged();
        throw const TabletUpdateRefused(TabletUpdateCode.changedOnDisk);
      }
      // The notice again, as the engine verifies it at install time, and the version check against NOW's installed.
      u = await engine.verify(s.document, forInstall: true);
      inst = await engine.installed();
      checkNoticeAgainstInstalled(u, inst);
      if (u.versionCode != s.versionCode) throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
      // The file again, from the bytes on the disk right now (never "it was fine when it arrived").
      try {
        await checkApkFileAgainstNotice(engine: engine, update: u, file: apk);
      } on TabletUpdateRefused catch (e) {
        if (e.code == TabletUpdateCode.hashMismatch || e.code == TabletUpdateCode.truncated) {
          await _deleteIfExists(apk);
          await store.clearStaged();
          throw const TabletUpdateRefused(TabletUpdateCode.changedOnDisk);
        }
        rethrow;
      }
      final DeviceGuards g = await engine.guards();
      if (g.batteryPercent >= 0 && g.batteryPercent < 20 && !g.charging) throw const TabletUpdateRefused(TabletUpdateCode.lowBattery);
      // The hashing above took a while. A grown-up has to still be here.
      if (!adultPresent()) throw const TabletUpdateRefused(TabletUpdateCode.notAllowed);
    } on TabletUpdateRefused catch (e) {
      _checking = false;
      await refresh();
      return _fail(e.code, remember: true);
    } catch (_) {
      _checking = false;
      await refresh();
      return _fail(TabletUpdateCode.installFailed, remember: true);
    }
    _checking = false;
    _installing = true;
    _changed();
    final StagedUpdate marker = s.copyWith(
        stage: StageState.installing, installStartedAtMs: _now().millisecondsSinceEpoch, fromVersionCode: inst.versionCode);
    try {
      // Pre-update safety: every write this app makes is atomic and flushed when it is made, so what is on disk is
      // whole. The marker below says an update began, from which version, and when.
      await store.saveStaged(marker);
      await _kiosk.begin();
      InstallOutcome out;
      try {
        out = await engine.install(apk, u);
      } catch (_) {
        out = InstallOutcome.failed;
      }
      if (out == InstallOutcome.handedToSystem) {
        _handedOverAt = _now();
        await store.saveLastResult(null);
        _changed();
        return null;
      }
      await _kiosk.end();
      await store.saveStaged(s.copyWith(stage: StageState.ready));
      final TabletUpdateCode code = switch (out) {
        InstallOutcome.declined => TabletUpdateCode.installDeclined,
        InstallOutcome.needsPermission => TabletUpdateCode.needsPermission,
        _ => TabletUpdateCode.installFailed,
      };
      return _fail(code, remember: true);
    } finally {
      _installing = false;
      await refresh();
    }
  }

  /// The app came to the front again (the kiosk shell tells us). If Android's confirmation had been shown a moment ago and
  /// this process is still running, the app was NOT replaced: the grown-up cancelled or Android said no. The staged update
  /// goes back to "ready" with a calm result, and the native side has already put the lock back.
  void appResumed() {
    final DateTime? at = _handedOverAt;
    if (at == null || _now().difference(at) < const Duration(seconds: 2)) return;
    _handedOverAt = null;
    unawaited(refresh());
  }

  /// The grown-up chose to drop the staged update. Deletes the file and the record.
  Future<void> discardStaged() async {
    final StagedUpdate? s = await store.loadStaged();
    if (s != null) {
      final Directory dir = await engine.stagingDirectory();
      await _deleteIfExists(File('${dir.path}${Platform.pathSeparator}${s.fileName}'));
    }
    await store.clearStaged();
    await store.saveLastResult(null);
    _result = null;
    await refresh();
  }

  TabletUpdateCode _fail(TabletUpdateCode c, {bool remember = false}) {
    _result = c;
    if (remember) unawaited(store.saveLastResult(c.name));
    _changed();
    return c;
  }

  // ---- the grown-up's phone: sharing ------------------------------------------------------------------------------------

  /// The verified update this phone holds, if any.
  Future<HeldUpdate?> held() async => engine.available ? engine.held() : null;

  /// A grown-up on THIS phone chose "Share with the tablet". Opens the link and starts offering.
  Future<void> startSharing({required bool Function() adultPresent}) async {
    if (!engine.available) {
      _fail(TabletUpdateCode.noEngine);
      return;
    }
    if (!adultPresent()) {
      _fail(TabletUpdateCode.notAllowed);
      return;
    }
    await stopSharing();
    _result = null;
    final HeldUpdate? h = await engine.held();
    if (h == null) {
      _fail(TabletUpdateCode.cancelled);
      return;
    }
    try {
      final UpdateLink l = await _linkFactory(grownUp: true);
      _link = l;
      final TabletUpdateSender s = TabletUpdateSender(transport: l.transport, held: h, grownUpDevice: true, adultPresent: adultPresent);
      s.addListener(_changed);
      _sender = s;
      await s.start();
    } on TabletUpdateRefused catch (e) {
      await stopSharing();
      _fail(e.code);
      return;
    } catch (_) {
      await stopSharing();
      _fail(TabletUpdateCode.lostTouch);
      return;
    }
    _changed();
  }

  Future<void> stopSharing() async {
    final TabletUpdateSender? s = _sender;
    final UpdateLink? l = _link;
    _sender = null;
    if (_receiver == null) _link = null;
    if (s != null) {
      s.removeListener(_changed);
      await s.stop();
      s.dispose();
    }
    if (l != null && _receiver == null) await l.close();
    _changed();
  }
}
