// OLIVE BRANCH — the lost-phone screens, on screen. MASTERFILE section 7.22. Every screen is driven against the in-memory
// server that answers like server/routes.mjs and checks each request against the REAL route table (test/support/).
// Covers: "Forgot your PIN?" and the account page reaching it, one question per screen, the sheet shown once and typed back,
// the waiting period said plainly, the notice and the one thing to do about it, the helper's one power, big text and narrow
// screens, and that nothing on a screen is a code, a status or a stack of jargon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/family_account_screens.dart';
import 'package:olive_client/guardian_pin_recovery_screens.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/recovery_paths_logic.dart';
import 'package:olive_client/recovery_paths_screens.dart';
import 'package:olive_client/recovery_paths_service.dart';
import 'package:olive_client/sheet_printer.dart';

import 'support/account_rig.dart';
import 'support/fake_identity_server.dart';
import 'support/recovery_fake.dart';

class _FakePrinter implements SheetPrinter {
  _FakePrinter({this.works = true});
  final bool works;
  final List<String> pages = <String>[];
  @override
  Future<bool> printSheet({required String title, required String html}) async {
    pages.add(html);
    return works;
  }
}

void main() {
  late DateTime clock;
  late FakeIdentityServer server;
  late RecoveryFake rf;

  setUp(() {
    clock = DateTime.utc(2026, 11, 21, 12);
    server = FakeIdentityServer(now: () => clock);
    rf = RecoveryFake(server);
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

  RecoveryPathsService svc(Phone p, {MemoryPendingRecoveryStore? pending, MemoryHelperKeyStore? helper}) => RecoveryPathsService(
      baseUrl: kBase,
      account: p.service,
      client: server.client,
      pending: pending ?? MemoryPendingRecoveryStore(),
      helper: helper ?? MemoryHelperKeyStore(),
      now: server.now);

  Future<void> pumpIn(WidgetTester t, Phone p, Widget screen) async {
    // The screens are driven as the phone's own: its session is the process-wide one while the screen runs.
    AuthSession.use(p.session);
    // The old screen is taken away first, so a screen of the same kind starts again and reads the server again (a
    // second pumpWidget of the same widget type would otherwise keep the first one's state).
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpWidget(MaterialApp(home: screen));
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

  String allText(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((Text w) => w.data ?? '').join(' | ');

  final RegExp jargon = RegExp(r'token|credential|hash|revoke|session|encrypt|exception|json|http|status code|null\b', caseSensitive: false);
  void plain(WidgetTester t) {
    final String s = allText(t);
    expect(jargon.hasMatch(s), isFalse, reason: s);
    expect(RegExp(r'[a-z]+_[a-z_]+').hasMatch(s), isFalse, reason: 'a code is on screen: $s');
    expect(s.contains('Exception'), isFalse);
  }

  group('reaching it', () {
    testWidgets('"Forgot your PIN?" offers "I lost my phone", and only when the build offers it', (t) async {
      await size(t);
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      await t.pumpWidget(MaterialApp(home: ForgotPinScreen(pin: pin, recovery: null)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('forgotLostPhone')), findsNothing);

      int opened = 0;
      await t.pumpWidget(MaterialApp(home: ForgotPinScreen(pin: pin, recovery: null, onLostPhone: () => opened++)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('forgotNoRecovery')), findsOneWidget, reason: 'the old words are still there');
      await tapKey(t, 'forgotLostPhone');
      expect(opened, 1);
      expect(find.textContaining("I lost my phone, or I'm on a new phone"), findsOneWidget);
    });

    testWidgets('the account page: "Lost your phone?" comes first when signed out, and the sign-up page warns against a second account',
        (t) async {
      await size(t);
      final Phone p = Phone(server);
      final RecoveryPathsService r = svc(p);
      await t.pumpWidget(MaterialApp(home: FamilyAccountScreen(service: p.service, baseUrl: kBase, recovery: r)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tileLostPhone')), findsOneWidget);
      final double lost = t.getTopLeft(find.byKey(const Key('tileLostPhone'))).dy;
      final double make = t.getTopLeft(find.byKey(const Key('tileCreateAccount'))).dy;
      expect(lost, lessThan(make), reason: 'it must be seen before "Make an account"');
      await tapKey(t, 'tileCreateAccount');
      expect(find.byKey(const Key('newAccountWarning')), findsOneWidget);
      expect(find.textContaining('Do not make another one'), findsOneWidget);
    });

    testWidgets('a build with no recovery service shows none of it', (t) async {
      await size(t);
      final Phone p = Phone(server);
      await t.pumpWidget(MaterialApp(home: FamilyAccountScreen(service: p.service, baseUrl: kBase)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tileLostPhone')), findsNothing);
    });

    testWidgets('signed in: the safety tile is there, and the notice banner appears only while a recovery waits', (t) async {
      await size(t);
      final Phone mom = await signedUp('Mom');
      final Phone dad = await signedUp('Dad', pin: '2468');
      final String momId = await userIdOf(mom), dadId = await userIdOf(dad);
      rf.makeParents(momId, dadId);
      final RecoveryPathsService r = svc(mom);
      await pumpIn(t, mom, FamilyAccountScreen(service: mom.service, baseUrl: kBase, recovery: r));
      expect(find.byKey(const Key('tileLostPhoneSafety')), findsOneWidget);
      expect(find.byKey(const Key('recoveryBanner')), findsNothing);
      await dad.act((_) => svc(dad).startFor(targetUserId: momId, pin: '2468'));
      await pumpIn(t, mom, FamilyAccountScreen(service: mom.service, baseUrl: kBase, recovery: r));
      expect(find.byKey(const Key('recoveryBanner')), findsOneWidget);
      expect(find.textContaining('Dad started getting your account onto a new phone'), findsOneWidget);
    });
  });

  group('"Lost your phone?"', () {
    testWidgets('one question, four honest answers, and a line against making a new account', (t) async {
      await size(t);
      final Phone p = Phone(server);
      await pumpIn(t, p, LostPhoneScreen(service: svc(p), account: p.service));
      for (final String k in <String>['tileGrownUpHelp', 'tileSheet', 'tileServerCode', 'tileBeHelper', 'noNewAccountNote']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('resumeRecovery')), findsNothing);
      expect(find.textContaining('Please do not make a new account'), findsOneWidget);
      expect(find.textContaining('Nothing is lost'), findsOneWidget);
      plain(t);
    });

    testWidgets('one grown-up: the sheet starts it, the wait is said in words, and a restart finds it again', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      final String key = await sam.act((_) => svc(sam).makeSheet(pin: '4821'));
      final Phone fresh = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(fresh, pending: pend);
      await pumpIn(t, fresh, LostPhoneScreen(service: s, account: fresh.service));
      await tapKey(t, 'tileSheet');
      expect(find.textContaining('Olive waits 3 days'), findsOneWidget);
      await type(t, 'sheetKeyField', key.toLowerCase());
      await tapKey(t, 'startWithSheet');
      expect(find.byKey(const Key('phaseWaiting')), findsOneWidget);
      expect(find.textContaining('You can finish'), findsOneWidget);
      expect(find.textContaining('about 3 days from now'), findsOneWidget);
      expect(find.textContaining('Every phone on the account has been told'), findsOneWidget);
      plain(t);
      // the key is not left in a box
      expect(find.text(key), findsNothing);
      expect(await pend.load(), isNotNull);

      // "restart": a new LostPhoneScreen on the same storage offers to carry on
      await pumpIn(t, fresh, LostPhoneScreen(service: s, account: fresh.service));
      expect(find.byKey(const Key('resumeRecovery')), findsOneWidget);
    });

    testWidgets('a wrong key is one sentence, nothing was changed, and no code is shown', (t) async {
      await size(t);
      final Phone fresh = Phone(server);
      await pumpIn(t, fresh, UseSheetScreen(service: svc(fresh), account: fresh.service));
      await type(t, 'sheetKeyField', 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF');
      await tapKey(t, 'startWithSheet');
      expect(find.byKey(const Key('recoveryProblem')), findsOneWidget);
      expect(find.textContaining("didn't match"), findsOneWidget);
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      plain(t);
    });

    testWidgets('another grown-up helps: code typed, the wait, then PIN to finish, then "You\'re back"', (t) async {
      await size(t);
      final Phone mom = await signedUp('Mom');
      final Phone dad = await signedUp('Dad', pin: '2468');
      final String momId = await userIdOf(mom), dadId = await userIdOf(dad);
      rf.makeParents(momId, dadId);
      rf.usersWithLivePhone.addAll(<String>{momId, dadId});
      final HelpStarted h = await dad.act((_) => svc(dad).startFor(targetUserId: momId, pin: '2468'));

      final Phone momNew = Phone(server);
      final RecoveryPathsService s = svc(momNew);
      await pumpIn(t, momNew, UseGrownUpCodeScreen(service: s, account: momNew.service));
      await type(t, 'grownUpCodeField', h.code);
      await tapKey(t, 'useGrownUpCode');
      expect(find.byKey(const Key('phaseWaiting')), findsOneWidget);

      clock = clock.add(const Duration(hours: 48, minutes: 5));
      await tapKey(t, 'checkAgain');
      expect(find.byKey(const Key('phaseReady')), findsOneWidget);
      await type(t, 'proofPinField', '0000');
      await tapKey(t, 'finishRecovery');
      expect(find.byKey(const Key('recoveryProblem')), findsOneWidget);
      expect(find.textContaining('Nobody else is locked out'), findsOneWidget);
      // the PIN box is emptied once sent
      expect(t.widget<TextField>(find.descendant(of: find.byKey(const Key('proofPinField')), matching: find.byType(TextField))).controller!.text, isEmpty);
      await type(t, 'proofPinField', '4821');
      await tapKey(t, 'finishRecovery');
      expect(find.byKey(const Key('recoveredDone')), findsOneWidget);
      expect(find.textContaining('signed out'), findsOneWidget);
      expect(find.textContaining('Nothing was made new and nothing was moved'), findsOneWidget);
      plain(t);
      expect((await momNew.identities.load())!.targetId, momId);
    });

    testWidgets('a stopped recovery says so and how, changes nothing, and offers to start again', (t) async {
      await size(t);
      final Phone mom = await signedUp('Mom');
      final Phone dad = await signedUp('Dad', pin: '2468');
      final String momId = await userIdOf(mom), dadId = await userIdOf(dad);
      rf.makeParents(momId, dadId);
      final HelpStarted h = await dad.act((_) => svc(dad).startFor(targetUserId: momId, pin: '2468'));
      final Phone momNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(momNew, pending: pend);
      await momNew.act((_) => s.useGrownUpCode(h.code));
      await mom.act((_) => svc(mom).stop(requestId: h.requestId, pin: '4821'));
      await pumpIn(t, momNew, RecoveryWaitScreen(service: s, account: momNew.service));
      expect(find.byKey(const Key('phaseOver')), findsOneWidget);
      expect(find.textContaining("stopped from the account's own phone"), findsOneWidget);
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      expect(find.byKey(const Key('finishRecovery')), findsNothing);
      await tapKey(t, 'startAgain');
      expect(await pend.load(), isNull);
    });

    testWidgets('the helper is needed: the wait is over and the screen says whose yes is missing', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      final String key = await sam.act((_) => svc(sam).makeSheet(pin: '4821'));
      await sam.act((_) => svc(sam).nameHelper(name: 'Jo', pin: '4821'));
      final Phone helper = Phone(server);
      // the invite was just made: accept it the way the helper would
      final String invite = rf.helpers.values.single.invite;
      await helper.act((_) => svc(helper).acceptHelperInvite(invite));
      final Phone samNew = Phone(server);
      final RecoveryPathsService s = svc(samNew);
      await samNew.act((_) => s.startWithSheet(key));
      clock = clock.add(const Duration(hours: 73));
      await pumpIn(t, samNew, RecoveryWaitScreen(service: s, account: samNew.service));
      expect(find.byKey(const Key('phaseWaitingHelper')), findsOneWidget);
      expect(find.textContaining('Your trusted helper has to say yes'), findsOneWidget);
      expect(find.byKey(const Key('finishRecovery')), findsNothing);
      plain(t);
    });
  });

  group('while the phone works', () {
    testWidgets('making the sheet: shown once, printed, typed back, then gone from the screen', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      final _FakePrinter printer = _FakePrinter();
      await pumpIn(t, sam, MakeSheetScreen(service: svc(sam), printer: printer, accountName: 'Sam', now: () => clock));
      await type(t, 'sheetPinField', '4821');
      await tapKey(t, 'sheetMake');
      expect(find.byKey(const Key('sheetShown')), findsOneWidget);
      final String shown = rf.sheets.values.single;
      expect(shown.length, 24);
      expect(find.byKey(const Key('sheetKey')), findsOneWidget);
      await tapKey(t, 'sheetPrint');
      expect(printer.pages, hasLength(1));
      expect(printer.pages.single, contains(groupRecoveryCode(shown)));
      expect(find.byKey(const Key('printNote')), findsOneWidget);
      await tapKey(t, 'sheetSaved');
      expect(find.byKey(const Key('sheetKey')), findsNothing, reason: 'the key is no longer on the screen');
      expect(find.byKey(const Key('sheetShown')), findsNothing);
      await type(t, 'sheetTypedField', 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF');
      await tapKey(t, 'sheetCheck');
      expect(find.byKey(const Key('recoveryProblem')), findsOneWidget);
      expect(find.textContaining("isn't the key from your sheet"), findsOneWidget);
      await type(t, 'sheetTypedField', groupRecoveryCode(shown).toLowerCase());
      await tapKey(t, 'sheetCheck');
      expect(find.byKey(const Key('sheetKept')), findsOneWidget);
      expect(rf.sheetConfirmed.values.single, isNotNull);
      expect(allText(t).contains(groupRecoveryCode(shown)), isFalse);
      plain(t);
    });

    testWidgets('a phone that cannot print says to write it down by hand; leaving before checking asks first', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      await pumpIn(t, sam, Builder(builder: (BuildContext c) => Scaffold(
          body: Center(child: FilledButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(c).push<void>(MaterialPageRoute<void>(
                  builder: (BuildContext _) => MakeSheetScreen(service: svc(sam), printer: _FakePrinter(works: false)))),
              child: const Text('open'))))));
      await tapKey(t, 'open');
      await type(t, 'sheetPinField', '4821');
      await tapKey(t, 'sheetMake');
      await tapKey(t, 'sheetPrint');
      expect(find.textContaining('Write the key down by hand'), findsOneWidget);
      // leaving without checking: asked first, "Stay" keeps the key on screen
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.textContaining('shown only once'), findsWidgets);
      await tapKey(t, 'stayOnSheet');
      expect(find.byKey(const Key('sheetKey')), findsOneWidget);
    });

    testWidgets('a wrong PIN makes no sheet and says so in words', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      await pumpIn(t, sam, MakeSheetScreen(service: svc(sam), printer: _FakePrinter()));
      await type(t, 'sheetPinField', '0000');
      await tapKey(t, 'sheetMake');
      expect(find.byKey(const Key('recoveryProblem')), findsOneWidget);
      expect(find.textContaining("isn't right"), findsOneWidget);
      expect(rf.sheets, isEmpty);
    });

    testWidgets('naming a helper: a first name and the PIN, then a code to hand over; what a helper can do is said', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      await pumpIn(t, sam, NameHelperScreen(service: svc(sam)));
      await type(t, 'helperNameField', 'jo@example.test');
      await type(t, 'helperPinField', '4821');
      await tapKey(t, 'helperMake');
      expect(find.byKey(const Key('recoveryProblem')), findsOneWidget);
      await type(t, 'helperNameField', 'Aunt Sam');
      await type(t, 'helperPinField', '4821');
      await tapKey(t, 'helperMake');
      expect(find.byKey(const Key('helperCodeShown')), findsOneWidget);
      expect(find.textContaining('Give this code to Aunt Sam'), findsOneWidget);
      expect(find.textContaining('cannot see your family'), findsOneWidget);
      expect(find.textContaining('Olive does not send it'), findsOneWidget);
      plain(t);
    });

    testWidgets('the safety screen: a waiting recovery is a card with one thing to do, which needs the PIN', (t) async {
      await size(t);
      final Phone mom = await signedUp('Mom');
      final Phone dad = await signedUp('Dad', pin: '2468');
      final String momId = await userIdOf(mom), dadId = await userIdOf(dad);
      rf.makeParents(momId, dadId);
      final HelpStarted h = await dad.act((_) => svc(dad).startFor(targetUserId: momId, pin: '2468'));
      await pumpIn(t, mom, RecoverySafetyScreen(service: svc(mom), now: () => clock));
      expect(find.byKey(Key('notice_${h.requestId}')), findsOneWidget);
      expect(find.textContaining('If you did not ask for this, stop it now'), findsOneWidget);
      await tapKey(t, 'stop_${h.requestId}');
      await type(t, 'askPinField', '0000');
      await tapKey(t, 'askPinYes');
      expect(find.byKey(const Key('recoveryProblem')), findsOneWidget);
      expect(rf.reqs[h.requestId]!.cancelledBy, isNull, reason: 'a phone left unlocked cannot stop it without the PIN');
      await tapKey(t, 'stop_${h.requestId}');
      await type(t, 'askPinField', '4821');
      await tapKey(t, 'askPinYes');
      expect(rf.reqs[h.requestId]!.cancelledBy, 'owner_phone');
      expect(find.byKey(Key('notice_${h.requestId}')), findsNothing);
      expect(find.textContaining('Lately'), findsOneWidget);
      plain(t);
    });

    testWidgets('the safety screen: sheet and helper states in words, and "Help someone" only when there is someone', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      await pumpIn(t, sam, RecoverySafetyScreen(service: svc(sam), now: () => clock));
      expect(find.textContaining('You have not made one yet'), findsOneWidget);
      expect(find.textContaining('You have not named anyone'), findsOneWidget);
      expect(find.byKey(const Key('tileHelpSomeone')), findsNothing);
      expect(find.byKey(const Key('tileImHelper')), findsOneWidget);
      await sam.act((_) => svc(sam).makeSheet(pin: '4821'));
      await pumpIn(t, sam, RecoverySafetyScreen(service: svc(sam), now: () => clock));
      expect(find.textContaining('You have not shown that you kept it yet'), findsOneWidget);
      expect(find.byKey(const Key('checkSheet')), findsOneWidget);
      plain(t);
    });

    testWidgets('helping another grown-up: who, your PIN is your yes, then the code and what happens next', (t) async {
      await size(t);
      final Phone mom = await signedUp('Mom');
      final Phone dad = await signedUp('Dad', pin: '2468');
      final String momId = await userIdOf(mom), dadId = await userIdOf(dad);
      rf.makeParents(momId, dadId);
      await pumpIn(t, dad, HelpGrownUpScreen(service: svc(dad), people: <CanHelp>[CanHelp(userId: momId, name: 'Mom')]));
      expect(find.textContaining('Only say yes if you have spoken to them yourself'), findsOneWidget);
      await type(t, 'helpPinField', '2468');
      await tapKey(t, 'helpStart');
      expect(find.byKey(const Key('helpCodeShown')), findsOneWidget);
      expect(find.textContaining('Give this code to Mom'), findsOneWidget);
      expect(find.textContaining('Nothing changes for 2 days'), findsOneWidget);
      plain(t);
    });
  });

  group('the helper\'s side', () {
    testWidgets('a helper can only say yes or no: one screen, two buttons, nothing about the family', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      final String key = await sam.act((_) => svc(sam).makeSheet(pin: '4821'));
      await sam.act((_) => svc(sam).nameHelper(name: 'Jo', pin: '4821'));
      final Phone helper = Phone(server);
      final RecoveryPathsService h = svc(helper);
      await helper.act((_) => h.acceptHelperInvite(rf.helpers.values.single.invite));
      final Phone samNew = Phone(server);
      await samNew.act((_) => svc(samNew).startWithSheet(key));
      final String reqId = rf.reqs.keys.single;

      await pumpIn(t, helper, HelperHomeScreen(service: h, now: () => clock));
      expect(find.byKey(const Key('helperIdentity')), findsOneWidget);
      expect(find.textContaining("Sam's trusted helper"), findsOneWidget);
      expect(find.textContaining('cannot sign in as them'), findsOneWidget);
      expect(find.byKey(Key('request_$reqId')), findsOneWidget);
      // the whole of the helper's power: these two buttons, and housekeeping
      expect(find.byType(FilledButton), findsOneWidget);
      await tapKey(t, 'yes_$reqId');
      expect(find.textContaining('Only say yes if you have spoken to Sam yourself'), findsOneWidget);
      await tapKey(t, 'confirmAnswer');
      expect(rf.reqs[reqId]!.helperConfirmed, isTrue);
      expect(find.byKey(const Key('helperNote')), findsOneWidget);
      expect(find.textContaining('You have said yes'), findsOneWidget);
      plain(t);
    });

    testWidgets('a helper removed by the grown-up is told so, calmly, and is not a helper any more', (t) async {
      await size(t);
      final Phone sam = await signedUp('Sam');
      await sam.act((_) => svc(sam).nameHelper(name: 'Jo', pin: '4821'));
      final Phone helper = Phone(server);
      final MemoryHelperKeyStore hk = MemoryHelperKeyStore();
      final RecoveryPathsService h = svc(helper, helper: hk);
      await helper.act((_) => h.acceptHelperInvite(rf.helpers.values.single.invite));
      await sam.act((_) => svc(sam).removeHelper(pin: '4821'));
      await pumpIn(t, helper, HelperHomeScreen(service: h));
      expect(find.byKey(const Key('notAHelper')), findsOneWidget);
      expect(find.textContaining('You do not need to do anything'), findsOneWidget);
      expect(await hk.load(), isNull);
      plain(t);
    });

    testWidgets('typing a helper code that is wrong is one sentence', (t) async {
      await size(t);
      final Phone p = Phone(server);
      await pumpIn(t, p, BecomeHelperScreen(service: svc(p)));
      await type(t, 'helperInviteField', 'AAAA-BBBB-CCCC-DDDD');
      await tapKey(t, 'helperAccept');
      expect(find.textContaining("didn't work"), findsOneWidget);
      plain(t);
    });
  });

  group('big text and narrow screens', () {
    for (final (String label, double w, double scale) in <(String, double, double)>[
      ('320 wide, normal text', 320, 1.0),
      ('320 wide, twice the text', 320, 2.0),
      ('600 wide, 1.5 times the text', 600, 1.5),
    ]) {
      testWidgets('$label: the screens lay out with no overflow', (t) async {
        await size(t, w: w, h: 1600, scale: scale);
        final Phone sam = await signedUp('Sam');
        final Phone fresh = Phone(server);
        final RecoveryPathsService s = svc(fresh);
        final List<Widget> screens = <Widget>[
          LostPhoneScreen(service: s, account: fresh.service),
          UseSheetScreen(service: s, account: fresh.service),
          UseGrownUpCodeScreen(service: s, account: fresh.service),
          BecomeHelperScreen(service: s),
          MakeSheetScreen(service: svc(sam), printer: _FakePrinter()),
          NameHelperScreen(service: svc(sam)),
          RecoverySafetyScreen(service: svc(sam)),
        ];
        for (final Widget screen in screens) {
          await pumpIn(t, screen is MakeSheetScreen || screen is NameHelperScreen || screen is RecoverySafetyScreen ? sam : fresh, screen);
          expect(t.takeException(), isNull, reason: '${screen.runtimeType}');
        }
        // and the key itself, in large type, at the narrowest width
        await pumpIn(t, sam, MakeSheetScreen(service: svc(sam), printer: _FakePrinter()));
        await type(t, 'sheetPinField', '4821');
        await tapKey(t, 'sheetMake');
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('sheetKey')), findsOneWidget);
      });
    }
  });
}
