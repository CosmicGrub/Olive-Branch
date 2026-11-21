// OLIVE BRANCH — the lost-phone screens, headless: the list of phones and tablets with a PIN before every action, the
// plain refusals, and the cover a lost phone puts over the app. Verified by CI.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_standing.dart';
import 'package:olive_client/lost_device_logic.dart';
import 'package:olive_client/lost_device_screens.dart';
import 'package:olive_client/lost_device_words.dart';

class _Fake implements LostDeviceActions {
  _Fake(this.devices);
  List<FamilyDeviceView> devices;
  final List<String> calls = <String>[];
  LostActionResult next = const LostActionResult.ok(incidentId: 'inc-1');
  bool failLoad = false;

  @override
  Future<List<FamilyDeviceView>> load() async {
    if (failLoad) throw StateError('offline');
    return devices;
  }

  Future<LostActionResult> _rec(String what, String id, String pin) async {
    calls.add('$what:$id:$pin');
    return next;
  }

  @override
  Future<LostActionResult> mark(String id, String pin) => _rec('mark', id, pin);
  @override
  Future<LostActionResult> found(String id, String inc, String pin) => _rec('found:$inc', id, pin);
  @override
  Future<LostActionResult> confirmLost(String id, String inc, String pin) => _rec('confirm:$inc', id, pin);
  @override
  Future<LostActionResult> orderErase(String id, String inc, String pin) => _rec('erase:$inc', id, pin);
  @override
  Future<LostActionResult> cancelErase(String id, String inc, String pin) => _rec('cancelErase:$inc', id, pin);
}

FamilyDeviceView _dev(String id, {String role = 'guardian', String state = 'active', Map<String, Object?> more = const <String, Object?>{}}) =>
    FamilyDeviceView.fromJson(<String, Object?>{'id': id, 'role': role, 'label': 'x', 'state': state, ...more})!;

Future<void> _pump(WidgetTester t, _Fake f, {DateTime? now}) async {
  await t.pumpWidget(MaterialApp(home: PhonesAndTabletsScreen(actions: f, childName: 'Ivy', now: () => now ?? DateTime.utc(2026, 11, 20, 12))));
  await t.pumpAndSettle();
}

Future<void> _pin(WidgetTester t, String pin, {String confirm = 'pinConfirm'}) async {
  await t.enterText(find.byKey(const Key('pinField')), pin);
  await t.pump();
  await t.tap(find.byKey(Key(confirm)));
  await t.pumpAndSettle();
}

