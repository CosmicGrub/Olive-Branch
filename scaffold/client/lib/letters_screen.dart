// OLIVE BRANCH — child shell, letters to her future self. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline). MASTERFILE
// §21.4, §21.8. Renders MARKUP screen 'letters'.
//
// A 1:1 semantic port of the letter functions in
// packages/maturation/src/maturation.ts (sealLetter / openLetter /
// deleteLetter / lettersDue), kept close to the TS originals so the two stay
// auditable side by side — same discipline lock_controller.dart already
// applies to lock.ts.
//
// Three invariants this file holds, straight from the TS doc comments:
//   - `preserved` has no setter and no false state. A letter on a retention
//     clock is a lost letter, and there is no configuration where that is
//     acceptable (§21.4).
//   - NOBODY can open a sealed letter early — not a guardian (there is no
//     guardian code path in this file at all) and not her, either. Sealing
//     is only meaningful if even the author can't peek.
//   - She CAN delete a letter without ever having read it — it is hers
//     (§2.10) — but delete is the only early exit; read never is.
//
// One deliberate adaptation from the TS shape: the REAL backend
// (db/migrations/0028_care_note_letter.sql) stores `body` directly on the
// `letter` table rather than routing it through `media_artifact` the way
// maturation.ts's own `Letter.artifactId` field speculates — that table's
// retention/preservation model assumes a guardian explicitly preserves
// something that would otherwise expire, and a letter has no guardian
// preserver and is never on a retention clock at all ("It gets kept
// forever," this screen's own copy). See that migration's own header for
// the full account. `Letter.body` below is nullable for exactly this
// reason: the server never sends real text for a letter this session
// hasn't opened, structurally, so `null` here is an honest "not fetched
// yet," never a placeholder.
//
// LIVE WIRING (baseUrl/sessionToken/httpClient, optional and additive):
// reached through child_home.dart -> child_more.dart, both of which
// already carry these three from ONE real child login
// (child_home_live.dart's own `_load()`) — this screen reuses that
// already-authenticated session directly rather than minting its own via
// devLoginFor(), the same established pattern homework_screen.dart/
// capture_gate.dart already use for a live screen reached through this
// exact chain. There is no guardianId anywhere in this wiring, matching
// this file's own "no guardian code path" invariant. When supplied, this
// screen fetches her real letters via OliveApi.fetchLetters() on init,
// seals via OliveApi.sealLetter(), opens via OliveApi.openLetter(), and
// deletes via OliveApi.deleteLetter(). `writtenAtAge` is NEVER sent by
// this client on seal, and no age is ever sent on open at all — the server
// computes her real current age itself from her real birth_date every
// time, never trusted from here (server/routes.mjs's own route comments
// have the full account). A 409 `not_yet`/`already_open` open response is
// shown as a real, honest message rather than silently retried or hidden —
// the UI only ever offers "Open it" once client-side age math already
// agrees it should be ready, so this path is a genuine defensive fallback
// for a stale client or a real race, not the normal case.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'form_factors.dart' as ff;

// ============ ported from packages/maturation/src/maturation.ts (letters) ==
enum SealError { tooSoon, tooFar, notYet, alreadyOpen }

const minSealYears = 1;
const maxSealToAge = 25;

class Letter {
  const Letter({
    required this.id,
    required this.childId,
    required this.writtenAtAge,
    required this.openAtAge,
    required this.writtenAt,
    required this.body,
    this.openedAt,
  });
  final String id;
  final String childId;
  final int writtenAtAge;
  final int openAtAge;
  final DateTime writtenAt;
  /// Nullable — see file header. The demo path always carries a real
  /// string; the live path only ever does once `openedAt` is non-null,
  /// since the server never sends real text for a letter this session
  /// hasn't opened.
  final String? body;
  final DateTime? openedAt;
  /// Literal, unconditional true — see file header. There is deliberately no
  /// way to construct a Letter with this false.
  bool get preserved => true;

  Letter _opened(DateTime at) => Letter(id: id, childId: childId,
    writtenAtAge: writtenAtAge, openAtAge: openAtAge, writtenAt: writtenAt,
    body: body, openedAt: at);
}

class SealResult {
  const SealResult.ok(this.letter) : reason = null;
  const SealResult.refused(this.reason) : letter = null;
  final Letter? letter;
  final SealError? reason;
  bool get ok => letter != null;
}

