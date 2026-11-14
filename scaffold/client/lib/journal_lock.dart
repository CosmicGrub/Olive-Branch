// OLIVE BRANCH — the code that locks her journal. No longer UNVERIFIED — verified by CI
// (client/test/journal_lock_test.dart). Prototype k.journal / kid.jKey / kid.jLockOn / kid.jUnlockOff;
// parity rows 316 and 317; MASTERFILE section 5.12 (P7).
//
// HERS, AND ONLY HERS. From her thirteenth birthday (the ladder's `journalAbsolute` rung) a child may put a
// four-number code on her journal. Nothing here ever involves a grown-up:
//   - the code is chosen on her own device, by her, twice (the second time confirms the first);
//   - it is kept only as a salted slow hash (PBKDF2-HMAC-SHA256, the same routine as the local PIN, with the same
//     5 wrong tries then a 15 minute rest), inside the journal's own SEALED area, so a copy of the app's files
//     holds neither the pages nor the code (the prototype kept the code as plain text; this does not);
//   - there is no reader, role or guardian argument anywhere in this file (P7), and no reset a grown-up can reach:
//     if she forgets it, the only way out is to start a new journal, and the old pages go for good. She is told so
//     before she does it.
//
// THIS IS NOT A PIN FLOW. The standing decision (adults set all PINs on adult devices; a child device only shows the
// calm "a grown-up does this" card) is about the GROWN-UP's PIN. This is the child's own journal code, the way a
// diary has a clasp; it unlocks nothing but her own pages and is never sent anywhere.
//
// Child wording (P1): a wrong code just empties the four dots, with no message and no count. The 15 minute rest
// is a calm "let's try again in a little while", never an error.
import 'dart:math';

import 'package:flutter/material.dart';

import 'access_settings.dart' show kChildTarget;
import 'local_pin.dart';
import 'local_services.dart';

/// Her journal can be locked from this age (the ladder's `journalAbsolute` rung).
const int kJournalLockAge = 13;

/// The code is exactly this many numbers.
const int kJournalCodeLength = 4;

final RegExp _codeShape = RegExp(r'^\d{4}$');

bool isJournalCode(String s) => _codeShape.hasMatch(s);

/// What the journal's lock says to a try.
enum JournalOpen { opened, wrong, resting, notLocked }

class JournalLock {
  JournalLock(this._svc);

  /// The lock for [childId]'s journal (default: this device's child), kept in the journal's own sealed area.
  factory JournalLock.forChild({String? childId, int iterations = kLocalPinIterations, DateTime Function()? now, Random? random}) =>
      JournalLock(LocalPinService(
          LocalStoreLocalPinRepository(LocalServices.current.area('journal', ownerId: childId)),
          iterations: iterations, now: now, random: random));

  final LocalPinService _svc;

  Future<bool> isOn() => _svc.isSet();

  /// Puts the lock on with [code] (four numbers). Throws [ArgumentError] for anything else and whatever the store
  /// throws when it cannot be written, so the screen never says "locked" for a lock that was not kept.
  Future<void> turnOn(String code) {
    if (!isJournalCode(code)) throw ArgumentError('A journal code is $kJournalCodeLength numbers.');
    return _svc.setPin(code);
  }

  Future<JournalOpen> tryOpen(String code) async {
    final PinCheck c = await _svc.verify(code);
    return switch (c.outcome) {
      PinOutcome.ok => JournalOpen.opened,
      PinOutcome.wrong => JournalOpen.wrong,
      PinOutcome.locked => JournalOpen.resting,
      PinOutcome.notSet => JournalOpen.notLocked,
    };
  }

  /// Takes the lock off. Only her open journal screen offers this, so it needs no code: she is already inside.
  Future<void> turnOff() => _svc.clear();
}

/// The four dots and the ten keys. A pure input widget: it hands each finished code to [onCode] and then empties
/// itself, whatever the answer was (a wrong code looks exactly like a fresh start).
class JournalCodePad extends StatefulWidget {
  const JournalCodePad({super.key, required this.title, required this.sub, required this.onCode});
  final String title;
  final String sub;

  /// Called with exactly [kJournalCodeLength] digits.
  final Future<void> Function(String code) onCode;

  @override
  State<JournalCodePad> createState() => _JournalCodePadState();
}

class _JournalCodePadState extends State<JournalCodePad> {
  String _code = '';
  bool _busy = false;

  Future<void> _press(String d) async {
    if (_busy || _code.length >= kJournalCodeLength) return;
    setState(() => _code += d);
    if (_code.length < kJournalCodeLength) return;
    final String done = _code;
    setState(() => _busy = true);
    try {
      await widget.onCode(done);
    } finally {
      if (mounted) {
        setState(() {
          _code = '';
          _busy = false;
        });
      }
    }
  }

  void _back() {
    if (_busy || _code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    Widget key(String d) => SizedBox(
        height: kChildTarget + 8,
        child: FilledButton.tonal(
            key: Key('journalKey$d'),
            onPressed: () => _press(d),
            child: Text(d, style: text.headlineSmall)));
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Icon(Icons.lock_outline, size: 56, color: scheme.primary),
      const SizedBox(height: 12),
      Text(widget.title, style: text.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(widget.sub, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      // Four dots: filled as she goes. The dots say how many she has put in, nothing else.
      Semantics(
          label: '${_code.length} of $kJournalCodeLength entered',
          child: ExcludeSemantics(
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            for (int i = 0; i < kJournalCodeLength; i++)
              Container(
                  key: Key('journalDot$i'),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _code.length ? scheme.primary : Colors.transparent,
                      border: Border.all(color: scheme.primary, width: 2))),
          ]))),
      const SizedBox(height: 16),
      ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(children: <Widget>[
            for (final List<String> row in const <List<String>>[<String>['1', '2', '3'], <String>['4', '5', '6'], <String>['7', '8', '9']])
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: <Widget>[
                    for (final String d in row) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: key(d))),
                  ])),
            Row(children: <Widget>[
              const Expanded(child: SizedBox.shrink()),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: key('0'))),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(
                          height: kChildTarget + 8,
                          child: IconButton(
                              key: const Key('journalKeyBack'),
                              tooltip: 'Take one back',
                              onPressed: _back,
                              icon: const Icon(Icons.backspace_outlined, size: 26))))),
            ]),
          ])),
    ]);
  }
}
