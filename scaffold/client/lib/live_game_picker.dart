// OLIVE BRANCH — GamePickerScreen's live wrapper. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze`/`flutter test` this session). MASTERFILE §9.2.
// docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-
// design.md.
//
// game_picker.dart's own header is explicit that GamePickerScreen stays a
// plain, non-fetching StatelessWidget fed by plain data — this file is
// where the live session actually lives, the identical split
// court_export.dart's LiveCourtExportScreen/CourtExportScreen and
// theme_picker_screen.dart's own self-contained live wiring already
// establish. ONE widget serves BOTH real call sites this spec names,
// rather than two hand-copied near-duplicates:
//
//   - child_home.dart's "Play together" tile: [sessionToken] set (her own,
//     already-minted token — the identical identity InboxScreen already
//     uses). Gets her real favoriteKinds/ageAtLastOpen and a Surprise-me
//     button; records her own visit in the background on open; NEVER gets
//     [onToggleFavorite] wired (she sees the RESULT of a favorite, never
//     the mechanism — the design spec's own "Where favoriting happens").
//   - guardian_more.dart's "Play together" tile: [guardianId] set, mints
//     its own fresh dev login on demand (theme_picker_screen.dart's own
//     Apply-time pattern) rather than a session cached on this widget.
//     Gets the real favoriteKinds (so star fill state is real) and
//     [onToggleFavorite] wired in — this spec's ONLY guardian-driven
//     favoriting surface. Never records ageAtLastOpen (that is HER visit
//     to record, not his browsing-on-her-behalf) and never gets a
//     Surprise-me button (this pass wires that for the child's own
//     screen only — see the design spec's own explicit call-site split).
//
// Exactly one of [sessionToken]/[guardianId] is expected non-null — the
// caller decides which identity this screen opens as, the same way it
// already decides whether to build this widget at all (both real call
// sites branch `(baseUrl != null && <identity> != null) ? Live... :
// GamePickerScreen(...)`, matching court_export.dart's/availability_screen
// .dart's own established shape) rather than this widget guessing.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'game_favorites_logic.dart' as fav;
import 'game_logic.dart';
import 'game_picker.dart';

class LiveGamePickerScreen extends StatefulWidget {
  const LiveGamePickerScreen({
    super.key,
    required this.baseUrl,
    required this.childId,
    this.childName,
    this.childAge = 7,
    this.sessionToken,
    this.guardianId,
    this.onPlay,
    this.extraSections,
    this.httpClient,
  });

  final String baseUrl;
  final String childId;
  final String? childName;
  final int childAge;

  /// Her own, already-authenticated session token — set only from
  /// child_home.dart's own call site.
  final String? sessionToken;

  /// A guardian's identity — set only from guardian_more.dart's own call
  /// site; mints its own dev login per write, same posture
  /// theme_picker_screen.dart's Apply already takes.
  final String? guardianId;

  final void Function(BuildContext context, GameKind kind)? onPlay;
  final List<Widget>? extraSections;
  final http.Client? httpClient;

  @override
  State<LiveGamePickerScreen> createState() => _LiveGamePickerScreenState();
}

class _LiveGamePickerScreenState extends State<LiveGamePickerScreen> {
  Set<String>? _favoriteKinds;
  int? _ageAtLastOpen;
  GameKind? _lastSurprise;

  bool get _isChild => widget.sessionToken != null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<OliveApi> _mintApi() async {
    if (widget.sessionToken != null) {
      return OliveApi(widget.baseUrl, widget.sessionToken!, client: widget.httpClient);
    }
    final token = await devLoginFor(widget.baseUrl, userId: widget.guardianId!, client: widget.httpClient);
    return OliveApi(widget.baseUrl, token, client: widget.httpClient);
  }

