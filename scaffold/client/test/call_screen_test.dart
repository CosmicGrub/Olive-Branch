// OLIVE BRANCH — call_screen.dart tests. MASTERFILE §5.20, §5.21.1, §8.1,
// §16.2 #6 (third reversal: Jitsi default, LiveKit selectable).
//
// The screen depends only on the CallProvider interface, so everything here
// runs against FakeCallProvider: the calm states, the audience-aware wording,
// the end-of-call callback and the provider choice, without a media engine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_modes.dart';
import 'package:olive_client/call_provider.dart';
import 'package:olive_client/call_screen.dart';

const _jitsiGrant = CallGrant.jitsi(
  jwt: 'a.b.c', room: 'oroom', serverURL: 'https://192.168.1.50:8443', displayName: 'Dad');
const _lkGrant = CallGrant.livekit(token: 'tok', wsURL: 'wss://x.invalid', displayName: 'Dad');

Future<FakeCallProvider> _pump(
  WidgetTester tester, {
  required FakeCallProvider fake,
  CallGrant grant = _jitsiGrant,
  String who = 'ivy',
  String displayName = 'Dad',
  CallMode mode = CallMode.video,
  Future<void> Function()? onCallEnd,
  void Function(CallGrant)? onFactory,
  bool settle = true,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => Scaffold(body: Center(
      child: ElevatedButton(
        key: const Key('open'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            who: who, displayName: displayName, knownGrant: grant, initialMode: mode,
            onCallEnd: onCallEnd,
            providerFactory: (g) { onFactory?.call(g); return fake; }))),
        child: const Text('open'),
      ))))));
  await tester.tap(find.byKey(const Key('open')));
  // A spinner (connecting/reconnecting) animates forever, so those states pump
  // a fixed time instead of settling.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
  return fake;
}

