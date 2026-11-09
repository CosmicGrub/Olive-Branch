// OLIVE BRANCH — the 5-7 and 8-12 homes at every posture that has produced an overflow bug before (#148):
// 344 dp (Fold cover), 390 dp (phone), 600 dp (7-inch tablet floor) and 800 dp (10-inch tablet), each at 1.0x and
// 2.0x text. No longer UNVERIFIED — verified by CI. For every size and both bands: the home, the More page, My people
// with its sheet, and the 'your home grows' page lay out without a RenderFlex overflow (takeException is null),
// nothing is clipped off the right edge, the Hero grows with the text instead of staying pinned, and at the Fold
// cover the home collapses to its one load-bearing tile plus ONE More tile that opens the whole home.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_home_growth.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/form_factors.dart' as ff;
import 'package:olive_client/grownup_labels.dart';

const FamilyPrincipal guardian = FamilyPrincipal(roleName: 'guardian', userId: 'g1');
const FamilyPrincipal childP = FamilyPrincipal(roleName: 'child', childId: 'c1');

Map<String, Object?> person(String id, String label, String role, String? home, List<String> contact) =>
    <String, Object?>{'id': id, 'label': label, 'role': role, 'homeId': home, 'contact': contact, 'away': null};

Future<FamilyChildSnapshot> snap(int years) async {
  final FamilyService s = FamilyService(MemoryFamilyStore(), clock: () => DateTime(2026, 11, 9, 9));
  Future<void> add(Map<String, Object?> op) => s.addChange(guardian, actorName: 'Dad', yearsOld: years, op: op, timing: Timing.now.toJson());
  await add(<String, Object?>{'op': 'put_home', 'home': <String, Object?>{'id': 'h1', 'name': "Mom's house", 'childSleeps': true}});
  await add(<String, Object?>{'op': 'put_home', 'home': <String, Object?>{'id': 'h2', 'name': "Dad's house", 'childSleeps': true}});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p1', 'Mom', 'guardian', 'h1', <String>['live_call', 'message'])});
  await add(<String, Object?>{'op': 'put_person', 'person': person('p2', 'Dad', 'guardian', 'h2', <String>['live_call', 'message'])});
  return s.childSnapshot(childP, childId: 'c1', yearsOld: years);
}

Widget app(Widget home, double scale, int years) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      builder: (BuildContext c, Widget? w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      home: GrownupLabelScope(labels: GrownupLabels(
          // "My weeks" waits for a family, so the posture child has one.
          contacts: const <GrownupContact>[
            GrownupContact(id: 'g1', guardianLabel: 'Mom', kind: GrownupKind.mom),
            GrownupContact(id: 'g2', guardianLabel: 'Dad', kind: GrownupKind.dad),
          ],
          age: AgeLockState(age: years, locked: true)), child: home),
    );

