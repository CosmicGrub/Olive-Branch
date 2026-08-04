// ignore_for_file: avoid_print — a CLI diagnostic script; print is the point.
// OLIVE BRANCH — one-off manual verification script, NOT part of the test
// suite. Runs the real OliveApi/devLoginFor client (client/lib/api_client.dart)
// against a real running server/index.mjs, end to end: no mocks anywhere in
// this file. `dart run bin/live_check.dart` from scaffold/client/, with the
// server already running (see server/index.mjs's own header for the env vars
// it needs).
import 'package:olive_client/api_client.dart';

const ivy = 'aaaaaaaa-0000-4000-8000-000000000001';

Future<void> main() async {
  const base = 'http://127.0.0.1:8123';
  print('Logging in as Ivy (child) against the real server...');
  final token = await devLoginFor(base, childId: ivy);
  print('  got a real session token: ${token.substring(0, 24)}...');

  final api = OliveApi(base, token);
  final me = await api.fetchMe();
  print('GET /v1/me -> $me');

  final now = await api.fetchNow(ivy);
  print('GET /v1/children/:childId/now -> $now');

  final inboxResult = await api.fetchInbox(ivy);
  print('GET /v1/children/:childId/inbox -> $inboxResult');

  api.close();
  print('\nAll real HTTP calls from the Flutter client succeeded against the real server.');
}
