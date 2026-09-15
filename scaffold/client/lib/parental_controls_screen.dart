// OLIVE BRANCH — Parental Controls: visibility & pacing (guardian-only,
// PIN-gated). UNVERIFIED (no Flutter toolchain in tools/verify.sh's
// automated pipeline — manually built and run via `flutter analyze`/
// `flutter test` this session). docs/superpowers/specs/2026-09-13-parental
// -controls-pacing-design.md ("sub-project 2: visibility & pacing").
//
// Off Guardian More's "Family setup" section, same convention as "Add a
// device" (add_device_screen.dart). Scoped to ONE child (childId/childName
// constructor fields), the same shape theme_picker_screen.dart's own
// "$childName's colour" already uses — no in-screen child-picker step,
// unlike add_device_screen.dart's own multi-target first step: there is no
// second "my own device" option here, every row in this table is per-CHILD
// by construction (0033_guardian_activity_override.sql's own PRIMARY KEY).
//
// PIN-verify step first — POST /v1/me/verify-controls-pin, this feature's
// own new, narrow screen-entry gate (see routes.mjs's own comment for why
// it's a separate route from kiosk-pin/verify's "every guardian" check) —
// mirroring add_device_screen.dart's own `_pinStep()` shape exactly. Only
// after that succeeds does this screen reveal its two tabs:
//   - Visibility: every ChildHome tile, game, joke, and drawing/activity —
//     a toggle switch each.
//   - Pacing: only the age-gateable items (games + jokes; drawing/
//     activities have no existing minAge concept anywhere in this client or
//     server — Explicitly out of scope per the design spec, "this pass does
//     not invent a minAge for surfaces that have never had one") — a +/-
//     stepper for the effective minAge, plus a Reveal now/Un-reveal button.
//
// No TabBar/TabController exists anywhere else in this client (grepped) —
// SegmentedButton is this app's own established switch-between-two-views
// convention (doodle_desk.dart's `_ToolSwitch`), reused here rather than
// this screen introducing a first, unprecedented TabBar. Disclosed judgment
// call — see this feature's own PR description.
//
// House style, reconfirmed by the design spec itself: nothing on THIS
// screen ever shows a lock icon or countdown to a child — this screen is
// the mechanism that PRODUCES that effect elsewhere (activity_overrides
// .dart's [effectiveVisibility]/[isTileVisible], consumed by child_home
// .dart/game_picker.dart/games_hub.dart/jokebook_screen.dart/child_more
// .dart); it is not itself a child-facing surface, so it plainly shows
// every item's real current state, the same way any other settings screen
// in this app already does.
//
// The catalogue of rows below is built from the SAME real sources every
// consumer screen already reads (game_logic.dart's `catalogue`/
// `hubGameMinAge`, joke_logic.dart's `kJokeCatalogue`) — never a sixth,
// hand-typed copy of any of them, so a future game/joke added to either
// catalogue shows up here automatically.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'activity_overrides.dart';
import 'api_client.dart';
import 'game_logic.dart' as game_catalogue;
import 'joke_logic.dart' as joke_catalogue;

enum _Step { enterPin, controls }
enum _Tab { visibility, pacing }

/// This screen's own small, local catalogue-of-catalogues — one row per
/// controllable item. [defaultMinAge] null means visibility-only (a
/// ChildHome tile, or a drawing/activity that has never had an age
/// concept); non-null means the item is ALSO eligible for the Pacing tab.
class _ControlItem {
  const _ControlItem(this.key, this.title, this.category, {this.defaultMinAge});
  final String key;
  final String title;
  final String category;
  final int? defaultMinAge;
}

/// Display titles for the 8 games_hub.dart games this feature's own pass
/// gave a real minAge (game_logic.dart's `hubGameMinAge`) — matching
/// games_hub.dart's own HubTile titles verbatim, so a guardian recognizes
/// the same name she sees in the games hub.
const Map<String, String> _hubGameTitles = {
  'checkers': 'Checkers',
  'chess': 'Chess',
  'battleship': 'Battleship',
  'wordsearch': 'Word search',
  'kimsGame': "Kim's game",
  'wordChain': 'Word chain',
  'hangman': 'Guess the word',
  'scavengerHunt': 'Scavenger hunt',
};

