import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/emergency_card.dart';

void main() {
  // Tall surface so every section is actually laid out by the ListView's
  // sliver — a viewport too short leaves off-screen sections unbuilt, which
  // would make "not found" indistinguishable from "not rendered".
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: EmergencyCardScreen()));
  }

  testWidgets('allergy warning renders with the specific demo allergy',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('allergyCard')), findsOneWidget);
    expect(find.textContaining('Peanuts'), findsOneWidget);
    expect(find.textContaining('EpiPen'), findsOneWidget);
  });

  testWidgets('allergy card sits above every other section on screen',
      (tester) async {
    await pump(tester);
    final allergyTop = tester.getTopLeft(find.byKey(const Key('allergyCard'))).dy;

    for (final laterText in [
      'Blood type', 'Current medications', 'Guardians',
      'Pediatrician', 'Insurance',
    ]) {
      final sectionTop = tester.getTopLeft(find.text(laterText.toUpperCase())).dy;
      expect(allergyTop, lessThan(sectionTop),
        reason: '$laterText header should be below the allergy card');
    }
  });

  testWidgets('blood type renders with a real demo value', (tester) async {
    await pump(tester);
    expect(find.text('O positive'), findsOneWidget);
  });

  testWidgets('medications render with name, dose, and schedule', (tester) async {
    await pump(tester);
    expect(find.text('Cetirizine'), findsOneWidget);
    expect(find.textContaining('5 mg'), findsOneWidget);
    expect(find.text('Albuterol inhaler'), findsOneWidget);
    expect(find.textContaining('as needed'), findsOneWidget);
  });

  testWidgets('both guardians render with names and phone numbers',
      (tester) async {
    await pump(tester);
    expect(find.textContaining('Claire Solomon'), findsOneWidget);
    expect(find.textContaining('Marcus Solomon'), findsOneWidget);
    expect(find.text('(617) 555-0142'), findsOneWidget);
    expect(find.text('(617) 555-0198'), findsOneWidget);
  });

  testWidgets('pediatrician renders with name and phone', (tester) async {
    await pump(tester);
    expect(find.textContaining('Dr. Priya Nair'), findsOneWidget);
    expect(find.text('(617) 555-0177'), findsOneWidget);
  });

  testWidgets('insurance renders with provider and member ID', (tester) async {
    await pump(tester);
    expect(find.text('BlueBridge Family Health'), findsOneWidget);
    expect(find.textContaining('BBH-7734-2201'), findsOneWidget);
  });

  testWidgets('everything fits on one screen with no tabs or expand/collapse',
      (tester) async {
    await pump(tester);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('has no interactive form fields — this is a read-only screen',
      (tester) async {
    await pump(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Radio), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('the non-functional Call button reports itself honestly',
      (tester) async {
    await pump(tester);
    final callButtons = find.byIcon(Icons.call);
    expect(callButtons, findsWidgets);

    await tester.tap(callButtons.first);
    await tester.pump();
    expect(find.textContaining('not built yet.'), findsOneWidget);
  });

  testWidgets('no animated widgets are used anywhere on this still surface',
      (tester) async {
    await pump(tester);
    expect(find.byType(AnimatedContainer), findsNothing);
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.byType(AnimatedPositioned), findsNothing);
  });
}
