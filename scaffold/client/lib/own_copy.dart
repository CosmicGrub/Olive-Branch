// OLIVE BRANCH — her own copy, made on this device. UNVERIFIED until CI runs it (client/test/own_copy_test.dart).
// Prototype: mod-child.js buildCopy / kid.takeCopy / k.copy; r3a-18-whatyouget. MASTERFILE §21.2 (rung 17), §21.6.
//
// What it does, for real: reads what THIS device holds for her (the areas in [kOwnCopyAreas]), writes it as ONE
// plain-text JSON file in the documents folder, reads the file back and checks it matches what was written. It does
// not touch the network and tells nobody (rung 17: no one has to say yes, and no one is told).
//
// What is in it and what is not is said in plain words and WITHOUT counts (P1-P11: the child sees no totals):
// [ownCopyIncludes] and [ownCopyExcludes] are the single source for the screen and for the file's own 'notIncluded'.
// The journal is hers and is in her copy; it is never uploaded anywhere (P7 stays as it was).
//
// What her copy can honestly NOT hold today is said too ([ownCopyNotHere]): messages and videos live on the
// server and arrive in a copy only through the connected take-and-go (take_and_go_screen.dart).
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_services.dart';
import 'sha256.dart';

/// The areas that are HERS and go in her copy. Not here, on purpose: the family a grown-up built (not hers to
/// carry off), everything a grown-up wrote for the grown-up side, her feelings weather and worry box (today's
/// weather only and a box that floats away: neither is kept as a record), and every pairing key.
const List<String> kOwnCopyAreas = <String>[
  'journal', 'lists', 'pictures', 'stories', 'jokes', 'lessons', 'collections', 'memorybox', 'teen', 'nicknames',
];

/// In plain words, no numbers.
const List<(String, String)> ownCopyIncludes = <(String, String)>[
  ('Your journal', 'Yours only.'),
  ('Your lists', 'Things you need and things you want.'),
  ('Pictures you kept', 'Drawings and colourings.'),
  ('Your memory box', 'And the notes grown-ups left in it, marked as theirs.'),
  ('Your calendar and free times', 'As you set them.'),
  ('Stories, jokes and what you taught', 'The ones you starred.'),
  ('What you call your grown-ups', 'The names you chose.'),
];

const String ownCopyExcludes =
    'Messages between your parents, anything they wrote about each other, and what they agreed about money. Those are theirs.';

/// Honest about today: what this copy cannot carry because it is not on this device.
const String ownCopyNotHere =
    'Messages and videos you were sent are kept online. They come in a copy only when this tablet can reach the server.';

const String ownCopyForm = 'One plain file you can open in any text editor.';

/// Reads the areas of [services] that belong in her copy. A damaged area is left out, never fatal, and the file says
/// which ones could not be read so the copy never pretends to be whole.
Future<Map<String, Object?>> buildOwnCopy(
  LocalServices services, {
  required String childName,
  required DateTime now,
  String? childId,
}) async {
  final Map<String, Object?> areas = <String, Object?>{};
  final List<String> unread = <String>[];
  for (final String a in kOwnCopyAreas) {
    try {
      final ns = services.area(a, ownerId: childId);
      final Map<String, Object?> doc = <String, Object?>{};
      for (final String k in await ns.list()) {
        doc[k] = await ns.get(k);
      }
      if (doc.isNotEmpty) areas[a] = doc;
    } catch (_) {
      unread.add(a);
    }
  }
  return <String, Object?>{
    'about': 'A copy of what is yours, made on this device. Nobody was told.',
    'madeAt': now.toUtc().toIso8601String(),
    'child': <String, Object?>{'name': childName},
    'areas': areas,
    if (unread.isNotEmpty) 'couldNotRead': unread,
    'notIncluded': ownCopyExcludes,
    'notOnThisDevice': ownCopyNotHere,
  };
}

class OwnCopyResult {
  const OwnCopyResult({required this.path, required this.verified, required this.hash});
  final String path;

  /// The file was read back and its hash equals the hash of what was written.
  final bool verified;
  final String hash;
}

/// Makes the copy and saves it. Throws on a real I/O failure: the caller says so plainly and records nothing.
Future<OwnCopyResult> saveOwnCopy(
  LocalServices services, {
  required String childName,
  required DateTime now,
  String? childId,
  Future<Directory> Function()? documentsDirectory,
}) async {
  final Map<String, Object?> data = await buildOwnCopy(services, childName: childName, now: now, childId: childId);
  final String json = const JsonEncoder.withIndent('  ').convert(data);
  final Directory dir = await (documentsDirectory ?? getApplicationDocumentsDirectory)();
  final String stamp = now.toUtc().millisecondsSinceEpoch.toString();
  final File file = File('${dir.path}${Platform.pathSeparator}olive-my-copy-$stamp.json');
  // Sync: a real async dart:io write hangs under the plain widget-test binding (see deletion_screen.dart).
  file.writeAsStringSync(json);
  final String back = file.readAsStringSync();
  final String want = sha256Hex(json);
  return OwnCopyResult(path: file.path, verified: sha256Hex(back) == want, hash: want);
}
