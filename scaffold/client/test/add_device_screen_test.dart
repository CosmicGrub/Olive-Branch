// OLIVE BRANCH — add_device_screen.dart tests. docs/superpowers/specs/
// 2026-09-12-device-pairing-provisioning-design.md.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/add_device_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, {
    required http.Client client,
    List<ChildOption> children = const [ChildOption(id: 'child-1', name: 'Ivy')],
  }) =>
      tester.pumpWidget(MaterialApp(home: AddDeviceScreen(
        baseUrl: 'http://olive.test', guardianId: 'dad-1',
        children: children, httpClient: client)));

  MockClient stubClient({
    String? expiresAt,
    List<String>? calledPaths,
    int pinStatus = 200,
    String pinError = 'pin_incorrect',
  }) => MockClient((req) async {
    calledPaths?.add('${req.method} ${req.url.path}');
    if (req.url.path == '/v1/auth/dev-login') {
      return http.Response(jsonEncode({'token': 'dev-token'}), 200);
    }
    if (req.url.path.endsWith('/device-pairing-codes')) {
      if (pinStatus != 200) {
        return http.Response(jsonEncode({'error': pinError}), pinStatus);
      }
      return http.Response(jsonEncode({
        'id': 'code-1', 'numericCode': '123456',
        'expiresAt': expiresAt ?? DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      }), 201);
    }
    if (req.url.path.endsWith('/cancel')) {
      return http.Response(jsonEncode({'ok': true}), 200);
    }
    return http.Response('{}', 404);
  });

  testWidgets('the role picker defaults to a child and shows Continue', (tester) async {
    await pump(tester, client: stubClient());
    expect(find.byKey(const Key('addDeviceRoleChild')), findsOneWidget);
    expect(find.byKey(const Key('addDeviceRoleGuardian')), findsOneWidget);
    expect(find.byKey(const Key('addDeviceContinueButton')), findsOneWidget);
  });

  testWidgets('a single child never shows a dropdown; more than one does', (tester) async {
    await pump(tester, client: stubClient());
    expect(find.byKey(const Key('addDeviceChildDropdown')), findsNothing);

    await pump(tester, client: stubClient(), children: const [
      ChildOption(id: 'child-1', name: 'Ivy'), ChildOption(id: 'child-2', name: 'Milo'),
    ]);
    expect(find.byKey(const Key('addDeviceChildDropdown')), findsOneWidget);
  });

  testWidgets('picking "my own other device" hides the child dropdown', (tester) async {
    await pump(tester, client: stubClient(), children: const [
      ChildOption(id: 'child-1', name: 'Ivy'), ChildOption(id: 'child-2', name: 'Milo'),
    ]);
    await tester.tap(find.byKey(const Key('addDeviceRoleGuardian')));
    await tester.pump();
    expect(find.byKey(const Key('addDeviceChildDropdown')), findsNothing);
  });

  testWidgets('Continue moves to the PIN re-entry gate', (tester) async {
    await pump(tester, client: stubClient());
    await tester.tap(find.byKey(const Key('addDeviceContinueButton')));
    await tester.pump();
    expect(find.byKey(const Key('addDevicePinField')), findsOneWidget);
    expect(find.byKey(const Key('addDeviceGenerateButton')), findsOneWidget);
  });

  testWidgets('a wrong PIN shows a real, specific error and stays on the PIN step', (tester) async {
    await pump(tester, client: stubClient(pinStatus: 403, pinError: 'pin_incorrect'));
    await tester.tap(find.byKey(const Key('addDeviceContinueButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addDevicePinField')), '0000');
    await tester.tap(find.byKey(const Key('addDeviceGenerateButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining("doesn't match"), findsOneWidget);
    expect(find.byKey(const Key('addDevicePinField')), findsOneWidget);
  });

  testWidgets('a correct PIN generates a real code: QR, numeric code, and a live countdown',
      (tester) async {
    final calledPaths = <String>[];
    await pump(tester, client: stubClient(calledPaths: calledPaths));
    await tester.tap(find.byKey(const Key('addDeviceContinueButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addDevicePinField')), '1357');
    await tester.tap(find.byKey(const Key('addDeviceGenerateButton')));
    await tester.pumpAndSettle();

    expect(calledPaths, contains('POST /v1/children/child-1/device-pairing-codes'));
    expect(find.text('123456'), findsOneWidget);
    expect(find.textContaining('Expires in'), findsOneWidget);
    expect(find.byKey(const Key('addDeviceCancelButton')), findsOneWidget);
  });

  testWidgets('generating a GUARDIAN-role code calls /v1/me/device-pairing-codes, not a childId path',
      (tester) async {
    final calledPaths = <String>[];
    await pump(tester, client: stubClient(calledPaths: calledPaths));
    await tester.tap(find.byKey(const Key('addDeviceRoleGuardian')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('addDeviceContinueButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addDevicePinField')), '1357');
    await tester.tap(find.byKey(const Key('addDeviceGenerateButton')));
    await tester.pumpAndSettle();
    expect(calledPaths, contains('POST /v1/me/device-pairing-codes'));
    expect(calledPaths.any((p) => p.contains('children')), isFalse);
  });

  // NOT a real-clock-advancement test: `tester.pump(duration)` fast-forwards
  // flutter_test's FAKE timer clock, but this screen's own countdown reads
  // `DateTime.now()` (real wall-clock — a live-server-issued `expiresAt` IS
  // real wall-clock time, so this is the honest thing for it to read), which
  // FakeAsync does not advance. Instead this proves the SAME underlying
  // logic two other ways, each its own fresh widget tree (two `pump()` calls
  // reusing one AddDeviceScreen's State would silently carry the first
  // scenario's `_step` into the second): a far-future expiry reads
  // "Expires in", and an already-past one reads "expired" — both true from
  // the very first frame, with no timer-driven wait needed either way.
  testWidgets('a far-future expiry shows a real "Expires in" countdown', (tester) async {
    await pump(tester, client: stubClient(
      expiresAt: DateTime.now().add(const Duration(minutes: 9)).toIso8601String()));
    await tester.tap(find.byKey(const Key('addDeviceContinueButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addDevicePinField')), '1357');
    await tester.tap(find.byKey(const Key('addDeviceGenerateButton')));
    await tester.pump();
    await tester.pump();
    // A RANGE, not a pinned "8m" — this reads real wall-clock time
    // (DateTime.now(), see this group's own header), so pinning to an exact
    // minute value is a real, load-sensitive flake: this suite's own full
    // run under this repo's own heavier concurrent load (dozens of other
    // suites/processes contending for the same machine) has genuinely taken
    // over a minute of real wall-clock time between this widget building
    // and this assertion running, which would tip "8m" over to "7m" purely
    // from scheduling delay having nothing to do with this screen's own
    // correctness. 6-9 minutes remaining, out of a real 9-minute expiry, is
    // the actual property worth proving: a real, sane countdown value, not
    // a stale/frozen one and not a negative one.
    final countdownText = tester.widget<Text>(find.byKey(const Key('addDeviceCountdown'))).data!;
    final minutesMatch = RegExp(r'Expires in (\d+)m').firstMatch(countdownText);
    expect(minutesMatch, isNotNull, reason: 'expected an "Expires in Nm ..." countdown, got: $countdownText');
    final minutes = int.parse(minutesMatch!.group(1)!);
    expect(minutes, inInclusiveRange(6, 9));
  });

  testWidgets('an already-past expiry honestly reads as expired, not a negative countdown',
      (tester) async {
    await pump(tester, client: stubClient(
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String()));
    await tester.tap(find.byKey(const Key('addDeviceContinueButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addDevicePinField')), '1357');
    await tester.tap(find.byKey(const Key('addDeviceGenerateButton')));
    await tester.pump();
    await tester.pump();
    expect(find.text('This code has expired'), findsOneWidget);
  });

  testWidgets('Cancel calls the real cancel route and returns to the role-picker step',
      (tester) async {
    final calledPaths = <String>[];
    await pump(tester, client: stubClient(calledPaths: calledPaths));
    await tester.tap(find.byKey(const Key('addDeviceContinueButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addDevicePinField')), '1357');
    await tester.tap(find.byKey(const Key('addDeviceGenerateButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addDeviceCancelButton')));
    await tester.pumpAndSettle();
    expect(calledPaths, contains('POST /v1/device-pairing-codes/code-1/cancel'));
    expect(find.byKey(const Key('addDeviceRoleChild')), findsOneWidget);
  });

  testWidgets('a network failure on generate shows an honest message', (tester) async {
    final client = MockClient((req) async => throw Exception('no route to host'));
    await pump(tester, client: client);
    await tester.tap(find.byKey(const Key('addDeviceContinueButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addDevicePinField')), '1357');
    await tester.tap(find.byKey(const Key('addDeviceGenerateButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
  });
}