void main() {
  group('isGuardianWho — the one real role signal this screen has', () {
    test("'ivy' is the only child identity — everything else is a guardian", () {
      expect(isGuardianWho('ivy'), false);
      expect(isGuardianWho('dad'), true);
    });
  });

  group('the engine is chosen from the grant, not from the screen', () {
    testWidgets('a jitsi grant reaches the factory as jitsi', (tester) async {
      CallGrant? seen;
      await _pump(tester, fake: FakeCallProvider(kind: CallProviderKind.jitsi, rendersOwnScreen: true),
        onFactory: (g) => seen = g);
      expect(seen?.kind, CallProviderKind.jitsi);
      expect(seen?.room, 'oroom');
    });

    testWidgets('a livekit grant reaches the factory as livekit', (tester) async {
      CallGrant? seen;
      await _pump(tester, fake: FakeCallProvider(), grant: _lkGrant, onFactory: (g) => seen = g);
      expect(seen?.kind, CallProviderKind.livekit);
    });

    testWidgets('the legacy knownToken/knownWsURL pair is a livekit grant', (tester) async {
      CallGrant? seen;
      final fake = FakeCallProvider();
      await tester.pumpWidget(MaterialApp(home: CallScreen(
        who: 'dad', displayName: 'Dad', knownToken: 't', knownWsURL: 'wss://h',
        providerFactory: (g) { seen = g; return fake; })));
      await tester.pumpAndSettle();
      expect(seen?.kind, CallProviderKind.livekit);
      expect(seen?.token, 't');
    });

    testWidgets('audio-only is her choice and reaches the engine as such', (tester) async {
      final fake = await _pump(tester, fake: FakeCallProvider(), mode: CallMode.audioOnly);
      expect(fake.joinedOptions?.mode, CallMode.audioOnly);
      expect(fake.state.cameraEnabled, false);
    });
  });

  group('an engine that draws its own screen (Jitsi)', () {
    testWidgets('rests on a calm surface; hang up leaves, ends once, and pops', (tester) async {
      var ended = 0;
      final fake = await _pump(tester,
        fake: FakeCallProvider(kind: CallProviderKind.jitsi, rendersOwnScreen: true),
        onCallEnd: () async { ended++; });
      expect(find.text("You're on a call with Dad."), findsOneWidget);
      expect(find.byTooltip('Hang up'), findsOneWidget);
      await tester.tap(find.byTooltip('Hang up'));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('leave'));
      expect(ended, 1);
      expect(find.byType(CallScreen), findsNothing); // popped
    });

    testWidgets('a call that really connected ends exactly once even if ended repeats', (tester) async {
      var ended = 0;
      final fake = await _pump(tester,
        fake: FakeCallProvider(kind: CallProviderKind.jitsi, rendersOwnScreen: true),
        onCallEnd: () async { ended++; });
      fake.emit(fake.state.copyWith(phase: CallPhase.ended));
      fake.emit(fake.state.copyWith(phase: CallPhase.ended));
      await tester.pumpAndSettle();
      expect(ended, 1);
    });
  });

  group('an engine that gives us video (LiveKit)', () {
    testWidgets('shows the real controls and the honest waiting surface', (tester) async {
      // A phone-shaped surface: the default 800x600 reads as a fold posture.
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fake = await _pump(tester, fake: FakeCallProvider(), grant: _lkGrant);
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Hang up'), findsOneWidget);
      expect(find.byTooltip('Turn camera off'), findsOneWidget);
      expect(find.text('Waiting for the other side…'), findsOneWidget);
      await tester.tap(find.byTooltip('Mute'));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('mic:false'));
      await tester.tap(find.byTooltip('Turn camera off'));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('camera:false'));
    });

    testWidgets('the other side choosing voice only is said plainly, never as a fault', (tester) async {
      final fake = await _pump(tester, fake: FakeCallProvider(), grant: _lkGrant);
      fake.emit(fake.state.copyWith(remoteMode: CallMode.audioOnly));
      await tester.pumpAndSettle();
      expect(find.text('Voice only just now.'), findsOneWidget);
    });

    testWidgets('reconnecting is calm and never names a network', (tester) async {
      final fake = await _pump(tester, fake: FakeCallProvider(), grant: _lkGrant);
      fake.emit(fake.state.copyWith(phase: CallPhase.reconnecting));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(reconnectingLine), findsOneWidget);
      for (final w in callBannedWords) {
        expect(reconnectingLine.toLowerCase().contains(w), false, reason: w);
      }
    });

    testWidgets('resuming asks first: after a reconnect the camera waits for her tap', (tester) async {
      final fake = await _pump(tester, fake: FakeCallProvider(), grant: _lkGrant);
      fake.emit(fake.state.copyWith(cameraEnabled: false, awaitingResumeConsent: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resumeVideoButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('resumeVideoButton')));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('camera:true'));
    });
  });

  group('calm states when the call cannot start', () {
    testWidgets('provider switched off: soft wording for the child, no error words', (tester) async {
      final fake = FakeCallProvider(joinError: const CallUnavailableException(CallUnavailableReason.providerOff));
      await _pump(tester, fake: fake, who: 'ivy');
      final line = callUnavailableLine(CallUnavailableReason.providerOff, isGuardian: false);
      expect(find.text(line), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      for (final w in callBannedWords) {
        expect(line.toLowerCase().contains(w), false, reason: 'child line contains "$w"');
      }
      expect(find.byIcon(Icons.call_end), findsNothing); // no red hang-up glyph on a calm state
    });

    testWidgets('the same situation reads plainly for an adult, and says what to do', (tester) async {
      final fake = FakeCallProvider(joinError: const CallUnavailableException(CallUnavailableReason.providerOff));
      await _pump(tester, fake: fake, who: 'dad');
      final line = callUnavailableLine(CallUnavailableReason.providerOff, isGuardian: true);
      expect(find.text(line), findsOneWidget);
      expect(line.contains('calls-on'), true);
    });

    testWidgets('no raw exception text, address or key ever reaches the screen', (tester) async {
      final fake = FakeCallProvider(joinError: const CallUnavailableException(
        CallUnavailableReason.unreachable, 'SocketException: Failed host lookup 192.168.1.50 secret-xyz'));
      await _pump(tester, fake: fake, who: 'ivy');
      expect(find.textContaining('Socket'), findsNothing);
      expect(find.textContaining('192.168'), findsNothing);
      expect(find.textContaining('secret'), findsNothing);
    });

    testWidgets('an end BEFORE the call ever connected is calm and records nothing', (tester) async {
      var ended = 0;
      final fake = await _pump(tester,
        fake: FakeCallProvider(kind: CallProviderKind.jitsi, rendersOwnScreen: true, connectOnJoin: false),
        onCallEnd: () async { ended++; }, settle: false);
      expect(fake.state.everConnected, false);
      fake.emit(fake.state.copyWith(phase: CallPhase.ended));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CallScreen), findsOneWidget); // still here, calmly
      expect(ended, 0);
    });

    testWidgets('Try again starts a fresh attempt', (tester) async {
      var made = 0;
      await tester.pumpWidget(MaterialApp(home: CallScreen(
        who: 'ivy', displayName: 'Dad', knownGrant: _jitsiGrant,
        providerFactory: (_) { made++; return FakeCallProvider(
          joinError: const CallUnavailableException(CallUnavailableReason.unreachable)); })));
      await tester.pumpAndSettle();
      expect(made, 1);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(made, 2);
    });
  });

  group('onCallEnd — fires once, after a real call, never when nothing started', () {
    testWidgets('a null onCallEnd is a safe no-op: reaching the calm state must never throw', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CallScreen(who: 'dad', displayName: 'Dad')));
      await tester.pumpAndSettle();
      // The dev room server is unreachable in a test sandbox: the calm state.
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets("a supplied onCallEnd is threaded through unmodified and is not fired early", (tester) async {
      var called = false;
      Future<void> onEnd() async { called = true; }
      await tester.pumpWidget(MaterialApp(home: CallScreen(who: 'dad', displayName: 'Dad', onCallEnd: onEnd)));
      await tester.pumpAndSettle();
      expect(tester.widget<CallScreen>(find.byType(CallScreen)).onCallEnd, same(onEnd));
      expect(called, false);
    });
  });
}
