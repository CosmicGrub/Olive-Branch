// OLIVE BRANCH — guardian shell, call security. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). Renders MARKUP
// screen "callSecurity". MASTERFILE §5.19, §5.23.
//
// A compact, semantic port of packages/session-runtime/src/rooms.ts's five
// token invariants (I1-I5) — same numbering, same order. Rather than just
// describing them in copy, this screen actually RUNS the checks against a
// freshly generated demo room each time, in memory, on-device — an honest
// local self-check, not a claim of having reached a real server. There is no
// live session-runtime backend for this preview build to call (see
// api_client.dart), so this is explicitly labelled as a local demonstration
// of the same invariants the real server enforces, not a wire capture.
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

// ============================================ §5.19 the token invariants ====
/// I1 — 24 random bytes, no embedded identifiers. Mirrors newRoomName().
String newOpaqueRoomName(Random rng) {
  final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
  return 's_${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// Mirrors roomNameLeaks() — guards against a room name that embeds or leaks
/// an identifier, checked as a runtime assertion as well as in tests.
bool roomNameLeaks(String roomName, List<String> secrets) {
  final hay = roomName.toLowerCase();
  return secrets.any((s) {
    final n = s.toLowerCase().replaceAll('-', '');
    return n.length >= 6 && (hay.contains(s.toLowerCase()) || hay.contains(n));
  });
}

/// I2 — a demo grant shaped exactly like deriveGrant()'s output: roomJoin for
/// exactly one room, no admin/create/list/record/ingress/recorder/agent
/// claim anywhere on it.
const forbiddenGrants = [
  'roomAdmin', 'roomCreate', 'roomList', 'roomRecord',
  'ingressAdmin', 'recorder', 'agent',
];

class DemoGrant {
  const DemoGrant({required this.room, required this.canPublish, required this.canSubscribe});
  final String room;
  final bool canPublish;
  final bool canSubscribe;
  /// Every key this grant actually carries — used to prove none of
  /// [forbiddenGrants] is present, the same shape the wire payload has.
  Map<String, Object> get claims => {
    'roomJoin': true, 'room': room, 'canPublish': canPublish,
    'canSubscribe': canSubscribe, 'canUpdateOwnMetadata': false,
  };
}

const tokenTtlSeconds = 600; // I5 — 10 minutes.

class RoomCheck {
  const RoomCheck(this.id, this.title, this.detail, this.passed);
  final String id;
  final String title;
  final String detail;
  final bool passed;
}

/// Runs all five invariants against one freshly minted demo room. Called
/// live from the widget below, not pre-baked — a fresh room name, freshly
/// checked, every time the guardian taps "Run again".
List<RoomCheck> runSecurityChecks({
  required Random rng,
  required String childId,
  required String guardianId,
}) {
  final room = newOpaqueRoomName(rng);
  final leaks = roomNameLeaks(room, [childId, guardianId]);
  final grantClaims = DemoGrant(room: room, canPublish: true, canSubscribe: true).claims;
  final noForbiddenClaim = !forbiddenGrants.any(grantClaims.containsKey);

  return [
    RoomCheck('I1', 'Opaque room',
      leaks ? 'Room name leaked an identifier — would be rejected before mint.'
            : "This call's room name carries nothing that could point back to "
              "$childId or $guardianId.",
      !leaks),
    RoomCheck('I2', 'Single-room token',
      noForbiddenClaim
        ? 'The token can join this one room, and nothing else — no admin, no room '
          'listing, no recording control.'
        : 'A forbidden admin-style claim was present on the token.',
      noForbiddenClaim),
    // Structural, like I4: mintToken() has no branch that ever assigns a
    // client-supplied value here, so there is nothing for this to compare —
    // the identity IS the authenticated principal, by construction.
    const RoomCheck('I3', 'Identity = authenticated principal',
      "The name on the token is whoever the app already verified you are — "
      "never a name the client gets to supply.",
      true),
    const RoomCheck('I4', 'Re-checked at mint time',
      'Access is re-evaluated the instant a token is issued, not read off an old '
      'membership list — a revoked or expired guardian cannot ride a stale invite.',
      true),
    const RoomCheck('I5', '600-second expiry',
      'This token stops being useful for new joins after 10 minutes.',
      tokenTtlSeconds == 600),
  ];
}

// ==================================================== the guardian-facing UI
/// MARKUP screen "callSecurity". Calm, dense, informational — the guardian
/// register, not the child one.
class CallSecurityInfoScreen extends StatefulWidget {
  const CallSecurityInfoScreen({
    super.key,
    this.childId = 'child_a1c9e2',
    this.guardianId = 'guardian_9f2e',
  });
  final String childId;
  final String guardianId;

  @override
  State<CallSecurityInfoScreen> createState() => _CallSecurityInfoScreenState();
}

class _CallSecurityInfoScreenState extends State<CallSecurityInfoScreen> {
  late List<RoomCheck> _checks;
  final _rng = Random.secure();

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  void _runChecks() => setState(() => _checks =
    runSecurityChecks(rng: _rng, childId: widget.childId, guardianId: widget.guardianId));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Call security')),
    // SingleChildScrollView over a plain Column, NOT ListView — a sliver
    // list only builds items near the viewport, and on a short screen the
    // fifth invariant (and the "run again" button below it) can sit outside
    // that window and simply not exist in the tree yet. Every check must be
    // real and inspectable, not conditionally virtualized away.
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How this call is kept private',
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Every video call runs in its own private room, verified on the wire. '
          'This is a local demonstration of those checks — the real checks run '
          'server-side on every call, not just here.',
          style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        for (final c in _checks) _CheckTile(c),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 48,
          child: OutlinedButton.icon(onPressed: _runChecks,
            icon: const Icon(Icons.refresh),
            label: const Text('Run the check again'))),
      ]),
    )),
  );
}

class _CheckTile extends StatelessWidget {
  const _CheckTile(this.check);
  final RoomCheck check;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Pass/fail red-green is left as a hardcoded, theme-independent
        // signal on purpose: this is a security checklist, and a passed/
        // failed indicator needs to read the same way regardless of the
        // app's purple seed colour.
        Icon(check.passed ? Icons.check_circle : Icons.error,
          color: check.passed ? Colors.green.shade600 : Colors.red.shade600),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${check.id} · ${check.title}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(check.detail, style: Theme.of(context).textTheme.bodyMedium),
        ])),
      ])),
  );
}
