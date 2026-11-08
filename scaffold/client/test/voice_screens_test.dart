// OLIVE BRANCH — the child's Voice screens: feelings weather, worry box, my
// helpers, symbols. Private first, picture-first, 64dp targets, no verdicts on
// feelings, and the worry never shown, read or counted unless SHE chooses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/picture_library.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/voice_logic.dart';
import 'package:olive_client/voice_screens.dart';

import 'rv_support.dart';

void main() {
  group('feelings weather', () {
    testWidgets('six skies, each at least 64dp; picking one is kept for today and shown selected', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = freshService();
      await t.pumpWidget(app(FeelingsWeatherScreen(service: s)));
      await t.pumpAndSettle();
      for (final String id in weatherIds) {
        expect(find.byKey(Key('weather_$id')), findsOneWidget, reason: id);
        expect(heightOf(t, find.byKey(Key('weather_$id'))), greaterThanOrEqualTo(64));
      }
      await t.tap(find.byKey(const Key('weather_stormy')));
      await t.pumpAndSettle();
      expect((await s.weatherToday(ivy))!.weather, 'stormy');
      expect(t.getSemantics(find.byKey(const Key('weather_stormy'))).flagsCollection.isSelected.toBoolOrNull(), isTrue);

      await t.pumpWidget(app(const SizedBox()));
      await t.pumpWidget(app(FeelingsWeatherScreen(service: s)));
      await t.pumpAndSettle();
      expect(t.getSemantics(find.byKey(const Key('weather_stormy'))).flagsCollection.isSelected.toBoolOrNull(), isTrue,
          reason: 'her pick is still there when she comes back today');
    });

    testWidgets('it is private: there is no way to show it, send it, or look back', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(FeelingsWeatherScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(find.text('Only you can see this. It stays on this device.'), findsOneWidget);
      expect(find.textContaining(RegExp('show|send|share|history|week|trend|chart|streak|count', caseSensitive: false)), findsNothing);
      expect(find.byIcon(Icons.send), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
      expect(find.byIcon(Icons.bar_chart), findsNothing);
      expect(find.byIcon(Icons.history), findsNothing);
    });

    testWidgets('no sky is called good or bad, and none is a feeling name', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(FeelingsWeatherScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(find.textContaining(RegExp('good|bad|happy|sad|angry|mad|scared|better|worse', caseSensitive: false)), findsNothing);
      for (final String id in weatherIds) {
        expect(find.text(pictureLabel(id)), findsOneWidget);
      }
    });

    testWidgets('she can clear it, and then nothing is left', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = freshService();
      await t.pumpWidget(app(FeelingsWeatherScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('weatherClear')), findsNothing, reason: 'nothing to clear yet');
      await t.tap(find.byKey(const Key('weather_foggy')));
      await t.pumpAndSettle();
      expect(heightOf(t, find.byKey(const Key('weatherClear'))), greaterThanOrEqualTo(64));
      await t.tap(find.byKey(const Key('weatherClear')));
      await t.pumpAndSettle();
      expect(await s.weatherToday(ivy), isNull);
      expect(await s.feelings.load(), isNull);
      expect(find.byKey(const Key('weatherClear')), findsNothing);
    });

    testWidgets('the read-aloud seam only speaks when a speaker is given and she taps', (WidgetTester t) async {
      await phone(t);
      final List<String> said = <String>[];
      await t.pumpWidget(app(FeelingsWeatherScreen(service: freshService(), speak: (String x) async => said.add(x))));
      await t.pumpAndSettle();
      expect(said, isEmpty);
      await t.tap(find.byIcon(Icons.volume_up_outlined).first);
      expect(said, <String>['Sunny']);
    });

    testWidgets('no overflow at 344dp with large text', (WidgetTester t) async {
      await phone(t, w: 344, h: 900);
      await t.pumpWidget(app(FeelingsWeatherScreen(service: freshService()), textScale: 1.8));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('the worry box', () {
    Future<void> open(WidgetTester t, RhythmVoiceService s, {Size? size}) async {
      await phone(t, w: size?.width ?? 344, h: size?.height ?? 900);
      await t.pumpWidget(app(WorryBoxScreen(service: s)));
      await t.pumpAndSettle();
    }

    testWidgets('pick a picture, then choose "keep it in the box": it is stored, private, and no one is shown it', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await open(t, s);
      await t.tap(find.byKey(const Key('worryPick')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryPic_worry-dark')));
      await t.pumpAndSettle();
      expect(find.text('Then you choose'), findsOneWidget);
      for (final String k in <String>['worryKeep', 'worryShow', 'worryFloat']) {
        expect(heightOf(t, find.byKey(Key(k))), greaterThanOrEqualTo(64), reason: k);
      }
      await t.tap(find.byKey(const Key('worryKeep')));
      await t.pumpAndSettle();
      expect(find.text('It is in the box.'), findsOneWidget);
      final List<Worry> box = await s.myWorries(ivy);
      expect(box.single.picture, 'worry-dark');
      expect(box.single.shown, isFalse);
      expect(await s.worriesShownToGrownUp(guardian), isEmpty, reason: 'nothing automatic');
    });

    testWidgets('"show my grown-up" is a separate, deliberate choice, and only then does a guardian see it', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await open(t, s);
      await t.tap(find.byKey(const Key('worryPick')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryPic_worry-storm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryShow')));
      await t.pumpAndSettle();
      expect(find.text('Your grown-up can see this one.'), findsOneWidget);
      final List<Worry> seen = await s.worriesShownToGrownUp(guardian);
      expect(seen.single.picture, 'worry-storm');
    });

    testWidgets('"let it float away" on a new worry stores NOTHING at all', (WidgetTester t) async {
      final LocalServices ls = LocalServices.memory(childId: 'ivy');
      final RhythmVoiceService s = RhythmVoiceService.local(ls, clock: () => DateTime(2026, 11, 8, 19));
      await open(t, s);
      await t.tap(find.byKey(const Key('worryPick')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryPic_worry-noise')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryFloat')));
      await t.pumpAndSettle();
      expect(find.text('It floated away.'), findsOneWidget);
      expect(await t.runAsync(() => s.worries.load()), isEmpty);
      expect(await t.runAsync(() => ls.store.namespaces()), isEmpty, reason: 'not even an empty document is left');
    });

    testWidgets('she can draw a worry: a drawing is kept, normalised, and shows only if she chooses', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await open(t, s);
      await t.tap(find.byKey(const Key('worryDraw')));
      await t.pumpAndSettle();
      await t.drag(find.byKey(const Key('worryPad')), const Offset(80, 40));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryDrawDone')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryKeep')));
      await t.pumpAndSettle();
      final Worry w = (await s.myWorries(ivy)).single;
      expect(w.kind, WorryKind.drawing);
      expect(w.shown, isFalse);
      expect(w.strokes!.single.length, greaterThanOrEqualTo(4));
      for (final double v in w.strokes!.single) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });

    testWidgets('an empty drawing cannot be put in the box', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await open(t, s);
      await t.tap(find.byKey(const Key('worryDraw')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryDrawDone')));
      await t.pumpAndSettle();
      expect(find.text('Then you choose'), findsNothing);
      expect(await s.myWorries(ivy), isEmpty);
    });

    testWidgets('the screen never reads, labels or counts: no numbers, no "N worries", no tags', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-dark');
      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      await open(t, s);
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
      await t.tap(find.byKey(const Key('worryLook')));
      await t.pumpAndSettle();
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
      expect(find.textContaining(RegExp('worries|total|count|risk|serious|urgent|flag|concern', caseSensitive: false)), findsNothing);
    });

    testWidgets('in the box: she can show one, take it back, or let it float away for real', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-dark');
      await s.putWorryDrawing(ivy, <List<double>>[<double>[0.2, 0.2, 0.8, 0.8]]);
      await phone(t);
      await t.pumpWidget(app(WorryShelfScreen(service: s)));
      await t.pumpAndSettle();
      final String darkId = (await s.myWorries(ivy)).firstWhere((Worry w) => w.picture == 'worry-dark').id;
      await t.tap(find.byKey(Key('worry_$darkId')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('worryPrivateNote')), findsOneWidget);
      await t.tap(find.byKey(const Key('worryShowLater')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('worryShownNote')), findsOneWidget);
      expect((await s.worriesShownToGrownUp(guardian)).single.id, darkId);
      await t.tap(find.byKey(const Key('worryHide')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('worryPrivateNote')), findsOneWidget);
      expect(await s.worriesShownToGrownUp(guardian), isEmpty);
      await t.tap(find.byKey(const Key('worryFloatAway')));
      await t.pumpAndSettle();
      expect((await s.myWorries(ivy)).length, 1);
      expect((await s.myWorries(ivy)).any((Worry w) => w.id == darkId), isFalse);
    });

    testWidgets('an empty box is just empty', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(WorryShelfScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(find.text('The box is empty.'), findsOneWidget);
    });

    testWidgets('a full box says so and drops nothing', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      for (int i = 0; i < maxWorries; i++) {
        await s.putWorryPicture(ivy, 'worry-dark');
      }
      await open(t, s);
      await t.tap(find.byKey(const Key('worryPick')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryPic_worry-storm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryKeep')));
      await t.pumpAndSettle();
      expect(find.text('The box is full. Let one float away first.'), findsOneWidget);
      expect((await s.myWorries(ivy)).length, maxWorries);
    });

    testWidgets('every picture is a thing, not a feeling; no tile is under 64dp; no overflow at 344dp with large text', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await phone(t, w: 344, h: 1200);
      await t.pumpWidget(app(WorryBoxScreen(service: s), textScale: 1.8));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('worryPick')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final PictureDef p in picturesIn(PictureGroup.worry)) {
        expect(heightOf(t, find.byKey(Key('worryPic_${p.id}'))), greaterThanOrEqualTo(64));
      }
    });
  });

  group('my helpers', () {
    testWidgets('only people who have said yes appear, as pictures with names; no call, message or map', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.saveHelpers(guardian, <Helper>[
        makeHelper(id: 'a', name: 'Nana', picture: 'grandparent', line: 'Knock on the door at the end of the hall', saidYes: true),
        makeHelper(id: 'b', name: 'Mr Reyes', picture: 'counsellor'),
      ]);
      await phone(t);
      await t.pumpWidget(app(MyHelpersScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.text('Nana'), findsOneWidget);
      expect(find.text('Mr Reyes'), findsNothing, reason: 'has not said yes');
      expect(heightOf(t, find.byKey(const Key('helper_a'))), greaterThanOrEqualTo(64));
      await t.tap(find.byKey(const Key('helper_a')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('helperDetail_a')), findsOneWidget);
      expect(find.text('Knock on the door at the end of the hall'), findsOneWidget);
      for (final IconData i in <IconData>[Icons.call, Icons.phone, Icons.message, Icons.chat, Icons.videocam, Icons.map, Icons.location_on]) {
        expect(find.byIcon(i), findsNothing);
      }
      await t.tap(find.byKey(const Key('helperBack')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('helper_a')), findsOneWidget);
    });

    testWidgets('with none yet, a gentle line', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(MyHelpersScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(find.text('Your grown-up will add the people you can go to.'), findsOneWidget);
    });

    testWidgets('the speaker reads the name and the line when a speaker is given', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.saveHelpers(guardian, <Helper>[makeHelper(id: 'a', name: 'Nana', picture: 'grandparent', line: 'Next door', saidYes: true)]);
      final List<String> said = <String>[];
      await phone(t);
      await t.pumpWidget(app(MyHelpersScreen(service: s, speak: (String x) async => said.add(x))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('helper_a')));
      await t.pumpAndSettle();
      await t.tap(find.text('Hear this'));
      expect(said, <String>['Nana. Next door']);
    });
  });

  group('symbols', () {
    Future<void> tapAll(WidgetTester t, List<String> ids) async {
      for (final String id in ids) {
        await t.tap(find.byKey(Key('symbol_$id')));
        await t.pump();
      }
    }

    testWidgets('tapping pictures builds a strip and the plain sentence, in the order tapped', (WidgetTester t) async {
      await phone(t, w: 344, h: 1400);
      await t.pumpWidget(app(SymbolBoardScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(heightOf(t, find.byKey(const Key('symbol_sym-want'))), greaterThanOrEqualTo(64));
      await tapAll(t, <String>['sym-i', 'sym-want', 'sym-more']);
      expect(t.widget<Text>(find.byKey(const Key('symbolSentence'))).data, 'I want more');
      await t.tap(find.byKey(const Key('symbolBack')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('symbolSentence'))).data, 'I want');
      await t.tap(find.byKey(const Key('symbolClear')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('symbolSentence'))).data, '');
    });

    testWidgets('without a speaker it is quiet: the sentence is shown large and there is no Say it button', (WidgetTester t) async {
      await phone(t, w: 344, h: 1400);
      await t.pumpWidget(app(SymbolBoardScreen(service: freshService())));
      await t.pumpAndSettle();
      await tapAll(t, <String>['sym-help']);
      expect(find.byKey(const Key('symbolSay')), findsNothing);
      expect(find.byKey(const Key('symbolSentence')), findsOneWidget);
    });

    testWidgets('with a speaker: each word is read as she taps it, and Say it reads the whole sentence', (WidgetTester t) async {
      final List<String> said = <String>[];
      await phone(t, w: 344, h: 1400);
      await t.pumpWidget(app(SymbolBoardScreen(service: freshService(), speak: (String x) async => said.add(x))));
      await t.pumpAndSettle();
      await tapAll(t, <String>['sym-i', 'sym-want', 'sym-eat']);
      expect(said, <String>['I', 'want', 'eat']);
      await t.tap(find.byKey(const Key('symbolSay')));
      await t.pump();
      expect(said.last, 'I want eat', reason: 'word for word: nothing is corrected for her');
    });

    testWidgets('with the sound off nothing is spoken even when a speaker is given', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.saveSensory(guardian, const SensoryProfile(sound: SoundLevel.off));
      final List<String> said = <String>[];
      await phone(t, w: 344, h: 1400);
      await t.pumpWidget(app(SymbolBoardScreen(service: s, speak: (String x) async => said.add(x))));
      await t.pumpAndSettle();
      await tapAll(t, <String>['sym-i', 'sym-want']);
      expect(said, isEmpty);
      expect(find.byKey(const Key('symbolSay')), findsNothing);
      expect(t.widget<Text>(find.byKey(const Key('symbolSentence'))).data, 'I want', reason: 'still shown in writing');
    });

    testWidgets('her personal symbols are on the board after the core words', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.savePersonalSymbols(guardian, <String>['sym-owl']);
      await phone(t, w: 344, h: 1400);
      await t.pumpWidget(app(SymbolBoardScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('symbol_sym-owl')), findsOneWidget);
      expect(find.byKey(const Key('symbol_sym-bath')), findsNothing, reason: 'not chosen for her board');
    });

    testWidgets('a full strip is gently refused, not an error', (WidgetTester t) async {
      await phone(t, w: 344, h: 1400);
      await t.pumpWidget(app(SymbolBoardScreen(service: freshService())));
      await t.pumpAndSettle();
      await tapAll(t, List<String>.filled(maxStripLength, 'sym-more'));
      await t.tap(find.byKey(const Key('symbol_sym-more')));
      await t.pump();
      expect(find.text('That is a full sentence. Say it, or take one back.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('what she says is never kept: using the board writes nothing to the device', (WidgetTester t) async {
      final LocalServices ls = LocalServices.memory(childId: 'ivy');
      final RhythmVoiceService s = RhythmVoiceService.local(ls);
      await phone(t, w: 344, h: 1400);
      await t.pumpWidget(app(SymbolBoardScreen(service: s)));
      await t.pumpAndSettle();
      await tapAll(t, <String>['sym-i', 'sym-want', 'sym-more']);
      expect(await t.runAsync(() => ls.store.namespaces()), isEmpty);
    });

    testWidgets('no overflow at 344dp with large text', (WidgetTester t) async {
      await phone(t, w: 344, h: 1600);
      await t.pumpWidget(app(SymbolBoardScreen(service: freshService()), textScale: 1.8));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
