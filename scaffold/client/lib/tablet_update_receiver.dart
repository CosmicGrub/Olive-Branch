// OLIVE BRANCH — the tablet's side of taking an update from the grown-up's phone. Verified headless
// (test/tablet_update_transfer_test.dart, tablet_update_hostile_test.dart, tablet_update_wiring_test.dart over the real
// encrypted transport). MASTERFILE section 7.25.
//
// THE TABLET TRUSTS NOTHING THE PHONE SAYS. Everything the phone sends is checked here, on the tablet, in this order:
//   1. Only while a grown-up has opened the update screen in Guardian mode ([adultPresent], read at each step) does the
//      tablet listen at all. A child cannot start it, and an offer that arrives while nothing is open is dropped.
//   2. The sender is the paired phone (the transport supplies the sender), the session id is the one in the offer, and
//      every message is exactly well-formed (tablet_update_wire.dart).
//   3. The signed notice is fetched first and checked against its offered hash, then handed to the update ENGINE
//      ([UpdateEnginePort.verify]): size cap, Ed25519 signature against a built-in key, channel, validity window, not
//      an older notice than one already seen, this app, a file for this processor. Then the tablet checks for itself
//      what it will not take on the engine's word: the version is strictly higher than the one installed (no
//      rollback), the package is this app, and the file's pinned signing certificate is the installed app's.
//   4. Storage and battery are checked before a byte of the file is asked for.
//   5. The file arrives in windows the tablet asks for, strictly in order, from the last verified byte. Each manifest
//      chunk is hashed the moment it is complete (a bad chunk stops everything at once), the total can never pass the
//      signed size, and a stray, repeated, out-of-order or oversized piece is dropped and counted.
//   6. At the end: exact size, whole-file SHA-256, and the APK's own package, version and signing certificate read from
//      the file by the platform, against the manifest and against what is installed.
//   7. Only then is the file renamed into place and recorded as staged. A partial file is never installable: it has a
//      different name and is deleted on any failure.
// The result is a staged update that a grown-up can install (tablet_update_service.dart), which repeats checks 3 and 6
// at the moment of installing. Nothing in this file shows anything to a child.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'play_transport.dart';
import 'tablet_update_checks.dart';
import 'tablet_update_hash.dart';
import 'tablet_update_port.dart';
import 'tablet_update_store.dart';
import 'tablet_update_wire.dart';

/// Room the tablet wants beyond the file itself (the installer copies the file once more).
const int kTabletSpaceMargin = 64 * 1024 * 1024;

/// Stray or invalid messages tolerated in one session before the tablet stops listening.
const int kReceiverBadBudget = 60;

enum ReceivePhase { idle, listening, fetchingNotice, offered, downloading, verifying, ready, paused, refused, stopped }

class TabletUpdateReceiver extends ChangeNotifier {
  TabletUpdateReceiver({
    required this.engine,
    required this.store,
    required this.adultPresent,
    this.pieceTimeout = const Duration(seconds: 20),
    this.maxRetries = 4,
  });

  final UpdateEnginePort engine;
  final StagedUpdateStore store;

  /// True only while a grown-up has been proved at this tablet (Guardian mode). Read at every step that matters.
  final bool Function() adultPresent;
  final Duration pieceTimeout;
  final int maxRetries;

  ReceivePhase _phase = ReceivePhase.idle;
  ReceivePhase get phase => _phase;
  TabletUpdateCode? _refusal;
  TabletUpdateCode? get refusal => _refusal;

  /// The verified update on offer (from the phone's notice), once the notice checked out.
  VerifiedUpdate? get offered => _offered;
  VerifiedUpdate? _offered;

  int get doneBytes => _received;
  int get totalBytes => _offered?.apk.size ?? 0;

  PlayTransport? _transport;
  StreamSubscription<PlayInbound>? _in;
  StreamSubscription<PeerPresence>? _pres;
  Future<void> _chain = Future<void>.value();
  int _bad = 0;

  // The notice.
  String? _sid;
  String? _docSha;
  int _docLen = 0;
  final BytesBuilder _doc = BytesBuilder(copy: false);
  int _docWindowEnd = 0;

  // The file.
  Directory? _dir;
  File? _part;
  RandomAccessFile? _raf;
  int _received = 0;
  int _windowEnd = 0;
  int _chunkIndex = 0;
  final BytesBuilder _chunk = BytesBuilder(copy: false);
  RunningSha256? _whole;
  Timer? _stall;
  int _retries = 0;
  InstalledFacts? _installed;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _set(ReceivePhase p) {
    if (_phase == p) return;
    _phase = p;
    _notify();
  }

