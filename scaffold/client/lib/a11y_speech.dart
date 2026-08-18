// OLIVE BRANCH — read-aloud, the pure logic half. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §8.8.5.
//
// A 1:1 semantic port of packages/a11y/src/a11y.ts's speakableText()/
// admitSpeech()/LABELS section, kept deliberately close to the original
// (same function names, same shapes) — the same discipline lock_controller.dart
// applies when porting lock.ts. The platform TTS call itself lives in
// tts_channel.dart, separately: this file has no plugin dependency at all,
// so it's testable with zero mocking.
//
// §8.8.5's own posture, carried forward unchanged: on-device only, never
// logged, never autonomous (a screen that starts talking on its own is
// §8.13's slot-machine mechanic wearing a voice — admitSpeech() below is
// the one gate that keeps every caller honest about that).
library;

/// §8.8.4's screen-reader label table — the SAME string a screen reader
/// already gets, never a second hand-maintained copy. Kept in sync with
/// a11y.ts's own LABELS by hand (both are small, reviewed, hand-authored
/// tables — the drift risk this file exists to describe, not eliminate,
/// since the two run in different languages).
const Map<String, String> labels = <String, String>{
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

/// Reads the accessibility label, not a second copy of it, falling back to
/// visible text only where no label has been written yet.
String speakableText(String controlId, String visibleText) =>
    labels[controlId] ?? visibleText;

enum SpeechTrigger { tap, autonomous }

class SpeechRefusal {
  const SpeechRefusal(this.note);
  final String note;
}

/// Never autonomous. `admitSpeech(SpeechTrigger.autonomous)` always refuses —
/// there is no configuration or override that lets it through, exactly
/// mirroring admitSpeech()'s own unconditional refusal in a11y.ts.
SpeechRefusal? admitSpeech(SpeechTrigger trigger) {
  if (trigger == SpeechTrigger.autonomous) {
    return const SpeechRefusal(
      "Speech that starts itself, rather than in response to a tap, is "
      "§8.13's slot-machine mechanic wearing a voice.");
  }
  return null;
}

/// Both fixed `true` in a11y.ts, carried forward as constants rather than
/// runtime-checkable booleans on purpose — see tts_channel.dart's own
/// header for how the platform wrapper actually honors them (no network
/// client exists in that file at all, so there is nothing to point at a
/// cloud endpoint, and no call logs the spoken text anywhere).
const bool readAloudOnDeviceOnly = true;
const bool readAloudNeverLogged = true;

const int readAloudDefaultBelowAge = 8;

bool readAloudDefaultOn(int? age) => age == null || age < readAloudDefaultBelowAge;
