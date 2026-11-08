// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — read-aloud on
// story pages, and on the three older screens that already had a speaker button
// (emergency card, handover notes) now reaching the app's read-aloud when no
// callback is passed. MASTERFILE §8.8.5.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/emergency_card.dart';
import 'package:olive_client/handover_notes.dart';
import 'package:olive_client/read_aloud.dart';
import 'package:olive_client/storyteller_logic.dart' as story;
import 'package:olive_client/storyteller_screen.dart';

class _Engine implements ReadAloudEngine {
  final List<String> spoken = <String>[];
  int stops = 0;
  bool fail = false;
  @override
  Future<void> speak(String text) async {
    if (fail) throw StateError('no voice');
    spoken.add(text);
  }

  @override
  Future<void> stop() async => stops++;
}

Future<void> pump(WidgetTester t, Widget w, ReadAloudController ra, {AccessSettings s = AccessSettings.defaults}) async {
  await t.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final AccessController c = AccessController(repository: MemoryAccessRepository(s));
  await c.load();
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
    home: AccessScope(controller: c, child: ReadAloudScope(controller: ra, child: w)),
  ));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  group('story pages speak their text', () {
    testWidgets('the speaker on a page reads that page\'s text, and only when she taps it', (WidgetTester t) async {
      final _Engine e = _Engine();
      await pump(t, const StorytellerScreen(childName: 'Ivy'), ReadAloudController(engine: e));
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      expect(e.spoken, isEmpty, reason: 'a story page never starts talking by itself');
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(e.spoken.length, 1);
      final String page = e.spoken.single;
      expect(page.trim(), isNotEmpty);
      expect(find.textContaining(page.substring(0, page.length.clamp(0, 12)), findRichText: true), findsWidgets,
          reason: 'what is spoken is the text on the page');
    });

    testWidgets('turning the page ends the old reading, and does not start the new one', (WidgetTester t) async {
      final _Engine e = _Engine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      await pump(t, const StorytellerScreen(childName: 'Ivy'), ra);
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      final int stopsBefore = e.stops;
      await t.tap(find.widgetWithText(FilledButton, 'Next'));
      await t.pump(const Duration(milliseconds: 500));
      expect(e.stops, greaterThan(stopsBefore));
      expect(e.spoken.length, 1, reason: 'the next page waits until she asks');
      expect(ra.speakingOwner, isNull);
    });

    testWidgets('closing the screen stops the reading', (WidgetTester t) async {
      final _Engine e = _Engine();
      final ReadAloudController ra = ReadAloudController(engine: e);
      await pump(t, const StorytellerScreen(childName: 'Ivy'), ra);
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(ra.speakingOwner, isNotNull);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pump();
      expect(ra.speakingOwner, isNull);
      expect(e.stops, greaterThanOrEqualTo(1));
    });

    testWidgets('no voice: the speaker is a quiet icon and the story is untouched, with no message', (WidgetTester t) async {
      await pump(t, const StorytellerScreen(childName: 'Ivy'), ReadAloudController());
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
    });

    testWidgets('guardian turned read-aloud off: no speaker on the page', (WidgetTester t) async {
      await pump(t, const StorytellerScreen(childName: 'Ivy'), ReadAloudController(engine: _Engine()),
          s: const AccessSettings(readAloud: false));
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });

    testWidgets('P1: the spoken page never carries a parent\'s name — it is the storyteller\'s text', (WidgetTester t) async {
      final _Engine e = _Engine();
      await pump(t, const StorytellerScreen(childName: 'Ivy'), ReadAloudController(engine: e));
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byKey(const Key('speakerButton')));
      await t.pump();
      for (final String banned in <String>['Dad', 'Mom', 'Mum', 'Daddy', 'Mommy']) {
        expect(e.spoken.single.contains(banned), isFalse);
      }
      expect(story.forReadingAloud, isNotNull);
    });
  });

  group('roomier reading on a story page', () {
    testWidgets('spaces the letters and keeps the page text left-aligned', (WidgetTester t) async {
      await pump(t, const StorytellerScreen(childName: 'Ivy'), ReadAloudController(engine: _Engine()),
          s: const AccessSettings(roomierReading: true));
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      final Iterable<Text> texts = find.descendant(of: find.byKey(const Key('readingCard')), matching: find.byType(Text))
          .evaluate().map((Element e) => e.widget as Text);
      final Iterable<Text> body = texts.where((Text x) => x.style?.fontSize == 19 || x.style?.fontSize == 21);
      expect(body, isNotEmpty);
      for (final Text x in body) {
        expect(x.style!.letterSpacing, closeTo(x.style!.fontSize! * 0.12, 1e-9));
        expect(x.style!.wordSpacing, closeTo(x.style!.fontSize! * 0.16, 1e-9));
        expect(x.style!.height, greaterThanOrEqualTo(1.5));
        expect(x.textAlign, TextAlign.start);
      }
    });

    testWidgets('off: the page text is the old 19/1.4 style', (WidgetTester t) async {
      await pump(t, const StorytellerScreen(childName: 'Ivy'), ReadAloudController(engine: _Engine()));
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 500));
      final Finder page = find.descendant(of: find.byKey(const Key('readingCard')), matching: find.byType(Text));
      final Iterable<Text> texts = page.evaluate().map((Element e) => e.widget as Text);
      expect(texts.any((Text x) => x.style?.fontSize == 19 && x.style?.height == 1.4 && x.style?.letterSpacing == null), isTrue);
    });
  });

  group('the older speak buttons reach the app\'s read-aloud', () {
    testWidgets('handover notes: a speaker with no callback passed reads the entry through the scope', (WidgetTester t) async {
      final _Engine e = _Engine();
      await pump(t, const HandoverNotesScreen(), ReadAloudController(engine: e));
      expect(find.byKey(const Key('readAloudButton_0')), findsOneWidget);
      await t.tap(find.byKey(const Key('readAloudButton_0')));
      await t.pump();
      expect(e.spoken, hasLength(1));
      expect(find.textContaining('not built yet'), findsNothing);
    });

    testWidgets('handover notes with no scope and no callback: still the honest not-built message', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: HandoverNotesScreen()));
      await t.tap(find.byKey(const Key('readAloudButton_0')));
      await t.pump();
      expect(find.textContaining('not built yet'), findsOneWidget);
    });

    testWidgets('the emergency card reads itself through the scope when asked, and never by itself', (WidgetTester t) async {
      final _Engine e = _Engine();
      await pump(t, const EmergencyCardScreen(childName: 'Ivy'), ReadAloudController(engine: e));
      expect(e.spoken, isEmpty);
      await t.tap(find.byIcon(Icons.volume_up_outlined));
      await t.pump();
      expect(e.spoken, hasLength(1));
    });
  });
}