  Future<T> _locked<T>(Future<T> Function() body) {
    final Completer<T> done = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await body());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  // ---- arming ------------------------------------------------------------------------------------------------------

  /// A grown-up at the tablet opened "Get the update from the phone". Starts listening on [transport]. Throws
  /// [TabletUpdateRefused] when there is no engine or no grown-up.
  Future<void> listen(PlayTransport transport) async {
    if (!engine.available) throw const TabletUpdateRefused(TabletUpdateCode.noEngine);
    if (!adultPresent()) throw const TabletUpdateRefused(TabletUpdateCode.notAllowed);
    if (_phase != ReceivePhase.idle && _phase != ReceivePhase.stopped && _phase != ReceivePhase.refused) {
      throw const TabletUpdateRefused(TabletUpdateCode.busy);
    }
    _reset();
    _installed = await engine.installed();
    _transport = transport;
    _in = transport.incoming.listen((PlayInbound m) => unawaited(_locked(() => _onIncoming(m))));
    _pres = transport.presence.listen((PeerPresence p) {
      if (p == PeerPresence.present && _phase == ReceivePhase.paused) unawaited(_locked(_resume));
    });
    _set(ReceivePhase.listening);
  }

  void _reset() {
    _refusal = null;
    _offered = null;
    _bad = 0;
    _sid = null;
    _docSha = null;
    _docLen = 0;
    _doc.clear();
    _received = 0;
    _windowEnd = 0;
    _chunkIndex = 0;
    _chunk.clear();
    _whole = null;
    _retries = 0;
  }

  // ---- incoming ----------------------------------------------------------------------------------------------------

  void _strike() {
    _bad++;
    if (_bad > kReceiverBadBudget) unawaited(_locked(() => _giveUp(TabletUpdateCode.cancelled, tell: true)));
  }

  Future<void> _onIncoming(PlayInbound inbound) async {
    if (_disposed) return;
    if (_phase == ReceivePhase.idle || _phase == ReceivePhase.stopped || _phase == ReceivePhase.refused || _phase == ReceivePhase.ready) {
      return;
    }
    // Nothing is taken unless a grown-up is, at this moment, at the tablet.
    if (!adultPresent()) {
      return;
    }
    final PlayTransport? t = _transport;
    if (t == null || inbound.senderSeat != t.peerSeat) {
      _strike();
      return;
    }
    final UpdateMsg? m = decodeUpdateMsg(inbound.raw);
    if (m == null) {
      _strike();
      return;
    }
    switch (m) {
      case OfferMsg():
        await _onOffer(m);
      case PieceMsg():
        if (m.sid != _sid) {
          _strike();
          return;
        }
        if (m.obj == UpdateObject.doc) {
          await _onDocPiece(m);
        } else {
          await _onApkPiece(m);
        }
      case EndMsg():
        if (m.sid != _sid) return;
        if (m.why == EndWhy.stop) {
          _stall?.cancel();
          if (_phase == ReceivePhase.downloading) {
            _set(ReceivePhase.paused);
          } else if (_phase == ReceivePhase.fetchingNotice) {
            _set(ReceivePhase.listening);
          }
        }
      case NeedMsg():
        // A phone never asks a tablet for anything.
        _strike();
    }
  }

  Future<void> _onOffer(OfferMsg m) async {
    switch (_phase) {
      case ReceivePhase.listening:
        if (m.docLen > 256 * 1024) {
          _strike();
          return;
        }
        _sid = m.sid;
        _docSha = m.docSha;
        _docLen = m.docLen;
        _doc.clear();
        _set(ReceivePhase.fetchingNotice);
        await _requestDoc();
      case ReceivePhase.fetchingNotice:
        // The same notice offered again (the phone re-offers every few seconds, and after a lost link).
        if (m.docSha == _docSha && m.docLen == _docLen) {
          _sid = m.sid;
          if (_doc.length == 0) await _requestDoc();
        }
      case ReceivePhase.offered || ReceivePhase.downloading || ReceivePhase.paused || ReceivePhase.verifying:
        if (m.docSha == _docSha) {
          // The phone started a new session for the very same notice: carry on with it.
          _sid = m.sid;
          if (_phase == ReceivePhase.paused) await _resume();
        } else {
          _strike();
        }
      case ReceivePhase.idle || ReceivePhase.refused || ReceivePhase.stopped || ReceivePhase.ready:
        break;
    }
  }

  // ---- the signed notice -------------------------------------------------------------------------------------------

  Future<void> _requestDoc() async {
    final int off = _doc.length;
    final int len = min(kUpdateWindowBytes, _docLen - off);
    _docWindowEnd = off + len;
    await _send(NeedMsg(_sid!, obj: UpdateObject.doc, off: off, len: len));
  }

