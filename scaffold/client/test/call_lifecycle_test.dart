// OLIVE BRANCH — call_lifecycle.dart tests. MASTERFILE §5.25.2, §7.18.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_lifecycle.dart';
import 'package:olive_client/call_provider.dart' show CallProviderKind;

void main() {
  group('CallAvailability.tryParse', () {
    test('the server\'s real answer', () {
      final a = CallAvailability.tryParse(<String, Object?>{'provider': 'jitsi', 'available': true, 'sameNetworkOnly': true});
      expect(a, isNotNull);
      expect(a!.provider, CallProviderKind.jitsi);
      expect(a.available, isTrue);
      expect(a.sameNetworkOnly, isTrue);
    });

    test('livekit, available anywhere', () {
      final a = CallAvailability.tryParse(<String, Object?>{'provider': 'livekit', 'available': true, 'sameNetworkOnly': false});
      expect(a!.provider, CallProviderKind.livekit);
      expect(a.sameNetworkOnly, isFalse);
    });

    test('an unknown provider name is null, not a guess, and does not change availability', () {
      final a = CallAvailability.tryParse(<String, Object?>{'provider': 'zoom', 'available': true});
      expect(a!.provider, isNull);
      expect(a.available, isTrue);
    });

    test('unavailable never claims "same network only"', () {
      final a = CallAvailability.tryParse(<String, Object?>{'provider': 'jitsi', 'available': false, 'sameNetworkOnly': true});
      expect(a!.available, isFalse);
      expect(a.sameNetworkOnly, isFalse);
    });

    test('hostile and damaged bodies are not usable, they are not guessed', () {
      expect(CallAvailability.tryParse(null), isNull);
      expect(CallAvailability.tryParse('available'), isNull);
      expect(CallAvailability.tryParse(<Object?>[true]), isNull);
      expect(CallAvailability.tryParse(<String, Object?>{}), isNull);
      // "true" the string is not true; 1 is not true.
      expect(CallAvailability.tryParse(<String, Object?>{'available': 'true'}), isNull);
      expect(CallAvailability.tryParse(<String, Object?>{'available': 1}), isNull);
      expect(CallAvailability.tryParse(<String, Object?>{'available': null}), isNull);
    });

    test('a non-boolean sameNetworkOnly is "no restriction known"', () {
      final a = CallAvailability.tryParse(<String, Object?>{'available': true, 'sameNetworkOnly': 'yes'});
      expect(a!.sameNetworkOnly, isFalse);
    });
  });

  group('availabilityLine', () {
    test('nothing known, nothing said', () {
      expect(availabilityLine(null), isNull);
    });

    test('available anywhere: nothing to add', () {
      expect(availabilityLine(const CallAvailability(provider: CallProviderKind.livekit, available: true, sameNetworkOnly: false)), isNull);
    });

    test('off: says calls are switched off, in a grown-up\'s words', () {
      final s = availabilityLine(const CallAvailability(provider: CallProviderKind.jitsi, available: false, sameNetworkOnly: false));
      expect(s, contains('switched off'));
    });

    test('home network only: says so plainly', () {
      final s = availabilityLine(const CallAvailability(provider: CallProviderKind.jitsi, available: true, sameNetworkOnly: true));
      expect(s, contains('home Wi-Fi'));
    });
  });

  group('ringStateOf / ringStateLine', () {
    test('every word the server sends maps, and anything else is unknown', () {
      expect(ringStateOf('rang'), CallRingState.rang);
      expect(ringStateOf('quiet_hours'), CallRingState.quietHours);
      expect(ringStateOf('no_devices'), CallRingState.noDevices);
      expect(ringStateOf('no_push_capability'), CallRingState.noPushCapability);
      expect(ringStateOf('send_failed'), CallRingState.sendFailed);
      expect(ringStateOf('something_new'), CallRingState.unknown);
      expect(ringStateOf(null), CallRingState.unknown);
      expect(ringStateOf(7), CallRingState.unknown);
      expect(ringStateOf(<String, Object?>{'rang': true}), CallRingState.unknown);
    });

    test('rang and unknown say nothing', () {
      expect(ringStateLine(CallRingState.rang), isNull);
      expect(ringStateLine(CallRingState.unknown), isNull);
    });

    test('every other state has a sentence that is honest and names the child by the grown-up\'s own word', () {
      for (final s in <CallRingState>[
        CallRingState.quietHours,
        CallRingState.noDevices,
        CallRingState.noPushCapability,
        CallRingState.sendFailed,
      ]) {
        final line = ringStateLine(s, childName: 'Mia');
        expect(line, isNotNull, reason: '$s');
        expect(line!.length, greaterThan(20));
      }
      expect(ringStateLine(CallRingState.quietHours, childName: 'Mia'), contains("Mia's tablet"));
      expect(ringStateLine(CallRingState.quietHours), startsWith('The tablet'));
      expect(ringStateLine(CallRingState.quietHours, childName: '   '), startsWith('The tablet'));
    });

    test('the sentences claim nothing the server did not say and never blame', () {
      for (final s in CallRingState.values) {
        final line = ringStateLine(s, childName: 'Mia');
        if (line == null) continue;
        for (final banned in <String>['declin', 'reject', 'refus', 'ignor', 'missed', 'fault']) {
          expect(line.toLowerCase().contains(banned), isFalse, reason: '$s says "$banned"');
        }
      }
    });
  });

  group('isCallSessionId', () {
    test('a canonical uuid, either case', () {
      expect(isCallSessionId('3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f50'), isTrue);
      expect(isCallSessionId('3F2C1A9E-7D4B-4C1E-9A55-0B1C2D3E4F50'), isTrue);
    });

    test('everything else, including path pieces and non-strings', () {
      expect(isCallSessionId(null), isFalse);
      expect(isCallSessionId(7), isFalse);
      expect(isCallSessionId(''), isFalse);
      expect(isCallSessionId('../../v1/me'), isFalse);
      expect(isCallSessionId('3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f5'), isFalse);
      expect(isCallSessionId('3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f50/end'), isFalse);
      expect(isCallSessionId('3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f5g'), isFalse);
      expect(isCallSessionId('3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f50\n'), isFalse);
      expect(isCallSessionId(' 3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f50'), isFalse);
      expect(isCallSessionId('<script>alert(1)</script>'), isFalse);
      expect(isCallSessionId('a' * 5000), isFalse);
    });
  });
}
