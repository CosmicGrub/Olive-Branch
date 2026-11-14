// OLIVE BRANCH — Wave 3 (guardian home and settings hub) parity with the live prototype.
// No longer UNVERIFIED — verified by CI (this file). MASTERFILE §8.1, §8.2, §8.5.7, §8.6.
//
// What it holds:
//   * the settings hub's groups, order and titles against the prototype's own list
//     (test/parity/vectors/settings_hub_prototype.json), so the hub cannot drift silently;
//   * "Ivy calls you" (ob.names): read-only, her word, never a setter;
//   * the age planner (g-planner): the real band table, per-age hold and reminder, kept;
//   * Change PIN on this device (g-pin / ob.pinInfo): current, new, confirm, easy guesses
//     and the same PIN refused, five wrong tries pause it for 15 minutes;
//   * the guardian home's one state sentence and its honest fallbacks (stateLine);
//   * the prohibitions the new screens touch (no counts or scores, nothing about what she did,
//     journal and worry box and feelings weather never in a guardian file, none of this
//     reachable from her shell);
//   * posture: every new or changed screen at 344, 390, 600 and 800 dp and at 2.0x text.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/adults_helpers_screen.dart';
import 'package:olive_client/age_planner_screen.dart';
import 'package:olive_client/calendar_day_logic.dart' show dayPartLabel;
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/guardian_names_screen.dart';
import 'package:olive_client/guardian_settings_hub.dart';
import 'package:olive_client/guardian_state_line.dart';
import 'package:olive_client/home_plan_store.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_pin_screens.dart';

Map<String, Object?> _vector() =>
    jsonDecode(File('test/parity/vectors/settings_hub_prototype.json').readAsStringSync()) as Map<String, Object?>;

List<Map<String, Object?>> _rows() =>
    <Map<String, Object?>>[for (final Object? r in _vector()['rows']! as List<Object?>) r! as Map<String, Object?>];

LocalFamily _family({int age = 7}) => LocalFamily.fromAnswers(
    guardianName: 'Jess', guardianLabel: 'Mom', guardianKind: GrownupKind.mom, childName: 'Ivy', age: age);

