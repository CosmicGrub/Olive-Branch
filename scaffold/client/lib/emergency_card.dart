// OLIVE BRANCH — emergency card. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.6.3,
// §8.13.5, §8.8.5.
//
// One screen, no navigation, no motion. §8.13.5 calls this a "still" surface:
// read once, in a hurry, possibly by a frightened child or a sitter who has
// never opened this app before. Allergies sit in a bordered card above every
// other section (§9.6.3) so the single fact that can kill someone is the
// first thing a scanning eye lands on, not the last thing found by scrolling.
//
// §8.8.5 read-aloud: the AppBar's speaker action reads this exact card back
// in the same allergy-first order a scanning eye would read it, verbatim —
// no summarizing, no rephrasing. Tap-gated only (admitSpeech(tap), never
// autonomous — see a11y_speech.dart's own header for why), because a sitter
// under real pressure benefits from hearing it, not from it talking at her
// unprompted. Absent [speak], the button reports itself honestly rather than
// pretending — same posture as the Call buttons below.
import 'package:flutter/material.dart';
import 'a11y_speech.dart' show SpeechTrigger, admitSpeech;
import 'form_factors.dart' as ff;

/// Same "recorded, not glossed over" pattern as child_home.dart's helper —
/// copied locally since it's private to that file.
void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

/// Every fact on this screen, concatenated in the exact allergy-first reading
/// order the layout already enforces — a single source of truth so the
/// spoken version can never drift from what's actually shown on screen.
const String _cardSpokenText =
    'Allergies: Peanuts. Carries an EpiPen, in her backpack side pocket. '
    'Blood type: O positive. '
    'Current medications: Cetirizine, 5 milligrams, once daily in the evening. '
    'Albuterol inhaler, 2 puffs, as needed for wheezing. '
    "Guardians: Mom, Claire Solomon, (617) 555-0142. "
    "Dad, Marcus Solomon, (617) 555-0198. "
    'Pediatrician: Doctor Priya Nair, Riverbend Pediatrics, (617) 555-0177. '
    'Insurance: BlueBridge Family Health. Member ID: BBH-7734-2201.';

class EmergencyCardScreen extends StatelessWidget {
  const EmergencyCardScreen({super.key, this.speak});

  /// Real wiring is tts_channel.dart's buildSpeakCallback(). Null means no
  /// read-aloud affordance exists — an honest absence, not a silent no-op.
  final Future<void> Function(String text)? speak;

  void _readAloud(BuildContext context) {
    if (speak == null) {
      _notBuiltYet(context, 'Read aloud');
      return;
    }
    // Real check, not just documentation: every speak() call in this
    // codebase routes through admitSpeech() first, so a future caller that
    // ever passes SpeechTrigger.autonomous here is refused for real, not
    // just by convention.
    if (admitSpeech(SpeechTrigger.tap) != null) return;
    speak!(_cardSpokenText);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Emergency card — Ivy'), actions: [
      IconButton(
        key: const Key('readAloudButton'),
        icon: const Icon(Icons.volume_up_outlined),
        tooltip: 'Read this card aloud',
        onPressed: () => _readAloud(context),
      ),
    ]),
    // §8.13.5 "still" surface, read once, possibly in a hurry (see file
    // header). On a wide tablet/desktop viewport the single column is only
    // ever capped to a comfortable reading width and centered, never split —
    // the allergy-first scan order below is completely untouched, byte for
    // byte, by this width-only wrapper. Same real columnsAt() gate every
    // other width decision in the app uses.
    body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final double textScale = MediaQuery.textScalerOf(context).scale(1);
      final bool capWidth = ff.columnsAt(
          ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
      // ListView, not a fixed Column: generous text at this size can exceed a
      // small phone's viewport. The allergy card is still first in the tree, so
      // it's on screen before any scrolling on every device this ships to.
      final Widget content = ListView(
        key: const Key('emergencyCardList'),
        padding: const EdgeInsets.all(16),
        children: const [
          _AllergyCard(),
          SizedBox(height: 20),
          _Section(title: 'Blood type', child: Text('O positive',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          SizedBox(height: 20),
          _Section(title: 'Current medications', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MedLine('Cetirizine', '5 mg — once daily, evening'),
              SizedBox(height: 8),
              _MedLine('Albuterol inhaler', '2 puffs — as needed for wheezing'),
            ])),
          SizedBox(height: 20),
          _Section(title: 'Guardians', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ContactLine(name: 'Mom — Claire Solomon', phone: '(617) 555-0142'),
              SizedBox(height: 10),
              _ContactLine(name: 'Dad — Marcus Solomon', phone: '(617) 555-0198'),
            ])),
          SizedBox(height: 20),
          _Section(title: 'Pediatrician', child:
            _ContactLine(name: 'Dr. Priya Nair — Riverbend Pediatrics', phone: '(617) 555-0177')),
          SizedBox(height: 20),
          _Section(title: 'Insurance', child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BlueBridge Family Health', style: TextStyle(fontSize: 18)),
              SizedBox(height: 4),
              Text('Member ID: BBH-7734-2201', style: TextStyle(fontSize: 18)),
            ])),
          SizedBox(height: 12),
        ]);
      return capWidth
          ? Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                  child: content))
          : content;
    })),
  );
}

class _AllergyCard extends StatelessWidget {
  const _AllergyCard();

  @override
  Widget build(BuildContext context) {
    // Theme error roles, not raw Colors.red: matches the same "red literal
    // -> theme role" fix applied elsewhere this pass (game_battleship.dart's
    // hit cells, exchange_screen.dart's essential-item marker) and keeps
    // this card legible in dark theme, where a fixed light-pink background
    // with near-black text would otherwise fight the surrounding surface —
    // the opposite of "fast to read in a hurry" this file exists for.
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('allergyCard'),
      color: scheme.errorContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.error, width: 3)),
      child: Padding(padding: const EdgeInsets.all(16), child:
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_rounded, color: scheme.error, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ALLERGIES', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              color: scheme.onErrorContainer, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Text('Peanuts — carries an EpiPen, in her backpack side pocket',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                color: scheme.onErrorContainer)),
          ])),
        ])),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
        letterSpacing: 0.5, color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 6),
      child,
    ]);
}

class _MedLine extends StatelessWidget {
  const _MedLine(this.name, this.dose);
  final String name, dose;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      Text(dose, style: const TextStyle(fontSize: 15)),
    ]);
}

// A plain, honestly-non-functional Call icon (§9.6.3) — no dialer bridge
// exists in this preview build, so it reports itself rather than pretending.
class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.name, required this.phone});
  final String name, phone;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      Text(phone, style: const TextStyle(fontSize: 18)),
    ])),
    IconButton(
      icon: const Icon(Icons.call),
      tooltip: 'Call $name',
      onPressed: () => _notBuiltYet(context, 'Calling $name')),
  ]);
}
