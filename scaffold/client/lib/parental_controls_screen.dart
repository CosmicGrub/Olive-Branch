// OLIVE BRANCH — Parental Controls: visibility & pacing (guardian-only,
// PIN-gated). UNVERIFIED (no Flutter toolchain in tools/verify.sh's
// automated pipeline — manually built and run via `flutter analyze`/
// `flutter test` this session). docs/superpowers/specs/2026-09-13-parental
// -controls-pacing-design.md ("sub-project 2: visibility & pacing"), and
// docs/superpowers/specs/2026-09-15-parental-controls-ia-rework-design.md
// ("UI/UX review theme #5") for the sub-grouping/search/overflow/divider
// rework below — the deferred IA half of the same feature, now built.
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
//
// ---- IA rework (theme #5) — sub-grouping, search, three targeted fixes ---
//
// Sub-grouping: both tabs' per-category ExpansionTiles now carry a SECOND
// grouping level for the two categories big enough to need one (Jokes: 59
// rows; Games: 21 rows) — a NESTED ExpansionTile per sub-group inside the
// existing category ExpansionTile, rather than a flat list with sub-group
// header rows. Chosen over the flat-header alternative because it reuses
// the exact same collapsible-section primitive the category level already
// established (one real pattern in this file, not two), and because a
// nested ExpansionTile is independently collapsible — a guardian who only
// cares about "Knock-knock" can collapse "Puns" without losing her place,
// which a flat header row can't offer without hand-rolled show/hide state.
// The category tiles keep their existing `initiallyExpanded` behaviour
// unchanged (ChildHome tiles on Visibility, Games on Pacing); the nested
// sub-group tiles default to COLLAPSED (ExpansionTile's own default) —
// deliberately, since an initially-expanded sub-group would leave all 59
// joke rows (or all 21 game rows) visible the instant the category opens,
// which is the exact flat-dump problem this rework exists to fix. This is
// why some pre-existing tests below now tap open a sub-group tile before
// reaching a row they used to find immediately — anticipated by the design
// spec's own Testing section.
//
// ChildHome tiles (6) and Drawing & activities (2) stay single flat
// groups, unchanged — too small to meaningfully sub-divide, per the spec.
//
// Search: one field per tab (_visibilitySearchController/
// _pacingSearchController), reusing story_library.dart's `_SearchShelf`
// TextField shape (hintText/prefixIcon: Icons.search_rounded, filled,
// rounded border) and its controller+listener state-management pattern
// directly. An empty query shows the normal grouped/sub-grouped view built
// above; a non-empty query flattens to one filtered ListView across every
// category and sub-group for that tab, live, case-insensitive substring
// match against each item's title — with an honest "no matches" empty
// state (never a blank screen) when nothing matches.
//
// Fix — joke titles: maxLines 1 → 2 on both row builders' title Text, so
// the 50-62-character joke setups render in full (or very nearly) instead
// of collapsing to a truncated "What do you call a..." fragment. `dense:
// true` is removed from both rows — dense trims a ListTile's vertical
// padding on the assumption of a single-line title; two lines of real text
// need the room back, and Flutter's own dense docs describe it as meant for
// compact single-line rows.
//
// Fix — Pacing overflow: verified FIRST via a real widget test at this
// app's established 344px Fold5-cover floor + 2.0x text scale, BEFORE any
// layout change — and it genuinely overflowed (`RenderFlex overflowed by
// 133 pixels`, confirmed by the test's real output, not assumed). Fixed by
// moving the Reveal/Un-reveal button to its own second line below the
// age-stepper trio (see `_pacingRow`'s own comment for why that was chosen
// over a `Wrap`, and parental_controls_screen_test.dart's group F for the
// regression test that reproduced the failure and now guards against it).
//
// Fix — Reveal-now separation: resolved as a direct side effect of the
// overflow fix above — the Reveal/Un-reveal button now sits on its own
// line below the age-stepper trio, which already reads as visually
// distinct without a separate divider (see `_pacingRow`'s own comment;
// this app has no existing precedent anywhere for "two distinct button
// groups sharing one row" — a `VerticalDivider` was this pass's first
// attempt, before the overflow test proved the single-Row shape needed to
// change regardless, making a divider on top of it redundant).
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
/// [subGroup] is the IA rework's second grouping level within [category] —
/// null for the two categories that stay flat (ChildHome tiles, Drawing &
/// activities); see [_subGroupOrderByCategory] for the two that don't.
class _ControlItem {
  const _ControlItem(this.key, this.title, this.category, {this.defaultMinAge, this.subGroup});
  final String key;
  final String title;
  final String category;
  final int? defaultMinAge;
  final String? subGroup;
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

/// Label mapping for the Jokes sub-group split — a straightforward
/// presentation label per `joke_logic.dart`'s own `JokeCategory` enum
/// value, in the order the design spec itself lists them.
const Map<joke_catalogue.JokeCategory, String> _jokeSubGroupLabels = {
  joke_catalogue.JokeCategory.dadJoke: 'Dad jokes',
  joke_catalogue.JokeCategory.pun: 'Puns',
  joke_catalogue.JokeCategory.wordplay: 'Wordplay',
  joke_catalogue.JokeCategory.silly: 'Silly',
  joke_catalogue.JokeCategory.knockKnock: 'Knock-knock',
};

/// The two categories big enough to earn a second grouping level, and the
/// exact sub-group display order within each — Jokes follows the design
/// spec's own listed order (not `JokeCategory.values`' declared order,
/// which differs — dadJoke/pun/wordplay/silly/knockKnock happens to match
/// here, but this map is what actually pins the order, not enum-declaration
/// order, so a future enum reorder can't silently reshuffle this screen).
/// Games matches games_hub.dart's own real framing of these 21 items as two
/// doors reached from the same "Play together" tile — "Games" (the 12
/// game_logic.dart catalogue entries, exactly how the main game picker
/// already presents them) and "More games" (the 8 `hubGameMinAge` entries
/// plus the standalone "Find the thing" row) — deliberately NOT
/// games_hub.dart's own finer 4-way HubSection split (Board & strategy /
/// Together / On her own / Playing fair); Explicitly out of scope, per the
/// design spec, to avoid over-fragmenting a controls screen.
const Map<String, List<String>> _subGroupOrderByCategory = {
  'Jokes': ['Dad jokes', 'Puns', 'Wordplay', 'Silly', 'Knock-knock'],
  'Games': ['Games', 'More games'],
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
        _ControlItem('game:${g.kind.name}', g.title, 'Games',
            defaultMinAge: g.minAge, subGroup: 'Games'),
      for (final entry in game_catalogue.hubGameMinAge.entries)
        _ControlItem('game:${entry.key}', _hubGameTitles[entry.key] ?? entry.key, 'Games',
            defaultMinAge: entry.value, subGroup: 'More games'),
      // No existing minAge (games_hub.dart's own "On her own" section) —
      // visibility-only, same reasoning as the two activities below.
      const _ControlItem('game:findthing', 'Find the thing', 'Games', subGroup: 'More games'),
      for (final j in joke_catalogue.kJokeCatalogue)
        _ControlItem('joke:${j.id}', j.setup, 'Jokes',
            defaultMinAge: j.minAge, subGroup: _jokeSubGroupLabels[j.category]),
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

  // IA rework — one search box per tab (see file header). Mirrors story_
  // library.dart's own `_SearchShelf` controller+listener shape exactly.
  final _visibilitySearchController = TextEditingController();
  final _pacingSearchController = TextEditingController();
  String _visibilityQuery = '';
  String _pacingQuery = '';

  @override
  void initState() {
    super.initState();
    _visibilitySearchController.addListener(
        () => setState(() => _visibilityQuery = _visibilitySearchController.text.trim()));
    _pacingSearchController.addListener(
        () => setState(() => _pacingQuery = _pacingSearchController.text.trim()));
  }

  @override
  void dispose() {
    _pinController.dispose();
    _visibilitySearchController.dispose();
    _pacingSearchController.dispose();
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

  /// The sub-group ExpansionTiles for one category's children, in the exact
  /// order [_subGroupOrderByCategory] states, skipping a sub-group with no
  /// real items — or, for a category with no sub-grouping (ChildHome tiles,
  /// Drawing & activities), the flat row list exactly as before this rework.
  List<Widget> _sectionChildren({
    required String tabPrefix,
    required String category,
    required List<_ControlItem> items,
    required Widget Function(_ControlItem) rowBuilder,
  }) {
    final subGroupOrder = _subGroupOrderByCategory[category];
    if (subGroupOrder == null) {
      return [for (final item in items) rowBuilder(item)];
    }
    return [
      for (final label in subGroupOrder)
        if (items.any((i) => i.subGroup == label))
          ExpansionTile(
            key: Key('${tabPrefix}Subgroup_${category}_$label'),
            title: Text(label),
            children: [for (final item in items.where((i) => i.subGroup == label)) rowBuilder(item)],
          ),
    ];
  }

  /// The grouped (non-search) view shared by both tabs — one category
  /// ExpansionTile per real category present in [items], each carrying
  /// [_sectionChildren]'s sub-grouping.
  Widget _groupedView({
    required List<_ControlItem> items,
    required Widget Function(_ControlItem) rowBuilder,
    required String tabPrefix,
    required String initiallyExpandedCategory,
  }) {
    final byCategory = _grouped(items);
    return ListView(children: [
      for (final entry in byCategory.entries)
        ExpansionTile(
          key: Key('${tabPrefix}Section_${entry.key}'),
          title: Text(entry.key),
          initiallyExpanded: entry.key == initiallyExpandedCategory,
          children: _sectionChildren(
              tabPrefix: tabPrefix, category: entry.key, items: entry.value, rowBuilder: rowBuilder),
        ),
    ]);
  }

  /// Search's live-filter — case-insensitive substring match against title,
  /// same rule story_library.dart's `_SearchShelf` already uses.
  List<_ControlItem> _filter(List<_ControlItem> items, String query) => query.isEmpty
      ? items
      : items.where((i) => i.title.toLowerCase().contains(query.toLowerCase())).toList();

  /// A non-empty query's flattened result — every match across every
  /// category/sub-group for this tab, in one plain ListView; an honest
  /// empty state (never a blank screen) when nothing matches.
  Widget _searchResultsView({
    required List<_ControlItem> matches,
    required Widget Function(_ControlItem) rowBuilder,
    required Key key,
  }) {
    if (matches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No matches — try a different search.',
              key: Key('parentalControlsNoMatches'), textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(key: key, children: [for (final item in matches) rowBuilder(item)]);
  }

  /// story_library.dart's own `_SearchShelf` TextField shape, reused
  /// directly (hintText/prefixIcon: Icons.search_rounded, filled, rounded
  /// border) rather than a new search-field implementation.
  Widget _searchField({
    required Key key,
    required TextEditingController controller,
    required String hintText,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: SizedBox(
          height: 52,
          child: TextField(
            key: key,
            controller: controller,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
      );

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

  Widget _visibilityList() => Column(children: [
        _searchField(
          key: const Key('visibilitySearchField'),
          controller: _visibilitySearchController,
          hintText: 'Find a tile, game, or joke…',
        ),
        Expanded(
          child: _visibilityQuery.isEmpty
              ? _groupedView(
                  items: _catalogue,
                  rowBuilder: _visibilityRow,
                  tabPrefix: 'visibility',
                  initiallyExpandedCategory: 'ChildHome tiles',
                )
              : _searchResultsView(
                  matches: _filter(_catalogue, _visibilityQuery),
                  rowBuilder: _visibilityRow,
                  key: const Key('visibilitySearchResults'),
                ),
        ),
      ]);

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
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          value: _rowFor(item.key)?.visible != false,
          onChanged: (v) => _setVisible(item.key, v),
        ),
      );

  Widget _pacingList() {
    final ageable = _catalogue.where((i) => i.defaultMinAge != null).toList();
    return Column(children: [
      _searchField(
        key: const Key('pacingSearchField'),
        controller: _pacingSearchController,
        hintText: 'Find a game or joke…',
      ),
      Expanded(
        child: _pacingQuery.isEmpty
            ? _groupedView(
                items: ageable,
                rowBuilder: _pacingRow,
                tabPrefix: 'pacing',
                initiallyExpandedCategory: 'Games',
              )
            : _searchResultsView(
                matches: _filter(ageable, _pacingQuery),
                rowBuilder: _pacingRow,
                key: const Key('pacingSearchResults'),
              ),
      ),
    ]);
  }

  Widget _pacingRow(_ControlItem item) {
    final row = _rowFor(item.key);
    final defaultMinAge = item.defaultMinAge!;
    final effectiveMinAge = row?.minAgeOverride ?? defaultMinAge;
    final revealed = row?.revealedAt != null;
    // Fix — Pacing overflow (design spec, verified BEFORE fixing): a real
    // widget test (parental_controls_screen_test.dart, group F) pumped this
    // row at this app's 344px Fold5-cover floor + 2.0x text scale with the
    // ORIGINAL single unconstrained `ListTile.trailing` Row (age-stepper
    // trio + Reveal/Un-reveal all in one line) and reproduced a genuine
    // `RenderFlex overflowed by 133 pixels` — not a guess, a confirmed
    // failure. The first fix attempted — keeping the controls inside
    // `ListTile.trailing` but splitting them across two lines there — ALSO
    // failed the same test, with a DIFFERENT genuine overflow (`overflowed
    // by 40 pixels on the bottom`, at this suite's normal, non-narrow test
    // size): `ListTile.trailing` caps its child's height to the tile's own
    // computed height (single-line-title tiles default to 56px), which is
    // simply too short for two stacked rows of controls regardless of
    // width — a real Flutter ListTile constraint, not a hypothesis.
    //
    // The fix both tests actually pass: move the whole controls cluster
    // OUT of `ListTile.trailing` entirely, as a second row below the title/
    // subtitle inside a plain Column — this sidesteps `trailing`'s height
    // cap altogether (a normal Column sizes to its own content) and gives
    // the controls the tile's full width rather than whatever's left after
    // an Expanded title, so the stepper trio and the Reveal/Un-reveal
    // button each get their own line with generous horizontal headroom.
    //
    // Fix — Reveal-now separation (design spec): this same restructuring
    // ALSO resolves the separation fix as a direct side effect — a
    // persistent override on its own line already reads as visually
    // distinct from the age-stepper value-adjustment controls above it, so
    // no additional `VerticalDivider` (this pass's first attempt, before
    // the overflow test proved the single-Row trailing shape genuinely
    // overflowed) is added; that would be redundant once the two control
    // groups are already on separate lines.
    return Column(
      key: Key('pacing_${item.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: revealed ? const Text('Revealed — shown regardless of age') : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: Key('pacingReveal_${item.key}'),
              onPressed: () => _toggleReveal(item.key),
              child: Text(revealed ? 'Un-reveal' : 'Reveal now'),
            ),
          ),
        ),
      ],
    );
  }
}
