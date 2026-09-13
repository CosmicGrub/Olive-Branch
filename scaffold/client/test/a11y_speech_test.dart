// OLIVE BRANCH — a11y_speech.dart tests. MASTERFILE §8.8.5.
// A 1:1 port of packages/a11y/src/a11y.ts's speakableText()/admitSpeech()
// section — this file proves the port matches the TS source's own behavior,
// mirroring how lock_controller_test.dart proves lock.ts's port.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/a11y_speech.dart';

void main() {
  group('speakableText — reads the label, not a second copy of it', () {
    test('a control with a real label speaks the label, not the visible text', () {
      expect(speakableText('star', 'the little star icon'), 'Keep this story');
    });

    test('a control with no label falls back to the visible text verbatim', () {
      expect(speakableText('some_unlabeled_control', 'Whatever is on screen'),
        'Whatever is on screen');
    });

    test('every documented control id round-trips to its real label', () {
      const expected = {
        'star': 'Keep this story',
        'bookmark': 'Save your place in this story',
        'turn_page': 'Next page',
        'back_page': 'Previous page',
        'colour_region': 'Colour this part of the picture',
        'send_show': 'Send this to Daddy',
        'end_call': 'Finish the call',
        'pin_digit': 'Enter one digit of your PIN',
        'hide_work': 'Put this picture away',
        'find_target': 'Tap the thing you are looking for',
      };
      for (final entry in expected.entries) {
        expect(speakableText(entry.key, 'irrelevant fallback'), entry.value);
      }
    });
  });

  group('admitSpeech — never autonomous', () {
    test('a tap trigger is always admitted', () {
      expect(admitSpeech(SpeechTrigger.tap), isNull);
    });

    test('an autonomous trigger is always refused, unconditionally', () {
      final refusal = admitSpeech(SpeechTrigger.autonomous);
      expect(refusal, isNotNull);
      expect(refusal!.note, contains('slot-machine'));
    });
  });

  group('the on-device/never-logged constants — fixed, not runtime toggles', () {
    test('readAloudOnDeviceOnly is true', () {
      expect(readAloudOnDeviceOnly, isTrue);
    });
    test('readAloudNeverLogged is true', () {
      expect(readAloudNeverLogged, isTrue);
    });
  });

  group('readAloudDefaultOn — default-on below age 8, opt-in above it', () {
    test('a 5-year-old gets it on by default', () {
      expect(readAloudDefaultOn(5), isTrue);
    });
    test('a 10-year-old does not', () {
      expect(readAloudDefaultOn(10), isFalse);
    });
    test('exactly age 8 does not (the fade point itself, not below it)', () {
      expect(readAloudDefaultOn(8), isFalse);
    });
    test('no known age defaults on, the same way an unknown child is treated '
        'as needing the most support elsewhere in this codebase', () {
      expect(readAloudDefaultOn(null), isTrue);
    });
  });
}