Future<void> _size(WidgetTester t, double w, {double h = 3200}) async {
  await t.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

Widget _scaled(Widget child, {double scale = 1.0}) => MaterialApp(
    builder: (BuildContext c, Widget? w) =>
        MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
    home: child);

String _stripped(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//.*'), '');

void main() {
  group('the settings hub follows the prototype\'s groups, order and titles', () {
    late GuardianLocalController ctl;
    setUp(() {
      final GuardianLocalServices services = GuardianLocalServices.memory(pinIterations: 500, family: _family());
      ctl = GuardianLocalController(services, family: _family());
    });

    Future<List<SettingsGroup>> hubGroups(WidgetTester t) async {
      await _size(t, 800, h: 3000);
      await t.pumpWidget(MaterialApp(
        builder: (BuildContext c, Widget? child) => GuardianLocalScope(controller: ctl, child: child!),
        home: const GuardianMoreScreen(childName: 'Ivy', childAge: 7),
      ));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('moreSettings')));
      await t.tap(find.byKey(const Key('moreSettings')));
      await t.pumpAndSettle();
      return t.widget<GuardianSettingsHubScreen>(find.byType(GuardianSettingsHubScreen)).groups;
    }

    testWidgets('same five groups, in the prototype\'s order', (t) async {
      final List<SettingsGroup> groups = await hubGroups(t);
      expect(groups.map((SettingsGroup g) => g.title).toList(), (_vector()['groups']! as List<Object?>).cast<String>());
    });

    testWidgets('every prototype row that Flutter builds is in its group, in the same relative order, with the same title', (t) async {
      final List<SettingsGroup> groups = await hubGroups(t);
      for (final SettingsGroup g in groups) {
        final List<Map<String, Object?>> proto = <Map<String, Object?>>[
          for (final Map<String, Object?> r in _rows())
            if (r['group'] == g.title && r['flutter'] != null) r,
        ];
        int last = -1;
        for (final Map<String, Object?> p in proto) {
          final int at = g.rows.indexWhere((SettingsRow r) => r.id == p['flutter']);
          expect(at, greaterThanOrEqualTo(0), reason: '${p['proto']} (${p['flutter']}) is missing from ${g.title}');
          expect(at, greaterThan(last), reason: '${p['proto']} is out of order in ${g.title}');
          last = at;
          expect(g.rows[at].title, (p['title']! as String).replaceAll('{child}', 'Ivy'), reason: '${p['proto']}');
        }
      }
    });

    testWidgets('every row is either the prototype\'s or a named Flutter-only row (nothing unaccounted for)', (t) async {
      final List<SettingsGroup> groups = await hubGroups(t);
      final Map<String, Object?> v = _vector();
      final Set<String> known = <String>{
        for (final Map<String, Object?> r in _rows())
          if (r['flutter'] != null) r['flutter']! as String,
        ...(v['flutterOnly']! as List<Object?>).cast<String>(),
      };
      final Set<String> built = <String>{for (final SettingsGroup g in groups) for (final SettingsRow r in g.rows) r.id};
      expect(built.difference(known), isEmpty, reason: 'add these to the vector with a reason');
      for (final String id in (v['flutterOnly']! as List<Object?>).cast<String>()) {
        if (id == 'connect') continue; // only when the build can connect
        if (id == 'phones') continue; // only where the guardian shell supplied the local recovery services
        expect(built.contains(id), isTrue, reason: id);
      }
    });

    testWidgets('prototype rows with no Flutter row each say why', (t) async {
      for (final Map<String, Object?> m in _rows()) {
        if (m['flutter'] == null) expect((m['why'] as String?)?.length ?? 0, greaterThan(20), reason: '${m['proto']}');
      }
    });

    testWidgets('Messages can never be hidden: Parental controls says so, in the hub row itself', (t) async {
      final List<SettingsGroup> groups = await hubGroups(t);
      final SettingsRow controls = groups.firstWhere((g) => g.title == 'Safety').rows.firstWhere((r) => r.id == 'controls');
      // Offline the row is an honest "needs a live session"; live it names the rule.
      expect(controls.subtitle, contains('live session'));
      final String src = _stripped('lib/guardian_more.dart');
      expect(src.contains('Messages are always on'), isTrue);
    });

    testWidgets('network-only rows are honest offline: a live-session line, and a tap opens nothing fake', (t) async {
      final List<SettingsGroup> groups = await hubGroups(t);
      for (final String id in <String>['devices', 'addtablet', 'controls']) {
        final SettingsRow r = groups.expand((g) => g.rows).firstWhere((r) => r.id == id);
        expect(r.subtitle, 'Needs a live session', reason: id);
      }
      await t.tap(find.byKey(const Key('settingsRow_addtablet')));
      await t.pump();
      expect(find.textContaining('needs a live session'), findsWidgets);
    });

    testWidgets('the family rows open the real screens: structure, history, weekly rhythm', (t) async {
      await hubGroups(t);
      for (final String id in <String>['family', 'history', 'weekly']) {
        await t.ensureVisible(find.byKey(Key('settingsRow_$id')));
        await t.tap(find.byKey(Key('settingsRow_$id')));
        await t.pumpAndSettle();
        expect(find.byKey(Key('settingsRow_$id')), findsNothing, reason: '$id opened a screen');
        await t.pageBack();
        await t.pumpAndSettle();
      }
    });
  });

  group('"Ivy calls you" (ob.names)', () {
    testWidgets('shows her word: the age default once the age is locked, her own word if she chose one', (t) async {
      await _size(t, 390);
      final MemoryNicknameRepository nicks = MemoryNicknameRepository();
      await t.pumpWidget(MaterialApp(home: GuardianNamesScreen(childName: 'Ivy', family: _family(), nicknames: nicks)));
      await t.pumpAndSettle();
      expect(find.text('Jess (Mom)'), findsOneWidget);
      expect(find.text('Ivy calls you Mommy'), findsOneWidget);
      await nicks.set(kLocalGuardianContactId, 'Dada');
      await t.pumpWidget(MaterialApp(home: GuardianNamesScreen(key: UniqueKey(), childName: 'Ivy', family: _family(), nicknames: nicks)));
      await t.pumpAndSettle();
      expect(find.text('Ivy calls you Dada'), findsOneWidget);
      expect(find.textContaining('Only she can change what she calls you'), findsOneWidget);
    });

    testWidgets('has no setter: it takes a NicknameReader, and offers no field or button', (t) async {
      await _size(t, 390);
      await t.pumpWidget(MaterialApp(home: GuardianNamesScreen(childName: 'Ivy', family: _family(), nicknames: MemoryNicknameRepository())));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      final String src = _stripped('lib/guardian_names_screen.dart');
      expect(src.contains('.set('), isFalse, reason: 'a guardian screen never writes her words (P5)');
    });

    testWidgets('no local family: an honest empty state, nothing invented', (t) async {
      await _size(t, 390);
      await t.pumpWidget(MaterialApp(home: GuardianNamesScreen(childName: 'Ivy', family: null, nicknames: MemoryNicknameRepository())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('namesNoFamily')), findsOneWidget);
      expect(find.text('Ivy calls you'), findsOneWidget, reason: 'only the title, no invented row');
    });
  });

  group('the age planner (g-planner)', () {
    testWidgets('one card per age from the real band table, hold on by default, reminder off', (t) async {
      await _size(t, 390, h: 4200);
      final MemoryHomePlanRepository repo = MemoryHomePlanRepository();
      await t.pumpWidget(MaterialApp(home: AgePlannerScreen(childName: 'Ivy', childAge: 9, repository: repo)));
      await t.pumpAndSettle();
      expect(find.text('A plan, not a schedule. Nothing here moves until she reaches the age and you say so.'), findsOneWidget);
      for (final int age in plannerAges) {
        expect(find.byKey(Key('plannerBand_$age')), findsOneWidget);
        expect(find.text('From age $age'), findsOneWidget);
        for (final String line in bandDef(plannerBandOfAge[age]!).summary) {
          expect(find.text('• $line'), findsOneWidget, reason: line);
        }
      }
      expect(find.byKey(const Key('plannerHere_8')), findsOneWidget, reason: 'Ivy is 9: she is in the 8 to 12 band');
      expect(find.byKey(const Key('plannerHere_5')), findsNothing);
    });

    testWidgets('a toggle is kept, and says honestly what is live', (t) async {
      await _size(t, 390, h: 4200);
      final MemoryHomePlanRepository repo = MemoryHomePlanRepository();
      await t.pumpWidget(MaterialApp(home: AgePlannerScreen(childName: 'Ivy', childAge: 6, repository: repo)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('plannerHold_8')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('plannerRemind_13')));
      await t.pumpAndSettle();
      final HomePlan p = await repo.load();
      expect(p.holdWhenArrives(8), isFalse);
      expect(p.holdWhenArrives(5), isTrue);
      expect(p.remindBefore(13), isTrue);
      expect(find.text('Saved on this device.'), findsOneWidget);
      expect(find.textContaining('not built yet'), findsOneWidget, reason: 'a reminder needs notifications: say so');
      expect(find.textContaining('the one on the Age bands screen'), findsOneWidget);
    });

    testWidgets('a save that fails is said, not hidden', (t) async {
      await _size(t, 390, h: 4200);
      final MemoryHomePlanRepository repo = MemoryHomePlanRepository()..failSaves = true;
      await t.pumpWidget(MaterialApp(home: AgePlannerScreen(childName: 'Ivy', childAge: 6, repository: repo)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('plannerHold_5')));
      await t.pumpAndSettle();
      expect(find.textContaining('could not keep it'), findsOneWidget);
    });
  });

  group('Adults and helpers (g-adults)', () {
    testWidgets('lists the grown-ups, reaches the builder and the helpers, and the invite is a preview', (t) async {
      await _size(t, 390, h: 2000);
      final List<String> hit = <String>[];
      await t.pumpWidget(MaterialApp(home: AdultsHelpersScreen(
        childName: 'Ivy',
        grownupLines: const <String>['Jess (Mom)'],
        onChangePeople: () => hit.add('people'),
        onHelpers: () => hit.add('helpers'),
        onInvitePreview: () => hit.add('invite'),
      )));
      expect(find.text('Jess (Mom)'), findsOneWidget);
      for (final String k in <String>['adultsChangePeople', 'adultsHelpers', 'adultsInvite']) {
        await t.tap(find.byKey(Key(k)));
      }
      expect(hit, <String>['people', 'helpers', 'invite']);
      expect(find.text('Invite a co-parent (preview)'), findsOneWidget);
      expect(find.textContaining('Nothing is sent'), findsOneWidget);
      expect(find.textContaining('not sent, saved by the sitter or shared as a link'), findsOneWidget);
    });
  });

  group('Change PIN on this device (g-pin, ob.pinInfo)', () {
    late LocalPinService pin;
    setUp(() => pin = LocalPinService(MemoryLocalPinRepository(), iterations: 500));

    Future<void> fill(WidgetTester t, {String cur = '', String neu = '', String conf = ''}) async {
      await t.enterText(find.byKey(const Key('pinChangeCurrent')), cur);
      await t.enterText(find.byKey(const Key('pinChangeNew')), neu);
      await t.enterText(find.byKey(const Key('pinChangeConfirm')), conf);
    }

    Future<void> submit(WidgetTester t) async {
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('pinChangeSave')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
    }

    testWidgets('explains itself: what the PIN guards, a child can never change it, five tries then 15 minutes', (t) async {
      await _size(t, 390);
      await t.pumpWidget(MaterialApp(home: LocalPinChangeScreen(service: pin)));
      expect(find.byKey(const Key('pinInfoCard')), findsOneWidget);
      expect(find.textContaining('A child can never make or change one'), findsOneWidget);
      expect(find.textContaining('Five wrong tries pause it for 15 minutes'), findsOneWidget);
    });

    testWidgets('refuses the same PIN, an easy guess, a mismatch and a short one, before touching the PIN', (t) async {
      await _size(t, 390);
      await t.runAsync(() => pin.setPin('4829'));
      await t.pumpWidget(MaterialApp(home: LocalPinChangeScreen(service: pin)));
      Future<String> errorFor({String cur = '4829', String neu = '', String conf = ''}) async {
        await fill(t, cur: cur, neu: neu, conf: conf);
        await submit(t);
        return t.widget<Text>(find.byKey(const Key('pinChangeError'))).data!;
      }
      expect(await errorFor(neu: '4829', conf: '4829'), contains('different from the current one'));
      expect(await errorFor(neu: '1234', conf: '1234'), contains('easy to guess'));
      expect(await errorFor(neu: '1111', conf: '1111'), contains('easy to guess'));
      expect(await errorFor(neu: '7391', conf: '7392'), contains("don't match"));
      expect(await errorFor(neu: '73', conf: '73'), contains('4-8 digit'));
      expect((await t.runAsync(() => pin.verify('4829')))!.ok, isTrue, reason: 'nothing changed');
    });

    testWidgets('a right current PIN changes it; the old one stops working', (t) async {
      await _size(t, 390);
      await t.runAsync(() => pin.setPin('4829'));
      var changed = 0;
      await t.pumpWidget(MaterialApp(home: LocalPinChangeScreen(service: pin, onChanged: () => changed++)));
      await fill(t, cur: '4829', neu: '7391', conf: '7391');
      await submit(t);
      expect(find.byKey(const Key('pinChangeDone')), findsOneWidget);
      expect(changed, 1);
      expect((await t.runAsync(() => pin.verify('7391')))!.ok, isTrue);
      expect((await t.runAsync(() => pin.verify('4829')))!.ok, isFalse);
    });

    testWidgets('a wrong current PIN counts toward the lock, and five wrong tries pause it', (t) async {
      await _size(t, 390);
      await t.runAsync(() => pin.setPin('4829'));
      await t.pumpWidget(MaterialApp(home: LocalPinChangeScreen(service: pin)));
      await fill(t, cur: '0000', neu: '7391', conf: '7391');
      await submit(t);
      expect(t.widget<Text>(find.byKey(const Key('pinChangeError'))).data, contains('4 tries left'));
      for (int i = 0; i < 4; i++) {
        await fill(t, cur: '0000', neu: '7391', conf: '7391');
        await submit(t);
      }
      expect(t.widget<Text>(find.byKey(const Key('pinChangeError'))).data, kLocalPinLockedMessage);
      // Even the right PIN is refused while paused.
      await fill(t, cur: '4829', neu: '7391', conf: '7391');
      await submit(t);
      expect(t.widget<Text>(find.byKey(const Key('pinChangeError'))).data, kLocalPinLockedMessage);
    });
  });

  group('the guardian home\'s one sentence (stateLine)', () {
    test('a real sentence wins', () {
      expect(guardianStateLine(childName: 'Ivy', sentence: 'Ivy is just home', connected: false), 'Ivy is just home');
    });
    test('otherwise, in priority: not connected, offline, then the part of her day', () {
      expect(guardianStateLine(childName: 'Ivy', connected: false, dayPart: 'school'), contains('isn’t connected yet'));
      expect(guardianStateLine(childName: 'Ivy', connected: true), contains('You are offline'));
      expect(guardianStateLine(childName: 'Ivy', connected: true, dayPart: 'after_school'),
          'It is ${dayPartLabel('after_school').toLowerCase()} for Ivy.');
    });
    test('a blank sentence is not a sentence', () {
      expect(guardianStateLine(childName: 'Ivy', sentence: '  ', connected: false), contains('isn’t connected yet'));
    });
    test('it never claims a mood, a place or a status it was not given', () {
      for (final String s in <String>[
        guardianStateLine(childName: 'Ivy', connected: false),
        guardianStateLine(childName: 'Ivy', connected: true),
        guardianStateLine(childName: 'Ivy', connected: true, dayPart: 'wake'),
      ]) {
        expect(s.toLowerCase(), isNot(matches(RegExp(r'happy|sad|upset|at (school|home|dad|mom)|location|where'))), reason: s);
      }
    });

    testWidgets('GuardianHome always shows it, with no sentence supplied', (t) async {
      await _size(t, 390, h: 2400);
      await t.pumpWidget(const MaterialApp(home: GuardianHome(
        childName: 'Ivy', childLocalTime: '4:12 PM', childZoneAbbr: 'CT', actorLocalTime: '5:12 PM ET',
        childBands: <RibbonBand>[], actorBands: <RibbonBand>[])));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('guardianStateLine'))).data, contains('isn’t connected yet'));
      // Her time and your time, both on screen.
      expect(find.text('4:12 PM'), findsOneWidget);
      expect(find.textContaining('you · 5:12 PM ET'), findsOneWidget);
    });
  });

  group('prohibitions the new screens touch', () {
    final List<String> newFiles = <String>[
      'lib/guardian_names_screen.dart', 'lib/age_planner_screen.dart', 'lib/adults_helpers_screen.dart',
      'lib/guardian_state_line.dart', 'lib/home_plan_store.dart', 'lib/play_window_screen.dart',
    ];

    test('journal, worry box and feelings weather appear in none of them (P7)', () {
      for (final String f in newFiles) {
        final String src = _stripped(f).toLowerCase();
        for (final String bad in <String>['journal', 'worry', 'feelings', 'weather_', 'wellbeing']) {
          expect(src.contains("'$bad") || src.contains('import \'$bad'), isFalse, reason: '$f imports $bad');
          expect(RegExp("import '[a-z_]*$bad[a-z_]*\\.dart'").hasMatch(src), isFalse, reason: '$f imports $bad');
        }
      }
    });

    test('no count, score, streak or location in any word the new guardian screens say (P2, P3)', () {
      for (final String f in newFiles) {
        final String src = _stripped(f);
        final Iterable<String> literals = RegExp(r"'([^'\\]|\\.)*'").allMatches(src).map((m) => m[0]!.toLowerCase());
        for (final String l in literals) {
          expect(l, isNot(matches(RegExp(r'\bstreak\b|\bscore\b|\bleaderboard\b|latitude|longitude|gps'))), reason: '$f: $l');
        }
      }
    });

    test('her shell reaches none of the new guardian screens or the plan store (§8.1)', () {
      final List<String> childFiles = <String>[
        for (final FileSystemEntity e in Directory('lib').listSync())
          if (e is File && RegExp(r'[/\\](child_[a-z0-9_]*|kiosk_shell|her_colour_home|play_window_gate)\.dart$').hasMatch(e.path)) e.path,
      ];
      expect(childFiles, isNotEmpty);
      for (final String f in childFiles) {
        final String src = _stripped(f);
        for (final String bad in <String>[
          'guardian_names_screen', 'age_planner_screen', 'adults_helpers_screen', 'guardian_state_line',
          'home_plan_store', 'play_window_screen', 'local_pin_screens',
        ]) {
          expect(src.contains("'$bad.dart'"), isFalse, reason: '$f imports $bad');
        }
      }
    });

    test('the plan store records no minutes, sessions or tallies of what she did (P2)', () {
      final String src = _stripped('lib/home_plan_store.dart');
      for (final String bad in <String>['minutesUsed', 'sessions', 'tally', 'streak', 'usage']) {
        expect(src.contains(bad), isFalse, reason: bad);
      }
    });
  });

  group('posture: 344, 390, 600 and 800 dp, at 1.0x and 2.0x text, with no overflow', () {
    for (final double w in <double>[344, 390, 600, 800]) {
      for (final double scale in <double>[1.0, 2.0]) {
        final String at = '$w dp ${scale}x';

        testWidgets('planner, names, adults and PIN change at $at', (t) async {
          await _size(t, w, h: 5200);
          for (final Widget screen in <Widget>[
            AgePlannerScreen(childName: 'Ivy', childAge: 9, repository: MemoryHomePlanRepository()),
            GuardianNamesScreen(childName: 'Ivy', family: _family(), nicknames: MemoryNicknameRepository()),
            AdultsHelpersScreen(childName: 'Ivy', grownupLines: const <String>['Jess (Mom)', 'Marcus (Dad)'],
                onChangePeople: () {}, onHelpers: () {}, onInvitePreview: () {}),
            LocalPinChangeScreen(service: LocalPinService(MemoryLocalPinRepository(), iterations: 500)),
          ]) {
            await t.pumpWidget(_scaled(screen, scale: scale));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: '${screen.runtimeType} at $at');
          }
        });

        testWidgets('the settings hub at $at', (t) async {
          await _size(t, w, h: 6000);
          final GuardianLocalServices services = GuardianLocalServices.memory(pinIterations: 500, family: _family());
          final GuardianLocalController ctl = GuardianLocalController(services, family: _family());
          await t.pumpWidget(MaterialApp(
            builder: (BuildContext c, Widget? child) => GuardianLocalScope(
                controller: ctl,
                child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
            home: const GuardianMoreScreen(childName: 'Ivy', childAge: 7),
          ));
          await t.pumpAndSettle();
          await t.ensureVisible(find.byKey(const Key('moreSettings')));
          await t.tap(find.byKey(const Key('moreSettings')));
          await t.pumpAndSettle();
          expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
          expect(t.takeException(), isNull, reason: 'hub at $at');
        });

        testWidgets('the guardian home with its fallback sentence at $at', (t) async {
          await _size(t, w, h: 2600);
          final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
          final void Function(FlutterErrorDetails)? old = FlutterError.onError;
          FlutterError.onError = errors.add;
          addTearDown(() => FlutterError.onError = old);
          await t.pumpWidget(_scaled(const GuardianHome(
            childName: 'Ivy', childLocalTime: '4:12 PM', childZoneAbbr: 'CT', actorLocalTime: '5:12 PM ET',
            childBands: <RibbonBand>[], actorBands: <RibbonBand>[]), scale: scale));
          await t.pumpAndSettle();
          FlutterError.onError = old;
          expect(errors.map((e) => e.exceptionAsString()).toList(), isEmpty, reason: 'home at \$at');
          expect(find.byKey(const Key('guardianStateLine')), findsOneWidget);
        });
      }
    }
  });
}
