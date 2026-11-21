// UNVERIFIED on a real device and against Google: covered by flutter test only (MASTERFILE 7.20).
// OLIVE BRANCH — the client half of the call log's life: can a call be placed, did it ring, how does it end.
// MASTERFILE §5.25.2, §7.18. Pure Dart, no platform, covered by test/call_lifecycle_test.dart.
//
// The server writes the call_log row FIRST (so a ring is never sent for a call nobody can join), stamps the
// answer when the child's device asks to join, and records how a call ended: answered, cancelled by the caller,
// declined by the child's device, or stale. It also tells the app, in two small answers, the two things a
// grown-up needs to know BEFORE and RIGHT AFTER tapping Call:
//
//   GET  .../calls/availability  ->  { provider, available, sameNetworkOnly }
//   POST .../calls               ->  { ..., rang, ringState, sessionId }
//
// This file reads both defensively (a field of the wrong type is "unknown", never a guess, never a crash) and
// turns them into plain sentences for the GROWN-UP. A child never reads any of it: her side is the knock
// (call_knock_screen.dart), and nothing she sees names a state, a count, a reason or a failure.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'call_provider.dart' show CallProviderKind, CallUnavailableReason, callUnavailableLine, tabletUnreachableLine;

/// What the server says about placing a call right now. Never carries an address, an app id or a secret: the
/// server sends only a provider name and two booleans.
@immutable
class CallAvailability {
  const CallAvailability({
    required this.provider,
    required this.available,
    required this.sameNetworkOnly,
    this.tabletReachable,
  });

  /// The engine the server would use, or null for a name this build does not know.
  final CallProviderKind? provider;
  final bool available;

  /// True when the call server is only reachable on the home network (a private or single-label address).
  final bool sameNetworkOnly;

  /// lan-p2p, asked by a grown-up: true when her tablet has asked the server in the last few seconds, false when it
  /// has not, null when the server did not say (another provider, an older server, a child asking).
  final bool? tabletReachable;

  /// null when the answer is not usable. `available` must be a real boolean; "true" the string is not true.
  static CallAvailability? tryParse(Object? body) {
    if (body is! Map) return null;
    final Object? available = body['available'];
    if (available is! bool) return null;
    final Object? same = body['sameNetworkOnly'];
    final Object? provider = body['provider'];
    return CallAvailability(
      provider: switch (provider) {
        'jitsi' => CallProviderKind.jitsi,
        'livekit' => CallProviderKind.livekit,
        'lan-p2p' => CallProviderKind.lanP2p,
        _ => null,
      },
      available: available,
      // Only an explicit true narrows the claim; anything else is "no restriction known".
      sameNetworkOnly: available && same == true,
      // Only a real boolean counts; "false" the string, a number or a missing field is "not said".
      tabletReachable: available && body['tabletReachable'] is bool ? body['tabletReachable'] as bool : null,
    );
  }
}

/// Why a device did or did not ring, from the server's single `ringState` word. An unknown or missing word
/// (an older server, a malformed body) is [unknown]: said nothing about, not guessed at.
enum CallRingState { rang, quietHours, noDevices, noPushCapability, sendFailed, tabletUnreachable, unknown }

CallRingState ringStateOf(Object? wire) => switch (wire) {
      'rang' => CallRingState.rang,
      'quiet_hours' => CallRingState.quietHours,
      'no_devices' => CallRingState.noDevices,
      'no_push_capability' => CallRingState.noPushCapability,
      'send_failed' => CallRingState.sendFailed,
      'tablet_unreachable' => CallRingState.tabletUnreachable,
      _ => CallRingState.unknown,
    };

/// A sentence for the grown-up before the call starts, or null when there is nothing to add.
String? availabilityLine(CallAvailability? a) {
  if (a == null) return null;
  if (!a.available) return callUnavailableLine(CallUnavailableReason.providerOff, isGuardian: true);
  // lan-p2p: her tablet is not reaching the server just now. Say so BEFORE the grown-up taps, with one next step.
  if (a.tabletReachable == false) return tabletUnreachableLine;
  if (a.sameNetworkOnly) {
    return 'Calls only work while you and the tablet are both on the home Wi-Fi.';
  }
  return null;
}

/// A sentence for the grown-up right after the call starts, or null when it rang (or when nothing is known).
/// The call itself is already open and joinable whatever the answer is: these only say why a tablet may stay
/// quiet. [childName] is the grown-up's own word for the child; it never reaches the child.
String? ringStateLine(CallRingState state, {String? childName}) {
  final String who = (childName == null || childName.trim().isEmpty) ? 'The tablet' : "${childName.trim()}'s tablet";
  return switch (state) {
    CallRingState.rang || CallRingState.unknown => null,
    CallRingState.quietHours => '$who is in quiet time, so it did not ring. You can wait in the call or leave a message instead.',
    CallRingState.noDevices => '$who has not been set up for rings yet, so it did not ring.',
    CallRingState.noPushCapability => '$who cannot show pop-up alerts, so it did not ring.',
    CallRingState.sendFailed => 'The ring did not go through. You can wait in the call or try again in a little while.',
    CallRingState.tabletUnreachable => tabletUnreachableLine,
  };
}

/// A session id is a canonical UUID (the server mints nothing else). Anything else, including path pieces,
/// is refused BEFORE it is placed in a request path or shown a ring.
final RegExp _sessionIdShape =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
bool isCallSessionId(Object? v) => v is String && v.length == 36 && _sessionIdShape.hasMatch(v);
