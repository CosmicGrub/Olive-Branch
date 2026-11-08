// OLIVE BRANCH — role_picker_screen.dart tests: "Who is using this device?", Step 0. No longer
// UNVERIFIED — verified by CI. MASTERFILE §8.5.8.
//
// Drives the real widget: three big picture choices (Kid, Mom, Dad) and a smaller "Someone else",
// picture-first, 64dp targets, read-aloud on request, no pressure.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_settings.dart' show kChildTarget;
import 'package:olive_client/device_role.dart';
import 'package:olive_client/read_aloud.dart';
import 'package:olive_client/role_picker_screen.dart';

class _FakeVoice implements ReadAloudEngine {
  final List<String> said = <String>[];
  int stops = 0;
  @override
  Future<void> speak(String text) async => said.add(text);
  @override
  Future<void> stop() async => stops++;
}

void main() {
  Future<List<DeviceRole>> pump(WidgetTester tester, {ReadAloudController? voice, Size size = const Size(800, 1600), DeviceRole? initial}) async {
    final List<DeviceRole> picked = <DeviceRole>[];
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget home = RolePickerScreen(onPicked: picked.add, initial: initial);
    if (voice != null) home = ReadAloudScope(controller: voice, child: home);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('it asks the question in plain words and offers all four roles', (tester) async {
    await pump(tester);
    expect(find.text('Who is using this device?'), findsOneWidget);
    expect(find.text('Kid'), findsOneWidget);
    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('Dad'), findsOneWidget);
    expect(find.text('Someone else'), findsOneWidget);
    expect(find.text('A grandparent or another grown-up'), findsOneWidget);
  });

  group('every role routes to the caller, once, only after "That\'s me"', () {
    for (final DeviceRole r in DeviceRole.values) {
      testWidgets('${r.title} -> onPicked(${r.wire})', (tester) async {
        final List<DeviceRole> picked = await pump(tester);
        await tester.tap(find.byKey(Key('role_${r.wire}')));
        await tester.pump();
        expect(picked, isEmpty, reason: 'highlighting is not committing: a small finger can mis-tap');
        await tester.tap(find.text("That's me"));
        await tester.pumpAndSettle();
        expect(picked, <DeviceRole>[r]);
      });
    }
  });

  testWidgets('"That\'s me" does nothing until a face is chosen, and a second choice replaces the first', (tester) async {
    final List<DeviceRole> picked = await pump(tester);
    await tester.tap(find.text("That's me"), warnIfMissed: false);
    await tester.pump();
    expect(picked, isEmpty);
    await tester.tap(find.byKey(const Key('role_kid')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('role_dad')));
    await tester.pump();
    await tester.tap(find.text("That's me"));
    await tester.pumpAndSettle();
    expect(picked, <DeviceRole>[DeviceRole.dad]);
  });

  testWidgets('a pre-highlighted choice can be confirmed straight away', (tester) async {
    final List<DeviceRole> picked = await pump(tester, initial: DeviceRole.mom);
    await tester.tap(find.text("That's me"));
    await tester.pumpAndSettle();
    expect(picked, <DeviceRole>[DeviceRole.mom]);
  });

  testWidgets('picture-first: each face carries an icon, and every target is at least 64dp', (tester) async {
    await pump(tester);
    for (final DeviceRole r in DeviceRole.values) {
      final Finder tile = find.byKey(Key('role_${r.wire}'));
      expect(find.descendant(of: tile, matching: find.byType(Icon)), findsOneWidget, reason: r.name);
      final Size s = tester.getSize(tile);
      expect(s.height, greaterThanOrEqualTo(kChildTarget), reason: '${r.name} height');
      expect(s.width, greaterThanOrEqualTo(kChildTarget), reason: '${r.name} width');
    }
    final Size cont = tester.getSize(find.widgetWithText(FilledButton, "That's me"));
    expect(cont.height, greaterThanOrEqualTo(kChildTarget));
  });

  testWidgets('Kid, Mom and Dad are the big three; Someone else is the smaller fourth', (tester) async {
    await pump(tester);
    final Size kid = tester.getSize(find.byKey(const Key('role_kid')));
    final Size mom = tester.getSize(find.byKey(const Key('role_mom')));
    final Size dad = tester.getSize(find.byKey(const Key('role_dad')));
    final Size other = tester.getSize(find.byKey(const Key('role_other')));
    expect(kid.height, greaterThan(other.height));
    expect(mom.height, greaterThan(other.height));
    expect(dad.height, greaterThan(other.height));
    expect(tester.getTopLeft(find.byKey(const Key('role_other'))).dy,
        greaterThan(tester.getBottomLeft(find.byKey(const Key('role_kid'))).dy),
        reason: 'the fourth sits below the three');
  });

  testWidgets('no pressure: no step counter, no timer, no score on the screen', (tester) async {
    await pump(tester);
    final String all = tester.widgetList<Text>(find.byType(Text)).map((Text t) => t.data ?? '').join(' ').toLowerCase();
    for (final String bad in <String>['step ', ' of ', 'hurry', 'quick', 'seconds', 'score', 'points']) {
      expect(all, isNot(contains(bad)), reason: bad);
    }
  });

  testWidgets('it fits a narrow phone and a Fold cover screen without overflow, even at 2x text', (tester) async {
    for (final Size size in <Size>[const Size(344, 760), const Size(390, 844)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: const TextScaler.linear(2.0)),
          child: RolePickerScreen(onPicked: (_) {}),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.byKey(const Key('role_other')), findsOneWidget);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  group('read aloud, on request only', () {
    testWidgets('the speaker reads the question and every choice; nothing is spoken by itself', (tester) async {
      final _FakeVoice engine = _FakeVoice();
      final ReadAloudController voice = ReadAloudController(engine: engine);
      await pump(tester, voice: voice);
      expect(engine.said, isEmpty, reason: 'speech starts only from a tap or a long-press');
      await tester.tap(find.byKey(const Key('roleSpeaker')));
      await tester.pump();
      expect(engine.said.single, allOf(contains('Who is using this device?'), contains('Kid'), contains('Mom'),
          contains('Dad'), contains('someone else')));
      expect(tester.getSize(find.byKey(const Key('roleSpeaker'))).height, greaterThanOrEqualTo(kChildTarget));
    });

    testWidgets('long-pressing a face says its word', (tester) async {
      final _FakeVoice engine = _FakeVoice();
      await pump(tester, voice: ReadAloudController(engine: engine));
      await tester.longPress(find.byKey(const Key('role_mom')));
      await tester.pump();
      expect(engine.said, <String>['Mom']);
      await tester.longPress(find.byKey(const Key('role_other')));
      await tester.pump();
      expect(engine.said.last, contains('Someone else'));
    });

    testWidgets('with no read-aloud scope there is simply no speaker', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('roleSpeaker')), findsNothing);
    });

    testWidgets('a long-press does not choose', (tester) async {
      final List<DeviceRole> picked = await pump(tester, voice: ReadAloudController(engine: _FakeVoice()));
      await tester.longPress(find.byKey(const Key('role_dad')));
      await tester.pump();
      await tester.tap(find.text("That's me"), warnIfMissed: false);
      await tester.pump();
      expect(picked, isEmpty);
    });
  });

  testWidgets('the screen is reachable by screen reader: each choice is a labelled, selectable button', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, initial: DeviceRole.dad);
    expect(find.bySemanticsLabel('Kid'), findsOneWidget);
    expect(find.bySemanticsLabel('Dad'), findsOneWidget);
    expect(find.bySemanticsLabel('Someone else, like a grandparent or another grown-up'), findsOneWidget);
    handle.dispose();
  });
}
