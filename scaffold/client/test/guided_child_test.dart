// OLIVE BRANCH — her half of the guided first run, on her tablet: started only by a grown-up through the gate, picture-led,
// read-aloud on a tap, two try-its, a calm ending on her home, and NOTHING a child should not see (no PIN, no number, no
// score, no error). Includes the source guard for guided_child.dart. Verified by CI, headless. MASTERFILE §8.5.14.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/guided_child.dart';
import 'package:olive_client/guided_progress.dart';
import 'package:olive_client/guided_script.dart';
import 'package:olive_client/read_aloud.dart';

class _Engine implements ReadAloudEngine {
  final List<String> spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

GuidedEntry _extra(String id) => GuidedEntry(
      id: id, half: GuidedHalf.child, slot: 'child.extra', kind: GuidedKind.childLabel, since: 2, whatsNew: true,
      title: id, words: '', labels: <GuidedLabel>[const GuidedLabel(Icons.brush, 'Painting', 'Make a picture')],
    );

/// Everything a child could read or hear on screen: text, tooltips, semantics labels.
String _everythingShown(WidgetTester t) {
  final List<String> out = <String>[];
  for (final Text w in t.widgetList<Text>(find.byType(Text))) {
    out.add(w.data ?? w.textSpan?.toPlainText() ?? '');
  }
  for (final Tooltip w in t.widgetList<Tooltip>(find.byType(Tooltip))) {
    out.add(w.message ?? '');
  }
  for (final Semantics w in t.widgetList<Semantics>(find.byType(Semantics))) {
    out.add(w.properties.label ?? '');
  }
  return out.join(' | ');
}

void main() {
  late MemoryGuidedProgressStore store;
  late _Engine engine;
  setUp(() {
    store = MemoryGuidedProgressStore();
    engine = _Engine();
  });

  Future<void> pump(
    WidgetTester t, {
    GuidedProgress? progress,
    bool grownUpProves = true,
    bool hasProof = true,
    bool enabled = true,
    bool simulate = false,
    Size size = const Size(1000, 800),
    double text = 1.0,
    List<GuidedEntry> registered = const <GuidedEntry>[],
    int version = kGuidedScriptVersion,
    String? name = 'Ana',
  }) async {
    if (progress != null) await store.save(progress);
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      builder: (BuildContext c, Widget? w) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(text)), child: w!),
      home: AccessScope(
        controller: AccessController(repository: MemoryAccessRepository()),
        child: ReadAloudScope(
          controller: ReadAloudController(engine: engine),
          child: ChildWelcomeHost(
            store: store,
            name: name,
            enabled: enabled,
            simulate: simulate,
            registered: registered,
            scriptVersion: version,
            prove: hasProof ? (BuildContext c) async => grownUpProves : null,
            child: const Scaffold(body: Center(child: Text('her home'))),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  String childTitle(WidgetTester t) => t.widget<Text>(find.byKey(const Key('childTitle'))).data!;

  Future<void> next(WidgetTester t) async {
    await t.tap(find.byKey(const Key('childNext')));
    await t.pumpAndSettle();
  }

  Future<void> startWelcome(WidgetTester t) async {
    await t.tap(find.byKey(const Key('childOfferGrownUp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('childReadyStart')));
    await t.pumpAndSettle();
  }

  group('who ever sees it', () {
    testWidgets('a tablet that was paired before this existed (no record): her home, nothing over it', (t) async {
      await pump(t);
      expect(find.text('her home'), findsOneWidget);
      expect(find.byKey(const Key('childOfferTitle')), findsNothing);
    });

    testWidgets('a tablet that has done it and has seen this version: nothing', (t) async {
      await pump(t, progress: const GuidedProgress(seenVersion: kGuidedScriptVersion, child: ChildWelcomeState.done));
      expect(find.byKey(const Key('childOfferTitle')), findsNothing);
    });

    testWidgets('a build that is not a locally paired tablet: nothing, even if a record says offered', (t) async {
      await pump(t, enabled: false, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      expect(find.byKey(const Key('childOfferTitle')), findsNothing);
    });

    testWidgets('a grown-up just paired it: the calm card, and nothing starts without a grown-up', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      expect(find.byKey(const Key('childOfferTitle')), findsOneWidget);
      expect(find.text('A grown-up does this'), findsWidgets);
      expect(find.text('A grown-up will show you around.'), findsOneWidget);
      await t.pump(const Duration(minutes: 30));
      expect(find.byKey(const Key('childOfferTitle')), findsOneWidget, reason: 'nothing advances by itself');
      expect(find.byKey(const Key('childTitle')), findsNothing, reason: 'she cannot start it');
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('"Go to my home" is always there: her home, the welcome is not offered again after a relaunch', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await t.tap(find.byKey(const Key('childOfferHome')));
      await t.pumpAndSettle();
      expect(find.text('her home'), findsOneWidget);
      expect((await store.load()).child, ChildWelcomeState.done);
      await pump(t); // a relaunch reads the same store
      expect(find.byKey(const Key('childOfferTitle')), findsNothing);
    });

    testWidgets('without a way to prove a grown-up, there is no grown-up button, only the way home: never stuck', (t) async {
      await pump(t, hasProof: false, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      expect(find.byKey(const Key('childOfferGrownUp')), findsNothing);
      expect(find.byKey(const Key('childOfferHome')), findsOneWidget);
    });

    testWidgets('a grown-up who does not pass the gate changes nothing and is told nothing: no error text, no count', (t) async {
      await pump(t, grownUpProves: false, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await t.tap(find.byKey(const Key('childOfferGrownUp')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childOfferTitle')), findsOneWidget);
      expect(find.byKey(const Key('childReadyTitle')), findsNothing);
      final String all = _everythingShown(t).toLowerCase();
      for (final String bad in <String>['wrong', 'error', 'try again', 'attempt', 'incorrect', 'locked']) {
        expect(all, isNot(contains(bad)));
      }
    });
  });

  group('the welcome, start to finish', () {
    testWidgets('the gate, the grown-up\'s one card, then hello, her icons with their labels, the try-its, and her home', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await t.tap(find.byKey(const Key('childOfferGrownUp')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('childReadyTitle'))).data, 'Ready to show Ana around?');
      expect(find.textContaining('She cannot start it on her own.'), findsOneWidget);
      await t.tap(find.byKey(const Key('childReadyStart')));
      await t.pumpAndSettle();

      final List<String> seen = <String>[];
      while (find.byKey(const Key('childTitle')).evaluate().isNotEmpty) {
        seen.add(childTitle(t));
        if (childTitle(t) == "All done. Let's go!") break;
        await next(t);
      }
      expect(seen, <String>[
        'Hello, Ana!', 'My day and Play together', 'Messages', 'Stories and Show & tell', 'Colour', 'More', "All done. Let's go!",
      ]);
      await t.tap(find.byKey(const Key('childNext')));
      await t.pumpAndSettle();
      expect(find.text('her home'), findsOneWidget, reason: 'it lands on her home');
      expect(find.byKey(const Key('childTitle')), findsNothing);
      final GuidedProgress p = await store.load();
      expect(p.child, ChildWelcomeState.done);
      expect(p.seenVersion, kGuidedScriptVersion);
    });

    testWidgets('every one of her icons is shown with its label spelled out, the labels on her own home', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await startWelcome(t);
      final Set<String> labels = <String>{};
      for (int i = 0; i < 7; i++) {
        for (final Text w in t.widgetList<Text>(find.byType(Text))) {
          labels.add(w.data ?? '');
        }
        await next(t);
      }
      for (final String l in <String>['My day', 'Play together', 'Messages', 'Stories', 'Show & tell', 'Colour', 'More']) {
        expect(labels, contains(l), reason: l);
      }
    });

    testWidgets('try-it one: Messages shows a calm empty box; nothing is saved', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await startWelcome(t);
      await next(t);
      await next(t);
      expect(childTitle(t), 'Messages');
      expect(find.byKey(const Key('childMessagesBox')), findsNothing);
      final GuidedProgress before = await store.load();
      await t.tap(find.byKey(const Key('childTryMessages')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childMessagesBox')), findsOneWidget);
      expect(find.text(GuidedWords.tryMessages), findsOneWidget);
      expect((await store.load()).toJson(), before.toJson(), reason: 'what she taps is not kept');
      await t.tap(find.byKey(const Key('childTryMessages')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childMessagesBox')), findsNothing);
    });

    testWidgets('try-it two: Colour paints the card the colour she taps, and says "Lovely."', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await startWelcome(t);
      for (int i = 0; i < 4; i++) {
        await next(t);
      }
      expect(childTitle(t), 'Colour');
      expect(find.byKey(const Key('childColour0')), findsOneWidget);
      await t.tap(find.byKey(const Key('childColour1')));
      await t.pumpAndSettle();
      expect(find.text(GuidedWords.tryColour), findsOneWidget);
      final AnimatedContainer ac = t.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
      final Color? tint = (ac.decoration as BoxDecoration?)?.color;
      expect(tint, isNotNull);
      expect(tint, isNot(Theme.of(t.element(find.byKey(const Key('childTitle')))).colorScheme.surface));
    });

    testWidgets('Back goes back; Skip goes on; Later goes to her home', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await startWelcome(t);
      expect(find.byKey(const Key('childBack')), findsNothing, reason: 'nothing behind the first card');
      await next(t);
      expect(childTitle(t), 'My day and Play together');
      await t.tap(find.byKey(const Key('childBack')));
      await t.pumpAndSettle();
      expect(childTitle(t), 'Hello, Ana!');
      await t.tap(find.byKey(const Key('childSkip')));
      await t.pumpAndSettle();
      expect(childTitle(t), 'My day and Play together');
      await t.tap(find.byKey(const Key('childLater')));
      await t.pumpAndSettle();
      expect(find.text('her home'), findsOneWidget);
    });

    testWidgets('killed half-way: she is NOT left in it; a grown-up proves again and it resumes at the same card', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.inProgress, childStep: 'c.stories'));
      expect(find.byKey(const Key('childOfferTitle')), findsOneWidget);
      expect(find.byKey(const Key('childTitle')), findsNothing);
      await t.tap(find.byKey(const Key('childOfferGrownUp')));
      await t.pumpAndSettle();
      expect(childTitle(t), 'Stories and Show & tell');
    });

    testWidgets('a name she does not have reads as "her", never a blank or a placeholder', (t) async {
      await pump(t, name: '', progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await t.tap(find.byKey(const Key('childOfferGrownUp')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('childReadyTitle'))).data, 'Ready to show her around?');
      await t.tap(find.byKey(const Key('childReadyStart')));
      await t.pumpAndSettle();
      expect(childTitle(t), 'Hello, her!'.replaceAll('her', 'her'));
      expect(find.textContaining('{'), findsNothing);
    });
  });

  group('nothing a child should not see', () {
    testWidgets('on every card, and the offer: no digit, no PIN, no count, no score, no streak, no error word, no field', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      final List<String> pages = <String>[_everythingShown(t)];
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.byKey(const Key('childOfferGrownUp')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('childReadyStart')));
      await t.pumpAndSettle();
      for (int i = 0; i < 7; i++) {
        if (find.byKey(const Key('childTryMessages')).evaluate().isNotEmpty) {
          await t.tap(find.byKey(const Key('childTryMessages')));
          await t.pumpAndSettle();
        }
        if (find.byKey(const Key('childColour0')).evaluate().isNotEmpty) {
          await t.tap(find.byKey(const Key('childColour0')));
          await t.pumpAndSettle();
        }
        pages.add(_everythingShown(t));
        expect(find.byType(TextField), findsNothing);
        await next(t);
      }
      for (final String all in pages) {
        expect(all, isNot(matches(RegExp(r'[0-9]'))), reason: 'a digit is shown to a child: $all');
        for (final String bad in <String>[
          'PIN', 'pin ', 'passcode', 'password', 'code', 'score', 'streak', 'points', 'level', 'minutes', 'hours', 'timer', 'count',
          'wrong', 'error', 'failed', 'try again', 'incorrect', 'invalid', 'expired', 'locked', 'server', 'connection', 'Exception',
        ]) {
          expect(all.toLowerCase(), isNot(contains(bad.toLowerCase())), reason: '"$bad" is shown to a child: $all');
        }
      }
    });

    test('source guard: guided_child.dart imports no keypad, no pairing and no PIN code, has no text field, and its words hold no digit or forbidden word', () {
      final String src = File('lib/guided_child.dart').readAsStringSync().replaceAll('\r\n', '\n');
      for (final String bad in <String>['pin_gate', 'pin_keypad', 'local_pin', 'adult_gate', 'pairing_', 'device_keys', 'TextField', 'obscureText']) {
        expect(src, isNot(contains(bad)), reason: 'guided_child.dart touches "$bad"');
      }
      final RegExp literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'|" '"((?:[^"\\\\\\n]|\\\\.)*)"');
      for (final String line in src.split('\n')) {
        final String code = line.trimLeft();
        if (code.startsWith('//') || code.startsWith('import ') || code.startsWith('///')) continue;
        for (final RegExpMatch m in literal.allMatches(line)) {
          final String s = m.group(1) ?? m.group(2) ?? '';
          if (s.startsWith('child') || s.startsWith('replay-') || s.startsWith('package:') || s.startsWith('guided_')) continue; // keys
          expect(s, isNot(matches(RegExp(r'[0-9]'))), reason: 'a digit in a string a child might read: "$s"');
          for (final String w in <String>['PIN', 'passcode', 'password', 'score', 'streak', 'error', 'wrong', 'failed']) {
            expect(s.toLowerCase(), isNot(contains(w.toLowerCase())), reason: '"$w" in "$s"');
          }
        }
      }
    });
  });

  group('read-aloud, a11y and large text', () {
    testWidgets('a speaker on each card reads the card on a tap, and nothing is spoken until she taps', (t) async {
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await startWelcome(t);
      expect(engine.spoken, isEmpty, reason: 'never autonomous');
      expect(find.byKey(const Key('speakerButton')), findsOneWidget);
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pumpAndSettle();
      expect(engine.spoken, <String>["Hello, Ana!. This is your Olive. Let's look at what is on your home."]);
    });

    testWidgets('semantics: the title is a header, the big arrow and the back arrow are named, icons carry their labels', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await pump(t, progress: const GuidedProgress(child: ChildWelcomeState.offered));
      await startWelcome(t);
      await next(t);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('My day.*What comes next')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Play together.*Games')), findsWidgets);
      expect(find.bySemanticsLabel('Skip this part'), findsWidgets);
      expect(find.bySemanticsLabel('Do this later'), findsWidgets);
      h.dispose();
    });

    for (final Size size in const <Size>[Size(344, 700), Size(904, 800)]) {
      testWidgets('${size.width.toInt()} wide at 2x text: the offer, the grown-up card and every card fit', (t) async {
        await pump(t, size: size, text: 2.0, progress: const GuidedProgress(child: ChildWelcomeState.offered));
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byKey(const Key('childOfferHome')));
        await t.ensureVisible(find.byKey(const Key('childOfferGrownUp')));
        await t.tap(find.byKey(const Key('childOfferGrownUp')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byKey(const Key('childReadyStart')));
        await t.tap(find.byKey(const Key('childReadyStart')));
        await t.pumpAndSettle();
        for (int i = 0; i < 7; i++) {
          expect(t.takeException(), isNull, reason: 'card $i');
          expect(find.byKey(const Key('childNext')), findsOneWidget);
          await t.ensureVisible(find.byKey(const Key('childNext')));
          await t.tap(find.byKey(const Key('childNext')));
          await t.pumpAndSettle();
        }
      });
    }
  });

