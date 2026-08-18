// OLIVE BRANCH — read-aloud, the real platform half. UNVERIFIED end-to-end
// on this file's own account (no Flutter toolchain in tools/verify.sh's
// automated pipeline, and no physical device attached this session to
// actually hear it speak) until a real device run proves it. MASTERFILE
// §8.8.5.
//
// Wraps package:flutter_tts, the same "real, federated plugin, no fabricated
// native config" posture image_picker/path_provider already use elsewhere in
// this client (see pubspec.yaml's own comment). Every platform flutter_tts
// targets speaks through that OS's own OFFLINE synthesizer
// (AVSpeechSynthesizer on iOS, android.speech.tts.TextToSpeech on Android,
// ...) — this file never constructs an http.Client, never calls a cloud
// endpoint, and never persists or logs the text it's asked to speak,
// honoring a11y_speech.dart's readAloudOnDeviceOnly/readAloudNeverLogged.
//
// One call in flight at a time, by construction: speak() always stop()s
// first. A screen tapping "read aloud" twice in a row should restart from
// the new text, never queue two readings back to back.
import 'package:flutter_tts/flutter_tts.dart';

class TtsChannel {
  TtsChannel({FlutterTts? engine}) : _engine = engine ?? FlutterTts();
  final FlutterTts _engine;

  Future<void> speak(String text) async {
    await _engine.stop();
    await _engine.speak(text);
  }

  Future<void> stop() => _engine.stop();
}

/// Builds a real `Future<void> Function(String)` for a screen's own `speak`
/// parameter — the exact integration point every real-vs-simulated screen in
/// this codebase already uses (capture_gate.dart's `takePhoto`,
/// webauthn_channel.dart's `buildVerifyBiometricCallback`, ...). A screen
/// that receives no `speak` callback at all has no read-aloud affordance —
/// same honest-stub posture as guardian_setup.dart's `registerPasskey`, not
/// a fabricated one that silently does nothing.
Future<void> Function(String) buildSpeakCallback({TtsChannel? channel}) {
  final ch = channel ?? TtsChannel();
  return (String text) => ch.speak(text);
}
