// OLIVE BRANCH — the client half of the security follow-ups (MASTERFILE section 7.12): the guardian PIN rides the
// export and invite calls, the first PIN on an account that holds a passkey asks for a fresh passkey assertion, and
// the adult-side "type your PIN" step is honest. Verified by CI, headless.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/guardian_setup.dart' show PasskeyOutcome;
import 'package:olive_client/guardian_step_up.dart';
import 'package:olive_client/webauthn_channel.dart';

http.Response _json(Object body, [int code = 200]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = WebAuthnChannel.methodChannel;
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  group('the PIN rides the calls the server step-up guards', () {
    test('both exports send it in the x-guardian-pin header, never in the URL', () async {
      final seen = <http.BaseRequest>[];
      final api = OliveApi('http://api.test', 'tok', client: MockClient((req) async {
        seen.add(req);
        return _json({'bundleJson': '{}', 'attestation': <String, Object?>{}});
      }));
      await api.fetchRawExport('child-a', pin: '5193');
      await api.fetchCertifiedExport('child-a', pin: '5193');
      expect(seen, hasLength(2));
      for (final r in seen) {
        expect(r.headers['x-guardian-pin'], '5193');
        expect(r.url.toString(), isNot(contains('5193')));
      }
      expect(seen[1].url.queryParameters['kind'], 'certified');
    });

    test('an invite sends it in the body; a passkey add sends it only when given', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = OliveApi('http://api.test', 'tok', client: MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _json({'ok': true});
      }));
      await api.createGuardianInvite('child-a', role: 'guardian', label: 'X', invitedEmail: 'x@x.com', pin: '5193');
      await api.submitWebauthnRegisterVerify(clientDataJSON: 'cd', attestationObject: 'ao', pin: '5193');
      await api.submitWebauthnRegisterVerify(clientDataJSON: 'cd', attestationObject: 'ao');
      expect(bodies[0]['pin'], '5193');
      expect(bodies[1]['pin'], '5193');
      expect(bodies[2].containsKey('pin'), isFalse, reason: 'the invite-bootstrap first credential sends none');
    });

    test('a refused step-up is thrown to the screen, not turned into success', () async {
      final api = OliveApi('http://api.test', 'tok',
          client: MockClient((req) async => _json({'error': 'pin_incorrect'}, 403)));
      await expectLater(api.fetchRawExport('c', pin: '1111'),
          throwsA(isA<ApiException>().having((e) => e.error, 'error', 'pin_incorrect')));
    });
  });

  group('first PIN on an account that holds a passkey', () {
    test('passkey_assertion_required: the provider is asked once and the PIN is retried with the assertion', () async {
      final posts = <Map<String, dynamic>>[];
      final api = OliveApi('http://api.test', 'tok',
          client: MockClient((req) async {
            posts.add(jsonDecode(req.body) as Map<String, dynamic>);
            return posts.length == 1 ? _json({'error': 'passkey_assertion_required'}, 403) : _json({'ok': true});
          }),
          passkeyAssertion: (OliveApi a) async => {
                'credentialId': 'c', 'clientDataJSON': 'd', 'authenticatorData': 'a', 'signature': 's',
              });
      await api.setGuardianPin('5193');
      expect(posts, hasLength(2));
      expect(posts[0].containsKey('assertion'), isFalse);
      expect((posts[1]['assertion'] as Map)['signature'], 's');
      expect(posts[1]['pin'], '5193');
    });

    test('no provider, or a cancelled prompt: the refusal reaches the caller and nothing is retried', () async {
      var calls = 0;
      final refuse = MockClient((req) async {
        calls++;
        return _json({'error': 'passkey_assertion_required'}, 403);
      });
      await expectLater(OliveApi('http://api.test', 'tok', client: refuse).setGuardianPin('5193'),
          throwsA(isA<ApiException>().having((e) => e.error, 'error', 'passkey_assertion_required')));
      expect(calls, 1);
      calls = 0;
      final cancelling = OliveApi('http://api.test', 'tok',
          client: refuse, passkeyAssertion: (OliveApi a) async => throw WebAuthnException('user_cancelled', null));
      await expectLater(cancelling.setGuardianPin('5193'), throwsA(isA<WebAuthnException>()));
      expect(calls, 1, reason: 'no second POST after a cancelled prompt');
    });

    test('an account with no passkey is unchanged: one POST, no prompt', () async {
      var asked = false;
      var calls = 0;
      final api = OliveApi('http://api.test', 'tok',
          client: MockClient((req) async {
            calls++;
            return _json({'ok': true});
          }),
          passkeyAssertion: (OliveApi a) async {
            asked = true;
            return {};
          });
      await api.setGuardianPin('5193');
      expect(calls, 1);
      expect(asked, isFalse);
    });

    test('platformPasskeyAssertion: asks the server for a challenge, runs the ceremony over it, returns the four fields', () async {
      String? sentChallenge;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == WebAuthnChannel.mAuthenticate) {
          sentChallenge = (call.arguments as Map)['challenge'] as String?;
          return {'credentialId': 'cred', 'clientDataJSON': 'cd', 'authenticatorData': 'ad', 'signature': 'sig'};
        }
        return null;
      });
      final api = OliveApi('http://api.test', 'tok', client: MockClient((req) async {
        expect(req.url.path, '/v1/me/pin/passkey-challenge');
        return _json({'challenge': 'chal-1', 'rpId': 'olive.test'});
      }));
      final a = await platformPasskeyAssertion(api);
      expect(sentChallenge, 'chal-1');
      expect(a, {'credentialId': 'cred', 'clientDataJSON': 'cd', 'authenticatorData': 'ad', 'signature': 'sig'});
    });

    test('plain adult words for every way it can fail; null for anything else', () {
      expect(guardianPinSetupMessage(const WebAuthnUnavailable()), contains("can't confirm with a passkey"));
      expect(guardianPinSetupMessage(WebAuthnException('user_cancelled', null)), contains('Nothing was changed'));
      expect(guardianPinSetupMessage(WebAuthnException('other', null)), contains('was not set'));
      expect(guardianPinSetupMessage(ApiException(403, 'passkey_assertion_failed')), contains('was not set'));
      expect(guardianPinSetupMessage(ApiException(403, 'passkey_assertion_required')), contains('passkey'));
      expect(guardianPinSetupMessage(ApiException(500, 'internal_error')), isNull);
      expect(guardianPinSetupMessage(StateError('x')), isNull);
    });
  });

  group('adding a passkey asks for the PIN first, before the device prompt', () {
    test('a cancelled PIN ask resolves to declined and neither the challenge nor the device are touched', () async {
      var calls = 0;
      var ceremonies = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        ceremonies++;
        return null;
      });
      final api = OliveApi('http://api.test', 'tok', client: MockClient((req) async {
        calls++;
        return _json({});
      }));
      final outcome = await buildRegisterPasskeyCallback(api: api, userName: 'Dad', pinProvider: () async => null)();
      expect(outcome, PasskeyOutcome.declined);
      expect(calls, 0);
      expect(ceremonies, 0);
    });

    test('the typed PIN is sent with the verify call', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == WebAuthnChannel.mRegister) return {'clientDataJSON': 'cd', 'attestationObject': 'ao'};
        return null;
      });
      Map<String, dynamic>? verifyBody;
      final api = OliveApi('http://api.test', 'tok', client: MockClient((req) async {
        if (req.url.path.endsWith('/register/challenge')) {
          return _json({'challenge': 'c', 'rpId': 'olive.test', 'userId': 'u'});
        }
        verifyBody = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'ok': true});
      }));
      final outcome = await buildRegisterPasskeyCallback(api: api, userName: 'Dad', pinProvider: () async => '5193')();
      expect(outcome, PasskeyOutcome.success);
      expect(verifyBody!['pin'], '5193');
    });
  });

  group('guardian_step_up.dart', () {
    test('words: plain, adult, honest about a lock and a PIN that was never set', () {
      expect(guardianStepUpMessage('pin_incorrect'), contains("doesn't match"));
      expect(guardianStepUpMessage('pin_locked'), contains('15 minutes'));
      expect(guardianStepUpMessage('pin_not_set'), contains("haven't set a PIN"));
      expect(guardianStepUpMessage('pin_required'), contains('digit PIN'));
      expect(guardianStepUpMessage('anything_else'), contains('connection'));
      expect(isPinStepUpError(ApiException(403, 'pin_incorrect')), isTrue);
      expect(isPinStepUpError(ApiException(403, 'not_a_guardian_of_child')), isFalse);
      expect(isPinStepUpError(StateError('x')), isFalse);
    });

    testWidgets('a wrong PIN is asked again with the reason; the right one returns the result; cancel returns null', (t) async {
      final asked = <String?>[];
      final answers = <String?>['1111', '5193'];
      Future<String?> source(BuildContext c, {required String title, String? why, String? error}) async {
        asked.add(error);
        return answers.removeAt(0);
      }

      BuildContext? ctx;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final tried = <String>[];
      final result = await runWithGuardianPin<String>(ctx!, title: 'x', source: source, run: (pin) async {
        tried.add(pin);
        if (pin != '5193') throw ApiException(403, 'pin_incorrect');
        return 'done';
      });
      expect(result, 'done');
      expect(tried, ['1111', '5193']);
      expect(asked, [null, "That PIN doesn't match. Try again."]);

      Future<String?> cancel(BuildContext c, {required String title, String? why, String? error}) async => null;
      expect(await runWithGuardianPin<String>(ctx!, title: 'x', source: cancel, run: (pin) async => 'never'), isNull);
    });

    testWidgets('a locked or never-set PIN is rethrown, not asked again; other failures pass through untouched', (t) async {
      var asks = 0;
      Future<String?> source(BuildContext c, {required String title, String? why, String? error}) async {
        asks++;
        return '5193';
      }

      BuildContext? ctx;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      await expectLater(
          runWithGuardianPin<String>(ctx!, title: 'x', source: source, run: (pin) async => throw ApiException(403, 'pin_locked')),
          throwsA(isA<ApiException>().having((e) => e.error, 'error', 'pin_locked')));
      expect(asks, 1, reason: 'asking again cannot help and must not look like a way around the lockout');
      await expectLater(
          runWithGuardianPin<String>(ctx!, title: 'x', source: source, run: (pin) async => throw ApiException(500, 'internal_error')),
          throwsA(isA<ApiException>().having((e) => e.error, 'error', 'internal_error')));
    });

    testWidgets('the PIN card submits what was typed once, clears the field, and shows the last refusal', (t) async {
      final got = <String>[];
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: GuardianPinCard(
        title: "Confirm it's you",
        why: 'why',
        actionLabel: 'Go',
        error: "That PIN doesn't match. Try again.",
        onSubmit: got.add,
      ))));
      expect(find.byKey(const Key('guardianPinCardError')), findsOneWidget);
      await t.tap(find.byKey(const Key('guardianPinCardGo')));
      expect(got, isEmpty, reason: 'nothing typed, nothing sent');
      await t.enterText(find.byKey(const Key('guardianPinCardField')), '5193');
      await t.tap(find.byKey(const Key('guardianPinCardGo')));
      expect(got, ['5193']);
      expect(t.widget<TextField>(find.byKey(const Key('guardianPinCardField'))).controller!.text, isEmpty);
    });
  });
}
