// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — read-aloud
// policy: never autonomous, stops with the screen, quiet when unavailable,
// switched off by the guardian. MASTERFILE §8.8.5, §8.13.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/a11y_speech.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/read_aloud.dart';
import 'package:olive_client/tiered_tile.dart';

class FakeEngine implements ReadAloudEngine {
  final List<String> spoken = <String>[];
  int stops = 0;
  bool throwOnSpeak = false;
  @override
  Future<void> speak(String text) async {
    if (throwOnSpeak) throw StateError('no voice installed');
    spoken.add(text);
  }

  @override
  Future<void> stop() async => stops++;
}

Widget host(Widget child,
        {ReadAloudController? ra, AccessController? access, List<NavigatorObserver> observers = const []}) =>
    MaterialApp(
      navigatorObservers: observers,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
      home: AccessScope(
        controller: access ?? AccessController(repository: MemoryAccessRepository()),
        child: ra == null
            ? Scaffold(body: child)
            : ReadAloudScope(controller: ra, child: Scaffold(body: child)),
      ),
    );

Future<AccessController> loaded(AccessSettings s, {int? age}) async {
  final AccessController c = AccessController(repository: MemoryAccessRepository(s), ageYears: age);
  await c.load();
  return c;
}

void main() {
  group('ReadAloudController', () {
    test('speaks on a tap', () async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController c = ReadAloudController(engine: e);
      expect(await c.speak('Hello'), isTrue);
      expect(e.spoken, <String>['Hello']);
    });

    test('NEVER autonomous: an autonomous trigger is refused and nothing is spoken', () async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController c = ReadAloudController(engine: e);
      expect(await c.speak('Hello', trigger: SpeechTrigger.autonomous), isFalse);
      expect(e.spoken, isEmpty);
    });

    test('empty text is not spoken', () async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController c = ReadAloudController(engine: e);
      expect(await c.speak('   '), isFalse);
      expect(e.spoken, isEmpty);
    });

    test('with no engine it is unavailable and speak is a quiet false, never a throw', () async {
      final ReadAloudController c = ReadAloudController();
      expect(c.available, isFalse);
      expect(await c.speak('Hello'), isFalse);
    });

    test('an engine that fails makes it unavailable and does not throw or keep an owner', () async {
      final FakeEngine e = FakeEngine()..throwOnSpeak = true;
      final ReadAloudController c = ReadAloudController(engine: e);
      expect(c.available, isTrue);
      expect(await c.speak('Hello', owner: 'x'), isFalse);
      expect(c.available, isFalse);
      expect(c.speakingOwner, isNull);
    });

    test('a replacement engine makes it available again', () async {
      final ReadAloudController c = ReadAloudController(engine: FakeEngine()..throwOnSpeak = true);
      await c.speak('x');
      expect(c.available, isFalse);
      c.engine = FakeEngine();
      expect(c.available, isTrue);
    });

    test('release stops only the owner that is speaking', () async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController c = ReadAloudController(engine: e);
      final Object a = Object(), b = Object();
      await c.speak('one', owner: a);
      await c.release(b);
      expect(e.stops, 0);
      expect(c.isSpeaking(a), isTrue);
      await c.release(a);
      expect(e.stops, 1);
      expect(c.speakingOwner, isNull);
    });
  });

  group('SpeakerButton', () {
    testWidgets('is at least 48dp, and speaks its text on a tap only', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'The fox sat down.')), ra: ra));
      await t.pump();
      expect(e.spoken, isEmpty, reason: 'speech never starts by itself');
      final Size size = t.getSize(find.descendant(of: find.byType(SpeakerButton), matching: find.byType(SizedBox)).first);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(e.spoken, <String>['The fox sat down.']);
    });

    testWidgets('a second tap while speaking stops it', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Hi')), ra: ra));
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(e.stops, 1);
      expect(e.spoken, <String>['Hi']);
    });

    testWidgets('speech stops when the screen closes (the button leaves the tree)', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Hi')), ra: ra));
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(ra.speakingOwner, isNotNull);
      await t.pumpWidget(host(const SizedBox(), ra: ra));
      await t.pump();
      expect(e.stops, greaterThanOrEqualTo(1));
      expect(ra.speakingOwner, isNull);
    });

    testWidgets('turning the story page stops the old page\'s reading', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Page one.')), ra: ra));
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Page two.')), ra: ra));
      await t.pump();
      expect(e.stops, 1);
      expect(e.spoken, <String>['Page one.'], reason: 'the new page waits for her to ask');
    });

    testWidgets('when the voice is unavailable the icon goes quiet and no error text appears',
        (WidgetTester t) async {
      final ReadAloudController ra = ReadAloudController();
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Hi')), ra: ra));
      expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('rror'), findsNothing);
      expect(find.textContaining('not available'), findsNothing,
          reason: 'the unavailable state is an icon, never a sentence to the child');
    });

    testWidgets('an engine that fails on the first tap goes quiet afterwards without a message',
        (WidgetTester t) async {
      final FakeEngine e = FakeEngine()..throwOnSpeak = true;
      final ReadAloudController ra = ReadAloudController(engine: e);
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Hi')), ra: ra));
      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('renders nothing when the guardian turns read-aloud off', (WidgetTester t) async {
      final ReadAloudController ra = ReadAloudController(engine: FakeEngine());
      final AccessController a = await loaded(const AccessSettings(readAloud: false), age: 5);
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Hi')), ra: ra, access: a));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });

    testWidgets('renders nothing with no read-aloud scope at all (every pre-existing screen)', (WidgetTester t) async {
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Hi'))));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });

    testWidgets('has an accessible name that changes when unavailable', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      final ReadAloudController ra = ReadAloudController(engine: FakeEngine());
      await t.pumpWidget(host(const Center(child: SpeakerButton(text: 'Hi')), ra: ra));
      expect(find.bySemanticsLabel('Read this out loud'), findsOneWidget);
      ra.engine = null;
      await t.pump();
      expect(find.bySemanticsLabel('Reading out loud is not available here'), findsOneWidget);
      h.dispose();
    });
  });

  group('the guardian switch and her age', () {
    testWidgets('with no choice, a 5-year-old gets the speaker and a 9-year-old does not', (WidgetTester t) async {
      final ReadAloudController ra = ReadAloudController(engine: FakeEngine());
      await t.pumpWidget(host(const SpeakerButton(text: 'Hi'), ra: ra, access: await loaded(AccessSettings.defaults, age: 5)));
      expect(find.byKey(const Key('speakerButton')), findsOneWidget);
      await t.pumpWidget(host(const SpeakerButton(text: 'Hi'), ra: ra, access: await loaded(AccessSettings.defaults, age: 9)));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });

    testWidgets('switching it on for a 9-year-old brings the speaker back', (WidgetTester t) async {
      final ReadAloudController ra = ReadAloudController(engine: FakeEngine());
      final AccessController a = await loaded(AccessSettings.defaults, age: 9);
      await t.pumpWidget(host(const SpeakerButton(text: 'Hi'), ra: ra, access: a));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
      await a.update((AccessSettings s) => s.copyWith(readAloud: true));
      await t.pump();
      expect(find.byKey(const Key('speakerButton')), findsOneWidget);
    });
  });

  group('every tile speaks its label', () {
    testWidgets('long-press speaks the label and a tap still opens the tile', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      int opened = 0;
      await t.pumpWidget(host(
          SizedBox(height: 90, child: TieredTile(icon: Icons.star, label: 'My list', onTap: (_) => opened++)),
          ra: ra));
      await t.longPress(find.text('My list'));
      await t.pump();
      expect(e.spoken, <String>['My list']);
      expect(opened, 0, reason: 'long-press only reads; it does not open');
      await t.tap(find.text('My list'));
      await t.pump();
      expect(opened, 1);
      expect(e.spoken, <String>['My list'], reason: 'a plain tap opens and does not read');
    });

    testWidgets('the speaker button on a tile speaks its label and does not open the tile', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      int opened = 0;
      await t.pumpWidget(host(
          SizedBox(height: 90, child: TieredTile(icon: Icons.star, label: 'Messages', onTap: (_) => opened++)),
          ra: ra));
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(e.spoken, <String>['Messages']);
      expect(opened, 0);
    });

    testWidgets('no speaker and no long-press reading when read-aloud is off', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      final AccessController a = await loaded(const AccessSettings(readAloud: false));
      await t.pumpWidget(host(
          SizedBox(height: 90, child: TieredTile(icon: Icons.star, label: 'My list', onTap: (_) {})),
          ra: ra, access: a));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
      await t.longPress(find.text('My list'));
      await t.pump();
      expect(e.spoken, isEmpty);
    });

    testWidgets('a tile with no read-aloud scope is exactly as before: no speaker', (WidgetTester t) async {
      await t.pumpWidget(host(
          SizedBox(height: 90, child: TieredTile(icon: Icons.star, label: 'My list', onTap: (_) {}))));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });

    testWidgets('the speaker does not overlap the label', (WidgetTester t) async {
      final ReadAloudController ra = ReadAloudController(engine: FakeEngine());
      await t.pumpWidget(host(
          SizedBox(width: 160, height: 100, child: TieredTile(icon: Icons.star, label: 'Messages', onTap: (_) {})),
          ra: ra));
      final Rect label = t.getRect(find.text('Messages'));
      final Rect speaker = t.getRect(find.byKey(const Key('speakerButton')));
      expect(label.overlaps(speaker), isFalse);
    });

    testWidgets('a tile that opts out (a grown-up screen) gets no speaker and no long-press reading',
        (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      await t.pumpWidget(host(
          SizedBox(height: 90, child: TieredTile(icon: Icons.star, label: 'Availability', readAloud: false, onTap: (_) {})),
          ra: ra));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
      await t.longPress(find.text('Availability'));
      await t.pump();
      expect(e.spoken, isEmpty);
    });

    testWidgets('leaving the screen stops a tile that is being read', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      await t.pumpWidget(host(
          SizedBox(height: 90, child: TieredTile(icon: Icons.star, label: 'Messages', onTap: (_) {})),
          ra: ra));
      await t.longPress(find.text('Messages'));
      await t.pump();
      expect(ra.speakingOwner, isNotNull);
      await t.pumpWidget(host(const SizedBox(), ra: ra));
      await t.pump();
      expect(ra.speakingOwner, isNull);
      expect(e.stops, greaterThanOrEqualTo(1));
    });
  });

  group('ReadAloudRouteObserver', () {
    testWidgets('opening and closing a screen stops whatever was being read', (WidgetTester t) async {
      final FakeEngine e = FakeEngine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      final ReadAloudRouteObserver obs = ReadAloudRouteObserver(ra);
      await t.pumpWidget(host(
          Builder(builder: (BuildContext context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
              child: const Text('open'))),
          ra: ra, observers: <NavigatorObserver>[obs]));
      await ra.speak('Hello', owner: 'x');
      final int before = e.stops;
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(e.stops, greaterThan(before));
      await ra.speak('Again', owner: 'x');
      final int mid = e.stops;
      Navigator.of(t.element(find.byType(Scaffold).last)).pop();
      await t.pumpAndSettle();
      expect(e.stops, greaterThan(mid));
    });
  });

  group('the older speak callbacks', () {
    testWidgets('speakFnOf is null with no scope, and speaks through the scope\'s controller otherwise',
        (WidgetTester t) async {
      Future<void> Function(String)? seen;
      await t.pumpWidget(host(Builder(builder: (BuildContext c) {
        seen = ReadAloudScope.speakFnOf(c);
        return const SizedBox();
      })));
      expect(seen, isNull);
      final FakeEngine e = FakeEngine();
      await t.pumpWidget(host(Builder(builder: (BuildContext c) {
        seen = ReadAloudScope.speakFnOf(c);
        return const SizedBox();
      }), ra: ReadAloudController(engine: e)));
      expect(seen, isNotNull);
      await seen!('Allergies: peanuts');
      expect(e.spoken, <String>['Allergies: peanuts']);
    });
  });

  test('read aloud never logs and never leaves the device (the constants this policy rests on)', () {
    expect(readAloudOnDeviceOnly, isTrue);
    expect(readAloudNeverLogged, isTrue);
  });
}
