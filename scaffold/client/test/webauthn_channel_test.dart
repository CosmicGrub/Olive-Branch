// OLIVE BRANCH — webauthn_channel.dart's buildVerifyBiometricCallback tests.
// MASTERFILE §5.20, §8.3, §11.
//
// The real HTTP+platform-channel round trip behind guardian escalation's
// biometric factor: webauthnLoginChallenge -> WebAuthnChannel.authenticate
// -> webauthnLoginVerify. Every real failure mode resolves to `false`, never
// an exception escaping to lock_controller.dart's escalate() — see the
// function's own header for why.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/webauthn_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel = WebAuthnChannel.methodChannel;
  const baseUrl = 'http://olive.test';
  const userId = 'guardian-1';

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  http.Client fakeHttp({required bool authenticateSucceeds}) => MockClient((req) async {
    if (req.url.path.endsWith('/login/challenge')) {
      return http.Response(jsonEncode({'challenge': 'c1', 'rpId': 'olive.test'}), 200);
    }
    if (req.url.path.endsWith('/login/verify')) {
      return authenticateSucceeds
        ? http.Response(jsonEncode({'token': 'session-tok'}), 200)
        : http.Response(jsonEncode({'error': 'bad_signature'}), 401);
    }
    return http.Response('not found', 404);
  });

  void mockAuthenticateSucceeds() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == WebAuthnChannel.mAuthenticate) {
        return {
          'credentialId': 'cred-1', 'clientDataJSON': 'cd', 'authenticatorData': 'ad',
          'signature': 'sig',
        };
      }
      return null;
    });
  }

  group('the full real round trip', () {
    test('challenge -> authenticate -> verify all succeeding returns true', () async {
      mockAuthenticateSucceeds();
      final cb = buildVerifyBiometricCallback(
        baseUrl: baseUrl, userId: userId,
        httpClient: fakeHttp(authenticateSucceeds: true),
      );
      expect(await cb(), isTrue);
    });

    test('a server-side verify rejection (e.g. bad signature) returns false, not a throw',
        () async {
      mockAuthenticateSucceeds();
      final cb = buildVerifyBiometricCallback(
        baseUrl: baseUrl, userId: userId,
        httpClient: fakeHttp(authenticateSucceeds: false),
      );
      expect(await cb(), isFalse);
    });
  });

  group('platform ceremony failures — never an exception reaching escalate()', () {
    test('no native handler at all (WebAuthnUnavailable) returns false', () async {
      // No setMockMethodCallHandler call — MissingPluginException path.
      final cb = buildVerifyBiometricCallback(
        baseUrl: baseUrl, userId: userId,
        httpClient: fakeHttp(authenticateSucceeds: true),
      );
      expect(await cb(), isFalse);
    });

    test('the user cancelling the ceremony (WebAuthnException) returns false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: 'user_cancelled');
      });
      final cb = buildVerifyBiometricCallback(
        baseUrl: baseUrl, userId: userId,
        httpClient: fakeHttp(authenticateSucceeds: true),
      );
      expect(await cb(), isFalse);
    });
  });

  group('network failures', () {
    test('an unreachable server returns false, not a throw', () async {
      mockAuthenticateSucceeds();
      final cb = buildVerifyBiometricCallback(
        baseUrl: baseUrl, userId: userId,
        httpClient: MockClient((req) async => throw Exception('no route to host')),
      );
      expect(await cb(), isFalse);
    });
  });
}
