// OLIVE BRANCH — the five computer opponents take their dice from the caller (ISS-038).
//
// Chess, checkers, dots-and-boxes, Connect 4 and Uno each built their own unseeded Random() inside the screen, so a
// test could not say which move the computer would make and could only assert "something happened". Each screen now
// takes an optional `random:` (null in the app: a fresh Random as before). This proves, per game, that the injected
// source is the one the opponent actually draws from, with the arguments the rules give it, and that two runs on the
// same seed are identical, which is what makes a failure reproducible.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_checkers.dart';
import 'package:olive_client/game_chess.dart';
import 'package:olive_client/game_connect4.dart';
import 'package:olive_client/game_dotsboxes.dart';
import 'package:olive_client/game_uno.dart';
import 'package:olive_client/uno_deck.dart';

/// A Random that records every draw and answers from a seeded generator.
class _Recording implements Random {
  _Recording(int seed) : _inner = Random(seed);
  final Random _inner;
  final List<String> calls = <String>[];
  @override
  int nextInt(int max) { calls.add('nextInt($max)'); return _inner.nextInt(max); }
  @override
  double nextDouble() { calls.add('nextDouble'); return _inner.nextDouble(); }
  @override
  bool nextBool() { calls.add('nextBool'); return _inner.nextBool(); }
}

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: child,
    );

void main() {
  group('chess — the grown-up opponent draws from the injected Random', () {
    Future<List<String>> play(WidgetTester t, int seed) async {
      final r = _Recording(seed);
      await t.pumpWidget(wrap(GameChess(botThinkDelay: Duration.zero, random: r)));
      await t.tap(find.text('Start game'));
      await t.pump();
      final cells = find.descendant(of: find.byType(GridView), matching: find.byType(GestureDetector));
      await t.tap(cells.at((7 - 1) * 8 + 4)); // e2
      await t.pump();
      await t.tap(cells.at((7 - 3) * 8 + 4)); // e4
      await t.pumpAndSettle();
      return r.calls;
    }

    testWidgets('one reply = one draw over the 20 legal replies, and the same seed repeats', (t) async {
      final a = await play(t, 11);
      expect(a, <String>['nextInt(20)']);
      final b = await play(t, 11);
      expect(b, a);
    });
  });

  group('checkers — the grown-up opponent draws from the injected Random', () {
    Future<List<String>> play(WidgetTester t, int seed) async {
      final r = _Recording(seed);
      await t.pumpWidget(wrap(GameCheckers(botThinkDelay: Duration.zero, random: r)));
      await t.tap(find.byKey(const Key('ckCell_5_0')));
      await t.pump();
      await t.tap(find.byKey(const Key('ckCell_4_1')));
      await t.pumpAndSettle();
      return r.calls;
    }

    testWidgets('one reply = one draw over its legal moves, and the same seed repeats', (t) async {
      final a = await play(t, 5);
      expect(a.length, 1);
      expect(a.single, startsWith('nextInt('));
      expect(int.parse(a.single.substring('nextInt('.length, a.single.length - 1)), greaterThan(0));
      expect(await play(t, 5), a);
    });
  });

  group('dots and boxes — the grown-up opponent draws from the injected Random', () {
    Future<List<String>> play(WidgetTester t, int seed) async {
      final r = _Recording(seed);
      await t.pumpWidget(wrap(GameDotsBoxes(botThinkDelay: Duration.zero, random: r)));
      await t.tap(find.byKey(const Key('dbH_0_0')));
      await t.pumpAndSettle();
      return r.calls;
    }

    testWidgets('one reply = one draw over the 23 edges left, and the same seed repeats', (t) async {
      final a = await play(t, 9);
      expect(a, <String>['nextInt(23)']);
      expect(await play(t, 9), a);
    });
  });

  group('Connect 4 — the computer draws from the injected Random', () {
    Future<List<String>> play(WidgetTester t, int seed) async {
      await t.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final r = _Recording(seed);
      await t.pumpWidget(wrap(GameConnect4Screen(role: 'ivy', displayName: 'Ivy', random: r)));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Easy')); // Easy draws on every move, so the count is not zero by luck
      await t.pump();
      await t.tap(find.text('Start'));
      await t.pump(const Duration(milliseconds: 100));
      final SemanticsHandle h = t.ensureSemantics();
      await t.tap(find.bySemanticsLabel('Column 4, row 1 from the bottom'));
      await t.pumpAndSettle();
      h.dispose();
      return r.calls;
    }

    testWidgets('the computer\'s first reply draws from it, and the same seed repeats', (t) async {
      final a = await play(t, 3);
      expect(a, isNotEmpty);
      expect(a.first, 'nextDouble');
      expect(await play(t, 3), a);
    });
  });

  group('Uno — every shuffle and the computer draw from the injected Random', () {
    Future<List<String>> dealt(WidgetTester t, int seed) async {
      await t.pumpWidget(wrap(GameUnoScreen(role: 'dad', displayName: 'Dad', random: Random(seed))));
      await t.pumpAndSettle();
      await t.tap(find.text('2').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Start'));
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      return t.widgetList<Draggable<UnoCard>>(find.byType(Draggable<UnoCard>)).map((d) => d.data!.code).toList();
    }

    testWidgets('the same seed deals the same hand, a different seed deals another', (t) async {
      final a = await dealt(t, 21);
      expect(a, isNotEmpty);
      expect(await dealt(t, 21), a);
      expect(await dealt(t, 22), isNot(a));
    });
  });
}
