// OLIVE BRANCH — inbox_screen.dart tests. §8.2, §9.5.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/inbox_screen.dart';
import 'package:olive_client/receipt_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

const List<InboxMessage> _messages = <InboxMessage>[
  InboxMessage(id: 1, senderName: 'Dad', deliveredAtLabel: '7:04 AM', dayPartKind: 'before_school'),
  InboxMessage(id: 2, senderName: 'Dad', deliveredAtLabel: 'Yesterday, 7:58 PM',
    dayPartKind: 'wind_down', watched: true),
];

void main() {
  group('Inbox — §8.2, §9.5', () {
    testWidgets('greets the child by name and states the unread count plainly',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      expect(find.textContaining('Hi Ivy'), findsOneWidget);
      expect(find.textContaining('1 new message'), findsOneWidget);
    });

    testWidgets('every message in the list renders a tile', (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      expect(find.textContaining('Dad sent a video'), findsNWidgets(2));
      expect(find.textContaining('New — tap to watch'), findsOneWidget);
      expect(find.textContaining('Watched · Yesterday, 7:58 PM'), findsOneWidget);
    });

    testWidgets('NO settings affordance and no price/financial text — P4, P6',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('price'), findsNothing);
      expect(find.textContaining('error'), findsNothing);
    });

    testWidgets('this is informational unread state, not a streak or score — P2',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('badge'), findsNothing);
    });

    testWidgets('opening an unwatched message marks it watched and opens its receipt',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      expect(find.textContaining('New — tap to watch'), findsOneWidget);

      await tester.tap(find.textContaining('New — tap to watch'));
      await tester.pumpAndSettle();

      // Landed on a real receipt, in her frame, with her name — never the
      // sender's clock, never a raw zone.
      expect(find.byType(ReceiptScreen), findsOneWidget);
      expect(find.textContaining("Ivy's time"), findsOneWidget);
      expect(find.textContaining('UTC'), findsNothing);

      // Back in the inbox, the message is now watched — no longer "New".
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('New — tap to watch'), findsNothing);
      expect(find.textContaining('Hi Ivy, all caught up'), findsOneWidget);
    });

    testWidgets('opening an already-watched message reopens its stored receipt honestly',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      await tester.tap(find.textContaining('Watched · Yesterday, 7:58 PM'));
      await tester.pumpAndSettle();
      expect(find.text("Watched at Yesterday, 7:58 PM Ivy's time — winding down."),
        findsOneWidget);
    });

    testWidgets('an empty inbox is handled honestly, not with a crash or a fake row',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: <InboxMessage>[])));
      expect(find.textContaining('Nothing here yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('message tiles meet the 48dp+ touch target minimum', (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      final int count = find.byType(InkWell).evaluate().length;
      expect(count, 2);
      for (int i = 0; i < count; i++) {
        expect(tester.getSize(find.byType(InkWell).at(i)).height, greaterThanOrEqualTo(48.0));
      }
    });
  });
}
