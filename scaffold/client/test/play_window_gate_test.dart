// OLIVE BRANCH — Wave 4: the child's half of the play window listens to the clock. UNVERIFIED until CI runs it.
// MASTERFILE §8.6.6, P2. The gate re-reads the window; a wind-down arrives on its own and rests the games door
// (never a game in progress); every sentence she can see is free of numbers, timers and punishment words.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/her_colour_store.dart';
import 'package:olive_client/play_window_gate.dart';

void main() {
  const w = PlayWindow(opensMin: 930, restsMin: 1140, windDownMin: 30); // opens 3:30 PM, rests 7:00 PM
  late DateTime now;
  MemoryColourStore store({PlayWindow? window = w}) => MemoryColourStore(now: () => now, window: window);

  Widget app(Widget home) => MaterialApp(home: home);
  Future<void> minutes(WidgetTester t, int n) async {
    now = now.add(Duration(minutes: n));
    await t.pump(const Duration(minutes: 1)); // the gate's own re-check fires
    await t.pump(const Duration(milliseconds: 500)); // the soft cross-fade
  }

  final bad = RegExp(r'\d|timer|locked?\b|limit|no more|punish|taken|minutes?|left', caseSensitive: false);

  testWidgets('a wind-down that starts while she is on the games list arrives on its own', (t) async {
    now = DateTime(2026, 11, 9, 18, 20);
    await t.pumpWidget(app(PlayWindowGate(store: store(), child: const Scaffold(body: Text('the games')))));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('windDownBanner')), findsNothing);
    await minutes(t, 12); // 18:32, inside the 30-minute tail
    expect(find.byKey(const Key('windDownBanner')), findsOneWidget);
    expect(find.text('the games'), findsOneWidget, reason: 'the games stay: it is one more, then goodnight');
    final line = playWindowLine('winding_down')!;
    expect(line, isNot(matches(bad)));
  });

  testWidgets('then the rest time puts the games to sleep, calm and with no number', (t) async {
    now = DateTime(2026, 11, 9, 18, 45);
    await t.pumpWidget(app(PlayWindowGate(store: store(), child: const Scaffold(body: Text('the games')))));
    await t.pumpAndSettle();
    await minutes(t, 20); // 19:05
    expect(find.text('the games'), findsNothing);
    final line = t.widget<Text>(find.byKey(const Key('goodnightLine'))).data!;
    expect(line, contains('tomorrow'));
    expect(line, isNot(matches(bad)));
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'no countdown ring');
  });

  testWidgets('before the games open today the card says later today, never tomorrow', (t) async {
    now = DateTime(2026, 11, 9, 8, 0);
    await t.pumpWidget(app(PlayWindowGate(store: store(), child: const Scaffold(body: Text('the games')))));
    await t.pumpAndSettle();
    final line = t.widget<Text>(find.byKey(const Key('goodnightLine'))).data!;
    expect(line, contains('later today'));
    expect(line, isNot(contains('tomorrow')));
    expect(line, isNot(matches(bad)));
    await minutes(t, 8 * 60); // 16:00, the window has opened
    expect(find.text('the games'), findsOneWidget);
  });

  testWidgets('a game in progress is never cut off: it finishes, and the door rests when she comes back', (t) async {
    now = DateTime(2026, 11, 9, 18, 50);
    await t.pumpWidget(app(PlayWindowGate(store: store(), child: Builder(builder: (ctx) => Scaffold(body: Center(
      child: FilledButton(onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('a game')), body: const Text('mid-game')))), child: const Text('play')))))))); 
    await t.pumpAndSettle();
    await t.tap(find.text('play'));
    await t.pumpAndSettle();
    expect(find.text('mid-game'), findsOneWidget);
    await minutes(t, 30); // 19:20, past the rest time, game still open
    expect(find.text('mid-game'), findsOneWidget, reason: 'the gate stands at the door, not inside the game');
    expect(find.byKey(const Key('goodnightLine')), findsNothing, reason: 'the goodnight card is under the game');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('goodnightLine')), findsOneWidget);
  });

  testWidgets('no window set means open, and a window the grown-up widens re-opens the door', (t) async {
    now = DateTime(2026, 11, 9, 20, 0);
    final s = store(window: null);
    await t.pumpWidget(app(PlayWindowGate(store: s, child: const Scaffold(body: Text('the games')))));
    await t.pumpAndSettle();
    expect(find.text('the games'), findsOneWidget);
    await s.savePlayWindow(const PlayWindow(opensMin: 930, restsMin: 1140, windDownMin: 0));
    await minutes(t, 1);
    expect(find.byKey(const Key('goodnightLine')), findsOneWidget);
    await s.savePlayWindow(const PlayWindow(opensMin: 930, restsMin: 1320, windDownMin: 0));
    await minutes(t, 1);
    expect(find.text('the games'), findsOneWidget);
  });

  test('the card line is a pure function with no number in any state', () {
    for (final info in [
      PlayWindowInfo(window: w, state: 'resting', line: playWindowLine('resting')),
      PlayWindowInfo(window: w, state: 'resting', line: playWindowLine('resting'), beforeOpen: true),
    ]) {
      expect(goodnightCardLine(info), isNot(matches(bad)));
    }
  });
}
