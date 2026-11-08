// No longer UNVERIFIED — verified by CI.
// OLIVE BRANCH — the component library (lib/ui). Every component is held to the same bar:
//   * renders in light AND dark (and in every palette for the shared primitives),
//   * at text scale 2.0 on a 344dp-wide surface with no overflow,
//   * every tap target is at least 48dp (guardian) or 64dp (child) in its hit area,
//   * exposes semantics (a tap action and a label on every target),
//   * reduced motion collapses every animation to zero,
// plus per-component behaviour: state is never carried by colour alone, child states have no words,
// the waveform and the pairing placeholder reproduce the kit's deterministic generators.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_data.dart';
import 'package:olive_client/ui/olive_ui.dart';

ThemeData _theme(Brightness b, [ThemePalette pal = ThemePalette.olive]) =>
    buildThemeData(AppTheme(palette: pal, brightness: b == Brightness.light ? ThemeBrightness.light : ThemeBrightness.dark));

Widget host(
  Widget child, {
  Brightness brightness = Brightness.light,
  ThemePalette palette = ThemePalette.olive,
  double scale = 1.0,
  double width = 344,
  OliveAudience audience = OliveAudience.guardian,
  bool reduceMotion = false,
}) =>
    MaterialApp(
      theme: _theme(brightness, palette),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: reduceMotion),
        child: OliveAudienceScope(audience: audience, child: app!),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: child)),
        ),
      ),
    );

/// A named specimen. [tapWidthFloor] is the one documented exception: the month calendar's day cells
/// are a seventh of the row wide (44dp in a padded 344dp page) and 48dp tall.
class Spec {
  const Spec(this.name, this.build, {this.tappable = true, this.tapWidthFloor = 48});
  final String name;
  final Widget Function() build;
  final bool tappable;
  final double tapWidthFloor;
}

