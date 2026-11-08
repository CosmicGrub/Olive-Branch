// OLIVE BRANCH — a kept room photo is decoded once, not on every rebuild
// (on-device performance pass).
//
// The "new place" walk used to call base64Decode(photo) inside build(). Every
// rebuild (a fold or unfold on the Fold5, a text-scale change, the next-stop
// tap) produced a brand-new byte list, which is a brand-new MemoryImage key:
// the framework dropped the cached bitmap and decoded the JPEG again.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/rhythm_screens.dart';

/// A real 1x1 PNG.
const String png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

class Host extends StatefulWidget {
  const Host({super.key, required this.photo});
  final String photo;
  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  String? swapped;
  int builds = 0;
  void rebuild() => setState(() => builds++);
  void swap(String p) => setState(() => swapped = p);
  @override
  Widget build(BuildContext context) => MaterialApp(
          home: Scaffold(
              body: RoomPhoto(swapped ?? widget.photo,
                  semanticLabel: 'a room', fallback: const Icon(Icons.home_outlined))));
}

void main() {
  setUp(() => RoomPhoto.decodeCount = 0);

  testWidgets('ten parent rebuilds decode the photo once', (WidgetTester t) async {
    await t.pumpWidget(const Host(photo: png1x1));
    final HostState host = t.state(find.byType(Host));
    for (int i = 0; i < 10; i++) {
      host.rebuild();
      await t.pump();
    }
    debugPrint('MEASURED RoomPhoto: base64 decodes over 1 build + 10 rebuilds = ${RoomPhoto.decodeCount} '
        '(before the change: 11, one per build)');
    expect(RoomPhoto.decodeCount, 1);
  });

  testWidgets('the image provider keeps the same bytes across rebuilds (cache hit)', (WidgetTester t) async {
    await t.pumpWidget(const Host(photo: png1x1));
    final Image before = t.widget(find.byType(Image));
    final HostState host = t.state(find.byType(Host));
    host.rebuild();
    await t.pump();
    final Image after = t.widget(find.byType(Image));
    expect(after.image, before.image, reason: 'equal MemoryImage keys: no re-decode');
  });

  testWidgets('a different photo is decoded again', (WidgetTester t) async {
    await t.pumpWidget(const Host(photo: png1x1));
    final HostState host = t.state(find.byType(Host));
    host.swap(base64Encode(<int>[...base64Decode(png1x1), 0]));
    await t.pump();
    expect(RoomPhoto.decodeCount, 2);
  });

  testWidgets('text that is not base64 shows the fallback, never throws', (WidgetTester t) async {
    await t.pumpWidget(const Host(photo: '%%% not base64 %%%'));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });
}
