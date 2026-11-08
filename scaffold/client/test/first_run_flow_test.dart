// OLIVE BRANCH — first_run_flow.dart tests: the child build's first run with
// "Connect this device" as the LAST step. No longer UNVERIFIED — verified by
// CI. MASTERFILE §8.5.6.
//
// Drives the real widgets: the welcome questions (offline), the local draft,
// the closing connect step, the calm waiting screen and the picture-only
// offline state.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/access_settings.dart' show kChildTarget;
import 'package:olive_client/first_run_flow.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/onboarding_draft.dart';
import 'package:olive_client/onboarding_logic.dart' show auditOnboardingCopy;
import 'package:olive_client/pairing_redeem_screen.dart';

class _Offline implements Exception {
  @override
  String toString() => 'SocketException: Connection refused (OS Error 111) secret-host.internal';
}

http.Client _online([void Function(http.Request)? onRequest]) => MockClient((http.Request r) async {
      onRequest?.call(r);
      if (r.url.path == '/v1/device-pairing/redeem') {
        return http.Response(jsonEncode(<String, Object?>{
          'sessionToken': 'tok', 'deviceId': 'device-1', 'role': 'child', 'targetId': 'child-1',
          'deviceCredential': 'cred',
        }), 201);
      }
      return http.Response('{}', 404); // any answer at all means "reachable"
    });

http.Client _offline() => MockClient((http.Request r) async => throw _Offline());

