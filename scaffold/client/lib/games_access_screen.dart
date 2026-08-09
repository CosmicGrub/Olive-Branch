// OLIVE BRANCH — guardian shell, games access. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §5.18,
// §5.17. db/migrations/0008_games_access.sql, server/routes.mjs's
// `PATCH /v1/children/:childId/games-access`.
//
// House convention, restated here because it is the whole point of this
// screen: no settings affordance ever on a child-facing surface -- a
// lock/unlock CONTROL lives only on the guardian side, and the child side
// may only ever passively show whether games are on or off. This is that
// control. The games themselves (packages/games/src/*, and every existing
// game screen) are untouched by this file -- it is purely an access gate
// wrapped around them, calling the real, already-landed backend route, not
// a local-only flag.
//
// Deliberately NOT bound to a live read of the current value on open. The
// only server-side read of `games_enabled` is `GET /v1/me` for a CHILD
// principal (server/routes.mjs) -- there is no analogous guardian-facing GET
// route, so a guardian screen has no honest live source for "is this
// currently on" before it acts. Rather than guess (house rule: never
// fabricate data -- an absent real source means absent, not guessed), this
// screen starts from the one fact that IS real and documented -- games are
// locked by default for every child who has never been toggled (the
// migration's own `games_enabled boolean NOT NULL DEFAULT false`) -- and
// only ever claims a specific "on"/"off" state once the server has actually
// confirmed it, via this screen's own successful PATCH response. Before that,
// the status line says plainly that nothing has been confirmed yet, rather
// than asserting a value nobody has actually read.
//
// Loading/error/success states mirror child_home_live.dart's own honest
// pattern: a failed toggle reverts the switch to whatever was last actually
// true (never leaves it looking like the flip succeeded when it didn't), and
// the error banner shows the real server-reported reason, not a
// paraphrase.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias
const _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy
const _defaultGuardianUserId = String.fromEnvironment('OLIVE_GUARDIAN_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000002'); // seed-dev.mjs's Dad

enum _ToggleStatus { unset, saving, confirmed, error }

class GamesAccessScreen extends StatefulWidget {
  const GamesAccessScreen({
    super.key,
    this.childName = 'Ivy',
    this.baseUrl = _defaultBaseUrl,
    this.childId = _defaultChildId,
    this.guardianUserId = _defaultGuardianUserId,
    this.httpClient,
  });

  final String childName;
  final String baseUrl;
  final String childId;
  final String guardianUserId;
  /// Injectable for tests, matching child_home_live.dart's own `httpClient` param.
  final http.Client? httpClient;

  @override
  State<GamesAccessScreen> createState() => _GamesAccessScreenState();
}

class _GamesAccessScreenState extends State<GamesAccessScreen> {
  // Honest default -- see file header. Never presented as a confirmed read;
  // `_status` (below) is what actually gates the wording shown on screen.
  bool _gamesEnabled = false;
  _ToggleStatus _status = _ToggleStatus.unset;
  String _errorMessage = '';
  // The value a failed attempt tried to set, so "Try again" retries the
  // guardian's actual intent rather than silently re-sending the old one.
  bool? _pendingRetryValue;

  Future<void> _setGamesEnabled(bool desired) async {
    final bool previous = _gamesEnabled;
    setState(() {
      _gamesEnabled = desired;
      _status = _ToggleStatus.saving;
      _errorMessage = '';
    });
    try {
      final token = await devLoginFor(widget.baseUrl,
          userId: widget.guardianUserId, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      final result = await api.setGamesEnabled(widget.childId, desired);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      setState(() {
        // The server's own returned value, never the locally-optimistic one
        // -- if it somehow disagreed with `desired` this is what actually won.
        _gamesEnabled = (result['gamesEnabled'] as bool?) ?? desired;
        _status = _ToggleStatus.confirmed;
        _pendingRetryValue = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // A failed toggle must not silently look like it worked.
        _gamesEnabled = previous;
        _status = _ToggleStatus.error;
        _pendingRetryValue = desired;
        _errorMessage = e is ApiException ? '${e.statusCode}: ${e.error}' : '$e';
      });
    }
  }

  void _retry() {
    final bool? v = _pendingRetryValue;
    if (v != null) _setGamesEnabled(v);
  }

  String _statusLine() {
    switch (_status) {
      case _ToggleStatus.unset:
        return 'Not confirmed yet this session -- games start locked by default.';
      case _ToggleStatus.saving:
        return 'Saving…';
      case _ToggleStatus.confirmed:
        return _gamesEnabled
            ? 'On for ${widget.childName} -- confirmed by the server.'
            : 'Off for ${widget.childName} -- confirmed by the server.';
      case _ToggleStatus.error:
        return 'Not changed -- see below.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool saving = _status == _ToggleStatus.saving;
    return Scaffold(
      appBar: AppBar(title: const Text('Games access')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          'Games start locked for every child. Turning this on lets '
          "${widget.childName} open the built-in games from her own screen; "
          'turning it off locks them again. She can only ever see whether '
          'games are on or off -- never this switch.',
          style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
        const SizedBox(height: 16),
        Card(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SwitchListTile(
            title: const Text('Allow games'),
            subtitle: Text(_statusLine()),
            value: _gamesEnabled,
            onChanged: saving ? null : (bool v) => _setGamesEnabled(v),
            secondary: saving
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_gamesEnabled ? Icons.sports_esports : Icons.lock_outline),
          ))),
        if (_status == _ToggleStatus.error) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  "Couldn't reach the server -- ${widget.childName}'s games "
                  'access was not changed.',
                  style: TextStyle(fontSize: 12.5, color: scheme.onErrorContainer))),
              ]),
              const SizedBox(height: 4),
              Text(_errorMessage,
                style: TextStyle(fontSize: 11, color: scheme.onErrorContainer)),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft,
                child: FilledButton(onPressed: _retry, child: const Text('Try again'))),
            ])),
        ],
      ])),
    );
  }
}
