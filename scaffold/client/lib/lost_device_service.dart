// OLIVE BRANCH — a lost or stolen phone or tablet, as one object the screens talk to. Verified headless against the
// real route shapes (client/test/lost_device_service_test.dart, lost_device_contract_test.dart). MASTERFILE section 7.23.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 7.23).
//
// WHAT THIS IS. The guardian-client half of server migration 0056 (words: lost_device_logic.dart). A grown-up, from a
// phone that works and with their own PIN, can:
//   * see every phone and tablet of the family and what each may be asked,
//   * mark one as lost (it is paused at once; nothing is deleted; reversible for 3 days),
//   * say "I have it" (it comes back, the owner shows their own PIN once on that phone),
//   * say "It is lost" (the cut-off becomes final; a grown-up's phone only by its owner),
//   * for their OWN lost phone: ask that it erases Olive's copy the next time it connects, or take that back.
//
// WHAT IT PROMISES (and tests hold it to):
//   * OPTIONAL. No call is made until a grown-up asks for one, and no failure here is raised outside these screens.
//   * OWN PIN, EVERY TIME. A PIN is held only for the one call that needs it and is never stored.
//   * ADULT WORDS. Every failure leaves as an [AccountFailure] carrying a sentence ([lostProblemFor]).
//   * TWO TAPS ARE ONE REQUEST. A double-tap shares the request already in flight.
//   * THE ANSWER IS CHECKED. A reply that is not the shape the server sends is "I am not sure it went through", never a
//     success.
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'family_account_logic.dart';
import 'family_account_service.dart';
import 'lost_device_logic.dart';
import 'server_transport_policy.dart' show OliveTransport;

/// Builds the lost-device service for [baseUrl] beside [account].
LostDeviceService buildLostDeviceService(String baseUrl, FamilyAccountService account) =>
    LostDeviceService(baseUrl: baseUrl, account: account);

class LostDeviceService {
  LostDeviceService({required this.baseUrl, required FamilyAccountService account, http.Client? client})
      : _account = account,
        _client = client ?? OliveTransport.clientFor(baseUrl),
        _ownsClient = client == null;

  final String baseUrl;
  final FamilyAccountService _account;
  final http.Client _client;
  final bool _ownsClient;
  final Map<String, Future<Object?>> _flights = <String, Future<Object?>>{};

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<T> _run<T>(String key, LostAction action, Future<T> Function() body) {
    final Future<Object?>? running = _flights[key];
    if (running != null) return running.then((Object? v) => v as T);
    final Future<T> f = () async {
      try {
        return await body();
      } on AccountFailure {
        rethrow;
      } catch (e) {
        throw AccountFailure(lostProblemFor(e, action));
      }
    }();
    _flights[key] = f;
    return f.whenComplete(() => _flights.remove(key));
  }

  static AccountFailure _fix(String message, String reason) =>
      AccountFailure(AccountProblem(message, ProblemKind.fixInput, reason: reason));

  static AccountFailure _unexpected() => const AccountFailure(AccountProblem(
      'The server answered in a way Olive did not expect. Nothing was changed. Look at the list again before you try a '
      'second time.',
      ProblemKind.tryAgain,
      reason: 'unexpected_reply'));

  static bool _looksLikeId(String s) => s.isNotEmpty && s.length <= 64 && RegExp(r'^[0-9a-fA-F-]+$').hasMatch(s);

  /// Every phone and tablet this grown-up may see.
  Future<List<FamilyDevice>> devices() => _run<List<FamilyDevice>>('devices', LostAction.load, () async {
        final Map<String, dynamic> j = await _account.signedCall((String t) => fetchFamilyDevices(baseUrl, t, client: _client));
        if (j['devices'] is! List) throw _unexpected();
        return parseFamilyDevices(j);
      });

  Future<DeviceActionResult> _act(
    String flight,
    LostAction action,
    String deviceId,
    String pin,
    Future<Map<String, dynamic>> Function(String token) call,
  ) =>
      _run<DeviceActionResult>('$flight:$deviceId', action, () async {
        if (!_looksLikeId(deviceId)) throw _unexpected();
        if (!looksLikePin(pin)) throw _fix('Type your PIN. It is 4 to 8 digits.', 'pin_required');
        final DeviceActionResult? r = DeviceActionResult.tryParse(await _account.signedCall(call));
        if (r == null) throw _unexpected();
        return r;
      });

  /// Marks a device as lost: paused at once, nothing deleted, 3 days to change one's mind.
  Future<DeviceActionResult> markLost({required String deviceId, required String pin}) =>
      _act('mark', LostAction.mark, deviceId, pin,
          (String t) => markDeviceLostCall(baseUrl, t, deviceId: deviceId, pin: pin, client: _client));

  /// "I have it". Must quote the incident the list showed, so an old answer can never undo a newer loss.
  Future<DeviceActionResult> found({required String deviceId, required String incidentId, required String pin}) =>
      _act('found', LostAction.found, deviceId, pin,
          (String t) => deviceFoundCall(baseUrl, t, deviceId: deviceId, incidentId: incidentId, pin: pin, client: _client));

  /// "It is lost": the cut-off becomes final.
  Future<DeviceActionResult> confirmLost({required String deviceId, required String incidentId, required String pin}) =>
      _act('confirm', LostAction.confirm, deviceId, pin,
          (String t) => confirmDeviceLostCall(baseUrl, t, deviceId: deviceId, incidentId: incidentId, pin: pin, client: _client));

  /// THIS phone was marked as lost and has been found: its owner types their own PIN once and it gets its sign-in
  /// back. Returns normally on success. A phone that is still paused, or a wrong PIN, says so in words.
  Future<void> resumeThisPhone({required String pin}) => _run<void>('resume', LostAction.found, () async {
        if (!looksLikePin(pin)) throw _fix('Type your PIN. It is 4 to 8 digits.', 'pin_required');
        await _account.resumeThisPhone(pin);
      });

  /// Ask a lost grown-up phone to erase Olive's copy the next time it connects. The phone's owner only.
  Future<DeviceActionResult> orderWipe({required String deviceId, required String pin}) =>
      _act('order', LostAction.orderWipe, deviceId, pin,
          (String t) => orderDeviceWipeCall(baseUrl, t, deviceId: deviceId, pin: pin, client: _client));

  /// Take that back before the phone has carried it out.
  Future<DeviceActionResult> cancelWipe({required String deviceId, required String pin}) =>
      _act('cancel', LostAction.cancelWipe, deviceId, pin,
          (String t) => cancelDeviceWipeCall(baseUrl, t, deviceId: deviceId, pin: pin, client: _client));
}
