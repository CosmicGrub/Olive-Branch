// OLIVE BRANCH — the guided first run's script table and docs/planning/ONBOARDING-SCRIPT.md cannot drift. A snapshot test:
// every entry's id, slot, version, kind, strip position, what is seen, title, words, icon labels and action must be in the
// document exactly, every document row must be in the table, and the fixed words, anchors, slots and script version
// match. Verified by CI, headless. MASTERFILE §8.5.14.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home_bands.dart';
import 'package:olive_client/guided_registry.dart';
import 'package:olive_client/guided_script.dart';

String _doc() => File('../../docs/planning/ONBOARDING-SCRIPT.md').readAsStringSync().replaceAll('\r\n', '\n');

/// The rows of the two entry tables (eleven cells), by id.
Map<String, List<String>> _entryRows(String doc) {
  final Map<String, List<String>> out = <String, List<String>>{};
  for (final String line in doc.split('\n')) {
    if (!line.startsWith('| `')) continue;
    final List<String> cells = line.substring(2, line.length - 2).split(' | ').map((String c) => c.trim()).toList();
    if (cells.length != 11) continue;
    out[cells[0].replaceAll('`', '')] = cells;
  }
  return out;
}

String _labels(GuidedEntry e) =>
    e.labels.isEmpty ? '-' : e.labels.map((GuidedLabel l) => '${l.label} = ${l.line}').join(' ; ');

void main() {
  final String doc = _doc();
  final Map<String, List<String>> rows = _entryRows(doc);
  final List<GuidedEntry> adult = resolveGuidedEntries(half: GuidedHalf.adult);
  // The "And there is more" card only resolves with labels registered; the base list has it.
  final List<GuidedEntry> childAll = kBaseGuidedEntries.where((GuidedEntry e) => e.half == GuidedHalf.child).toList();

  test('the document names the same script version as the code', () {
    expect(doc, contains('Script version: **$kGuidedScriptVersion**'));
  });

  test('every entry in the table is in the document, word for word', () {
    for (final GuidedEntry e in kBaseGuidedEntries) {
      final List<String>? c = rows[e.id];
      expect(c, isNotNull, reason: '${e.id} has no row in ONBOARDING-SCRIPT.md');
      expect(c![1], e.slot, reason: '${e.id} slot');
      expect(c[2], '${e.since}', reason: '${e.id} version');
      expect(c[3], e.kind.word, reason: '${e.id} kind');
      expect(c[4], e.needsFeature ?? '-', reason: '${e.id} needs');
      expect(c[6], e.sees, reason: '${e.id} sees');
      expect(c[7], e.title, reason: '${e.id} title');
      expect(c[8], e.words, reason: '${e.id} words');
      expect(c[10], e.action, reason: '${e.id} action');
      if (e.id == 'c.extra') {
        expect(c[9], '(the labels that newer features registered)');
      } else {
        expect(c[9], _labels(e), reason: '${e.id} icon labels');
      }
    }
  });

  test('the strip position in the document is the one the code computes', () {
    for (int i = 0; i < adult.length; i++) {
      final ({int step, int of}) s = guidedStrip(adult, i);
      expect(rows[adult[i].id]![5], '${s.step} of ${s.of}', reason: adult[i].id);
    }
    for (final GuidedEntry e in childAll) {
      expect(rows[e.id]![5], 'none', reason: e.id);
    }
  });

  test('every row in the document is in the table: nothing documented that does not ship', () {
    final Set<String> code = kBaseGuidedEntries.map((GuidedEntry e) => e.id).toSet();
    expect(rows.keys.toSet(), code);
  });

  test('her icon labels are the titles on her own home (the same table, so they cannot differ)', () {
    final Map<String, String> byTitle = <String, String>{for (final BandTile b in kBandTiles.values) b.title: b.id};
    for (final String id in <String>['c.day', 'c.messages', 'c.stories', 'c.colour', 'c.more']) {
      for (final GuidedLabel l in childAll.firstWhere((GuidedEntry e) => e.id == id).labels) {
        expect(byTitle.containsKey(l.label), isTrue, reason: '"${l.label}" is not a tile title on her home');
      }
    }
  });

  test('the slot list in the document is the one in the code, in order', () {
    final List<String> docSlots = <String>[];
    for (final String line in doc.split('\n')) {
      final RegExpMatch? m = RegExp(r'^\| ((?:adult|child)\.[a-z.]+) \| (?:adult|child) \|').firstMatch(line);
      if (m != null) docSlots.add(m.group(1)!);
    }
    expect(docSlots, kGuidedSlots);
  });

  test('the tour anchors in the document are the ones the entries point at', () {
    final Set<String> docAnchors = RegExp(r'^\| `(home\.[A-Za-z]+)` \|', multiLine: true)
        .allMatches(doc)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();
    final Set<String> code = kBaseGuidedEntries.map((GuidedEntry e) => e.anchor).whereType<String>().toSet();
    expect(docAnchors, code);
  });

  test('the fixed screens\' words are in the document', () {
    String fill(String s) => s;
    expect(doc, contains('${GuidedWords.pauseTitle} ${GuidedWords.pauseBody} (button: ${GuidedWords.pauseButton})'));
    for (int i = 0; i < GuidedWords.tabletSteps.length; i++) {
      expect(doc, contains('| `x.tablet.step.${i + 1}` | helper strip, step ${i + 1} | ${GuidedWords.tabletSteps[i]} |'));
    }
    for (final String w in <String>[
      GuidedWords.tabletWait,
      GuidedWords.tabletRecover,
      GuidedWords.tabletDone,
      GuidedWords.tourNoFind,
      GuidedWords.later,
      GuidedWords.tryMessages,
      GuidedWords.tryColour,
    ]) {
      expect(doc, contains(fill(w)), reason: w);
    }
  });

  test('the extension procedure is documented as three numbered steps', () {
    final String tail = doc.substring(doc.indexOf('## Extending the script'));
    expect(RegExp(r'^1\. \*\*', multiLine: true).hasMatch(tail), isTrue);
    expect(RegExp(r'^2\. \*\*', multiLine: true).hasMatch(tail), isTrue);
    expect(RegExp(r'^3\. \*\*', multiLine: true).hasMatch(tail), isTrue);
    expect(RegExp(r'^4\. \*\*', multiLine: true).hasMatch(tail), isFalse);
  });

  test('the words are plain: no jargon a grandparent would stumble on, nothing blaming', () {
    for (final GuidedEntry e in kBaseGuidedEntries.where((GuidedEntry x) => x.half == GuidedHalf.adult)) {
      final String all = '${e.title} ${e.words} ${e.labels.map((GuidedLabel l) => '${l.label} ${l.line}').join(' ')}'.toLowerCase();
      for (final String bad in <String>['sync', 'server', 'sign in', 'sign-in', 'token', 'must', 'wrong', 'failed', 'error', 'invalid', 'required']) {
        expect(all, isNot(contains(bad)), reason: '${e.id} says "$bad"');
      }
    }
  });
}