List<_ControlItem> _buildCatalogue() => [
      // The design spec's own exact 6 — deliberately NOT "My day"/"Play
      // together" (see child_home.dart's own comment on why those two stay
      // outside this list: "My day" is MASTERFILE's one signature element,
      // and "Play together" is a pure navigation door onto the games/jokes
      // this same catalogue already controls item-by-item).
      const _ControlItem('tile:storyteller', 'Storyteller', 'ChildHome tiles'),
      const _ControlItem('tile:homework', 'Homework', 'ChildHome tiles'),
      const _ControlItem('tile:messages', 'Messages', 'ChildHome tiles'),
      const _ControlItem('tile:showAndTell', 'Show & tell', 'ChildHome tiles'),
      const _ControlItem('tile:myList', 'My list', 'ChildHome tiles'),
      const _ControlItem('tile:more', 'More for you', 'ChildHome tiles'),
      for (final g in game_catalogue.catalogue)
        _ControlItem('game:${g.kind.name}', g.title, 'Games', defaultMinAge: g.minAge),
      for (final entry in game_catalogue.hubGameMinAge.entries)
        _ControlItem('game:${entry.key}', _hubGameTitles[entry.key] ?? entry.key, 'Games',
            defaultMinAge: entry.value),
      // No existing minAge (games_hub.dart's own "On her own" section) —
      // visibility-only, same reasoning as the two activities below.
      const _ControlItem('game:findthing', 'Find the thing', 'Games'),
      for (final j in joke_catalogue.kJokeCatalogue)
        _ControlItem('joke:${j.id}', j.setup, 'Jokes', defaultMinAge: j.minAge),
      const _ControlItem('activity:doodle', 'Doodle desk', 'Drawing & activities'),
      const _ControlItem('activity:colouring', 'Colouring', 'Drawing & activities'),
    ];

class ParentalControlsScreen extends StatefulWidget {
  const ParentalControlsScreen({
    super.key,
    required this.baseUrl,
    required this.childId,
    required this.childName,
    required this.guardianId,
    this.httpClient,
  });

  final String baseUrl;
  final String childId;
  final String childName;
  final String guardianId;
  final http.Client? httpClient;

  @override
  State<ParentalControlsScreen> createState() => _ParentalControlsScreenState();
}

class _ParentalControlsScreenState extends State<ParentalControlsScreen> {
  _Step _step = _Step.enterPin;
  _Tab _tab = _Tab.visibility;
  final _pinController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;
  Map<String, ActivityOverride> _overrides = const {};
  late final List<_ControlItem> _catalogue = _buildCatalogue();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<OliveApi> _mintApi() async {
    final token =
        await devLoginFor(widget.baseUrl, userId: widget.guardianId, client: widget.httpClient);
    return OliveApi(widget.baseUrl, token, client: widget.httpClient);
  }

  String _messageFor(String error) => switch (error) {
        'pin_incorrect' => "That PIN isn't right.",
        'pin_locked' => 'Too many tries — wait a bit and try again.',
        'pin_not_set' => "You haven't set a PIN yet.",
        _ => "Couldn't verify that — try again.",
      };

  Future<void> _verifyPin() async {
    final pin = _pinController.text;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final api = await _mintApi();
    try {
      await api.verifyControlsPin(pin);
      final overridesJson = await api.fetchActivityOverrides(widget.childId);
      if (!mounted) return;
      setState(() {
        _overrides = decodeActivityOverrides(overridesJson);
        _step = _Step.controls;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _messageFor(e.error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = "Couldn't reach the server — try again.");
    } finally {
      if (widget.httpClient == null) api.close();
      if (mounted) setState(() => _submitting = false);
    }
  }

  ActivityOverride? _rowFor(String key) => _overrides[key];

  /// Best-effort re-fetch, used only to reconcile local state after a
  /// failed write — the same "reconcile on a failed write" posture
  /// live_game_picker.dart's own `_persistFavorites` already takes for
  /// favouriting.
  Future<void> _refresh() async {
    final api = await _mintApi();
    try {
      final overridesJson = await api.fetchActivityOverrides(widget.childId);
      if (!mounted) return;
      setState(() => _overrides = decodeActivityOverrides(overridesJson));
    } catch (_) {
      // Best-effort — the local, possibly-stale state stays as it is; the
      // snack bar the caller already showed is the honest signal here.
    } finally {
      if (widget.httpClient == null) api.close();
    }
  }

  Future<void> _persist(
    String key, {
    bool? visible,
    int? minAgeOverride,
    bool? reveal,
    bool? unreveal,
  }) async {
    final api = await _mintApi();
    try {
      await api.setActivityOverride(widget.childId, key,
          visible: visible, minAgeOverride: minAgeOverride, reveal: reveal, unreveal: unreveal);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't save that change — try again."),
          duration: Duration(seconds: 3)));
      await _refresh();
      return;
    } finally {
      if (widget.httpClient == null) api.close();
    }
  }

  void _setVisible(String key, bool value) {
    final before = _rowFor(key);
    setState(() {
      _overrides = {
        ..._overrides,
        key: ActivityOverride(
            activityKey: key,
            visible: value,
            minAgeOverride: before?.minAgeOverride,
            revealedAt: before?.revealedAt),
      };
    });
    unawaited(_persist(key, visible: value));
  }

