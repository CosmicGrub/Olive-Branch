// The call UI depends only on the CallProvider interface. MASTERFILE §16.2 #6
// (third reversal). A source-level guard: no call UI file may import a media
// engine or a concrete provider.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uiFiles = ['lib/call_screen.dart', 'lib/call_knock_screen.dart'];
  const forbidden = [
    'package:livekit_client', 'package:jitsi_meet_flutter_sdk',
    'livekit_call_provider.dart', 'jitsi_call_provider.dart',
  ];
  for (final f in uiFiles) {
    test('$f imports no engine and no concrete provider', () {
      final imports = File(f).readAsLinesSync().where((l) => l.trimLeft().startsWith('import '));
      for (final bad in forbidden) {
        expect(imports.where((l) => l.contains(bad)), isEmpty, reason: '$f must not import $bad');
      }
    });
  }
  test('call_screen.dart reaches an engine only through the interface and the registry', () {
    final imports = File('lib/call_screen.dart').readAsLinesSync().where((l) => l.startsWith('import '));
    expect(imports.any((l) => l.contains('call_provider.dart')), true);
    expect(imports.any((l) => l.contains('call_provider_registry.dart')), true);
  });
  test('the interface file is engine-free too', () {
    final imports = File('lib/call_provider.dart').readAsLinesSync().where((l) => l.startsWith('import '));
    for (final bad in forbidden) {
      expect(imports.where((l) => l.contains(bad)), isEmpty);
    }
  });
  test('only the registry names both concrete engines', () {
    final named = Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))
        .where((f) {
      final t = f.readAsStringSync();
      return t.contains("import 'jitsi_call_provider.dart'") && t.contains("import 'livekit_call_provider.dart'");
    }).map((f) => f.uri.pathSegments.last);
    expect(named.toList(), ['call_provider_registry.dart']);
  });
}
