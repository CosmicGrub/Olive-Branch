// PRIVATE BUILD ONLY -- DO NOT SHIP -- see
// scaffold/client/lib/private_storybooks/README.md before ever merging this
// branch anywhere near a release.
//
// The manifest is the only thing a real book touches. Adding one is: drop
// its HTML file next to manifest.json under assets/private_storybooks/, and
// append one entry to the JSON array -- no Dart change, no switch statement,
// no rebuild of this file. private_storybook_shelf.dart and
// private_storybook_reader.dart only ever see [StorybookEntry] values; they
// have no idea how many books exist or what is in them.
library private_storybook_manifest;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One entry on the shelf: a title and short description to show while
/// browsing, plus the asset path of the HTML file the reader should load
/// when it is opened. Nothing here is the story content itself.
class StorybookEntry {
  const StorybookEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.assetPath,
  });

  final String id;
  final String title;
  final String description;
  final String assetPath;

  factory StorybookEntry.fromJson(Map<String, dynamic> json) => StorybookEntry(
    id: json['id'] as String,
    title: json['title'] as String,
    description: (json['description'] as String?) ?? '',
    assetPath: json['assetPath'] as String,
  );
}

/// Default location of the manifest asset -- must match the path registered
/// under `flutter: assets:` in pubspec.yaml.
const String kPrivateStorybookManifestPath =
    'assets/private_storybooks/manifest.json';

/// Loads and parses the manifest asset into a list of [StorybookEntry].
///
/// No silent fallback on a malformed manifest -- a broken JSON file should
/// fail loudly during development, not quietly show an empty shelf.
Future<List<StorybookEntry>> loadPrivateStorybookManifest({
  String manifestPath = kPrivateStorybookManifestPath,
}) async {
  final raw = await rootBundle.loadString(manifestPath);
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = decoded['storybooks'] as List<dynamic>;
  return entries
      .map((e) => StorybookEntry.fromJson(e as Map<String, dynamic>))
      .toList();
}
