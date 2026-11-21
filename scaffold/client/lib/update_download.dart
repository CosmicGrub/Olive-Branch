// OLIVE BRANCH — the resumable, chunk-verified download and the safe place it keeps a file. Verified headless
// (test/update_download_test.dart: a fake transport that lies in every way a network can). MASTERFILE 7.24.
//
// SAFE PARTIAL FILES. The manifest (signed) names the size, the SHA-256 of every chunk and the SHA-256 of the whole
// file. A file under download is named `<sha256>.part` and is NEVER something the installer can be handed: only a
// finished, fully checked file is renamed to `<sha256>.apk`, and the installer is handed nothing else. Each chunk is
// checked BEFORE it is written, so a corrupt chunk never reaches the disk; a part file left by a crash, a power cut
// or a full disk is re-checked chunk by chunk when the download resumes and cut back to the last good chunk (so
// nothing about a part file is trusted, not even our own). The name carries the hash, so a part file can never be
// mistaken for a different version's.
//
// WEAK LINKS. One connection streams from the first missing byte (Range). A dropped connection resumes from the last
// verified chunk, with a short doubling wait, a few times per address; a corrupt chunk or a lie about size marks the
// ADDRESS bad and the next one (the mirror) is tried from the same point. A server that ignores Range and sends the
// whole file is tolerated (the bytes we already have are skipped). More bytes than the manifest allows are refused
// the moment they are seen; fewer is a dropped connection, never a finished file.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'update_manifest.dart';
import 'update_transport.dart';