  group('what is new on her home, and the developer seam', () {
    testWidgets('an older tablet is offered only the new icon, on one card, with its label; finishing marks it seen', (t) async {
      await pump(t,
          progress: const GuidedProgress(seenVersion: 1, child: ChildWelcomeState.done),
          registered: <GuidedEntry>[_extra('painting')], version: 2);
      expect(find.byKey(const Key('childOfferTitle')), findsOneWidget);
      await t.tap(find.byKey(const Key('childOfferGrownUp')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('childReadyStart')));
      await t.pumpAndSettle();
      expect(childTitle(t), 'And there is more');
      expect(find.text('Painting'), findsOneWidget);
      expect(find.text('Make a picture'), findsOneWidget);
      await t.tap(find.byKey(const Key('childNext')));
      await t.pumpAndSettle();
      expect(find.text('her home'), findsOneWidget);
      expect((await store.load()).seenVersion, 2);
    });

    testWidgets('a tablet that has seen the newest version, with an icon registered: nothing', (t) async {
      await pump(t, progress: const GuidedProgress(seenVersion: 2, child: ChildWelcomeState.done),
          registered: <GuidedEntry>[_extra('painting')], version: 2);
      expect(find.byKey(const Key('childOfferTitle')), findsNothing);
    });

    testWidgets('the seam: on a tablet that already finished, it starts at the gate card, marked SIMULATED, with nothing erased', (t) async {
      await pump(t, simulate: true, hasProof: false, progress: const GuidedProgress(seenVersion: 1, child: ChildWelcomeState.done));
      expect(find.byKey(const Key('childOfferTitle')), findsOneWidget);
      expect(find.byKey(const Key('simBand')), findsOneWidget);
      expect(find.byKey(const Key('childOfferGrownUp')), findsOneWidget, reason: 'the stand-in gate: no real gate is needed on one device');
      await t.tap(find.byKey(const Key('childOfferGrownUp')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childReadyTitle')), findsOneWidget);
    });
  });

  group('"Show her the welcome again", from the grown-up screen on her tablet', () {
    testWidgets('runs her cards from the hello and closes itself at the end', (t) async {
      await t.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => ChildWelcomeReplay(name: 'Ana', store: store))),
                child: const Text('open it'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open it'));
      await t.pumpAndSettle();
      expect(childTitle(t), 'Hello, Ana!');
      for (int i = 0; i < 6; i++) {
        await next(t);
      }
      expect(childTitle(t), "All done. Let's go!");
      await next(t);
      expect(find.text('open it'), findsOneWidget, reason: 'back on the grown-up screen it came from');
    });
  });
}