/// Sealed at nine, opened at eighteen (those are the *defaults* a family
/// picks; the guard below is what actually enforces the shape of the rule).
SealResult sealLetter({
  required String id, required String childId, required int writtenAtAge,
  required int openAtAge, required String body, required DateTime at,
}) {
  if (openAtAge - writtenAtAge < minSealYears) return const SealResult.refused(SealError.tooSoon);
  if (openAtAge > maxSealToAge) return const SealResult.refused(SealError.tooFar);
  return SealResult.ok(Letter(id: id, childId: childId, writtenAtAge: writtenAtAge,
    openAtAge: openAtAge, writtenAt: at, body: body));
}

class OpenResult {
  const OpenResult.ok(this.letter) : reason = null, yearsLeft = 0;
  const OpenResult.refused(this.reason, this.yearsLeft) : letter = null;
  final Letter? letter;
  final SealError? reason;
  final int yearsLeft;
  bool get ok => letter != null;
}

/// Nobody can open it early. Not a guardian — unreachable from this file —
/// and not her either, which is the whole point of a seal.
OpenResult openLetter(Letter l, int currentAge, DateTime at) {
  if (l.openedAt != null) return const OpenResult.refused(SealError.alreadyOpen, 0);
  if (currentAge < l.openAtAge) {
    return OpenResult.refused(SealError.notYet, l.openAtAge - currentAge);
  }
  return OpenResult.ok(l._opened(at));
}

/// The only actor this file can ever pass is 'child' — there is no guardian
/// surface here to call it as anything else (packages/maturation/src's
/// `deleteLetter` also refuses a 'guardian' actor; that branch simply cannot
/// be reached from this widget tree).
List<Letter> deleteLetter(List<Letter> letters, String id) =>
    letters.where((l) => l.id != id).toList();

List<Letter> lettersDue(List<Letter> letters, int age) =>
    letters.where((l) => l.openedAt == null && age >= l.openAtAge).toList();
// =============================================================================

const _candidateOpenAges = <int>[12, 14, 16, 18, 21, 25];

enum _LoadState { ready, loading, error }

class LettersScreen extends StatefulWidget {
  const LettersScreen({
    super.key,
    required this.childName,
    required this.currentAge,
    this.childId = 'demo-child',
    this.initialLetters = const [],
    this.baseUrl,
    this.sessionToken,
    this.httpClient,
  });

  final String childName;
  final int currentAge;
  final String childId;
  final List<Letter> initialLetters;
  /// Live-session wiring, reached through child_home.dart -> child_more
  /// .dart, both of which already carry these three from a single real
  /// child login (child_home_live.dart's own `_load()`) -- this screen
  /// reuses that ALREADY-authenticated session directly, the same
  /// established pattern homework_screen.dart/capture_gate.dart already use
  /// for a live screen reached through this exact chain, rather than
  /// minting its own fresh devLoginFor() session the way every guardian
  /// screen in this codebase does (there is no equivalent single guardian
  /// login to reuse today — see expenses_screen.dart's own header).
  final String? baseUrl;
  final String? sessionToken;
  final http.Client? httpClient;

  bool get _isLive => baseUrl != null && sessionToken != null;

  @override
  State<LettersScreen> createState() => _LettersScreenState();
}

class _LettersScreenState extends State<LettersScreen> {
  late List<Letter> _letters;
  final _controller = TextEditingController();
  late int _selectedOpenAge;
  int _nextId = 1;
  _LoadState _loadState = _LoadState.ready;
  bool _sealing = false;
  // Per-letter id in flight (open or delete) — mirrors expenses_screen
  // .dart's own `_resolving` Set, same reasoning: disables that one
  // letter's buttons so a slow connection can't be double-tapped.
  final Set<String> _busyIds = <String>{};

  List<int> get _availableAges => _candidateOpenAges
      .where((a) => a - widget.currentAge >= minSealYears && a <= maxSealToAge)
      .toList();

