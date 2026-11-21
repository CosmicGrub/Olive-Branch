// OLIVE BRANCH — the guided first run's logic: the registry (order, slots, the delta for an older install, a missing or off
// feature skipped with no gap), the engine (the five controls), and the progress record (hostile documents, a failing
// store). Pure Dart; verified by CI, headless. MASTERFILE §8.5.13.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guided_engine.dart';
import 'package:olive_client/guided_progress.dart';
import 'package:olive_client/guided_registry.dart';
import 'package:olive_client/guided_script.dart';
import 'package:olive_client/local_services.dart';

GuidedEntry _stop(String id, {int since = 2, String slot = 'adult.tour.features', String? needs, bool whatsNew = true}) =>
    GuidedEntry(
      id: id, half: GuidedHalf.adult, slot: slot, kind: GuidedKind.coach, phase: 'tour', since: since,
      needsFeature: needs, whatsNew: whatsNew, anchor: 'home.$id', title: 'T $id', words: 'W $id',
      labels: <GuidedLabel>[GuidedLabel(Icons.star, 'L $id', 'line')],
    );

GuidedEntry _childLabel(String id, {int since = 2, String? needs}) => GuidedEntry(
      id: id, half: GuidedHalf.child, slot: 'child.extra', kind: GuidedKind.childLabel, since: since,
      needsFeature: needs, whatsNew: true, title: id, words: '',
      labels: <GuidedLabel>[GuidedLabel(Icons.brush, 'Label $id', 'a line')],
    );

List<String> _ids(List<GuidedEntry> l) => l.map((GuidedEntry e) => e.id).toList();

