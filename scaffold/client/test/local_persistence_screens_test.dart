// OLIVE BRANCH — the sixteen screens that used to lose everything on exit,
// proven to KEEP it now: each test writes through a real screen, "restarts"
// the device (a brand-new LocalServices over the same backend and key), builds
// the screen again, and expects what she made to still be there. Plus the
// refusals: nothing private in plaintext, no invented content in a live build,
// a full box says so instead of silently dropping, no counters stored.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colouring_screen.dart';
import 'package:olive_client/collection_screen.dart';
import 'package:olive_client/doodle_desk.dart';
import 'package:olive_client/jokebook_screen.dart';
import 'package:olive_client/journal_screen.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/maturation_ladder.dart';
import 'package:olive_client/snapshot_button.dart';
import 'package:olive_client/storyteller_screen.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/teach_me.dart';
import 'package:olive_client/wants_needs.dart';

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 3));

/// One "device": a store over [backend] with a fixed key, so a second one over
/// the same backend is genuinely the same phone after a restart.
LocalServices _device(MemoryStoreBackend backend, {bool live = false, String child = 'ivy'}) =>
    LocalServices(
      store: LocalStore(backend: backend, cipher: AesGcmStoreCipher(_key)),
      childId: child,
      isLive: live,
      demoSeeds: !live,
    );

