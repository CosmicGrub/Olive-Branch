// OLIVE BRANCH — client invariant tests.
//
// These assert the SAME properties the TypeScript suites assert, but against
// the widget tree that a child actually sees. Until v0.15.0 the Dart was
// contract-checked only — its endpoint strings and channel constants were
// verified, which is not the same as verifying what renders.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/games_hub.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/kiosk_channel.dart';
import 'package:olive_client/kiosk_shell.dart';
import 'package:olive_client/pin_gate.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// KioskChannel's methods are regular (non-final) instance methods, so this
/// overrides them rather than touching a real platform channel — there is no
/// native handler under `flutter test`, on purpose (see kiosk_shell.dart's
/// `_engage()` for the same reasoning on the production path).
class _FakeKioskChannel extends KioskChannel {
  final _controller = StreamController<String>.broadcast();
  String startMode = 'pinned';

  void emit(String event) => _controller.add(event);

  @override
  Future<String> start() async => startMode;

  @override
  Stream<String> events() => _controller.stream;
}

void main() {
  group('child shell — §8.1', () {
    testWidgets('renders the child by name, not by id', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 1)));
      expect(find.text('Hi Maya'), findsOneWidget);
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
      expect(find.textContaining('settings'), findsNothing);
    });

    testWidgets('§8.2.5 countdown is in sleeps, never hours', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0)));
      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('sleeps until'), findsOneWidget);
      expect(find.textContaining('hours'), findsNothing);
    });

    testWidgets('singular sleep is not "1 sleeps"', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 1, unreadCount: 0)));
      expect(find.textContaining('sleep until'), findsOneWidget);
      expect(find.textContaining('sleeps until'), findsNothing);
    });

    testWidgets('§4.1 presence names HER frame first', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya',
        presence: ParentPresence('Dad', '8:41 PM', '9:30'),
        sleepsUntilHandover: 3, unreadCount: 0)));
      expect(find.text('Dad is free right now'), findsOneWidget);
      expect(find.text('Call Dad'), findsOneWidget);
    });

    testWidgets('§8.4 touch targets are at least 48dp for pre-readers',
        (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya',
        presence: ParentPresence('Dad', '8:41 PM', '9:30'),
        sleepsUntilHandover: 3, unreadCount: 0)));
      final Size button = t.getSize(find.byType(FilledButton).first);
      expect(button.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('unread count reaches the Messages tile as a badge, not '
        'silently dropped', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 2)));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a zero unread count shows no badge', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0)));
      expect(find.text('0'), findsNothing);
    });
  });

  group('games dormancy — child side (db/migrations/0008_games_access.sql)', () {
    testWidgets('default (no gamesEnabled passed) behaves exactly as before this field existed',
        (t) async {
      // No `gamesEnabled:` argument at all — the exact call shape every
      // caller before this field existed already used. Must default to
      // unlocked so main.dart's offline demo and this file's own
      // pre-existing tests above keep behaving identically.
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0)));
      expect(find.byIcon(Icons.extension), findsOneWidget);
      expect(find.byIcon(Icons.casino_outlined), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);
    });

    testWidgets('unlocked (gamesEnabled: true) opens the real games hub as before', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0, gamesEnabled: true)));
      await t.tap(find.text('More games'));
      await t.pumpAndSettle();
      expect(find.byType(GamesHubScreen), findsOneWidget);
    });

    testWidgets('locked: both games tiles stay visible with a real lock icon, passively, '
        'with no tap needed to see the state', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0, gamesEnabled: false)));
      // Not silently disappeared — the tile labels are still exactly there.
      expect(find.text('Play together'), findsOneWidget);
      expect(find.text('More games'), findsOneWidget);
      // A real icon replaces the game icon on both, passively, with no tap —
      // "the child side may only ever passively show whether games are on
      // or off."
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
      expect(find.byIcon(Icons.extension), findsNothing);
      expect(find.byIcon(Icons.casino_outlined), findsNothing);
    });

    testWidgets('locked: tapping "Play together" gives calm, honest feedback, never '
        'opens the game picker', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0, gamesEnabled: false)));
      await t.tap(find.text('Play together'));
      await t.pump();
      expect(find.text('Ask a grown-up to turn on games'), findsOneWidget);
      expect(find.byType(GamePickerScreen), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpAndSettle();
    });

    testWidgets('locked: tapping "More games" gives calm, honest feedback, never opens '
        'the games hub', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0, gamesEnabled: false)));
      await t.tap(find.text('More games'));
      await t.pump();
      expect(find.text('Ask a grown-up to turn on games'), findsOneWidget);
      expect(find.byType(GamesHubScreen), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpAndSettle();
    });

    testWidgets('locked state still shows no settings/toggle control of any kind', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0, gamesEnabled: false)));
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
      expect(find.textContaining('turn off'), findsNothing);
    });

    testWidgets('locked ChildHome renders without overflow at the Fold5 cover width (344px)',
        (t) async {
      t.view.physicalSize = const Size(344, 882);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0, gamesEnabled: false)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('guardian shell — §8.2', () {
    const List<RibbonBand> bands = <RibbonBand>[
      RibbonBand(0, 0.5, Colors.blue, 'school'),
      RibbonBand(0.5, 0.5, Colors.green, 'home time'),
    ];

    testWidgets('the CHILD time is dominant and the actor time subordinate',
        (t) async {
      await t.pumpWidget(wrap(const GuardianHome(
        childName: 'Maya', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT',
        actorLocalTime: '3:12 PM CDT',
        childStateSentence: 'Maya is just home from school',
        childBands: bands, actorBands: bands)));
      final Text childTime = t.widget(find.text('4:12 PM'));
      final Text actorLine = t.widget(find.text('you · 3:12 PM CDT'));
      expect(childTime.style!.fontSize!,
          greaterThan(actorLine.style!.fontSize!));
    });

    testWidgets('§8.2.3 the parent is never shown arithmetic', (t) async {
      await t.pumpWidget(wrap(const GuardianHome(
        childName: 'Maya', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT',
        actorLocalTime: '3:12 PM CDT',
        childStateSentence: 'Maya is just home from school',
        childBands: bands, actorBands: bands)));
      expect(find.textContaining('+1'), findsNothing);
      expect(find.textContaining('difference'), findsNothing);
      expect(find.textContaining('UTC'), findsNothing);
    });

    testWidgets('her state reads as a sentence about her', (t) async {
      await t.pumpWidget(wrap(const GuardianHome(
        childName: 'Maya', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT',
        actorLocalTime: '3:12 PM CDT',
        childStateSentence: 'Maya is just home from school',
        childBands: bands, actorBands: bands)));
      expect(find.text('Maya is just home from school'), findsOneWidget);
    });
  });

  group('responsive layout — phone, Fold5 (cover + main), and desktop-scale '
      'PC widths', () {
    // MASTERFILE's own mandated minimum widths for this app: the Fold5's
    // cover screen (344 CSS px, the narrowest supported width) and its
    // unfolded main screen (~673x841, nearly square) -- plus a standard
    // phone width and a desktop-scale width now that Windows is a real
    // target (short-and-wide, unlike a tall phone). Same
    // `tester.view.physicalSize` idiom story_library_test.dart and
    // shared_reading_test.dart already use.
    const Map<String, Size> widths = <String, Size>{
      'Fold5 cover (344)': Size(344, 882),
      'Fold5 main (~673x841)': Size(673, 841),
      'phone (390)': Size(390, 844),
      'desktop-scale PC (1100)': Size(1100, 750),
    };

    Future<void> useWidth(WidgetTester t, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }

    for (final MapEntry<String, Size> entry in widths.entries) {
      testWidgets('ChildHome renders without overflow at ${entry.key}',
          (t) async {
        await useWidth(t, entry.value);
        await t.pumpWidget(wrap(const ChildHome(
          childName: 'Maya',
          presence: ParentPresence('Dad', '8:41 PM', '9:30'),
          sleepsUntilHandover: 3, unreadCount: 2)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });

      testWidgets('GuardianHome renders without overflow at ${entry.key}',
          (t) async {
        await useWidth(t, entry.value);
        const List<RibbonBand> bands = <RibbonBand>[
          RibbonBand(0, 0.5, Colors.blue, 'school'),
          RibbonBand(0.5, 0.5, Colors.green, 'home time'),
        ];
        // Longest guardian tile labels ('Message banking', 'Send-time
        // guard', 'Morning briefing') plus a non-null overlapLabel — this
        // is the exact combination that overflowed by 4px at the Fold5
        // cover width before guardian_home.dart's grid grew a
        // LayoutBuilder breakpoint.
        await t.pumpWidget(wrap(const GuardianHome(
          childName: 'Maya', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT',
          actorLocalTime: '3:12 PM CDT',
          childStateSentence: 'Maya is just home from school',
          childBands: bands, actorBands: bands,
          overlapLabel: 'both free 4:00-5:00 PM')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('PIN gate — §8.3', () {
    testWidgets('renders nine keys', (t) async {
      await t.pumpWidget(wrap(PinGate(digits: 4, onComplete: (_) {})));
      expect(find.byType(TextButton), findsNWidgets(9));
    });

    testWidgets('the keypad is SHUFFLED — the child is watching', (t) async {
      final List<String> orders = <String>[];
      for (int i = 0; i < 12; i++) {
        await t.pumpWidget(wrap(PinGate(
            key: ValueKey<int>(i), digits: 4, onComplete: (_) {})));
        orders.add(t
            .widgetList<Text>(find.descendant(
                of: find.byType(TextButton), matching: find.byType(Text)))
            .map((Text w) => w.data!)
            .join());
      }
      // Twelve consecutive identical orders would mean no shuffle at all.
      expect(orders.toSet().length, greaterThan(1));
    });

    testWidgets('shuffle can be disabled for deterministic tests only',
        (t) async {
      await t.pumpWidget(wrap(PinGate(
          digits: 4, shuffle: false, onComplete: (_) {})));
      final String order = t
          .widgetList<Text>(find.descendant(
              of: find.byType(TextButton), matching: find.byType(Text)))
          .map((Text w) => w.data!)
          .join();
      expect(order, '123456789');
    });

    testWidgets('entry fires onComplete at the right length and clears',
        (t) async {
      String? got;
      await t.pumpWidget(wrap(PinGate(
          digits: 4, shuffle: false, onComplete: (String v) => got = v)));
      for (final String d in <String>['1', '2', '3']) {
        await t.tap(find.text(d));
        await t.pump();
      }
      expect(got, isNull, reason: 'must not fire before the full length');
      await t.tap(find.text('4'));
      await t.pump();
      expect(got, '1234');
    });

    testWidgets('no error text is ever shown after a kiosk defeat', (t) async {
      await t.pumpWidget(wrap(PinGate(digits: 4, onComplete: (_) {})));
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('failed'), findsNothing);
      expect(find.textContaining('Incorrect'), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  group('kiosk shell — §5.20', () {
    const child = Text('the unlocked child home');

    Widget shellWith(_FakeKioskChannel ch, {String pin = '1234'}) => wrap(KioskShell(
          channel: ch,
          verifyPin: (String p) async => p == pin,
          child: child,
        ));

    testWidgets('shows the unlocked child surface by default', (t) async {
      await t.pumpWidget(shellWith(_FakeKioskChannel()));
      await t.pumpAndSettle();
      expect(find.byWidget(child), findsOneWidget);
      expect(find.byType(PinGate), findsNothing);
    });

    testWidgets('a lockTaskExited event lands on the PIN gate, never the child surface',
        (t) async {
      final ch = _FakeKioskChannel();
      await t.pumpWidget(shellWith(ch));
      await t.pumpAndSettle();
      ch.emit(KioskChannel.eExited);
      await t.pumpAndSettle();
      expect(find.byType(PinGate), findsOneWidget);
      expect(find.byWidget(child), findsNothing);
    });

    testWidgets('a backgrounded event also lands on the PIN gate', (t) async {
      final ch = _FakeKioskChannel();
      await t.pumpWidget(shellWith(ch));
      await t.pumpAndSettle();
      ch.emit(KioskChannel.eBackground);
      await t.pumpAndSettle();
      expect(find.byType(PinGate), findsOneWidget);
    });

    testWidgets('the correct PIN after a defeat returns to the child surface',
        (t) async {
      final ch = _FakeKioskChannel();
      await t.pumpWidget(shellWith(ch, pin: '5193'));
      await t.pumpAndSettle();
      ch.emit(KioskChannel.eExited);
      await t.pumpAndSettle();
      for (final d in ['5', '1', '9', '3']) {
        await t.tap(find.text(d));
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.byWidget(child), findsOneWidget);
    });

    testWidgets('five wrong PINs lock out — never fabricates an error string',
        (t) async {
      final ch = _FakeKioskChannel();
      await t.pumpWidget(shellWith(ch, pin: '9999'));
      await t.pumpAndSettle();
      ch.emit(KioskChannel.eExited);
      await t.pumpAndSettle();
      for (var attempt = 0; attempt < 5; attempt++) {
        final keys = t
            .widgetList<Text>(find.descendant(
                of: find.byType(TextButton), matching: find.byType(Text)))
            .map((w) => w.data!)
            .toList();
        for (final d in keys.take(4)) {
          await t.tap(find.text(d).first);
          await t.pump();
        }
        await t.pumpAndSettle();
      }
      expect(find.byType(PinGate), findsNothing,
          reason: 'locked_out is a distinct surface from pin_gate');
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('Incorrect'), findsNothing);
      expect(find.text("I'm the grown-up"), findsOneWidget);
    });
  });
}