void main() {
  group('the registry', () {
    test('version 1 with nothing registered: the whole script, in slot order, welcome first and done last', () {
      final List<GuidedEntry> a = resolveGuidedEntries(half: GuidedHalf.adult);
      expect(a.first.id, 'a.welcome');
      expect(a.last.id, 'a.done');
      expect(_ids(a).indexOf('a.pin'), lessThan(_ids(a).indexOf('a.tablet')));
      expect(_ids(a).indexOf('a.tour.call'), lessThan(_ids(a).indexOf('a.tour.more')));
      final List<GuidedEntry> c = resolveGuidedEntries(half: GuidedHalf.child);
      expect(c.last.id, 'c.done');
      expect(_ids(c), isNot(contains('c.extra')), reason: 'no registered icon, no extra card, no gap');
    });

    test('a new registered stop appears in its slot, between Call and More, in registration order', () {
      final List<GuidedEntry> a = resolveGuidedEntries(
          half: GuidedHalf.adult, scriptVersion: 2, registered: <GuidedEntry>[_stop('diary'), _stop('garden')]);
      final List<String> ids = _ids(a);
      expect(ids.indexOf('a.tour.call') + 1, ids.indexOf('diary'));
      expect(ids.indexOf('diary') + 1, ids.indexOf('garden'));
      expect(ids.indexOf('garden') + 1, ids.indexOf('a.tour.more'));
    });

    test('the strip renumbers: a new tour stop shares the tour step, so a missing feature leaves no gap', () {
      final List<GuidedEntry> without = resolveGuidedEntries(half: GuidedHalf.adult);
      final List<GuidedEntry> with_ = resolveGuidedEntries(
          half: GuidedHalf.adult, scriptVersion: 2, features: <String>{'diary'},
          registered: <GuidedEntry>[_stop('diary', needs: 'diary')]);
      expect(guidedStrip(without, 0).of, 9);
      expect(guidedStrip(with_, 0).of, 9, reason: 'a tour stop joins the tour step; the strip is still nine');
      final int i = _ids(with_).indexOf('a.help');
      expect(guidedStrip(with_, i), (step: 8, of: 9));
    });

    test('a feature that is off or missing skips its entry: no empty card and no gap in the order', () {
      final List<GuidedEntry> reg = <GuidedEntry>[_stop('diary', needs: 'diary'), _stop('garden')];
      final List<String> off = _ids(resolveGuidedEntries(half: GuidedHalf.adult, scriptVersion: 2, registered: reg));
      expect(off, isNot(contains('diary')));
      expect(off.indexOf('garden') + 1, off.indexOf('a.tour.more'), reason: 'the next entry closes up');
      final List<String> on = _ids(resolveGuidedEntries(
          half: GuidedHalf.adult, scriptVersion: 2, features: <String>{'diary'}, registered: reg));
      expect(on, contains('diary'));
    });

    test('an entry from a script version this build does not know is ignored; so is one in an unknown slot', () {
      final List<String> ids = _ids(resolveGuidedEntries(
          half: GuidedHalf.adult,
          registered: <GuidedEntry>[_stop('future', since: 3), _stop('lost', since: 1, slot: 'adult.nowhere')]));
      expect(ids, isNot(contains('future')));
      expect(ids, isNot(contains('lost')));
    });

    test('an older install (it saw version 1) is shown only the delta, in order', () {
      final List<GuidedEntry> reg = <GuidedEntry>[
        _stop('diary', since: 2),
        _stop('garden', since: 2),
        _stop('quiet', since: 2, whatsNew: false),
        _stop('old', since: 1),
      ];
      final List<String> delta = _ids(resolveGuidedEntries(half: GuidedHalf.adult, scriptVersion: 2, seenVersion: 1, registered: reg));
      expect(delta, <String>['diary', 'garden'], reason: 'only newer than 1 and marked for the mini-tour');
      expect(_ids(resolveGuidedEntries(half: GuidedHalf.adult, scriptVersion: 2, seenVersion: 2, registered: reg)), isEmpty,
          reason: 'an install that has seen version 2 sees nothing');
      expect(_ids(resolveGuidedEntries(half: GuidedHalf.adult, seenVersion: 1)), isEmpty,
          reason: 'version 1, nothing registered: nothing to show an existing install');
    });

    test('her icon labels: registered labels make the "And there is more" card, in order; none, no card', () {
      final List<GuidedEntry> reg = <GuidedEntry>[_childLabel('a'), _childLabel('b', needs: 'b')];
      final List<GuidedEntry> one = resolveGuidedEntries(half: GuidedHalf.child, scriptVersion: 2, registered: reg);
      expect(one.firstWhere((GuidedEntry e) => e.id == 'c.extra').labels.map((GuidedLabel l) => l.label), <String>['Label a']);
      final List<GuidedEntry> two = resolveGuidedEntries(half: GuidedHalf.child, scriptVersion: 2, features: <String>{'b'}, registered: reg);
      expect(two.firstWhere((GuidedEntry e) => e.id == 'c.extra').labels.map((GuidedLabel l) => l.label), <String>['Label a', 'Label b']);
      final List<String> ids = _ids(two);
      expect(ids.indexOf('c.more') + 1, ids.indexOf('c.extra'));
      expect(ids.indexOf('c.extra') + 1, ids.indexOf('c.done'));
      // Her delta is just that card.
      final List<GuidedEntry> delta = resolveGuidedEntries(half: GuidedHalf.child, scriptVersion: 2, seenVersion: 1, registered: reg);
      expect(_ids(delta), <String>['c.extra']);
    });

    test('order is stable: same-slot entries keep the order they were registered in', () {
      final List<GuidedEntry> reg = <GuidedEntry>[for (final String n in <String>['z', 'a', 'm', 'b']) _stop(n)];
      final List<String> ids = _ids(resolveGuidedEntries(half: GuidedHalf.adult, scriptVersion: 2, registered: reg));
      final int i = ids.indexOf('z');
      expect(ids.sublist(i, i + 4), <String>['z', 'a', 'm', 'b']);
    });
  });

  group('the engine', () {
    late MemoryGuidedProgressStore store;
    late List<GuidedEntry> steps;
    setUp(() {
      store = MemoryGuidedProgressStore();
      steps = resolveGuidedEntries(half: GuidedHalf.adult);
    });

    GuidedController make({int at = 0}) =>
        GuidedController(half: GuidedHalf.adult, steps: steps, store: store, startIndex: at);

    test('nothing advances by itself: a new controller stays where it starts', () async {
      final GuidedController c = make();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.current.id, 'a.welcome');
      expect(c.finished, isFalse);
    });

    test('next saves the step name FIRST and then moves; back goes back, and never past the first', () async {
      final GuidedController c = make();
      await c.next();
      expect(c.current.id, 'a.you');
      expect((await store.load()).adultStep, 'a.you');
      await c.back();
      expect(c.current.id, 'a.welcome');
      expect(c.canBack, isFalse);
      await c.back();
      expect(c.current.id, 'a.welcome');
    });

    test('a form cannot be skipped; "Do this later" on a form is "I need a minute"', () async {
      final GuidedController c = make(at: steps.indexWhere((GuidedEntry e) => e.id == 'a.pin'));
      expect(c.canSkip, isFalse);
      await c.skip();
      expect(c.current.id, 'a.pin');
      await c.later();
      expect(c.paused, isTrue);
      expect(c.current.id, 'a.pin');
      expect(c.progress.deferred, isEmpty, reason: 'a needed answer is never "left for later"');
      await c.resume();
      expect(c.paused, isFalse);
      expect(c.current.id, 'a.pin', reason: 'back to the same step');
    });

    test('Skip this part on a tour stop jumps past the whole tour; Later also remembers the part', () async {
      final GuidedController s = make(at: steps.indexWhere((GuidedEntry e) => e.id == 'a.tour.guard'));
      await s.skip();
      expect(s.current.id, 'a.help');
      expect(s.progress.deferred, isEmpty);
      final GuidedController l = make(at: steps.indexWhere((GuidedEntry e) => e.id == 'a.tablet'));
      await l.later();
      expect(l.current.id, 'a.tour.bank');
      expect(l.progress.deferred, <String>['tablet']);
      await l.partDone('tablet');
      expect(l.progress.deferred, isEmpty);
    });

    test('the last screen cannot be skipped or left for later; Next finishes and records the version seen', () async {
      final GuidedController c = make(at: steps.length - 1);
      expect(c.canSkip, isFalse);
      expect(c.canLater, isFalse);
      await c.next();
      expect(c.finished, isTrue);
      final GuidedProgress p = await store.load();
      expect(p.adultDone, isTrue);
      expect(p.seenVersion, kGuidedScriptVersion);
    });

    test('a pause saves the place, so a killed app resumes there', () async {
      final GuidedController c = make(at: steps.indexWhere((GuidedEntry e) => e.id == 'a.tour.care'));
      await c.pause();
      expect(c.paused, isTrue);
      final GuidedProgress p = await store.load();
      expect(p.adultStep, 'a.tour.care');
      expect(GuidedController.resumeIndex(steps, p.adultStep), steps.indexWhere((GuidedEntry e) => e.id == 'a.tour.care'));
      expect(GuidedController.resumeIndex(steps, 'gone.step'), 0, reason: 'an unknown saved step starts again, never crashes');
      expect(GuidedController.resumeIndex(steps, null), 0);
    });

    test('a store that cannot be written never traps anyone: the run carries on', () async {
      store.failWrites = true;
      final GuidedController c = make();
      await c.next();
      await c.next();
      expect(c.current.id, 'a.her');
    });

    test('a mini-tour never moves the first-run step', () async {
      store = MemoryGuidedProgressStore(const GuidedProgress(seenVersion: 1, adultStep: 'a.done', adultDone: true));
      final GuidedController c = GuidedController(
          half: GuidedHalf.adult,
          steps: <GuidedEntry>[_stop('x'), _stop('y')],
          store: store,
          progress: await store.load(),
          mini: true);
      await c.next();
      expect((await store.load()).adultStep, 'a.done');
      await c.finish();
      expect((await store.load()).seenVersion, kGuidedScriptVersion);
    });

    test('her half: progress goes in progress, then done', () async {
      final List<GuidedEntry> cards = resolveGuidedEntries(half: GuidedHalf.child).where((GuidedEntry e) => e.id.startsWith('c.') && e.id != 'c.offer' && e.id != 'c.start').toList();
      final GuidedController c = GuidedController(half: GuidedHalf.child, steps: cards, store: store);
      await c.next();
      expect((await store.load()).child, ChildWelcomeState.inProgress);
      await c.finish();
      expect((await store.load()).child, ChildWelcomeState.done);
    });
  });

  group('the progress record', () {
    test('round-trips, and holds no name, age or PIN: only step names and marks', () {
      const GuidedProgress p = GuidedProgress(
          seenVersion: 1, adultStep: 'a.tour.care', adultDone: false, deferred: <String>['tablet'],
          child: ChildWelcomeState.inProgress, childStep: 'c.day');
      final GuidedProgress back = GuidedProgress.fromJson(p.toJson());
      expect(back.adultStep, 'a.tour.care');
      expect(back.deferred, <String>['tablet']);
      expect(back.child, ChildWelcomeState.inProgress);
      expect(back.childStep, 'c.day');
      expect(p.toJson().keys.toSet(), <String>{'v', 'seen', 'aStep', 'aDone', 'later', 'child', 'cStep'});
    });

    test('hostile documents are "no record", never a crash or a trap', () {
      for (final Object? bad in <Object?>[
        null, 'x', 5, <Object?>[], <String, Object?>{'seen': 'one'}, <String, Object?>{'seen': -5, 'later': 'x'},
        <String, Object?>{'aStep': 'x' * 5000, 'cStep': 7, 'child': 'weird', 'later': <Object?>[1, null, 'ok']},
      ]) {
        final GuidedProgress p = GuidedProgress.fromJson(bad);
        expect(p.seenVersion, 0);
        expect(p.adultStep, isNull);
        expect(p.child, ChildWelcomeState.none);
        expect(p.deferred.length, lessThanOrEqualTo(1));
      }
      expect(GuidedProgress.fromJson(<String, Object?>{'later': List<String>.filled(100, 'p')}).deferred.length, 16);
    });

    test('an install with no record at all is not "in" the guided run', () {
      expect(const GuidedProgress().exists, isFalse);
      expect(const GuidedProgress(seenVersion: 1).exists, isTrue);
    });

    test('the area is catalogued, device-scoped and sealed, and the local store keeps and re-reads it', () async {
      final LocalDataEntry e = localDataEntry('guidedtour');
      expect(e.scope, LocalScope.device);
      expect(e.encrypted, isTrue);
      expect(e.what, contains('Never a name, an age, a PIN'));
      final LocalServices s = LocalServices.memory(childId: 'c-test', guardianId: 'g-test', isLive: false, demoSeeds: false);
      final LocalGuidedProgressStore a = LocalGuidedProgressStore(s.area('guidedtour'));
      await a.save(const GuidedProgress(seenVersion: 1, adultStep: 'a.help'));
      final GuidedProgress back = await LocalGuidedProgressStore(s.area('guidedtour')).load();
      expect(back.adultStep, 'a.help');
    });
  });
}