void main() {
  tearDown(DeviceStanding.reset);

  group('Phones and tablets', () {
    testWidgets('it lists the family\'s phones and tablet, says the honest limit first, and shows no place', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('m1', more: <String, Object?>{'ownerName': 'Mom', 'isOwn': true, 'canMarkLost': true}),
        _dev('d1', more: <String, Object?>{'ownerName': 'Dad', 'canMarkLost': true}),
        _dev('t1', role: 'child', more: <String, Object?>{'canMarkLost': true}),
      ]);
      await _pump(t, f);
      expect(find.text("Mom's phone"), findsOneWidget);
      expect(find.text("Dad's phone"), findsOneWidget);
      expect(find.text("Ivy's tablet"), findsOneWidget);
      expect(find.byKey(const Key('honestLimit')), findsOneWidget);
      expect(find.textContaining('cannot take back what was already on the phone'), findsOneWidget);
      expect(find.byKey(const Key('erase-t1')), findsNothing, reason: 'a tablet is never offered an erase');
    });

    testWidgets('Mark as lost asks for the PIN first, says what it cannot do, and sends the PIN with the mark', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[_dev('d1', more: <String, Object?>{'ownerName': 'Dad', 'canMarkLost': true})]);
      await _pump(t, f);
      await t.tap(find.byKey(const Key('mark-d1')));
      await t.pumpAndSettle();
      expect(find.textContaining('Mark Dad'), findsOneWidget);
      expect(find.textContaining('cannot take back what was already on the phone'), findsWidgets);
      expect(find.byKey(const Key('pinField')), findsOneWidget);
      // the button stays off until a real PIN is typed
      expect(t.widget<FilledButton>(find.byKey(const Key('pinConfirm'))).onPressed, isNull);
      await _pin(t, '4821');
      expect(f.calls, <String>['mark:d1:4821']);
      expect(find.byKey(const Key('doneLine')), findsOneWidget);
      expect(find.textContaining('marked as lost'), findsWidgets);
    });

    testWidgets('Not now sends nothing', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[_dev('d1', more: <String, Object?>{'ownerName': 'Dad', 'canMarkLost': true})]);
      await _pump(t, f);
      await t.tap(find.byKey(const Key('mark-d1')));
      await t.pumpAndSettle();
      await t.tap(find.text(LostDeviceWords.notNow));
      await t.pumpAndSettle();
      expect(f.calls, isEmpty);
    });

    testWidgets('a paused phone: shows who marked it and how long is left; I have it quotes the incident it answers', (WidgetTester t) async {
      final DateTime now = DateTime.utc(2026, 11, 20, 12);
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('m1', state: 'paused', more: <String, Object?>{
          'ownerName': 'Mom', 'markedByName': 'Dad', 'incidentId': 'inc-9', 'canFound': true, 'canConfirmLost': true,
          'revokeDueAt': now.add(const Duration(hours: 70)).toIso8601String()}),
      ]);
      await _pump(t, f, now: now);
      expect(find.byKey(const Key('state-m1')), findsOneWidget);
      expect(find.textContaining('Marked as lost by Dad'), findsOneWidget);
      expect(find.textContaining('about 2 days'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('state-m1')), matching: find.textContaining('Nothing is deleted')), findsOneWidget);
      await t.tap(find.byKey(const Key('found-m1')));
      await t.pumpAndSettle();
      await _pin(t, '4821');
      expect(f.calls, <String>['found:inc-9:m1:4821']);
    });

    testWidgets('It is lost asks again in plain words before it removes anything, and says nothing in the records is deleted', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('m1', state: 'paused', more: <String, Object?>{'ownerName': 'Mom', 'isOwn': true, 'incidentId': 'inc-9', 'canConfirmLost': true})]);
      await _pump(t, f);
      await t.tap(find.byKey(const Key('confirm-m1')));
      await t.pumpAndSettle();
      expect(find.text(LostDeviceWords.confirmLostTitle), findsOneWidget);
      expect(find.textContaining("Nothing in your family's records is deleted"), findsOneWidget);
      await _pin(t, '4821');
      expect(f.calls.single, startsWith('confirm:inc-9'));
    });

    testWidgets('Erase when it connects: says it starts in 24 hours, that records are safe, that it cannot take back what was read, and asks for the PIN', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('m1', state: 'paused', more: <String, Object?>{'ownerName': 'Mom', 'isOwn': true, 'incidentId': 'inc-9', 'canOrderErase': true})]);
      await _pump(t, f);
      await t.tap(find.byKey(const Key('erase-m1')));
      await t.pumpAndSettle();
      expect(find.textContaining('24 hours'), findsWidgets);
      expect(find.textContaining('Your records are not lost'), findsOneWidget);
      expect(find.textContaining('cannot take back what someone already read'), findsOneWidget);
      await _pin(t, '4821');
      expect(f.calls.single, 'erase:inc-9:m1:4821');
      expect(find.text(LostDeviceWords.eraseOrderedDone), findsOneWidget);
    });

    testWidgets('an ordered erase shows when it starts, and ANY grown-up can call it off (but only the owner could order it)', (WidgetTester t) async {
      final DateTime now = DateTime.utc(2026, 11, 20, 12);
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('m1', state: 'paused', more: <String, Object?>{
          'ownerName': 'Mom', 'incidentId': 'inc-9', 'eraseOrdered': true, 'canCancelErase': true,
          'eraseDueAt': now.add(const Duration(hours: 20)).toIso8601String(), 'revokeDueAt': now.add(const Duration(hours: 60)).toIso8601String()})]);
      await _pump(t, f, now: now);
      expect(find.textContaining('erase its own copy'), findsOneWidget);
      expect(find.byKey(const Key('erase-m1')), findsNothing);
      await t.tap(find.byKey(const Key('cancelErase-m1')));
      await t.pumpAndSettle();
      await _pin(t, '2468');
      expect(f.calls.single, 'cancelErase:inc-9:m1:2468');
      expect(find.text(LostDeviceWords.eraseCancelDone), findsOneWidget);
    });

    testWidgets('every refusal is said in a plain sentence, never a code', (WidgetTester t) async {
      for (final String e in <String>['owner_only', 'rate_limited', 'no_other_copy', 'too_late', 'pin_incorrect', 'pin_locked', 'weird_new_error']) {
        final _Fake f = _Fake(<FamilyDeviceView>[_dev('d1', more: <String, Object?>{'ownerName': 'Dad', 'canMarkLost': true})])
          ..next = LostActionResult.refused(e);
        await _pump(t, f);
        await t.tap(find.byKey(const Key('mark-d1')));
        await t.pumpAndSettle();
        await _pin(t, '1111');
        final String shown = t.widget<Text>(find.byKey(const Key('doneLine'))).data!;
        expect(shown, isNot(contains('_')), reason: e);
        expect(shown, isNot(contains(e)), reason: e);
        expect(shown.length, greaterThan(10));
      }
    });

    testWidgets('no connection: a calm line and a way to try again, not an exception', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[])..failLoad = true;
      await _pump(t, f);
      expect(find.byKey(const Key('loadError')), findsOneWidget);
      expect(find.text(LostDeviceWords.loadError), findsOneWidget);
    });

    testWidgets('the PIN is never left on screen or kept: the field is cleared when the dialog closes', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[_dev('d1', more: <String, Object?>{'ownerName': 'Dad', 'canMarkLost': true})]);
      await _pump(t, f);
      await t.tap(find.byKey(const Key('mark-d1')));
      await t.pumpAndSettle();
      await _pin(t, '4821');
      expect(find.text('4821'), findsNothing);
      expect(find.byKey(const Key('pinField')), findsNothing);
    });
  });

  group('the cover on a lost phone', () {
    Widget app({CheckBack? check}) => MaterialApp(
          home: DeviceStandingGuard(
            checkBack: check ?? (String? pin) async => DeviceStanding.value,
            child: const Scaffold(body: Text('FAMILY SCREEN')),
          ),
        );

    testWidgets('normal: the app shows, there is no cover', (WidgetTester t) async {
      await t.pumpWidget(app());
      expect(find.text('FAMILY SCREEN'), findsOneWidget);
      expect(find.byKey(const Key('coverTitle')), findsNothing);
    });

    testWidgets('paused: the app is covered and not reachable, but stays alive underneath (nothing is lost)', (WidgetTester t) async {
      await t.pumpWidget(app());
      DeviceStanding.state.value = DeviceStandingState.paused;
      await t.pumpAndSettle();
      expect(find.byKey(const Key('coverTitle')), findsOneWidget);
      expect(find.text(LostDeviceWords.pausedCoverTitle), findsOneWidget);
      expect(find.text('FAMILY SCREEN', skipOffstage: true), findsNothing);
      expect(find.text('FAMILY SCREEN', skipOffstage: false), findsOneWidget, reason: 'kept alive, not drawn');
      expect(find.byKey(const Key('checkAgain')), findsOneWidget);
    });

    testWidgets('Check again that is still paused says so calmly', (WidgetTester t) async {
      await t.pumpWidget(app());
      DeviceStanding.state.value = DeviceStandingState.paused;
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('checkAgain')));
      await t.pumpAndSettle();
      expect(find.text(LostDeviceWords.pausedStillPaused), findsOneWidget);
    });

    testWidgets('brought back: the cover goes away by itself when the family says so', (WidgetTester t) async {
      await t.pumpWidget(app(check: (String? pin) async {
        DeviceStanding.state.value = DeviceStandingState.active;
        return DeviceStandingState.active;
      }));
      DeviceStanding.state.value = DeviceStandingState.paused;
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('checkAgain')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('coverTitle')), findsNothing);
      expect(find.text('FAMILY SCREEN'), findsOneWidget);
    });

    testWidgets('waiting for its owner PIN: the PIN is sent to the check, then cleared', (WidgetTester t) async {
      String? sent;
      await t.pumpWidget(app(check: (String? pin) async {
        sent = pin;
        return DeviceStanding.value;
      }));
      DeviceStanding.state.value = DeviceStandingState.needsOwnerPin;
      await t.pumpAndSettle();
      expect(find.text(LostDeviceWords.pinCoverTitle), findsOneWidget);
      await t.enterText(find.byKey(const Key('coverPin')), '4821');
      await t.tap(find.byKey(const Key('checkPin')));
      await t.pumpAndSettle();
      expect(sent, '4821');
      expect(find.text('4821'), findsNothing);
    });

    testWidgets('cut off and erased: each says what is true, and only Add this phone again goes forward', (WidgetTester t) async {
      await t.pumpWidget(app());
      DeviceStanding.state.value = DeviceStandingState.cutOff;
      await t.pumpAndSettle();
      expect(find.text(LostDeviceWords.cutOffCoverTitle), findsOneWidget);
      expect(find.textContaining('What was already on this phone stays on it'), findsOneWidget);
      DeviceStanding.state.value = DeviceStandingState.erased;
      await t.pumpAndSettle();
      expect(find.text(LostDeviceWords.erasedCoverTitle), findsOneWidget);
      expect(find.textContaining('safe with the family'), findsOneWidget);
      await t.tap(find.byKey(const Key('addAgain')));
      await t.pumpAndSettle();
      expect(DeviceStanding.value, DeviceStandingState.active);
      expect(find.byKey(const Key('coverTitle')), findsNothing);
    });

    testWidgets('no cover names a person, a place or a network', (WidgetTester t) async {
      await t.pumpWidget(app());
      for (final DeviceStandingState s in <DeviceStandingState>[
        DeviceStandingState.paused, DeviceStandingState.needsOwnerPin, DeviceStandingState.cutOff, DeviceStandingState.erased]) {
        DeviceStanding.state.value = s;
        await t.pumpAndSettle();
        final String text = <String>[
          t.widget<Text>(find.byKey(const Key('coverTitle'))).data!, t.widget<Text>(find.byKey(const Key('coverBody'))).data!,
        ].join(' ');
        expect(text, isNot(matches(RegExp(r'\b(Mom|Dad|Alex|Sam|wi-?fi|map|GPS|where)\b', caseSensitive: false))), reason: '$s');
        DeviceStanding.state.value = DeviceStandingState.active;
        await t.pumpAndSettle();
      }
    });
  });

  group('the quiet notice on a grown-up\'s home', () {
    Future<void> pumpNotice(WidgetTester t, _Fake f, {VoidCallback? onOpen}) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: LostDeviceNotice(actions: f, childName: 'Ivy', onOpen: onOpen ?? () {})),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('another grown-up\'s phone marked as lost: a calm notice in plain words, with the honest limit built in', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('d1', state: 'paused', more: <String, Object?>{'ownerName': 'Dad', 'incidentId': 'i1'})]);
      await pumpNotice(t, f);
      expect(find.text("Dad's phone is marked as lost"), findsOneWidget);
      expect(find.textContaining('New family updates will not go to it.'), findsOneWidget);
      expect(find.textContaining('Anyone who had it open could have read that.'), findsOneWidget);
      expect(find.textContaining('Your own records are not affected.'), findsOneWidget);
    });

    testWidgets('the owner, on another phone, is told in the owner\'s words and offered "I have it"', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('m1', state: 'paused', more: <String, Object?>{'ownerName': 'Mom', 'isOwn': true, 'markedByName': 'Dad', 'incidentId': 'i1'})]);
      int opened = 0;
      await pumpNotice(t, f, onOpen: () => opened++);
      expect(find.text(LostDeviceWords.ownerTitle()), findsOneWidget);
      expect(find.textContaining('Dad marked your phone as lost'), findsOneWidget);
      await t.tap(find.byKey(const Key('lostNoticeOpen-m1')));
      expect(opened, 1);
      expect(find.text(LostDeviceWords.foundButton), findsOneWidget);
    });

    testWidgets('a lost phone told to erase says so, and OK puts the notice away for this run', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('m1', state: 'paused', more: <String, Object?>{'ownerName': 'Mom', 'incidentId': 'i1', 'eraseOrdered': true})]);
      await pumpNotice(t, f);
      expect(find.byKey(const Key('lostNoticeErase-m1')), findsOneWidget);
      await t.tap(find.byKey(const Key('lostNoticeOk-m1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('lostNotice-m1')), findsNothing);
    });

    testWidgets('nothing to say: nothing is drawn. No signal: nothing is drawn and nothing is said', (WidgetTester t) async {
      await pumpNotice(t, _Fake(<FamilyDeviceView>[_dev('d1', more: <String, Object?>{'ownerName': 'Dad'})]));
      expect(find.byType(Container), findsNothing);
      await pumpNotice(t, _Fake(<FamilyDeviceView>[])..failLoad = true);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('this phone is never told about itself here (its own cover does that)', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[
        _dev('me', state: 'paused', more: <String, Object?>{'ownerName': 'Mom', 'isThisDevice': true, 'incidentId': 'i1'})]);
      await pumpNotice(t, f);
      expect(find.byKey(const Key('lostNotice-me')), findsNothing);
    });

    testWidgets('a child\'s tablet marked as lost reads as "Ivy\'s tablet" for grown-ups', (WidgetTester t) async {
      final _Fake f = _Fake(<FamilyDeviceView>[_dev('t1', role: 'child', state: 'paused', more: <String, Object?>{'incidentId': 'i1'})]);
      await pumpNotice(t, f);
      expect(find.text("Ivy's tablet is marked as lost"), findsOneWidget);
    });
  });
}
