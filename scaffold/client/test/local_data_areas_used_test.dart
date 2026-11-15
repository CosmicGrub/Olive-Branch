// OLIVE BRANCH — guards against a local data area being used in code without being listed in
// [localDataCatalogue]. Found on a real device: the pairing trust book used the area 'trust', which was never
// registered, so tapping "Connect a child's device" threw '"trust" is not in localDataCatalogue'. The catalogue
// test only compared the catalogue with the spec table, never the code that uses it. This scans every
// `.area('name'` in lib and fails for any name the catalogue does not know.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_services.dart';

void main() {
  test('every local data area used in lib is listed in localDataCatalogue', () {
    final Set<String> listed = <String>{for (final LocalDataEntry e in localDataCatalogue) e.area};
    final RegExp use = RegExp(r"\.area\(\s*'([a-z0-9_.]+)'");
    final Map<String, Set<String>> missing = <String, Set<String>>{};
    int found = 0;
    for (final File f in Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart'))) {
      for (final Match m in use.allMatches(f.readAsStringSync())) {
        found++;
        final String name = m.group(1)!;
        if (!listed.contains(name)) missing.putIfAbsent(name, () => <String>{}).add(f.path);
      }
    }
    expect(found, greaterThan(10), reason: 'the scan found the area calls');
    expect(missing, isEmpty, reason: 'areas used but not in localDataCatalogue: $missing');
  });

  test('the pairing trust book area exists and is sealed on a grown-up device', () {
    final LocalDataEntry e = localDataEntry('trust');
    expect(e.encrypted, isTrue);
    expect(e.scope, LocalScope.guardian);
  });
}
