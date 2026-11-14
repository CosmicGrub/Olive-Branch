// CallGrant parsing, transport policy, calm wording, and the golden grant
// vectors server/call_grant.mjs generates (tools/gen-call-grant-vectors.mjs).
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_provider.dart';

void main() {
  group('CallGrant.fromJson', () {
    test('jitsi', () {
      final g = CallGrant.fromJson({'provider': 'jitsi', 'jwt': 'a.b.c', 'room': 'r',
        'serverURL': 'https://h:8443', 'displayName': 'Dad', 'moderator': true});
      expect(g.kind, CallProviderKind.jitsi);
      expect(g.moderator, true);
      expect(g.observerOnly, false);
    });
    test('no provider field means livekit (older/dev servers)', () {
      final g = CallGrant.fromJson({'token': 't', 'wsURL': 'wss://x'});
      expect(g.kind, CallProviderKind.livekit);
    });
    test('an unusable body never becomes a half-formed join', () {
      expect(() => CallGrant.fromJson({'provider': 'jitsi', 'jwt': 'x'}), throwsFormatException);
      expect(() => CallGrant.fromJson({'provider': 'zoom'}), throwsFormatException);
      expect(() => CallGrant.fromJson({'provider': 'livekit', 'token': ''}), throwsFormatException);
      expect(() => CallGrant.fromJson({}), throwsFormatException);
    });
  });

  group('jitsiServerUrlAllowed — https in release, always', () {
    test('release', () {
      expect(jitsiServerUrlAllowed('https://192.168.1.50:8443', release: true), true);
      expect(jitsiServerUrlAllowed('http://192.168.1.50:8443', release: true), false);
      expect(jitsiServerUrlAllowed('ftp://h', release: true), false);
      expect(jitsiServerUrlAllowed('https://u:p@h', release: true), false);
      expect(jitsiServerUrlAllowed('not a url', release: true), false);
      expect(jitsiServerUrlAllowed('', release: true), false);
    });
    test('debug may also use http for a local server', () {
      expect(jitsiServerUrlAllowed('http://127.0.0.1:8000', release: false), true);
      expect(jitsiServerUrlAllowed('https://h', release: false), true);
    });
  });

  group('calm wording', () {
    test('child lines carry no banned word, address or key', () {
      for (final r in CallUnavailableReason.values) {
        final line = callUnavailableLine(r, isGuardian: false).toLowerCase();
        for (final w in callBannedWords) {
          expect(line.contains(w), false, reason: '$r contains "$w"');
        }
        expect(RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(line), false);
      }
    });
    test('adult lines are plain and differ from the child lines', () {
      for (final r in CallUnavailableReason.values) {
        expect(callUnavailableLine(r, isGuardian: true), isNot(callUnavailableLine(r, isGuardian: false)));
      }
    });
    test('dialing lines name the person', () {
      expect(callingLine('Dad'), 'Calling Dad…');
      expect(joiningLine('Dad'), 'Joining Dad…');
    });
  });

  group('CallViewState', () {
    test('everConnected latches on the first connected phase', () {
      var s = const CallViewState();
      expect(s.everConnected, false);
      s = s.copyWith(phase: CallPhase.connected);
      expect(s.everConnected, true);
      s = s.copyWith(phase: CallPhase.reconnecting).copyWith(phase: CallPhase.ended);
      expect(s.everConnected, true);
    });
  });

  group('FakeCallProvider honours the interface contract', () {
    test('join, mute, camera, leave', () async {
      final f = FakeCallProvider();
      final phases = <CallPhase>[];
      f.states.listen((s) => phases.add(s.phase));
      await f.join(const CallGrant.livekit(token: 't', wsURL: 'w'),
          const CallJoinOptions(displayName: 'Dad', isGuardian: false));
      await f.setMicrophoneEnabled(false);
      await f.setCameraEnabled(false);
      await f.leave();
      await Future<void>.delayed(Duration.zero);
      expect(phases.first, CallPhase.connected);
      expect(phases.last, CallPhase.ended);
      expect(f.calls, ['join', 'mic:false', 'camera:false', 'leave']);
    });
  });

  group('golden grant vectors (Node reference: tools/gen-call-grant-vectors.mjs)', () {
    final file = jsonDecode(File('test/vectors/call_grant_vectors.json').readAsStringSync()) as Map<String, dynamic>;
    final vectors = (file['vectors'] as List).cast<Map<String, dynamic>>();

    test('every success body parses into the right engine', () {
      for (final v in vectors.where((v) => (v['body'] as Map)['error'] == null)) {
        final g = CallGrant.fromJson(v['body'] as Map<String, dynamic>);
        final want = (v['body'] as Map)['provider'] == 'jitsi' ? CallProviderKind.jitsi : CallProviderKind.livekit;
        expect(g.kind, want, reason: v['label'] as String);
      }
    });

    test('the jitsi JWT verifies (HS256) and says what the server decided', () async {
      final hex = file['appSecretHex'] as String;
      final secret = <int>[for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
      for (final v in vectors.where((v) => (v['body'] as Map)['jwt'] != null)) {
        final body = v['body'] as Map<String, dynamic>;
        final parts = (body['jwt'] as String).split('.');
        final mac = await Hmac.sha256().calculateMac(utf8.encode('${parts[0]}.${parts[1]}'), secretKey: SecretKey(secret));
        expect(base64Url.encode(mac.bytes).replaceAll('=', ''), parts[2], reason: v['label'] as String);
        final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
        expect(claims['room'], body['room']);
        final user = ((claims['context'] as Map<String, dynamic>)['user'] as Map<String, dynamic>);
        expect(user['moderator'], body['moderator']);
        final g = CallGrant.fromJson(body);
        expect(g.moderator, body['moderator']);
        expect(g.observerOnly, body['observerOnly']);
      }
    });

    test('the child is never a moderator, the observer is flagged', () {
      final byLabel = {for (final v in vectors) v['label'] as String: v['body'] as Map<String, dynamic>};
      expect(byLabel['jitsi, child joins (not moderator)']!['moderator'], false);
      expect(byLabel['jitsi, observer-only guardian']!['observerOnly'], true);
      expect(byLabel['jitsi, observer-only guardian']!['moderator'], false);
    });

    test('unavailable is a 503 body', () {
      final u = vectors.firstWhere((v) => (v['body'] as Map)['error'] == 'call_provider_unavailable');
      expect(u['status'], 503);
    });
  });
}
