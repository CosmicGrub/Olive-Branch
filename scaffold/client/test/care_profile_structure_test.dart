// OLIVE BRANCH — the care profile's structure: the child NEVER sees it, because no child-side file reaches the
// profile files, her app cannot name its areas, and the profile's screens are the guardian shell only. Same
// technique as journal_lock_test.dart and child_no_settings_contract_test.dart: read the real sources (comments
// stripped), not a rendered tree, so a regression cannot hide behind an age gate. UNVERIFIED until CI runs this
// file. MASTERFILE section 8.24.8, section 2.1 (P1 to P11), section 5.23.2.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_profile_logic.dart';

const List<String> _profileFiles = <String>['care_profile_logic.dart', 'care_profile_store.dart', 'care_profile_screens.dart'];

String _code(String path) =>
    File(path).readAsLinesSync().where((String l) => !l.trimLeft().startsWith('//')).join('\n');

/// lib/*.dart file name -> the lib files it imports (relative imports only; the client uses nothing else).
Map<String, Set<String>> _graph() {
  final RegExp imp = RegExp(r"^\s*(?:import|export)\s+'([^':]+\.dart)'", multiLine: true);
  final Map<String, Set<String>> g = <String, Set<String>>{};
  for (final File f in Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart'))) {
    final String name = f.uri.pathSegments.last;
    g[name] = <String>{
      for (final RegExpMatch m in imp.allMatches(_code(f.path)))
        if (!m.group(1)!.contains('/')) m.group(1)!,
    };
  }
  return g;
}

Set<String> _reach(Map<String, Set<String>> g, Iterable<String> roots) {
  final Set<String> seen = <String>{};
  final List<String> todo = <String>[...roots];
  while (todo.isNotEmpty) {
    final String n = todo.removeLast();
    if (!seen.add(n)) continue;
    todo.addAll(g[n] ?? const <String>{});
  }
  return seen;
}

bool _childSide(String name) =>
    RegExp(r'^(child_|kid_|journal_|my_marks|her_colour_home|her_colour_art|kiosk_)').hasMatch(name);

