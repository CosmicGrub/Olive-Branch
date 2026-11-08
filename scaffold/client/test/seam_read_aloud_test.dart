// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — the
// SEAM(child-accessibility) read-aloud callbacks of the Rhythm screens (and the
// picture-story pager) are filled by the app's read-aloud when none is passed,
// gated by the guardian's switch. MASTERFILE §8.21.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/child_explainer_screens.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/read_aloud.dart';
import 'package:olive_client/rhythm_screens.dart';

import 'rhythm_screens_test.dart' show seeded;
import 'rv_support.dart';

class _Engine implements ReadAloudEngine {
  final List<String> spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

Future<Widget> scoped(Widget w, ReadAloudEngine e, {AccessSettings s = AccessSettings.defaults}) async {
  final AccessController c = AccessController(repository: MemoryAccessRepository(s));
  await c.load();
  return AccessScope(controller: c, child: ReadAloudScope(controller: ReadAloudController(engine: e), child: w));
}

void main() {
  testWidgets('a routine tile reads its name through the app read-aloud, only when tapped', (WidgetTester t) async {
    await phone(t);
    final _Engine e = _Engine();
    await t.pumpWidget(app(await scoped(MyRoutineScreen(service: await seeded()), e)));
    await t.pumpAndSettle();
    expect(e.spoken, isEmpty);
    await t.tap(find.byIcon(Icons.volume_up_outlined).first);
    expect(e.spoken, <String>['Bath']);
  });

  testWidgets('guardian turned read-aloud off: the tiles show no speaker', (WidgetTester t) async {
    await phone(t);
    await t.pumpWidget(app(await scoped(MyRoutineScreen(service: await seeded()), _Engine(),
        s: const AccessSettings(readAloud: false))));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  testWidgets('first-then and packing buddy get the same fallback', (WidgetTester t) async {
    await phone(t);
    final _Engine e = _Engine();
    await t.pumpWidget(app(await scoped(FirstThenScreen(service: await seeded()), e)));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up_outlined), findsWidgets);
    await t.pumpWidget(app(await scoped(PackingBuddyScreen(service: await seeded()), e)));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up_outlined), findsWidgets);
  });

  testWidgets('picture stories: the pager reads the page text through the scope, and roomier reading spaces it',
      (WidgetTester t) async {
    await phone(t);
    final _Engine e = _Engine();
    const ExplainerStory story = ExplainerStory(
        id: 's1', title: 'The new school', pages: <String>['We go in the gate.', 'We hang up our coats.'],
        updatedOn: '2026-11-07', shownToHer: true);
    await t.pumpWidget(app(await scoped(const ExplainerPagerScreen(story: story), e,
        s: const AccessSettings(roomierReading: true))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('readAloud')));
    expect(e.spoken, <String>['We go in the gate.']);
    final Text txt = t.widget<Text>(find.byKey(const Key('storyText')));
    expect(txt.style!.letterSpacing, greaterThan(0));
    expect(txt.textAlign, TextAlign.start);
  });
}
