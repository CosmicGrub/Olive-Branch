// OLIVE BRANCH — the lost or stolen phone or tablet screen, on screen. MASTERFILE section 7.23. Driven against the in-memory
// server that answers like server/routes.mjs and checks each request against the REAL route table (test/support/).
// Covers: the list with only the true buttons, every action saying what it does AND what it cannot do before it asks for the
// grown-up's own PIN, "Not now" sending nothing, the PIN never on screen afterwards, the erase order offered to the owner of
// a lost grown-up's phone only (never a child's tablet), the phone that was itself marked as lost, big text and narrow
// screens, and that nothing on a screen is a code, a status or a stack of jargon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/lost_device_screens.dart';
import 'package:olive_client/lost_device_service.dart';

import 'support/account_rig.dart';
import 'support/fake_identity_server.dart';
import 'support/lost_fake.dart';

void main() {
  late DateTime clock;
  late FakeIdentityServer server;
  late LostFake lf;

  setUp(() {
    clock = DateTime.utc(2026, 11, 21, 12);
    server = FakeIdentityServer(now: () => clock);
    lf = LostFake(server);
    AuthSession.use(null);
  });
  tearDown(() => AuthSession.use(null));

  Future<void> size(WidgetTester t, {double w = 800, double h = 2400, double scale = 1.0}) async {
    t.view.physicalSize = Size(w, h);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);
  }

  int n = 0;
  Future<Phone> signedUp(String name, {String pin = '4821'}) async {
    final Phone p = Phone(server);
    final String code = 'allowance-token-0123456789abcdef-${n++}';
    server.addAllowance(code);
    await p.act((s) => s.signUp(allowanceCode: code, displayName: name, homeTz: 'America/Chicago', pin: pin));
    return p;
  }

  Future<String> userIdOf(Phone p) async => (await p.identities.load())!.targetId;

  LostDeviceService svc(Phone p) => LostDeviceService(baseUrl: kBase, account: p.service, client: server.client);

  Future<({Phone mom, Phone dad, FakeDev phone, FakeDev tablet})> family() async {
    final Phone mom = await signedUp('Mom');
    final Phone dad = await signedUp('Dad', pin: '2468');
    final String momId = await userIdOf(mom), dadId = await userIdOf(dad);
    lf.names[momId] = 'Mom';
    lf.names[dadId] = 'Dad';
    return (
      mom: mom,
      dad: dad,
      phone: lf.add('guardian', momId, 'Old phone', ownerName: 'Mom'),
      tablet: lf.add('child', 'child-1', 'Kitchen tablet'),
    );
  }

  Future<void> pumpIn(WidgetTester t, Phone p) async {
    AuthSession.use(p.session);
    await t.pumpWidget(MaterialApp(home: YourDevicesScreen(service: svc(p), now: server.now)));
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  Future<void> type(WidgetTester t, String key, String text) async {
    await t.enterText(find.byKey(Key(key)), text);
    await t.pump();
  }

  String allText(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((Text w) => w.data ?? '').join(' | ');

  final RegExp jargon = RegExp(r'token|credential|hash|revoke|session|encrypt|exception|json|http|status code|null\b', caseSensitive: false);
  void plain(WidgetTester t) {
    final String s = allText(t);
    expect(jargon.hasMatch(s), isFalse, reason: s);
    expect(RegExp(r'[a-z]+_[a-z_]+').hasMatch(s), isFalse, reason: 'a code is on screen: $s');
    expect(s.contains('Exception'), isFalse);
  }

  group('the list', () {
    testWidgets('shows each device in words with only the buttons that are true', (t) async {
      await size(t);
      final f = await family();
      await pumpIn(t, f.mom);
      expect(find.byKey(const Key('devicesIntro')), findsOneWidget);
      expect(find.text('Your phone: Old phone'), findsOneWidget);
      expect(find.text('Tablet: Kitchen tablet'), findsOneWidget);
      expect(find.byKey(Key('markLost_${f.phone.id}')), findsOneWidget);
      expect(find.byKey(Key('found_${f.phone.id}')), findsNothing);
      expect(find.byKey(Key('erase_${f.phone.id}')), findsNothing, reason: 'a working phone is never offered an erase');
      expect(find.byKey(Key('erase_${f.tablet.id}')), findsNothing);
      plain(t);
    });

    testWidgets('an empty family says so kindly', (t) async {
      await size(t);
      final Phone mom = await signedUp('Mom');
      await pumpIn(t, mom);
      expect(find.byKey(const Key('noDevices')), findsOneWidget);
    });

    testWidgets('a problem loading is a sentence, not a code', (t) async {
      await size(t);
      final f = await family();
      server.failNext = http.Response('x', 503);
      await pumpIn(t, f.mom);
      expect(find.byKey(const Key('lostProblem')), findsOneWidget);
      plain(t);
    });
  });

  group('marking as lost', () {
    testWidgets('says what it does AND what it cannot do before asking for the PIN; "Not now" sends nothing', (t) async {
      await size(t);
      final f = await family();
      await pumpIn(t, f.mom);
      server.requests.clear();
      await tapKey(t, 'markLost_${f.phone.id}');
      expect(find.byKey(const Key('confirmDoes')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('confirmDoes'))).data, contains('Nothing is deleted'));
      expect(t.widget<Text>(find.byKey(const Key('confirmDoes'))).data, contains('3 days'));
      expect(find.text('What this cannot do'), findsOneWidget);
      expect(find.byKey(const Key('confirmLimits')), findsOneWidget);
      expect(find.textContaining('cannot find'), findsOneWidget);
      plain(t);
      await tapKey(t, 'confirmCancel');
      expect(server.requests, isEmpty, reason: 'nothing was sent');
      expect(f.phone.state, 'active');
    });

    testWidgets('with the PIN it pauses the device, says so, and the list reads it back; the PIN is not on screen', (t) async {
      await size(t);
      final f = await family();
      await pumpIn(t, f.mom);
      await tapKey(t, 'markLost_${f.phone.id}');
      await type(t, 'confirmPinField', '4821');
      await tapKey(t, 'confirmYes');
      expect(f.phone.state, 'paused');
      expect(find.byKey(const Key('lostDone')), findsOneWidget);
      expect(find.textContaining('marked as lost and paused'), findsOneWidget);
      expect(find.textContaining('You marked it as lost'), findsOneWidget);
      expect(find.byKey(Key('found_${f.phone.id}')), findsOneWidget);
      expect(find.byKey(Key('erase_${f.phone.id}')), findsOneWidget, reason: 'now the owner may ask for it to be erased');
      expect(find.byKey(Key('markLost_${f.phone.id}')), findsNothing);
      expect(allText(t), isNot(contains('4821')));
      plain(t);
    });

    testWidgets('a wrong PIN is a sentence and changes nothing', (t) async {
      await size(t);
      final f = await family();
      await pumpIn(t, f.mom);
      await tapKey(t, 'markLost_${f.phone.id}');
      await type(t, 'confirmPinField', '9999');
      await tapKey(t, 'confirmYes');
      expect(f.phone.state, 'active');
      expect(find.textContaining("isn't right"), findsOneWidget);
      plain(t);
    });

    testWidgets('a child\'s tablet can be paused, but is never offered an erase', (t) async {
      await size(t);
      final f = await family();
      await pumpIn(t, f.dad);
      await tapKey(t, 'markLost_${f.tablet.id}');
      await type(t, 'confirmPinField', '2468');
      await tapKey(t, 'confirmYes');
      expect(f.tablet.state, 'paused');
      expect(find.byKey(Key('erase_${f.tablet.id}')), findsNothing);
      expect(find.byKey(Key('confirmLost_${f.tablet.id}')), findsOneWidget);
      plain(t);
    });
  });

  group('bringing it back, making it final, erasing', () {
    testWidgets('"I have it" brings a paused phone back', (t) async {
      await size(t);
      final f = await family();
      await t.runAsync(() => f.mom.act((_) => svc(f.mom).markLost(deviceId: f.phone.id, pin: '4821')));
      await pumpIn(t, f.mom);
      await tapKey(t, 'found_${f.phone.id}');
      expect(find.textContaining('Nothing was lost while it was paused'), findsOneWidget);
      await type(t, 'confirmPinField', '4821');
      await tapKey(t, 'confirmYes');
      expect(f.phone.state, 'active');
      expect(find.byKey(Key('markLost_${f.phone.id}')), findsOneWidget);
    });

    testWidgets('the other grown-up sees no "I have it" or "It is lost" on a phone its owner reported herself', (t) async {
      await size(t);
      final f = await family();
      await t.runAsync(() => f.mom.act((_) => svc(f.mom).markLost(deviceId: f.phone.id, pin: '4821')));
      await pumpIn(t, f.dad);
      expect(find.byKey(Key('found_${f.phone.id}')), findsNothing);
      expect(find.byKey(Key('confirmLost_${f.phone.id}')), findsNothing);
      expect(find.byKey(Key('erase_${f.phone.id}')), findsNothing, reason: 'only the owner may ask for an erase');
    });

    testWidgets('"Erase it when it connects" says what it does and cannot do; then the list shows it waiting; it can be cancelled', (t) async {
      await size(t);
      final f = await family();
      await t.runAsync(() => f.mom.act((_) => svc(f.mom).markLost(deviceId: f.phone.id, pin: '4821')));
      await pumpIn(t, f.mom);
      await tapKey(t, 'erase_${f.phone.id}');
      expect(find.textContaining('next connects to the internet'), findsOneWidget);
      expect(find.textContaining('are not touched'), findsOneWidget);
      expect(find.textContaining('switched on and online'), findsOneWidget);
      expect(find.textContaining('added to your family again'), findsOneWidget);
      await type(t, 'confirmPinField', '4821');
      await tapKey(t, 'confirmYes');
      expect(f.phone.wipe, 'ordered');
      expect(find.textContaining('Waiting to erase'), findsOneWidget);
      expect(find.byKey(Key('erase_${f.phone.id}')), findsNothing);
      expect(find.byKey(Key('cancelErase_${f.phone.id}')), findsOneWidget);
      plain(t);
      await tapKey(t, 'cancelErase_${f.phone.id}');
      await type(t, 'confirmPinField', '4821');
      await tapKey(t, 'confirmYes');
      expect(f.phone.wipe, 'none');
      expect(find.byKey(Key('erase_${f.phone.id}')), findsOneWidget);
    });

    testWidgets('once the phone says it erased itself, the list says so and offers nothing more', (t) async {
      await size(t);
      final f = await family();
      await t.runAsync(() => f.mom.act((_) => svc(f.mom).markLost(deviceId: f.phone.id, pin: '4821')));
      f.phone.wipe = 'done';
      await pumpIn(t, f.mom);
      expect(find.textContaining('has erased'), findsOneWidget);
      expect(find.byKey(Key('erase_${f.phone.id}')), findsNothing);
      expect(find.byKey(Key('cancelErase_${f.phone.id}')), findsNothing);
      plain(t);
    });
  });

  group('the phone that was itself marked as lost', () {
    testWidgets('sees what happened and a place for its owner\'s PIN, and comes back when it has been found', (t) async {
      await size(t);
      final f = await family();
      bool paused = true;
      final Future<http.Response?> Function(http.BaseRequest)? prev = server.interceptor;
      server.interceptor = (http.BaseRequest r) async {
        if (paused && r.url.path == '/v1/me/devices') {
          return http.Response('{"error":"device_paused"}', 401, headers: <String, String>{'content-type': 'application/json'});
        }
        return prev!(r);
      };
      await pumpIn(t, f.mom);
      expect(find.byKey(const Key('pausedThisPhone')), findsOneWidget);
      expect(find.text('This phone was marked as lost'), findsOneWidget);
      expect(find.textContaining('Nothing on your family'), findsOneWidget);
      expect(find.byKey(Key('markLost_${f.phone.id}')), findsNothing, reason: 'a paused phone acts on nothing');
      plain(t);
      // found: the server lets it back in, and the owner's own PIN was all it asked for
      paused = false;
      await type(t, 'resumePinField', '4821');
      await tapKey(t, 'resumeThisPhone');
      expect(find.byKey(const Key('pausedThisPhone')), findsNothing);
      expect(find.byKey(Key('markLost_${f.phone.id}')), findsOneWidget);
      expect(allText(t), isNot(contains('4821')));
    });

    testWidgets('a PIN that is not 4 to 8 digits goes nowhere', (t) async {
      await size(t);
      final f = await family();
      final Future<http.Response?> Function(http.BaseRequest)? prev = server.interceptor;
      server.interceptor = (http.BaseRequest r) async => r.url.path == '/v1/me/devices'
          ? http.Response('{"error":"device_paused"}', 401, headers: <String, String>{'content-type': 'application/json'})
          : prev!(r);
      await pumpIn(t, f.mom);
      server.requests.clear();
      await type(t, 'resumePinField', '12');
      await tapKey(t, 'resumeThisPhone');
      expect(server.requests, isEmpty);
      expect(find.textContaining('4 to 8 digits'), findsOneWidget);
    });
  });

  group('the notice on the account page', () {
    Future<void> pumpBanner(WidgetTester t, Phone p, {VoidCallback? onOpen}) async {
      AuthSession.use(p.session);
      // Opened afresh each time, as a person opening the page again would (the same widget twice keeps its State).
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: LostDeviceNoticeBanner(service: svc(p), onOpen: onOpen ?? () {}, now: server.now))));
      await t.pumpAndSettle();
    }

    testWidgets('nothing while every phone works; a calm card, in words, while one is marked as lost', (t) async {
      await size(t);
      final f = await family();
      await pumpBanner(t, f.dad);
      expect(find.byKey(const Key('lostDeviceBanner')), findsNothing);
      await t.runAsync(() => f.mom.act((_) => svc(f.mom).markLost(deviceId: f.phone.id, pin: '4821')));
      await pumpBanner(t, f.dad);
      expect(find.byKey(const Key('lostDeviceBanner')), findsOneWidget);
      expect(find.text('A phone or tablet is marked as lost'), findsOneWidget);
      expect(find.textContaining("Mom's phone: Old phone was marked as lost by Mom"), findsOneWidget);
      expect(find.textContaining('Nothing is deleted'), findsOneWidget);
      expect(find.textContaining('can come back until'), findsOneWidget);
      plain(t);
    });

    testWidgets('it opens the list when tapped, and says "more" when there are several', (t) async {
      await size(t);
      final f = await family();
      await t.runAsync(() => f.mom.act((_) => svc(f.mom).markLost(deviceId: f.phone.id, pin: '4821')));
      await t.runAsync(() => f.mom.act((_) => svc(f.mom).markLost(deviceId: f.tablet.id, pin: '4821')));
      int opened = 0;
      await pumpBanner(t, f.dad, onOpen: () => opened++);
      expect(find.text('Phones or tablets are marked as lost'), findsOneWidget);
      expect(find.textContaining('And 1 more'), findsOneWidget);
      await t.tap(find.byKey(const Key('lostDeviceBanner')));
      expect(opened, 1);
    });

    testWidgets('a phone that cannot ask shows nothing, and never an error', (t) async {
      await size(t);
      final f = await family();
      server.failNext = http.Response('x', 503);
      await pumpBanner(t, f.dad);
      expect(find.byKey(const Key('lostDeviceBanner')), findsNothing);
      expect(find.byKey(const Key('lostProblem')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a phone that is itself marked as lost shows nothing here (its own card is on the list)', (t) async {
      await size(t);
      final f = await family();
      final Future<http.Response?> Function(http.BaseRequest)? prev = server.interceptor;
      server.interceptor = (http.BaseRequest r) async => r.url.path == '/v1/me/devices'
          ? http.Response('{"error":"device_paused"}', 401, headers: <String, String>{'content-type': 'application/json'})
          : prev!(r);
      await pumpBanner(t, f.mom);
      expect(find.byKey(const Key('lostDeviceBanner')), findsNothing);
    });
  });

  group('looks right on a small phone with big text', () {
    testWidgets('narrow and 2x text: no overflow, nothing cut', (t) async {
      await size(t, w: 360, h: 800, scale: 2.0);
      final f = await family();
      await t.runAsync(() => f.mom.act((_) => svc(f.mom).markLost(deviceId: f.phone.id, pin: '4821')));
      await pumpIn(t, f.mom);
      expect(t.takeException(), isNull);
      await tapKey(t, 'erase_${f.phone.id}');
      expect(t.takeException(), isNull);
    });
  });
}