void main() {
  final Map<String, Set<String>> g = _graph();

  test('the profile files exist and the graph was read', () {
    for (final String f in _profileFiles) {
      expect(g.containsKey(f), isTrue, reason: f);
    }
    expect(g.length, greaterThan(100));
  });

  test('only the guardian shell (guardian_more.dart) imports the profile; nothing on her side does', () {
    final Set<String> importers = <String>{
      for (final MapEntry<String, Set<String>> e in g.entries)
        if (e.value.any(_profileFiles.contains) && !_profileFiles.contains(e.key)) e.key,
    };
    expect(importers, <String>{'guardian_more.dart'}, reason: 'a new importer must be a guardian-shell file: review it, then add it here');
  });

  test('no child-side file reaches the profile, directly or through anything it imports', () {
    final Iterable<String> roots = g.keys.where(_childSide);
    expect(roots, isNotEmpty);
    final Set<String> reach = _reach(g, roots);
    for (final String f in _profileFiles) {
      expect(reach.contains(f), isFalse, reason: '$f is reachable from her side');
    }
    expect(reach.contains('guardian_more.dart'), isFalse, reason: 'her side must not reach the guardian shell that opens the profile');
  });

  test('her side cannot even name the profile: no file of hers mentions its types, files or areas', () {
    for (final String name in g.keys.where(_childSide)) {
      final String src = _code('lib/$name');
      for (final String banned in <String>['care_profile', 'CareProfile', 'CarePlanPhoto', 'aboutchild', 'aboutplans', 'CpEntry', 'cpEntriesOf']) {
        expect(src.contains(banned), isFalse, reason: '$name mentions $banned');
      }
    }
  });

  test('the areas are named only by the store, the catalogue and the wipe screen', () {
    final Set<String> files = <String>{
      for (final File f in Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')))
        if (RegExp(r'''['"](aboutchild|aboutplans)['"]''').hasMatch(_code(f.path))) f.uri.pathSegments.last,
    };
    expect(files, <String>{'care_profile_store.dart', 'local_services.dart', 'clear_local_data_screen.dart'});
  });

  test('the profile screens are the guardian shell: they import no child screen and no pairing file', () {
    for (final String f in _profileFiles) {
      for (final String dep in g[f]!) {
        expect(_childSide(dep), isFalse, reason: '$f imports $dep');
        expect(RegExp(r'pair|connect_child|unlock_child|device_keys').hasMatch(dep), isFalse, reason: '$f imports $dep');
      }
    }
  });

  test('every screen that shows the profile refuses a non-guardian before reading anything', () {
    final String src = _code('lib/care_profile_screens.dart');
    final int screens = RegExp(r'class CareProfile\w+Screen extends StatefulWidget').allMatches(src).length;
    final int gates = RegExp(r'canEditStructure\(widget\.principal\)').allMatches(src).length;
    expect(screens, greaterThanOrEqualTo(5));
    // The hub, the part, sharing, show-as, the plans and the sheet each check; the teen preview is handed a document by the hub.
    expect(gates, greaterThanOrEqualTo(screens - 1));
    expect(src.contains('CareProfileNotForYou'), isTrue);
  });

  test('it makes no network call and is in no export', () {
    for (final String f in _profileFiles) {
      final String src = _code('lib/$f');
      // dart:io is allowed only as `show File` (the screens delete the picker's temporary copy); HttpClient and
      // WebSocket stay banned by name below, so the network door is still shut.
      expect(RegExp(r"dart:io'(?! show File;)").hasMatch(src), isFalse, reason: '$f imports dart:io beyond File');
      for (final String banned in <String>['package:http', 'api_client', 'HttpClient', 'WebSocket', 'court_export', 'computeEntryHash', 'appendEntry', 'verifyChain']) {
        expect(src.contains(banned), isFalse, reason: '$f uses $banned');
      }
    }
    for (final File f in Directory('lib').listSync().whereType<File>().where((File f) => RegExp(r'court_export|export_').hasMatch(f.path))) {
      final String src = _code(f.path);
      expect(src.contains('care_profile'), isFalse, reason: f.path);
      expect(src.contains('aboutchild'), isFalse, reason: f.path);
    }
  });

  test('the edit history is not an evidence log: no hash, chain or signature in the stored form', () {
    for (final String f in <String>['care_profile_logic.dart', 'care_profile_store.dart']) {
      final String src = _code('lib/$f').toLowerCase();
      for (final String banned in <String>['sha256(', 'hmac', 'prevhash', 'chain']) {
        expect(src.contains(banned), isFalse, reason: '$f: $banned');
      }
    }
  });

  test('a photo of a plan only ever comes from a grown-up\'s own choice: the store has no camera or picker, the screens one door', () {
    expect(_code('lib/care_profile_store.dart').contains('image_picker'), isFalse);
    expect(_code('lib/care_profile_logic.dart').contains('image_picker'), isFalse);
    final String screens = _code('lib/care_profile_screens.dart');
    expect(RegExp(r'ImagePicker\(\)').allMatches(screens).length, 1);
    expect(screens.contains('ImageSource.camera'), isFalse);
    expect(screens.contains('pickPlanPhoto'), isTrue);
  });

  test('the app writes no medical advice and no dose: no unit-bearing number, no instruction verb phrases in what it ships', () {
    for (final String f in _profileFiles) {
      final String src = _code('lib/$f');
      expect(RegExp(r'\b\d+(\.\d+)?\s?(mg|mcg|ml|iu|units?)\b', caseSensitive: false).hasMatch(src), isFalse, reason: f);
      for (final String banned in <String>['recommended dose', 'should take', 'give her ', 'call 911', 'emergency number', 'treat with']) {
        expect(src.toLowerCase().contains(banned), isFalse, reason: '$f: $banned');
      }
    }
  });

  test('the child is invisible to every part, by function', () {
    for (final CareProfilePart p in CareProfilePart.values) {
      expect(careProfileVisibleToChild(p), isFalse);
    }
  });
}
