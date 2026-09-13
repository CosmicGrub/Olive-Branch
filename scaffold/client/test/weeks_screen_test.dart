// OLIVE BRANCH — weeks_screen.dart tests. §8.2, §8.2.5, P3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/form_factors.dart' as ff;
import 'package:olive_client/weeks_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

final List<CustodyNight> _fourteenNights = demoCustodyNights(today: DateTime(2026, 8, 4));

void main() {
  group('Weeks — §8.2.5, sleeps not dates', () {
    testWidgets('renders the child by name, not by id', (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      expect(find.textContaining("Ivy's weeks"), findsOneWidget);
    });

    testWidgets('states who she is with right now, in words', (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      expect(find.textContaining("You're with Mom right now"), findsOneWidget);
    });

    testWidgets('the handover countdown is in sleeps, never hours or a raw date',
        (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      // The demo pattern is 4 nights Mom / 3 nights Dad — the switch is 4 sleeps out.
      expect(find.textContaining('sleeps until'), findsOneWidget);
      expect(find.textContaining('hours'), findsNothing);
      expect(find.textContaining('hour '), findsNothing);
      // No ISO-shaped date (yyyy-mm-dd) anywhere in the rendered tree.
      final Iterable<Text> allTexts = tester.widgetList<Text>(find.byType(Text));
      final RegExp isoDate = RegExp(r'\d{4}-\d{2}-\d{2}');
      for (final Text t in allTexts) {
        final String? data = t.data;
        if (data != null) expect(isoDate.hasMatch(data), isFalse, reason: 'found a raw date in "$data"');
      }
    });

    testWidgets('singular sleep is not "1 sleeps"', (tester) async {
      final List<CustodyNight> nights = <CustodyNight>[
        const CustodyNight(dateIso: '2026-08-04', withWhom: 'Mom'),
        const CustodyNight(dateIso: '2026-08-05', withWhom: 'Dad'),
      ];
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: nights, guardianColors: demoGuardianColors)));
      expect(find.textContaining('sleep until'), findsOneWidget);
      expect(find.textContaining('sleeps until'), findsNothing);
    });

    testWidgets('no location or place ever appears near a night — P3', (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      expect(find.textContaining('address'), findsNothing);
      expect(find.textContaining('location'), findsNothing);
      for (final String word in <String>['Street', 'Ave', 'coordinates', 'lat', 'lng']) {
        expect(find.textContaining(word), findsNothing);
      }
    });

    testWidgets('NO settings affordance and no score/streak language — P2', (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('badge'), findsNothing);
    });

    testWidgets('renders one bead per night and each meets the 48dp touch minimum',
        (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      final Finder beads = find.byType(Tooltip);
      expect(beads.evaluate().length, _fourteenNights.length);
      final Size first = tester.getSize(beads.first);
      expect(first.height, greaterThanOrEqualTo(48.0));
      expect(first.width, greaterThanOrEqualTo(48.0));
    });

    testWidgets("today's bead carries a relative label, never a calendar date",
        (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      final Tooltip todayBead = tester.widget<Tooltip>(find.byType(Tooltip).first);
      expect(todayBead.message, startsWith('Tonight'));
    });

    testWidgets('an empty night list is handled honestly, not with a crash or a fake row',
        (tester) async {
      await tester.pumpWidget(wrap(const WeeksScreen(
        childName: 'Ivy', nights: <CustodyNight>[], guardianColors: demoGuardianColors)));
      expect(find.textContaining('Nothing to show yet'), findsOneWidget);
      expect(find.byIcon(Icons.nights_stay_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long guardian label in the legend does not overflow its chip',
        (tester) async {
      // guardianColors is caller-supplied (unlike the demo's short "Mom"/"Dad")
      // — a real family's label ("Step-mum Jennifer") is not bounded the same
      // way. Found by actually rendering at the Fold5 cover width: an
      // unprotected Text in _LegendChip's Row overflowed by 51px there.
      await tester.binding.setSurfaceSize(const Size(344, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(WeeksScreen(childName: 'Ivy',
        nights: demoCustodyNights(today: DateTime(2026, 8, 4)),
        guardianColors: const <String, Color>{
          'Mom': Color(0xFFAD1457),
          'Step-mum Jennifer-Rosalind': Color(0xFF00838F),
        })));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    group('responsive — no overflow at any required viewport width', () {
      // Fold5 cover, Fold5 main, phone, and tablet/desktop widths. The
      // surface height at each is taller than the named device — this
      // screen renders with a ListView (see class doc), whose sliver only
      // lays out children near the viewport, so a device-accurate short
      // height would leave the legend/beads unbuilt and any overflow in
      // them undetectable. Width is what a RenderFlex overflow actually
      // depends on, so the extra height doesn't change what's being tested.
      Future<void> pumpAt(WidgetTester tester, Size size) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(wrap(WeeksScreen(
          childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
        await tester.pump();
      }

      testWidgets('Fold5 cover screen (344 CSS px wide)', (tester) async {
        await pumpAt(tester, const Size(344, 1400));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Fold5 unfolded main screen (~673x841, nearly square)', (tester) async {
        await pumpAt(tester, const Size(673, 1400));
        expect(tester.takeException(), isNull);
      });

      testWidgets('standard phone width (~390px)', (tester) async {
        await pumpAt(tester, const Size(390, 1400));
        expect(tester.takeException(), isNull);
      });

      testWidgets('tablet/desktop width (~1100px, short and wide)', (tester) async {
        await pumpAt(tester, const Size(1100, 1000));
        expect(tester.takeException(), isNull);
      });
    });

    group('responsive — comfortable reading width cap (form_factors.dart)', () {
      // This is a rhythm visualization, not a list+detail screen (see file
      // header) — never a two-pane split. On a wide tablet/desktop viewport
      // the single column is only ever capped to a comfortable reading
      // width and centered; the Fold5 cover and phone widths are completely
      // untouched by this cap.
      testWidgets('the cap engages only on a wide tablet/desktop viewport — '
          'never at the Fold5 cover or phone width', (tester) async {
        Future<void> pumpAt(Size size) async {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(wrap(WeeksScreen(
            childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
          await tester.pump();
        }

        addTearDown(() => tester.binding.setSurfaceSize(null));

        await pumpAt(const Size(1100, 1000));
        expect(tester.getSize(find.byType(ListView)).width, ff.comfortableReadingWidth);

        await pumpAt(const Size(344, 1400)); // Fold5 cover
        expect(tester.getSize(find.byType(ListView)).width, 344);

        await pumpAt(const Size(390, 1400)); // standard phone
        expect(tester.getSize(find.byType(ListView)).width, 390);
      });
    });
  });
}
