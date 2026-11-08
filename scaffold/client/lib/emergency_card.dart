// OLIVE BRANCH — emergency card. No longer UNVERIFIED — verified by CI (a Flutter toolchain now
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
// actually for. G-11: the server now versions the card (If-Match style
// `ifMatch`, 409 `stale_version`) and keeps an append-only history; the
// live screen shows "Last changed by X on <date>" from it, and
// OliveApi.putEmergencyCard requires the version, so the future edit
// surface cannot silently overwrite a co-guardian's change.
//
// LOCAL CARD (MASTERFILE section 8.24). Which card is shown, in this order:
//   1. a live build WITH a session (baseUrl/guardianId/childId): the server's card,
//      exactly as above. If the server cannot be reached and a guardian has written
//      a local card, that local card is shown, clearly labelled as saved on this
//      device (it never replaces a card that WAS fetched);
//   2. no session and a local card exists (emergency_card_local.dart, read through
//      [localService] by a guardian [principal]): the local card;
//   3. no session, no local card: the invented demo card ONLY when this run allows
//      demo content (LocalServices.demoSeeds, the offline preview); in a live build a
//      plain "no card yet" page. A live build never shows invented data.
// Without a [localService] nothing local is read and (1) and (3) behave as before.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'a11y_speech.dart' show SpeechTrigger, admitSpeech;
import 'api_client.dart';
import 'auth_session.dart';
import 'design_tokens.dart';
import 'emergency_card_editor_screen.dart';
import 'emergency_card_local.dart';
import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'form_factors.dart' as ff;
import 'local_services.dart' show LocalServices;
import 'read_aloud.dart' show ReadAloudScope;

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

/// Where the card on screen came from.
enum _Src { demo, server, local, none }

class EmergencyCardScreen extends StatefulWidget {
  const EmergencyCardScreen({
    super.key,
    this.speak,
    this.childName = 'Ivy',
    this.baseUrl,
    this.guardianId,
    this.childId,
    this.httpClient,
    this.localService,
    this.principal,
  });

  /// Real wiring is tts_channel.dart's buildSpeakCallback(). Null means no
  /// read-aloud affordance exists — an honest absence, not a silent no-op.
  final Future<void> Function(String text)? speak;
  final String childName;
  final String? baseUrl;
  final String? guardianId;
  final String? childId;
  final http.Client? httpClient;

  /// The local card (guardian-written, on this device) and the guardian reading
  /// it. Both null: no local card is read.
  final EmergencyCardService? localService;
  final FamilyPrincipal? principal;

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
  // G-11: who last changed the card. Null before any write. (The card's
  // `version` is deliberately not kept: this screen has no edit surface to
  // send it back from — see OliveApi.putEmergencyCard's `ifMatch`.)
  String? _lastChangedBy, _lastChangedAt;
  List<String> _conditions = <String>[];
  _Src _src = _Src.demo;
  bool _localAsFallback = false;

  // The server's card lists the guardians and a pediatrician; a guardian's own card lists
  // whoever they wrote as contacts and a doctor, so it says that.
  String get _contactsTitle => _src == _Src.local ? 'Contacts' : 'Guardians';
  String get _doctorTitle => _src == _Src.local ? 'Doctor' : 'Pediatrician';

  bool get _canEditLocal => widget.localService != null && canEditStructure(widget.principal);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(EmergencyCardScreen old) {
    super.didUpdateWidget(old);
    // A screen re-used for a different source (live <-> not) starts over, so nothing from the
    // earlier source (an author line, a fetched card) lingers.
    if (old._isLive != widget._isLive || old.localService != widget.localService) {
      _lastChangedBy = _lastChangedAt = null;
      _localAsFallback = false;
      _loadState = _LoadState.ready;
      _start();
    }
  }

  void _start() {
    if (widget._isLive) {
      _src = _Src.server;
      _load();
    } else if (widget.localService != null) {
      _loadState = _LoadState.loading;
      _loadLocal();
    } else {
      _src = LocalServices.current.demoSeeds ? _Src.demo : _Src.none;
    }
  }

  /// The guardian's local card, or null (none written, or not a guardian).
  Future<EmergencyCardDoc?> _readLocal() async {
    final EmergencyCardService? s = widget.localService;
    if (s == null) return null;
    try {
      final EmergencyCardDoc d = await s.read(widget.principal);
      final LocalEmergencyCard? c = d.card;
      return c == null || c.isEmpty ? null : d;
    } catch (_) {
      return null;
    }
  }

  void _applyLocal(EmergencyCardDoc d) {
    final LocalEmergencyCard c = d.card!;
    _bloodType = null;
    _allergies = c.allergies;
    _conditions = c.conditions;
    _medications = <_LiveMedLine>[for (final EcMedicine m in c.medicines) _LiveMedLine(m.name, m.dose)];
    _guardians = <_LiveGuardian>[
      for (final EcContact x in c.contacts)
        _LiveGuardian(x.relation.isEmpty ? x.name : '${x.name}, ${x.relation}', x.phone.isEmpty ? null : x.phone),
    ];
    _pediatricianName = c.doctor.name.isEmpty ? null : c.doctor.name;
    _pediatricianPractice = c.doctor.practice.isEmpty ? null : c.doctor.practice;
    _pediatricianPhone = c.doctor.phone.isEmpty ? null : c.doctor.phone;
    _insuranceProvider = null;
    _insuranceMemberId = null;
    final EcChange? last = d.history.isEmpty ? null : d.history.last;
    _lastChangedBy = last?.byName;
    _lastChangedAt = last?.at;
  }

