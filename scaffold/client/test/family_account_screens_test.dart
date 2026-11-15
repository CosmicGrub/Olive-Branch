// OLIVE BRANCH — the optional family account, on screen. MASTERFILE section 8.5.13. Every screen is driven against the
// in-memory server that checks each request against the real route table (test/support/).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/family_account_store.dart' show JoinStage, PendingJoin;
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/family_account_screens.dart';
import 'package:olive_client/family_account_service.dart';
import 'package:olive_client/screen_privacy.dart' show SensitiveScreen;

import 'support/account_rig.dart';
import 'support/fake_identity_server.dart';

void main() {
  late FakeIdentityServer server;
  setUp(() {
    server = FakeIdentityServer();
    AuthSession.use(null);
  });
  // The system clipboard has no host in a widget test; answer its channel so a copy can finish.
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async => null);
  tearDown(() => AuthSession.use(null));

  Future<void> size(WidgetTester t, {double w = 800, double h = 2400, double scale = 1.0}) async {
    t.view.physicalSize = Size(w, h);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearAllTestValues);
  }

  Future<void> pumpHub(WidgetTester t, Phone p, {String? name, String? zone, int? age, String? childName}) async {
    await t.pumpWidget(MaterialApp(
        home: FamilyAccountScreen(
            service: p.service, baseUrl: kBase, suggestedName: name, suggestedZone: zone, suggestedChildAge: age,
            suggestedChildName: childName)));
    await t.pumpAndSettle();
  }

  Future<void> type(WidgetTester t, String key, String text) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.enterText(find.byKey(Key(key)), text);
    await t.pump();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  Future<Phone> signedUp(String name, {String code = kCode}) async {
    final Phone p = Phone(server);
    server.addAllowance(code);
    await p.act((s) => s.signUp(allowanceCode: code, displayName: name, homeTz: 'America/Chicago', pin: '4821'));
    return p;
  }

  String problemText(WidgetTester t) =>
      (t.widget<Text>(find.descendant(of: find.byKey(const Key('accountProblem')), matching: find.byType(Text)).first)).data!;

  group('with no account', () {
    testWidgets('says it is optional, offers three ways in, and asks the server nothing', (t) async {
      await size(t);
      final Phone p = Phone(server);
      await pumpHub(t, p);
      expect(find.byKey(const Key('accountOptionalNote')), findsOneWidget);
      expect(find.textContaining('Olive works fully on this phone without one'), findsOneWidget);
      expect(find.textContaining('Your child never sees any of this'), findsOneWidget);
      for (final String k in <String>['tileCreateAccount', 'tileSignIn', 'tileJoin']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(server.requests, isEmpty);
    });

    testWidgets('making an account: every box is checked first, in words, before anything is sent', (t) async {
      await size(t);
      final Phone p = Phone(server);
      await pumpHub(t, p);
      await tapKey(t, 'tileCreateAccount');
      expect(find.byType(SensitiveScreen), findsWidgets);
      await tapKey(t, 'submitCreateAccount');
      expect(problemText(t), contains('Enter the invite code'));
      await type(t, 'allowanceCode', kCode);
      await tapKey(t, 'submitCreateAccount');
      expect(problemText(t), 'Please enter your name.');
      await type(t, 'accountName', 'Sam');
      await tapKey(t, 'submitCreateAccount');
      expect(problemText(t), contains('time zone'));
      expect(server.requests, isEmpty);
    });

    testWidgets('making an account, start to finish: the PIN is checked, the account appears, the PIN is gone', (t) async {
      await size(t);
      final Phone p = Phone(server);
      server.addAllowance(kCode);
      await pumpHub(t, p, name: 'Sam', zone: 'America/Chicago');
      await tapKey(t, 'tileCreateAccount');
      expect(find.text('Sam'), findsOneWidget, reason: 'the name from the family already on this phone is offered');
      await type(t, 'allowanceCode', kCode);
      await type(t, 'accountPin', '1111');
      await type(t, 'accountPin2', '1111');
      await tapKey(t, 'submitCreateAccount');
      expect(problemText(t), contains('easy to guess'));
      await type(t, 'accountPin', '4821');
      await type(t, 'accountPin2', '4822');
      await tapKey(t, 'submitCreateAccount');
      expect(problemText(t), contains("don't match"));
      expect(server.requests, isEmpty);
      await type(t, 'accountPin2', '4821');
      await tapKey(t, 'submitCreateAccount');
      expect(find.byType(CreateAccountScreen), findsNothing);
      expect(find.text('Signed in on this phone'), findsOneWidget);
      expect(find.byKey(const Key('tileAddChild')), findsOneWidget);
      expect(server.users.values.single.pin, '4821');
      // The PIN is not on the account page or anywhere in the tree.
      expect(find.text('4821'), findsNothing);
    });

    testWidgets('a wrong invite code reads as a sentence, never as a code', (t) async {
      await size(t);
      final Phone p = Phone(server);
      await pumpHub(t, p, name: 'Sam', zone: 'America/Chicago');
      await tapKey(t, 'tileCreateAccount');
      await type(t, 'allowanceCode', 'a-code-that-was-never-issued-1');
      await type(t, 'accountPin', '4821');
      await type(t, 'accountPin2', '4821');
      await tapKey(t, 'submitCreateAccount');
      expect(problemText(t), contains("didn't work"));
      expect(problemText(t), isNot(contains('invalid_allowance')));
      expect(find.byType(CreateAccountScreen), findsOneWidget, reason: 'stays on the form so nothing typed is lost');
    });

    testWidgets('the time zone list has a real region name for each choice, never "same as this phone"', (t) async {
      expect(accountTimeZones.map((z) => z.id), isNot(contains('device')));
      expect(accountTimeZones.every((z) => z.id.contains('/')), isTrue);
      await size(t);
      final Phone p = Phone(server);
      await pumpHub(t, p);
      await tapKey(t, 'tileCreateAccount');
      await tapKey(t, 'accountZone');
      await t.tap(find.text('US Central').last);
      await t.pumpAndSettle();
      expect(find.text('US Central'), findsOneWidget);
    });

    testWidgets('sign in without an account explains how, and is honest that there is no recovery', (t) async {
      await size(t);
      final Phone p = Phone(server);
      await pumpHub(t, p);
      await tapKey(t, 'tileSignIn');
      expect(find.textContaining('My own other device'), findsOneWidget);
      expect(find.textContaining('Olive cannot sign you back in by itself'), findsOneWidget);
    });
  });

  group('signed in', () {
    testWidgets('adding a child: name, date, zone, PIN; then she is listed', (t) async {
      await size(t);
      final Phone p = await signedUp('Sam');
      await pumpHub(t, p, zone: 'America/Chicago', childName: 'Ivy', age: 7);
      expect(find.byKey(const Key('tileAddChild')), findsOneWidget);
      await tapKey(t, 'tileAddChild');
      expect(find.text('Ivy'), findsOneWidget, reason: 'her name from this phone is offered');
      await tapKey(t, 'submitAddChild');
      expect(problemText(t), contains('birth date'));
      await tapKey(t, 'pickBirthDate');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await type(t, 'childPin', '9999');
      await tapKey(t, 'submitAddChild');
      expect(problemText(t), "That PIN isn't right.");
      await type(t, 'childPin', '4821');
      await tapKey(t, 'submitAddChild');
      expect(find.byType(AddChildScreen), findsNothing);
      expect(find.text('On this account'), findsOneWidget);
      expect(find.text('Ivy'), findsOneWidget);
      expect(find.byKey(const Key('tileAddChild')), findsNothing);
    });

    testWidgets('an age that does not match the one on this phone is a note, not a block', (t) async {
      await size(t);
      final Phone p = await signedUp('Sam');
      await pumpHub(t, p, zone: 'America/Chicago', childName: 'Ivy', age: 12);
      await tapKey(t, 'tileAddChild');
      await tapKey(t, 'pickBirthDate');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ageMismatch')), findsOneWidget);
      expect(find.textContaining('keeps the age already set'), findsOneWidget);
    });

    testWidgets('inviting: the code is shown to hand over, not sent; copying says so', (t) async {
      await size(t);
      final Phone p = await signedUp('Sam');
      await p.act((s) => s.addChild(displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      await pumpHub(t, p);
      await tapKey(t, 'invite_${server.children.keys.single}');
      await tapKey(t, 'submitInvite');
      expect(problemText(t), contains('word Ivy will use'));
      await type(t, 'inviteLabel', 'Mama');
      await tapKey(t, 'submitInvite');
      expect(problemText(t), contains('email address'));
      await type(t, 'inviteEmail', 'robin@example.com');
      await type(t, 'invitePin', '4821');
      await tapKey(t, 'submitInvite');
      expect(find.textContaining('Olive does not send this'), findsOneWidget);
      final String code = (t.widget<SelectableText>(find.byKey(const Key('inviteCode')))).data!;
      expect(isServerId(code), isTrue);
      expect(server.invites[code]!.email, 'robin@example.com');
      await tapKey(t, 'copyInviteCode');
      expect(find.text('Copied'), findsOneWidget);
      await tapKey(t, 'doneInvite');
      expect(find.textContaining('Invites you sent'), findsOneWidget);
      expect(find.textContaining('r***@example.com'), findsOneWidget);
      expect(find.textContaining('robin@example.com'), findsNothing, reason: 'the email is masked once the invite is made');
    });

    testWidgets('the inviter\'s yes: names who asked, wants the PIN, and a wrong one adds nobody', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      final AccountChild kid = await sam.act((s) => s.addChild(
          displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      final CreatedInvite inv = await sam.act((s) => s.createInvite(
          childId: kid.id, role: 'guardian', label: 'Mama', email: 'robin@example.com', pin: '4821'));
      final Phone robin = Phone(server);
      await robin.act((s) => s.joinAsNew(inviteCode: inv.code, displayName: 'Robin'));
      AuthSession.use(sam.session);
      await pumpHub(t, sam);
      expect(find.text('Waiting for your yes'), findsOneWidget);
      await tapKey(t, 'waiting_${inv.code}');
      expect(find.textContaining('Robin asked to join as parent or guardian'), findsOneWidget);
      await type(t, 'confirmPin', '0000');
      await tapKey(t, 'submitConfirm');
      expect(problemText(t), "That PIN isn't right.");
      expect(server.guardianship[kid.id], hasLength(1));
      await type(t, 'confirmPin', '4821');
      await tapKey(t, 'submitConfirm');
      expect(find.byType(ConfirmGrownUpScreen), findsNothing);
      expect(server.guardianship[kid.id], hasLength(2));
      expect(find.text('Waiting for your yes'), findsNothing);
      expect(find.textContaining('Robin joined as parent or guardian'), findsOneWidget);
    });

    testWidgets('turning them away is one tap and needs no PIN; they can be told no without being shamed', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      final AccountChild kid = await sam.act((s) => s.addChild(
          displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      final CreatedInvite inv = await sam.act((s) => s.createInvite(
          childId: kid.id, role: 'sitter', label: 'Jo', email: 'jo@example.com', pin: '4821'));
      final Phone jo = Phone(server);
      await jo.act((s) => s.joinAsNew(inviteCode: inv.code, displayName: 'Jo'));
      AuthSession.use(sam.session);
      await pumpHub(t, sam);
      await tapKey(t, 'waiting_${inv.code}');
      await tapKey(t, 'submitTurnAway');
      expect(server.guardianship[kid.id], hasLength(1));
      expect(find.textContaining('You turned this one away'), findsOneWidget);
    });

    testWidgets('an invite that has not been opened can be cancelled from the list', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      final AccountChild kid = await sam.act((s) => s.addChild(
          displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      final CreatedInvite inv = await sam.act((s) => s.createInvite(
          childId: kid.id, role: 'sitter', label: 'Jo', email: 'jo@example.com', pin: '4821'));
      AuthSession.use(sam.session);
      await pumpHub(t, sam);
      await tapKey(t, 'cancel_${inv.code}');
      expect(find.textContaining('You cancelled this invite'), findsOneWidget);
      expect(server.invites[inv.code]!.revoked, isTrue);
    });

    testWidgets('a PIN-less account made from an invite is led to set one before anything asks for it', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      final AccountChild kid = await sam.act((s) => s.addChild(
          displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      final CreatedInvite inv = await sam.act((s) => s.createInvite(
          childId: kid.id, role: 'guardian', label: 'Mama', email: 'robin@example.com', pin: '4821'));
      final Phone robin = Phone(server);
      await robin.act((s) => s.joinAsNew(inviteCode: inv.code, displayName: 'Robin'));
      AuthSession.use(robin.session);
      await pumpHub(t, robin);
      expect(find.byKey(const Key('waitingForInviter')), findsOneWidget);
      expect(find.byKey(const Key('tileSetPin')), findsOneWidget);
      await tapKey(t, 'tileSetPin');
      await type(t, 'newPin', '1234');
      await type(t, 'newPin2', '1234');
      await tapKey(t, 'submitSetPin');
      expect(problemText(t), contains('easy to guess'));
      await type(t, 'newPin', '7391');
      await type(t, 'newPin2', '7391');
      await tapKey(t, 'submitSetPin');
      expect(find.byKey(const Key('tileSetPin')), findsNothing);
      expect(server.users[server.users.keys.last]!.pin, '7391');
    });

    testWidgets('signing out asks first, keeps everything on the phone, and returns to the three ways in', (t) async {
      await size(t);
      final Phone p = await signedUp('Sam');
      AuthSession.use(p.session);
      await pumpHub(t, p);
      await tapKey(t, 'tileSignOut');
      expect(find.textContaining('Everything on this phone stays'), findsOneWidget);
      await tapKey(t, 'confirmSignOut');
      expect(find.byKey(const Key('tileCreateAccount')), findsOneWidget);
      expect(find.text('You are signed out.'), findsOneWidget);
      expect(await p.identities.load(), isNull);
    });

    testWidgets('a sign-in that could not be saved is said loudly, with a way to try again', (t) async {
      await size(t);
      final Phone p = Phone(server);
      p.secure.failWrites = true;
      server.addAllowance(kCode);
      await p.act((s) => s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821'));
      await pumpHub(t, p);
      expect(find.byKey(const Key('unsavedSignIn')), findsOneWidget);
      await tapKey(t, 'retrySaveSignIn');
      expect(find.textContaining('Still could not save it'), findsOneWidget);
      p.secure.failWrites = false;
      await tapKey(t, 'retrySaveSignIn');
      expect(find.byKey(const Key('unsavedSignIn')), findsNothing);
      expect(find.text('Saved. This phone will stay signed in.'), findsOneWidget);
    });

    testWidgets('with no connection the page says what it is showing', (t) async {
      await size(t);
      final Phone p = await signedUp('Sam');
      server.interceptor = (http.BaseRequest _) async => throw Exception('offline');
      AuthSession.use(p.session);
      await pumpHub(t, p);
      expect(find.textContaining("couldn't reach the server just now"), findsOneWidget);
    });

    testWidgets('sign-in check: yes for a working phone', (t) async {
      await size(t);
      final Phone p = await signedUp('Sam');
      AuthSession.use(p.session);
      await pumpHub(t, p);
      await tapKey(t, 'tileSignInCheck');
      await tapKey(t, 'checkSignIn');
      expect(find.text('Yes, this phone is signed in and it works.'), findsOneWidget);
    });
  });

  group('being invited', () {
    Future<(Phone, AccountChild, CreatedInvite)> sent() async {
      final Phone sam = await signedUp('Sam');
      final AccountChild kid = await sam.act((s) => s.addChild(
          displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      final CreatedInvite inv = await sam.act((s) => s.createInvite(
          childId: kid.id, role: 'guardian', label: 'Mama', email: 'robin@example.com', pin: '4821'));
      return (sam, kid, inv);
    }

    testWidgets('paste the code, see who it is for, give a name, then wait for their yes', (t) async {
      await size(t);
      final (Phone _, AccountChild _, CreatedInvite inv) = await sent();
      AuthSession.use(null);
      final Phone robin = Phone(server);
      await pumpHub(t, robin);
      await tapKey(t, 'tileJoin');
      await tapKey(t, 'lookUpInvite');
      expect(problemText(t), contains('does not look like an invite code'));
      await type(t, 'inviteCodeIn', '  ${inv.code}  ');
      await tapKey(t, 'lookUpInvite');
      expect(find.byKey(const Key('inviteFound')), findsOneWidget);
      expect(find.textContaining('r***@example.com'), findsOneWidget);
      expect(find.textContaining('has to say yes, with their PIN'), findsOneWidget);
      await tapKey(t, 'joinAsNew');
      expect(problemText(t), 'Please enter your name.');
      await type(t, 'joinName', 'Robin');
      await tapKey(t, 'joinAsNew');
      expect(find.byType(JoinInviteScreen), findsNothing);
      expect(find.byKey(const Key('waitingForInviter')), findsOneWidget);
      await tapKey(t, 'checkJoin');
      expect(find.textContaining("haven't answered yet"), findsOneWidget);
    });

    testWidgets('a code that is not there is said calmly, and the form stays', (t) async {
      await size(t);
      final Phone robin = Phone(server);
      await pumpHub(t, robin);
      await tapKey(t, 'tileJoin');
      await type(t, 'inviteCodeIn', '00000000-0000-4000-8000-0000000000ff');
      await tapKey(t, 'lookUpInvite');
      expect(problemText(t), contains("wasn't found"));
      expect(find.byKey(const Key('lookUpInvite')), findsOneWidget);
    });

    testWidgets('an invite opened and not finished is offered again on a signed-in phone too', (t) async {
      await size(t);
      final (Phone _, AccountChild _, CreatedInvite inv) = await sent();
      AuthSession.use(null);
      final FakeUser robinUser = server.addUser('Robin', email: 'robin@example.com', pin: '5921');
      final Phone robin = Phone(server);
      final String dev = server.mintDevice(robinUser.id);
      await robin.identities.save(DeviceIdentity(
          sessionToken: server.sessionFor(robinUser.id), deviceId: dev, role: 'guardian', targetId: robinUser.id,
          deviceCredential: server.devices[dev]!.credential));
      await robin.pending.save(PendingJoin(inviteId: inv.code, stage: JoinStage.accepted));
      await pumpHub(t, robin);
      expect(find.byKey(const Key('finishJoining')), findsOneWidget);
      await tapKey(t, 'finishJoining');
      await tapKey(t, 'lookUpInvite');
      expect(find.byKey(const Key('useMyAccount')), findsOneWidget);
      expect(find.byKey(const Key('joinAsNew')), findsNothing, reason: 'a signed-in phone is never offered a second account');
    });

    testWidgets('joining that was started and not finished is offered again on the start page', (t) async {
      await size(t);
      final (Phone _, AccountChild _, CreatedInvite inv) = await sent();
      AuthSession.use(null);
      final Phone robin = Phone(server);
      server.interceptor = (http.BaseRequest r) async => r.url.path.endsWith('/bootstrap') ? throw Exception('cut') : null;
      await expectLater(robin.act((s) => s.joinAsNew(inviteCode: inv.code, displayName: 'Robin')), throwsA(isA<AccountFailure>()));
      server.interceptor = null;
      await pumpHub(t, robin);
      expect(find.byKey(const Key('finishJoining')), findsOneWidget);
      await tapKey(t, 'finishJoining');
      expect(find.byKey(const Key('lookUpInvite')), findsOneWidget);
      // The code is already filled in from what the phone kept.
      expect(find.text(inv.code), findsOneWidget);
    });
  });

  group('looks and reach', () {
    for (final (String label, double w, double h, double scale) c in <(String, double, double, double)>[
      ('a small phone at the largest text size', 320, 640, 2.0),
      ('a tablet', 1000, 700, 1.0),
    ]) {
      testWidgets('every form fits on ${c.$1}', (t) async {
        await size(t, w: c.$2, h: c.$3, scale: c.$4);
        final Phone p = await signedUp('Sam');
        final AccountChild kid = await p.act((s) => s.addChild(
            displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
        final CreatedInvite inv = await p.act((s) => s.createInvite(
            childId: kid.id, role: 'guardian', label: 'Mama', email: 'robin@example.com', pin: '4821'));
        final Phone robin = Phone(server);
        await robin.act((s) => s.joinAsNew(inviteCode: inv.code, displayName: 'Robin'));
        final FamilyAccountService s = p.service;
        final List<Widget> forms = <Widget>[
          CreateAccountScreen(service: s),
          AddChildScreen(service: s),
          InviteGrownUpScreen(service: s, childId: kid.id, childName: 'Ivy'),
          JoinInviteScreen(service: s),
          SignInScreen(service: s, baseUrl: kBase),
          SetAccountPinScreen(service: s),
          ConfirmGrownUpScreen(
              service: s,
              invite: InviteView(
                  id: inv.code, role: 'guardian', label: 'Mama', invitedEmail: 'robin@example.com',
                  state: InviteState.waitingForYou, claimantName: 'Robin')),
        ];
        for (final Widget f in forms) {
          await t.pumpWidget(MaterialApp(home: f));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '${f.runtimeType} overflows at ${c.$1}');
        }
        AuthSession.use(p.session);
        await pumpHub(t, p);
        expect(t.takeException(), isNull, reason: 'the hub overflows at ${c.$1}');
      });
    }

    testWidgets('the hub shows no raw code, status number or underscore word anywhere', (t) async {
      await size(t);
      final Phone p = await signedUp('Sam');
      await p.act((s) => s.addChild(displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      AuthSession.use(p.session);
      await pumpHub(t, p);
      final Iterable<String> texts = t.widgetList<Text>(find.byType(Text)).map((Text w) => w.data ?? '');
      for (final String s in texts) {
        expect(RegExp(r'[a-z]+_[a-z_]+').hasMatch(s), isFalse, reason: '"$s"');
      }
    });
  });
}