  Future<void> _onDocPiece(PieceMsg m) async {
    if (_phase != ReceivePhase.fetchingNotice) {
      _strike();
      return;
    }
    final bool lastOfWindow = m.off + m.data.length == _docWindowEnd;
    if (m.off != _doc.length || m.off + m.data.length > _docWindowEnd || (!lastOfWindow && m.data.length != kUpdatePieceBytes)) {
      _strike();
      return;
    }
    _doc.add(m.data);
    if (_doc.length < _docLen) {
      if (_doc.length == _docWindowEnd) await _requestDoc();
      return;
    }
    final Uint8List doc = _doc.takeBytes();
    if (await sha256HexOf(doc) != _docSha) {
      await _giveUp(TabletUpdateCode.notGenuine, tell: true);
      return;
    }
    try {
      final VerifiedUpdate u = await engine.verify(doc, forInstall: false);
      checkNoticeAgainstInstalled(u, _installed ?? await engine.installed());
      _offered = u;
      _set(ReceivePhase.offered);
    } on TabletUpdateRefused catch (e) {
      await _giveUp(e.code, tell: true);
    } catch (_) {
      await _giveUp(TabletUpdateCode.notGenuine, tell: true);
    }
  }

  // ---- the file ----------------------------------------------------------------------------------------------------

  /// The grown-up said "Get it". Checks space and battery, then asks for the file from the last verified byte.
  Future<void> accept() => _locked(() async {
        if (_phase != ReceivePhase.offered) throw const TabletUpdateRefused(TabletUpdateCode.busy);
        if (!adultPresent()) throw const TabletUpdateRefused(TabletUpdateCode.notAllowed);
        final VerifiedUpdate u = _offered!;
        await checkGuards(engine, u.apk.size, margin: kTabletSpaceMargin);
        _dir = await engine.stagingDirectory();
        _part = File('${_dir!.path}${Platform.pathSeparator}u${_docSha!.substring(0, 16)}.part');
        await _openAndResumeFromDisk(u.apk);
        _retries = 0;
        _set(ReceivePhase.downloading);
        await _requestWindow();
      });

  /// Keeps the longest verified prefix of a partial file from an earlier attempt and throws the rest away.
  Future<void> _openAndResumeFromDisk(ApkFacts a) async {
    final File part = _part!;
    _whole = RunningSha256();
    _chunk.clear();
    _chunkIndex = 0;
    _received = 0;
    if (!await part.exists()) await part.create(recursive: true);
    final int have = await part.length();
    final RandomAccessFile raf = await part.open(mode: FileMode.append);
    int good = 0;
    int idx = 0;
    if (have > 0 && have <= a.size) {
      await raf.setPosition(0);
      while (idx < a.chunkSha256.length) {
        final int start = idx * a.chunkSize;
        final int end = min(start + a.chunkSize, a.size);
        if (end > have) break;
        final Uint8List b = await raf.read(end - start);
        if (b.length != end - start || await sha256HexOf(b) != a.chunkSha256[idx]) break;
        _whole!.add(b);
        good = end;
        idx++;
      }
    }
    if (good != have) {
      await raf.truncate(good);
    }
    await raf.setPosition(good);
    _raf = raf;
    _received = good;
    _chunkIndex = idx;
  }

  Future<void> _requestWindow() async {
    final VerifiedUpdate u = _offered!;
    if (_received >= u.apk.size) return;
    final int len = min(kUpdateWindowBytes, u.apk.size - _received);
    _windowEnd = _received + len;
    _armStall();
    await _send(NeedMsg(_sid!, obj: UpdateObject.apk, off: _received, len: len));
  }

  void _armStall() {
    _stall?.cancel();
    _stall = Timer(pieceTimeout, () => unawaited(_locked(_onStall)));
  }

  Future<void> _onStall() async {
    if (_phase != ReceivePhase.downloading) return;
    if (_retries >= maxRetries) {
      _set(ReceivePhase.paused);
      return;
    }
    _retries++;
    await _requestWindow();
  }

  Future<void> _resume() async {
    if (_phase != ReceivePhase.paused || _offered == null) return;
    _retries = 0;
    _set(ReceivePhase.downloading);
    await _requestWindow();
  }

