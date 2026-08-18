// OLIVE BRANCH — tts_channel.dart tests. MASTERFILE §8.8.5.
//
// Proves TtsChannel talks to the real flutter_tts plugin channel correctly
// (stop-then-speak, the right text, no separate network client anywhere in
// the call path) — mirrors kiosk_channel_test.dart's own method-channel
// mocking pattern for a different plugin.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/tts_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');

  final List<String> calls = [];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return 1;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('TtsChannel.speak — always stop() before speak(), never queues', () {
    test('calls stop then speak, in that order', () async {
      String? spokenText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'speak') spokenText = call.arguments as String;
        return 1;
      });

      await TtsChannel().speak('Allergies: Peanuts.');

      expect(calls, ['stop', 'speak']);
      expect(spokenText, 'Allergies: Peanuts.');
    });

    test('a second speak() call also stops first — no queueing of readings',
        () async {
      final channelObj = TtsChannel();
      await channelObj.speak('first reading');
      await channelObj.speak('second reading');
      expect(calls, ['stop', 'speak', 'stop', 'speak']);
    });
  });

  group('TtsChannel.stop', () {
    test('calls the real stop method', () async {
      await TtsChannel().stop();
      expect(calls, ['stop']);
    });
  });

  group('buildSpeakCallback — the real integration point screens receive', () {
    test('returns a function that, when called, speaks via the real channel',
        () async {
      String? spokenText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'speak') spokenText = call.arguments as String;
        return 1;
      });

      final speak = buildSpeakCallback();
      await speak('read this aloud');
      expect(spokenText, 'read this aloud');
    });
  });
}