  @override
  void initState() {
    super.initState();
    _letters = List.of(widget.initialLetters);
    final avail = _availableAges;
    _selectedOpenAge = avail.contains(18) ? 18 : (avail.isNotEmpty ? avail.first : widget.currentAge + minSealYears);
    _controller.addListener(_onTextChanged);
    if (widget._isLive) _load();
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  /// The ONLY place this screen calls the network to READ — reuses the
  /// already-authenticated session (see file header) instead of minting
  /// its own via devLoginFor(); `api.close()` still runs on the success
  /// path when no client was injected, same reasoning every other screen's
  /// own `_load()` already has — that closes the OliveApi instance's own
  /// internal http.Client, unrelated to whose session token it was handed.
  Future<void> _load() async {
    setState(() => _loadState = _LoadState.loading);
    try {
      final OliveApi api = OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
      final Map<String, dynamic> result = await api.fetchLetters(widget.childId);
      if (widget.httpClient == null) api.close();
      final List<dynamic> raw = result['letters'] as List<dynamic>? ?? <dynamic>[];
      final List<Letter> letters = raw.map((dynamic e) {
        final Map<String, dynamic> row = e as Map<String, dynamic>;
        return Letter(
          id: row['id'] as String, childId: widget.childId,
          writtenAtAge: row['writtenAtAge'] as int, openAtAge: row['openAtAge'] as int,
          writtenAt: DateTime.tryParse(row['writtenAt'] as String? ?? '') ?? DateTime.now(),
          body: row['body'] as String?,
          openedAt: DateTime.tryParse(row['openedAt'] as String? ?? ''));
      }).toList();
      if (!mounted) return;
      setState(() {
        _letters = letters;
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  void _seal() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!widget._isLive) {
      final result = sealLetter(id: 'local-${_nextId++}', childId: widget.childId,
        writtenAtAge: widget.currentAge, openAtAge: _selectedOpenAge, body: text,
        at: DateTime.now());
      if (!result.ok) {
        // Only reachable if _availableAges is ever empty and the fallback
        // above picked something invalid — say so plainly rather than
        // eating her letter silently.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("That one can't be sealed yet — try picking a later age.")));
        return;
      }
      setState(() { _letters.insert(0, result.letter!); _controller.clear(); });
      return;
    }
    _sealLive(text);
  }

  /// Live path — `writtenAtAge` is never sent; the server computes her real
  /// current age from her real birth_date and validates it against
  /// [_selectedOpenAge] itself (see file header).
  Future<void> _sealLive(String text) async {
    setState(() => _sealing = true);
    try {
      final OliveApi api = OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
      final Map<String, dynamic> row =
          await api.sealLetter(widget.childId, text, _selectedOpenAge);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      setState(() {
        _letters.insert(0, Letter(
          id: row['id'] as String, childId: widget.childId,
          writtenAtAge: row['writtenAtAge'] as int, openAtAge: row['openAtAge'] as int,
          writtenAt: DateTime.tryParse(row['writtenAt'] as String? ?? '') ?? DateTime.now(),
          body: null, openedAt: null));
        _controller.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't seal that letter — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _sealing = false);
    }
  }

  void _open(Letter l) {
    if (!widget._isLive) {
      final result = openLetter(l, widget.currentAge, DateTime.now());
      if (!result.ok) return; // defensive only — the open button is hidden until this succeeds
      setState(() => _letters = [for (final x in _letters) x.id == l.id ? result.letter! : x]);
      return;
    }
    _openLive(l);
  }

  /// Live path — takes no age parameter at all; the server computes her
  /// real current age itself inside openLetterRow() (see file header). A
  /// 409 `not_yet`/`already_open` response is shown as a real message, a
  /// genuine defensive fallback for a stale client or a real race, never
  /// silently ignored.
  Future<void> _openLive(Letter l) async {
    setState(() => _busyIds.add(l.id));
    try {
      final OliveApi api = OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
      final Map<String, dynamic> row = await api.openLetter(widget.childId, l.id);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      if (row['error'] == 'not_yet' || row['error'] == 'already_open') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          row['error'] == 'already_open'
            ? "That letter's already open."
            : "Not quite yet — ${row['yearsLeft']} more year"
              "${row['yearsLeft'] == 1 ? '' : 's'} to go.")));
        return;
      }
      final Letter opened = Letter(
        id: row['id'] as String, childId: widget.childId,
        writtenAtAge: row['writtenAtAge'] as int, openAtAge: row['openAtAge'] as int,
        writtenAt: DateTime.tryParse(row['writtenAt'] as String? ?? '') ?? l.writtenAt,
        body: row['body'] as String?,
        openedAt: DateTime.tryParse(row['openedAt'] as String? ?? '') ?? DateTime.now());
      setState(() => _letters = [for (final x in _letters) x.id == l.id ? opened : x]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't open that letter — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _busyIds.remove(l.id));
    }
  }

  Future<void> _confirmDelete(Letter l) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete this letter?'),
      content: const Text("It can't be brought back once it's gone. Nobody else can read it "
        'either way, so this is only your call to make.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete it')),
      ],
    ));
    if (confirmed != true) return;
    if (!widget._isLive) {
      setState(() => _letters = deleteLetter(_letters, l.id));
      return;
    }
    setState(() => _busyIds.add(l.id));
    try {
      final OliveApi api = OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
      await api.deleteLetter(widget.childId, l.id);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      setState(() => _letters = deleteLetter(_letters, l.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't delete that letter — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _busyIds.remove(l.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading/error UI mirrors expenses_screen.dart/care_note.dart's own
    // established shape — only ever reachable when this screen is
    // live-wired; the pure demo path never enters either state.
    if (_loadState == _LoadState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadState == _LoadState.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Letters to future you')),
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
    final scheme = Theme.of(context).colorScheme;
    final avail = _availableAges;

    // Pane A — compose: the whole 'Dear future me…' Card, verbatim (field,
    // age chips, and the Seal it button all together, unsplit). Only ever
    // pulled into a named list so the wide/narrow branches below can share
    // it verbatim rather than diverging — same discipline message_banking.dart
    // uses for its own two panes.
    final List<Widget> composeChildren = <Widget>[
      Card(child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Dear future me…', style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
          const SizedBox(height: 12),
          TextField(controller: _controller, minLines: 4, maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Say whatever you want. This is between you and future you.',
              border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Text('Open it when I turn:', style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (avail.isEmpty)
            Text("There's no age left that's far enough away to seal one right now.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [for (final age in avail)
              ChoiceChip(
                label: SizedBox(height: 32, child: Center(child: Text('$age'))),
                selected: _selectedOpenAge == age,
                onSelected: (_) => setState(() => _selectedOpenAge = age)),
            ]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 48,
            child: FilledButton.icon(
              onPressed: (avail.isEmpty || _controller.text.trim().isEmpty || _sealing)
                ? null : _seal,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Seal it'))),
        ]))),
    ];

    // Pane B — the letters region: either the empty state or every
    // _LetterTile, same widgets and same order as this screen always
    // rendered.
    final List<Widget> listChildren = <Widget>[
      if (_letters.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Column(children: [
            Icon(Icons.mail_outline, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No letters yet. Write one whenever you feel like it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
          ])))
      else
        for (final l in _letters)
          _LetterTile(key: ValueKey(l.id), letter: l, currentAge: widget.currentAge,
            onOpen: () => _open(l), onDelete: () => _confirmDelete(l),
            busy: _busyIds.contains(l.id)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Letters to future you')),
      // SingleChildScrollView + Column, NOT ListView — a sliver list only
      // realizes children near the viewport, which would silently drop
      // letters scrolled below the fold from the widget tree. Same fix
      // message_banking.dart already documents for the same bug class.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // number — same threshold message_banking.dart uses for its own
        // two-pane split.
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 12, matching the compact inline info-banner role used elsewhere
            // (expenses_screen.dart, meds_care.dart, morning_briefing.dart,
            // care_note.dart, guardian_setup.dart) — was 16, a leftover from
            // before the radius sweep.
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.mail_lock_outlined, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  "Write to the you who's older. Once it's sealed, nobody can open it early — "
                  'not you, and not anyone else. It gets kept forever.',
                  style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSecondaryContainer))),
              ])),
            const SizedBox(height: 16),
            wide
              ? Row(key: const Key('lettersTwoPaneRow'),
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: composeChildren)),
                    const SizedBox(width: 24),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: listChildren)),
                  ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ...composeChildren,
                  const SizedBox(height: 24),
                  ...listChildren,
                ]),
          ]),
        );
      })),
    );
  }
}

