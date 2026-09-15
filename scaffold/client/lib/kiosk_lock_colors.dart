// OLIVE BRANCH — kiosk lock screens' own fixed color palette. No longer
// UNVERIFIED — verified by CI (a Flutter toolchain runs for real in
// tools/verify.sh's automated pipeline).
//
// Deliberately NOT theme.dart's ColorScheme: pin_gate.dart and kiosk_shell.dart's own
// _LockedOutScreen intentionally stay a fixed navy appearance regardless of
// whichever theme palette the family has chosen elsewhere in the app — a
// guardian who needs back in should recognize the same screen on any
// device, independent of a child's own chosen bedroom-tablet color theme.
// Confirmed decision (UI/UX review theme #3, not a default assumed here).
//
// Previously duplicated verbatim, value-for-value, between both files —
// this is the one shared source now, so the two can never quietly drift
// apart from each other again.
import 'package:flutter/material.dart';

class KioskLockColors {
  const KioskLockColors._();
  static const background = Color(0xFF12172B);
  static const primaryText = Colors.white;
  static const secondaryText = Colors.white70;
  static const tertiaryText = Colors.white54;
  static const quaternaryText = Colors.white38;
}
