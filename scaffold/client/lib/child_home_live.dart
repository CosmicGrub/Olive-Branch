// OLIVE BRANCH — live-backed child home. UNVERIFIED at the live-device/live-
// server level (this screen has never been run against a real deployed
// backend or a paired Wear OS watch). tools/verify.sh's own automated
// pipeline still has no Flutter toolchain, so this marker stays present —
// but see wear_sync_channel.dart's own header for the real, actually-run
// `flutter analyze`/`flutter test` verification this file's own §21.5
// changes got this pass, against a real local Flutter toolchain. MASTERFILE
// §7, §8.1.
//
// The first screen in this app wired to real network calls rather than
// hardcoded demo constants (see main.dart's own header, and server/index.mjs
// for what's actually running behind it). Reuses ChildHome unmodified — this
// widget's only job is fetching real data and mapping it onto ChildHome's
// existing constructor, so every invariant ChildHome's own test suite already
// asserts (her name not an id, no settings affordance, sleeps not hours,
// HER frame first) still holds for the live path with zero duplicated logic.
//
// All four of ChildHome's fields are real now. `presence` (this pass) is
// backed by the real GET .../presence route (api_client.dart's
// `fetchPresence` / `childPresence` path) -- see `_load()` below for how a
// failure there is kept from breaking the rest of this screen, and
// `ParentPresence`'s own construction for how the server's `free` shape maps
// onto ChildHome's existing constructor field unchanged (ChildHome itself is
// untouched -- its `_PresenceCard` already renders nothing when `presence`
// is null, an honest absence, not a guess, exactly as before).
// sleepsUntilHandover, unreadCount, and childName are ALL real too.
// sleepsUntilHandover (v0.49.15): a prior pass found the real custody
// endpoint (db/migrations/0007_custody_order.sql, packages/db/src/pool.mjs's
// activeCustodyOrderFor, routes.mjs's /now calling schedule.mjs's real
// sleepsUntilSideChange) had landed and stayed landed, but this screen never
// called it -- OliveApi.fetchNow() existed, contract-checked, with zero
// callers anywhere in this client. `_load()` now calls it alongside
// fetchMe()/fetchInbox() and reads its real `sleepsUntilHandover` key
// (honestly `null` when the child has no active custody_order row -- /now's
// own documented absence, not this screen inventing a second one).
// unreadCount (v0.49.15): was counting EVERY row /inbox returns, but that
// route deliberately includes both `'delivered'` (unwatched) and `'opened'`
// (already watched) messages (server/routes.mjs's own query) -- a child who
// had watched every message still saw a badge claiming all of them were new.
// Now filtered to `state == 'delivered'` before counting.
//
// Phone -> watch sync (§21.5): this screen is the one real place a live
// `sleepsUntilHandover` reaches wear_sync_channel.dart's WearSyncChannel,
// which pushes it to a paired Wear OS companion via the Data Layer API
// (android/app/.../WearSyncBridge.kt on the native side). `_syncWear()`
// below only ever forwards `_sleepsUntilHandover` itself, so as of v0.49.15
// this is a real sync of a real value whenever an active custody order
// exists, and correctly still a no-op (never a placeholder) when it doesn't
// -- see wear_sync_channel.dart's own doc comment on why a guess must never
// be sent.
//
// Watch -> phone (§21.5, new this pass): this is also the one real place a
// watch's "Call Dad" tap reaches this client. `_handleWatchCallDad()` below
// is registered against `_wearSync.listenForCallDad()` in `initState()`
// (before `_load()` even resolves, so a tap arriving unusually early is
// still caught) and opens the exact same real `CallScreen(who: 'ivy', ...)`
// child_home.dart's own existing "Call Dad" button (`_PresenceCard`) already
// opens -- see wear_sync_channel.dart's and WearSyncBridge.kt's own headers
// for the full watch -> phone -> Dart path and for exactly why THIS is the
// honest target rather than guardian_more.dart's guardian-only real
// `POST /v1/children/:childId/calls` route (server/routes.mjs refuses a
// child session there by design). Gated on `widget.navigatorKey` being
// supplied, same posture as `_initPush`'s own `buildCallIncomingHandler`
// wiring below -- null there is not a regression, it's the same honest gap
// every build without a navigator key already had.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'call_knock_screen.dart' show buildCallIncomingHandler;
import 'call_screen.dart';
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
    this.navigatorKey,
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
  /// The real, previously-missing wire call_knock_screen.dart's own header
  /// named directly: "a `call_incoming` push carries only kind/ref/
  /// callHandle — buildCallIncomingHandler is real, tested wiring ready to
  /// pass as PushChannel.onForegroundPointer the day this client's root
  /// widget gains a `GlobalKey&lt;NavigatorState&gt;` — it doesn't have one yet."
  /// Null (the default) means exactly what it always meant here: an
  /// incoming call push falls through to PushChannel's own generic debug-
  /// log fallback instead of opening CallKnockScreen — not a regression,
  /// the same behavior every build without this param already had.
  final GlobalKey<NavigatorState>? navigatorKey;

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
  // Real, fetched from GET .../presence in `_load()` below. Honestly null
  // whenever the server reports `{free: null}`, OR whenever the presence
  // fetch itself failed -- both are the same "no live signal to show" state
  // from ChildHome's own point of view, matching `_sleepsUntilHandover`'s
  // own null-is-honest-absence posture above.
  ParentPresence? _presence;
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
    // Registered before `_load()` resolves on purpose -- see file header.
    _wearSync.listenForCallDad(_handleWatchCallDad);
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
      final now = await api.fetchNow(widget.childId);
      // Fetched in its own try/catch, deliberately NOT alongside the three
      // awaits directly above: presence is a supplementary signal, not core
      // to this screen's own readiness, matching `_initPush`'s own posture
      // below for push registration (a design-spec-literal inline await
      // here would let a presence-fetch failure throw into this method's
      // outer catch and trap her name/inbox/sleeps behind an error screen
      // too -- this app's established "never let a secondary fetch trap the
      // primary screen" posture, same as `_initPush`'s own comment states).
      Map<String, dynamic>? presenceJson;
      try {
        presenceJson = await api.fetchPresence(widget.childId);
      } catch (e) {
        debugPrint('[olive.presence] not loaded this run: $e');
      }
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      // `entries`, not `messages` -- server/routes.mjs's own GET .../inbox
      // handler renamed its response key: `messages` collided with
      // packages/globalaudit/src/globalaudit.ts's GLOBAL_CHILD_FORBIDDEN
      // list (banned there for an unrelated reason), which meant every real
      // child session hitting this exact call 500'd in production, silently
      // -- see that handler's own comment for the full account. This
      // screen's own header already disclosed why nothing caught it: it has
      // never been run against a real deployed backend.
      final List<dynamic> messages = inbox['entries'] as List;
      setState(() {
        _childName = (me['displayName'] as String?) ?? 'there';
        // Only 'delivered' (unwatched) messages count toward the badge --
        // /inbox itself returns BOTH 'delivered' and 'opened' rows (see
        // server/routes.mjs's own query, `state IN ('delivered','opened')`),
        // so counting the raw list length double-counted every message
        // she had already watched as still unread. See file header.
        _unreadCount = messages.where(
            (dynamic m) => (m as Map<String, dynamic>)['state'] == 'delivered').length;
        // Real, fetched from /now -- see file header. Honestly null when
        // the child has no active custody_order row (/now's own absence).
        _sleepsUntilHandover = (now['sleepsUntilHandover'] as num?)?.toInt();
        // §1's own disclosure lives at the server computation site
        // (server/routes.mjs), not here -- this is a pure wire-shape decode,
        // matching how `now`/`inbox` are decoded immediately above.
        final free = presenceJson?['free'] as Map<String, dynamic>?;
        _presence = free == null ? null : ParentPresence(
          free['name'] as String,
          free['theirLocalTime'] as String,
          free['freeUntilHerTime'] as String,
        );
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
  // (§21.5). Real as of v0.49.15 whenever the child has an active custody
  // order (see file header); still correctly a no-op when she doesn't --
  // WearSyncChannel itself has no validation against being handed a
  // placeholder, so the "never send a guess" guarantee lives here, at the
  // one call site.
  Future<void> _syncWear() async {
    final sleeps = _sleepsUntilHandover;
    if (sleeps != null) await _wearSync.syncSleepsUntilHandover(sleeps);
  }

  // Real watch -> phone "Call Dad" handler (§21.5) -- see file header for
  // the full path and why this specific screen (CallScreen(who: 'ivy', ...),
  // no knownRoom) is the honest target. Reads `_childName` live rather than
  // closing over it at registration time, since `listenForCallDad` above
  // runs in `initState()` before `_childName` has a real fetched value --
  // by the time any real watch tap can plausibly arrive (well after this
  // screen has had a chance to load), this reads whatever `_childName`
  // actually is then, same as `ChildHome`'s own build() below already does.
  //
  // Deliberately does NOT check `_state == _LoadState.ready`: a real "Call
  // Dad" tap should reach Dad even if this screen's own name/inbox fetch is
  // still in flight or has failed -- matching this affordance's own
  // unconditional presence on the watch face (no presence gate, unlike
  // child_home.dart's own `_PresenceCard`, which only ever renders when a
  // real `_presence` is both fetched AND non-null -- see file header).
  void _handleWatchCallDad() {
    if (!mounted) return;
    final navigator = widget.navigatorKey?.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => CallScreen(who: 'ivy', displayName: _childName)));
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
        PushChannel(
          OliveApi(widget.baseUrl, token, client: widget.httpClient),
          onForegroundPointer: widget.navigatorKey == null ? null : buildCallIncomingHandler(
            navigatorKey: widget.navigatorKey!,
            // Hardcoded, matching every other call site in this client
            // (CallScreen's own constructors, local-call-room-server.mjs) —
            // a real call_incoming push carries no caller identity by
            // design (push.ts's content-free PushInput shape), so there is
            // nothing to resolve 'from'/'who'/'displayName' from even if
            // this screen wanted to.
            from: 'Dad', who: 'ivy', displayName: 'Ivy',
          ),
        );
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
            presence: _presence, // real, from GET .../presence
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
