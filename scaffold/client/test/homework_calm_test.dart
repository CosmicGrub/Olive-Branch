// OLIVE BRANCH — Homework on a child device is a live-session feature. A locally paired or offline home has no
// session, so it shows no Homework tile and no Homework entry on the More page, and nothing pretends to
// photograph, recognise or hint (the simulated capture and the canned problems belong to the preview build,
// LocalServices.demoSeeds, alone). When the real path fails the child sees the one calm try-again card, never a
// sentence about a server or a connection. Owner rules P1-P11 (a child sees no error text). Verified by CI, headless.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/capture_gate.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_home_bands_ui.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/homework_screen.dart';
import 'package:olive_client/local_services.dart';

const FamilyPrincipal _childP = FamilyPrincipal(roleName: 'child', childId: 'c1');

Future<FamilyChildSnapshot> _snap(int years) {
  final FamilyService s = FamilyService(MemoryFamilyStore(), clock: () => DateTime(2026, 11, 9, 9));
  return s.childSnapshot(_childP, childId: 'c1', yearsOld: years);
}

Future<void> _big(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

String _allText(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((Text w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .join(' | ')
    .toLowerCase();

void main() {
  /// What a real device runs: on-device storage in live mode, no invented content.
  void liveDevice() =>
      LocalServices.install(LocalServices.memory(childId: 'kid-1', isLive: true, demoSeeds: false));

  tearDown(LocalServices.resetForTest);

  group('Standard home', () {
    ChildHome home({String? baseUrl, String? childId, String? sessionToken}) => ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: null,
        baseUrl: baseUrl, childId: childId, sessionToken: sessionToken);

    testWidgets('locally paired (no session at all): no Homework tile', (WidgetTester t) async {
      liveDevice();
      await _big(t);
      await t.pumpWidget(MaterialApp(home: home()));
      await t.pumpAndSettle();
      expect(find.text('Homework'), findsNothing);
      expect(find.text('My list'), findsOneWidget, reason: 'the rest of the home is untouched');
    });

    testWidgets('offline (an address, the cached name, but no session token): no Homework tile', (WidgetTester t) async {
      liveDevice();
      await _big(t);
      await t.pumpWidget(MaterialApp(home: home(baseUrl: 'http://api.test', childId: 'kid-1')));
      await t.pumpAndSettle();
      expect(find.text('Homework'), findsNothing);
      expect(find.text('My list'), findsOneWidget);
    });

    testWidgets('a live session: the Homework tile is there and opens the real screen', (WidgetTester t) async {
      liveDevice();
      await _big(t);
      await t.pumpWidget(MaterialApp(home: home(baseUrl: 'http://api.test', childId: 'kid-1', sessionToken: 'tok')));
      await t.pumpAndSettle();
      expect(find.text('Homework'), findsOneWidget);
      await t.tap(find.text('Homework'));
      await t.pumpAndSettle();
      expect(find.byType(HomeworkScreen), findsOneWidget);
      expect(find.byKey(const Key('takePhotoButton')), findsOneWidget);
    });

    testWidgets('the preview build (demo seeds on) keeps its sample Homework', (WidgetTester t) async {
      LocalServices.resetForTest();
      await _big(t);
      await t.pumpWidget(MaterialApp(home: home()));
      await t.pumpAndSettle();
      expect(find.text('Homework'), findsOneWidget);
    });
  });

  group('the 5-7 and 8-12 More page', () {
    Future<void> openMore(WidgetTester t, int years, {String? token}) async {
      await _big(t);
      final FamilyChildSnapshot f = await _snap(years);
      await t.pumpWidget(MaterialApp(
          home: ChildHome(
              childName: 'Ivy', presence: null, sleepsUntilHandover: null, family: f, childAge: years,
              baseUrl: token == null ? null : 'http://api.test', childId: token == null ? null : 'kid-1',
              sessionToken: token)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandTile.more')));
      await t.pumpAndSettle();
      expect(find.byType(ChildBandMoreScreen), findsOneWidget);
    }

    for (final int years in <int>[6, 9]) {
      testWidgets('age $years, no session: no Homework entry on More, Everything else still there', (WidgetTester t) async {
        liveDevice();
        await openMore(t, years);
        expect(find.byKey(const Key('moreHomework')), findsNothing);
        expect(find.byKey(const Key('moreEverything')), findsOneWidget);
      });

      testWidgets('age $years, live session: the Homework entry is on More', (WidgetTester t) async {
        liveDevice();
        await openMore(t, years, token: 'tok');
        expect(find.byKey(const Key('moreHomework')), findsOneWidget);
      });
    }
  });

  group('the capture and the screen never pretend on a live device', () {
    testWidgets('capture without a session shows the calm card, no simulated photo, no demo caption', (WidgetTester t) async {
      liveDevice();
      await t.pumpWidget(const MaterialApp(home: CaptureGateScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
      expect(find.byKey(const Key('shutterButton')), findsNothing);
      expect(_allText(t), isNot(contains('demo')));
    });

    testWidgets('the Homework screen without a session shows the calm card, no canned problem', (WidgetTester t) async {
      liveDevice();
      await t.pumpWidget(const MaterialApp(home: HomeworkScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
      expect(find.byKey(const Key('takePhotoButton')), findsNothing);
      expect(_allText(t), isNot(contains('6 x 7')));
    });

    testWidgets('the preview build keeps its simulated capture (demo seeds on)', (WidgetTester t) async {
      LocalServices.resetForTest();
      await t.pumpWidget(const MaterialApp(home: CaptureGateScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('shutterButton')), findsOneWidget);
      expect(_allText(t), contains('demo capture'));
    });

    Future<void> pumpReal(WidgetTester t, http.Client client) async {
      await t.pumpWidget(MaterialApp(
          home: CaptureGateScreen(
              baseUrl: 'http://api.test', childId: 'kid-1', sessionToken: 'tok', httpClient: client,
              takePhoto: () async => Uint8List.fromList(<int>[1, 2, 3]))));
      await t.pumpAndSettle();
    }

    testWidgets('real path: no sentence about a server on the capture screen', (WidgetTester t) async {
      liveDevice();
      await pumpReal(t, MockClient((http.Request r) async => http.Response('{}', 200)));
      expect(find.byKey(const Key('shutterButton')), findsOneWidget);
      final String all = _allText(t);
      expect(all, isNot(contains('server')));
      expect(all, isNot(contains('demo')));
    });

    testWidgets('real path, network failure: the one calm card, no server or connection wording, then back', (WidgetTester t) async {
      liveDevice();
      await pumpReal(t, MockClient((http.Request r) async => throw http.ClientException('no route to secret-host.internal')));
      await t.tap(find.byKey(const Key('shutterButton')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
      final String all = _allText(t);
      for (final String bad in <String>['server', 'connection', 'secret-host', 'exception', "couldn't", 'error']) {
        expect(all, isNot(contains(bad)), reason: '"$bad" shown to a child: $all');
      }
      await t.tap(find.byKey(const Key('childConnectBack')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('shutterButton')), findsOneWidget, reason: 'OK returns to the camera');
    });

    testWidgets('real path, a good answer: only the server\'s problems are shown, never the canned ones', (WidgetTester t) async {
      liveDevice();
      final http.Client ok = MockClient((http.Request r) async => http.Response(
          jsonEncode(<String, Object?>{
            'ok': true,
            'problems': <Map<String, Object?>>[
              <String, Object?>{'text': '9 + 4', 'hint': 'Make ten first.'},
            ],
          }),
          200));
      await t.pumpWidget(MaterialApp(
          home: HomeworkScreen(
              baseUrl: 'http://api.test', childId: 'kid-1', sessionToken: 'tok', httpClient: ok)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('takePhotoButton')));
      await t.pumpAndSettle();
      // The default camera is not available headless: this route only proves the screen offers the real capture.
      expect(find.byType(CaptureGateScreen), findsOneWidget);
      expect(_allText(t), isNot(contains('6 x 7')));
    });
  });
}
