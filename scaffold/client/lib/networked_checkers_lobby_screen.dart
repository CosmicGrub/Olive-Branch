// OLIVE BRANCH — the real entry point for LIVE network play. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline) — manually run
// via `flutter analyze`/`flutter test` as part of this feature's own
// security review; see networked_checkers_lobby_screen_test.dart. Two
// paired devices play one checkers game against each other, relayed through
// this app's own authenticated backend server (never peer-to-peer, never
// LAN-broadcast/discovery-based) — see scaffold/packages/game-sync/src/
// table.ts and scaffold/server/game_tables.mjs for the server-side half of
// this contract.
//
// Reachable from games_hub.dart's "Checkers — play live" tile.
//
// Honesty note: nothing in client/lib currently threads a real backend
// session through the widget tree at all — child_home.dart hands
// GamesHubScreen a hardcoded `childName` string, not a session (see that
// file's own header comment). Rather than fake a connected session to make
// this screen LOOK wired up, it does the same dev-only bootstrap
// server/index.mjs's own header already describes (`devLoginFor`, fenced
// behind DEV_LOGIN=1 server-side, real credential ceremonies still an open
// gap in this codebase) — so the feature is genuinely reachable and
// operable today, on two real devices/instances, without pretending a
// production login flow exists here that does not.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';
import 'game_checkers.dart';
import 'networked_checkers_channel.dart';

class NetworkedCheckersLobbyScreen extends StatefulWidget {
  const NetworkedCheckersLobbyScreen({
    super.key,
    this.initialBaseUrl = 'http://10.0.2.2:8080',
    this.httpClientForTesting,
    this.wsConnectForTesting,
  });

  final String initialBaseUrl;

  /// Test seam only — production always uses a real `http.Client`.
  final http.Client? httpClientForTesting;
  /// Test seam only — production always opens a real WebSocket.
  final WebSocketChannel Function(Uri)? wsConnectForTesting;

  @override
  State<NetworkedCheckersLobbyScreen> createState() => _NetworkedCheckersLobbyScreenState();
}

class _NetworkedCheckersLobbyScreenState extends State<NetworkedCheckersLobbyScreen> {
  late final _baseUrlCtrl = TextEditingController(text: widget.initialBaseUrl);
  final _userIdCtrl = TextEditingController();
  final _childIdCtrl = TextEditingController();
  final _partnerChildIdCtrl = TextEditingController();
  final _partnerUserIdCtrl = TextEditingController();
  final _joinTableIdCtrl = TextEditingController();
  bool _asChild = false;
  bool _busy = false;
  String? _error;
  OliveApi? _api;
  GameTableTicket? _ticket;

  String? _emptyToNull(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _signIn() async {
    setState(() { _busy = true; _error = null; });
    try {
      final token = await devLoginFor(
        _baseUrlCtrl.text,
        userId: _asChild ? null : _emptyToNull(_userIdCtrl.text),
        childId: _asChild ? _emptyToNull(_childIdCtrl.text) : null,
        client: widget.httpClientForTesting,
      );
      if (!mounted) return;
      setState(() => _api = OliveApi(_baseUrlCtrl.text, token, client: widget.httpClientForTesting));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed: ${e.error}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTable() async {
    final api = _api;
    if (api == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final ticket = await api.requestGameTable(
        game: 'checkers',
        partnerChildId: _emptyToNull(_partnerChildIdCtrl.text),
        partnerUserId: _emptyToNull(_partnerUserIdCtrl.text),
      );
      if (!mounted) return;
      setState(() => _ticket = ticket);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open a table: ${e.error}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinTable() async {
    final api = _api;
    final tableId = _joinTableIdCtrl.text.trim();
    if (api == null || tableId.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final ticket = await api.joinGameTable(tableId);
      if (!mounted) return;
      setState(() => _ticket = ticket);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not join: ${e.error}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPlaying() {
    final ticket = _ticket;
    final api = _api;
    if (ticket == null || api == null) return;
    final wsBase = api.baseUrl.replaceFirst(RegExp('^http'), 'ws');
    final channel = NetworkedCheckersChannel(
      wsUrl: '$wsBase${ticket.wsPath}',
      token: ticket.token,
      mySeat: ticket.seat,
      connect: widget.wsConnectForTesting,
    );
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GameCheckers(network: channel.toHook()),
    ));
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _userIdCtrl.dispose();
    _childIdCtrl.dispose();
    _partnerChildIdCtrl.dispose();
    _partnerUserIdCtrl.dispose();
    _joinTableIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkers — play live')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'This connects two real devices through the app’s own server — '
            'never directly to each other, and only between people the family '
            'graph already says may be in contact.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, key: const Key('lobbyError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          TextField(key: const Key('lobbyBaseUrl'), controller: _baseUrlCtrl,
            decoration: const InputDecoration(labelText: 'Server address')),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const Key('lobbyAsChild'),
            value: _asChild,
            onChanged: api == null ? (v) => setState(() => _asChild = v) : null,
            title: const Text("I'm signing in as the child on this device"),
          ),
          if (_asChild)
            TextField(key: const Key('lobbyChildId'), controller: _childIdCtrl,
              decoration: const InputDecoration(labelText: 'Child id'))
          else
            TextField(key: const Key('lobbyUserId'), controller: _userIdCtrl,
              decoration: const InputDecoration(labelText: 'Guardian/adult id')),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('lobbySignIn'),
            onPressed: (_busy || api != null) ? null : _signIn,
            child: Text(api == null ? 'Sign in' : 'Signed in'),
          ),
          if (api != null) ...[
            const Divider(height: 32),
            Text('Start a new table', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(key: const Key('lobbyPartnerChildId'), controller: _partnerChildIdCtrl,
              decoration: const InputDecoration(labelText: "Partner's child id (if inviting a child)")),
            TextField(key: const Key('lobbyPartnerUserId'), controller: _partnerUserIdCtrl,
              decoration: const InputDecoration(labelText: "Partner's adult id (if inviting a guardian)")),
            const SizedBox(height: 8),
            OutlinedButton(key: const Key('lobbyOpenTable'), onPressed: _busy ? null : _createTable,
              child: const Text('Open a table')),
            const Divider(height: 32),
            Text('…or join a table someone shared with you', style: Theme.of(context).textTheme.titleMedium),
            TextField(key: const Key('lobbyJoinTableId'), controller: _joinTableIdCtrl,
              decoration: const InputDecoration(labelText: 'Table code')),
            OutlinedButton(key: const Key('lobbyJoin'), onPressed: _busy ? null : _joinTable,
              child: const Text('Join')),
          ],
          if (_ticket != null) ...[
            const Divider(height: 32),
            SelectableText('Table code to share: ${_ticket!.tableId}', key: const Key('lobbyTableCode')),
            Text('You are seat ${_ticket!.seat}.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('lobbyStartPlaying'),
              icon: const Icon(Icons.play_arrow),
              onPressed: _startPlaying,
              label: const Text('Start playing'),
            ),
          ],
        ]),
      )),
    );
  }
}
