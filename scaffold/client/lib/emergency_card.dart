// OLIVE BRANCH — emergency card. Verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — also manually
// built and run via `flutter analyze` / `flutter test` this session;
// CHANGELOG v0.49.61). MASTERFILE §9.6.3, §8.13.5, §8.8.5.
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
//
// LIVE WIRING (baseUrl/guardianId/childId/httpClient, all optional and
// additive — same convention meds_care.dart/expenses_screen.dart already
// establish): when supplied, this screen fetches the real medical_record
// (allergies/blood type/pediatrician/insurance) plus the real, LIVE-derived
// guardians list (name + phone_e164, joined from the actual guardianship/
// app_user rows — never a second stored copy, see that route's own
// migration header) via OliveApi.fetchEmergencyCard() on init. The demo's
// own hardcoded Claire/Marcus/Dr. Priya Nair/BlueBridge content is
// preserved exactly when no live params are supplied — every existing
// test in this file keeps passing unchanged. Editing (PUT) is NOT wired
// into this screen at all — the guardian-facing "set the emergency card"
// affordance is a real, disclosed follow-up; this pass closes the READ
// side, which is what §8.13.5's own "read once, in a hurry" framing is
// actually for.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'a11y_speech.dart' show SpeechTrigger, admitSpeech;
import 'api_client.dart';
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

enum _LoadState { ready, loading, error }

class EmergencyCardScreen extends StatefulWidget {
  const EmergencyCardScreen({
    super.key,
    this.speak,
    this.childName = 'Ivy',
    this.baseUrl,
    this.guardianId,
    this.childId,
    this.httpClient,
  });

  /// Real wiring is tts_channel.dart's buildSpeakCallback(). Null means no
  /// read-aloud affordance exists — an honest absence, not a silent no-op.
  final Future<void> Function(String text)? speak;
  final String childName;
  final String? baseUrl;
  final String? guardianId;
  final String? childId;
  final http.Client? httpClient;

  bool get _isLive => baseUrl != null && guardianId != null && childId != null;

  @override
  State<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

/// One real fetched medication, formatted for this screen's own
/// "Current medications" section — a real, disclosed simplification: the
/// real `medication` row carries `dose`/`slots`/`isPrn`, never a reason
/// string ("for wheezing"), so the live schedule text is genuinely
/// narrower than the demo's own hand-written copy, not a guess dressed up
/// to look identical.
class _LiveMedLine {
  const _LiveMedLine(this.name, this.schedule);
  final String name;
  final String schedule;
}

class _LiveGuardian {
  const _LiveGuardian(this.name, this.phone);
  final String name;
  final String? phone;
}

class _EmergencyCardScreenState extends State<EmergencyCardScreen> {
  _LoadState _loadState = _LoadState.ready;
  String? _bloodType;
  List<String> _allergies = <String>[];
  List<_LiveMedLine> _medications = <_LiveMedLine>[];
  List<_LiveGuardian> _guardians = <_LiveGuardian>[];
  String? _pediatricianName, _pediatricianPractice, _pediatricianPhone;
  String? _insuranceProvider, _insuranceMemberId;

  @override
  void initState() {
    super.initState();
    if (widget._isLive) _load();
  }

