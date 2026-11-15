// OLIVE BRANCH — the Android push and incoming-call native side, checked against its Dart and server twins.
// MASTERFILE §11, §5.25.2, §7.18.
//
// There is no Gradle run in this test (CI's `verify` compiles the Kotlin: `:app:compileDebugKotlin`). What this proves is
// everything a compiler cannot: that the two sides of each bridge agree on names, that the notification channels
// are the ones the SERVER names, that the receiver reads only what a content-free push carries, that the words a
// child's tablet can show are soft, that nothing refuses or counts, and that no Firebase credential file is in the
// tree or can be committed by accident.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_lifecycle.dart' show isCallSessionId;
import 'package:olive_client/incoming_call_channel.dart';

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

const _kotlin = 'android/app/src/main/kotlin/com/olivebranch/olive_client';

void main() {
  final notifications = _read('$_kotlin/OliveNotifications.kt');
  final receiver = _read('$_kotlin/OlivePushReceiver.kt');
  final bridge = _read('$_kotlin/IncomingCallBridge.kt');
  final activity = _read('$_kotlin/MainActivity.kt');
  final manifest = _read('android/app/src/main/AndroidManifest.xml');
  final strings = _read('android/app/src/main/res/values/strings.xml');
  final pushTs = _read('../packages/transport/src/push.ts');
  final fcmTs = _read('../packages/transport/src/fcm.ts');
  final knockDart = _read('lib/call_knock.dart');

  String? kotlinConst(String source, String name) =>
      RegExp('const val $name = "([^"]*)"').firstMatch(source)?.group(1) ??
      RegExp('private const val $name = "([^"]*)"').firstMatch(source)?.group(1);

  group('the channels are the ones the server names', () {
    test('push.ts puts a push on exactly `calls` or `reminders`', () {
      final ids = RegExp(r"'(calls|reminders)'").allMatches(pushTs).map((m) => m.group(1)).toSet();
      expect(ids, <String>{'calls', 'reminders'});
      expect(RegExp(r"channelId: input\.kind === 'call_incoming' \|\| input\.kind === 'call_cancelled'\s*\? 'calls' : 'reminders'")
          .hasMatch(pushTs), isTrue, reason: 'the channel rule in push.ts changed; re-read OliveNotifications.kt');
    });

    test('the server sends the channel in the FCM v1 body', () {
      expect(fcmTs.contains('channel_id: payload.android.channelId'), isTrue);
    });

    test('OliveNotifications.kt creates both, by the same ids', () {
      expect(kotlinConst(notifications, 'CHANNEL_CALLS'), 'calls');
      expect(kotlinConst(notifications, 'CHANNEL_REMINDERS'), 'reminders');
      expect(notifications.contains('createNotificationChannels'), isTrue);
    });

    test('MainActivity creates them at start-up, before any push can need them', () {
      expect(activity.contains('OliveNotifications.ensureChannels(this)'), isTrue);
    });

    test('neither channel shows a launcher badge (a badge is a count)', () {
      expect('setShowBadge(false)'.allMatches(notifications).length, 2);
      expect(notifications.contains('setShowBadge(true)'), isFalse);
    });
  });

  group('the Dart and Kotlin ends of the bridge agree', () {
    test('channel name', () {
      expect(kotlinConst(bridge, 'METHOD_CHANNEL'), IncomingCallChannel.methodChannel.name);
    });
    test('every method name', () {
      expect(kotlinConst(bridge, 'M_ATTACH'), IncomingCallChannel.mAttach);
      expect(kotlinConst(bridge, 'M_RING_FINISHED'), IncomingCallChannel.mRingFinished);
      expect(kotlinConst(bridge, 'M_STATUS'), IncomingCallChannel.mStatus);
      expect(kotlinConst(bridge, 'M_REQUEST_NOTIFICATIONS'), IncomingCallChannel.mRequestNotifications);
      expect(kotlinConst(bridge, 'M_OPEN_FULL_SCREEN_SETTINGS'), IncomingCallChannel.mOpenFullScreenSettings);
    });
    test('both events and both keys', () {
      expect(kotlinConst(bridge, 'E_RING'), IncomingCallChannel.eRing);
      expect(kotlinConst(bridge, 'E_CANCEL'), IncomingCallChannel.eCancel);
      expect(kotlinConst(bridge, 'K_REF'), IncomingCallChannel.kRef);
      expect(kotlinConst(bridge, 'K_AT'), IncomingCallChannel.kAt);
      expect(kotlinConst(notifications, 'EXTRA_REF'), IncomingCallChannel.kRef);
    });
    test('the status answer has the two keys the Dart card reads', () {
      expect(bridge.contains('"notifications" to'), isTrue);
      expect(bridge.contains('"fullScreen" to'), isTrue);
    });
    test('MainActivity registers the bridge on the engine', () {
      expect(activity.contains('IncomingCallBridge.register(this, MethodChannel(messenger, IncomingCallBridge.METHOD_CHANNEL))'), isTrue);
      expect(activity.contains('IncomingCallBridge.handleIntent(this, intent)'), isTrue);
      expect(activity.contains('override fun onNewIntent'), isTrue);
      expect(activity.contains('IncomingCallBridge.onPermissionResult'), isTrue);
    });
    test('both sides believe the same session ids', () {
      final kt = RegExp(r'Regex\("(.*?)"\)').firstMatch(notifications)!.group(1)!;
      expect(kt, r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      expect(isCallSessionId('3F2C1A9E-7D4B-4C1E-9A55-0B1C2D3E4F50'), isTrue);
    });
  });

  group('the knock, not an alarm (§5.25.2)', () {
    test('it removes itself after the knock\'s own ninety seconds', () {
      final dartSeconds = int.parse(RegExp(r'const int knockWaitsSeconds = (\d+);').firstMatch(knockDart)!.group(1)!);
      final kotlinMs = int.parse(RegExp(r'const val RING_WINDOW_MS = ([0-9_]+)L').firstMatch(notifications)!.group(1)!.replaceAll('_', ''));
      expect(kotlinMs, dartSeconds * 1000);
      expect(notifications.contains('.setTimeoutAfter(RING_WINDOW_MS)'), isTrue);
    });
    test('it is a call-category heads-up with a full-screen intent, posted once and quietly re-posted', () {
      expect(notifications.contains('Notification.CATEGORY_CALL'), isTrue);
      expect(notifications.contains('.setFullScreenIntent(pending, true)'), isTrue);
      expect(notifications.contains('.setOnlyAlertOnce(true)'), isTrue);
    });
    test('it has no action buttons: the answers live on the knock screen, and no phone button offers a refusal', () {
      expect(notifications.contains('addAction'), isFalse);
      expect(notifications.contains('Action.Builder'), isFalse);
    });
    test('it uses no ringtone, no looping sound, no alarm stream, no repeated insistent flag', () {
      for (final bad in <String>['RingtoneManager', 'FLAG_INSISTENT', 'USAGE_ALARM', 'USAGE_NOTIFICATION_RINGTONE', 'setSound', 'MediaPlayer', 'setOngoing(true)']) {
        expect(notifications.contains(bad), isFalse, reason: bad);
      }
    });
    test('it stays out of an open app (the app knocks itself; lock-task mode hides banners anyway)', () {
      expect(receiver.contains('if (!OliveNotifications.appInForeground(context))'), isTrue);
    });
    test('the call_cancelled push only takes the notification away', () {
      final branch = RegExp(r'KIND_CALL_CANCELLED -> ([^\n]*)').firstMatch(receiver)!.group(1)!;
      expect(branch.trim(), 'OliveNotifications.cancelRing(context, ref)');
    });
  });

  group('the receiver reads only what a content-free push carries', () {
    test('only `kind` and `ref`', () {
      expect(kotlinConst(notifications, 'EXTRA_KIND'), 'kind');
      expect(kotlinConst(notifications, 'EXTRA_REF'), 'ref');
      final reads = RegExp(r'extras\.get\w+\(([^)]*)\)').allMatches(receiver).map((m) => m.group(1)).toList();
      expect(reads, <String?>['OliveNotifications.EXTRA_KIND', 'OliveNotifications.EXTRA_REF']);
    });

    test('none of push.ts\'s forbidden keys, nor callHandle, nor the notification block, appears in any native file', () {
      final listBody = RegExp(r'FORBIDDEN_DATA_KEYS = \[([\s\S]*?)\] as const').firstMatch(pushTs)!.group(1)!;
      final forbidden = RegExp(r"'([A-Za-z_]+)'").allMatches(listBody).map((m) => m.group(1)!).toList();
      expect(forbidden, contains('childName'));
      for (final f in <String>[...forbidden, 'callHandle', 'RemoteMessage', 'getNotification']) {
        for (final src in <String, String>{'receiver': receiver, 'notifications': notifications, 'bridge': bridge}.entries) {
          expect(src.value.contains('"$f"'), isFalse, reason: '${src.key} reads "$f"');
        }
      }
      expect(receiver.contains('callHandle'), isFalse);
    });

    test('a kind the receiver does not know does nothing, and a ref that is not a session id stops it first', () {
      expect(receiver.contains('if (!OliveNotifications.isSessionId(ref)) return'), isTrue);
      final whens = RegExp(r'KIND_CALL_(INCOMING|CANCELLED) ->').allMatches(receiver).length;
      expect(whens, 2);
    });

    test('the kinds are the server\'s', () {
      expect(pushTs.contains("'call_incoming'"), isTrue);
      expect(pushTs.contains("'call_cancelled'"), isTrue);
      expect(kotlinConst(receiver, 'KIND_CALL_INCOMING'), 'call_incoming');
      expect(kotlinConst(receiver, 'KIND_CALL_CANCELLED'), 'call_cancelled');
    });

    test('only Google Play services can ring it: the c2dm SEND permission, the RECEIVE action, nothing else', () {
      final block = RegExp(r'<receiver[\s\S]*?</receiver>').firstMatch(manifest)!.group(0)!;
      expect(block.contains('android:name=".OlivePushReceiver"'), isTrue);
      expect(block.contains('android:exported="true"'), isTrue);
      expect(block.contains('android:permission="com.google.android.c2dm.permission.SEND"'), isTrue);
      expect('<action '.allMatches(block).length, 1);
      expect(block.contains('com.google.android.c2dm.intent.RECEIVE'), isTrue);
      expect(kotlinConst(receiver, 'ACTION_RECEIVE'), 'com.google.android.c2dm.intent.RECEIVE');
    });
  });

  group('the lock screen and the kiosk rules', () {
    test('the ring may show over the lock screen but never dismisses it', () {
      for (final bad in <String>['requestDismissKeyguard', 'KeyguardManager', 'FLAG_DISMISS_KEYGUARD', 'DISMISS_KEYGUARD']) {
        expect(bridge.contains(bad), isFalse, reason: bad);
        expect(activity.contains(bad), isFalse, reason: bad);
      }
      expect(bridge.contains('setShowWhenLocked(on)'), isTrue);
    });
    test('it lets go of the lock screen when the activity stops or the ring is put away', () {
      expect(activity.contains('IncomingCallBridge.onActivityStopped(this)'), isTrue);
      expect(RegExp(r'fun onActivityStopped[\s\S]*?showOverLockScreen\(activity, false\)').hasMatch(bridge), isTrue);
      expect(RegExp(r'M_RING_FINISHED -> \{[\s\S]*?showOverLockScreen\(activity, false\)').hasMatch(bridge), isTrue);
    });
    test('an intent is consumed when read, so a recreated activity cannot ring twice', () {
      expect(bridge.contains('intent.action = null'), isTrue);
    });
    test('an old or malformed ring intent is refused', () {
      expect(bridge.contains('if (!OliveNotifications.isSessionId(ref)) return'), isTrue);
      expect(bridge.contains('System.currentTimeMillis() - at > OliveNotifications.RING_WINDOW_MS'), isTrue);
    });
    test('the kiosk bridge is untouched by calling: no lock-task call anywhere in the new files', () {
      for (final src in <String>[notifications, receiver, bridge]) {
        expect(src.contains('LockTask'), isFalse);
        expect(src.contains('startLockTask'), isFalse);
        expect(src.contains('KioskBridge'), isFalse);
      }
    });
  });

  group('the manifest', () {
    test('declares the full-screen-intent permission and the notification permission, and no foreground service', () {
      expect(manifest.contains('android.permission.USE_FULL_SCREEN_INTENT'), isTrue);
      expect(manifest.contains('android.permission.POST_NOTIFICATIONS'), isTrue);
      expect(manifest.contains('FOREGROUND_SERVICE'), isFalse);
    });
    test('the ring intent action matches between the notification and the bridge', () {
      expect(kotlinConst(bridge, 'ACTION_RING'), 'com.olivebranch.olive_client.INCOMING_RING');
      expect(notifications.contains('action = IncomingCallBridge.ACTION_RING'), isTrue);
    });
  });

  group('the words a child\'s tablet can show', () {
    final values = RegExp(r'<string name="([^"]+)">([^<]*)</string>').allMatches(strings).map((m) => MapEntry(m.group(1)!, m.group(2)!)).toList();
    test('there are exactly the strings the code uses', () {
      final used = RegExp(r'R\.string\.(\w+)').allMatches(notifications).map((m) => m.group(1)).toSet();
      expect(values.map((e) => e.key).toSet(), used);
    });
    test('soft, no refusal, no error, no count, no name, no placeholder', () {
      expect(values, isNotEmpty);
      for (final e in values) {
        final lower = e.value.toLowerCase();
        for (final bad in <String>['declin', 'reject', 'refus', 'dismiss', 'ignor', 'missed', 'error', 'fail', 'sorry', 'wrong',
            'urgent', 'emergency', 'alert!', 'now!', 'dad', 'mom', 'mommy', 'daddy', 'mother', 'father']) {
          expect(lower.contains(bad), isFalse, reason: '${e.key} says "$bad"');
        }
        expect(RegExp(r'\d').hasMatch(e.value), isFalse, reason: '${e.key} carries a number');
        expect(e.value.contains('%'), isFalse, reason: '${e.key} has a placeholder');
        expect(e.value.contains('!'), isFalse, reason: '${e.key} shouts');
      }
    });
    test('the ring says only that someone would like to talk', () {
      final text = values.firstWhere((e) => e.key == 'olive_ring_text').value;
      expect(text, 'Someone would like to talk.');
    });
  });

  group('no Firebase credential is in the tree or can be committed by accident', () {
    Iterable<File> files(Directory d) sync* {
      for (final e in d.listSync(recursive: false, followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name == 'build' || name == '.dart_tool' || name == '.gradle' || name == 'node_modules' || name == '.git') continue;
        if (e is Directory) {
          yield* files(e);
        } else if (e is File) {
          yield e;
        }
      }
    }

    test('no google-services.json or GoogleService-Info.plist anywhere under the client or the scaffold', () {
      final hits = <String>[];
      for (final root in <String>['android', 'lib', 'test', '../tools', '../server', '../docker-compose.dev.yml']) {
        final d = Directory(root);
        if (!d.existsSync()) continue;
        for (final f in files(d)) {
          final n = f.uri.pathSegments.last;
          if (n == 'google-services.json' || n == 'GoogleService-Info.plist') hits.add(f.path);
        }
      }
      expect(hits, isEmpty);
    });

    test('the Google services Gradle plugin is not applied (Firebase starts from run-time settings)', () {
      for (final g in <String>['android/build.gradle.kts', 'android/settings.gradle.kts', 'android/app/build.gradle.kts']) {
        final src = _read(g);
        expect(src.contains('com.google.gms'), isFalse, reason: g);
        expect(src.contains('google-services'), isFalse, reason: g);
      }
    });

    test('.gitignore keeps the secrets folder and any Firebase config file out of git', () {
      final ignore = _read('../../.gitignore');
      expect(RegExp(r'^scaffold/secrets/\s*$', multiLine: true).hasMatch(ignore), isTrue);
      expect(RegExp(r'^\*\*/google-services\.json\s*$', multiLine: true).hasMatch(ignore), isTrue);
      expect(RegExp(r'^\*\*/GoogleService-Info\.plist\s*$', multiLine: true).hasMatch(ignore), isTrue);
    });

    test('the child build carries no analytics, crash-reporting or ad SDK', () {
      final pubspec = _read('pubspec.yaml');
      for (final bad in <String>['firebase_analytics', 'firebase_crashlytics', 'firebase_performance', 'google_mobile_ads',
          'firebase_remote_config', 'firebase_in_app_messaging', 'sentry', 'amplitude', 'mixpanel']) {
        expect(RegExp('^\\s+$bad:', multiLine: true).hasMatch(pubspec), isFalse, reason: bad);
      }
    });

    test('push_config.dart has no default for any setting (a value in source would be a value in git)', () {
      final src = _read('lib/push_config.dart');
      for (final name in <String>['OLIVE_FCM_PROJECT_ID', 'OLIVE_FCM_APP_ID', 'OLIVE_FCM_API_KEY', 'OLIVE_FCM_SENDER_ID']) {
        expect(RegExp("String\\.fromEnvironment\\('$name'\\)").hasMatch(src), isTrue, reason: name);
        expect(src.contains("'$name',"), isFalse, reason: '$name has a defaultValue');
      }
    });
  });
}
