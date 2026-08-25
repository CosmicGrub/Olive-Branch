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

  // A real, not-yet-decided invite the GET load would return — used by
  // every real-path test below that isn't specifically exercising a
  // not-found/expired/already_accepted/revoked/network outcome.
  Map<String, dynamic> liveInvite({String label = 'Mom', String role = 'guardian'}) => {
    'id': 'inv-1', 'childId': 'child-1', 'invitedBy': 'guardian-1',
    'invitedEmail': 'ro@example.com', 'role': role, 'label': label,
    'createdAt': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    'expiresAt': DateTime.now().add(const Duration(days: 13)).toIso8601String(),
    'acceptedAt': null, 'revokedAt': null,
  };

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
    testWidgets('loads the real invite first: a genuine GET, then a genuine POST (not a guess)',
        (tester) async {
      var accepted = false;
      final calledPaths = <String>[];
      final client = MockClient((req) async {
        calledPaths.add('${req.method} ${req.url.path}');
        if (req.method == 'GET') {
          return http.Response(jsonEncode({'invite': liveInvite()}), 200);
        }
        return http.Response(jsonEncode({'ok': true, 'invite': {'id': 'inv-1'}}), 200);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: () => accepted = true,
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle(); // the real-path GET load settles
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pumpAndSettle();
      expect(calledPaths,
        ['GET /v1/guardian-invites/inv-1', 'POST /v1/guardian-invites/inv-1/accept']);
      expect(accepted, isTrue);
    });

    testWidgets("the server's real label overrides a stale caller-supplied yourLabel",
        (tester) async {
      // The caller passes a guess -- exactly what guardian_more.dart's
      // hardcoded 'Mom' would be for an invite that's actually for someone
      // else entirely. The real invite's own `label` (0014_guardian_invite.
      // sql's column, the one wire field this screen can cross-check) must
      // win once it's loaded, or a guardian could accept under copy that
      // was never checked against the record the POST is about to act on.
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode({'invite': liveInvite(label: 'Auntie Ro', role: 'trusted_adult')}), 200);
        }
        return http.Response(jsonEncode({'ok': true, 'invite': {'id': 'inv-1'}}), 200);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle();
      expect(find.textContaining("Ivy's family as Auntie Ro"), findsOneWidget);
      expect(find.textContaining('as Mom'), findsNothing);
    });

    testWidgets('shows a loading state while the invite itself is loading', (tester) async {
      final completer = Completer<http.Response>();
      final client = MockClient((req) async => completer.future);
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Nothing about the invite is known yet, so nothing is tappable —
      // the button (and the copy it would gate) doesn't exist at all.
      expect(find.byKey(const Key('acceptInvitationButton')), findsNothing);
      completer.complete(http.Response(jsonEncode({'invite': liveInvite()}), 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('acceptInvitationButton')), findsOneWidget);
    });

    testWidgets('shows a loading state while the accept request is in flight', (tester) async {
      // A Completer, not an instantly-resolving MockClient callback, so the
      // in-flight frame is actually observable rather than racing a single
      // pump() against a microtask that may already be done by then.
      final completer = Completer<http.Response>();
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(jsonEncode({'invite': liveInvite()}), 200);
        }
        return completer.future;
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle(); // the GET load settles; button now live
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completer.complete(http.Response(jsonEncode({'ok': true, 'invite': {'id': 'inv-1'}}), 200));
      await tester.pumpAndSettle();
    });

    testWidgets('a not-found invite (GET 404) blocks Accept before any POST is attempted',
        (tester) async {
      final calledMethods = <String>[];
      final client = MockClient((req) async {
        calledMethods.add(req.method);
        return http.Response(jsonEncode({'error': 'not_found'}), 404);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle();
      expect(find.textContaining("couldn't be found"), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const Key('acceptInvitationButton')));
      expect(button.onPressed, isNull);
      expect(calledMethods, ['GET']);
    });

    testWidgets('an invite already expired when loaded blocks Accept before any POST is attempted',
        (tester) async {
      final calledMethods = <String>[];
      final client = MockClient((req) async {
        calledMethods.add(req.method);
        return http.Response(jsonEncode({'invite': {
          ...liveInvite(),
          'expiresAt': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        }}), 200);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle();
      expect(find.textContaining('This invitation has expired'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const Key('acceptInvitationButton')));
      expect(button.onPressed, isNull);
      expect(calledMethods, ['GET']);
    });

    testWidgets('an already-accepted invite blocks Accept before any POST is attempted',
        (tester) async {
      final calledMethods = <String>[];
      final client = MockClient((req) async {
        calledMethods.add(req.method);
        return http.Response(jsonEncode({'invite': {
          ...liveInvite(),
          'acceptedAt': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        }}), 200);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle();
      expect(find.textContaining('already accepted'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const Key('acceptInvitationButton')));
      expect(button.onPressed, isNull);
      expect(calledMethods, ['GET']);
    });

    testWidgets('a revoked invite blocks Accept before any POST is attempted', (tester) async {
      final calledMethods = <String>[];
      final client = MockClient((req) async {
        calledMethods.add(req.method);
        return http.Response(jsonEncode({'invite': {
          ...liveInvite(),
          'revokedAt': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        }}), 200);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle();
      expect(find.textContaining('cancelled'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const Key('acceptInvitationButton')));
      expect(button.onPressed, isNull);
      expect(calledMethods, ['GET']);
    });

    testWidgets('a network failure loading the invite blocks Accept with an honest message',
        (tester) async {
      final client = MockClient((req) async => throw Exception('no route to host'));
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom', onAccept: () {},
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const Key('acceptInvitationButton')));
      expect(button.onPressed, isNull);
    });

    testWidgets('a POST-time race (expired between load and tap) shows the real reason, '
        'never fires onAccept', (tester) async {
      // The GET load says this invite is fine; the POST -- moments later --
      // finds out it is not. This is the backstop file header's own comment
      // calls out: an invite can still turn stale in that gap, and the real
      // POST answer must still be believed over a load that already went
      // stale, never papered over by firing onAccept anyway.
      var accepted = false;
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(jsonEncode({'invite': liveInvite()}), 200);
        }
        return http.Response(jsonEncode({'error': 'expired'}), 410);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: () => accepted = true,
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      expect(find.textContaining('This invitation has expired'), findsOneWidget);
    });

    testWidgets('a network failure on accept shows an honest message, never fires onAccept',
        (tester) async {
      var accepted = false;
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(jsonEncode({'invite': liveInvite()}), 200);
        }
        throw Exception('no route to host');
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: () => accepted = true,
        baseUrl: 'http://olive.test', inviteId: 'inv-1', httpClient: client)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    });

    testWidgets('missing either baseUrl or inviteId falls back to the simulated tap, '
        'no GET attempted', (tester) async {
      var accepted = false;
      var requested = false;
      final client = MockClient((req) async {
        requested = true;
        return http.Response('{}', 200);
      });
      await tester.pumpWidget(MaterialApp(home: InvitationScreen(
        childName: 'Ivy', inviterLabel: 'Dad', yourLabel: 'Mom',
        onAccept: () => accepted = true, baseUrl: 'http://olive.test' /* no inviteId */,
        httpClient: client)));
      await tester.pump();
      expect(find.byKey(const Key('acceptInvitationButton')), findsOneWidget,
        reason: 'no load should be attempted, so the button renders immediately');
      await tester.tap(find.byKey(const Key('acceptInvitationButton')));
      await tester.pump();
      expect(accepted, isTrue, reason: 'no network call should be attempted at all');
      expect(requested, isFalse);
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
