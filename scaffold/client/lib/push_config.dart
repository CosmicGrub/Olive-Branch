// OLIVE BRANCH — the Firebase settings a build is given, and nothing else. MASTERFILE §11, §7.18.
//
// WHY THIS FILE EXISTS. A checkout has no Firebase project, so it has no push. The app is offline-first
// (the server enables the live experience, it never gates the local one), so "no Firebase settings" is a
// normal state, not a failure: the app starts the same, shows nothing, says nothing to a child, and simply
// never asks Google for a token. This file is the one place that decides which of those two worlds a build
// is in.
//
// THE SETTINGS COME FROM THE BUILD, NEVER FROM THE REPOSITORY. Four `--dart-define` values (or one
// `--dart-define-from-file`), produced from the owner's own `google-services.json` by
// `tools/fcm-defines.mjs` into the git-ignored `secrets/` folder:
//
//   OLIVE_FCM_PROJECT_ID   the Firebase project id
//   OLIVE_FCM_APP_ID       the Android app id, "1:<number>:android:<hex>"
//   OLIVE_FCM_API_KEY      the Android client key (an identifier, not a password, but still kept out of git)
//   OLIVE_FCM_SENDER_ID    the project number; must equal the number inside the app id
//
// Nothing here fabricates a value or ships a default: with any of the four missing or malformed the whole
// config is null and push stays off. Because the Google services Gradle plugin is not applied (its version
// cannot be verified against this project's Android Gradle Plugin without a Gradle run), Firebase is started
// from these values at run time with `Firebase.initializeApp(options: ...)`.
//
// The values are checked for SHAPE only (a pasted newline, a space, a wrong-looking id and a sender number
// that disagrees with the app id are all refused). Whether Google accepts them is something only a real
// device can say.
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show immutable;

const String kFcmProjectId = String.fromEnvironment('OLIVE_FCM_PROJECT_ID');
const String kFcmAppId = String.fromEnvironment('OLIVE_FCM_APP_ID');
const String kFcmApiKey = String.fromEnvironment('OLIVE_FCM_API_KEY');
const String kFcmSenderId = String.fromEnvironment('OLIVE_FCM_SENDER_ID');

final RegExp _projectIdShape = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');
final RegExp _appIdShape = RegExp(r'^1:(\d{6,20}):android:[0-9a-f]{8,40}$');
final RegExp _senderIdShape = RegExp(r'^\d{6,20}$');
final RegExp _apiKeyShape = RegExp(r'^[A-Za-z0-9_\-]{20,80}$');

@immutable
class FcmConfig {
  const FcmConfig._({
    required this.projectId,
    required this.appId,
    required this.apiKey,
    required this.senderId,
  });

  final String projectId;
  final String appId;
  final String apiKey;
  final String senderId;

  /// The four values as given, or null when any one is missing or not the right shape. Never throws, never
  /// repairs: a value with a space or a newline in it is refused, not trimmed into something that might work.
  static FcmConfig? tryParse({
    required String projectId,
    required String appId,
    required String apiKey,
    required String senderId,
  }) {
    if (!_projectIdShape.hasMatch(projectId)) return null;
    final Match? app = _appIdShape.firstMatch(appId);
    if (app == null) return null;
    if (!_senderIdShape.hasMatch(senderId)) return null;
    if (app.group(1) != senderId) return null; // the app id and the sender number are one project
    if (!_apiKeyShape.hasMatch(apiKey)) return null;
    return FcmConfig._(projectId: projectId, appId: appId, apiKey: apiKey, senderId: senderId);
  }

  /// What this build was given, or null (push off). Compile-time constants, so a build without the defines
  /// carries no Firebase settings at all.
  static FcmConfig? fromEnvironment() => tryParse(
        projectId: kFcmProjectId,
        appId: kFcmAppId,
        apiKey: kFcmApiKey,
        senderId: kFcmSenderId,
      );

  FirebaseOptions toFirebaseOptions() => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
      );

  /// Never the key, never the app id: a log line or an error message cannot leak what is not in it.
  @override
  String toString() => 'FcmConfig(configured)';
}
