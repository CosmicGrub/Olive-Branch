// OLIVE BRANCH — Parent Learn screens and storage seam.
// Guardian-only, optional extras that default private, nothing stored unless
// the guardian opted in. Every deny path is a real assertion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/parent_learn_logic.dart';
import 'package:olive_client/parent_learn_screens.dart';
import 'package:olive_client/parent_learn_store.dart';

const LearnPrincipal guardian = LearnPrincipal('guardian', 'g1');
const LearnPrincipal child = LearnPrincipal('child', 'c1');

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(500, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

Widget _home(LearnStore s, {LearnPrincipal p = guardian, int? age = 6}) => LearnHomeScreen(
    principal: p, store: s, childAge: age, clock: () => DateTime(2026, 11, 7));

void main() {
  group('storage seam', () {
    test('a child principal is refused everywhere', () async {
      final MemoryLearnStore s = MemoryLearnStore(principal: child);
      await expectLater(s.loadSettings(), throwsA(isA<LearnStoreRefused>()));
      await expectLater(s.saveSettings(defaultLearnSettings), throwsA(isA<LearnStoreRefused>()));
      await expectLater(s.reflections(), throwsA(isA<LearnStoreRefused>()));
      await expectLater(s.myRules(), throwsA(isA<LearnStoreRefused>()));
      await expectLater(s.othersRules(), throwsA(isA<LearnStoreRefused>()));
    });
    test('defaults are the most private choice', () async {
      final MemoryLearnStore s = MemoryLearnStore();
      expect(await s.loadSettings(), defaultLearnSettings);
    });
    test('a reflection is refused unless the guardian chose to save', () async {
      final MemoryLearnStore s = MemoryLearnStore();
      await expectLater(s.saveReflection(const Reflection(day: '2026-11-07', warmth: 50, expectations: 50)),
          throwsA(isA<LearnStoreRefused>()));
      await s.saveSettings(const LearnSettings(reflection: 'off'));
      await expectLater(s.saveReflection(const Reflection(day: '2026-11-07', warmth: 50, expectations: 50)),
          throwsA(isA<LearnStoreRefused>()));
      expect(await s.reflections(), isEmpty);
    });
    test('saving works once opted in, clamps values and rejects a bad day', () async {
      final MemoryLearnStore s = MemoryLearnStore();
      await s.saveSettings(const LearnSettings(reflection: 'saved'));
      await s.saveReflection(const Reflection(day: '2026-11-07', warmth: 500, expectations: -5));
      final List<Reflection> r = await s.reflections();
      expect(r.single.warmth, 100);
      expect(r.single.expectations, 0);
      await expectLater(s.saveReflection(const Reflection(day: 'today', warmth: 1, expectations: 1)),
          throwsA(isA<LearnStoreRefused>()));
    });
    test('turning saving off forgets what was saved', () async {
      final MemoryLearnStore s = MemoryLearnStore();
      await s.saveSettings(const LearnSettings(reflection: 'saved'));
      await s.saveReflection(const Reflection(day: '2026-11-07', warmth: 50, expectations: 50));
      await s.saveSettings(const LearnSettings(reflection: 'session'));
      expect(await s.reflections(), isEmpty);
    });
    test('the rules list is refused while off, and only core categories are kept', () async {
      final MemoryLearnStore s = MemoryLearnStore();
      await expectLater(s.setMyRules(const <RuleItem>[RuleItem('bedtime', '8:00')]), throwsA(isA<LearnStoreRefused>()));
      await s.saveSettings(const LearnSettings(rulesList: true));
      await s.setMyRules(const <RuleItem>[RuleItem('bedtime', ' 8:00 '), RuleItem('style', 'x'), RuleItem('screens', '')]);
      final List<RuleItem> mine = await s.myRules();
      expect(mine.length, 1);
      expect(mine.single.text, '8:00');
    });
    test('turning the rules list off clears it and hides the other guardian\'s', () async {
      final MemoryLearnStore s = MemoryLearnStore(others: <OtherGuardianRules>[
        const OtherGuardianRules(guardianName: 'Dana', rules: <RuleItem>[RuleItem('bedtime', '8:30')])
      ]);
      await s.saveSettings(const LearnSettings(rulesList: true));
      await s.setMyRules(const <RuleItem>[RuleItem('bedtime', '8:00')]);
      expect((await s.othersRules()).length, 1);
      await s.saveSettings(const LearnSettings());
      expect(await s.myRules(), isEmpty);
      expect(await s.othersRules(), isEmpty);
    });
  });

  group('guardian-only', () {
    testWidgets('a child principal sees nothing from Learn', (WidgetTester t) async {
      await _pump(t, _home(MemoryLearnStore(principal: child), p: child));
      expect(find.byKey(const Key('learnGuardiansOnly')), findsOneWidget);
      expect(find.byKey(const Key('learnCard_two-dimensions')), findsNothing);
      expect(find.textContaining('Strong evidence'), findsNothing);
    });
    testWidgets('every other screen refuses a child too', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore(principal: child);
      for (final Widget w in <Widget>[
        ReflectionScreen(principal: child, store: s),
        LearnSettingsScreen(principal: child, store: s),
        RulesScreen(principal: child, store: s),
        const MessageCheckScreen(principal: child, settings: LearnSettings(messageCheck: true)),
      ]) {
        await _pump(t, w);
        expect(find.byKey(const Key('learnGuardiansOnly')), findsOneWidget);
      }
    });
  });

  group('home', () {
    testWidgets('shows cards with evidence labels and a privacy line', (WidgetTester t) async {
      await _pump(t, _home(MemoryLearnStore()));
      expect(find.byKey(const Key('learnPrivacyLine')), findsOneWidget);
      expect(find.byKey(const Key('learnCard_warm-and-clear')), findsOneWidget);
      expect(find.text('Moderate evidence'), findsWidgets);
      expect(find.text('Contested'), findsWidgets);
    });
    testWidgets('the optional tools are hidden by default; Your choices is always there', (WidgetTester t) async {
      await _pump(t, _home(MemoryLearnStore()));
      expect(find.byKey(const Key('learnToolMessage')), findsNothing);
      expect(find.byKey(const Key('learnToolRules')), findsNothing);
      expect(find.byKey(const Key('learnToolReflection')), findsOneWidget);
      expect(find.byKey(const Key('learnToolSettings')), findsOneWidget);
    });
    testWidgets('the age filter hides what is not for a 1-year-old', (WidgetTester t) async {
      await _pump(t, _home(MemoryLearnStore(), age: 1));
      expect(find.byKey(const Key('learnCard_short-time-out')), findsNothing);
      expect(find.byKey(const Key('learnCard_two-dimensions')), findsOneWidget);
    });
    testWidgets('a topic chip filters the list', (WidgetTester t) async {
      await _pump(t, _home(MemoryLearnStore()));
      await t.tap(find.byKey(const Key('learnTopic_conflict')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('learnCard_how-parents-fight')), findsOneWidget);
      expect(find.byKey(const Key('learnCard_two-dimensions')), findsNothing);
    });
    testWidgets('a card opens with its sources and the not-clinical-advice line', (WidgetTester t) async {
      await _pump(t, _home(MemoryLearnStore()));
      await t.tap(find.byKey(const Key('learnCard_culture-changes-meaning')));
      await t.pumpAndSettle();
      expect(find.text('Contested'), findsOneWidget);
      expect(find.byKey(const Key('learnSource_culture-changes-meaning')), findsOneWidget);
      expect(find.textContaining('not clinical advice'), findsOneWidget);
    });
  });

  group('your choices', () {
    testWidgets('turning the message check on adds the tool to home', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore();
      await _pump(t, _home(s));
      await t.tap(find.byKey(const Key('learnToolSettings')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('toggleMessageCheck')));
      await t.tap(find.byKey(const Key('toggleMessageCheck')));
      await t.pumpAndSettle();
      expect((await s.loadSettings()).messageCheck, isTrue);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('learnToolMessage')), findsOneWidget);
    });
    testWidgets('reflection off hides the reflection tool', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore();
      await s.saveSettings(const LearnSettings(reflection: 'off'));
      await _pump(t, _home(s));
      expect(find.byKey(const Key('learnToolReflection')), findsNothing);
    });
    testWidgets('choosing "save privately" is stored and says it is never exported', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore();
      await _pump(t, LearnSettingsScreen(principal: guardian, store: s));
      expect(find.textContaining('never exported'), findsOneWidget);
      await t.tap(find.byKey(const Key('reflectionSaved')));
      await t.pumpAndSettle();
      expect((await s.loadSettings()).reflection, 'saved');
    });
    testWidgets('the culture note framing is applied to style cards', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore();
      await s.saveSettings(const LearnSettings(framing: 'culture-note'));
      await _pump(t, _home(s));
      await t.tap(find.byKey(const Key('learnCard_two-dimensions')));
      await t.pumpAndSettle();
      expect(find.textContaining('differ by family and culture'), findsOneWidget);
    });
  });

  group('reflection', () {
    testWidgets('moving the slider changes the mirror, which describes the day not the person', (WidgetTester t) async {
      await _pump(t, ReflectionScreen(principal: guardian, store: MemoryLearnStore()));
      expect(t.widget<Text>(find.byKey(const Key('mirrorHeadline'))).data, 'Warm, with clear limits.');
      await t.drag(find.byKey(const Key('sliderWarmth')), const Offset(-600, 0));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('mirrorHeadline'))).data, 'Firm today, with less warmth.');
    });
    testWidgets('session mode offers no save button and says it is cleared', (WidgetTester t) async {
      await _pump(t, ReflectionScreen(principal: guardian, store: MemoryLearnStore()));
      expect(find.byKey(const Key('reflectionSave')), findsNothing);
      expect(find.byKey(const Key('reflectionSessionNote')), findsOneWidget);
    });
    testWidgets('saved mode saves, lists and deletes', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore();
      await s.saveSettings(const LearnSettings(reflection: 'saved'));
      await _pump(t, ReflectionScreen(principal: guardian, store: s, clock: () => DateTime(2026, 11, 7)));
      await t.tap(find.byKey(const Key('reflectionSave')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('saved_2026-11-07')), findsOneWidget);
      expect((await s.reflections()).length, 1);
      await t.tap(find.byTooltip('Delete'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('saved_2026-11-07')), findsNothing);
      expect(await s.reflections(), isEmpty);
    });
    testWidgets('session mode writes nothing to the store', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore();
      await _pump(t, ReflectionScreen(principal: guardian, store: s));
      await t.drag(find.byKey(const Key('sliderExpectations')), const Offset(-600, 0));
      await t.pumpAndSettle();
      expect(await s.reflections(), isEmpty);
    });
  });

  group('message check', () {
    testWidgets('off: explains how to turn it on and offers no input', (WidgetTester t) async {
      await _pump(t, const MessageCheckScreen(principal: guardian, settings: defaultLearnSettings));
      expect(find.byKey(const Key('messageCheckOff')), findsOneWidget);
      expect(find.byKey(const Key('messageDraft')), findsNothing);
    });
    testWidgets('on: flags blame and absolutes, hints only', (WidgetTester t) async {
      await _pump(t, const MessageCheckScreen(principal: guardian, settings: LearnSettings(messageCheck: true)));
      await t.enterText(find.byKey(const Key('messageDraft')), 'You always let her stay up and it is your fault.');
      await t.tap(find.byKey(const Key('messageCheckRun')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('hint_absolute')), findsOneWidget);
      expect(find.byKey(const Key('hint_blame')), findsOneWidget);
      expect(find.textContaining('words are yours to change'), findsOneWidget);
    });
    testWidgets('a calm message gets a calm answer', (WidgetTester t) async {
      await _pump(t, const MessageCheckScreen(principal: guardian, settings: LearnSettings(messageCheck: true)));
      await t.enterText(find.byKey(const Key('messageDraft')), 'Pickup is 5:30 Sunday at the library. Thanks.');
      await t.tap(find.byKey(const Key('messageCheckRun')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('messageClear')), findsOneWidget);
    });
    testWidgets('closing the screen leaves nothing behind (a new one starts empty)', (WidgetTester t) async {
      const LearnSettings on = LearnSettings(messageCheck: true);
      await _pump(t, const MessageCheckScreen(principal: guardian, settings: on));
      await t.enterText(find.byKey(const Key('messageDraft')), 'You never listen.');
      await _pump(t, const SizedBox()); // the screen closes (its State is disposed)
      await _pump(t, const MessageCheckScreen(principal: guardian, settings: on));
      expect(t.widget<TextField>(find.byKey(const Key('messageDraft'))).controller!.text, isEmpty);
    });
  });

  group('rules that match', () {
    testWidgets('off: explains how to turn it on', (WidgetTester t) async {
      await _pump(t, RulesScreen(principal: guardian, store: MemoryLearnStore()));
      expect(find.byKey(const Key('rulesOff')), findsOneWidget);
    });
    testWidgets('add a rule, see it, remove it; the other guardian\'s list is read-only', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore(others: <OtherGuardianRules>[
        const OtherGuardianRules(guardianName: 'Dana', rules: <RuleItem>[RuleItem('bedtime', '8:30 on school nights')])
      ]);
      await s.saveSettings(const LearnSettings(rulesList: true));
      await _pump(t, RulesScreen(principal: guardian, store: s));
      expect(find.byKey(const Key('rulesEmpty')), findsOneWidget);
      expect(find.text('Dana'), findsOneWidget);
      expect(find.text('8:30 on school nights'), findsOneWidget);
      await t.tap(find.byKey(const Key('ruleCat_screens')));
      await t.enterText(find.byKey(const Key('ruleText')), 'No screens at dinner');
      await t.tap(find.byKey(const Key('ruleAdd')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('myRule_0')), findsOneWidget);
      expect((await s.myRules()).single.category, 'screens');
      await t.tap(find.byTooltip('Remove'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rulesEmpty')), findsOneWidget);
      // nothing to edit on the other guardian's list
      expect(find.byTooltip('Remove'), findsNothing);
    });
    testWidgets('only the four core categories are offered', (WidgetTester t) async {
      final MemoryLearnStore s = MemoryLearnStore();
      await s.saveSettings(const LearnSettings(rulesList: true));
      await _pump(t, RulesScreen(principal: guardian, store: s));
      for (final String c in ruleCategories) {
        expect(find.byKey(Key('ruleCat_$c')), findsOneWidget);
      }
      expect(find.byKey(const Key('ruleCat_style')), findsNothing);
    });
  });

  group('reachable from the guardian More hub', () {
    testWidgets('the Learn tile opens the Learn screen', (WidgetTester t) async {
      await _pump(t, const GuardianMoreScreen());
      await t.ensureVisible(find.byKey(const Key('moreLearn')));
      await t.tap(find.byKey(const Key('moreLearn')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('learnPrivacyLine')), findsOneWidget);
    });
  });
}
