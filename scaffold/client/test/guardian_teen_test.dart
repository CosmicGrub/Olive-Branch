// OLIVE BRANCH — wave 2b: the grown-up's half (lib/guardian_teen_screens.dart): what they see of a teen and the 18
// handover note. Verifies the screens lay out at the four postures, show only what she shared WITH THIS grown-up, and
// never claim an ask was sent. UNVERIFIED until CI runs it.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_teen_screens.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/teen_logic.dart';
import 'package:olive_client/teen_store.dart';

class _PlainCipher implements StoreCipher {
  @override
  Future<Uint8List> seal(Uint8List plain, List<int> aad) async => plain;
  @override
  Future<Uint8List> open(Uint8List box, List<int> aad) async => box;
}

final DateTime now = DateTime(2026, 11, 9, 9);

/// Built inside each test (see teen_screens_test.dart for why).
TeenRepository newRepo() => TeenRepository(LocalServices(
        store: LocalStore(backend: MemoryStoreBackend(), cipher: _PlainCipher()),
        childId: 'c1', guardianId: 'g1', isLive: true, demoSeeds: false)
    .area('teen'));

Widget app(Widget home, double scale) => MaterialApp(
      builder: (BuildContext c, Widget? w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      home: home,
    );

void main() {
  for (final (double w, double h) in <(double, double)>[(344, 882), (390, 844), (600, 960), (800, 1280)]) {
    for (final double scale in <double>[1.0, 2.0]) {
      testWidgets('what a grown-up sees, at $w dp, ${scale}x', (WidgetTester t) async {
        await t.binding.setSurfaceSize(Size(w, h));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final TeenRepository repo = newRepo();
        await repo.addEvent(const TeenEvent(id: 'mine', year: 2026, month: 11, day: 9, title: 'Private thing'));
        await repo.addEvent(const TeenEvent(id: 'dads', year: 2026, month: 11, day: 9, title: 'Lesson', share: EventShare.with_(<String>{'dad'})));
        await t.pumpWidget(app(GuardianTeenSeesScreen(childName: 'Ivy', age: 15, guardianId: 'dad', repository: repo, clock: () => now), scale));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('guardianTeenSees')), findsOneWidget);
        expect(find.textContaining('Private thing'), findsNothing, reason: 'not shared with anyone');
        expect(find.byKey(const Key('askParked')), findsOneWidget, reason: 'honest that asks wait: the transport is not built');
        expect(find.textContaining('Ask sent'), findsNothing);
      });

      testWidgets('the 18 handover, theirs, at $w dp, ${scale}x', (WidgetTester t) async {
        await t.binding.setSurfaceSize(Size(w, h));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final TeenRepository repo = newRepo();
        await t.pumpWidget(app(GuardianHandoverScreen(childName: 'Ivy', guardianId: 'dad', monthDay: '12-09', repository: repo), scale));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('guardianHandover')), findsOneWidget);
        await t.pumpWidget(app(GuardianHandoverScreen(childName: 'Ivy', guardianId: 'dad', after: true, repository: repo), scale));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('guardianAfter18')), findsOneWidget);
      });
    }
  }
}
