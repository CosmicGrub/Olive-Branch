// OLIVE BRANCH — invitation_screen.dart tests. §8.5.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
