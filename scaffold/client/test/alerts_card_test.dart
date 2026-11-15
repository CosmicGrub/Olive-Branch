// OLIVE BRANCH — alerts_card.dart tests. MASTERFILE §11, §7.18.
//
// The grown-up's "Alerts on this tablet" card: two facts and the two taps that fix them. It lives in Guardian mode
// only, and draws nothing where there is no phone side (Windows, tests).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/alerts_card.dart';
import 'package:olive_client/guardian_escalation_screen.dart';
import 'package:olive_client/incoming_call_channel.dart';

class _Phone {
  _Phone(this.t, {this.notifications = false, this.fullScreen = false, this.grantsOnRequest = true, this.statusBroken = false}) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call.method);
      switch (call.method) {
        case IncomingCallChannel.mStatus:
          if (statusBroken) return 'garbage';
          return <String, Object?>{'notifications': notifications, 'fullScreen': fullScreen};
        case IncomingCallChannel.mRequestNotifications:
          if (grantsOnRequest) notifications = true;
          return notifications;
        case IncomingCallChannel.mOpenFullScreenSettings:
          fullScreen = true; // the grown-up flips the switch on the settings page
          return null;
      }
      return null;
    });
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('olive/app_settings'), (MethodCall c) async {
      calls.add('app_settings:${c.method}');
      return null;
    });
  }
  final WidgetTester t;
  final MethodChannel channel = const MethodChannel('test/alerts');
  final List<String> calls = <String>[];
  bool notifications;
  bool fullScreen;
  final bool grantsOnRequest;
  final bool statusBroken;
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('both off: says so and offers both taps', (t) async {
    final p = _Phone(t);
    await t.pumpWidget(_app(AlertsCard(channel: IncomingCallChannel(channel: p.channel))));
    await t.pumpAndSettle();
    expect(find.text('Pop-up alerts: off'), findsOneWidget);
    expect(find.text('Rings over the lock screen: off'), findsOneWidget);
    expect(find.byKey(const Key('alertsAllow')), findsOneWidget);
    expect(find.byKey(const Key('alertsFullScreenSettings')), findsOneWidget);
  });

  testWidgets('both on: says so and offers nothing to tap', (t) async {
    final p = _Phone(t, notifications: true, fullScreen: true);
    await t.pumpWidget(_app(AlertsCard(channel: IncomingCallChannel(channel: p.channel))));
    await t.pumpAndSettle();
    expect(find.text('Pop-up alerts: on'), findsOneWidget);
    expect(find.text('Rings over the lock screen: on'), findsOneWidget);
    expect(find.byKey(const Key('alertsAllow')), findsNothing);
    expect(find.byKey(const Key('alertsFullScreenSettings')), findsNothing);
  });

  testWidgets('Allow asks the phone once and the card updates', (t) async {
    final p = _Phone(t);
    await t.pumpWidget(_app(AlertsCard(channel: IncomingCallChannel(channel: p.channel))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alertsAllow')));
    await t.pumpAndSettle();
    expect(p.calls.where((c) => c == IncomingCallChannel.mRequestNotifications).length, 1);
    expect(find.text('Pop-up alerts: on'), findsOneWidget);
    // Allowed: the phone's settings page is not opened.
    expect(p.calls.any((c) => c.startsWith('app_settings')), isFalse);
  });

  testWidgets('if the phone will not show its box again, Allow opens the app\'s page in the phone\'s settings', (t) async {
    final p = _Phone(t, grantsOnRequest: false);
    await t.pumpWidget(_app(AlertsCard(channel: IncomingCallChannel(channel: p.channel))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alertsAllow')));
    await t.pumpAndSettle();
    expect(p.calls, contains('app_settings:open'));
    expect(find.text('Pop-up alerts: off'), findsOneWidget);
  });

  testWidgets('the full-screen row opens the phone\'s settings and re-reads the answer', (t) async {
    final p = _Phone(t, notifications: true);
    await t.pumpWidget(_app(AlertsCard(channel: IncomingCallChannel(channel: p.channel))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alertsFullScreenSettings')));
    await t.pumpAndSettle();
    expect(p.calls, contains(IncomingCallChannel.mOpenFullScreenSettings));
    expect(find.text('Rings over the lock screen: on'), findsOneWidget);
  });

  testWidgets('with no phone side the card draws nothing at all', (t) async {
    await t.pumpWidget(_app(AlertsCard(channel: IncomingCallChannel(channel: const MethodChannel('nobody/home')))));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('alertsCard')), findsNothing);
  });

  testWidgets('an answer that is not two booleans draws nothing rather than a guess', (t) async {
    final p = _Phone(t, statusBroken: true);
    await t.pumpWidget(_app(AlertsCard(channel: IncomingCallChannel(channel: p.channel))));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('alertsCard')), findsNothing);
  });

  testWidgets('the card says nothing about any child: no name, no count', (t) async {
    final p = _Phone(t);
    await t.pumpWidget(_app(AlertsCard(channel: IncomingCallChannel(channel: p.channel))));
    await t.pumpAndSettle();
    final texts = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join(' ');
    expect(RegExp(r'\d').hasMatch(texts), isFalse, reason: 'no numbers on the card');
  });

  testWidgets('Guardian mode still has its way out, with the card in the page', (t) async {
    // No phone side registered: the card is absent and the screen is exactly what it was.
    await t.pumpWidget(MaterialApp(home: GuardianEscalationScreen(
        escalatedUntil: DateTime.now().add(const Duration(minutes: 5)), onExitKiosk: () {}, childName: 'Mia')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exitKioskButton')), findsOneWidget);
    expect(find.byKey(const Key('alertsCard')), findsNothing);
  });
}