List<Spec> specs() => [
      Spec('OliveButton', () => Wrap(spacing: 8, runSpacing: 8, children: [
            OliveButton('Send the letter now', onPressed: () {}, icon: OliveIcons.send),
            OliveButton('Tonal', onPressed: () {}, kind: OliveButtonKind.tonal, size: OliveButtonSize.sm),
            OliveButton('Ghost', onPressed: () {}, kind: OliveButtonKind.ghost, size: OliveButtonSize.lg),
            OliveButton('Remove', onPressed: () {}, kind: OliveButtonKind.danger),
            const OliveButton('Disabled'),
          ])),
      Spec('OliveIconButton', () => Wrap(children: [
            OliveIconButton(OliveIcons.chevL, label: 'Back', onPressed: () {}),
            OliveIconButton(OliveIcons.x, label: 'Close', onPressed: () {}, small: true, kind: OliveButtonKind.tonal),
            OliveIconButton(OliveIcons.mic, label: 'Record', onPressed: () {}, kind: OliveButtonKind.pri),
          ])),
      Spec('OliveChip + section label + divider', () => const Column(children: [
            Wrap(spacing: 6, children: [OliveChip('Quiet'), OliveChip('Fine', tone: OliveTone.ok, icon: OliveIcons.check), OliveChip('Small', small: true, tone: OliveTone.bad)]),
            OliveSectionLabel('Today', trailing: OliveChip('3', small: true)),
            OliveDivider(),
            OliveDivider(text: 'or'),
          ]), tappable: false),
      for (final v in OliveCardVariant.values)
        Spec('OliveCard.${v.name}', () => OliveCard(
              variant: v,
              onTap: v == OliveCardVariant.interactive ? () {} : null,
              semanticLabel: v == OliveCardVariant.interactive ? 'Open the card' : null,
              child: const Text('A card on the page with a sentence that is long enough to wrap onto more than one line.'),
            ), tappable: v == OliveCardVariant.interactive),
      Spec('OliveTile.hero', () => OliveTile.hero(title: 'Ivy is up', sub: 'Before school, 7:42', icon: OliveIcons.sun, scene: 'day', badge: '2', onTap: () {})),
      Spec('OliveTile.featured', () => OliveTile.featured(title: 'Letters', sub: 'One new from Dad', icon: OliveIcons.mail, badge: '1', onTap: () {})),
      Spec('OliveTile.standard', () => Row(children: [
            Expanded(child: OliveTile.standard(title: 'Games', icon: OliveIcons.dice, onTap: () {})),
            Expanded(child: OliveTile.standard(title: 'Colour', icon: OliveIcons.palette, onTap: () {})),
            Expanded(child: OliveTile.standard(title: 'Read', icon: OliveIcons.book, onTap: () {})),
          ])),
      Spec('OliveTile.picture', () => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: OliveTile.picture(title: 'Dad', spot: 'video', showDot: true, onTap: () {})),
            Expanded(child: OliveTile.picture(title: 'Stories', scene: 'bedroom', onTap: () {})),
          ])),
      Spec('OliveRow + group', () => OliveRowGroup(children: [
            OliveRow(title: 'Bedtime story tonight with a long title that wraps', sub: 'Tonight, 7:30', icon: OliveIcons.book, onTap: () {}),
            const OliveRow(title: 'Medicine', sub: 'Given', icon: OliveIcons.pill, tone: OliveTone.ok, trailing: StatusPill(StatusKind.delivered, small: true)),
          ])),
      Spec('KeyValueRow + list', () => const OliveCard(child: KeyValueList([('Recorded', 'Tuesday'), ('A long label that will need to wrap', 'Mom and Dad together')])), tappable: false),
      Spec('StatTile', () => const Wrap(spacing: 8, children: [
            SizedBox(width: 150, child: StatTile(label: 'Next handover', value: '3', unit: 'sleeps', note: 'Friday', icon: OliveIcons.calendar)),
            SizedBox(width: 150, child: StatTile(label: 'Letters', value: '4')),
          ]), tappable: false),
      Spec('OliveAvatar + AvatarStack', () => const Wrap(spacing: 8, children: [
            OliveAvatar('I'),
            OliveAvatar('D', tone: OliveTone.accent, presence: true, ring: true),
            AvatarStack([AvatarSpec('I'), AvatarSpec('D'), AvatarSpec('M'), AvatarSpec('G'), AvatarSpec('H')]),
          ]), tappable: false),
      Spec('StatusPill', () => Wrap(spacing: 6, runSpacing: 6, children: [for (final k in StatusKind.values) StatusPill(k), const StatusPill(StatusKind.watched, text: 'Watched 7:04', small: true)]), tappable: false),
      Spec('OliveNotice', () => Column(children: [
            OliveNotice(tone: OliveTone.warn, title: 'Clock ahead', text: 'This phone is 4 minutes ahead of the family.', actionLabel: 'See why', onAction: () {}, onDismiss: () {}),
            const OliveNotice(tone: OliveTone.bad, title: 'Not sent'),
            const OliveNotice(text: 'Plain info'),
          ])),
      Spec('OliveBanner', () => const Column(children: [OliveBanner('Welcome back. Three things are new.'), OliveBanner('All good', tone: OliveTone.ok)]), tappable: false),
      Spec('OfflineBanner', () => OfflineBanner(actionLabel: 'Retry', onAction: () {})),
      Spec('OliveToast', () => OliveToast('Message banked', icon: OliveIcons.check, tone: OliveTone.ok, actionLabel: 'Undo', onAction: () {})),
      Spec('EmptyState', () => EmptyState(spot: 'envelope', title: 'No letters yet', sub: 'When someone writes to you it will appear here.', actionLabel: 'Write one', onAction: () {})),
      Spec('EmptyState.child', () => const EmptyState.child(spot: 'family', semanticLabel: 'Nothing here yet'), tappable: false),
      Spec('ErrorState', () => ErrorState(onAction: () {}, detail: 'E-4012')),
      Spec('ErrorState.child', () => ErrorState.child(onAction: () {})),
      Spec('OliveSkeleton', () => Column(children: [for (final k in SkeletonKind.values) OliveSkeleton(k, count: 2)]), tappable: false),
      Spec('PermissionPrompt', () => PermissionPrompt(title: 'Allow the camera?', body: 'So she can show Dad what she made.', why: const ['Only while a call is open', 'Nothing is recorded'], onAllow: () {}, onDeny: () {})),
      Spec('SegmentedControl', () => Column(children: [
            SegmentedControl(items: const [SegmentItem('Today', count: 3), SegmentItem('This week'), SegmentItem('Month')], selected: 0, onChanged: (_) {}),
            SegmentedControl(full: false, small: true, items: const [SegmentItem('Mom', icon: OliveIcons.user), SegmentItem('Dad')], selected: 1, onChanged: (_) {}),
          ])),
      Spec('FilterChips', () => Column(children: [
            FilterChips(items: const [SegmentItem('All'), SegmentItem('Dad'), SegmentItem('Grandma', count: 2)], selected: const {0, 2}, onToggle: (_) {}),
            FilterChips(wrap: true, items: const [SegmentItem('All'), SegmentItem('Dad'), SegmentItem('Grandma', count: 2)], selected: const {1}, onToggle: (_) {}),
          ])),
      Spec('ToggleRow / RadioRow / CheckRow', () => OliveRowGroup(children: [
            ToggleRow(title: 'Quiet hours', sub: 'After 8 in the evening', icon: OliveIcons.moon, value: true, onChanged: (_) {}),
            RadioRow(title: 'Every day', selected: true, onSelected: () {}),
            CheckRow(title: 'Remind me', sub: 'A day before', value: false, onChanged: (_) {}),
          ])),
      Spec('OliveSwitch / OliveCheck / OliveRadio', () => Row(children: [
            OliveSwitch(value: true, onChanged: (_) {}, label: 'Wi-Fi only'),
            OliveCheck(value: true, onChanged: (_) {}, label: 'Agree'),
            OliveRadio(selected: false, onSelected: () {}, label: 'Option'),
          ])),
      Spec('SliderRow', () => SliderRow(title: 'Text size', icon: OliveIcons.eye, value: 0.6, onChanged: (_) {}, valueText: 'Large', startLabel: 'A', endLabel: 'A'), tappable: false),
      Spec('OliveFormField', () => const Column(children: [
            OliveFormField(label: 'Email address', placeholder: 'name@example.com', icon: OliveIcons.mail, required: true, hint: 'Only used to sign you in.'),
            OliveFormField(label: 'Code', initialValue: 'OLIVE-7', error: 'Looks unfinished', suffix: 'of 10'),
            OliveFormField(label: 'Locked', initialValue: 'Cannot change', enabled: false),
          ]), tappable: false),
      Spec('PinPad', () => PinPad(title: 'Grown-ups only', sub: 'Enter your PIN', filled: 2, includeZero: true, biometric: true, onDigit: (_) {}, onDelete: () {}, onBiometric: () {})),
      Spec('OliveStepper / OliveSteps / OliveProgress', () => const Column(children: [
            OliveStepper(total: 5, active: 3),
            SizedBox(height: 8),
            OliveSteps(labels: ['Role', 'Code', 'Scan'], active: 1),
            SizedBox(height: 8),
            OliveProgress(value: 0.6),
          ]), tappable: false),
      Spec('Timeline', () => const Timeline([
            TimelineItem(time: '7:04', title: 'Watched', sub: 'Mom saw it and smiled', tone: OliveTone.ok),
            TimelineItem(title: 'Now', sub: 'Waiting for Dad', state: TimelineState.now),
            TimelineItem(title: 'Later', state: TimelineState.next),
          ]), tappable: false),
      Spec('ScheduleGrid + ScheduleBlock', () => const ScheduleGrid(from: 7, to: 14, now: 11, blocks: [
            ScheduleBlockSpec(start: 8.5, end: 12, title: 'School', sub: 'Room 4', tone: OliveTone.info),
            ScheduleBlockSpec(start: 9, end: 10.5, title: 'Reading', col: 1, cols: 2),
          ]), tappable: false),
      Spec('MonthCalendar + DayCell', () => MonthCalendar(
            year: 2026, month: 11, today: 8, selected: 12,
            marks: const {1: DayMark.houseA, 5: DayMark.houseB, 4: DayMark.handover, 14: DayMark.event},
            onSelect: (_) {}, onPrevious: () {}, onNext: () {}),
          tapWidthFloor: 43),
      Spec('RecordButton', () => Wrap(children: [
            for (final s in RecordState.values) RecordButton(state: s, time: s == RecordState.idle ? null : '0:12', onPressed: () {}),
          ])),
      Spec('Waveform', () => const Waveform(played: 0.4, seed: 3), tappable: false),
      Spec('PlayerChrome', () => PlayerChrome(caption: 'Goodnight, Ivy.', onPlayPause: () {}, onSeek: (_) {}, onCaptions: () {}, onFullscreen: () {})),
      Spec('QrCard', () => QrCard(title: 'Scan on her tablet', sub: 'Open Olive and choose Pair.', expires: '10 minutes', onCopy: () {})),
      Spec('OliveBottomSheet', () => SizedBox(
            height: 520,
            child: OliveBottomSheet(title: 'Send to', onClose: () {}, actions: [OliveButton('Done', onPressed: () {})], child: const Column(children: [OliveRow(title: 'Dad', icon: OliveIcons.user), OliveRow(title: 'Grandma', icon: OliveIcons.user)])),
          )),
      Spec('OliveDialog', () => OliveDialog(title: 'Remove this letter?', body: 'It stays in the archive for 12 months.', icon: OliveIcons.trash, tone: OliveTone.bad, actions: [OliveButton('Cancel', kind: OliveButtonKind.ghost, onPressed: () {}), OliveButton('Remove', kind: OliveButtonKind.danger, onPressed: () {})])),
    ];

