// OLIVE BRANCH — push notification channel (client side). MASTERFILE §11.
//
// UNVERIFIED against a real device — see the file-wide convention this
// codebase uses for exactly this caveat. HONEST STATUS: this compiles, and
// every request shape/registration/
// refresh/dispatch decision below is real code exercised by
// push_channel_test.dart against a mocked HTTP transport and, for the
// Firebase-unconfigured path, against the REAL (unmocked)
// `Firebase.initializeApp()` failure that this environment genuinely
// produces. What has NEVER happened here: a real device requesting
// permission, a real FCM/APNs token, or a real push landing on a real
// device. That needs a real Firebase project's android/app/
// google-services.json (and, if this client ever grows an ios/ platform
// folder, GoogleService-Info.plist) — neither exists in this repo and
// neither is fabricated here (see pubspec.yaml's own comment on why a fake
// one would be worse than none). Server-side, the same caveat applies to
// packages/transport/src/fcm.ts and apns.ts's own missing-credential
// errors — this file's [PushInitializationError] is the client-side twin of
// that same honesty rule.
//
// THE RULE THIS FILE MUST NEVER BREAK (packages/transport/src/push.ts's own
// header, restated here because it binds this file too): a push payload
// carries no content. Not a child's name, not a sender's name, not a
// message body. Both handlers below — [_handleForeground] and the real
// top-level background handler — read ONLY `kind`/`ref`/`callHandle` out of
// a message and construct nothing else from it. Neither ever touches
// `message.notification.title`/`.body`, even though push.ts's own
// buildPush() only ever puts approved, generic strings there today — this
// file does not trust that upstream invariant to hold forever and does not
// need to: [PushPointer] simply has no field a leaked string could occupy.
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'device_channels.dart';

/// Thrown by [PushChannel.initialize] (and, independently, by the top-level
/// background handler below) when `Firebase.initializeApp()` itself fails —
/// overwhelmingly likely because no native Firebase config exists. Named and
/// distinguishable on purpose: a caller must never mistake "push isn't
/// configured in this environment" for "push silently succeeded." Compare
/// fcm.ts's `fcm_config_missing` / apns.ts's equivalent — same rule, client
/// side.
class PushInitializationError implements Exception {
  PushInitializationError(this.cause);
  final Object cause;
  @override
  String toString() =>
      'PushInitializationError: Firebase.initializeApp() failed. This is '
      'expected in any checkout without a real android/app/'
      'google-services.json (see pubspec.yaml) — push notifications are not '
      'configured, not silently broken. Underlying error: $cause';
}

/// `v is String ? v : null` — never `v as String?`. A bare cast throws a
/// TypeError the instant `v` is a non-null, non-String value (an int, a
/// bool, a nested map); this returns null instead, so a malformed data
/// value degrades gracefully rather than crashing whatever's reading it.
String? _asString(dynamic v) => v is String ? v : null;

/// The entire content-free surface a push payload can ever hand this app —
/// deliberately not a raw `Map<String, dynamic>` passthrough. There is no
/// field here a server-side regression of push.ts's own audit could smuggle
/// a name or a message body through, because there is no field for it to
/// land in.
@immutable
class PushPointer {
  const PushPointer({required this.kind, required this.ref, this.callHandle});

  /// One of push.ts's PushKind values — 'call_incoming', 'message_ready',
  /// 'turn_ready', 'exchange_reminder', 'dose_due'. Opaque to this class;
  /// a caller decides what (if anything) to do with it.
  final String kind;

  /// Opaque handle a caller resolves through the authenticated API, post
  /// unlock — never a value this class or its caller may treat as content.
  final String ref;

  /// Present only for kind == 'call_incoming' — push.ts's own
  /// `callRoomHandle` requirement.
  final String? callHandle;

  /// Reads ONLY kind/ref/callHandle out of a message's `data` map. Every
  /// other key — including any FORBIDDEN_DATA_KEYS-shaped leak
  /// (push.ts's own list: childName, senderName, body, text, …) — is
  /// silently, structurally ignored: not filtered out, just never read.
  ///
  /// Uses [_asString] rather than a bare `as String?` cast. FCM's v1 data
  /// map is server-enforced `map<string,string>` (fcm.ts never puts
  /// anything else there), but APNs carries arbitrary custom JSON with NO
  /// type constraint — the day this client ships an ios/ platform folder, a
  /// malformed or adversarial APNs payload (e.g. `"kind": 7`) must degrade
  /// to an empty/null field, not throw an uncaught TypeError inside
  /// [_handleForeground]'s stream listener or the background isolate entry
  /// point. For call_incoming specifically — the kind push.ts's own header
  /// says must ring rather than fail silently — a crash here would mean a
  /// malformed call push never rings at all. Degrading to `''`/`null`
  /// preserves the content-free guarantee fail-closed either way: nothing is
  /// displayed, logged, or forwarded from a value that failed this check.
  factory PushPointer.fromData(Map<String, dynamic> data) => PushPointer(
        kind: _asString(data['kind']) ?? '',
        ref: _asString(data['ref']) ?? '',
        callHandle: _asString(data['callHandle']),
      );