String _hex(List<int> bytes) => <String>[for (final int b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

Future<String> sha256OfBytes(List<int> bytes) async => _hex((await Sha256().hash(bytes)).bytes);

/// SHA-256 of a whole file, read in pieces.
Future<String> sha256OfFile(File f) async {
  final HashSink sink = Sha256().newHashSink();
  await for (final List<int> part in f.openRead()) {
    sink.add(part);
  }
  sink.close();
  return _hex((await sink.hash()).bytes);
}

/// The app-private folder an update lives in.
class UpdateStaging {
  UpdateStaging(this.dir);
  final Directory dir;

  File partFor(ApkEntry a) => File('${dir.path}${Platform.pathSeparator}${a.sha256}.part');
  File finalFor(ApkEntry a) => File('${dir.path}${Platform.pathSeparator}${a.sha256}.apk');

  Future<void> ensure() async {
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  /// Deletes everything in the folder except the files that belong to [keep] (null keeps nothing).
  Future<void> sweep({ApkEntry? keep}) async {
    if (!await dir.exists()) return;
    final Set<String> keepNames = keep == null
        ? <String>{}
        : <String>{partFor(keep).uri.pathSegments.last, finalFor(keep).uri.pathSegments.last};
    await for (final FileSystemEntity e in dir.list(followLinks: false)) {
      if (keepNames.contains(e.uri.pathSegments.where((String s) => s.isNotEmpty).last)) continue;
      try {
        await e.delete(recursive: true);
      } catch (_) {
        // A file that cannot be removed is left; it is never read.
      }
    }
  }

  Future<void> discard(ApkEntry a) async {
    for (final File f in <File>[partFor(a), finalFor(a)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// How many leading chunks of the part file are intact. The file is cut back to exactly those, so what is left is
  /// always a prefix of the real file.
  Future<int> goodChunks(ApkEntry a) async {
    final File p = partFor(a);
    if (!await p.exists()) return 0;
    final int have = await p.length();
    int good = 0;
    final RandomAccessFile r = await p.open();
    try {
      while (good < a.chunkCount) {
        final int len = a.chunkLength(good);
        if ((good * a.chunkSize) + len > have) break;
        final Uint8List piece = await r.read(len);
        if (piece.length != len || await sha256OfBytes(piece) != a.chunks[good]) break;
        good++;
      }
    } finally {
      await r.close();
    }
    final int keepBytes = good == 0 ? 0 : (good == a.chunkCount ? a.size : good * a.chunkSize);
    if (have != keepBytes) {
      final RandomAccessFile w = await p.open(mode: FileMode.append);
      try {
        await w.truncate(keepBytes);
      } finally {
        await w.close();
      }
    }
    return good;
  }

  /// The finished file for [a], if there is one and it is still exactly what the manifest says.
  Future<File?> verifiedFile(ApkEntry a) async {
    final File f = finalFor(a);
    if (!await f.exists()) return null;
    if (await f.length() != a.size || await sha256OfFile(f) != a.sha256) {
      try {
        await f.delete();
      } catch (_) {}
      return null;
    }
    return f;
  }
}

class DownloadProgress {
  const DownloadProgress(this.doneBytes, this.totalBytes);
  final int doneBytes, totalBytes;
  double get fraction => totalBytes == 0 ? 0 : doneBytes / totalBytes;
}

/// Called before every chunk; throws [UpdateRefusal] (lowBattery, needsWifi, noSpace, cancelled) to pause.
typedef UpdateGuard = Future<void> Function();

class UpdateDownloader {
  UpdateDownloader({
    required this.transport,
    required this.staging,
    this.retriesPerUrl = 3,
    this.backoff = const Duration(seconds: 2),
    this.stall = const Duration(seconds: 30),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? ((Duration d) => Future<void>.delayed(d));

  final UpdateTransport transport;
  final UpdateStaging staging;
  final int retriesPerUrl;
  final Duration backoff;
  final Duration stall;
  final Future<void> Function(Duration) _sleep;

  /// Downloads (or finishes downloading) the file [apk] names and returns it only once it is complete and exactly what
  /// the manifest says. Throws [UpdateRefusal]; every refusal leaves nothing installable behind.
  Future<File> download(
    ApkEntry apk, {
    void Function(DownloadProgress)? onProgress,
    UpdateCancel? cancel,
    UpdateGuard? guard,
  }) async {
    await staging.ensure();
    await staging.sweep(keep: apk);
    final File? already = await staging.verifiedFile(apk);
    if (already != null) {
      onProgress?.call(DownloadProgress(apk.size, apk.size));
      return already;
    }
    int good = await staging.goodChunks(apk);
    onProgress?.call(DownloadProgress(_bytesFor(apk, good), apk.size));
    UpdateRefusal? last;
    for (int u = 0; u < apk.urls.length && good < apk.chunkCount; u++) {
      int attempt = 0;
      while (good < apk.chunkCount) {
        if (cancel?.isCancelled ?? false) throw const UpdateRefusal(UpdateRefusalCode.cancelled);
        try {
          good = await _pull(apk, apk.urls[u], good, onProgress, cancel, guard);
        } on UpdateRefusal catch (e) {
          last = e;
          // The part file may have grown by whole good chunks before the failure: take them.
          good = await staging.goodChunks(apk);
          switch (e.code) {
            case UpdateRefusalCode.cancelled:
            case UpdateRefusalCode.lowBattery:
            case UpdateRefusalCode.needsWifi:
            case UpdateRefusalCode.noSpace:
              rethrow; // a pause, not a failure of the address
            case UpdateRefusalCode.offline:
            case UpdateRefusalCode.truncated:
              if (++attempt <= retriesPerUrl) {
                await _sleep(backoff * (1 << (attempt - 1)));
                continue;
              }
            default:
              break; // a lie, a bad chunk, a 404, a bad redirect: this address is finished
          }
          break;
        }
        break;
      }
    }
    if (good < apk.chunkCount) throw last ?? const UpdateRefusal(UpdateRefusalCode.truncated, 'no address worked');
    return _finish(apk);
  }

  int _bytesFor(ApkEntry a, int chunks) => chunks >= a.chunkCount ? a.size : chunks * a.chunkSize;

  Future<int> _pull(ApkEntry apk, Uri url, int from, void Function(DownloadProgress)? onProgress, UpdateCancel? cancel,
      UpdateGuard? guard) async {
    final int offset = from * apk.chunkSize;
    final UpdateStream s = await transport.open(url, rangeStart: offset, cancel: cancel);
    int skip = 0;
    final int remaining = apk.size - offset;
    if (offset > 0) {
      if (s.status == 206) {
        if (s.contentRangeStart != offset) throw const UpdateRefusal(UpdateRefusalCode.httpError, 'wrong range');
        if (s.contentLength != null && s.contentLength! > remaining) {
          throw const UpdateRefusal(UpdateRefusalCode.tooMuchData, 'more than the file');
        }
      } else {
        skip = offset; // the server sent the whole file from the start
        if (s.contentLength != null && s.contentLength! > apk.size) {
          throw const UpdateRefusal(UpdateRefusalCode.tooMuchData, 'more than the file');
        }
      }
    } else if (s.contentLength != null && s.contentLength! > apk.size) {
      throw const UpdateRefusal(UpdateRefusalCode.tooMuchData, 'more than the file');
    }

    final RandomAccessFile out = await staging.partFor(apk).open(mode: FileMode.append);
    int idx = from;
    final BytesBuilder buf = BytesBuilder(copy: false);
    try {
      try {
        await for (final List<int> part in s.body.timeout(stall)) {
          if (cancel?.isCancelled ?? false) throw const UpdateRefusal(UpdateRefusalCode.cancelled);
          List<int> data = part;
          if (skip > 0) {
            if (data.length <= skip) {
              skip -= data.length;
              continue;
            }
            data = data.sublist(skip);
            skip = 0;
          }
          buf.add(data);
          while (idx < apk.chunkCount && buf.length >= apk.chunkLength(idx)) {
            await guard?.call();
            final Uint8List all = buf.takeBytes();
            final int len = apk.chunkLength(idx);
            final Uint8List chunk = Uint8List.sublistView(all, 0, len);
            if (await sha256OfBytes(chunk) != apk.chunks[idx]) {
              throw UpdateRefusal(UpdateRefusalCode.hashMismatch, 'chunk $idx');
            }
            try {
              await out.writeFrom(chunk);
              await out.flush();
            } on FileSystemException {
              throw const UpdateRefusal(UpdateRefusalCode.noSpace, 'could not write the file');
            }
            if (all.length > len) buf.add(Uint8List.sublistView(all, len));
            idx++;
            onProgress?.call(DownloadProgress(_bytesFor(apk, idx), apk.size));
          }
          if (idx >= apk.chunkCount) break; // everything the manifest names has arrived; any more is not read
        }
      } on TimeoutException {
        throw const UpdateRefusal(UpdateRefusalCode.offline, 'the connection stalled');
      } on SocketException {
        throw const UpdateRefusal(UpdateRefusalCode.offline, 'the connection dropped');
      } on HttpException {
        throw const UpdateRefusal(UpdateRefusalCode.offline, 'the connection dropped');
      }
    } finally {
      await out.close();
    }
    if (idx < apk.chunkCount) throw const UpdateRefusal(UpdateRefusalCode.truncated, 'the connection ended early');
    return idx;
  }

  Future<File> _finish(ApkEntry apk) async {
    final File part = staging.partFor(apk);
    if (!await part.exists() || await part.length() != apk.size) {
      await staging.discard(apk);
      throw const UpdateRefusal(UpdateRefusalCode.sizeMismatch, 'the finished file is not the declared size');
    }
    if (await sha256OfFile(part) != apk.sha256) {
      await staging.discard(apk);
      throw const UpdateRefusal(UpdateRefusalCode.hashMismatch, 'whole file');
    }
    final File done = staging.finalFor(apk);
    try {
      if (await done.exists()) await done.delete();
      return await part.rename(done.path);
    } on FileSystemException {
      throw const UpdateRefusal(UpdateRefusalCode.noSpace, 'could not finish the file');
    }
  }

  /// Verifies bytes that arrive some other way (a phone handing the file to a tablet over the family link) the same way
  /// a download does: each chunk against the signed hash before it is kept, then size and the whole-file hash. Nothing
  /// is kept unless all of it checks.
  Future<File> stageFromStream(ApkEntry apk, Stream<List<int>> source, {UpdateCancel? cancel}) async {
    await staging.ensure();
    await staging.sweep();
    final File part = staging.partFor(apk);
    final RandomAccessFile out = await part.open(mode: FileMode.write);
    int idx = 0;
    final BytesBuilder buf = BytesBuilder(copy: false);
    try {
      await for (final List<int> data in source) {
        if (cancel?.isCancelled ?? false) throw const UpdateRefusal(UpdateRefusalCode.cancelled);
        buf.add(data);
        if (buf.length > apk.size + apk.chunkSize) throw const UpdateRefusal(UpdateRefusalCode.tooMuchData);
        while (idx < apk.chunkCount && buf.length >= apk.chunkLength(idx)) {
          final Uint8List all = buf.takeBytes();
          final int len = apk.chunkLength(idx);
          if (await sha256OfBytes(Uint8List.sublistView(all, 0, len)) != apk.chunks[idx]) {
            throw UpdateRefusal(UpdateRefusalCode.hashMismatch, 'chunk $idx');
          }
          await out.writeFrom(all, 0, len);
          if (all.length > len) buf.add(Uint8List.sublistView(all, len));
          idx++;
        }
        if (idx >= apk.chunkCount && buf.length > 0) throw const UpdateRefusal(UpdateRefusalCode.tooMuchData);
      }
      if (idx != apk.chunkCount || buf.length != 0) throw const UpdateRefusal(UpdateRefusalCode.truncated);
      await out.flush();
    } on FileSystemException {
      await out.close();
      await staging.discard(apk);
      throw const UpdateRefusal(UpdateRefusalCode.noSpace, 'could not write the file');
    } catch (_) {
      await out.close();
      await staging.discard(apk);
      rethrow;
    }
    await out.close();
    return _finish(apk);
  }
}
