// OLIVE BRANCH — device_channels.dart tests. MASTERFILE §8.11.4.
// A deliberately partial 1:1 port of devices.ts's Channel/CHANNELS/
// capability()/channelAdvice() — this file proves the port matches the TS
// source's own behavior, mirroring how a11y_speech_test.dart proves a11y.ts's
// port.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_channels.dart';

void main() {
  group('Channel.wireValue — matches the server/db/devices.ts string form '
      'exactly', () {
    test('every channel round-trips to its real snake_case wire value', () {
      const expected = {
        Channel.androidPlay: 'android_play',
        Channel.androidAmazon: 'android_amazon',
        Channel.androidBare: 'android_bare',
        Channel.ios: 'ios',
        Channel.windows: 'windows',
        Channel.web: 'web',
      };
      for (final entry in expected.entries) {
        expect(entry.key.wireValue, entry.value);
      }
    });
  });

  group('channels — same six rows, same facts, as devices.ts\'s CHANNELS', () {
    test('exactly six channels declared', () {
      expect(channels.length, 6);
    });

    test('android_play pushes, falls back to socket only', () {
      final cap = capability(Channel.androidPlay);
      expect(cap.push, isTrue);
      expect(cap.fallback, ChannelFallback.foregroundSocket);
    });

    test('android_amazon does not push, falls back to socket AND sms', () {
      final cap = capability(Channel.androidAmazon);
      expect(cap.push, isFalse);
      expect(cap.fallback, ChannelFallback.foregroundSocketAndSms);
    });

    test('android_bare does not push, falls back to socket AND sms', () {
      final cap = capability(Channel.androidBare);
      expect(cap.push, isFalse);
      expect(cap.fallback, ChannelFallback.foregroundSocketAndSms);
    });

    test('ios pushes, falls back to socket only', () {
      final cap = capability(Channel.ios);
      expect(cap.push, isTrue);
      expect(cap.fallback, ChannelFallback.foregroundSocket);
    });

    test('windows pushes, falls back to socket only', () {
      final cap = capability(Channel.windows);
      expect(cap.push, isTrue);
      expect(cap.fallback, ChannelFallback.foregroundSocket);
    });

    test('web does NOT push and its fallback stops at socket -- '
        'never sms (the exact fact channels.ts\'s own route() bug missed)', () {
      final cap = capability(Channel.web);
      expect(cap.push, isFalse);
      expect(cap.fallback, ChannelFallback.foregroundSocket);
    });

    test('every capability carries a real, non-empty note', () {
      for (final c in channels) {
        expect(c.note, isNotEmpty);
      }
    });
  });

  group('channelAdvice — plain guardian-facing copy, null when nothing to '
      'advise', () {
    test('a pushing channel needs no advice', () {
      expect(channelAdvice(Channel.ios), isNull);
      expect(channelAdvice(Channel.androidPlay), isNull);
      expect(channelAdvice(Channel.windows), isNull);
    });

    test('an sms-eligible non-push channel mentions texting the grown-up', () {
      final advice = channelAdvice(Channel.androidAmazon);
      expect(advice, isNotNull);
      expect(advice, contains('text the grown-up'));
    });

    test('android_bare gets the same sms-eligible advice as android_amazon', () {
      expect(channelAdvice(Channel.androidBare), contains('text the grown-up'));
    });

    test('web -- NOT sms-eligible -- must never promise texting the '
        'grown-up (the same bug channels.ts\'s route() had, fixed there and '
        'never introduced here)', () {
      final advice = channelAdvice(Channel.web);
      expect(advice, isNotNull);
      expect(advice, isNot(contains('text the grown-up')));
      expect(advice, contains('cannot show pop-up alerts'));
    });

    test('the advice never blames the device or a parent', () {
      for (final c in [Channel.androidAmazon, Channel.androidBare, Channel.web]) {
        final advice = channelAdvice(c)!;
        expect(advice.toLowerCase(), isNot(contains('broken')));
        expect(advice.toLowerCase(), isNot(contains('fault')));
      }
    });
  });
}