  @override
  String toString() => 'PushPointer(kind: $kind, ref: $ref, '
      'callHandle: ${callHandle == null ? 'null' : '<redacted>'})';
}

/// Real default: wraps `Firebase.initializeApp()` and rethrows as the named
/// [PushInitializationError] on failure. Shared by [PushChannel.initialize]
/// and the top-level background handler below, so both entry points fail
/// the same honest way.
Future<void> _initializeFirebaseOrThrow() async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    throw PushInitializationError(e);
  }
}

/// THE ANDROID BACKGROUND-MESSAGE ENTRY POINT.
///
/// This MUST be a top-level (or static) function, never a closure and never
/// an instance method — Android delivers background messages to a SEPARATE
/// ISOLATE that shares no memory with the app's main isolate, so anything a
/// closure captured (an object, `this`, a variable from an enclosing scope)
/// simply would not exist there. The Flutter engine locates this callback
/// via a compile-time-constant handle it can hand across isolates; only a
/// top-level/static function tear-off can provide one. A closure assigned to
/// `FirebaseMessaging.onBackgroundMessage(...)` compiles without a single
/// warning and then never fires in the background — no crash, no log, just
/// silence. This is exactly the well-known Flutter/Firebase pitfall the task
/// that produced this file called out by name, which is why
/// push_channel_test.dart asserts this function's SHAPE (declared at column
/// 0, `@pragma('vm:entry-point')` immediately above it, assignable to a
/// `const` reference — none of which a closure or instance method could
/// satisfy) rather than merely eyeballing it.
///
/// Because the background isolate shares nothing with the main isolate, this
/// handler must independently initialize its own Firebase app instance —
/// `Firebase.initializeApp()` from `main()` does NOT carry over. Skipping
/// this line is the other half of the same pitfall: code that "looks right"
/// (it compiles, it's top-level) but throws unseen inside a background
/// isolate no one is watching, the moment it tries to touch anything
/// Firebase-related.
///
/// No content-fetch call here, by design, not by oversight — a background
/// isolate has no authenticated session and no UI to unlock into, and the
/// task that produced this file was explicit: do not invent a fetch call
/// for a kind that has no real endpoint on this branch yet. The only real,
/// existing content endpoint today is `GET /v1/children/:childId/inbox`
/// (api_client.dart's `inbox`), which needs a `childId` this payload does
/// not and must not carry (see push.ts's own header on why). So this
/// handler does the one honest thing available to it: log that SOMETHING
/// arrived, using only the opaque pointer, and stop. The real "go open the
/// app" fallback UI lives in [PushChannel]'s foreground handler and, for a
/// tapped notification, wherever this app's own notification-tap routing is
/// eventually built (none exists yet — a background handler cannot build
/// that surface by itself, since it has no UI to show).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _initializeFirebaseOrThrow();
  final pointer = PushPointer.fromData(message.data);
  debugPrint('[olive.push] background message received: kind=${pointer.kind}');
}

/// Test-only injection seam. Every field defaults to the real
/// FirebaseMessaging.instance-backed behavior — a caller that supplies
/// nothing gets exactly the real, non-overridable production path. Exists
/// ONLY because `FirebaseMessaging` has no simple mock-platform story to
/// drive from a black-box widget test in this environment (unlike
/// `KioskChannel`/`WearSyncChannel`, which are thin MethodChannel wrappers
/// this app owns end to end and so can fake by subclassing). Mirrors
/// packages/transport/src/notify.ts's own `NotifyDeviceDeps` — same repo,
/// same reasoning, restated in its own doc comment there.
@immutable
class PushChannelDeps {
  const PushChannelDeps({
    this.initializeFirebase,
    this.requestPermission,
    this.getToken,
    this.onTokenRefresh,
    this.onMessage,
  });

  final Future<void> Function()? initializeFirebase;
  final Future<void> Function()? requestPermission;
  final Future<String?> Function()? getToken;
  final Stream<String>? onTokenRefresh;
  final Stream<RemoteMessage>? onMessage;
}

