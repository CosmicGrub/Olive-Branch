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
import 'push_channel.dart';
import 'wear_sync_channel.dart';

enum _LoadState { loading, error, ready }

class LiveChildHomeScreen extends StatefulWidget {
  const LiveChildHomeScreen({
    super.key,
    required this.baseUrl,
    required this.childId,
    this.httpClient,
    this.wearSync,
    this.pushChannel,
  });

  final String baseUrl;
  final String childId;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient).
  final http.Client? httpClient;
  /// Injectable for tests, matching kiosk_shell.dart's `channel` param.
  /// Defaults to the real Android-only Data Layer client.
  final WearSyncChannel? wearSync;
  /// Injectable for tests (see push_channel_test.dart). Defaults to a real
  /// [PushChannel] built from the session token this screen fetches for
  /// itself in [_LiveChildHomeScreenState._load] — MASTERFILE §11. This is
  /// the one place in this client a real, authenticated session actually
  /// exists (mirrors this file's own `api`/`token` for the same reason
  /// `_syncWear` piggybacks on it), so push registration lives here rather
  /// than inventing a second, parallel session concept.
  final PushChannel? pushChannel;

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
  // The session token _load() mints is otherwise used-once-and-discarded
  // (only `api` above holds it); retained here so ChildHome's own Homework
  // tile can reach the REAL capture_gate.dart path (§9.1, §20.2b) with the
  // same real session, instead of every child-facing screen needing its own
  // separate dev-login call.
  String? _sessionToken;
  late final WearSyncChannel _wearSync = widget.wearSync ?? WearSyncChannel();
  PushChannel? _pushChannel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pushChannel?.dispose();
    super.dispose();
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
        _sessionToken = token;
        _state = _LoadState.ready;
      });
      await _syncWear();
      await _initPush(token);
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

  // Real permission request + token registration (§11) using the exact
  // session token this screen just fetched for itself above -- the only
  // place this client currently holds a live, authenticated session. Never
  // allowed to fail this screen's own readiness: PushChannel.initialize()
  // throws a real, named PushInitializationError (push_channel.dart) the
  // overwhelming majority of the time this runs, because no real Firebase
  // project config exists in this repo (see pubspec.yaml) -- that failure
  // is real and logged, not hidden, but it stays confined to push. A child
  // or guardian opening this screen must still see their name and inbox
  // count even on a checkout with zero push configuration.
  Future<void> _initPush(String token) async {
    final channel = widget.pushChannel ??
        PushChannel(OliveApi(widget.baseUrl, token, client: widget.httpClient));
    _pushChannel = channel;
    try {
      await channel.initialize();
    } catch (e) {
      debugPrint('[olive.push] not registered this run: $e');
    }
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
            Icon(Icons.cloud_off, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
              style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_errorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onTertiaryContainer))),
          Expanded(child: ChildHome(
            childName: _childName,
            presence: null, // no live day-part/overlap endpoint yet
            sleepsUntilHandover: _sleepsUntilHandover, // still null -- see header and _load()
            unreadCount: _unreadCount,
            // Real homework-capture wiring (§9.1, §20.2b) — the same
            // session _load() already minted, reused rather than each
            // child-facing screen calling devLoginFor() again on its own.
            baseUrl: widget.baseUrl,
            childId: widget.childId,
            sessionToken: _sessionToken,
            httpClient: widget.httpClient,
          )),
        ])));
    }
  }
}
