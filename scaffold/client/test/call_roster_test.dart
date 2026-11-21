// OLIVE BRANCH - who is on the call, in the open (ISS-099, ISS-100). Three-party and observer tests:
// a second and a third person ADD to the roster (nobody overwrites anybody); every join and leave becomes one sentence
// shown on screen and in a live region for the screen reader; the count that stays on screen includes everyone, observers
// included; an unnamed person is "Someone", never an id; no path joins a person without being listed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_modes.dart';
import 'package:olive_client/call_provider.dart';
import 'package:olive_client/call_screen.dart';

const CallParticipant dad = CallParticipant(id: 'p-dad', name: 'Dad');
const CallParticipant mum = CallParticipant(id: 'p-mum', name: 'Mum');
const CallParticipant gran = CallParticipant(id: 'p-gran', name: 'Gran', observer: true);

void main() {
  group('the roster is a list, and nobody replaces anybody', () {
    test('three people join in turn: all three are listed, in the order they came', () {
      List<CallParticipant> r = const <CallParticipant>[];
      r = rosterWith(r, dad);
      r = rosterWith(r, mum);
      r = rosterWith(r, gran);
      expect(r.map((CallParticipant p) => p.label).toList(), <String>['Dad', 'Mum', 'Gran']);
    });

    test('one leaves: only that person goes', () {
      final List<CallParticipant> r = rosterWithout(<CallParticipant>[dad, mum, gran], 'p-mum');
      expect(r.map((CallParticipant p) => p.label).toList(), <String>['Dad', 'Gran']);
    });

    test('the same id arriving again (a name that came late) updates in place and adds nobody', () {
      final List<CallParticipant> r = rosterWith(<CallParticipant>[const CallParticipant(id: 'p1', name: '')], const CallParticipant(id: 'p1', name: 'Dad'));
      expect(r.length, 1);
      expect(r.single.label, 'Dad');
    });

    test('an unnamed participant is "Someone", never an id', () {
      const CallParticipant p = CallParticipant(id: '3f9c2b1e-1111-2222-3333-444455556666', name: '  ');
      expect(p.label, 'Someone');
      expect(rosterAnnouncements(const <CallParticipant>[], <CallParticipant>[p]), <String>['Someone joined']);
    });

    test('leaving someone who is not there changes nothing', () {
      expect(rosterWithout(<CallParticipant>[dad], 'nobody'), <CallParticipant>[dad]);
    });
  });

  group('every join and leave is announced', () {
    test('a join, a leave', () {
      expect(rosterAnnouncements(const <CallParticipant>[], <CallParticipant>[dad]), <String>['Dad joined']);
      expect(rosterAnnouncements(<CallParticipant>[dad], const <CallParticipant>[]), <String>['Dad left']);
    });

    test('two joining at once are both announced, joins first and then leaves', () {
      expect(rosterAnnouncements(<CallParticipant>[dad], <CallParticipant>[mum, gran]),
          <String>['Mum joined', 'Gran is watching', 'Dad left']);
    });

    test('an observer is named too: "is watching" and "stopped watching"', () {
      expect(rosterAnnouncements(<CallParticipant>[dad], <CallParticipant>[dad, gran]), <String>['Gran is watching']);
      expect(rosterAnnouncements(<CallParticipant>[dad, gran], <CallParticipant>[dad]), <String>['Gran stopped watching']);
    });

    test('no change, no sentence', () {
      expect(rosterAnnouncements(<CallParticipant>[dad, gran], <CallParticipant>[dad, gran]), isEmpty);
    });
  });

  group('the persistent count includes everyone, observers too', () {
    test('just you', () => expect(rosterCountLine(const <CallParticipant>[]), 'Just you here'));
    test('you and one person', () => expect(rosterCountLine(<CallParticipant>[dad]), '2 people here'));
    test('you and two people', () => expect(rosterCountLine(<CallParticipant>[dad, mum]), '3 people here'));
    test('an observer is counted and named in the count', () {
      expect(rosterCountLine(<CallParticipant>[dad, gran]), '3 people here, 1 watching');
      expect(rosterCountLine(<CallParticipant>[gran]), '2 people here, 1 watching');
    });
    test('the spoken line names everyone, observers marked', () {
      expect(rosterSpokenLine(<CallParticipant>[dad, gran]), '3 people here, 1 watching. With you: Dad, Gran (watching)');
    });
    test('the count never undercounts: n others is always n + 1', () {
      for (int n = 0; n < 8; n++) {
        final List<CallParticipant> others = <CallParticipant>[for (int i = 0; i < n; i++) CallParticipant(id: 'p$i', name: 'P$i', observer: i.isOdd)];
        final String line = rosterCountLine(others);
        if (n == 0) {
          expect(line, 'Just you here');
        } else {
          expect(line.startsWith('${n + 1} people here'), true, reason: line);
        }
      }
    });
  });

  group('CallViewState carries the list', () {
    test('a new state has nobody and no remoteName', () {
      expect(const CallViewState().participants, isEmpty);
      expect(const CallViewState().remoteName, isNull);
    });

    test('copyWith keeps the whole list; remoteName is the first person taking part, else the first observer', () {
      final CallViewState s = const CallViewState().copyWith(participants: <CallParticipant>[gran, dad, mum]);
      expect(s.participants.length, 3);
      expect(s.remoteName, 'Dad');
      expect(const CallViewState().copyWith(participants: <CallParticipant>[gran]).remoteName, 'Gran');
      expect(s.copyWith(phase: CallPhase.connected).participants.length, 3, reason: 'an unrelated change keeps the roster');
    });
  });

  group('no unannounced join in the call code', () {
    test('no engine adapter overwrites the roster with a single name, and none hides a participant', () {
      for (final String f in <String>['lib/livekit_call_provider.dart', 'lib/jitsi_call_provider.dart', 'lib/call_screen.dart', 'lib/call_provider.dart']) {
        final String src = File(f).readAsStringSync();
        expect(RegExp(r'copyWith\([^)]*remoteName\s*:').hasMatch(src), isFalse, reason: '$f sets a single remoteName');
        expect(src.contains('clearRemoteName'), isFalse, reason: '$f clears a single remoteName');
        expect(RegExp(r'hidden\s*[:=]\s*true').hasMatch(src), isFalse, reason: '$f hides somebody');
      }
    });

    test('every engine join and leave goes through the roster helpers', () {
      final String lk = File('lib/livekit_call_provider.dart').readAsStringSync();
      final String jitsi = File('lib/jitsi_call_provider.dart').readAsStringSync();
      expect(lk.contains('ParticipantConnectedEvent') && lk.contains('rosterWith('), isTrue);
      expect(lk.contains('ParticipantDisconnectedEvent') && lk.contains('rosterWithout('), isTrue);
      expect(jitsi.contains('rosterWith(') && jitsi.contains('rosterWithout('), isTrue);
    });
  });

  group('the call screen shows it', () {
    Future<void> pumpView(WidgetTester t, {required List<CallParticipant> others, String? announcement}) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: InCallView(
        localVideo: null, remoteVideo: null, remoteName: null, notice: null,
        participants: others, announcement: announcement,
        isGuardian: false, onHangUp: () async {}, onToggleMic: () async {}, onToggleCamera: () async {},
        micEnabled: true, cameraEnabled: true, remoteMode: CallMode.video, awaitingResumeConsent: false, onResumeVideo: () {},
      ))));
      await t.pump(const Duration(milliseconds: 200));
    }

    String countText(WidgetTester t) => (t.widget(find.byKey(const Key('callRosterCount'))) as Text).data!;

    testWidgets('the count line is always on screen: alone, with one, with three, with an observer', (t) async {
      await pumpView(t, others: const <CallParticipant>[]);
      expect(countText(t), 'Just you here');
      await pumpView(t, others: <CallParticipant>[dad]);
      expect(countText(t), '2 people here');
      await pumpView(t, others: <CallParticipant>[dad, mum]);
      expect(countText(t), '3 people here');
      await pumpView(t, others: <CallParticipant>[dad, mum, gran]);
      expect(countText(t), '4 people here, 1 watching');
    });

    testWidgets('an announcement is written on screen and is a live region (read out without a tap)', (t) async {
      await pumpView(t, others: <CallParticipant>[dad], announcement: 'Dad joined');
      expect(find.byKey(const Key('callRosterAnnouncement')), findsOneWidget);
      expect(find.text('Dad joined'), findsOneWidget);
      final Finder live = find.ancestor(
          of: find.byKey(const Key('callRosterAnnouncement')),
          matching: find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.liveRegion == true));
      expect(live, findsOneWidget);
    });

    testWidgets('the count line is described to a screen reader with the names, observers marked', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await pumpView(t, others: <CallParticipant>[dad, gran]);
      expect(find.bySemanticsLabel('3 people here, 1 watching. With you: Dad, Gran (watching)'), findsOneWidget);
      h.dispose();
    });

    testWidgets('no announcement, no announcement widget', (t) async {
      await pumpView(t, others: <CallParticipant>[dad]);
      expect(find.byKey(const Key('callRosterAnnouncement')), findsNothing);
    });

    testWidgets('the count also shows in the tabletop layout', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: InCallView(
        localVideo: null, remoteVideo: null, remoteName: null, notice: null, tabletop: true,
        participants: <CallParticipant>[dad, gran],
        isGuardian: false, onHangUp: () async {}, onToggleMic: () async {}, onToggleCamera: () async {},
        micEnabled: true, cameraEnabled: true, remoteMode: CallMode.video, awaitingResumeConsent: false, onResumeVideo: () {},
      ))));
      await t.pump(const Duration(milliseconds: 200));
      expect(countText(t), '3 people here, 1 watching');
    });
  });

  group('driven through the real screen: three parties, then an observer', () {
    testWidgets('each join is announced, the count follows, a leave is announced, and nobody is dropped', (t) async {
      final FakeCallProvider fake = FakeCallProvider();
      await t.pumpWidget(MaterialApp(
          home: CallScreen(
              who: 'ivy', displayName: 'Dad',
              knownGrant: const CallGrant.livekit(token: 'tok', wsURL: 'wss://x.invalid', displayName: 'Dad'),
              providerFactory: (_) => fake)));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));

      CallViewState s = fake.state.copyWith(phase: CallPhase.connected);
      fake.emit(s);
      await t.pump(const Duration(milliseconds: 10)); // a pump with a duration delivers the stream event first, then draws
      expect((t.widget(find.byKey(const Key('callRosterCount'))) as Text).data, 'Just you here');

      s = s.copyWith(participants: <CallParticipant>[dad]);
      fake.emit(s);
      await t.pump(const Duration(milliseconds: 10)); // a pump with a duration delivers the stream event first, then draws
      expect(find.text('Dad joined'), findsOneWidget);
      expect((t.widget(find.byKey(const Key('callRosterCount'))) as Text).data, '2 people here');

      s = s.copyWith(participants: <CallParticipant>[dad, mum]);
      fake.emit(s);
      await t.pump(const Duration(milliseconds: 10)); // a pump with a duration delivers the stream event first, then draws
      expect(find.text('Mum joined'), findsOneWidget, reason: 'a third person is announced, not swallowed');
      expect((t.widget(find.byKey(const Key('callRosterCount'))) as Text).data, '3 people here');

      s = s.copyWith(participants: <CallParticipant>[dad, mum, gran]);
      fake.emit(s);
      await t.pump(const Duration(milliseconds: 10)); // a pump with a duration delivers the stream event first, then draws
      expect(find.text('Gran is watching'), findsOneWidget, reason: 'an observer is announced as soon as they are present');
      expect((t.widget(find.byKey(const Key('callRosterCount'))) as Text).data, '4 people here, 1 watching');

      s = s.copyWith(participants: <CallParticipant>[dad, gran]);
      fake.emit(s);
      await t.pump(const Duration(milliseconds: 10)); // a pump with a duration delivers the stream event first, then draws
      expect(find.text('Mum left'), findsOneWidget);
      expect((t.widget(find.byKey(const Key('callRosterCount'))) as Text).data, '3 people here, 1 watching');

      // the sentence goes away by itself after a few seconds, the count stays
      await t.pump(const Duration(seconds: 9));
      expect(find.byKey(const Key('callRosterAnnouncement')), findsNothing);
      expect(find.byKey(const Key('callRosterCount')), findsOneWidget);

      // leave the screen cleanly (no timers left behind)
      fake.emit(s.copyWith(phase: CallPhase.ended));
      await t.pumpAndSettle();
    });
  });
}
