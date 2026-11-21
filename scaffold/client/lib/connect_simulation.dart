// OLIVE BRANCH — DEV-ONLY device-test seam for the connect flows: "simulate her tablet" on the phone and "simulate a phone" on
// the tablet, so ONE real device can show the whole connection flow with a simulated other end. Owner's standing rule: every
// flow that needs two devices gets a seam that lets one device show it.
//
// THE DEFINE. `--dart-define=OLIVE_SIMULATE_CONNECT=true` (exactly `true`; any other value is a no-op for bool.fromEnvironment).
// Only the device lane's script (tools/device-sync.sh, on request) passes it; tools/check-simulate-connect.mjs fails CI if any
// other script, workflow, Dockerfile or release config does. A build without it has no button, no code path and no text for this
// (the seam's widgets are built only behind [kSimulateConnect]).
//
// WHAT IS REAL AND WHAT IS NOT. The seam runs the REAL pairing protocol (the same CPace key exchange, confirmation, Match and
// approval, in the same process over an in-memory transport instead of the Wi-Fi). What is simulated is the OTHER DEVICE and the
// network between: its name says "(simulated)", every card it draws says "simulated", and the connection it makes is a real
// record on this device (so the rest of the flow, "Disconnect her tablet" included, can be walked), disconnectable like any other.
// It proves the screens, the states, the steps and the protocol; it does not prove mDNS, the same-Wi-Fi transport or a second
// device's camera, which only two devices can.
import 'dart:async';

import 'device_keys.dart';
import 'pairing_protocol.dart';

/// True only in a build made with `--dart-define=OLIVE_SIMULATE_CONNECT=true`.
const bool kSimulateConnect = bool.fromEnvironment('OLIVE_SIMULATE_CONNECT');

/// The name the simulated tablet gives itself (shown to the grown-up, who can see at once it is not a real device).
const String kSimulatedTabletName = 'Simulated tablet';

/// A simulated tablet for the PHONE's connect screen: it shows a code (the real way: it chose it), asks the phone's window
/// whether the grown-up has typed it, runs the key exchange and fetches its credential. Shown to the grown-up as "simulated".
class SimulatedTablet {
  SimulatedTablet({required this.window, DeviceKey? key, String? code}) : _code = code ?? newPairingCode();
  final AdultWindow window;
  final String _code;
  DeviceKey? _key;
  PairingMatch? match;
  PairingResult? result;
  final StreamController<void> _changed = StreamController<void>.broadcast();

  /// The six numbers the simulated tablet "shows".
  String get code => _code;
  Stream<void> get changed => _changed.stream;
  bool get done => result != null;

  Future<void> run() async {
    _key = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final ChildPairingClient c = ChildPairingClient(
      childKey: _key!,
      transport: LoopbackPairingTransport(window),
      deviceName: kSimulatedTabletName,
      pollEvery: const Duration(milliseconds: 400),
    );
    result = await c.pair(
      handle: window.discoveryHandle,
      password: _code,
      waitForCode: true,
      onMatched: (PairingMatch m) {
        match = m;
        if (!_changed.isClosed) _changed.add(null);
      },
    );
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => unawaited(_changed.close());
}

/// A simulated PHONE for the tablet's connect screen: an in-process grown-up window in the code way. When the tablet shows its
/// code, the simulated grown-up "types" it a moment later, picks the right Match card and says Yes. Marked simulated on screen.
class SimulatedPhone {
  SimulatedPhone._(this.window);
  final AdultWindow window;
  bool _typed = false;

  static Future<SimulatedPhone> open() async {
    final DeviceKey key = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final AdultWindow w = await AdultWindow.open(
      adultKey: key,
      adultName: 'Simulated phone',
      familyId: 'simulated-family',
      childId: 'simulated-child',
      childName: 'You',
      awaitCode: true,
      phoneOnly: true,
      requireMatch: true,
    );
    final SimulatedPhone p = SimulatedPhone._(w);
    w.addListener(p._onWindow);
    return p;
  }

  void _onWindow() {
    final AdultWindow w = window;
    if (w.state == WindowState.awaitingApproval && !w.matchConfirmed && w.matchChoices != null) {
      // The simulated grown-up recognises the pictures (a real grown-up compares the two screens) and says Yes.
      w.pickMatch(w.matchChoices!.correct);
      unawaited(w.approve());
    }
  }

  /// The tablet has put a code on its screen: the simulated grown-up types it after [after].
  void typeCode(String code, {Duration after = const Duration(seconds: 2)}) {
    if (_typed) return;
    _typed = true;
    Timer(after, () {
      if (window.state == WindowState.open) window.provideCode(code);
    });
  }

  void dispose() {
    window.removeListener(_onWindow);
    window.close();
  }
}
