// OLIVE BRANCH — the one place that names both call engines. UNVERIFIED on
// real devices (see call_provider.dart). MASTERFILE §16.2 #6, third reversal.
//
// The call screens depend only on call_provider.dart; this registry turns the
// server's grant (`provider`) into the engine that carries it. Keeping both
// concrete engines behind one function is what lets tests/call_ui_imports_test
// .dart assert that no call UI file imports an engine.
import 'call_provider.dart';
import 'call_signaling.dart';
import 'lan_p2p_call_provider.dart';
import 'jitsi_call_provider.dart';
import 'kiosk_channel.dart';
import 'livekit_call_provider.dart';

/// [signaling] is the handshake channel a direct (lan-p2p) call needs; the other engines ignore it. A lan-p2p grant
/// with none is refused with a [CallUnavailableException], which the screens turn into calm wording.
CallProvider defaultCallProviderFor(CallGrant grant, {KioskChannel? kiosk, CallSignaling? signaling}) => switch (grant.kind) {
  CallProviderKind.jitsi => JitsiCallProvider(kiosk: kiosk),
  CallProviderKind.livekit => LiveKitCallProvider(),
  CallProviderKind.lanP2p => signaling == null
      ? throw const CallUnavailableException(CallUnavailableReason.refused, 'no signalling channel for a direct call')
      : LanP2pCallProvider(signaling: signaling),
};
