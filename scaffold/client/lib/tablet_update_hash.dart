// OLIVE BRANCH — SHA-256 helpers for the tablet update path: one-shot over bytes, and a streaming one that is fed
// a file chunk by chunk so a 100 MB update is never held in memory. Verified headless
// (test/tablet_update_hash_test.dart, against the two NIST vectors and a multi-chunk file).
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

String _hex(List<int> b) {
  final StringBuffer s = StringBuffer();
  for (final int x in b) {
    s.write(x.toRadixString(16).padLeft(2, '0'));
  }
  return s.toString();
}

/// Lower-case hex SHA-256 of [bytes].
Future<String> sha256HexOf(List<int> bytes) async => _hex((await Sha256().hash(bytes)).bytes);

/// A running SHA-256. [add] chunks in order, then [finish] once.
class RunningSha256 {
  RunningSha256() : _sink = Sha256().newHashSink();
  final HashSink _sink;
  bool _done = false;

  void add(List<int> chunk) {
    if (_done) throw StateError('already finished');
    _sink.add(chunk);
  }

  Future<String> finish() async {
    if (_done) throw StateError('already finished');
    _done = true;
    _sink.close();
    return _hex((await _sink.hash()).bytes);
  }
}

/// The SHA-256 of a whole file, read in [block]-sized pieces.
Future<String> sha256HexOfFile(File f, {int block = 1024 * 1024}) async {
  final RunningSha256 h = RunningSha256();
  final RandomAccessFile raf = await f.open();
  try {
    while (true) {
      final Uint8List b = await raf.read(block);
      if (b.isEmpty) break;
      h.add(b);
    }
  } finally {
    await raf.close();
  }
  return h.finish();
}
