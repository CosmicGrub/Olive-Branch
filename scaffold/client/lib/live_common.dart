// OLIVE BRANCH — the dart-defines and the one-time start-up both live shells share.
// No longer UNVERIFIED — verified by CI (client/test/main_live_test.dart,
// client/test/main_live_guardian_test.dart). MASTERFILE §7, §8.5.8.
//
// main_live.dart (the unified live entry) and guardian_boot.dart (the guardian shell's
// boot) used to each declare these constants and each repeat the Firebase block. They
// are declared once here. `bool.hasEnvironment` is what tells "the define is genuinely
// absent" from "the define happens to equal its own default"; a defaultValue comparison
// cannot (see the dev paths in live_boot_plan.dart).
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_channel.dart';
import 'push_config.dart';

const String kLiveBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias
const String kLiveChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy
const String kLiveGuardianId = String.fromEnvironment('OLIVE_GUARDIAN_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000002'); // seed-dev.mjs's Dad

/// True on every `flutter run --dart-define=OLIVE_CHILD_ID=...` invocation, dev or CI.
const bool kHasChildIdDartDefine = bool.hasEnvironment('OLIVE_CHILD_ID');
const bool kHasGuardianIdDartDefine = bool.hasEnvironment('OLIVE_GUARDIAN_ID');

/// Explicit opt-in to the credential-free dev login for a build NOT provisioned through
/// OLIVE_CHILD_ID / OLIVE_GUARDIAN_ID. Off by default: a store build sets none of them
/// and can never reach POST /v1/auth/dev-login (AuthSession.devLoginEnabled stays false).
const bool kDevLoginDartDefine = bool.fromEnvironment('OLIVE_DEV_LOGIN');

/// MASTERFILE §11 — registers the real top-level background handler (push_channel.dart's
/// firebaseMessagingBackgroundHandler) before runApp(), the one place FlutterFire's docs
/// require it.
///
/// A build without Firebase settings (push_config.dart: the four OLIVE_FCM_* defines) does
/// NOTHING here: it never touches the Firebase plugin, logs nothing and shows nothing. That is
/// the normal state of a checkout and of any install the owner has not given a Firebase project
/// to (the app is offline-first; push only ever adds to it).
///
/// With settings, this starts Firebase from them and registers the background handler. It is
/// still wrapped in try/catch: a malformed project must never crash the build before its first
/// frame, and push_channel.dart's PushChannel.initialize(), called later once a real session
/// exists, is the second, independent attempt.
Future<void> initFirebaseForLive() async {
  final FcmConfig? config = FcmConfig.fromEnvironment();
  if (config == null) return;
  try {
    await Firebase.initializeApp(options: config.toFirebaseOptions());
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[olive.push] background handler not registered at boot: $e');
  }
}