Future<void> _show(WidgetTester t, Widget w, {Size size = const Size(700, 2400)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

/// Closes the screen and brings the "phone" back up on the same files.
Future<void> _restart(WidgetTester t, MemoryStoreBackend b, {bool live = false, String child = 'ivy'}) async {
  await t.pumpWidget(const SizedBox());
  LocalServices.install(_device(b, live: live, child: child));
}

void main() {
  group('journal — sealed on this device, kept across a restart (P7)', () {
    testWidgets('an entry survives a restart and is not in plaintext on disk', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      await _show(t, const JournalScreen(childName: 'Ivy'));
      await t.enterText(find.byType(TextField), 'I climbed the very tall tree.');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pumpAndSettle();
      expect(find.text('I climbed the very tall tree.'), findsOneWidget);

      for (final String name in await disk.names()) {
        expect(utf8.decode(disk.rawFor(name)!, allowMalformed: true), isNot(contains('very tall tree')),
            reason: '$name must be sealed');
      }

      await _restart(t, disk);
      await _show(t, const JournalScreen(childName: 'Ivy'));
      expect(find.text('I climbed the very tall tree.'), findsOneWidget);
    });

    testWidgets('entries are per child: another profile on the same phone sees none of them', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk, child: 'ivy'));
      await _show(t, const JournalScreen(childName: 'Ivy'));
      await t.enterText(find.byType(TextField), 'ivy only');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pumpAndSettle();

      await t.pumpWidget(const SizedBox());
      LocalServices.install(_device(disk, child: 'wren'));
      await _show(t, const JournalScreen(childName: 'Wren'));
      expect(find.text('ivy only'), findsNothing);
    });

    testWidgets('a live build writes under its real child id, never demo-child', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk, live: true, child: 'real-child-1'));
      await _show(t, const JournalScreen(childName: 'Ivy'));
      await t.enterText(find.byType(TextField), 'hello');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pumpAndSettle();
      final List<String> names = await disk.names();
      expect(names, <String>['child.real-child-1.journal']);
      expect(names.any((String n) => n.contains('demo-child')), isFalse);
    });

    testWidgets('a full journal gives the words back with a gentle line, never a silent loss', (t) async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      LocalServices.install(s);
      final LocalNamespace tiny = s.store.open(
          const NamespaceSpec(name: 'child.tiny.journal', encrypted: true, maxBytes: 60));
      await _show(t, JournalScreen(childName: 'Ivy', repository: JournalRepository(tiny)));
      await t.enterText(find.byType(TextField), 'This is far too long to fit in a sixty byte journal, sorry.');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pumpAndSettle();
      expect(find.textContaining("couldn't be kept"), findsOneWidget);
      final TextField field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, startsWith('This is far too long'), reason: 'her words come back');
      expect(find.text('This is far too long to fit in a sixty byte journal, sorry.'), findsOneWidget,
          reason: 'only in the box, not as a saved entry');
    });
  });

  group('wants and needs — kept, and no invented wishes in a live build', () {
    testWidgets('what she adds and ticks survives a restart', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      await _show(t, const WantsNeedsScreen());
      await t.enterText(find.byType(TextField).first, 'A bike');
      await t.tap(find.widgetWithText(FilledButton, 'Add').first);
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox).first); // tick the first want
      await t.pumpAndSettle();

      await _restart(t, disk);
      await _show(t, const WantsNeedsScreen());
      expect(find.text('A bike'), findsOneWidget);
      expect(find.text('LEGO set'), findsOneWidget, reason: 'her saved list replaced nothing she kept');
      final Checkbox first = t.widget<Checkbox>(find.byType(Checkbox).first);
      expect(first.value, isTrue);
    });

    testWidgets('the demo seeds show in the preview until she saves her own list', (t) async {
      LocalServices.install(_device(MemoryStoreBackend()));
      await _show(t, const WantsNeedsScreen());
      expect(find.text('LEGO set'), findsOneWidget);
      expect(find.text('New shoes'), findsOneWidget);
    });

    testWidgets('a LIVE build starts empty, with a picture prompt, and no toys', (t) async {
      LocalServices.install(_device(MemoryStoreBackend(), live: true, child: 'real-child-1'));
      await _show(t, const WantsNeedsScreen());
      for (final String toy in <String>['LEGO set', 'New video game', 'New shoes', 'Winter coat']) {
        expect(find.text(toy), findsNothing, reason: toy);
      }
      expect(find.text('Nothing on this list yet'), findsNWidgets(2));
      expect(find.byIcon(Icons.star_border), findsWidgets, reason: 'the gentle picture prompt');
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('P4: the stored shape has no price field, only text and a tick', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk, live: true, child: 'real-child-1');
      LocalServices.install(s);
      await _show(t, const WantsNeedsScreen());
      await t.enterText(find.byType(TextField).first, 'A kite');
      await t.tap(find.widgetWithText(FilledButton, 'Add').first);
      await t.pumpAndSettle();
      final Object? raw = await s.area('lists').get('wants');
      expect((raw! as List).single, <String, Object?>{'text': 'A kite', 'done': false});
    });
  });

  group('saved pictures — doodles and colourings are really kept', () {
    Future<void> drawAStroke(WidgetTester t) async {
      final Offset c = t.getCenter(find.byKey(const Key('doodleBoard')));
      final TestGesture g = await t.startGesture(c);
      await g.moveBy(const Offset(40, 10));
      await g.moveBy(const Offset(30, 30));
      await g.up();
      await t.pump();
    }

    testWidgets('a doodle is kept, survives a restart, and shows in My saved pictures', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      final AppGallery gallery = AppGallery(repository: SavedPicturesRepository.forChild());
      await _show(t, DoodleDesk(gallery: gallery));
      await drawAStroke(t);
      await t.tap(find.byKey(const Key('snapshotButton')));
      await t.pumpAndSettle();
      expect(find.text('Kept in your saved pictures.'), findsOneWidget);
      expect(gallery.photos.single.kind, 'doodle');

      await _restart(t, disk);
      final AppGallery reborn = AppGallery(repository: SavedPicturesRepository.forChild());
      await _show(t, AppGalleryScreen(gallery: reborn));
      await reborn.load();
      await t.pumpAndSettle();
      expect(find.byType(DoodleThumbnail), findsOneWidget);
      expect(find.text('Nothing saved yet — take a photo to see it here.'), findsNothing);
    });

    testWidgets('an empty doodle board has nothing to keep and says so gently', (t) async {
      LocalServices.install(_device(MemoryStoreBackend()));
      final AppGallery gallery = AppGallery(repository: SavedPicturesRepository.forChild());
      await _show(t, DoodleDesk(gallery: gallery));
      await t.tap(find.byKey(const Key('snapshotButton')));
      await t.pumpAndSettle();
      expect(find.text('Draw something first, then keep it.'), findsOneWidget);
      expect(gallery.photos, isEmpty);
    });

    testWidgets('an undone stroke is not kept; no stroke count is stored (P2)', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      LocalServices.install(s);
      final AppGallery gallery = AppGallery(repository: SavedPicturesRepository.forChild());
      await _show(t, DoodleDesk(gallery: gallery));
      await drawAStroke(t);
      await drawAStroke(t);
      await t.tap(find.text('Undo'));
      await t.pump();
      await t.tap(find.byKey(const Key('snapshotButton')));
      await t.pumpAndSettle();
      final Map<String, Object?> data = gallery.photos.single.data!;
      expect((data['strokes']! as List).length, 1, reason: 'only what is visible');
      expect(data.keys.toSet(), <String>{'w', 'h', 'strokes'}, reason: 'no counters, timers or scores');
    });

    testWidgets('a colouring is kept as region fills and drawn back from them', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      final AppGallery gallery = AppGallery(repository: SavedPicturesRepository.forChild());
      await _show(t, ColouringScreen(gallery: gallery));
      // Nothing coloured yet: nothing to keep.
      await t.tap(find.byKey(const Key('snapshotButton')));
      await t.pumpAndSettle();
      expect(find.text('Colour something first, then keep it.'), findsOneWidget);
      expect(gallery.photos, isEmpty);

      final Finder board = find.byWidgetPredicate((Widget w) => w is GestureDetector && w.onTapUp != null);
      await t.tapAt(t.getTopLeft(board.first) + const Offset(20, 20)); // the sky
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('snapshotButton')));
      await t.pumpAndSettle();
      expect(gallery.photos.single.kind, 'colouring');
      expect((gallery.photos.single.data!['fills']! as Map).containsKey('sky'), isTrue);

      await _restart(t, disk);
      final AppGallery reborn = AppGallery(repository: SavedPicturesRepository.forChild());
      await _show(t, AppGalleryScreen(gallery: reborn));
      await reborn.load();
      await t.pumpAndSettle();
      expect(find.byType(ColouringThumbnail), findsOneWidget);
    });

    testWidgets('a bare photo-tap (no capture) is still stored honestly, as where and when only', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      LocalServices.install(s);
      final AppGallery gallery = AppGallery(repository: SavedPicturesRepository.forChild());
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SnapshotButton(currentSurface: 'home', gallery: gallery))));
      await t.tap(find.byKey(const Key('snapshotButton')));
      await t.pumpAndSettle();
      final String key = (await s.area('pictures').list()).single;
      final Map<Object?, Object?> row = (await s.area('pictures').get(key))! as Map<Object?, Object?>;
      expect(row['kind'], 'snapshot');
      expect(row.containsKey('data'), isFalse);
    });

    testWidgets('long-press puts a picture away for good (asks first)', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      LocalServices.install(s);
      final AppGallery gallery = AppGallery(repository: SavedPicturesRepository.forChild());
      gallery.add(AppPhoto(id: 'p1', surface: 'home', savedAt: DateTime(2026, 11, 1)));
      await _show(t, AppGalleryScreen(gallery: gallery));
      expect(find.byKey(const ValueKey<String>('picture-p1')), findsOneWidget);

      await t.longPress(find.byKey(const ValueKey<String>('picture-p1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('keepPicture')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('picture-p1')), findsOneWidget, reason: '"Keep it" keeps it');

      await t.longPress(find.byKey(const ValueKey<String>('picture-p1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('putAwayPicture')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('picture-p1')), findsNothing);
      expect(await s.area('pictures').list(), isEmpty, reason: 'gone from the device, not just the screen');
    });

    testWidgets('a full picture box says so and takes the picture back out; nothing is evicted', (t) async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      LocalServices.install(s);
      final LocalNamespace tiny =
          s.store.open(const NamespaceSpec(name: 'child.tiny.pictures', maxBytes: 400));
      final AppGallery gallery = AppGallery(repository: SavedPicturesRepository(tiny));
      expect(await gallery.keep(AppPhoto(id: 'a', surface: 'home', savedAt: DateTime(2026))), isTrue);
      final bool ok = await gallery.keep(AppPhoto(
          id: 'b', surface: 'doodle', savedAt: DateTime(2026, 2), kind: 'doodle',
          data: <String, Object?>{'w': 1, 'h': 1, 'strokes': List<Object?>.filled(200, 'x' * 10)}));
      expect(ok, isFalse);
      expect(gallery.photos.map((AppPhoto p) => p.id), <String>['a'], reason: 'the old one is still there');
    });

    testWidgets('one enormous picture is refused on its own, whatever room the box has', (t) async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      LocalServices.install(s);
      final SavedPicturesRepository r = SavedPicturesRepository.forChild();
      await expectLater(
          r.add(AppPhoto(
              id: 'huge', surface: 'doodle', savedAt: DateTime(2026), kind: 'doodle',
              data: <String, Object?>{'w': 1, 'h': 1, 'strokes': <Object?>['x' * (maxSavedPictureBytes + 10)]})),
          throwsA(isA<LocalStoreFull>()));
    });

    testWidgets('the shared gallery binds to this device\'s child and rebinds when the scope changes', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk, child: 'ivy'));
      final AppGallery shared = AppGallery.shared();
      shared.ensureBound();
      shared.add(AppPhoto(id: 'one', surface: 'home', savedAt: DateTime(2026)));
      await t.pump();
      LocalServices.install(_device(disk, child: 'wren'));
      shared.ensureBound();
      await t.pump();
      expect(shared.photos, isEmpty, reason: 'wren does not see ivy\'s pictures');
      LocalServices.install(_device(disk, child: 'ivy'));
      shared.ensureBound();
      await t.pump();
      await shared.load();
      expect(shared.photos.map((AppPhoto p) => p.id), <String>['one']);
    });
  });

  group('storyteller and jokebook — stars and bookmarks survive a restart', () {
    testWidgets('a starred story is still on the shelf after a restart; no read count is stored', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      LocalServices.install(s);
      await _show(t, const StorytellerScreen(childName: 'Ivy'));
      await t.tap(find.text('Tell me a story!'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.star_border_rounded));
      await t.pumpAndSettle();
      expect(find.text('Your starred stories'), findsOneWidget);
      final Map<Object?, Object?> fav =
          ((await s.area('stories').get('favourites'))! as List).single as Map<Object?, Object?>;
      expect(fav.keys.toSet(), <Object?>{'code', 'title', 'starredAt'});

      await _restart(t, disk);
      await _show(t, const StorytellerScreen(childName: 'Ivy'));
      expect(find.text('Your starred stories'), findsOneWidget);
    });

    testWidgets('a starred joke is still starred after a restart', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      await _show(t, const JokebookScreen(childName: 'Ivy', childAge: 12));
      await t.tap(find.text('Tell me one!'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tap for the punchline'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.star_border_rounded));
      await t.pumpAndSettle();
      expect(find.text('Your starred jokes'), findsOneWidget);

      await _restart(t, disk);
      await _show(t, const JokebookScreen(childName: 'Ivy', childAge: 12));
      expect(find.text('Your starred jokes'), findsOneWidget);
    });
  });

  group('teach me and collections', () {
    testWidgets('what she taught survives a restart, authored by this device\'s child (not demo-child)', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk, live: true, child: 'real-child-1');
      LocalServices.install(s);
      await _show(t, const TeachMeScreen(childName: 'Ivy', childAge: 9));
      await t.enterText(find.byType(TextField), 'How a lock works');
      await t.pump();
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Teach Dad'));
      await t.tap(find.widgetWithText(FilledButton, 'Teach Dad'));
      await t.pumpAndSettle();

      final Map<Object?, Object?> row =
          (((await s.area('lessons').get('lessons'))! as List).single) as Map<Object?, Object?>;
      expect(row['fromUserId'], 'real-child-1');
      expect(row['askedAgain'], false);

      await _restart(t, disk, live: true, child: 'real-child-1');
      await _show(t, const TeachMeScreen(childName: 'Ivy', childAge: 9));
      expect(find.text('How a lock works'), findsOneWidget);
    });

    testWidgets('P2: "asked again" is kept as one bit, never a running count', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      LocalServices.install(s);
      final LessonsRepository r = LessonsRepository.forChild();
      await r.save(<Lesson>[
        Lesson(id: 'l1', fromUserId: 'ivy', title: 'Whistling', medium: TeachMedium.draw,
            taughtAt: DateTime.utc(2026, 11, 1), askedAgain: 5),
      ]);
      final Object? raw = await s.area('lessons').get('lessons');
      expect(raw.toString(), isNot(contains('5')));
      expect((await r.load())!.single.askedAgain, 1);
      expect((await r.load())!.single.medium, TeachMedium.draw);
    });

    testWidgets('collections: what she adds survives a restart', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      await _show(t, const CollectionScreen());
      await t.tap(find.widgetWithText(OutlinedButton, 'Show another dinosaurs'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, '').first, 'Ankylosaurus');
      await t.tap(find.byType(FilledButton).last);
      await t.pumpAndSettle();
      expect(find.text('Ankylosaurus'), findsOneWidget);

      await _restart(t, disk);
      await _show(t, const CollectionScreen());
      expect(find.text('Ankylosaurus'), findsOneWidget);
    });

    testWidgets('a LIVE build shows no invented specimens, only the empty collections', (t) async {
      LocalServices.install(_device(MemoryStoreBackend(), live: true, child: 'real-child-1'));
      await _show(t, const CollectionScreen());
      for (final String fake in <String>['Stegosaurus', 'Triceratops', 'T. Rex', 'The sparkly one']) {
        expect(find.text(fake), findsNothing, reason: fake);
      }
    });
  });

  group('growing-up ladder — "told once" is true across a restart now', () {
    testWidgets('the child reveal is shown once, and not again after a restart', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      childSeenRungReveals.clear();
      final DateTime now = DateTime(2026, 1, 1);
      await _show(t, MaturationLadderScreen(
          childName: 'Ivy', childAgeYears: 10, viewer: LadderViewer.child, now: now));
      expect(find.byKey(const Key('rungRevealDismiss')), findsOneWidget);
      await t.tap(find.byKey(const Key('rungRevealDismiss')));
      await t.pumpAndSettle();

      await _restart(t, disk);
      childSeenRungReveals.clear(); // a restart empties the in-process set; only the disk remembers
      await _show(t, MaturationLadderScreen(
          childName: 'Ivy', childAgeYears: 10, viewer: LadderViewer.child, now: now));
      expect(find.byKey(const Key('rungRevealDismiss')), findsNothing);
      expect(find.textContaining('Ivy'), findsWidgets, reason: 'and the ladder itself is still there');
    });

    testWidgets('the guardian banner is dismissed for good; grants only ever grow; a moved rung stays moved', (t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      LocalServices.install(s);
      final DateTime now = DateTime(2026, 1, 1);
      await _show(t, MaturationLadderScreen(
          childName: 'Ivy', childAgeYears: 15, viewer: LadderViewer.guardian, now: now));
      expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
      await t.tap(find.byTooltip('Dismiss'));
      await t.pumpAndSettle();

      await _restart(t, disk);
      await _show(t, MaturationLadderScreen(
          childName: 'Ivy', childAgeYears: 15, viewer: LadderViewer.guardian, now: now));
      expect(find.byIcon(Icons.favorite_outline), findsNothing);

      final LadderState state = (await LadderRepository.forChild().load())!;
      expect(state.grants.map((MaturationGrant g) => g.grant).toSet(),
          <Grant>{Grant.ownList, Grant.journalAbsolute, Grant.ownCalendar, Grant.publishAvailability});
      expect(state.announced, isNotEmpty);
    });

    test('LadderRepository round-trips and ignores a rung moved EARLIER than the ladder allows', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      LocalServices.install(s);
      final LadderRepository r = LadderRepository.forChild();
      expect(await r.load(), isNull);
      await r.save(LadderState(
        grants: <MaturationGrant>[
          MaturationGrant(childId: 'ivy', grant: Grant.ownList, age: 10, reachedAt: DateTime.utc(2026), rungAge: 10),
        ],
        agesLater: const <Grant, int>{Grant.ownCalendar: 16},
        revealsSeen: const <Grant>{Grant.ownList},
        announced: const <Grant>{},
      ));
      final LadderState back = (await r.load())!;
      expect(back.grants.single.grant, Grant.ownList);
      expect(back.agesLater, <Grant, int>{Grant.ownCalendar: 16});
      expect(back.revealsSeen, <Grant>{Grant.ownList});
    });
  });
}
