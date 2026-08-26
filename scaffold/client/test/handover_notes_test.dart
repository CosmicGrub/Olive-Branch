// OLIVE BRANCH — handover log tests. P8, §21.7.
//
// The one invariant that matters most here: there is no way, anywhere in
// this tree, to delete or edit an entry. Everything else is secondary to
// that assertion holding across the WHOLE rendered widget tree, not just
// the entries visible at first paint.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/handover_notes.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  // Tall surface so every entry's Card is actually laid out by the
  // ListView.builder's sliver, not just whatever fits the default test
  // window — the read-aloud IconButton this pass adds to each row made
  // every Card slightly taller, which was enough to push a 5th entry (after
  // a test adds one) outside the previous default viewport's built range.
  // Same "off-screen leaves things unbuilt" fix emergency_card_test.dart's
  // own pump() helper already documents for the identical reason.
  Future<void> pumpTall(WidgetTester t, Widget child) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(child);
  }

  group('handover notes — P8, §21.7', () {
    testWidgets('seeds with pre-existing entries, not empty', (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      expect(find.byType(Card), findsNWidgets(4));
      expect(find.textContaining('Running about 15 minutes late'), findsOneWidget);
    });

    testWidgets('adding a note appends a new, correctly-attributed entry',
        (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      final int before = find.byType(Card).evaluate().length;

      await t.enterText(find.byType(TextField),
          "Forgot her library book on the counter, it's due back Friday.");
      await t.tap(find.text('Add note'));
      await t.pump();

      expect(find.textContaining('Forgot her library book on the counter'),
          findsOneWidget);
      expect(find.byType(Card).evaluate().length, before + 1);

      // The new entry sits in a Card alongside the 'You' author label.
      final Finder newCard = find.ancestor(
        of: find.textContaining('Forgot her library book on the counter'),
        matching: find.byType(Card));
      expect(find.descendant(of: newCard, matching: find.text('You')),
          findsOneWidget);
    });

    testWidgets('the text field clears after a successful add', (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      await t.enterText(find.byType(TextField), 'Swim lessons moved to Saturday.');
      await t.tap(find.text('Add note'));
      await t.pump();
      final TextField field = t.widget(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('blank input does not append a new entry', (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      final int before = find.byType(Card).evaluate().length;
      await t.enterText(find.byType(TextField), '   ');
      await t.tap(find.text('Add note'));
      await t.pump();
      expect(find.byType(Card).evaluate().length, before);
    });

    testWidgets('NO delete or edit affordance exists anywhere in the tree',
        (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      // Add one more entry first so the check covers freshly-appended state too.
      await t.enterText(find.byType(TextField), 'Checking the invariant after an append.');
      await t.tap(find.text('Add note'));
      await t.pump();

      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.delete_forever), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
      expect(find.textContaining('Delete'), findsNothing);
      expect(find.textContaining('Edit'), findsNothing);
      // §8.8.5's read-aloud IconButton is real and expected here — the
      // invariant this test actually protects is "no delete/edit
      // affordance", not "no IconButton at all" (that broader check would
      // have quietly started failing the moment ANY legitimate, unrelated
      // IconButton was added anywhere on this screen). Every IconButton
      // present must be the read-aloud one and nothing else.
      final Iterable<IconButton> buttons =
          t.widgetList<IconButton>(find.byType(IconButton));
      expect(buttons, isNotEmpty, reason: 'the read-aloud buttons should be present');
      for (final IconButton b in buttons) {
        expect((b.icon as Icon).icon, Icons.volume_up_outlined);
        expect(b.tooltip, 'Read this entry aloud');
      }
    });

    testWidgets('append-only disclosure copy is genuinely present and visible',
        (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      final Finder disclosure = find.textContaining("can't be edited or removed");
      expect(disclosure, findsOneWidget);
      // Actually laid out on screen, not an offstage/zero-size artifact.
      final Size size = t.getSize(disclosure);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });
  });

  group('read aloud — §8.8.5', () {
    testWidgets('one read-aloud button per entry, absent speak reports itself honestly',
        (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      expect(find.byIcon(Icons.volume_up_outlined), findsNWidgets(4));

      await t.tap(find.byKey(const Key('readAloudButton_0')));
      await t.pump();
      expect(find.textContaining('Read aloud — not built yet.'), findsOneWidget);
    });

    testWidgets('a real speak callback reads that entry only — author, when, and text',
        (t) async {
      final List<String> spoken = [];
      await pumpTall(t, wrap(HandoverNotesScreen(speak: (text) async => spoken.add(text))));

      // Index 0 is the newest-first entry — the Aug 1 peanut-free lunch note.
      await t.tap(find.byKey(const Key('readAloudButton_0')));
      await t.pump();

      expect(spoken, hasLength(1));
      expect(spoken.single, contains('You'));
      expect(spoken.single, contains('Aug 1'));
      expect(spoken.single, contains('peanut-free'));
      // Must not bleed into a different entry's content.
      expect(spoken.single, isNot(contains('Picture day')));
    });

    testWidgets('a newly-added entry gets its own working read-aloud button',
        (t) async {
      final List<String> spoken = [];
      await pumpTall(t, wrap(HandoverNotesScreen(speak: (text) async => spoken.add(text))));
      await t.enterText(find.byType(TextField), 'A brand new note to read back.');
      await t.tap(find.text('Add note'));
      await t.pump();

      // Newest-first: the just-added entry is index 0 now.
      await t.tap(find.byKey(const Key('readAloudButton_0')));
      await t.pump();
      expect(spoken.single, contains('A brand new note to read back.'));
    });
  });

  group('handover notes — responsive two-pane split (§8.11.1, form_factors.dart)', () {
    testWidgets('a genuinely wide viewport (tablet/desktop, >=660px effective) renders the '
        'compose form and the entries list as two side-by-side panes', (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('handoverNotesTwoPaneRow')), findsOneWidget);
      // Pane A content (the compose form) and Pane B content (an entry) are
      // both genuinely present at once.
      expect(find.textContaining("can't be edited or removed"), findsOneWidget);
      expect(find.textContaining('Running about 15 minutes late'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the Fold5 cover width (344px) keeps the exact stacked single column '
        'unchanged — no two-pane Row at all', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('handoverNotesTwoPaneRow')), findsNothing);
      expect(find.textContaining("can't be edited or removed"), findsOneWidget);
      expect(find.textContaining('Running about 15 minutes late'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a standard phone width (390px) also keeps the stacked single column, '
        'not the two-pane Row', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('handoverNotesTwoPaneRow')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('adding a note still works correctly inside the wide two-pane layout',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('handoverNotesTwoPaneRow')), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Wide-pane handover note.');
      await t.tap(find.text('Add note'));
      await t.pump();

      // Still inside the wide two-pane layout, and the new entry landed in
      // the list pane.
      expect(find.byKey(const Key('handoverNotesTwoPaneRow')), findsOneWidget);
      expect(find.textContaining('Wide-pane handover note.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('live wiring — the real message_log-backed routes '
      '(server/routes.mjs, packages/db/src/pool.ts appendHandoverNote/'
      'handoverNotesFor)', () {
    testWidgets('shows a loading indicator, then real fetched entries replace '
        'the demo fixtures', (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        expect(req.url.path, '/v1/children/child-a/handover-notes');
        expect(req.headers['authorization'], 'Bearer tok');
        return http.Response(jsonEncode({'entries': [
          {'seq': 0, 'authorId': 'dad-1', 'authorName': 'Dad',
           'at': '2026-07-28T16:12:00.000Z', 'body': 'Real note one.',
           'whenLabel': 'Jul 28, 9:12 AM'},
          {'seq': 1, 'authorId': 'mom-1', 'authorName': 'Mom',
           'at': '2026-07-28T16:20:00.000Z', 'body': 'Real note two.',
           'whenLabel': 'Jul 28, 9:20 AM'},
        ]}), 200);
      });
      await pumpTall(t, wrap(HandoverNotesScreen(
        baseUrl: 'http://api.test', childId: 'child-a', guardianId: 'dad-1',
        httpClient: mock)));
      // Before the fetch resolves this is the real loading state, not the
      // demo fixtures for one frame.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();

      // The real fetched rows, not the demo fixtures — proves this is
      // actually live data, not a coincidentally-similar hardcoded list.
      expect(find.textContaining('Real note one.'), findsOneWidget);
      expect(find.textContaining('Real note two.'), findsOneWidget);
      expect(find.textContaining('Running about 15 minutes late'), findsNothing);
      // authorId 'dad-1' matches the threaded-in guardianId -> 'You';
      // 'mom-1' does not -> the real authorName, 'Mom'.
      final Finder noteOneCard = find.ancestor(
        of: find.textContaining('Real note one.'), matching: find.byType(Card));
      expect(find.descendant(of: noteOneCard, matching: find.text('You')), findsOneWidget);
      final Finder noteTwoCard = find.ancestor(
        of: find.textContaining('Real note two.'), matching: find.byType(Card));
      expect(find.descendant(of: noteTwoCard, matching: find.text('Mom')), findsOneWidget);
      // whenLabel is rendered verbatim — no client-side timezone math.
      expect(find.textContaining('Jul 28, 9:20 AM'), findsOneWidget);
    });

    testWidgets('adding a note POSTs the real body to the real route and '
        "renders the SERVER's own returned entry, not a client-guessed one",
        (t) async {
      final List<http.Request> posts = <http.Request>[];
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST') {
          posts.add(req);
          return http.Response(jsonEncode({
            'ok': true, 'seq': 4, 'authorId': 'dad-1',
            'at': '2026-08-02T15:00:00.000Z', 'body': 'A brand new live note.',
            'whenLabel': 'Aug 2, 8:00 AM',
          }), 201);
        }
        return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
      });
      await pumpTall(t, wrap(HandoverNotesScreen(
        baseUrl: 'http://api.test', childId: 'child-a', guardianId: 'dad-1',
        httpClient: mock)));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), 'A brand new live note.');
      await t.tap(find.text('Add note'));
      await t.pumpAndSettle();

      expect(posts, hasLength(1));
      expect(posts.single.url.path, '/v1/children/child-a/handover-notes');
      expect(posts.single.headers['authorization'], 'Bearer tok');
      expect(jsonDecode(posts.single.body), {'body': 'A brand new live note.'});

      // The rendered entry uses the SERVER's own whenLabel ('Aug 2, 8:00 AM')
      // -- proves this isn't _nowLabel()'s demo-only client clock, which
      // would render today's real wall-clock date instead.
      expect(find.textContaining('A brand new live note.'), findsOneWidget);
      expect(find.textContaining('Aug 2, 8:00 AM'), findsOneWidget);
      final TextField field = t.widget(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('a real POST failure shows a visible, honest error and '
        'leaves the typed text in place -- never a silent no-op that lets a '
        'guardian believe the other parent was actually told something',
        (t) async {
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.method == 'POST') return http.Response('server error', 500);
        return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
      });
      await pumpTall(t, wrap(HandoverNotesScreen(
        baseUrl: 'http://api.test', childId: 'child-a', guardianId: 'dad-1',
        httpClient: mock)));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), 'This one will fail to send.');
      await t.tap(find.text('Add note'));
      await t.pumpAndSettle();

      expect(find.textContaining("Couldn't send that note"), findsOneWidget);
      // Never rendered as a real Card entry (findsNothing among Cards
      // specifically -- find.textContaining alone would also match the
      // still-populated TextField's own EditableText content, which is
      // exactly what the very next assertion confirms on purpose).
      expect(find.byType(Card), findsNothing);
      final TextField field = t.widget(find.byType(TextField));
      expect(field.controller!.text, 'This one will fail to send.'); // not cleared
      expect(t.takeException(), isNull);
    });

    testWidgets('a real fetch failure is an honest error with a working '
        'retry, never a crash or a silent fallback to the demo fixtures',
        (t) async {
      int calls = 0;
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        calls++;
        if (calls == 1) return http.Response('server error', 500);
        return http.Response(jsonEncode({'entries': <dynamic>[]}), 200);
      });
      await pumpTall(t, wrap(HandoverNotesScreen(
        baseUrl: 'http://api.test', childId: 'child-a', guardianId: 'dad-1',
        httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
      expect(find.textContaining('Running about 15 minutes late'), findsNothing);
      expect(t.takeException(), isNull);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.byType(Card), findsNothing); // real empty list, honestly rendered
      expect(calls, 2);
    });

    testWidgets('with no live params supplied, the demo fixtures render '
        'exactly as before -- no network call, no loading state', (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Running about 15 minutes late'), findsOneWidget);
    });
  });
}
