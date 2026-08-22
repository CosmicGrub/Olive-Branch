// OLIVE BRANCH — WebAuthn/passkey platform channel. UNVERIFIED end-to-end on
// this file's own account (no Flutter toolchain in tools/verify.sh's
// automated pipeline) until a real device run proves it — see
// guardian_more.dart's dev-verification tile and this repo's device-testing
// notes for that run's actual result. §7.1, §8.1, §11.
//
// Mirrors android/app/.../WebAuthnBridge.kt (channel app.olive/webauthn) the
// same way kiosk_channel.dart mirrors KioskBridge.kt. Android-only for now —
// no Windows/desktop native implementation exists (see kiosk_channel.dart's
// own Windows stub for the shape a desktop guardian passkey ceremony would
// take; that is a real, separate follow-up, not silently assumed
// unnecessary). Calling on a platform with no native handler throws
// MissingPluginException, surfaced here as [WebAuthnUnavailable] rather than
// folded into [WebAuthnException], because "not implemented on this
// platform" and "the ceremony failed on a platform that DOES implement it"
// are different facts guardian_setup.dart's PasskeyOutcome enum
// (success/declined/unavailable) needs to tell apart honestly.
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'guardian_setup.dart' show PasskeyOutcome;

/// A real, distinct ceremony failure reported by the native side —
/// [code] mirrors WebAuthnBridge.kt's own error codes verbatim
/// ('user_cancelled', 'no_platform_authenticator', 'api_level_too_low',
/// 'provider_not_configured', 'interrupted', `dom_error_<DOMException type>`,
/// `create_credential_failed_<type>` / `get_credential_failed_<type>`).
class WebAuthnException implements Exception {
  WebAuthnException(this.code, this.message);
  final String code;
  final String? message;
  @override
  String toString() => 'WebAuthnException($code${message == null ? "" : ", $message"})';
}

/// Thrown instead of [WebAuthnException] when no platform implementation of
/// this channel exists at all (Windows, `flutter test`) — never confuse this
/// with a real ceremony outcome from a platform that DOES implement it.
class WebAuthnUnavailable implements Exception {
  const WebAuthnUnavailable();
  @override
  String toString() => 'WebAuthnUnavailable()';
}

/// What a real registration ceremony returns — both fields already
/// base64url, ready to POST verbatim to [OliveApi.webauthnRegisterVerify].
class WebAuthnRegistration {
  const WebAuthnRegistration({required this.clientDataJSON, required this.attestationObject});
  final String clientDataJSON;
  final String attestationObject;
}

/// What a real authentication ceremony returns — all fields already
/// base64url, ready to POST verbatim to [webauthnLoginVerify].
class WebAuthnAssertion {
  const WebAuthnAssertion({
    required this.credentialId,
    required this.clientDataJSON,
    required this.authenticatorData,
    required this.signature,
  });
  final String credentialId;
  final String clientDataJSON;
  final String authenticatorData;
  final String signature;
}

class WebAuthnChannel {
  static const methodChannel = MethodChannel('app.olive/webauthn');

  static const mRegister = 'register';
  static const mAuthenticate = 'authenticate';

  /// Runs the real platform passkey REGISTRATION ceremony (Android
  /// Credential Manager, via WebAuthnBridge.kt). [challenge], [rpId], and
  /// [userId] come verbatim from [OliveApi.webauthnRegisterChallenge];
  /// [userName] is shown by the system passkey UI and never read back by the
  /// server (see WebAuthnBridge.kt's own comment on the WebAuthn user
  /// handle).
  Future<WebAuthnRegistration> register({
    required String challenge,
    required String rpId,
    required String userId,
    required String userName,
  }) async {
    try {
      final result = await methodChannel.invokeMapMethod<String, String>(mRegister, {
        'challenge': challenge,
        'rpId': rpId,
        'userId': userId,
        'userName': userName,
      });
      return WebAuthnRegistration(
        clientDataJSON: result!['clientDataJSON']!,
        attestationObject: result['attestationObject']!,
      );
    } on MissingPluginException {
      throw const WebAuthnUnavailable();
    } on PlatformException catch (e) {
      throw WebAuthnException(e.code, e.message);
    }
  }

  /// Runs the real platform passkey AUTHENTICATION ceremony. No credentialId
  /// or allowCredentials narrowing goes in — see WebAuthnBridge.kt's own
  /// header on why this only ever works against a discoverable (resident)
  /// credential, which [register] above deliberately creates.
  Future<WebAuthnAssertion> authenticate({
    required String challenge,
    required String rpId,
  }) async {
    try {
      final result = await methodChannel.invokeMapMethod<String, String>(mAuthenticate, {
        'challenge': challenge,
        'rpId': rpId,
      });
      return WebAuthnAssertion(
        credentialId: result!['credentialId']!,
        clientDataJSON: result['clientDataJSON']!,
        authenticatorData: result['authenticatorData']!,
        signature: result['signature']!,
      );
    } on MissingPluginException {
      throw const WebAuthnUnavailable();
    } on PlatformException catch (e) {
      throw WebAuthnException(e.code, e.message);
    }
  }
}

