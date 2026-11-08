// OLIVE BRANCH — shared helpers for the Rhythm and Voice widget tests. Not a
// test file itself (no main): it is imported by rhythm_screens_test.dart,
// voice_screens_test.dart, rhythm_voice_guardian_screens_test.dart and
// rhythm_voice_sections_test.dart.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';

const FamilyPrincipal guardian = FamilyPrincipal(roleName: 'guardian', userId: 'g1');
const FamilyPrincipal ivy = FamilyPrincipal(roleName: 'child', childId: 'ivy');

/// A 1x1 PNG, enough to be a real image the checks accept.
final List<int> tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

RhythmVoiceService freshService() => RhythmVoiceService.memory(childId: 'ivy', clock: () => DateTime(2026, 11, 8, 19));

Routine bedtime() => addStep(
    addStep(addStep(const Routine(title: 'Bedtime'), newStep('a', 'bath')), newStep('b', 'pyjamas')),
    newStep('c', 'book'));

/// A fresh MaterialApp every time (a new key), so re-pumping really starts over:
/// no State, pushed route or queued snack bar survives from an earlier pump.
Widget app(Widget child, {double textScale = 1.0}) => MaterialApp(
      key: UniqueKey(),
      home: child,
      builder: (BuildContext c, Widget? w) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)), child: w!),
    );

/// Sizes the test surface to a phone cover screen (344dp wide) by default.
Future<void> phone(WidgetTester t, {double w = 344, double h = 900}) async {
  await t.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

double heightOf(WidgetTester t, Finder f) => t.getSize(f).height;
