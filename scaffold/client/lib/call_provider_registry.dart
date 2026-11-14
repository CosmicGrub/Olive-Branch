// OLIVE BRANCH — the one place that names both call engines. UNVERIFIED on
// real devices (see call_provider.dart). MASTERFILE §16.2 #6, third reversal.
//
// The call screens depend only on call_provider.dart; this registry turns the
// server's grant (`provider`) into the engine that carries it. Keeping both
// concrete engines behind one function is what lets tests/call_ui_imports_test
// .dart assert that no call UI file imports an engine.
import 'call_provider.dart';
import 'jitsi_call_provider.dart';
import 'kiosk_channel.dart';
import 'livekit_call_provider.dart';

CallProvider defaultCallProviderFor(CallGrant grant, {KioskChannel? kiosk}) => switch (grant.kind) {
  CallProviderKind.jitsi => JitsiCallProvider(kiosk: kiosk),
  CallProviderKind.livekit => LiveKitCallProvider(),
};
