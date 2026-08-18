// OLIVE BRANCH — invitation_screen.dart tests. §8.5, §11.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/invitation_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required VoidCallback onAccept, VoidCallback? onDecline}) =>
      tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: onAccept, onDecline: onDecline)));

  testWidgets('states who invited whom and what the new guardian will be called', (tester) async {
    await pump(tester, onAccept: () {});
    expect(find.textContaining('Dad has invited you'), findsOneWidget);
    expect(find.textContaining("Ivy's family as Mom"), findsOneWidget);
  });

  testWidgets('accepting fires onAccept', (tester) async {
    var accepted = false;
    await pump(tester, onAccept: () => accepted = true);
    await tester.tap(find.text('Accept invitation'));
    await tester.pump();
    expect(accepted, isTrue);
  });

  testWidgets('declining fires onDecline when supplied, and is hidden when not', (tester) async {
    var declined = false;
    await pump(tester, onAccept: () {}, onDecline: () => declined = true);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(declined, isTrue);

    await pump(tester, onAccept: () {}); // onDecline omitted
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('mentions the passkey path onward, never collects a password', (tester) async {
    await pump(tester, onAccept: () {});
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    // Copy is allowed to REASSURE ("no password to create or remember") —
    // what must never exist is a field that collects one.
    expect(find.textContaining('no password'), findsOneWidget);
    expect(find.textContaining('passkey'), findsOneWidget);
  });

  testWidgets('data symmetry is stated plainly, without any conflict framing', (tester) async {
    await pump(tester, onAccept: () {});
    expect(find.textContaining('nothing hidden between guardians'), findsOneWidget);
    expect(find.textContaining('custody'), findsNothing);
  });

  testWidgets('no financial surface, and the accept action clears 48dp', (tester) async {
    await pump(tester, onAccept: () {}, onDecline: () {});
    expect(find.textContaining(RegExp(r'\$')), findsNothing);
    final acceptButton = find.ancestor(
      of: find.text('Accept invitation'), matching: find.byType(FilledButton));
    final size = tester.getSize(acceptButton);
    expect(size.height, greaterThanOrEqualTo(48));
  });

  group('the real path — baseUrl + inviteId supplied', () {
    testWidgets('a genuine 200 fires onAccept, and calls the real endpoint (not a guess)',
        (tester) async {
      var accepted = false;
      String? calledPath;
      final client = MockClient((req) async {
        calledPath = req.url.path;
        return http.Response(jsonEncode({'ok': true, 'invite': {'id': 'inv-1'}}), 200);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: () => accepted = true,
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pumpAndSettle();
      expect(calledPath, '/v1/guardian-invites/inv-1/accept');
      expect(accepted, isTrue);
    });

    testWidgets('shows a loading state while the request is in flight', (tester) async {
      // A Completer, not an instantly-resolving MockClient callback, so the
      // in-flight frame is actually observable rather than racing a single
      // pump() against a microtask that may already be done by then.
      final completer = Completer<http.Response>();
      final client = MockClient((req) => completer.future);
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completer.complete(http.Response(jsonEncode({'ok': true, 'invite': {'id': 'inv-1'}}), 200));
      await tester.pumpAndSettle();
    });

    testWidgets('an expired invite shows the real reason, never fires onAccept', (tester) async {
      var accepted = false;
      final client = MockClient((req) async =>
        http.Response(jsonEncode({'error': 'expired'}), 410));
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: () => accepted = true,
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('a network failure shows an honest message, never fires onAccept', (tester) async {
      var accepted = false;
      final client = MockClient((req) async => throw Exception('no route to host'));
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: () => accepted = true,
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    });

    testWidgets('missing either baseUrl or inviteId falls back to the simulated tap', (tester) async {
      var accepted = false;
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: () => accepted = true, baseUrl: 'http://olive.test' /* no inviteId */)));
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pump();
      expect(accepted, isTrue, reason: 'no network call should be attempted at all');
    });
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. onDecline supplied so both buttons render.
    const viewports = {
      'Fold5 cover (344x882)': Size(344, 882),
      'Fold5 main (673x841)': Size(673, 841),
      'phone (390x844)': Size(390, 844),
      'tablet/desktop (1200x800)': Size(1200, 800),
    };

    for (final entry in viewports.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pump(tester, onAccept: () {}, onDecline: () {});
        expect(tester.takeException(), isNull);
      });
    }
  });
}