  Future<void> _load() async {
    final api = await _mintApi();
    try {
      final result = await api.fetchGameFavorites(widget.childId);
      if (!mounted) return;
      setState(() {
        _favoriteKinds = Set<String>.from((result['favoriteKinds'] as List?) ?? const <String>[]);
        _ageAtLastOpen = result['ageAtLastOpen'] as int?;
      });
    } catch (_) {
      // Honest, empty — never a fabricated favourites list. `favoriteKinds`
      // stays null (no row renders at all), matching GamePickerScreen's own
      // "null = no live session" contract for a fetch that never succeeded.
      return;
    } finally {
      if (widget.httpClient == null) api.close();
    }

    // Recording HER OWN visit is fire-and-forget, best-effort — the same
    // posture OliveApi.endCall()/InboxScreen's own _markOpenedRemote()
    // already take for a write nothing in the UI blocks on. Deliberately
    // does NOT update `_ageAtLastOpen` with the freshly-recorded value —
    // the Recommended row's own age-unlock half is "what's new SINCE her
    // last visit", i.e. the value the GET above already returned, and
    // overwriting it here would make a game she just unlocked THIS visit
    // vanish from the row before she ever saw it recommended.
    if (_isChild) {
      unawaited(_recordOpen());
    }
  }

  Future<void> _recordOpen() async {
    try {
      final api = await _mintApi();
      try {
        await api.recordGamePickerOpen(widget.childId);
      } finally {
        if (widget.httpClient == null) api.close();
      }
    } catch (_) {
      // Best-effort — a failed visit-stamp is invisible to her either way
      // (it only ever affects a FUTURE visit's age-unlock row), so there is
      // nothing useful to surface here.
    }
  }

  /// Optimistic local toggle — updates `_favoriteKinds` immediately (the
  /// design spec's own "does not await a network round trip inline"), then
  /// persists in the background, reverting on a failed write. The FULL new
  /// list is what the real PUT sends (setGameFavoriteKinds()'s own
  /// full-replace contract) — computed here via game_favorites_logic.dart's
  /// star()/unstar(), the exact favorites.ts contract, ported.
  void _toggleFavorite(String kind, bool nowFavorited) {
    final before = _favoriteKinds ?? <String>{};
    final beforeList = before.toList();
    final afterList = nowFavorited ? fav.star(beforeList, kind) : fav.unstar(beforeList, kind);
    setState(() => _favoriteKinds = afterList.toSet());
    unawaited(_persistFavorites(afterList, fallback: before));
  }

  Future<void> _persistFavorites(List<String> kinds, {required Set<String> fallback}) async {
    try {
      final api = await _mintApi();
      try {
        await api.putGameFavoriteKinds(widget.childId, kinds);
      } finally {
        if (widget.httpClient == null) api.close();
      }
    } catch (_) {
      // Reconcile on a failed write — the design spec's own "reconciling on
      // a failed write" line — rather than leaving her star showing a state
      // that never actually saved.
      if (!mounted) return;
      setState(() => _favoriteKinds = fallback);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't save that favourite — try again."),
        duration: Duration(seconds: 3)));
    }
  }

  GameMeta? _surpriseMe() {
    final picked = fav.randomGame(forAge(widget.childAge), widget.childAge, _lastSurprise);
    if (picked != null) _lastSurprise = picked.kind;
    return picked;
  }

  @override
  Widget build(BuildContext context) => GamePickerScreen(
        childName: widget.childName,
        childAge: widget.childAge,
        onPlay: widget.onPlay,
        extraSections: widget.extraSections,
        favoriteKinds: _favoriteKinds,
        ageAtLastOpen: _ageAtLastOpen,
        onToggleFavorite: _isChild ? null : _toggleFavorite,
        // Wired for the CHILD call site only, matching the design spec's
        // own explicit split: child_home.dart gets a Surprise-me button;
        // guardian_more.dart's "Play together" call site does not (its own
        // job this pass is onToggleFavorite, nothing else — see this
        // file's own header).
        onSurpriseMe: _isChild ? _surpriseMe : null,
      );
}