void main() {
  Future<void> pumpFlow(
    WidgetTester tester, {
    required OnboardingDraftRepository repo,
    required http.Client client,
    void Function(Map<String, dynamic>)? onRedeemed,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: FirstRunFlow(
      baseUrl: 'http://olive.test', draftRepository: repo, httpClient: client,
      onRedeemed: onRedeemed ?? (_) {})));
    await tester.pumpAndSettle();
  }

  /// Skips every question for real, through the on-screen buttons.
  Future<void> skipAllQuestions(WidgetTester tester) async {
    await tester.tap(find.text("Let's begin"));
    await tester.pumpAndSettle();
    for (final String title in <String>[
      "What's your name?", 'How old are you?', 'Are you a boy or a girl?', 'Pick your colour',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
    }
    expect(find.text('When is your birthday?'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
  }

  group('a fresh device runs the questions first, pairing last', () {
    testWidgets('it opens on the welcome card, NOT on the code field', (tester) async {
      await pumpFlow(tester, repo: MemoryOnboardingDraftRepository(), client: _online());
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text("Let's begin"), findsOneWidget);
      expect(find.byKey(const Key('pairingCodeField')), findsNothing);
      expect(find.textContaining('one last step to connect this device'), findsOneWidget);
    });

    testWidgets('skipping every question reaches Connect this device, and the draft is saved',
        (tester) async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository();
      await pumpFlow(tester, repo: repo, client: _online());
      await skipAllQuestions(tester);

      expect(find.text('Connect this device'), findsOneWidget);
      expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
      final OnboardingDraft? d = await repo.load();
      expect(d, isNotNull);
      expect(d!.complete, isTrue);
      expect(d.name, isNull);
      expect(d.gender, isNull);
      expect(d.birthdayMonth, isNull);
    });

    testWidgets('real answers are collected into the draft, with no network call before the last step',
        (tester) async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository();
      final List<String> requests = <String>[];
      await pumpFlow(tester, repo: repo, client: _online((http.Request r) => requests.add(r.url.path)));
      requests.clear(); // ignore the reachability probe that the connect step makes on entry

      await tester.tap(find.text("Let's begin"));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ivy');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Girl'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // No "who is here" step: nobody is known before a device is connected.
      expect(find.text('Who is here?'), findsNothing);
      expect(find.text('Dad'), findsNothing);
      expect(find.text('Pick your colour'), findsOneWidget);
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('March'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(find.text('My birthday'), findsOneWidget);
      // Nothing was sent anywhere during the questions.
      expect(requests, isEmpty);
      await tester.tap(find.text('All done!'));
      await tester.pumpAndSettle();

      expect(find.text('Connect this device'), findsOneWidget);
      final OnboardingDraft d = (await repo.load())!;
      expect(d.name, 'Ivy');
      expect(d.age, 7);
      expect(d.gender, 'girl');
      expect(d.birthdayMonth, 3);
      expect(d.birthdayDay, 14);
      expect(d.complete, isTrue);
    });

    testWidgets('the questions never use the literal demo-child or the demo names', (tester) async {
      await pumpFlow(tester, repo: MemoryOnboardingDraftRepository(), client: _online());
      await skipAllQuestions(tester);
      expect(find.textContaining('demo'), findsNothing);
      expect(find.textContaining('Ivy'), findsNothing);
    });
  });

  group('a restart resumes at the last step, not the beginning', () {
    testWidgets('a finished draft on disk opens straight on Connect this device', (tester) async {
      final MemoryStoreBackend files = MemoryStoreBackend();
      LocalOnboardingDraftRepository open() => LocalOnboardingDraftRepository(
          LocalServices.memory(childId: kPendingDeviceScope, isLive: true, demoSeeds: false, backend: files)
              .area('onboarding', ownerId: kPendingDeviceScope));

      // Run 1: answer everything.
      await pumpFlow(tester, repo: open(), client: _online());
      await skipAllQuestions(tester);
      expect(find.text('Connect this device'), findsOneWidget);

      // The app is killed.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Run 2: a brand-new widget tree over the same files.
      await pumpFlow(tester, repo: open(), client: _online());
      expect(find.text('Connect this device'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
      expect(find.text("Let's begin"), findsNothing);
      expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
    });

    testWidgets('an unreadable store never traps her: she simply starts the questions', (tester) async {
      await pumpFlow(tester, repo: _BrokenRepo(), client: _online());
      expect(find.text('Welcome'), findsOneWidget);
      await skipAllQuestions(tester);
      // The save failed, but she still reaches the last step this run.
      expect(find.text('Connect this device'), findsOneWidget);
    });
  });

  group('the connect step', () {
    testWidgets('a correct code redeems with role child and hands the result to the caller',
        (tester) async {
      final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
      Map<String, dynamic>? result;
      await pumpFlow(
        tester,
        repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)),
        client: _online((http.Request r) {
          if (r.url.path == '/v1/device-pairing/redeem') {
            calls.add(<String, Object?>{'body': jsonDecode(r.body)});
          }
        }),
        onRedeemed: (Map<String, dynamic> r) => result = r,
      );
      await tester.enterText(find.byKey(const Key('pairingCodeField')), '123456');
      await tester.tap(find.byKey(const Key('pairingConnectButton')));
      await tester.pump();
      await tester.pump();
      expect(calls, hasLength(1));
      expect(calls.single['body'], <String, Object?>{'code': '123456', 'role': 'child'});
      expect(result?['deviceId'], 'device-1');
    });

    testWidgets('the draft is untouched by redeeming: only the caller clears it, after the upload',
        (tester) async {
      final MemoryOnboardingDraftRepository repo =
          MemoryOnboardingDraftRepository(const OnboardingDraft(gender: 'boy', complete: true));
      await pumpFlow(tester, repo: repo, client: _online());
      await tester.enterText(find.byKey(const Key('pairingCodeField')), '123456');
      await tester.tap(find.byKey(const Key('pairingConnectButton')));
      await tester.pump();
      await tester.pump();
      expect((await repo.load())?.gender, 'boy');
    });

    testWidgets('a wrong code gets calm fixed copy and no raw error text', (tester) async {
      final http.Client client = MockClient((http.Request r) async {
        if (r.url.path == '/v1/device-pairing/redeem') {
          return http.Response(jsonEncode(<String, Object?>{'error': 'not_found'}), 404);
        }
        return http.Response('{}', 404);
      });
      await pumpFlow(tester,
          repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)), client: client);
      await tester.enterText(find.byKey(const Key('pairingCodeField')), '000000');
      await tester.tap(find.byKey(const Key('pairingConnectButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pairingErrorMessage')), findsOneWidget);
      expect(find.textContaining("doesn't match"), findsOneWidget);
      expect(find.textContaining('not_found'), findsNothing);
      expect(find.textContaining('404'), findsNothing);
    });

    testWidgets('it says in plain words that a grown-up gives the 6-digit code, with no pressure, '
        'and shows an ask-a-grown-up picture', (tester) async {
      await pumpFlow(tester,
          repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)),
          client: _online());
      expect(find.textContaining('A grown-up gives you a number with 6 digits'), findsOneWidget);
      expect(find.textContaining('no hurry'), findsOneWidget);
      expect(find.byIcon(Icons.escalator_warning_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Ask a grown-up to give you the code'), findsOneWidget);
    });

    testWidgets('P2 and the onboarding copy rules hold: no score, count, rank, praise or "try again"',
        (tester) async {
      await pumpFlow(tester,
          repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)),
          client: _online());
      final String all = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join(' | ');
      expect(auditOnboardingCopy(all).ok, isTrue, reason: auditOnboardingCopy(all).found.join(','));
      for (final String bad in <String>['score', 'streak', 'rank', 'points', 'badge', 'of 7', 'step 7']) {
        expect(all.toLowerCase(), isNot(contains(bad)), reason: bad);
      }
    });

    testWidgets('every control is at least 64dp tall (the child target)', (tester) async {
      await pumpFlow(tester,
          repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)),
          client: _online());
      expect(kChildTarget, 64);
      for (final Key k in const <Key>[
        Key('pairingConnectButton'), Key('pairingScanQrButton'), Key('pairingNotNowButton'),
      ]) {
        final Size s = tester.getSize(find.byKey(k));
        expect(s.height, greaterThanOrEqualTo(64), reason: '$k is ${s.height}dp tall');
      }
    });
  });

  group('"Not now" is a calm pause, never a skip', () {
    testWidgets('it goes to a waiting screen that keeps the draft and offers the code again',
        (tester) async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(
          const OnboardingDraft(name: 'Ivy', gender: 'girl', complete: true));
      await pumpFlow(tester, repo: repo, client: _online());
      await tester.tap(find.byKey(const Key('pairingNotNowButton')));
      await tester.pumpAndSettle();

      expect(find.text('Waiting for a grown-up'), findsOneWidget);
      expect(find.byKey(const Key('pairingCodeField')), findsNothing);
      expect((await repo.load())?.name, 'Ivy', reason: 'the draft is kept');
      final Size s = tester.getSize(find.byKey(const Key('firstRunConnectAgain')));
      expect(s.height, greaterThanOrEqualTo(64));
      final String text = tester.widgetList<Text>(find.byType(Text)).map((Text t) => t.data ?? '').join(' ');
      expect(auditOnboardingCopy(text).ok, isTrue);

      await tester.tap(find.byKey(const Key('firstRunConnectAgain')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
      expect((await repo.load())?.name, 'Ivy');
    });

    testWidgets('there is no way past the connect step except connecting: no Skip, no Next',
        (tester) async {
      await pumpFlow(tester,
          repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)),
          client: _online());
      expect(find.text('Skip for now'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Next'), findsNothing);
    });
  });

  group('no connection at the last step', () {
    testWidgets('a picture-only "needs a grown-up and a connection" state with a retry, and no raw error',
        (tester) async {
      await pumpFlow(tester,
          repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)),
          client: _offline());
      expect(find.byKey(const Key('pairingOfflinePicture')), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.escalator_warning_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('This needs a grown-up and a connection'), findsOneWidget);
      expect(find.byKey(const Key('pairingRetryButton')), findsOneWidget);
      expect(find.byKey(const Key('pairingCodeField')), findsNothing);
      // Never the exception's text, never a sentence about servers.
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('secret-host'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('server'), findsNothing);
      expect(tester.getSize(find.byKey(const Key('pairingRetryButton'))).height, greaterThanOrEqualTo(64));
    });

    testWidgets('the draft survives and "Not now" is still offered while offline', (tester) async {
      final MemoryOnboardingDraftRepository repo =
          MemoryOnboardingDraftRepository(const OnboardingDraft(name: 'Ivy', complete: true));
      await pumpFlow(tester, repo: repo, client: _offline());
      expect(find.byKey(const Key('pairingNotNowButton')), findsOneWidget);
      expect((await repo.load())?.name, 'Ivy');
    });

    testWidgets('retry returns to the code field once the connection is back', (tester) async {
      bool up = false;
      final http.Client client = MockClient((http.Request r) async {
        if (!up) throw _Offline();
        return http.Response('{}', 404);
      });
      await pumpFlow(tester,
          repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)), client: client);
      expect(find.byKey(const Key('pairingOfflinePicture')), findsOneWidget);

      up = true;
      await tester.tap(find.byKey(const Key('pairingRetryButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pairingOfflinePicture')), findsNothing);
      expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
    });

    testWidgets('losing the connection while redeeming shows the same picture-only state',
        (tester) async {
      bool down = false;
      final http.Client client = MockClient((http.Request r) async {
        if (down) throw _Offline();
        return http.Response('{}', 404);
      });
      await pumpFlow(tester,
          repo: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)), client: client);
      expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
      down = true;
      await tester.enterText(find.byKey(const Key('pairingCodeField')), '123456');
      await tester.tap(find.byKey(const Key('pairingConnectButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pairingOfflinePicture')), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.byKey(const Key('pairingErrorMessage')), findsNothing);
    });
  });

  group('the standalone pairing screen is unchanged for everyone else', () {
    testWidgets('the guardian build still opens on the code screen and says why it connects first',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: PairingRedeemScreen(
          baseUrl: 'http://olive.test', role: 'guardian', onRedeemed: (_) {},
          httpClient: _online())));
      await tester.pump();
      expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
      expect(find.byKey(const Key('pairingGuardianWhy')), findsOneWidget);
      expect(find.textContaining('PIN is kept safely on your account'), findsOneWidget);
      expect(find.byKey(const Key('pairingNotNowButton')), findsNothing);
    });
  });
}

class _BrokenRepo implements OnboardingDraftRepository {
  @override
  Future<OnboardingDraft?> load() async => throw StateError('unreadable');
  @override
  Future<void> save(OnboardingDraft draft) async => throw StateError('unwritable');
  @override
  Future<void> clear() async => throw StateError('unwritable');
}
