// OLIVE BRANCH — "Her day" on screen: view and edit the child's day-parts in plain words. Headless, against a stand-in
// written from the real routes. MASTERFILE section 8.31.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/day_parts_editor_screen.dart';
import 'package:olive_client/day_parts_service.dart';

import 'support/fake_delivery_server.dart';

Widget app(FakeDeliveryServer s, {Size size = const Size(400, 900), double scale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: DayPartsEditorScreen(
          childName: 'Mia',
          service: DayPartsService(
              childId: kChild, closeApi: false, openApi: () async => OliveApi(kBase, 'tok', client: s.client)),
        ),
      ),
    );

Future<void> settle(WidgetTester t) async {
  for (int i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> pickFrom(WidgetTester t, Key dropdown, String text) async {
  await t.ensureVisible(find.byKey(dropdown));
  await t.tap(find.byKey(dropdown));
  await t.pumpAndSettle();
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows the day in adult words, in her clock, and says the seeded times are only a guess', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer();
    await t.pumpWidget(app(s));
    await settle(t);
    expect(find.text("Mia's day"), findsOneWidget);
    expect(find.byKey(const Key('dayPlaceholder')), findsOneWidget);
    expect(find.textContaining('starting guess'), findsOneWidget);
    expect(find.text('Bedtime'), findsOneWidget);
    expect(find.textContaining('7:30 PM to 8:30 PM'), findsOneWidget);
    expect(find.textContaining('8:30 PM to 6:30 AM the next morning'), findsOneWidget);
    expect(find.textContaining('quiet: no buzzing'), findsOneWidget);
    expect(find.text('Waking up'), findsOneWidget);
    // nothing to save yet
    expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNull);
    // no raw codes
    expect(find.textContaining('wind_down'), findsNothing);
    expect(find.textContaining('asleep'), findsNothing);
  });

  testWidgets('a day that is not the seeded guess shows no guess banner', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer();
    s.dayParts = <Map<String, dynamic>>[
      for (final Map<String, dynamic> p in s.dayParts) p['kind'] == 'bedtime' ? <String, dynamic>{...p, 'startsLocal': '19:45'} : p,
    ];
    await t.pumpWidget(app(s));
    await settle(t);
    expect(find.byKey(const Key('dayPlaceholder')), findsNothing);
  });

  testWidgets('change the bedtime start, save, and the server holds it; the guess banner goes', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer();
    await t.pumpWidget(app(s));
    await settle(t);
    await t.tap(find.text('Bedtime'));
    await settle(t);
    expect(find.text('Change this part'), findsOneWidget);
    await pickFrom(t, const Key('partStartMinute'), '45');
    await pickFrom(t, const Key('partStartHour'), '7');
    await t.tap(find.byKey(const Key('partDone')));
    await settle(t);
    expect(find.textContaining('7:45 PM to 8:30 PM'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('daySave')));
    await settle(t);
    expect(find.textContaining('Saved. Anything still waiting to arrive will be timed again'), findsOneWidget);
    final Map<String, dynamic> bed =
        s.dayParts.firstWhere((Map<String, dynamic> p) => p['kind'] == 'bedtime');
    expect(bed['startsLocal'], '19:45');
    expect(find.byKey(const Key('dayPlaceholder')), findsNothing);
    expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNull, reason: 'nothing left to save');
  });

  testWidgets('the time dropdowns make a wall clock: 9:05 PM is 21:05, 12:00 AM is 00:00', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer();
    await t.pumpWidget(app(s));
    await settle(t);
    await t.tap(find.byKey(const Key('dayAdd')));
    await settle(t);
    expect(find.text('Add a part of her day'), findsOneWidget);
    await pickFrom(t, const Key('partStartAmpm'), 'PM');
    await pickFrom(t, const Key('partStartHour'), '9');
    await pickFrom(t, const Key('partStartMinute'), '05');
    await pickFrom(t, const Key('partEndHour'), '12');
    await pickFrom(t, const Key('partEndAmpm'), 'AM');
    await pickFrom(t, const Key('partEndMinute'), '00');
    expect(find.textContaining('past midnight'), findsOneWidget);
    await t.tap(find.byKey(const Key('partDone')));
    await settle(t);
    await t.ensureVisible(find.byKey(const Key('daySave')));
    await t.tap(find.byKey(const Key('daySave')));
    await settle(t);
    final Map<String, dynamic> added = s.dayParts.firstWhere(
        (Map<String, dynamic> p) => p['kind'] == 'free' && p['startsLocal'] == '21:05');
    expect(added['endsLocal'], '00:00');
  });

  testWidgets('a part that would overlap its own kind is stopped in the dialog and in the list, in words', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer();
    await t.pumpWidget(app(s));
    await settle(t);
    await t.tap(find.byKey(const Key('dayAdd')));
    await settle(t);
    await pickFrom(t, const Key('partKind'), 'Bedtime');
    // 9:00 AM to 10:00 AM is the default; make the new bedtime overlap the real one by starting at 7:30 PM
    await pickFrom(t, const Key('partStartAmpm'), 'PM');
    await pickFrom(t, const Key('partStartHour'), '7');
    await pickFrom(t, const Key('partStartMinute'), '30');
    await pickFrom(t, const Key('partEndAmpm'), 'PM');
    await pickFrom(t, const Key('partEndHour'), '8');
    await t.tap(find.byKey(const Key('partDone')));
    await settle(t);
    expect(find.byKey(const Key('dayProblem')), findsOneWidget);
    expect(find.textContaining('Bedtime is set twice'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNull);
    await t.tap(find.byKey(const Key('dayUndo')));
    await settle(t);
    expect(find.byKey(const Key('dayProblem')), findsNothing);
    expect(s.putCount, 0);
  });

  testWidgets('removing the bedtime is allowed, and says plainly what that means', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer();
    await t.pumpWidget(app(s));
    await settle(t);
    await t.tap(find.byKey(Key('dayRemove_bedtime_${'19:30'}')));
    await settle(t);
    expect(find.byKey(const Key('dayNote')), findsOneWidget);
    expect(find.textContaining('no bedtime'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNotNull);
  });

  testWidgets('someone else changed her day: nothing is saved, what is there now is shown, and they are told', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer();
    await t.pumpWidget(app(s));
    await settle(t);
    await t.tap(find.byKey(Key('dayRemove_wake_${'06:30'}')));
    await settle(t);
    s.dayParts = <Map<String, dynamic>>[
      for (final Map<String, dynamic> p in s.dayParts) p['kind'] == 'bedtime' ? <String, dynamic>{...p, 'startsLocal': '19:00'} : p,
    ];
    await t.ensureVisible(find.byKey(const Key('daySave')));
    await t.tap(find.byKey(const Key('daySave')));
    await settle(t);
    expect(find.textContaining('Someone changed her day'), findsOneWidget);
    expect(s.putCount, 0);
    expect(find.textContaining('7:00 PM to 8:30 PM'), findsOneWidget, reason: 'the other parent\'s bedtime is what is shown now');
    expect(find.text('Waking up'), findsOneWidget, reason: 'the editor was reset to what is there, not left half-edited');
  });

  testWidgets('a save that fails says nothing was changed, and does not retry', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer();
    await t.pumpWidget(app(s));
    await settle(t);
    await t.tap(find.byKey(Key('dayRemove_wake_${'06:30'}')));
    await settle(t);
    s.offline = true;
    await t.ensureVisible(find.byKey(const Key('daySave')));
    await t.tap(find.byKey(const Key('daySave')));
    await settle(t);
    expect(find.textContaining('could not reach the server'), findsOneWidget);
    expect(find.textContaining('Saved.'), findsNothing);
    expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNotNull, reason: 'they can try again');
    expect(s.putCount, 0);
  });

  testWidgets('cannot read her day: an honest message and Try again, never an empty editable schedule', (t) async {
    final FakeDeliveryServer s = FakeDeliveryServer()..offline = true;
    await t.pumpWidget(app(s));
    await settle(t);
    expect(find.byKey(const Key('dayLoadError')), findsOneWidget);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(find.byKey(const Key('dayAdd')), findsNothing);
    s.offline = false;
    await t.tap(find.byKey(const Key('dayRetry')));
    await settle(t);
    expect(find.byKey(const Key('dayAdd')), findsOneWidget);
    // and a reply that is not a schedule
    final FakeDeliveryServer bad = FakeDeliveryServer();
    bad.dayParts = <Map<String, dynamic>>[<String, dynamic>{'kind': 'free'}];
    await t.pumpWidget(app(bad));
    await settle(t);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.byKey(const Key('dayAdd')), findsNothing);
  });

  for (final (String label, Size size, double scale) in <(String, Size, double)>[
    ('fold5 cover at 2x text', const Size(344, 820), 2.0),
    ('phone', const Size(390, 844), 1.0),
    ('tablet', const Size(1100, 800), 1.3),
  ]) {
    testWidgets('does not overflow at $label, in the list or in the part dialog', (t) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final FakeDeliveryServer s = FakeDeliveryServer();
      await t.pumpWidget(app(s, size: size, scale: scale));
      await settle(t);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Bedtime'));
      await settle(t);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('partCancel')));
      await settle(t);
      expect(t.takeException(), isNull);
    });
  }
}
