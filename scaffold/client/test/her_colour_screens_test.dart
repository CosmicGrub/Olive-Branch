// OLIVE BRANCH — her colour end to end, local-first: her side (the question, her
// colour as a budgeted accent, art style, the activities), the guardian's side
// (a fact, a colour day, art style), the play window and its gentle ending, and
// the Settings hub. No network anywhere in this file.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/guardian_settings_hub.dart';
import 'package:olive_client/her_colour_guardian.dart';
import 'package:olive_client/her_colour_home.dart';
import 'package:olive_client/her_colour_store.dart';
import 'package:olive_client/play_window_gate.dart';
import 'package:olive_client/play_window_screen.dart';

Future<void> big(WidgetTester t) async {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget app(Widget home) => MaterialApp(home: home);

MemoryColourStore store({int age = 6, DateTime? at, PlayWindow? window}) =>
    MemoryColourStore(ageYears: age, now: () => at ?? DateTime(2026, 11, 7, 8, 0), window: window);

void main() {
  group('her colour: the question', () {
    testWidgets('the first thing she sees is the one daily question', (t) async {
      await big(t);
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: store(), random: () => 0)));
      await t.pumpAndSettle();
      expect(find.text('Which do you like more today?'), findsOneWidget);
      expect(find.text('sea blue'), findsOneWidget);
    });

    testWidgets('answering ends the question and lands on her colour, stated as a fact', (t) async {
      await big(t);
      final s = store();
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s, random: () => 0)));
      await t.pumpAndSettle();
      await t.tap(find.text('sea blue'));
      await t.pumpAndSettle();
      expect(find.text('Today your colour is'), findsOneWidget);
      expect(find.byKey(const Key('colourName')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('colourName'))).data, 'Sea blue');
      expect((await s.today()).ask, isFalse);
    });

    testWidgets('a second visit the same day does not ask again', (t) async {
      await big(t);
      final s = store();
      await s.answer('mint');
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      expect(find.text('Which do you like more today?'), findsNothing);
      expect(t.widget<Text>(find.byKey(const Key('colourName'))).data, 'Mint');
    });

    testWidgets('a guardian colour day is simply her colour: no question, no explanation', (t) async {
      await big(t);
      final s = store();
      await s.setColourDay('grape');
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      expect(find.text('Which do you like more today?'), findsNothing);
      expect(t.widget<Text>(find.byKey(const Key('colourName'))).data, 'Purple');
      expect(find.textContaining(RegExp('guardian|mum|dad|chose for', caseSensitive: false)), findsNothing);
    });

    testWidgets('with the question off and no colour she simply has none, and the app looks as before', (t) async {
      await big(t);
      final s = store();
      await s.saveArt({'dailyQuestion': false});
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      expect(find.text('No colour yet'), findsOneWidget);
      expect(find.byKey(const Key('accentStripe')), findsNothing);
      expect(find.byKey(const Key('colourFlourish')), findsNothing);
      expect(find.byKey(const Key('activity_sort')), findsOneWidget, reason: 'activities still use a default colour');
    });
  });

  group('her colour: a placement-budgeted accent (§8.6.2)', () {
    testWidgets('exactly the three allowed placements, never more', (t) async {
      await big(t);
      final s = store();
      await s.answer('sea');
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      final placed = [
        find.byKey(const Key('accentStripe')), find.byKey(const Key('accentRing')), find.byKey(const Key('colourFlourish')),
      ].map((f) => f.evaluate().length).reduce((a, b) => a + b);
      expect(placed, 3);
      expect(homePlacements.length, 3);
    });

    testWidgets('the stripe is a thin rule, never a surface: the scaffold keeps its own background', (t) async {
      await big(t);
      final s = store();
      await s.answer('sea');
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      expect(t.getSize(find.byKey(const Key('accentStripe'))).height, 4);
      final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, isNull);
    });

    testWidgets('her colour never labels an emotion', (t) async {
      await big(t);
      final s = store();
      await s.answer('storm');
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      expect(find.textContaining(RegExp('sad|happy|mood|feel|angry|calm|cheerful', caseSensitive: false)), findsNothing);
      expect(t.widget<Text>(find.byKey(const Key('colourName'))).data, 'Storm grey');
    });
  });

  group('her colour: activities grow up with her', () {
    Future<List<String>> shown(WidgetTester t, int age, {bool code = true}) async {
      await big(t);
      final s = store(age: age);
      await s.answer('sea');
      if (!code) await s.saveArt({'codeActivities': false});
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: age, store: s)));
      await t.pumpAndSettle();
      return [for (final id in ['sort', 'path', 'critter', 'pixel']) if (find.byKey(Key('activity_$id')).evaluate().isNotEmpty) id];
    }

    testWidgets('age 4: sort and critter', (t) async => expect(await shown(t, 4), ['sort', 'critter']));
    testWidgets('age 6: and Path code', (t) async => expect(await shown(t, 6), ['sort', 'path', 'critter']));
    testWidgets('age 9: Path code, critter and Pixel garden', (t) async => expect(await shown(t, 9), ['path', 'critter', 'pixel']));
    testWidgets('coding switched off: only critter at 9', (t) async => expect(await shown(t, 9, code: false), ['critter']));

    testWidgets('each tile opens its real screen', (t) async {
      await big(t);
      final s = store(age: 6);
      await s.answer('sea');
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('activity_sort')));
      await t.pumpAndSettle();
      expect(find.text('Colour sort'), findsWidgets);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('activity_path')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('runPath')), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('activity_critter')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('critterCanvas')), findsOneWidget);
    });
  });

  group('her colour: art style picker', () {
    testWidgets('she can pick among the styles her guardian allows, and only those', (t) async {
      await big(t);
      final s = store();
      await s.answer('sea');
      await s.saveArt({'artStyle': 'felt', 'allowedStyles': ['felt', 'line']});
      await t.pumpWidget(app(HerColourScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('homeStyle_felt')), findsOneWidget);
      expect(find.byKey(const Key('homeStyle_line')), findsOneWidget);
      expect(find.byKey(const Key('homeStyle_paper')), findsNothing);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('homeStyle_felt'))).selected, isTrue);
      await t.tap(find.byKey(const Key('homeStyle_line')));
      await t.pumpAndSettle();
      expect(t.widget<ChoiceChip>(find.byKey(const Key('homeStyle_line'))).selected, isTrue);
      expect((await s.artStyle()).artStyle, 'felt', reason: 'her pick is play, not a setting: nothing is written');
    });
  });

  group('the More hub tile', () {
    testWidgets('says what is waiting, then what today’s colour is, as a plain fact', (t) async {
      await big(t);
      final s = store();
      await t.pumpWidget(app(ChildMoreScreen(childName: 'Ivy', childAge: 6, colourStore: s)));
      await t.pumpAndSettle();
      expect(find.text('Pick yours'), findsOneWidget);
      await s.answer('sea');
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(ChildMoreScreen(childName: 'Ivy', childAge: 6, colourStore: s)));
      await t.pumpAndSettle();
      expect(find.text('Today: sea blue'), findsOneWidget);
    });

    testWidgets('the tile opens her colour screen, and is the old hard-coded "sea" no more', (t) async {
      await big(t);
      final s = store();
      await s.answer('chocolate');
      await t.pumpWidget(app(ChildMoreScreen(childName: 'Ivy', childAge: 6, colourStore: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('colourTile')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('colourName'))).data, 'Chocolate');
      expect(File('lib/child_more.dart').readAsStringSync().contains("currentColourId: 'sea'"), isFalse);
    });

    testWidgets('one placement on the hub: the tile border, only once she has a colour', (t) async {
      await big(t);
      final s = store();
      await t.pumpWidget(app(ChildMoreScreen(childName: 'Ivy', childAge: 6, colourStore: s)));
      await t.pumpAndSettle();
      expect(t.widget<Card>(find.ancestor(of: find.byKey(const Key('colourTile')), matching: find.byType(Card))).shape, isNull);
      await s.answer('sea');
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(ChildMoreScreen(childName: 'Ivy', childAge: 6, colourStore: s)));
      await t.pumpAndSettle();
      final card = t.widget<Card>(find.ancestor(of: find.byKey(const Key('colourTile')), matching: find.byType(Card)));
      expect(card.shape, isA<RoundedRectangleBorder>());
    });
  });

  group('guardian: her colour and art', () {
    testWidgets('a fact in one sentence, the time, and that her devices agree', (t) async {
      await big(t);
      final s = store();
      await s.answer('sea');
      await t.pumpWidget(app(HerColourGuardianScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      expect(find.text('Today her colour is sea blue.'), findsOneWidget);
      expect(find.text('Chosen at 08:00, her time.'), findsOneWidget);
      expect(find.text('Every device Ivy uses shows the same colour.'), findsOneWidget);
    });

    testWidgets('no mood, trend or history is on offer anywhere (§8.6.4)', (t) async {
      await big(t);
      final s = store();
      await s.answer('storm');
      await t.pumpWidget(app(HerColourGuardianScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      expect(find.textContaining(RegExp(r'\b(mood|sad|trend|darker|lighter this|concern|streak|history of her choices)\b', caseSensitive: false)),
          findsOneWidget, reason: 'only the "You can’t" list names a history, to refuse it');
      expect(find.textContaining('Today her colour is storm grey.'), findsOneWidget);
    });

    testWidgets('a colour day: set, shown as such, and cleared', (t) async {
      await big(t);
      final s = store();
      await s.answer('sea');
      await t.pumpWidget(app(HerColourGuardianScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('day_mint')));
      await t.pumpAndSettle();
      expect(find.text('Colour day set for today.'), findsOneWidget);
      expect(find.byKey(const Key('colourDayNote')), findsOneWidget);
      expect(find.text('Today her colour is mint.'), findsOneWidget);
      expect((await s.today()).override, isTrue);
      await t.tap(find.byKey(const Key('clearColourDay')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('colourDayNote')), findsNothing);
      expect(find.textContaining('can choose again'), findsOneWidget);
      expect((await s.today()).ask, isTrue);
    });

    testWidgets('the daily question and the coding activities switch off and on', (t) async {
      await big(t);
      final s = store();
      await t.pumpWidget(app(HerColourGuardianScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('dailyQuestionSwitch')));
      await t.pumpAndSettle();
      expect((await s.art()).dailyQuestion, isFalse);
      await t.tap(find.byKey(const Key('codeActivitiesSwitch')));
      await t.pumpAndSettle();
      expect((await s.art()).codeActivities, isFalse);
    });

    testWidgets('art style: pick the default and the styles she can choose between', (t) async {
      await big(t);
      final s = store();
      await t.pumpWidget(app(HerColourGuardianScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('artStyle_watercolour')));
      await t.pumpAndSettle();
      expect((await s.art()).artStyle, 'watercolour');
      await t.tap(find.byKey(const Key('allowed_felt')));
      await t.pumpAndSettle();
      expect((await s.art()).allowedStyles.contains('felt'), isFalse);
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('removing the default style from the allowed list is refused, in words', (t) async {
      await big(t);
      final s = store();
      await t.pumpWidget(app(HerColourGuardianScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('allowed_paper')));
      await t.pumpAndSettle();
      expect(find.text('The default style has to be one of the allowed styles.'), findsOneWidget);
      expect((await s.art()).allowedStyles.contains('paper'), isTrue);
    });

    testWidgets('pixel is not on offer under 8, and says it opens at 8; from 8 it is', (t) async {
      await big(t);
      await t.pumpWidget(app(HerColourGuardianScreen(childName: 'Ivy', childAge: 6, store: store())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('artStyle_pixel')), findsNothing);
      expect(find.textContaining('Pixel opens at 8'), findsOneWidget);
      await t.pumpWidget(app(HerColourGuardianScreen(childName: 'Ivy', childAge: 9, store: store(age: 9))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('artStyle_pixel')), findsOneWidget);
    });
  });

  group('the play window', () {
    testWidgets('defaults are 3:30 PM to 7:00 PM with a 30 minute wind-down, previewed in her words', (t) async {
      await big(t);
      await t.pumpWidget(app(PlayWindowScreen(childName: 'Ivy', store: store())));
      await t.pumpAndSettle();
      expect(find.text('3:30 PM'), findsOneWidget);
      expect(find.text('7:00 PM'), findsOneWidget);
      expect(find.text('It’s getting sleepy. One more, then goodnight.'), findsOneWidget);
      expect(find.textContaining('Calls and family messages are never affected'), findsOneWidget);
    });

    testWidgets('wind-down off previews the resting line; save stores it', (t) async {
      await big(t);
      final s = store();
      await t.pumpWidget(app(PlayWindowScreen(childName: 'Ivy', store: s)));
      await t.pumpAndSettle();
      await t.tap(find.text('Off'));
      await t.pumpAndSettle();
      expect(find.textContaining('tomorrow'), findsWidgets);
      await t.tap(find.byKey(const Key('saveWindow')));
      await t.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      final w = (await s.playWindow()).window!;
      expect([w.opensMin, w.restsMin, w.windDownMin], [930, 1140, 0]);
    });

    testWidgets('a window that rests before it opens cannot be saved', (t) async {
      await big(t);
      await t.pumpWidget(app(PlayWindowScreen(childName: 'Ivy', store: store())));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('opensDrop')));
      await t.pumpAndSettle();
      await t.tap(find.text('8:00 PM').last);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('windInvalid')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('saveWindow'))).onPressed, isNull);
    });

    testWidgets('an existing window is loaded, not overwritten by the defaults', (t) async {
      await big(t);
      final s = store(window: const PlayWindow(opensMin: 480, restsMin: 1080, windDownMin: 15));
      await t.pumpWidget(app(PlayWindowScreen(childName: 'Ivy', store: s)));
      await t.pumpAndSettle();
      expect(find.text('8:00 AM'), findsOneWidget);
      expect(find.text('6:00 PM'), findsOneWidget);
    });

    test('minute labels', () {
      expect(minuteLabel(0), '12:00 AM');
      expect(minuteLabel(930), '3:30 PM');
      expect(minuteLabel(720), '12:00 PM');
      expect(minuteLabel(1425), '11:45 PM');
    });
  });

  group('the gentle ending, on her device', () {
    const w = PlayWindow(opensMin: 930, restsMin: 1140, windDownMin: 30);
    Widget gate(MemoryColourStore s) => app(PlayWindowGate(store: s, child: const Scaffold(body: Text('the games'))));

    testWidgets('open: the games, untouched', (t) async {
      await t.pumpWidget(gate(store(at: DateTime(2026, 11, 7, 16, 0), window: w)));
      await t.pumpAndSettle();
      expect(find.text('the games'), findsOneWidget);
      expect(find.byKey(const Key('windDownBanner')), findsNothing);
    });

    testWidgets('winding down: the games stay, with one calm line and no number', (t) async {
      await t.pumpWidget(gate(store(at: DateTime(2026, 11, 7, 18, 40), window: w)));
      await t.pumpAndSettle();
      expect(find.text('the games'), findsOneWidget, reason: 'a game in progress is never cut off');
      expect(find.text('It’s getting sleepy. One more, then goodnight.'), findsOneWidget);
    });

    testWidgets('resting: a goodnight card that promises tomorrow, with no lock, timer or red', (t) async {
      await t.pumpWidget(gate(store(at: DateTime(2026, 11, 7, 19, 30), window: w)));
      await t.pumpAndSettle();
      expect(find.text('the games'), findsNothing);
      final line = t.widget<Text>(find.byKey(const Key('goodnightLine'))).data!;
      expect(line, contains('tomorrow'));
      expect(line, isNot(matches(RegExp(r'\d|timer|locked|limit|no more', caseSensitive: false))));
    });

    testWidgets('no window set: always open', (t) async {
      await t.pumpWidget(gate(store(at: DateTime(2026, 11, 7, 23, 0))));
      await t.pumpAndSettle();
      expect(find.text('the games'), findsOneWidget);
    });

    test('the gate gates games only: it imports no call, message or inbox code', () {
      final src = File('lib/play_window_gate.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      for (final bad in ['call_', 'inbox', 'message', 'push_', 'guardian_']) {
        expect(src.contains("'$bad"), isFalse, reason: bad);
      }
    });
  });

  group('the Settings hub', () {
    Widget hub(List<SettingsGroup> groups) => app(GuardianSettingsHubScreen(childName: 'Ivy', groups: groups));
    SettingsRow row(String id, String title, String sub, VoidCallback onTap) =>
        SettingsRow(id: id, icon: Icons.circle, title: title, subtitle: sub, onTap: onTap);

    testWidgets('groups are titled plainly, and the banner says her app has none', (t) async {
      await big(t);
      await t.pumpWidget(hub([SettingsGroup('Her', [row('a', 'Colour and art', 'x', () {})]), SettingsGroup('Safety', [row('b', 'Play window', 'y', () {})])]));
      expect(find.text('HER'), findsOneWidget);
      expect(find.text('SAFETY'), findsOneWidget);
      expect(find.text('Ivy never sees these settings. Her app has none.'), findsOneWidget);
    });

    testWidgets('search narrows rows, and says when nothing matches', (t) async {
      await big(t);
      await t.pumpWidget(hub([SettingsGroup('Her', [row('a', 'Colour and art', 'x', () {})]), SettingsGroup('Safety', [row('b', 'Play window', 'bedtime', () {})])]));
      await t.enterText(find.byKey(const Key('settingsSearch')), 'bedtime');
      await t.pump();
      expect(find.byKey(const Key('settingsRow_b')), findsOneWidget);
      expect(find.byKey(const Key('settingsRow_a')), findsNothing);
      await t.enterText(find.byKey(const Key('settingsSearch')), 'zzz');
      await t.pump();
      expect(find.byKey(const Key('settingsNoMatch')), findsOneWidget);
    });

    testWidgets('a row calls what it was given', (t) async {
      await big(t);
      var hit = 0;
      await t.pumpWidget(hub([SettingsGroup('Her', [row('a', 'Colour and art', 'x', () => hit++)])]));
      await t.tap(find.byKey(const Key('settingsRow_a')));
      expect(hit, 1);
    });

    Future<void> openHub(WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(const GuardianMoreScreen(childName: 'Ivy', childAge: 6)));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('moreSettings')));
      await t.tap(find.byKey(const Key('moreSettings')));
      await t.pumpAndSettle();
    }

    testWidgets('reachable from More, with all five groups', (t) async {
      await openHub(t);
      for (final g in ['HER', 'FAMILY', 'SAFETY', 'LEARN', 'ACCOUNT']) {
        expect(find.text(g), findsOneWidget, reason: g);
      }
    });

    testWidgets('Her: Colour and art opens the real guardian screen', (t) async {
      await openHub(t);
      await t.tap(find.byKey(const Key('settingsRow_colour')));
      await t.pumpAndSettle();
      expect(find.byType(HerColourGuardianScreen), findsOneWidget);
    });

    testWidgets('Safety: the play window opens, and parental controls says it needs a live session offline', (t) async {
      await openHub(t);
      await t.tap(find.byKey(const Key('settingsRow_window')));
      await t.pumpAndSettle();
      expect(find.byType(PlayWindowScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settingsRow_controls')));
      await t.pump();
      expect(find.textContaining('needs a live session'), findsWidgets);
    });

    testWidgets('Her: the age band explains itself and offers nothing to set', (t) async {
      await openHub(t);
      await t.tap(find.byKey(const Key('settingsRow_age')));
      await t.pumpAndSettle();
      expect(find.textContaining('there is nothing to set here yet'), findsOneWidget);
    });

    testWidgets('Learn and Family rows open the existing screens', (t) async {
      await openHub(t);
      await t.tap(find.byKey(const Key('settingsRow_learn')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settingsRow_learn')), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settingsRow_adults')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settingsRow_adults')), findsNothing);
    });

    test('there is no bottom tab bar: the hub is reached from More, and says why', () {
      final src = File('lib/guardian_settings_hub.dart').readAsStringSync();
      expect(src.contains('BottomNavigationBar'), isFalse);
      expect(src.contains('NavigationBar('), isFalse);
      expect(src.contains('It is a HUB, not a tab bar'), isTrue);
    });
  });

  group('the child shell stays free of controls (§8.1)', () {
    final childFiles = ['her_colour_home', 'colour_sort_screen', 'path_code_screen', 'colour_critter_screen',
      'pixel_garden_screen', 'play_window_gate', 'child_more'];
    test('Play together stands behind the gate, live and offline', () {
      final src = File('lib/child_home.dart').readAsStringSync();
      expect(src.contains('PlayWindowGate(child: LiveGamePickerScreen('), isTrue);
      expect(src.contains('PlayWindowGate(child: GamePickerScreen('), isTrue);
    });

    for (final f in childFiles) {
      test('$f has no settings word in anything she can read, and imports nothing guardian-facing', () {
        final src = File('lib/$f.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
        final literals = RegExp(r'''('([^'\\]|\\.)*')|("([^"\\]|\\.)*")''').allMatches(src).map((m) => m[0]!);
        expect([for (final l in literals) if (RegExp('settings', caseSensitive: false).hasMatch(l)) l], isEmpty);
        for (final bad in ['her_colour_guardian', 'play_window_screen', 'guardian_settings_hub', 'guardian_more', 'theme_picker_screen']) {
          expect(src.contains("'$bad.dart'"), isFalse, reason: bad);
        }
      });
    }
  });
}
