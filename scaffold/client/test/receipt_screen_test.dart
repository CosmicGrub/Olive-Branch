// OLIVE BRANCH — receipt_screen.dart tests. §8.2.4, §9.5.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/receipt_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('Receipt — §8.2.4, her frame first', () {
    testWidgets('renders the exact quoted phrase shape, her frame, her name', (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(find.text("Watched at 7:04 AM Ivy's time — before school."), findsOneWidget);
    });

    testWidgets('names the sender and the child, not an id', (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(find.textContaining("Dad's message"), findsOneWidget);
    });

    testWidgets('a null day-part still renders an honest phrase with no dangling dash',
        (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '2:00 PM', dayPartKind: null)));
      expect(find.text("Watched at 2:00 PM Ivy's time."), findsOneWidget);
      expect(find.textContaining('—'), findsNothing);
    });

    testWidgets('never shows a zone abbreviation, UTC, or raw offset arithmetic',
        (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(find.textContaining('UTC'), findsNothing);
      expect(find.textContaining('GMT'), findsNothing);
      expect(find.textContaining('+1'), findsNothing);
    });

    testWidgets('NO settings affordance, no price, no error copy anywhere', (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('failed'), findsNothing);
    });

    testWidgets("'Send one back' is an honest stub, not a faked success", (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      await tester.tap(find.text('Send one back'));
      await tester.pump();
      expect(find.textContaining('not built yet.'), findsOneWidget);
      expect(find.textContaining('Sent!'), findsNothing);
    });

    testWidgets('both primary buttons meet the 48dp+ touch target minimum', (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(tester.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(48.0));
      expect(tester.getSize(find.byType(OutlinedButton)).height, greaterThanOrEqualTo(48.0));
    });

    group('responsive — no overflow at any required viewport width', () {
      Future<void> pumpAt(WidgetTester tester, Size size) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(wrap(const ReceiptScreen(
          childName: 'Ivy', senderName: 'Dad',
          watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
        await tester.pump();
      }

      testWidgets('Fold5 cover screen (344 CSS px wide)', (tester) async {
        await pumpAt(tester, const Size(344, 900));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Fold5 unfolded main screen (~673x841, nearly square)', (tester) async {
        await pumpAt(tester, const Size(673, 841));
        expect(tester.takeException(), isNull);
      });

      testWidgets('standard phone width (~390px)', (tester) async {
        await pumpAt(tester, const Size(390, 844));
        expect(tester.takeException(), isNull);
      });

      testWidgets('tablet/desktop width (~1100px, short and wide)', (tester) async {
        await pumpAt(tester, const Size(1100, 800));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets("'Back to messages' pops the route", (tester) async {
      await tester.pumpWidget(wrap(Builder(builder: (context) => Scaffold(
        body: Center(child: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const ReceiptScreen(
              childName: 'Ivy', senderName: 'Dad',
              watchedAtLabel: '7:04 AM', dayPartKind: 'before_school'))),
          child: const Text('open'))),
      ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsOneWidget);
      await tester.tap(find.text('Back to messages'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsNothing);
    });
  });
}
