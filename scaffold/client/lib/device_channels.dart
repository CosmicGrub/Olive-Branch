// OLIVE BRANCH — §8.11.4 delivery channels, the pure-logic half. UNVERIFIED
// (no Flutter toolchain in tools/verify.sh's automated pipeline — manually
// built and run via `flutter analyze`/`flutter test` this session).
// MASTERFILE §8.11.4.
//
// A DELIBERATELY PARTIAL 1:1 port of packages/devices/src/devices.ts's
// Channel/ChannelCapability/CHANNELS/capability()/channelAdvice() — same
// names and shapes as the original, the same discipline a11y_speech.dart
// already applies porting a11y.ts. Partial on purpose: devices.ts also
// exports admitDevice() and AdmitError, neither ported here, because
// nothing in this client calls them. Porting unused logic 1:1 is exactly
// the kind of "declaration with nothing behind it" MASTERFILE §0 warns
// against — the day a real caller needs admitDevice() client-side, port it
// then, against that caller's actual need.
//
// WHY THIS EXISTS DESPITE BEING FUNCTIONALLY INERT TODAY: push_channel.dart
// reports a real channel to the server for exactly one case this client can
// currently detect — 'ios' (there is nothing ambiguous about "this is
// iOS"). No Android build of this client can yet tell android_play from
// android_amazon from android_bare (see push_channel.dart's own
// registrationAdvice doc comment for the real, credential-free native APIs
// that WOULD answer this, and why building that native bridge is
// explicitly out of scope this pass). Since 'ios' is always push-capable,
// channelAdvice('ios') always returns null today — this file's real logic
// is exercised and tested (device_channels_test.dart), just not yet fed an
// input that produces a non-null result on a real device. That is an
// honest, narrow gap, not a fabricated one: the moment real Android channel
// detection exists, this file needs no changes at all to start mattering.
enum Channel { androidPlay, androidAmazon, androidBare, ios, windows, web }

/// The wire string this client sends to/would receive from the server —
/// server/routes.mjs's DEVICE_CHANNELS set, db/migrations/0015's CHECK
/// constraint, and devices.ts's own Channel union all use these exact
/// snake_case values.
extension ChannelWire on Channel {
  String get wireValue => switch (this) {
        Channel.androidPlay => 'android_play',
        Channel.androidAmazon => 'android_amazon',
        Channel.androidBare => 'android_bare',
        Channel.ios => 'ios',
        Channel.windows => 'windows',
        Channel.web => 'web',
      };
}

enum ChannelFallback { foregroundSocketAndSms, foregroundSocket, none }

class ChannelCapability {
  const ChannelCapability({
    required this.channel,
    required this.push,
    required this.fallback,
    required this.note,
  });
  final Channel channel;
  final bool push;
  final ChannelFallback fallback;
  final String note;
}

/// Same six rows, same push/fallback facts, same notes as devices.ts's own
/// CHANNELS — kept in sync by hand across languages (there is no shared
/// schema TS and Dart can both compile against in this codebase), same as
/// every other cross-language constant pair here. transport.test.mjs-style
/// drift is not automatically caught for this one the way MethodChannel
/// name literals are; device_channels_test.dart instead cross-checks every
/// value here against a value list mirroring devices.test.mjs's own.
const List<ChannelCapability> channels = <ChannelCapability>[
  ChannelCapability(channel: Channel.androidPlay, push: true,
    fallback: ChannelFallback.foregroundSocket, note: 'FCM.'),
  ChannelCapability(channel: Channel.androidAmazon, push: false,
    fallback: ChannelFallback.foregroundSocketAndSms,
    note: 'FireOS has no Play Services. A great many families use a £50 Fire '
        "tablet as the child's device, and with FCM alone every notification "
        'would be built, dispatched and silently discarded.'),
  ChannelCapability(channel: Channel.androidBare, push: false,
    fallback: ChannelFallback.foregroundSocketAndSms,
    note: 'De-Googled Android. Same failure, rarer cause.'),
  ChannelCapability(channel: Channel.ios, push: true,
    fallback: ChannelFallback.foregroundSocket, note: 'APNS.'),
  ChannelCapability(channel: Channel.windows, push: true,
    fallback: ChannelFallback.foregroundSocket,
    note: 'WNS where available; the desktop client holds a socket regardless.'),
  ChannelCapability(channel: Channel.web, push: false,
    fallback: ChannelFallback.foregroundSocket,
    note: 'Web Push is too inconsistent to rely on for a child hearing from a parent.'),
];

ChannelCapability capability(Channel c) =>
    channels.firstWhere((x) => x.channel == c);

/// What a guardian is told when the child's device cannot push. Plain, not
/// alarming. 1:1 with devices.ts's own channelAdvice() copy, word for word.
String? channelAdvice(Channel c) {
  final cap = capability(c);
  if (cap.push) return null;
  return cap.fallback == ChannelFallback.foregroundSocketAndSms
      ? 'Her tablet cannot show pop-up alerts, so she sees new things when she '
        'opens Olive — and we can text the grown-up there if something is waiting.'
      : 'Her device cannot show pop-up alerts. She sees new things when she opens Olive.';
}