  void _setMinAge(String key, int defaultMinAge, int delta) {
    final before = _rowFor(key);
    final current = before?.minAgeOverride ?? defaultMinAge;
    final next = (current + delta).clamp(0, 18);
    if (next == current) return; // already at the clamp — nothing to persist
    setState(() {
      _overrides = {
        ..._overrides,
        key: ActivityOverride(
            activityKey: key,
            visible: before?.visible,
            minAgeOverride: next,
            revealedAt: before?.revealedAt),
      };
    });
    unawaited(_persist(key, minAgeOverride: next));
  }

  void _toggleReveal(String key) {
    final before = _rowFor(key);
    final revealed = before?.revealedAt != null;
    setState(() {
      _overrides = {
        ..._overrides,
        key: ActivityOverride(
            activityKey: key,
            visible: before?.visible,
            minAgeOverride: before?.minAgeOverride,
            revealedAt: revealed ? null : DateTime.now()),
      };
    });
    unawaited(_persist(key, reveal: revealed ? null : true, unreveal: revealed ? true : null));
  }

  Map<String, List<_ControlItem>> _grouped(Iterable<_ControlItem> items) {
    final byCategory = <String, List<_ControlItem>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }
    return byCategory;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Parental controls')),
        body: SafeArea(
          child: switch (_step) {
            _Step.enterPin => Padding(padding: const EdgeInsets.all(20), child: _pinStep()),
            _Step.controls => _controlsBody(),
          },
        ),
      );

  Widget _pinStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Confirm it\'s you', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Enter your PIN to manage what ${widget.childName} can see.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('parentalControlsPinField'),
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: FilledButton(
            key: const Key('parentalControlsVerifyButton'),
            onPressed: _submitting ? null : _verifyPin,
            child: _submitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4,
                      color: Theme.of(context).colorScheme.onPrimary))
                : const Text('Continue'),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!,
              key: const Key('parentalControlsErrorMessage'),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]);

  Widget _controlsBody() => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<_Tab>(
            key: const Key('parentalControlsTabSwitch'),
            segments: const [
              ButtonSegment(
                  value: _Tab.visibility,
                  label: Text('Visibility'),
                  icon: Icon(Icons.visibility_outlined)),
              ButtonSegment(
                  value: _Tab.pacing, label: Text('Pacing'), icon: Icon(Icons.speed_outlined)),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(
          key: Key('parentalControlsTabBody_${_tab.name}'),
          child: _tab == _Tab.visibility ? _visibilityList() : _pacingList(),
        ),
      ]);

  Widget _visibilityList() {
    final byCategory = _grouped(_catalogue);
    return ListView(children: [
      for (final entry in byCategory.entries)
        ExpansionTile(
          key: Key('visibilitySection_${entry.key}'),
          title: Text(entry.key),
          initiallyExpanded: entry.key == 'ChildHome tiles',
          children: [for (final item in entry.value) _visibilityRow(item)],
        ),
    ]);
  }

  Widget _visibilityRow(_ControlItem item) =>
      // Wrapped in its own transparent Material — court_export.dart's own
      // established convention for a SwitchListTile sitting inside a
      // Container/tile with its own background (ExpansionTile's children
      // area here), so Flutter's ink splashes have a real Material ancestor
      // to paint against.
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: Key('visible_${item.key}'),
          dense: true,
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          value: _rowFor(item.key)?.visible != false,
          onChanged: (v) => _setVisible(item.key, v),
        ),
      );

  Widget _pacingList() {
    final ageable = _catalogue.where((i) => i.defaultMinAge != null);
    final byCategory = _grouped(ageable);
    return ListView(children: [
      for (final entry in byCategory.entries)
        ExpansionTile(
          key: Key('pacingSection_${entry.key}'),
          title: Text(entry.key),
          initiallyExpanded: entry.key == 'Games',
          children: [for (final item in entry.value) _pacingRow(item)],
        ),
    ]);
  }

  Widget _pacingRow(_ControlItem item) {
    final row = _rowFor(item.key);
    final defaultMinAge = item.defaultMinAge!;
    final effectiveMinAge = row?.minAgeOverride ?? defaultMinAge;
    final revealed = row?.revealedAt != null;
    return ListTile(
      key: Key('pacing_${item.key}'),
      dense: true,
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: revealed ? const Text('Revealed — shown regardless of age') : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('pacingMinus_${item.key}'),
          tooltip: 'Lower the age',
          onPressed: () => _setMinAge(item.key, defaultMinAge, -1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
            width: 28,
            child: Text('$effectiveMinAge', textAlign: TextAlign.center, key: Key('pacingAge_${item.key}'))),
        IconButton(
          key: Key('pacingPlus_${item.key}'),
          tooltip: 'Raise the age',
          onPressed: () => _setMinAge(item.key, defaultMinAge, 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
        TextButton(
          key: Key('pacingReveal_${item.key}'),
          onPressed: () => _toggleReveal(item.key),
          child: Text(revealed ? 'Un-reveal' : 'Reveal now'),
        ),
      ]),
    );
  }
}
