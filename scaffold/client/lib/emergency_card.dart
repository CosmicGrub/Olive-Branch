// OLIVE BRANCH — emergency card. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.6.3, §8.13.5.
//
// One screen, no navigation, no motion. §8.13.5 calls this a "still" surface:
// read once, in a hurry, possibly by a frightened child or a sitter who has
// never opened this app before. Allergies sit in a bordered card above every
// other section (§9.6.3) so the single fact that can kill someone is the
// first thing a scanning eye lands on, not the last thing found by scrolling.
import 'package:flutter/material.dart';

/// Same "recorded, not glossed over" pattern as child_home.dart's helper —
/// copied locally since it's private to that file.
void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class EmergencyCardScreen extends StatelessWidget {
  const EmergencyCardScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Emergency card — Ivy')),
    // ListView, not a fixed Column: generous text at this size can exceed a
    // small phone's viewport. The allergy card is still first in the tree, so
    // it's on screen before any scrolling on every device this ships to.
    body: SafeArea(child: ListView(
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
      ])),
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