Future<void> size(WidgetTester t, double w, double h) async {
  await t.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

/// Nothing may sit past the right edge: every tile is inside the viewport.
void expectInside(WidgetTester t, Finder f, double w) {
  for (final Element e in f.evaluate()) {
    final Rect r = t.getRect(find.byElementPredicate((Element x) => x == e));
    expect(r.right, lessThanOrEqualTo(w + 0.5), reason: 'clipped past the right edge');
    expect(r.left, greaterThanOrEqualTo(-0.5));
  }
}

const List<(double, double, String)> kSizes = <(double, double, String)>[
  (344, 882, 'Fold cover 344'),
  (390, 844, 'phone 390 (also read as the cover by form_factors)'),
  (360, 640, 'ordinary phone 360'),
  (600, 960, '7-inch tablet 600'),
  (800, 1280, '10-inch tablet 800'),
];

bool _cover(double w, double h) => ff.postureFor(ff.Viewport(w: w, h: h)) == ff.Posture.foldCover;

void main() {
  for (final (int years, String band) in <(int, String)>[(6, 't57'), (10, 't812')]) {
    for (final (double w, double h, String name) in kSizes) {
      for (final double scale in <double>[1.0, 2.0]) {
        final String tag = '$band at $name dp, ${scale}x text';

        testWidgets('home: $tag', (WidgetTester t) async {
          await size(t, w, h);
          final FamilyChildSnapshot f = await snap(years);
          await t.pumpWidget(app(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 2,
              family: f, childAge: years, clock: () => DateTime(2026, 11, 9, 9)), scale, years));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'no overflow');
          expect(find.byKey(Key('bandHome.$band')), findsOneWidget);
          if (_cover(w, h)) {
            // Fold cover: the one load-bearing tile and ONE More tile.
            expect(find.byKey(const Key('bandCollapsedMore')), findsOneWidget);
            expect(find.byKey(const Key('childHomeFeaturedGrid')), findsNothing);
            expect(find.byKey(const Key('childHomeStandardGrid')), findsNothing);
            await t.tap(find.byKey(const Key('bandCollapsedMore')));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(find.byKey(const Key('childHomeFeaturedGrid')), findsOneWidget, reason: 'More opens the whole home');
            expect(find.byKey(const Key('childHomeStandardGrid')), findsOneWidget);
            expectInside(t, find.byKey(const Key('childHomeFeaturedGrid')), w);
          } else {
            expect(find.byKey(const Key('bandCollapsedMore')), findsNothing);
            expect(find.byKey(const Key('childHomeFeaturedGrid')), findsOneWidget);
            expect(find.byKey(const Key('childHomeStandardGrid')), findsOneWidget);
            expectInside(t, find.byKey(const Key('childHomeFeaturedGrid')), w);
            expectInside(t, find.byKey(const Key('childHomeStandardGrid')), w);
          }
        });

        testWidgets('hero grows with the text: $tag', (WidgetTester t) async {
          await size(t, w, h);
          final FamilyChildSnapshot f = await snap(years);
          await t.pumpWidget(app(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0,
              family: f, childAge: years, clock: () => DateTime(2026, 11, 9, 9)), scale, years));
          await t.pumpAndSettle();
          final Finder lead = band == 't57' ? find.byKey(const Key('childHomeHero')) : find.byKey(const Key('bandTile.weeks'));
          final double lh = t.getSize(lead).height;
          expect(lh, greaterThanOrEqualTo(band == 't57' ? 140.0 : 96.0), reason: 'never smaller than its base');
          if (scale > 1.0) expect(lh, greaterThan(band == 't57' ? 140.0 : 96.0), reason: 'grew with the text, not pinned');
        });

        testWidgets('More page, My people and its sheet: $tag', (WidgetTester t) async {
          await size(t, w, h);
          final FamilyChildSnapshot f = await snap(years);
          await t.pumpWidget(app(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0,
              family: f, childAge: years, nicknames: MemoryNicknameRepository(), clock: () => DateTime(2026, 11, 9, 9)), scale, years));
          await t.pumpAndSettle();
          if (_cover(w, h)) {
            await t.tap(find.byKey(const Key('bandCollapsedMore')));
            await t.pumpAndSettle();
          }
          // My people.
          await t.ensureVisible(find.byKey(const Key('childHomeMyPeople')));
          await t.tap(find.byKey(const Key('childHomeMyPeople')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await t.tap(find.byKey(const Key('person_p1')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byKey(const Key('personSheet')), findsOneWidget);
          await t.tap(find.byKey(const Key('personRename')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'the name bank lays out');
          await t.tap(find.byKey(const Key('bank_Mama')));
          await t.pumpAndSettle();
          await t.pageBack();
          await t.pumpAndSettle();
          // The More page.
          await t.ensureVisible(find.byKey(const Key('bandTile.more')));
          await t.tap(find.byKey(const Key('bandTile.more')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byKey(const Key('moreCaption')), findsOneWidget);
          expect(find.byKey(const Key('moreEverything')), findsOneWidget);
        });

        testWidgets('your home grows and its Later row: $tag', (WidgetTester t) async {
          await size(t, w, h);
          final FamilyChildSnapshot f = await snap(years);
          final ChildGrowth g = ChildGrowth();
          await g.observe(years == 6 ? 4 : 7);
          await g.observe(years == 6 ? 5 : 8);
          await t.pumpWidget(app(ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: null, unreadCount: 0,
              family: f, childAge: years, growth: g, clock: () => DateTime(2026, 11, 9, 9)), scale, years));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byKey(const Key('growPage')), findsOneWidget);
          await t.ensureVisible(find.byKey(const Key('growLater')));
          await t.tap(find.byKey(const Key('growLater')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byKey(const Key('growLaterCard')), findsOneWidget);
          expectInside(t, find.byKey(const Key('growLaterCard')), w);
        });
      }
    }
  }
}
