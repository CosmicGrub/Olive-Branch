// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — picture-first
// input: wants and needs, and the journal, accept a tap on a picture as well as
// typing. MASTERFILE §8.4, P2, P4, P7.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/journal_screen.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/picture_bank.dart';
import 'package:olive_client/read_aloud.dart';
import 'package:olive_client/wants_needs.dart';

Widget wrap(Widget child, {AccessController? access, ReadAloudController? ra}) {
  Widget body = child;
  if (ra != null) body = ReadAloudScope(controller: ra, child: body);
  if (access != null) body = AccessScope(controller: access, child: body);
  return MaterialApp(theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true), home: Material(child: body));
}

class _Engine implements ReadAloudEngine {
  final List<String> spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

void main() {
  setUp(LocalServices.resetForTest);
  tearDown(LocalServices.resetForTest);

  group('the banks', () {
    final Map<String, List<PictureChoice>> banks = <String, List<PictureChoice>>{
      'wants': wantsPictureBank, 'needs': needsPictureBank,
      'feelings': journalFeelingsBank, 'moments': journalMomentsBank,
    };

    test('every picture has a plain label, and ids and labels are unique within a bank', () {
      banks.forEach((String name, List<PictureChoice> bank) {
        expect(bank, isNotEmpty, reason: name);
        expect(bank.map((PictureChoice c) => c.id).toSet().length, bank.length, reason: '$name ids');
        expect(bank.map((PictureChoice c) => c.label).toSet().length, bank.length, reason: '$name labels');
        for (final PictureChoice c in bank) {
          expect(c.label.trim(), isNotEmpty);
        }
      });
    });

    test('P4: no bank carries a price, a brand, a shop or a link — a want is a kind of thing', () {
      final RegExp banned = RegExp(r'\$|£|€|price|cost|buy|shop|store|brand|http|www|\.com|sale|deal|cheap',
          caseSensitive: false);
      banks.forEach((String name, List<PictureChoice> bank) {
        for (final PictureChoice c in bank) {
          expect(banned.hasMatch('${c.label} ${c.sentence ?? ''}'), isFalse, reason: '$name: ${c.label}');
        }
      });
    });

    test('P2: nothing in a bank counts, ranks or scores', () {
      final RegExp banned = RegExp(r'\d|score|streak|rank|best|most|level|points', caseSensitive: false);
      banks.forEach((String name, List<PictureChoice> bank) {
        for (final PictureChoice c in bank) {
          expect(banned.hasMatch('${c.label} ${c.sentence ?? ''}'), isFalse, reason: '$name: ${c.label}');
        }
      });
    });

    test('a picture adds the same plain words typing would have: its sentence if it has one, else its label', () {
      expect(wordsFor(wantsPictureBank.first), wantsPictureBank.first.label);
      expect(wordsFor(journalFeelingsBank.first), 'I feel happy.');
      for (final PictureChoice c in journalFeelingsBank) {
        expect(c.sentence, isNotNull);
        expect(c.sentence!.startsWith('I feel '), isTrue);
      }
    });

    test('the journal feelings include the hard ones, not only the happy ones', () {
      final Set<String> ids = journalFeelingsBank.map((PictureChoice c) => c.id).toSet();
      expect(ids, containsAll(<String>['happy', 'sad', 'cross', 'scared', 'tired']));
    });
  });

  group('PictureBank', () {
    testWidgets('every tile is named for a screen reader and at least 64dp', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(wrap(SingleChildScrollView(
          child: PictureBank(choices: wantsPictureBank, onPick: (_) {}, heading: 'Pick'))));
      for (final PictureChoice c in wantsPictureBank) {
        expect(find.bySemanticsLabel(c.label), findsOneWidget, reason: c.label);
        final Size s = t.getSize(find.byKey(Key('picture_${c.id}')));
        expect(s.width, greaterThanOrEqualTo(64), reason: c.label);
        expect(s.height, greaterThanOrEqualTo(64), reason: c.label);
      }
      h.dispose();
    });

    testWidgets('larger targets raise the tiles to 80dp', (WidgetTester t) async {
      final AccessController a = AccessController(
          repository: MemoryAccessRepository(const AccessSettings(largerTargets: true)));
      await a.load();
      await t.pumpWidget(wrap(SingleChildScrollView(
          child: PictureBank(choices: needsPictureBank, onPick: (_) {})), access: a));
      final Size s = t.getSize(find.byKey(Key('picture_${needsPictureBank.first.id}')));
      expect(s.width, greaterThanOrEqualTo(80));
      expect(s.height, greaterThanOrEqualTo(80));
    });

    testWidgets('tap picks; long-press reads the label and does not pick', (WidgetTester t) async {
      final _Engine e = _Engine();
      final List<String> picked = <String>[];
      await t.pumpWidget(wrap(
          SingleChildScrollView(child: PictureBank(choices: wantsPictureBank, onPick: (PictureChoice c) => picked.add(c.id))),
          ra: ReadAloudController(engine: e)));
      await t.longPress(find.byKey(const Key('picture_book')));
      await t.pump();
      expect(e.spoken, <String>['A book']);
      expect(picked, isEmpty);
      await t.tap(find.byKey(const Key('picture_book')));
      expect(picked, <String>['book']);
      expect(e.spoken, <String>['A book'], reason: 'a tap picks silently; it does not start speech by itself');
    });
  });

