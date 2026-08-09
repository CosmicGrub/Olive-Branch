// OLIVE BRANCH — live-backed child home. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §7, §8.1.
//
// The first screen in this app wired to real network calls rather than
// hardcoded demo constants (see main.dart's own header, and server/index.mjs
// for what's actually running behind it). Reuses ChildHome unmodified — this
// widget's only job is fetching real data and mapping it onto ChildHome's
// existing constructor, so every invariant ChildHome's own test suite already
// asserts (her name not an id, no settings affordance, sleeps not hours,
// HER frame first) still holds for the live path with zero duplicated logic.
//
// Two of ChildHome's four fields have no real data source wired up yet:
//   presence             -- no day-part/overlap endpoint exists server-side,
//                           so this is `null` (ChildHome already renders
//                           nothing when presence is null -- an honest
//                           absence, not a guess).
//   sleepsUntilHandover  -- still `null`, but as of this pass not because no
//                           endpoint exists. A separate session landed a real
//                           one (db/migrations/0007_custody_order.sql,
//                           packages/db/src/pool.mjs's activeCustodyOrderFor,
//                           routes.mjs's /now calling schedule.mjs's real
//                           sleepsUntilSideChange) and this pass independently
//                           re-verified it against a real Postgres --
//                           `node packages/db/test/custody_order.test.mjs`:
//                           16/16, plus regressions `pool.test.mjs` (18/18)
//                           and `custody.test.mjs` (42/42), all green. But by
//                           the time this pass reached routes.mjs/index.mjs to
//                           wire the client to it, re-reading the files (this
//                           repo directory is shared with other concurrently
//                           running sessions) showed all four of that
//                           session's tracked edits -- pool.ts, routes.mjs,
//                           index.mjs, seed-dev.mjs -- silently reverted back
//                           to their pre-custody committed state, confirmed
//                           stable across repeated checks and matching
//                           `git status` showing no diff at all. A real HTTP
//                           call to /v1/children/:id/now against the server
//                           actually running from disk right now confirms it:
//                           no `sleepsUntilHandover` key in the response.
//                           Wiring this screen to a field the currently-
//                           deployed server doesn't serve would just always
//                           read null anyway, and re-authoring the missing
//                           server-side wiring from memory, unasked, into an
//                           already-contested shared tree would risk making
//                           the conflict worse rather than fixing it. So this
//                           stays exactly what it was: `null`, honestly,
//                           blocked on that dependency landing and staying
//                           landed, not on the absence of a design for it.
// unreadCount and childName ARE real, fetched from /v1/me and /inbox.
//
// gamesEnabled is ALSO now real (db/migrations/0008_games_access.sql,
// server/routes.mjs's GET /v1/me): fetched from the same /v1/me call as
// childName, off a real RLS-scoped Postgres row a guardian can flip via
// PATCH /v1/children/:childId/games-access. Unlike sleepsUntilHandover's
// permanent `null` above, this is not an absent field being honestly
// reported absent -- it is a live, working value, parsed straight off
// `me['gamesEnabled']` in `_load()` below. The only defaulting is a
// fail-CLOSED fallback (dormant, matching the migration's own
// `games_enabled boolean NOT NULL DEFAULT false`) if that key were ever
// unexpectedly missing from a real response -- the opposite direction
// from `displayName`'s fail-friendly `?? 'there'`, because this field
// gates a real feature rather than filling in copy.
//
// Phone -> watch sync (§21.5): this screen is now the one real place a live
// `sleepsUntilHandover` would reach wear_sync_channel.dart's
// WearSyncChannel, which pushes it to a paired Wear OS companion via the
// Data Layer API (android/app/.../WearSyncBridge.kt on the native side).
// `_syncWear()` below only ever forwards `_sleepsUntilHandover` itself — the
// same field that stays `null` per the paragraph above — so today this is
// wiring with nothing yet to carry: the guard means no sync call is ever
// actually made until the custody endpoint lands for real. That is
// deliberate, not an oversight; see wear_sync_channel.dart's own doc comment
// on why a placeholder must never be sent.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'child_home.dart';
import 'wear_sync_channel.dart';