  Future<void> _loadLocal() async {
    final EmergencyCardDoc? d = await _readLocal();
    if (!mounted) return;
    setState(() {
      if (d != null) {
        _applyLocal(d);
        _src = _Src.local;
      } else {
        _src = LocalServices.current.demoSeeds ? _Src.demo : _Src.none;
      }
      _loadState = _LoadState.ready;
    });
  }

  Future<void> _editLocal() async {
    final bool? saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => EmergencyCardEditorScreen(
            service: widget.localService!, principal: widget.principal, childName: widget.childName)));
    if (saved == true && !widget._isLive) await _loadLocal();
  }

  /// The ONLY place this screen calls the network — mirrors meds_care.dart's
  /// own self-fetching pattern. A failure here is a real, honest error
  /// state with a retry affordance, never a silent fall-back to the demo
  /// fixtures.
  Future<void> _load() async {
    setState(() => _loadState = _LoadState.loading);
    try {
      final OliveApi api = await apiFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
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
        final Map<String, dynamic>? change = result['lastChange'] as Map<String, dynamic>?;
        _lastChangedBy = change?['byName'] as String?;
        _lastChangedAt = change?['at'] as String?;
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      final EmergencyCardDoc? local = await _readLocal();
      if (!mounted) return;
      setState(() {
        if (local != null) {
          // Could not reach the server: the guardian's own card, labelled as such.
          _applyLocal(local);
          _src = _Src.local;
          _localAsFallback = true;
          _loadState = _LoadState.ready;
        } else {
          _loadState = _LoadState.error;
        }
      });
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
    if (_conditions.isNotEmpty) b.write('Conditions: ${_conditions.join('. ')}. ');
    if (_medications.isNotEmpty) {
      b.write('Current medications: ');
      b.write(_medications.map((_LiveMedLine m) => '${m.name}, ${m.schedule}').join('. '));
      b.write('. ');
    }
    if (_guardians.isNotEmpty) {
      b.write('$_contactsTitle: ');
      b.write(_guardians.map((_LiveGuardian g) =>
        g.phone == null ? g.name : '${g.name}, ${g.phone}').join('. '));
      b.write('. ');
    }
    if (_pediatricianName != null) {
      b.write('$_doctorTitle: $_pediatricianName');
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
    // The screen's own callback if it was given one, else the app's read-aloud
    // (access_shell.dart). Null only with neither: then it says so honestly.
    final Future<void> Function(String)? speak = widget.speak ?? ReadAloudScope.speakFnOf(context);
    if (speak == null) {
      _notBuiltYet(context, 'Read aloud');
      return;
    }
    // Real check, not just documentation: every speak() call in this
    // codebase routes through admitSpeech() first, so a future caller that
    // ever passes SpeechTrigger.autonomous here is refused for real, not
    // just by convention.
    if (admitSpeech(SpeechTrigger.tap) != null) return;
    speak(switch (_src) {
      _Src.demo => _cardSpokenText,
      _Src.none => 'No emergency card has been written yet.',
      _ => _liveSpokenText(),
    });
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
      if (_canEditLocal && _src != _Src.server)
        IconButton(
          key: const Key('editLocalCard'),
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Write or change the card',
          onPressed: _editLocal,
        ),
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
      final Widget content = _src == _Src.none
        ? _NoCardYet(canWrite: _canEditLocal, onWrite: _editLocal)
        : _src != _Src.demo
        ? ListView(
            key: const Key('emergencyCardList'),
            padding: const EdgeInsets.all(16),
            children: [
              if (_src == _Src.local) ...[
                Text(key: const Key('localCardNote'),
                  _localAsFallback
                    ? "Couldn't reach the server, so this is the card saved on this device."
                    : 'This is the card a guardian saved on this device.',
                  style: TextStyle(fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
              ],
              _AllergyCard(allergies: _allergies),
              const SizedBox(height: 20),
              if (_conditions.isNotEmpty) ...[
                _Section(title: 'Conditions', child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final String c in _conditions)
                      Padding(padding: const EdgeInsets.only(bottom: 4),
                        child: Text(c, style: const TextStyle(fontSize: 18))),
                  ])),
                const SizedBox(height: 20),
              ],
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
                _Section(title: _contactsTitle, child: Column(
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
                _Section(title: _doctorTitle, child: _ContactLine(
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
              // G-11 — who last changed this card, from the append-only
              // history. Absent (not a made-up name) before the first write.
              if (_lastChangedAt != null) ...[
                const SizedBox(height: 8),
                Text(key: const Key('lastChangedBy'),
                  'Last changed by ${_lastChangedBy ?? 'a guardian'} on '
                  '${_lastChangedAt!.split('T').first}',
                  style: TextStyle(fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

/// Shown in a live build when there is no card at all: never invented data.
class _NoCardYet extends StatelessWidget {
  const _NoCardYet({required this.canWrite, required this.onWrite});
  final bool canWrite;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.medical_information_outlined, size: 40,
        color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(height: 12),
      Text('No emergency card has been written yet.', key: const Key('noCardYet'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      if (canWrite) ...[
        const SizedBox(height: 16),
        FilledButton(key: const Key('writeLocalCard'), onPressed: onWrite,
          child: const Text('Write the emergency card')),
      ],
    ]),
  ));
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
      child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child:
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