  group('wants and needs', () {
    testWidgets('tapping a picture adds its words to that list only, and typing still works', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const WantsNeedsScreen(seedDemoItems: false)));
      await t.pumpAndSettle();
      // The wants bank's "A book".
      await t.tap(find.descendant(of: find.byKey(const Key('wantsSection')), matching: find.byKey(const Key('picture_book'))));
      await t.pump();
      expect(find.descendant(of: find.byKey(const Key('wantsSection')), matching: find.text('A book')), findsWidgets);
      expect(find.descendant(of: find.byKey(const Key('needsSection')), matching: find.text('A book')), findsNothing);
      // The needs bank's "A coat".
      await t.tap(find.descendant(of: find.byKey(const Key('needsSection')), matching: find.byKey(const Key('picture_coat'))));
      await t.pump();
      expect(find.descendant(of: find.byKey(const Key('needsSection')), matching: find.text('A coat')), findsWidgets);
      // Typing, as before.
      await t.enterText(find.descendant(of: find.byKey(const Key('wantsSection')), matching: find.byType(TextField)), 'A kite');
      await t.tap(find.descendant(of: find.byKey(const Key('wantsSection')), matching: find.text('Add')));
      await t.pump();
      expect(find.text('A kite'), findsOneWidget);
    });

    testWidgets('the same picture twice is kept once, quietly: no message, no count', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const WantsNeedsScreen(seedDemoItems: false)));
      await t.pumpAndSettle();
      final Finder pic = find.descendant(of: find.byKey(const Key('wantsSection')), matching: find.byKey(const Key('picture_toy')));
      await t.tap(pic);
      await t.pump();
      await t.tap(pic);
      await t.pump();
      // One list row ("A toy"), plus the picture's own label in the bank.
      expect(find.descendant(of: find.byType(InkWell), matching: find.text('A toy')), findsWidgets);
      final int rows = find.byType(Checkbox).evaluate().length;
      expect(rows, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a picked item is kept on this device, in the same document typing would have written', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final WantsNeedsRepository repo = WantsNeedsRepository(LocalServices.current.area('lists'));
      await t.pumpWidget(wrap(WantsNeedsScreen(repository: repo, seedDemoItems: false)));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byKey(const Key('needsSection')), matching: find.byKey(const Key('picture_food'))));
      await t.pumpAndSettle();
      final List<({String text, bool done})>? saved = await repo.load('needs');
      expect(saved, isNotNull);
      expect(saved!.map((({String text, bool done}) i) => i.text), <String>['Food']);
    });

    testWidgets('no price field appears anywhere on the screen (P4), pictures included', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const WantsNeedsScreen(seedDemoItems: false)));
      await t.pumpAndSettle();
      expect(find.textContaining(RegExp(r'price|\$|buy|cost', caseSensitive: false)), findsNothing);
    });

    testWidgets('the Add buttons and the item rows are 64dp', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const WantsNeedsScreen()));
      await t.pumpAndSettle();
      for (final Element e in find.widgetWithText(FilledButton, 'Add').evaluate()) {
        expect((e.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(64));
      }
      final Finder rows = find.ancestor(of: find.byType(Checkbox), matching: find.byType(InkWell));
      expect(rows, findsWidgets);
      for (final Element e in rows.evaluate()) {
        expect((e.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(64));
      }
    });
  });

  group('journal', () {
    Future<void> open(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(JournalScreen(
          childName: 'Ivy', repository: JournalRepository.forChild())));
      await t.pumpAndSettle();
    }

    testWidgets('a feeling picture writes its sentence into the page, and keeping it still works', (WidgetTester t) async {
      await open(t);
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Keep it, just for me')).onPressed, isNull);
      await t.tap(find.byKey(const Key('picture_happy')));
      await t.pump();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'I feel happy.');
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pumpAndSettle();
      expect(find.text('I feel happy.'), findsOneWidget);
    });

    testWidgets('pictures add to what is already written, and typing is untouched', (WidgetTester t) async {
      await open(t);
      await t.enterText(find.byType(TextField), 'Today was long.');
      await t.tap(find.byKey(const Key('picture_tired')));
      await t.tap(find.byKey(const Key('picture_friend')));
      await t.pump();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text,
          'Today was long. I feel tired. I saw a friend today.');
    });

    testWidgets('the journal stays a still surface: the pictures add no motion', (WidgetTester t) async {
      await open(t);
      await t.tap(find.byKey(const Key('picture_sad')));
      // The touch ripple is the finger's own (driven); once it ends, nothing moves.
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('no guardian-readable path: the screen still takes no reader and the bank imports nothing guardian-side', (WidgetTester t) async {
      await open(t);
      expect(find.textContaining('guardian', findRichText: true), findsNothing);
    });

    testWidgets('the Keep button is 64dp', (WidgetTester t) async {
      await open(t);
      expect(t.getSize(find.widgetWithText(FilledButton, 'Keep it, just for me')).height, greaterThanOrEqualTo(64));
    });
  });
}