  Future<void> _onApkPiece(PieceMsg m) async {
    if (_phase != ReceivePhase.downloading) {
      _strike();
      return;
    }
    final VerifiedUpdate u = _offered!;
    final ApkFacts a = u.apk;
    final bool lastOfWindow = m.off + m.data.length == _windowEnd;
    // Strictly in order, inside the window asked for, never past the signed size, full pieces except the last.
    if (m.off != _received || m.off + m.data.length > _windowEnd || m.off + m.data.length > a.size ||
        (!lastOfWindow && m.data.length != kUpdatePieceBytes)) {
      _strike();
      return;
    }
    await _raf!.writeFrom(m.data);
    _received += m.data.length;
    _retries = 0;
    // A piece may straddle a chunk boundary, so it is fed to the chunk buffer in segments. Every complete manifest
    // chunk is checked the moment it is complete.
    int at = 0;
    while (at < m.data.length) {
      final int chunkEnd = min((_chunkIndex + 1) * a.chunkSize, a.size);
      final int have = _chunk.length;
      final int need = (chunkEnd - (_chunkIndex * a.chunkSize)) - have;
      final int take = min(need, m.data.length - at);
      _chunk.add(Uint8List.sublistView(m.data, at, at + take));
      at += take;
      if (_chunk.length == chunkEnd - (_chunkIndex * a.chunkSize)) {
        final Uint8List bytes = _chunk.takeBytes();
        if (await sha256HexOf(bytes) != a.chunkSha256[_chunkIndex]) {
          await _discardPart();
          await _giveUp(TabletUpdateCode.hashMismatch, tell: true);
          return;
        }
        _whole!.add(bytes);
        _chunkIndex++;
      }
    }
    _notify();
    if (_received == a.size) {
      _stall?.cancel();
      await _finalize();
    } else if (_received == _windowEnd) {
      await _requestWindow();
    } else {
      _armStall();
    }
  }

  Future<void> _finalize() async {
    _set(ReceivePhase.verifying);
    final VerifiedUpdate u = _offered!;
    try {
      await _raf!.flush();
      await _raf!.close();
      _raf = null;
      final File part = _part!;
      await checkApkFileAgainstNotice(engine: engine, update: u, file: part, knownSha: await _whole!.finish());
      final String name = 'update-${u.versionCode}.apk';
      final File staged = File('${_dir!.path}${Platform.pathSeparator}$name');
      if (await staged.exists()) await staged.delete();
      await part.rename(staged.path);
      await store.saveStaged(StagedUpdate(
          stage: StageState.ready,
          versionName: u.versionName,
          versionCode: u.versionCode,
          fileName: name,
          document: u.document,
          headline: u.headline,
          notes: u.notes));
      await store.saveLastResult(null);
      _set(ReceivePhase.ready);
      await _send(EndMsg(_sid!, EndWhy.done));
    } on TabletUpdateRefused catch (e) {
      await _discardPart();
      await _giveUp(e.code, tell: true);
    } catch (_) {
      await _discardPart();
      await _giveUp(TabletUpdateCode.installFailed, tell: true);
    }
  }

  Future<void> _discardPart() async {
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;
    try {
      final File? p = _part;
      if (p != null && await p.exists()) await p.delete();
    } catch (_) {}
  }

  // ---- ending ------------------------------------------------------------------------------------------------------

  Future<void> _send(UpdateMsg m) async {
    final PlayTransport? t = _transport;
    if (t == null) return;
    await t.send(encodeUpdateMsg(m));
  }

  Future<void> _giveUp(TabletUpdateCode code, {required bool tell}) async {
    _stall?.cancel();
    _refusal = code;
    final String? sid = _sid;
    _set(ReceivePhase.refused);
    // The phone is told only that it was refused: no reason crosses the wire.
    if (tell && sid != null) await _send(EndMsg(sid, EndWhy.refused));
    await _release();
  }

  Future<void> _release() async {
    await _in?.cancel();
    await _pres?.cancel();
    _in = null;
    _pres = null;
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;
  }

  /// The grown-up left the screen. A partial file stays (it resumes next time); nothing is deleted but the listener.
  Future<void> stop() => _locked(() async {
        _stall?.cancel();
        final String? sid = _sid;
        final bool live = _phase == ReceivePhase.fetchingNotice || _phase == ReceivePhase.downloading || _phase == ReceivePhase.paused;
        if (_phase != ReceivePhase.ready && _phase != ReceivePhase.refused) _set(ReceivePhase.stopped);
        if (live && sid != null) await _send(EndMsg(sid, EndWhy.stop));
        await _release();
      });

  @override
  void dispose() {
    _disposed = true;
    _stall?.cancel();
    // Closed behind any piece still being written, so the partial file is never left open (it must be renamable next run).
    unawaited(_in?.cancel());
    unawaited(_pres?.cancel());
    unawaited(_locked(_release));
    super.dispose();
  }
}