/// Real permission request, real token retrieval, real registration with the
/// server, and real re-registration on every token refresh — a device token
/// can rotate at any time, not only at first launch (this is FCM's/APNs' own
/// guidance, not a guess), so this listens for the whole lifetime of the
/// channel rather than registering once at startup and forgetting.
class PushChannel {
  PushChannel(
    this.api, {
    this.onForegroundPointer,
    FirebaseMessaging? messaging,
    PushChannelDeps? deps,
  })  : _messagingOverride = messaging,
        _deps = deps ?? const PushChannelDeps();

  final OliveApi api;
  final FirebaseMessaging? _messagingOverride;
  final PushChannelDeps _deps;

  /// Deliberately a LAZY getter, not a field evaluated in the constructor.
  /// `FirebaseMessaging.instance` itself throws `[core/no-app]` the instant
  /// it's touched if `Firebase.initializeApp()` hasn't succeeded yet — which
  /// is every test in push_channel_test.dart that supplies a full
  /// [PushChannelDeps] override and therefore never needs this at all. Were
  /// this a field, simply constructing a [PushChannel] in such a test would
  /// throw before the test got anywhere near what it was actually testing.
  FirebaseMessaging get _messaging => _messagingOverride ?? FirebaseMessaging.instance;

  /// Called with ONLY the content-free [PushPointer] for every foreground
  /// push — never the raw `RemoteMessage`, so there is no call site in this
  /// app that could read `message.notification`/other `message.data` keys
  /// even by accident. Defaults to a debug log ("new activity, open the
  /// app") when a caller supplies nothing — see [_defaultForegroundFallback].
  final void Function(PushPointer pointer)? onForegroundPointer;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<String>? _onRefreshSub;
  String? _lastRegisteredToken;

  /// Real init sequence: Firebase, permission, subscribe to foreground
  /// messages and token refresh, fetch+register the current token. Throws
  /// [PushInitializationError] (never swallows it) if Firebase itself is
  /// unconfigured — callers that want push to be best-effort (e.g. this
  /// client's own live child-home screen, which must not fail to render
  /// just because no Firebase project exists here) catch this at the call
  /// site, not inside this method. See child_home_live.dart's `_initPush`.
  Future<void> initialize() async {
    await (_deps.initializeFirebase ?? _initializeFirebaseOrThrow).call();

    await (_deps.requestPermission ?? _requestPermission).call();

    final messages = _deps.onMessage ?? _defaultOnMessage;
    _onMessageSub = messages.listen(_handleForeground);

    final refresh = _deps.onTokenRefresh ?? _defaultOnTokenRefresh;
    _onRefreshSub = refresh.listen(registerToken);

    final getToken = _deps.getToken ?? _defaultGetToken;
    final token = await getToken();
    if (token != null) await registerToken(token);
  }

