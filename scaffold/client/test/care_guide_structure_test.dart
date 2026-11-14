// Source-level guards for the care guides. UNVERIFIED until CI runs it.
//
//  * No child-side file or screen can reach the guides (child-first rule, MASTERFILE §2.1 and §5.23.2).
//  * Nothing in lib/ turns the draft preview on.
//  * No parent-facing string the app itself writes contains reviewer vocabulary, and no phone number is written in code:
//    numbers come from guide data only.
//  * The emergency-first order is fixed in code.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_guide_loader.dart';
import 'package:olive_client/care_guide_models.dart';
import 'package:olive_client/care_guide_screens.dart';

import 'care_guide_fixtures.dart';

List<File> _lib() => Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
String _name(File f) => f.uri.pathSegments.last;

/// String literals of a Dart source file (single and double quoted, one line), good enough for a guard.
Iterable<String> _literals(String src) sync* {
  for (final RegExpMatch m in RegExp(r'''(?:'((?:\\.|[^'\\\n])*)'|"((?:\\.|[^"\\\n])*)")''').allMatches(src)) {
    yield m.group(1) ?? m.group(2) ?? '';
  }
}

void main() {
  const Set<String> careFiles = <String>{
    'care_guide_models.dart', 'care_guide_gate.dart', 'care_guide_loader.dart', 'care_guide_plan.dart', 'care_guide_screens.dart',
  };

  group('no child-side file reaches the guides', () {
    test('only the care_guide files and the guardian hub mention care guides in lib/', () {
      final List<String> users = <String>[
        for (final File f in _lib())
          if (!careFiles.contains(_name(f)) && RegExp(r'care_guide|CareGuide|careGuide').hasMatch(f.readAsStringSync())) _name(f),
      ];
      expect(users, <String>['guardian_more.dart']);
    });

    test('guardian_more.dart imports only the hub tile, nothing else from the guides', () {
      final String src = File('lib/guardian_more.dart').readAsStringSync();
      final Iterable<RegExpMatch> imports = RegExp(r"import 'care_guide[^']*'[^;]*;").allMatches(src);
      expect(imports.map((RegExpMatch m) => m.group(0)).toList(), <String>["import 'care_guide_screens.dart' show CareGuidesHubTile;"]);
    });

    test('no child shell file (child_*, kiosk, games, play, call, storyteller, reading, kid) imports a care_guide file', () {
      final RegExp childish = RegExp(r'^(child|kiosk|games?|play|call|story|read|kid|colour|colour_of|her_colour|olive_art|ad_hoc|local_play)');
      for (final File f in _lib()) {
        if (!childish.hasMatch(_name(f))) continue;
        expect(RegExp(r"import\s+'[^']*care_guide").hasMatch(f.readAsStringSync()), false, reason: '${_name(f)} must not import care guides');
      }
    });

    test('the guide screens refuse a non-guardian role and show no content', () {
      final String src = File('lib/care_guide_screens.dart').readAsStringSync();
      // every public screen takes a principalRole and returns _GuardiansOnly for anything else
      final int screens = RegExp(r'class (CareGuideLibraryScreen|CareGuideScreen|WhoToCallScreen|NewCarerStartScreen|HelperPageSelectionScreen)\b').allMatches(src).length;
      expect(screens, 5);
      expect('principalRole != _guardianRole'.allMatches(src).length, greaterThanOrEqualTo(5));
    });
  });

  group('the draft preview is never switched on from code', () {
    test('only care_guide_gate.dart mentions the switch, and it defaults to false', () {
      final List<String> users = <String>[for (final File f in _lib()) if (f.readAsStringSync().contains('careGuidesDraftPreview')) _name(f)];
      expect(users, <String>['care_guide_gate.dart']);
      expect(RegExp(r'bool careGuidesDraftPreview = false;').hasMatch(File('lib/care_guide_gate.dart').readAsStringSync()), true);
    });

    test('no lib file builds a policy with draftPreview: true', () {
      for (final File f in _lib()) {
        expect(RegExp(r'draftPreview\s*:\s*true').hasMatch(f.readAsStringSync()), false, reason: _name(f));
      }
    });

    test('the hub tile and the library use the policy through CareGuidePolicy.current() only', () {
      expect(File('lib/care_guide_screens.dart').readAsStringSync().contains('CareGuidePolicy.current()'), true);
    });
  });

  group('words and numbers the app itself writes', () {
    final List<File> files = <File>[for (final String n in <String>['care_guide_screens.dart', 'care_guide_plan.dart', 'care_guide_loader.dart', 'care_guide_models.dart']) File('lib/$n')];

    test('no string literal contains reviewer vocabulary', () {
      final List<RegExp> bad = <RegExp>[
        RegExp('clinician', caseSensitive: false),
        RegExp(r'\bsources?\s*\d', caseSensitive: false),
        RegExp(r'\bdisagreements?\s*\d', caseSensitive: false),
        RegExp('unverified', caseSensitive: false),
      ];
      for (final File f in files) {
        for (final String s in _literals(f.readAsStringSync())) {
          for (final RegExp r in bad) {
            expect(r.hasMatch(s), false, reason: '${_name(f)}: "$s"');
          }
        }
      }
    });

    test('no string literal contains a phone-number-like digit run', () {
      for (final File f in files) {
        for (final String s in _literals(f.readAsStringSync())) {
          final String noInterpolation = s.replaceAll(RegExp(r'\$\{[^}]*\}'), '');
          expect(RegExp(r'\d{3,}').hasMatch(noInterpolation), false, reason: '${_name(f)}: "$s"');
        }
      }
    });

    test('no dial or launch plumbing: the app never places a call from a guide', () {
      for (final File f in files) {
        final String src = f.readAsStringSync();
        expect(src.contains('tel:'), false, reason: _name(f));
        expect(src.contains('url_launcher'), false, reason: _name(f));
      }
    });
  });

  group('no draft medical text ships in the app', () {
    final Directory assets = Directory('assets/care_guides');
    final List<File> bundled = assets.listSync().whereType<File>().where((File f) => f.path.endsWith('.json')).toList();

    test('the pubspec bundles assets/care_guides/ and nothing under docs/ (where the drafts live)', () {
      final String p = File('pubspec.yaml').readAsStringSync();
      expect(p.contains('- assets/care_guides/'), true);
      expect(p.contains('care-guides'), false);
      expect(p.contains('app-draft'), false);
    });

    test('every guide file in the bundled directory is REVIEWED with a complete record, and the index lists exactly those', () {
      final List<String> listed = <String>[];
      for (final File f in bundled) {
        if (_name(f) == 'index.json') continue;
        final Map<String, Object?> m = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
        expect(m['status'], 'REVIEWED', reason: '${_name(f)} must not ship unless a clinician has reviewed it');
        final Map<String, Object?> r = m['review']! as Map<String, Object?>;
        expect(r['reviewedOn'], isNotNull, reason: _name(f));
        expect((r['reviewedBy'] as String? ?? '').trim(), isNotEmpty, reason: _name(f));
        listed.add(_name(f).replaceAll('.json', ''));
      }
      final Map<String, Object?> idx = jsonDecode(File('assets/care_guides/index.json').readAsStringSync()) as Map<String, Object?>;
      expect((idx['guides']! as List<Object?>).cast<String>().toList()..sort(), listed..sort());
    });

    test('no bundled file contains the draft status word or the draft disclaimer', () {
      for (final File f in bundled) {
        final String s = f.readAsStringSync();
        expect(s.contains('DRAFT'), false, reason: _name(f));
        expect(s.contains('Needs review'), false, reason: _name(f));
      }
    });

    test('the five real drafts are kept outside the app, in docs/care-guides/app-draft', () {
      for (final String id in <String>['who-to-call', 'choking', 'head-injury', 'high-fever', 'childproofing-home']) {
        expect(File('$kDraftDir/$id.json').existsSync(), true, reason: id);
        expect(File('assets/care_guides/$id.json').existsSync(), false, reason: '$id must not be bundled while it is a draft');
      }
    });
  });

  group('the app-written headings', () {
    test('every block kind has a heading, and every heading is listed for sign-off with its kind', () {
      final String doc = File('../../docs/care-guides/HEADING-SIGNOFF.md').readAsStringSync();
      for (final String k in kBlockOrder) {
        if (k == 'room') continue; // the heading is the draft's own room name
        expect(kBlockHeadings.containsKey(k), true, reason: k);
        expect(doc.contains('| `$k` | ${kBlockHeadings[k]} |'), true, reason: 'HEADING-SIGNOFF.md lacks "$k": "${kBlockHeadings[k]}"');
      }
    });

    test('the post-episode and urgent headings add no timeframe, actor or place to the draft content', () {
      for (final String k in <String>['afterEpisode', 'urgent']) {
        final String h = kBlockHeadings[k]!.toLowerCase();
        for (final String w in <String>['doctor', 'hospital', 'day', 'hour', 'now', 'minute', 'call']) {
          expect(h.contains(w), false, reason: '"$h" for $k contains "$w"');
        }
      }
      expect(kBlockHeadings['afterEpisode'], isNot('Same-day doctor'));
    });
  });

  group('emergency first', () {
    test('the fixed block order starts with the emergency block, then the other call tiers', () {
      expect(kBlockOrder.take(5).toList(), <String>['emergency', 'urgent', 'poison', 'nurseLine', 'sameDay']);
    });

    test('every bundled guide that has an emergency block shows it first, whatever order it is stored in', () {
      for (final String id in <String>['who-to-call', 'choking', 'head-injury', 'high-fever', 'childproofing-home']) {
        final CareGuide g = CareGuide.fromJson(jsonDecode(File('$kDraftDir/$id.json').readAsStringSync()) as Map<String, Object?>);
        if (g.blocks.any((CareBlock b) => b.kind == 'emergency')) {
          expect(g.orderedBlocks.first.kind, 'emergency', reason: id);
        }
      }
    });

    test('a guide stored with the emergency block last still shows it first', () {
      final CareGuide g = fixtureCareGuide(); // fixture stores doNow before emergency
      expect(g.blocks.first.kind, 'doNow');
      expect(g.orderedBlocks.first.kind, 'emergency');
    });

    test('the library lists the emergency entry first, even when no guide is available', () {
      expect(libraryEntries(CareGuideLibrary.empty).first.isEmergency, true);
    });
  });
}