enum _LoadState { loading, error, ready }

class LiveChildHomeScreen extends StatefulWidget {
  const LiveChildHomeScreen({
    super.key,
    required this.baseUrl,
    required this.childId,
    this.httpClient,
    this.wearSync,
  });

  final String baseUrl;
  final String childId;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient).
  final http.Client? httpClient;
  /// Injectable for tests, matching kiosk_shell.dart's `channel` param.
  /// Defaults to the real Android-only Data Layer client.
  final WearSyncChannel? wearSync;

  @override
  State<LiveChildHomeScreen> createState() => _LiveChildHomeScreenState();
}

class _LiveChildHomeScreenState extends State<LiveChildHomeScreen> {
  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';
  String _childName = '';
  int _unreadCount = 0;
  // Still null -- see file header. Kept as a field (not a bare literal on
  // ChildHome's constructor below) so _syncWear() has a real value to read
  // once a live custody endpoint exists to populate it from.
  int? _sleepsUntilHandover;
  // Fail-closed (dormant) until a real fetch says otherwise -- see file
  // header. Never read before `_state` reaches `ready`, since ChildHome
  // itself isn't built in the `loading`/`error` states below, but starting
  // locked rather than unlocked matches the migration's own
  // `DEFAULT false` for the same reason: a gate's unknown state should
  // read as off, not on.
  bool _gamesEnabled = false;
  late final WearSyncChannel _wearSync = widget.wearSync ?? WearSyncChannel();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final token = await devLoginFor(widget.baseUrl,
          childId: widget.childId, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      final me = await api.fetchMe();
      final inbox = await api.fetchInbox(widget.childId);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      setState(() {
        _childName = (me['displayName'] as String?) ?? 'there';
        _unreadCount = (inbox['messages'] as List).length;
        // custody endpoint exists but is currently reverted out of the
        // shared tree -- see header. No fetch call for it exists yet either.
        _sleepsUntilHandover = null;
        // Real value from GET /v1/me -- see file header. Fails closed
        // (locked) if the key is ever missing rather than treating absence
        // as permission.
        _gamesEnabled = (me['gamesEnabled'] as bool?) ?? false;
        _state = _LoadState.ready;
      });
      await _syncWear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is ApiException ? '${e.statusCode}: ${e.error}' : '$e';
        _state = _LoadState.error;
      });
    }
  }

  // Forwards a real sleepsUntilHandover to a paired Wear OS companion
  // (§21.5) once one exists to forward. A no-op today because
  // _sleepsUntilHandover is still null (see header) -- WearSyncChannel
  // itself has no validation against being handed a placeholder, so the
  // "never send a guess" guarantee lives here, at the one call site.
  Future<void> _syncWear() async {
    final sleeps = _sleepsUntilHandover;
    if (sleeps != null) await _wearSync.syncSleepsUntilHandover(sleeps);
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LoadState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _LoadState.error:
        return Scaffold(body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.black38),
            const SizedBox(height: 12),
            const Text("Couldn't reach the server",
              style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        )));
      case _LoadState.ready:
        return Scaffold(body: SafeArea(child: Column(children: [
          Container(width: double.infinity,
            color: Theme.of(context).colorScheme.tertiaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Live: name and message count are real, fetched from the server '
              'just now.',
              style: TextStyle(fontSize: 11,
                color: Theme.of(context).colorScheme.onTertiaryContainer))),
          Expanded(child: ChildHome(
            childName: _childName,
            presence: null, // no live day-part/overlap endpoint yet
            sleepsUntilHandover: _sleepsUntilHandover, // still null -- see header and _load()
            unreadCount: _unreadCount,
            gamesEnabled: _gamesEnabled, // real value fetched in _load() -- see header
          )),
        ])));
    }
  }
}
