// UNVERIFIED on a real device and against Google: covered by flutter test only (MASTERFILE 7.20).
// OLIVE BRANCH — starting push for a connected child device, and what each push means. MASTERFILE §11, §7.18.
//
// [PushService.start] is the ONE guarded door to push. It decides, in this order, whether to do anything at all:
//
//   1. no Firebase settings in this build (push_config.dart)  -> NOTHING: the plugin is never touched
//   2. a platform with no push plugin (Windows, tests)         -> nothing
//   3. no signed-in server session on this device              -> nothing (a locally paired tablet has none, and
//                                                                  keeps working exactly as before)
//   4. otherwise: start Firebase, subscribe, fetch the token and register it with `POST /v1/me/device-tokens`
//
// Whatever happens, [start] returns a [PushStart] word and never throws and never shows anything: not a log line
// a child could read, not a banner, not an error. Push is an addition to an app that already works without it.
//
// [PushDispatcher] is what each push KIND means once it reaches the open app. It reads the content-free
// [PushPointer] (kind, ref, callHandle) and nothing else:
//   call_incoming   -> a knock (incoming_call.dart decides whether it is shown)
//   call_cancelled  -> the knock goes away, silently
//   message_ready   -> "something new is waiting": the home may look again; nothing is shown for it
//   anything else   -> ignored (turn_ready, exchange_reminder and dose_due have no sender yet, and an unknown kind
//                      from a newer server must not do anything in an older app)
library;

import 'package:flutter/foundation.dart';

import 'api_client.dart' show OliveApi;
import 'call_lifecycle.dart' show isCallSessionId;
import 'push_channel.dart';
import 'push_config.dart';

enum PushStart { notConfigured, unsupportedPlatform, noSession, failed, started }

class PushService {
  PushService({
    FcmConfig? config,
    this._platformSupported,
    this._channelFactory,
  })  : _config = config,
        _useEnvironment = config == null;

  final FcmConfig? _config;

  /// When no config was handed in, the build's own settings decide (tests hand one in or null explicitly).
  final bool _useEnvironment;
  final bool? _platformSupported;
  final PushChannel Function(OliveApi api, void Function(PushPointer) onPointer)? _channelFactory;

  PushChannel? _channel;

  /// True once the server has accepted this device's token.
  bool get registered => _channel?.hasRegisteredToken ?? false;

  FcmConfig? get _effectiveConfig => _useEnvironment ? FcmConfig.fromEnvironment() : _config;

  Future<PushStart> start({required OliveApi? api, required void Function(PushPointer) onPointer}) async {
    if (!(_platformSupported ?? pushSupportedOnThisPlatform)) return PushStart.unsupportedPlatform;
    if (_effectiveConfig == null) return PushStart.notConfigured;
    if (api == null) return PushStart.noSession;
    final PushChannel channel = _channelFactory != null
        ? _channelFactory(api, onPointer)
        : PushChannel(api, onForegroundPointer: onPointer);
    _channel = channel;
    try {
      await channel.initialize();
      return PushStart.started;
    } catch (e) {
      // Debug log only, and only the kind of failure: the exception text can carry a server's words.
      debugPrint('[olive.push] not started this run: ${e.runtimeType}');
      return PushStart.failed;
    }
  }

  /// Stops listening. Does not unregister the token (that is sign-out's job, push_channel.dart `unregister`).
  void dispose() {
    _channel?.dispose();
    _channel = null;
  }
}

/// What each push kind does in the open app. Every handler is optional; a missing one means "nothing happens".
class PushDispatcher {
  PushDispatcher({this.onCallIncoming, this.onCallCancelled, this.onMessageReady});

  final void Function(String sessionId)? onCallIncoming;
  final void Function(String sessionId)? onCallCancelled;
  final void Function()? onMessageReady;

  void handle(PushPointer pointer) {
    switch (pointer.kind) {
      case 'call_incoming':
        // Only a canonical session id is believed; the incoming-call logic checks again, this keeps a hostile ref
        // from reaching it at all.
        if (isCallSessionId(pointer.ref)) onCallIncoming?.call(pointer.ref);
      case 'call_cancelled':
        if (isCallSessionId(pointer.ref)) onCallCancelled?.call(pointer.ref);
      case 'message_ready':
        onMessageReady?.call();
      default:
        break;
    }
  }
}
