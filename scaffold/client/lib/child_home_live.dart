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
// Two of ChildHome's four fields have no real data source yet:
//   presence             -- no day-part/overlap endpoint exists server-side,
//                           so this is `null` (ChildHome already renders
//                           nothing when presence is null -- an honest
//                           absence, not a guess).
//   sleepsUntilHandover  -- no custody-schedule endpoint exists yet either,
//                           and unlike presence this field isn't nullable on
//                           ChildHome. Rather than fabricate a number that
//                           would look exactly as real as the two that
//                           genuinely are, a visible banner says so.
// unreadCount and childName ARE real, fetched from /v1/me and /inbox.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'child_home.dart';

enum _LoadState { loading, error, ready }

class LiveChildHomeScreen extends StatefulWidget {
  const LiveChildHomeScreen({
    super.key,
    required this.baseUrl,
    required this.childId,
    this.httpClient,
  });

  final String baseUrl;
  final String childId;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient).
  final http.Client? httpClient;

  @override
  State<LiveChildHomeScreen> createState() => _LiveChildHomeScreenState();
}

class _LiveChildHomeScreenState extends State<LiveChildHomeScreen> {
  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';
  String _childName = '';
  int _unreadCount = 0;

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
        _state = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is ApiException ? '${e.statusCode}: ${e.error}' : '$e';
        _state = _LoadState.error;
      });
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
            sleepsUntilHandover: null, // no live custody-schedule endpoint yet
            unreadCount: _unreadCount,
          )),
        ])));
    }
  }
}