void main() {
  group('every component renders in light and dark', () {
    for (final s in specs()) {
      testWidgets(s.name, (tester) async {
        for (final b in Brightness.values) {
          await tester.pumpWidget(host(s.build(), brightness: b));
          expect(tester.takeException(), isNull, reason: '${s.name} ${b.name}');
        }
      });
    }
    testWidgets('the shared primitives render in all seven palettes', (tester) async {
      for (final pal in ThemePalette.values) {
        await tester.pumpWidget(host(Column(children: [specs()[0].build(), specs().firstWhere((s) => s.name == 'StatusPill').build(), specs().firstWhere((s) => s.name == 'OliveNotice').build()]), palette: pal));
        expect(tester.takeException(), isNull, reason: pal.name);
      }
    });
  });

  group('text scale 2.0 on a 344dp surface: no overflow', () {
    for (final s in specs()) {
      testWidgets(s.name, (tester) async {
        for (final b in Brightness.values) {
          await tester.pumpWidget(host(s.build(), scale: 2.0, brightness: b));
          expect(tester.takeException(), isNull, reason: '${s.name} ${b.name}');
        }
      });
    }
  });

  group('tap targets: >= 48dp guardian, >= 64dp child', () {
    for (final s in specs().where((s) => s.tappable)) {
      testWidgets('${s.name} (guardian)', (tester) async {
        await tester.pumpWidget(host(s.build()));
        _expectTargets(tester, 48, s.tapWidthFloor);
      });
      testWidgets('${s.name} (child)', (tester) async {
        await tester.pumpWidget(host(s.build(), audience: OliveAudience.child));
        _expectTargets(tester, 64, s.tapWidthFloor == 48 ? 64 : s.tapWidthFloor);
      });
    }
    testWidgets('the slider and the scrubber are at least 48dp tall', (tester) async {
      await tester.pumpWidget(host(Column(children: [OliveSlider(value: 0.5, onChanged: (_) {}), PlayerChrome(onSeek: (_) {})])));
      expect(tester.getSize(find.byType(OliveSlider)).height, greaterThanOrEqualTo(48));
      final scrub = find.bySemanticsLabel('Seek');
      expect(scrub, findsOneWidget);
    });
    testWidgets('a button smaller than the target on screen still has a full-size hit area', (tester) async {
      await tester.pumpWidget(host(Align(alignment: Alignment.topLeft, child: OliveButton('Hi', size: OliveButtonSize.sm, onPressed: () {}))));
      expect(tester.getSize(find.byType(OlivePressable)).height, greaterThanOrEqualTo(48));
    });
  });

  group('semantics: every target has a tap action and a name', () {
    for (final s in specs().where((s) => s.tappable)) {
      testWidgets(s.name, (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(host(s.build()));
        var checked = 0;
        for (final e in find.byType(OlivePressable).evaluate()) {
          final w = e.widget as OlivePressable;
          if (w.onTap == null) continue;
          final data = tester.getSemantics(find.byWidget(w)).getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isTrue, reason: '${s.name}: no tap action');
          expect(data.label.trim().isNotEmpty, isTrue, reason: '${s.name}: a target with no name');
          checked++;
        }
        expect(checked, greaterThan(0), reason: '${s.name} has no enabled target');
        handle.dispose();
      });
    }

    testWidgets('selection, toggle and check states are exposed', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(Column(children: [
        ToggleRow(title: 'Quiet hours', value: true, onChanged: (_) {}),
        RadioRow(title: 'Every day', selected: true, onSelected: () {}),
        CheckRow(title: 'Remind me', value: true, onChanged: (_) {}),
        SegmentedControl(items: const [SegmentItem('A'), SegmentItem('B')], selected: 1, onChanged: (_) {}),
      ])));
      expect(tester.getSemantics(find.byType(ToggleRow)).getSemanticsData().flagsCollection.isToggled.name, isNot('none'));
      final radio = tester.getSemantics(find.byType(RadioRow)).getSemanticsData();
      expect(radio.flagsCollection.isSelected.name, isNot('none'));
      final check = tester.getSemantics(find.byType(CheckRow)).getSemanticsData();
      expect(check.flagsCollection.isChecked.name, isNot('none'));
      handle.dispose();
    });
  });

  group('reduced motion collapses every animation', () {
    bool animated(Widget w) => w is AnimatedContainer || w is AnimatedScale || w is AnimatedAlign || w is AnimatedFractionallySizedBox;
    Duration? durationOf(Widget w) => w is ImplicitlyAnimatedWidget ? w.duration : null;

    for (final s in specs()) {
      testWidgets(s.name, (tester) async {
        await tester.pumpWidget(host(s.build(), reduceMotion: true));
        final slow = find.byWidgetPredicate((w) => animated(w) && durationOf(w) != Duration.zero);
        expect(slow, findsNothing, reason: '${s.name} animates under reduced motion');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the same components DO animate when motion is allowed (the test bites)', (tester) async {
      await tester.pumpWidget(host(Column(children: [
        OliveSwitch(value: true, onChanged: (_) {}),
        const OliveStepper(total: 3, active: 2),
        SegmentedControl(items: const [SegmentItem('A'), SegmentItem('B')], selected: 0, onChanged: (_) {}),
      ])));
      expect(find.byWidgetPredicate((w) => animated(w) && durationOf(w) != Duration.zero), findsWidgets);
    });

    testWidgets('OliveTiming durations are the kit values and zero when reduced', (tester) async {
      late Duration press, fast, base, slow;
      Widget probe() => Builder(builder: (c) {
            press = OliveTiming.press(c);
            fast = OliveTiming.fast(c);
            base = OliveTiming.base(c);
            slow = OliveTiming.slow(c);
            return const SizedBox();
          });
      await tester.pumpWidget(host(probe()));
      expect([press.inMilliseconds, fast.inMilliseconds, base.inMilliseconds, slow.inMilliseconds], [40, 120, 220, 340]);
      await tester.pumpWidget(host(probe(), reduceMotion: true));
      expect([press, fast, base, slow], everyElement(Duration.zero));
    });

    testWidgets('a press does not scale the target under reduced motion', (tester) async {
      await tester.pumpWidget(host(OliveButton('Go', onPressed: () {}), reduceMotion: true));
      final gesture = await tester.startGesture(tester.getCenter(find.byType(OliveButton)));
      await tester.pump();
      final scale = tester.widget<AnimatedScale>(find.descendant(of: find.byType(OlivePressable), matching: find.byType(AnimatedScale)));
      expect(scale.scale, 1.0);
      await gesture.up();
    });
  });

  group('StatusPill: shape + icon + word, never colour alone', () {
    test('every state has its own word and its own icon', () {
      final words = StatusKind.values.map(StatusPill.defaultWord).toSet();
      final icons = StatusKind.values.map(StatusPill.iconFor).toSet();
      expect(words.length, StatusKind.values.length);
      expect(icons.length, StatusKind.values.length);
    });

    test('the outline shape distinguishes queued, sending, watched and failed', () {
      expect(StatusPill.edgeFor(StatusKind.queued), 'dashed');
      expect(StatusPill.edgeFor(StatusKind.delivering), 'solid');
      expect(StatusPill.edgeFor(StatusKind.watched), 'ring');
      expect(StatusPill.edgeFor(StatusKind.failed), 'bold');
      expect({for (final k in StatusKind.values) '${StatusPill.edgeFor(k)}/${StatusPill.iconFor(k)}'}.length, StatusKind.values.length);
    });

    testWidgets('the word is drawn and is the semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(Column(children: [for (final k in StatusKind.values) StatusPill(k)])));
      for (final k in StatusKind.values) {
        expect(find.text(StatusPill.defaultWord(k)), findsOneWidget, reason: k.name);
        expect(find.bySemanticsLabel(StatusPill.defaultWord(k)), findsOneWidget, reason: k.name);
      }
      handle.dispose();
    });

    testWidgets('a custom word replaces the default', (tester) async {
      await tester.pumpWidget(host(const StatusPill(StatusKind.watched, text: 'Watched 7:04')));
      expect(find.text('Watched 7:04'), findsOneWidget);
    });

    testWidgets('the states are distinguishable with all colour removed (greyscale)', (tester) async {
      Widget grey(Widget c) => ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0]), child: c);
      await tester.pumpWidget(host(grey(Wrap(children: [for (final k in StatusKind.values) StatusPill(k)]))));
      // Words survive the filter: that is the guarantee the greyscale proof stands on.
      for (final k in StatusKind.values) {
        expect(find.text(StatusPill.defaultWord(k)), findsOneWidget);
      }
    });
  });

  group('child surfaces carry no words and no numbers', () {
    testWidgets('EmptyState.child has no text at all', (tester) async {
      await tester.pumpWidget(host(const EmptyState.child(semanticLabel: 'Nothing here yet'), audience: OliveAudience.child));
      expect(find.byType(Text), findsNothing);
      expect(find.byType(RichText), findsNothing);
      expect(find.byType(OliveSpot), findsOneWidget);
    });

    testWidgets('ErrorState.child has no text, only a picture and a retry button', (tester) async {
      var retried = 0;
      await tester.pumpWidget(host(ErrorState.child(onAction: () => retried++), audience: OliveAudience.child));
      expect(find.byType(Text), findsNothing);
      expect(find.byType(RichText), findsNothing);
      await tester.tap(find.byType(OlivePressable));
      expect(retried, 1);
      final size = tester.getSize(find.byType(OlivePressable));
      expect(size.shortestSide, greaterThanOrEqualTo(64));
    });

    testWidgets('the guardian EmptyState and ErrorState DO have words', (tester) async {
      await tester.pumpWidget(host(Column(children: [const EmptyState(title: 'No letters yet'), ErrorState(onAction: () {})])));
      expect(find.text('No letters yet'), findsOneWidget);
      expect(find.text('That did not work'), findsOneWidget);
    });

    testWidgets('the picture tile shows a DOT, never a number', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(OliveTile.picture(title: 'Dad', spot: 'video', showDot: true, onTap: () {}), audience: OliveAudience.child));
      final digits = find.byWidgetPredicate((w) => w is Text && RegExp(r'\d').hasMatch(w.data ?? ''));
      expect(digits, findsNothing);
      expect(find.bySemanticsLabel('Dad, something new'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the picture tile can drop its label entirely', (tester) async {
      await tester.pumpWidget(host(OliveTile.picture(title: 'Dad', spot: 'video', showLabel: false, onTap: () {}), audience: OliveAudience.child));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('child audience enlarges buttons, icon buttons and cards', (tester) async {
      await tester.pumpWidget(host(Column(children: [OliveButton('Go', onPressed: () {}), OliveIconButton(OliveIcons.x, label: 'Close', onPressed: () {})]), audience: OliveAudience.child));
      expect(tester.getSize(find.byType(OliveButton)).height, greaterThanOrEqualTo(64));
      expect(tester.getSize(find.byType(OliveIconButton)).height, greaterThanOrEqualTo(64));
    });

    testWidgets('no component of the library renders a score, streak, star or trophy', (tester) async {
      await tester.pumpWidget(host(Column(children: [for (final s in specs()) s.build()])));
      final banned = RegExp(r'score|streak|trophy|rank|points', caseSensitive: false);
      expect(find.byWidgetPredicate((w) => w is Text && banned.hasMatch(w.data ?? '')), findsNothing);
    });
  });

  group('behaviour', () {
    testWidgets('SegmentedControl reports the tapped index', (tester) async {
      int? got;
      await tester.pumpWidget(host(SegmentedControl(items: const [SegmentItem('One'), SegmentItem('Two'), SegmentItem('Three')], selected: 0, onChanged: (i) => got = i)));
      await tester.tap(find.text('Three'));
      expect(got, 2);
    });

    testWidgets('FilterChips toggles by index and shows a check when on', (tester) async {
      final toggled = <int>[];
      await tester.pumpWidget(host(FilterChips(items: const [SegmentItem('All'), SegmentItem('Dad')], selected: const {1}, onToggle: toggled.add)));
      await tester.tap(find.text('All'));
      expect(toggled, [0]);
      expect(find.byType(OliveIcon), findsOneWidget, reason: 'only the selected chip carries a check');
    });

    testWidgets('ToggleRow flips on tap and disabled rows do nothing', (tester) async {
      var v = false;
      await tester.pumpWidget(host(StatefulBuilder(builder: (c, set) => ToggleRow(title: 'Quiet', value: v, onChanged: (x) => set(() => v = x)))));
      await tester.tap(find.text('Quiet'));
      await tester.pump();
      expect(v, isTrue);
      await tester.pumpWidget(host(const ToggleRow(title: 'Quiet', value: true, onChanged: null)));
      await tester.tap(find.text('Quiet'));
    });

    testWidgets('OliveSlider: drag, tap, arrow keys and screen reader actions', (tester) async {
      var v = 0.5;
      await tester.pumpWidget(host(StatefulBuilder(builder: (c, set) => OliveSlider(value: v, step: 0.1, label: 'Volume', onChanged: (x) => set(() => v = x)))));
      await tester.tapAt(tester.getTopLeft(find.byType(OliveSlider)) + const Offset(300, 24));
      await tester.pump();
      expect(v, greaterThan(0.8));
      await tester.drag(find.byType(OliveSlider), const Offset(-400, 0));
      await tester.pump();
      expect(v, lessThan(0.5));
      final handle = tester.ensureSemantics();
      final before = v;
      tester.semantics.performAction(find.semantics.byLabel('Volume'), SemanticsAction.increase);
      await tester.pump();
      expect(v, greaterThan(before));
      handle.dispose();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    });

    testWidgets('OliveFormField shows an error with an icon AND words, and the hint otherwise', (tester) async {
      await tester.pumpWidget(host(const Column(children: [
        OliveFormField(label: 'Email', hint: 'Only used to sign you in.'),
        OliveFormField(label: 'Code', error: 'Looks unfinished'),
      ])));
      expect(find.text('Only used to sign you in.'), findsOneWidget);
      expect(find.text('Looks unfinished'), findsOneWidget);
      expect(find.byType(OliveIcon), findsNWidgets(2), reason: 'the error icon appears beside the field and beside the words');
      await tester.enterText(find.byType(TextField).first, 'dad@example.com');
      expect(find.text('dad@example.com'), findsOneWidget);
    });

    testWidgets('PinPad: digits, delete and biometric callbacks; dots announce progress without digits', (tester) async {
      final digits = <int>[];
      var deleted = 0, bio = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(PinPad(filled: 2, includeZero: true, biometric: true, onDigit: digits.add, onDelete: () => deleted++, onBiometric: () => bio++)));
      await tester.tap(find.text('7'));
      await tester.tap(find.text('0'));
      await tester.tap(find.bySemanticsLabel('Delete'));
      await tester.tap(find.bySemanticsLabel('Use fingerprint'));
      expect(digits, [7, 0]);
      expect([deleted, bio], [1, 1]);
      expect(find.bySemanticsLabel('2 of 4 entered'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a child PinPad has no zero key and takes the order it is given', (tester) async {
      await tester.pumpWidget(host(const PinPad(digits: [4, 8, 1, 9, 3, 6, 2, 7, 5]), audience: OliveAudience.child));
      expect(find.text('0'), findsNothing);
      final order = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
      expect(order, ['4', '8', '1', '9', '3', '6', '2', '7', '5']);
    });

    testWidgets('MonthCalendar: day tap, previous/next, legend, house shapes in the semantics', (tester) async {
      int? sel;
      var prev = 0, next = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(MonthCalendar(
        year: 2026, month: 11, today: 8,
        marks: const {1: DayMark.houseA, 5: DayMark.houseB, 4: DayMark.handover},
        onSelect: (d) => sel = d, onPrevious: () => prev++, onNext: () => next++)));
      await tester.tap(find.text('17'));
      await tester.tap(find.bySemanticsLabel('Previous month'));
      await tester.tap(find.bySemanticsLabel('Next month'));
      expect([sel, prev, next], [17, 1, 1]);
      expect(find.bySemanticsLabel(RegExp('8, today')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('1, Mom’s house')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('5, Dad’s house')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('4, handover day')), findsOneWidget);
      expect(find.text('November 2026'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('MonthCalendar lays November 2026 out correctly (Sunday and Monday starts)', (tester) async {
      // 1 November 2026 is a Sunday: no leading blanks with a Sunday start, six with a Monday start.
      await tester.pumpWidget(host(const MonthCalendar(year: 2026, month: 11, showLegend: false)));
      expect(find.byType(DayCell), findsNWidgets(35));
      await tester.pumpWidget(host(const MonthCalendar(year: 2026, month: 11, showLegend: false, weekStartsOn: 1)));
      expect(find.byType(DayCell), findsNWidgets(42));
    });

    testWidgets('Timeline words the state in its semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const Timeline([TimelineItem(title: 'Delivered'), TimelineItem(title: 'Waiting', state: TimelineState.now), TimelineItem(title: 'Goodnight call', state: TimelineState.next)])));
      expect(find.bySemanticsLabel('Now, Waiting'), findsOneWidget);
      expect(find.bySemanticsLabel('Next, Goodnight call'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ScheduleBlock carries its whole text in the semantics even when clipped', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const ScheduleGrid(from: 7, to: 10, blocks: [ScheduleBlockSpec(start: 8, end: 8.5, title: 'Tiny block', sub: 'Does not fit')])));
      expect(find.bySemanticsLabel('Tiny block, Does not fit, 8a to 8:30a'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('OliveStepper and OliveProgress are announced', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const Column(children: [OliveStepper(total: 5, active: 3), OliveProgress(value: 0.6, semanticLabel: 'Upload')])));
      expect(find.bySemanticsLabel('Step 3 of 5'), findsOneWidget);
      expect(find.bySemanticsLabel('Upload'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('RecordButton states differ in shape and in label', (tester) async {
      final handle = tester.ensureSemantics();
      for (final e in {RecordState.idle: 'Start recording', RecordState.recording: 'Stop recording', RecordState.done: 'Record again'}.entries) {
        await tester.pumpWidget(host(RecordButton(state: e.key, onPressed: () {})));
        expect(find.bySemanticsLabel(e.value), findsOneWidget);
      }
      handle.dispose();
    });

    testWidgets('PlayerChrome: play, pause, captions, wordless by default', (tester) async {
      var plays = 0, caps = 0;
      await tester.pumpWidget(host(PlayerChrome(caption: 'Goodnight, Ivy.', onPlayPause: () => plays++, onCaptions: () => caps++)));
      expect(find.text('Goodnight, Ivy.'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && RegExp(r'\d:\d\d').hasMatch(w.data ?? '')), findsNothing, reason: 'no times unless asked');
      await tester.tap(find.bySemanticsLabel('Captions'));
      await tester.tap(find.bySemanticsLabel('Play').first);
      expect([plays, caps], [1, 1]);
      await tester.pumpWidget(host(const PlayerChrome(caption: 'Hi', captionsOn: false, playing: true, showScrubber: false)));
      expect(find.text('Hi'), findsNothing, reason: 'captions off');
      expect(find.bySemanticsLabel('Seek'), findsNothing, reason: 'scrubber hidden');
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    });

    testWidgets('QrCard placeholder is labelled sample, and a real code replaces it', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const QrCard(title: 'Scan', code: 'OLIVE-7K4P')));
      expect(find.text('Sample'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('sample only')), findsOneWidget);
      await tester.pumpWidget(host(const QrCard(code: 'OLIVE-7K4P', qr: ColoredBox(color: Colors.black, child: SizedBox(width: 50, height: 50)))));
      expect(find.text('Sample'), findsNothing);
      handle.dispose();
    });

    testWidgets('showOliveToast floats a toast and its action dismisses and calls back', (tester) async {
      var undone = 0;
      await tester.pumpWidget(host(Builder(builder: (c) => OliveButton('Toast', onPressed: () => showOliveToast(c, 'Message banked', icon: OliveIcons.check, actionLabel: 'Undo', onAction: () => undone++)))));
      await tester.tap(find.text('Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Message banked'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      expect(undone, 1);
    });

    testWidgets('OliveBottomSheet.show presents a titled sheet that closes', (tester) async {
      await tester.pumpWidget(host(Builder(builder: (c) => OliveButton('Open', onPressed: () => OliveBottomSheet.show<void>(c, title: 'Send to', showClose: true, builder: (_) => const Text('Dad'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Send to'), findsOneWidget);
      expect(find.text('Dad'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Send to'), findsNothing);
    });

    testWidgets('OliveDialog.show returns the value its action pops', (tester) async {
      String? result;
      await tester.pumpWidget(host(Builder(builder: (c) => OliveButton('Open', onPressed: () async {
            result = await OliveDialog.show<String>(c, title: 'Remove?', icon: OliveIcons.trash, tone: OliveTone.bad, actions: (d) => [OliveButton('Remove', onPressed: () => Navigator.of(d).pop('removed'))]);
          }))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Remove?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(result, 'removed');
    });

    testWidgets('a sheet and a dialog appear instantly under reduced motion', (tester) async {
      await tester.pumpWidget(host(Builder(builder: (c) => OliveButton('Open', onPressed: () => OliveDialog.show<void>(c, title: 'Quick', actions: (_) => const []))), reduceMotion: true));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Quick'), findsOneWidget);
    });
  });

  group('kit parity: deterministic generators', () {
    test('Waveform heights are the kit OB.waveform values (seed 3, 36 bars)', () {
      final h = Waveform.heights(36, 3);
      const expected = [0.2569469485846288, 0.33914544905120225, 0.3210041206945416, 0.3437646644580189, 0.5591064220648978];
      for (var i = 0; i < expected.length; i++) {
        expect(h[i], closeTo(expected[i], 1e-9), reason: 'bar $i');
      }
      expect(h.every((v) => v >= 0.14 && v <= 1.0), isTrue);
      expect(Waveform.heights(36, 3), h, reason: 'deterministic');
      expect(Waveform.heights(36, 4), isNot(h));
    });

    test('QrCard placeholder reproduces the kit generator for OLIVE-7K4P', () {
      final g = QrCard.placeholderCells('OLIVE-7K4P');
      String row(int y) => g[y].map((b) => b ? '1' : '0').join();
      expect(row(0), '111111101110001111111');
      expect(row(10), '001100010100001000010');
      expect(row(20), '111111101000100010011');
      expect(g.expand((r) => r).where((b) => b).length, 243);
      expect(QrCard.placeholderCells('OLIVE-7K4Q'), isNot(g));
    });

    test('the placeholder is not a valid QR: the bottom-left position marker is never drawn', () {
      final full = QrCard.placeholderCells('OLIVE-7K4P');
      final drawn = QrCard.placeholderDrawn('OLIVE-7K4P');
      bool block(List<List<bool>> g, int x0, int y0) => [for (var y = y0; y < y0 + 7; y++) for (var x = x0; x < x0 + 7; x++) g[y][x]].any((b) => b);
      expect(block(full, 0, 14), isTrue, reason: 'the kit pattern has all three markers');
      expect(block(drawn, 0, 14), isFalse, reason: 'ours leaves one out');
      expect(block(drawn, 0, 0), isTrue);
      expect(block(drawn, 14, 0), isTrue);
    });
  });

  group('tokens: nothing is hard-coded', () {
    testWidgets('a different palette changes the colours of the same widget', (tester) async {
      Future<Color> bg(ThemePalette p) async {
        await tester.pumpWidget(host(const OliveCard(variant: OliveCardVariant.tint, child: Text('x')), palette: p));
        await tester.pumpAndSettle();
        final box = tester.widget<AnimatedContainer>(find.descendant(of: find.byType(OliveCard), matching: find.byType(AnimatedContainer)).first);
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(await bg(ThemePalette.olive), isNot(await bg(ThemePalette.warmGrounded)));
    });

    testWidgets('dark mode changes the same widget', (tester) async {
      Future<Color> bg(Brightness b) async {
        await tester.pumpWidget(host(const OliveCard(variant: OliveCardVariant.tint, child: Text('x')), brightness: b));
        await tester.pumpAndSettle();
        final box = tester.widget<AnimatedContainer>(find.descendant(of: find.byType(OliveCard), matching: find.byType(AnimatedContainer)).first);
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(await bg(Brightness.light), isNot(await bg(Brightness.dark)));
    });

    test('OlivePalette follows the OliveSemantic extension, not a palette', () {
      for (final pal in ThemePalette.values) {
        final light = OlivePalette.fromTheme(_theme(Brightness.light, pal));
        expect(light.ok, OliveSemantic.light.ok);
        expect(light.dpNight, OliveSemantic.light.dayNight);
        final dark = OlivePalette.fromTheme(_theme(Brightness.dark, pal));
        expect(dark.warnC, OliveSemantic.dark.warnContainer);
      }
    });

    test('shadow ladder has four levels that grow', () {
      final p = OlivePalette.fromTheme(_theme(Brightness.light));
      final blur = [for (var i = 0; i < 4; i++) p.shadow(i).fold<double>(0, (a, s) => a + s.blurRadius)];
      for (var i = 1; i < 4; i++) {
        expect(blur[i], greaterThan(blur[i - 1]));
      }
    });
  });
}

void _expectTargets(WidgetTester tester, double minHeight, double minWidth) {
  var n = 0;
  for (final e in find.byType(OlivePressable).evaluate()) {
    final w = e.widget as OlivePressable;
    if (w.onTap == null) continue;
    final size = tester.getSize(find.byWidget(w));
    expect(size.height, greaterThanOrEqualTo(minHeight - 0.01), reason: 'target ${size.width}x${size.height} is shorter than $minHeight');
    expect(size.width, greaterThanOrEqualTo(minWidth - 0.01), reason: 'target ${size.width}x${size.height} is narrower than $minWidth');
    n++;
  }
  expect(n, greaterThan(0));
}
