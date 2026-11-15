// OLIVE BRANCH — push_config.dart tests. MASTERFILE §11, §7.18.
//
// A build is "push on" only when all four Firebase settings are present AND the right shape. Anything else is
// "push off", silently. These are the cases that matter: the shape of a good one, every way a pasted value goes
// wrong, and that a config never prints what it holds.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/push_config.dart';

void main() {
  const project = 'olive-test-project';
  const number = '123456789012';
  const app = '1:$number:android:0123456789abcdef';
  const key = 'test-only-key-not-real-0123456789';

  FcmConfig? parse({
    String projectId = project,
    String appId = app,
    String apiKey = key,
    String senderId = number,
  }) =>
      FcmConfig.tryParse(projectId: projectId, appId: appId, apiKey: apiKey, senderId: senderId);

  group('a good set of settings', () {
    test('parses and turns into Firebase options with the same four values', () {
      final c = parse();
      expect(c, isNotNull);
      final o = c!.toFirebaseOptions();
      expect(o.projectId, project);
      expect(o.appId, app);
      expect(o.apiKey, key);
      expect(o.messagingSenderId, number);
    });

    test('toString never carries a value', () {
      final s = parse().toString();
      for (final v in <String>[project, app, key, number]) {
        expect(s.contains(v), isFalse, reason: 'toString leaked a setting');
      }
    });
  });

  group('this build (no --dart-define was given)', () {
    test('carries no settings at all, so push is off', () {
      // Compile-time constants: a test run is built without the defines, exactly like a checkout.
      expect(kFcmProjectId, isEmpty);
      expect(kFcmAppId, isEmpty);
      expect(kFcmApiKey, isEmpty);
      expect(kFcmSenderId, isEmpty);
      expect(FcmConfig.fromEnvironment(), isNull);
    });
  });

  group('refused: anything missing or the wrong shape', () {
    test('any one missing', () {
      expect(parse(projectId: ''), isNull);
      expect(parse(appId: ''), isNull);
      expect(parse(apiKey: ''), isNull);
      expect(parse(senderId: ''), isNull);
    });

    test('whitespace and control characters are refused, never trimmed into something that might work', () {
      expect(parse(apiKey: ' $key'), isNull);
      expect(parse(apiKey: '$key '), isNull);
      expect(parse(apiKey: '$key\n'), isNull);
      expect(parse(apiKey: 'abc def ghi jkl mno pqr stu'), isNull);
      expect(parse(projectId: '$project\r\n'), isNull);
      expect(parse(appId: '$app\u0000'), isNull);
      expect(parse(senderId: '$number '), isNull);
    });

    test('a project id with the wrong characters or length', () {
      expect(parse(projectId: 'Olive-Test-Project'), isNull);
      expect(parse(projectId: 'olive_test_project'), isNull);
      expect(parse(projectId: 'abc'), isNull);
      expect(parse(projectId: 'a' * 40), isNull);
      expect(parse(projectId: '../../etc/passwd-0000'), isNull);
    });

    test('an app id for the wrong platform or the wrong form', () {
      expect(parse(appId: '1:$number:ios:0123456789abcdef'), isNull);
      expect(parse(appId: '1:$number:web:0123456789abcdef'), isNull);
      expect(parse(appId: '2:$number:android:0123456789abcdef'), isNull);
      expect(parse(appId: '1:$number:android:XYZ'), isNull);
      expect(parse(appId: 'not-an-app-id'), isNull);
    });

    test('a sender number that is not the app id\'s own project number', () {
      expect(parse(senderId: '999999999999'), isNull);
      expect(parse(senderId: 'abcdefghijkl'), isNull);
    });

    test('an api key that is too short, too long or carries a symbol', () {
      expect(parse(apiKey: 'short'), isNull);
      expect(parse(apiKey: 'a' * 81), isNull);
      expect(parse(apiKey: 'test-only-key-not-real-0123456789!'), isNull);
      expect(parse(apiKey: 'test-only-key-not-real-01234567="x"'), isNull);
    });
  });
}