/// Builds a real [GuardianSetupScreen.registerPasskey] callback: the full
/// challenge -> native ceremony -> verify round trip against the real
/// backend. This is the exact integration point guardian_setup.dart's own
/// header describes ("plugs in as [registerPasskey] without this screen
/// changing shape") — supplying this is what turns that screen's honest stub
/// into a real one. [api] must already hold an authenticated guardian
/// session (see OliveApi) — this function does not create one.
///
/// Never throws: [GuardianSetupScreen] awaits this callback directly with no
/// try/catch of its own (see its `_tap()`), so every real failure mode here
/// — cancellation, no authenticator, a network error reaching the server, a
/// malformed response — resolves to a [PasskeyOutcome] instead of an
/// unhandled exception reaching the widget.
Future<PasskeyOutcome> Function() buildRegisterPasskeyCallback({
  required OliveApi api,
  required String userName,
  WebAuthnChannel? channel,
}) {
  final ch = channel ?? WebAuthnChannel();
  return () async {
    try {
      final challengeBody = await api.requestWebauthnRegisterChallenge();
      final challenge = challengeBody['challenge'] as String;
      final rpId = challengeBody['rpId'] as String;
      final userId = challengeBody['userId'] as String;
      final reg = await ch.register(
        challenge: challenge, rpId: rpId, userId: userId, userName: userName);
      await api.submitWebauthnRegisterVerify(
        clientDataJSON: reg.clientDataJSON, attestationObject: reg.attestationObject);
      return PasskeyOutcome.success;
    } on WebAuthnUnavailable {
      return PasskeyOutcome.unavailable;
    } on WebAuthnException catch (e) {
      switch (e.code) {
        case 'user_cancelled':
          return PasskeyOutcome.declined;
        case 'no_platform_authenticator':
        case 'api_level_too_low':
        case 'provider_not_configured':
          return PasskeyOutcome.unavailable;
        default:
          // 'interrupted', 'dom_error_*', 'create_credential_failed_*', or
          // anything else real-but-unanticipated -- a genuine failure, not a
          // silent success, and not worth inventing a fourth PasskeyOutcome
          // for here (guardian_setup.dart's UI text is the same either way:
          // "could not complete, try again").
          return PasskeyOutcome.declined;
      }
    } on ApiException {
      // The server rejected the challenge/verify call outright (expired
      // session, challenge mismatch, rpId/origin mismatch, ...) -- a real
      // failure, reported the same honest way.
      return PasskeyOutcome.declined;
    } catch (_) {
      // Anything else unanticipated (e.g. no network reaching the server at
      // all) -- still never an unhandled exception reaching the widget.
      return PasskeyOutcome.declined;
    }
  };
}

/// Builds a real `Future<bool> Function()` for kiosk_shell.dart's
/// `verifyBiometric` — the "biometric" half of §8.3's PIN + biometric
/// guardian escalation ceremony (`escalate()`, lock_controller.dart). Runs
/// the exact same real LOGIN round trip webauthnLoginChallenge/
/// webauthnLoginVerify already prove elsewhere (api_client.dart) against the
/// device's own configured guardian [userId] -- a real platform-authenticator
/// assertion, checked server-side, not a device-local biometric prompt taken
/// on faith. The resulting session token is intentionally discarded: this
/// pass closes "escalate() has nowhere to go," not "escalation grants a live
/// guardian API session" -- a real, separate follow-up if that's ever needed,
/// not silently assumed here.
///
/// Never throws, matching [buildRegisterPasskeyCallback]'s own posture: a
/// cancelled ceremony, no platform authenticator, a network failure, or a
/// server-side rejection (expired/consumed challenge, wrong credential, a
/// deactivated account) are all real "no" answers, not exceptions escaping
/// to `escalate()`'s caller -- `false` here always means the PIN factor
/// alone must not be enough, exactly per §8.3.
Future<bool> Function() buildVerifyBiometricCallback({
  required String baseUrl,
  required String userId,
  WebAuthnChannel? channel,
  /// Injectable for tests of the HTTP half (e.g. package:http/testing.dart's
  /// MockClient) -- matches every other real-callback-builder's own
  /// convention in this codebase (capture_gate.dart's httpClient, etc.)
  /// rather than leaving this round trip only exercisable end to end.
  http.Client? httpClient,
}) {
  final ch = channel ?? WebAuthnChannel();
  return () async {
    try {
      final challengeBody = await webauthnLoginChallenge(baseUrl, userId, client: httpClient);
      final assertion = await ch.authenticate(
        challenge: challengeBody['challenge'] as String,
        rpId: challengeBody['rpId'] as String,
      );
      await webauthnLoginVerify(
        baseUrl,
        userId: userId,
        credentialId: assertion.credentialId,
        clientDataJSON: assertion.clientDataJSON,
        authenticatorData: assertion.authenticatorData,
        signature: assertion.signature,
        client: httpClient,
      );
      return true;
    } on WebAuthnUnavailable {
      return false;
    } on WebAuthnException {
      return false; // cancelled / no authenticator / any real ceremony failure
    } on ApiException {
      return false; // server rejected the challenge/verify round trip
    } catch (_) {
      return false; // e.g. no network reaching the server at all
    }
  };
}
