// OLIVE BRANCH - the developer-only "simulate the other end" seam (call_dev_sim.dart). In a normal build (this test runs
// WITHOUT the define) the strip is absent; the simulated engine and the simulated knock work and mark themselves
// "simulated"; none of it touches a server. The CI guard over the define itself is tools/test/dev_call_sim_guard.test.mjs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_dev_sim.dart';
import 'package:olive_client/call_knock_screen.dart';
import 'package:olive_client/call_provider.dart';

void main() {
  testWidgets('a normal build has no strip: kDevCallSim is false and the bar is a zero-size box', (t) async {
    expect(kDevCallSim, false);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: DevCallSimBar(side: DevCallSimSide.tablet, otherName: 'Dad'))));
    expect(find.byKey(const Key('devCallSimButton')), findsNothing);
    expect(find.textContaining('simulate', findRichText: true), findsNothing);
  });

  test('the simulated engine connects, marks the other side simulated, and ends when asked', () async {
    final p = SimulatedCallProvider(who: 'Ivy', connectAfter: const Duration(milliseconds: 10));
    final seen = <CallPhase>[];
    p.states.listen((s) => seen.add(s.phase));
    await p.join(kSimulatedGrant, const CallJoinOptions(displayName: 'Dad', isGuardian: true));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(p.state.phase, CallPhase.connected);
    expect(p.state.remoteName, 'Ivy (simulated)');
    await p.leave();
    expect(p.state.phase, CallPhase.ended);
    expect(seen, [CallPhase.connecting, CallPhase.connected, CallPhase.ended]);
    await p.dispose();
  });

  testWidgets('a simulated knock shows the grown-up as simulated and Answer opens a simulated call, never a real join', (t) async {
    await t.pumpWidget(const MaterialApp(home: CallKnockScreen(from: 'Dad (simulated)', who: 'ivy', displayName: 'Ivy', simulated: true)));
    expect(find.textContaining('Dad (simulated) would like to talk.'), findsOneWidget);
    await t.tap(find.byKey(const Key('answerButton_Answer')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    // the call screen is up (the status line names the simulated side); no server was involved
    expect(find.textContaining('Dad (simulated)'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 100));
  });
}
