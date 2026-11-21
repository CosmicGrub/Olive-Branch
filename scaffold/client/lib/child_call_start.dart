// OLIVE BRANCH - the CHILD calls an approved grown-up. MASTERFILE 5.25.2, 5.27 (2026-11-21).
//
// Her tap on "Call Dad" used to open a call screen with nothing behind it. Now it asks the server to start a call
// to a grown-up of hers (POST .../calls as a child session), and the server decides who may be called: only a
// parent-role guardian whose own edge to her still passes can('call'). She names nobody she is not connected to.
//
// WHAT SHE SEES: the dialing screen, then the call. If it cannot start (the server is off, it is her quiet time,
// no grown-up can be rung) she sees ONE soft line and is back where she was. Never an error, a code, a reason that
// blames anyone, a count, or a PIN. The reason stays in the log.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart' show ApiException, OliveApi;
import 'call_provider.dart' show CallGrant;
import 'call_screen.dart';
import 'call_signaling.dart' show ServerCallSignaling;

/// The only two lines a child can be shown when a call does not start. No banned word (call_provider.dart's
/// [callBannedWords] is asserted over these in test), no cause, no blame.
const String childCallRestingLine = "It's quiet time. Calls will be here later.";
const String childCallLaterLine = "Let's try again in a little while.";

/// Which of the two lines an error becomes. Pure, so it is tested without a screen.
String childCallFailureLine(Object e) =>
    e is ApiException && e.error == 'quiet_hours' ? childCallRestingLine : childCallLaterLine;

Future<void> startChildCall(
  BuildContext context, {
  required Future<OliveApi> Function() apiProvider,
  required String childId,
  required String childName,
  String? toUserId,
}) async {
  try {
    final OliveApi api = await apiProvider();
    final Map<String, dynamic> started;
    try {
      started = await api.startCall(childId, toUserId: toUserId);
    } finally {
      api.close();
    }
    final CallGrant grant = CallGrant.fromJson(started);
    final String? sessionId = started['sessionId'] as String?;
    final Object? toName = started['toName'];
    if (!context.mounted) return;
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CallScreen(
        who: 'ivy',
        displayName: childName,
        remoteLabel: toName is String && toName.trim().isNotEmpty ? toName.trim() : null,
        knownGrant: grant,
        knownToken: grant.token,
        knownWsURL: grant.wsURL,
        signalingFactory: ServerCallSignaling.factory(apiProvider, childId),
        onCallEnd: sessionId == null ? null : () => _endChildCall(apiProvider, childId, sessionId),
      ),
    )));
  } catch (e) {
    debugPrint('[olive.call] her call did not start: ${e is ApiException ? '${e.statusCode} ${e.error}' : e.runtimeType}');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(childCallFailureLine(e)), duration: const Duration(seconds: 3)));
  }
}

/// Record-keeping only: closes the call's log row. Silent on failure, always.
Future<void> _endChildCall(Future<OliveApi> Function() apiProvider, String childId, String sessionId) async {
  try {
    final OliveApi api = await apiProvider();
    try {
      await api.endCall(childId, sessionId);
    } finally {
      api.close();
    }
  } catch (_) {
    // nothing about the call depends on this
  }
}