class _LetterTile extends StatelessWidget {
  const _LetterTile({super.key, required this.letter, required this.currentAge,
    required this.onOpen, required this.onDelete, this.busy = false});
  final Letter letter;
  final int currentAge;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  /// True while a real live open/delete for THIS letter is in flight —
  /// disables both buttons so a slow connection can't be double-tapped.
  /// Always false on the demo path.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opened = letter.openedAt != null;
    final ready = !opened && currentAge >= letter.openAtAge;

    return Card(margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(16),
        child: AnimatedSize(
          // Consequence-driven expand/reveal only, well under the motion
          // budget — never ambient, never looping.
          duration: const Duration(milliseconds: 300),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(opened ? Icons.drafts_outlined : Icons.mail_lock_outlined,
                color: scheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(
                opened ? 'Opened' : (ready ? 'Ready whenever you want' : "Sealed until you're ${letter.openAtAge}"),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(tooltip: 'Delete this letter', onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline)),
            ]),
            const SizedBox(height: 4),
            Text('Written when you were ${letter.writtenAtAge}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (opened) ...[
              const SizedBox(height: 12),
              Text(letter.body ?? '',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35)),
            ] else if (ready) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 48,
                child: FilledButton.tonal(onPressed: busy ? null : onOpen, child: const Text('Open it'))),
            ],
          ]),
        ),
      ));
  }
}