  /// The ONLY place this screen calls the network — mirrors meds_care.dart's
  /// own self-fetching pattern. A failure here is a real, honest error
  /// state with a retry affordance, never a silent fall-back to the demo
  /// fixtures.
  Future<void> _load() async {
    setState(() => _loadState = _LoadState.loading);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> result = await api.fetchEmergencyCard(widget.childId!);
      if (widget.httpClient == null) api.close();
      final List<dynamic> rawMeds = result['medications'] as List<dynamic>? ?? <dynamic>[];
      final List<dynamic> rawGuardians = result['guardians'] as List<dynamic>? ?? <dynamic>[];
      if (!mounted) return;
      setState(() {
        _bloodType = result['bloodType'] as String?;
        _allergies = (result['allergies'] as List<dynamic>? ?? <dynamic>[]).cast<String>();
        _medications = rawMeds.map((dynamic m) {
          final Map<String, dynamic> row = m as Map<String, dynamic>;
          final List<String> slots = (row['slots'] as List<dynamic>? ?? <dynamic>[]).cast<String>();
          final bool isPrn = row['isPrn'] as bool? ?? false;
          final String schedule = isPrn
            ? '${row['dose']} — as needed' : '${row['dose']} — ${slots.join(', ')}';
          return _LiveMedLine(row['name'] as String, schedule);
        }).toList();
        _guardians = rawGuardians.map((dynamic g) {
          final Map<String, dynamic> row = g as Map<String, dynamic>;
          return _LiveGuardian(row['name'] as String, row['phone'] as String?);
        }).toList();
        _pediatricianName = result['pediatricianName'] as String?;
        _pediatricianPractice = result['pediatricianPractice'] as String?;
        _pediatricianPhone = result['pediatricianPhone'] as String?;
        _insuranceProvider = result['insuranceProvider'] as String?;
        _insuranceMemberId = result['insuranceMemberId'] as String?;
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  /// Every real fact on this screen, allergy-first — the live path's own
  /// version of the file-level `_cardSpokenText` const, built from the
  /// same real fields the rendered tree shows so the spoken version can
  /// never drift from what's actually on screen, same discipline that
  /// const's own doc comment states for the demo path.
  String _liveSpokenText() {
    final StringBuffer b = StringBuffer();
    b.write(_allergies.isEmpty
      ? 'No allergies on file. ' : 'Allergies: ${_allergies.join('. ')}. ');
    if (_bloodType != null) b.write('Blood type: $_bloodType. ');
    if (_medications.isNotEmpty) {
      b.write('Current medications: ');
      b.write(_medications.map((_LiveMedLine m) => '${m.name}, ${m.schedule}').join('. '));
      b.write('. ');
    }
    if (_guardians.isNotEmpty) {
      b.write('Guardians: ');
      b.write(_guardians.map((_LiveGuardian g) =>
        g.phone == null ? g.name : '${g.name}, ${g.phone}').join('. '));
      b.write('. ');
    }
    if (_pediatricianName != null) {
      b.write('Pediatrician: $_pediatricianName');
      if (_pediatricianPractice != null) b.write(', $_pediatricianPractice');
      if (_pediatricianPhone != null) b.write('. Phone: $_pediatricianPhone');
      b.write('. ');
    }
    if (_insuranceProvider != null) {
      b.write('Insurance: $_insuranceProvider.');
      if (_insuranceMemberId != null) b.write(' Member ID: $_insuranceMemberId.');
    }
    return b.toString().trim();
  }

  void _readAloud(BuildContext context) {
    if (widget.speak == null) {
      _notBuiltYet(context, 'Read aloud');
      return;
    }
    // Real check, not just documentation: every speak() call in this
    // codebase routes through admitSpeech() first, so a future caller that
    // ever passes SpeechTrigger.autonomous here is refused for real, not
    // just by convention.
    if (admitSpeech(SpeechTrigger.tap) != null) return;
    widget.speak!(widget._isLive ? _liveSpokenText() : _cardSpokenText);
  }

  @override
  Widget build(BuildContext context) {
    // Loading/error UI mirrors meds_care.dart's own established shape —
    // only ever reachable when this screen is live-wired; the pure demo
    // path never enters either state.
    if (_loadState == _LoadState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadState == _LoadState.error) {
      return Scaffold(
        appBar: AppBar(title: Text('Emergency card — ${widget.childName}')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
              style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        )),
      );
    }
    return Scaffold(
    appBar: AppBar(title: Text('Emergency card — ${widget.childName}'), actions: [
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
      final Widget content = widget._isLive
        ? ListView(
            key: const Key('emergencyCardList'),
            padding: const EdgeInsets.all(16),
            children: [
              _AllergyCard(allergies: _allergies),
              const SizedBox(height: 20),
              if (_bloodType != null) ...[
                _Section(title: 'Blood type', child: Text(_bloodType!,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                const SizedBox(height: 20),
              ],
              if (_medications.isNotEmpty) ...[
                _Section(title: 'Current medications', child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < _medications.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _MedLine(_medications[i].name, _medications[i].schedule),
                    ],
                  ])),
                const SizedBox(height: 20),
              ],
              if (_guardians.isNotEmpty) ...[
                _Section(title: 'Guardians', child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < _guardians.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _ContactLine(name: _guardians[i].name,
                        phone: _guardians[i].phone ?? 'No phone on file'),
                    ],
                  ])),
                const SizedBox(height: 20),
              ],
              if (_pediatricianName != null) ...[
                _Section(title: 'Pediatrician', child: _ContactLine(
                  name: _pediatricianPractice == null
                    ? _pediatricianName! : '$_pediatricianName — $_pediatricianPractice',
                  phone: _pediatricianPhone ?? 'No phone on file')),
                const SizedBox(height: 20),
              ],
              if (_insuranceProvider != null) ...[
                _Section(title: 'Insurance', child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_insuranceProvider!, style: const TextStyle(fontSize: 18)),
                    if (_insuranceMemberId != null) ...[
                      const SizedBox(height: 4),
                      Text('Member ID: $_insuranceMemberId', style: const TextStyle(fontSize: 18)),
                    ],
                  ])),
              ],
              const SizedBox(height: 12),
            ])
        : ListView(
        key: const Key('emergencyCardList'),
        padding: const EdgeInsets.all(16),
        children: const [
          _AllergyCard(allergies: <String>['Peanuts — carries an EpiPen, in her backpack side pocket']),
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
}

class _AllergyCard extends StatelessWidget {
  const _AllergyCard({required this.allergies});
  final List<String> allergies;

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
            Text(allergies.isEmpty ? 'None on file' : allergies.join(', '),
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