  // Everything below this line touches the REAL `firebase_messaging` plugin
  // API and is guarded by [pushSupportedOnThisPlatform] — mirrors
  // wear_sync_channel.dart's own `Platform.isAndroid` guard for the exact
  // same reason: `firebase_core` DOES ship a real Windows implementation
  // (confirmed by the real diff `flutter pub get` made to windows/flutter/
  // generated_plugins.cmake when this dependency was added -- it lists
  // `firebase_core` there), so `Firebase.initializeApp()` above is left
  // unguarded and free to genuinely succeed on this app's other real build
  // target. `firebase_messaging` ships NO Windows implementation at all
  // (that same file lists only `firebase_core`) -- calling any of its real
  // APIs with no native handler registered throws a real, raw
  // MissingPluginException, not a graceful "unsupported" result. Only the
  // REAL defaults are guarded, never a [PushChannelDeps] override: a caller
  // that supplies its own `getToken`/`onTokenRefresh`/`onMessage` has
  // already opted out of touching the real plugin at all, so the platform
  // question does not apply to it (this is exactly what lets
  // push_channel_test.dart exercise the real registration/refresh/dispatch
  // logic on this Windows dev machine without ever hitting this guard).
  Future<void> _requestPermission() async {
    if (!pushSupportedOnThisPlatform) return;
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Stream<RemoteMessage> get _defaultOnMessage =>
      pushSupportedOnThisPlatform ? FirebaseMessaging.onMessage : const Stream<RemoteMessage>.empty();

  Stream<String> get _defaultOnTokenRefresh =>
      pushSupportedOnThisPlatform ? _messaging.onTokenRefresh : const Stream<String>.empty();

  Future<String?> _defaultGetToken() async =>
      pushSupportedOnThisPlatform ? _messaging.getToken() : null;

  /// The single place a token — freshly fetched OR delivered by
  /// `onTokenRefresh` — gets registered with the server (`POST
  /// /v1/me/device-tokens`, api_client.dart's `registerDeviceToken`). Public
  /// (not `_registerToken`) so push_channel_test.dart can simulate a refresh
  /// event through [PushChannelDeps.onTokenRefresh] and assert on the exact
  /// request it produces, without needing to mock `FirebaseMessaging`
  /// itself.
  Future<void> registerToken(String token) async {
    if (token == _lastRegisteredToken) return; // avoid a redundant re-POST
    await api.registerDeviceToken(
      platform: _platform(), token: token, channel: _channel()?.wireValue);
    _lastRegisteredToken = token;
  }

  String _platform() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// §8.11.4 (v0.49.11) — the real channel THIS device can honestly report,
  /// or null when it can't. iOS is unambiguous, so it always reports one;
  /// Android omits the field entirely (see api_client.dart's own
  /// registerDeviceToken doc comment for why omission, not a guessed
  /// value) — this client cannot yet distinguish Play/Amazon/bare Android
  /// (device_channels.dart's own header explains the real, credential-free
  /// native APIs that would, and why building that bridge is out of scope
  /// this pass).
  Channel? _channel() =>
      defaultTargetPlatform == TargetPlatform.iOS ? Channel.ios : null;

  /// §8.11.4 guardian-facing advice for THIS device's own self-reported
  /// channel — real `channelAdvice()` (device_channels.dart), not a stub.
  /// Functionally inert today: the only channel this client can currently
  /// report ('ios') is always push-capable, so this always returns null on
  /// a real device right now. No caller surfaces it in any screen yet
  /// either — there is no settings/notifications screen anywhere in
  /// `client/lib/` as of this pass (checked directly, not assumed). Kept
  /// real and tested rather than omitted so the day Android channel
  /// detection lands, this getter needs no changes to start mattering —
  /// see this file's own registerToken()/_channel() for why 'today' is
  /// narrower than 'always'.
  String? get registrationAdvice {
    final c = _channel();
    return c == null ? null : channelAdvice(c);
  }

  void _handleForeground(RemoteMessage message) {
    final pointer = PushPointer.fromData(message.data);
    (onForegroundPointer ?? _defaultForegroundFallback)(pointer);
  }

  /// Deliberately generic, and deliberately NOT derived from
  /// `message.notification` — see this file's own header. Does not guess at
  /// a content-fetch call for `pointer.kind`: the task that produced this
  /// file was explicit that inventing one for a kind with no real endpoint
  /// on this branch is worse than a plain fallback. A caller with a real
  /// endpoint for a specific kind supplies [onForegroundPointer] instead.
  void _defaultForegroundFallback(PushPointer pointer) {
    debugPrint('[olive.push] New activity — open the app to see what\'s new. '
        '(kind=${pointer.kind})');
  }

  /// Symmetric with the server's `DELETE /v1/me/device-tokens`
  /// (api_client.dart's `unregisterDeviceToken`). No call site in this
  /// client uses this yet — there is no sign-out/log-out flow anywhere in
  /// lib/ as of this pass (confirmed by grep across lib/ before writing
  /// this). Kept here so wiring a future sign-out to also stop pushes is a
  /// one-line call, not a new endpoint to design.
  Future<void> unregister() async {
    final getToken = _deps.getToken ?? _defaultGetToken;
    final token = _lastRegisteredToken ?? await getToken();
    if (token != null) await api.unregisterDeviceToken(token);
  }

  /// Cancels both subscriptions. Callers that construct a [PushChannel] for
  /// the lifetime of a screen/session must call this from their own
  /// `dispose()` — see child_home_live.dart.
  void dispose() {
    _onMessageSub?.cancel();
    _onRefreshSub?.cancel();
  }
}

/// True on the only two platforms `firebase_messaging` actually ships a
/// native implementation for in this project (Android is real; iOS would be
/// real too the day this client grows an ios/ platform folder, which it does
/// not have yet — see pubspec.yaml). Windows (this app's other real build
/// target, see main_live.dart) has no push-notification implementation
/// behind this plugin at all — mirrors wear_sync_channel.dart's own
/// `Platform.isAndroid` guard and the same reasoning: calling a plugin API
/// with no native handler registered throws a real `MissingPluginException`,
/// so a caller on an unsupported platform should check this first rather
/// than relying on catching that exception as its control flow.
bool get pushSupportedOnThisPlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
