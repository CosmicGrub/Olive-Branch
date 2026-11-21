// OLIVE BRANCH — losing a phone without losing anything, as one object the screens talk to. Verified headless against
// the real route shapes (client/test/recovery_paths_service_test.dart, recovery_paths_contract_test.dart).
// MASTERFILE section 7.22.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 7.22).
//
// WHAT THIS IS. The guardian-client half of server migration 0055 (see recovery_paths_logic.dart for the words):
//
//   while a phone still works   a printed recovery sheet (made once, shown once, typed back to prove it was kept) and
//                               ONE trusted helper. Both are own-PIN steps; neither is ever required.
//   another grown-up helps      the grown-up on the working phone starts it (their own PIN is their yes), the family
//                               waits 48 hours, every phone is told, anyone can stop it, then the new phone finishes.
//   one grown-up, no phone      the printed sheet starts it, the family (and the helper, if one was named) waits 72
//                               hours, then the new phone finishes. The helper can ONLY say yes or no.
//
// WHAT IT PROMISES (and tests hold it to):
//   * THE SAME ACCOUNT. A recovery brings this phone into the account it already had. The new sign-in is kept exactly
//     as a new account's is ([FamilyAccountService.adoptRecoveredSignIn]); nothing is made, copied or moved here.
//   * NOTHING SECRET IS KEPT BEYOND NEED. The recovery sheet's key is shown once and never stored by this app. A PIN
//     is held only for the one call that needs it. The code the new phone waits with, and a helper's own key, live
//     in secure storage only, and are deleted when they stop being useful.
//   * ADULT WORDS. Every failure leaves as an [AccountFailure] carrying a sentence ([recoveryProblemFor]).
//   * OPTIONAL. No call is made until a grown-up asks for one, and no failure here is raised outside these screens.
//   * TWO TAPS ARE ONE REQUEST. A double-tap shares the request already in flight.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'device_identity.dart' show FlutterSecureKeyValueStore, SecureKeyValueStore;
import 'family_account_logic.dart';
import 'family_account_service.dart';
import 'recovery_paths_logic.dart';
import 'server_transport_policy.dart' show OliveTransport;

// ---- what the new phone remembers while it waits --------------------------------------------------------------------

/// The recovery this (new) phone is waiting on. The code is a bearer secret for finishing it, so it lives in secure
/// storage and is deleted the moment the recovery ends, on any ending.
class PendingRecovery {
  const PendingRecovery({
    required this.code,
    required this.readyAt,
    required this.soleParent,
    required this.accountName,
    required this.helperRequired,
    required this.savedAt,
  });
  final String code;
  final DateTime readyAt;
  final bool soleParent;
  final String accountName;
  final bool helperRequired;
  final DateTime savedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'readyAt': readyAt.toUtc().toIso8601String(),
        'soleParent': soleParent,
        'accountName': accountName,
        'helperRequired': helperRequired,
        'savedAt': savedAt.toUtc().toIso8601String(),
      };

  /// Refuses a damaged record (a code that cannot be one, no times).
  static PendingRecovery? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? code = raw['code'];
    final DateTime? ready = raw['readyAt'] is String ? DateTime.tryParse(raw['readyAt'] as String) : null;
    final DateTime? saved = raw['savedAt'] is String ? DateTime.tryParse(raw['savedAt'] as String) : null;
    if (code is! String || normaliseRecoveryCode(RecoveryCodeKind.request, code) == null || ready == null || saved == null) {
      return null;
    }
    return PendingRecovery(
        code: code,
        readyAt: ready,
        soleParent: raw['soleParent'] == true,
        accountName: raw['accountName'] is String ? raw['accountName'] as String : '',
        helperRequired: raw['helperRequired'] == true,
        savedAt: saved);
  }
}

abstract class PendingRecoveryStore {
  Future<PendingRecovery?> load();
  Future<void> save(PendingRecovery r);
  Future<void> clear();
}

class MemoryPendingRecoveryStore implements PendingRecoveryStore {
  PendingRecovery? _r;
  @override
  Future<PendingRecovery?> load() async => _r;
  @override
  Future<void> save(PendingRecovery r) async => _r = r;
  @override
  Future<void> clear() async => _r = null;
}

/// In the phone's secure storage (Keystore), beside the device identity.
class SecurePendingRecoveryStore implements PendingRecoveryStore {
  SecurePendingRecoveryStore({SecureKeyValueStore? storage}) : _s = storage ?? const FlutterSecureKeyValueStore();
  final SecureKeyValueStore _s;
  static const String _key = 'olive_pending_recovery';

  @override
  Future<PendingRecovery?> load() async {
    final String? raw = await _s.read(_key);
    if (raw == null) return null;
    try {
      return PendingRecovery.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PendingRecovery r) => _s.write(_key, jsonEncode(r.toJson()));

  @override
  Future<void> clear() => _s.delete(_key);
}

// ---- what a helper's phone remembers --------------------------------------------------------------------------------

/// A trusted helper's own key. It opens the two helper calls (list the recoveries that name them, answer yes or no)
/// and nothing else: it is not a sign-in and cannot become one.
class HelperKey {
  const HelperKey({required this.key, required this.accountName, required this.label});
  final String key;
  final String accountName;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{'key': key, 'accountName': accountName, 'label': label};

  static HelperKey? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? k = raw['key'];
    if (k is! String || k.length < 20 || k.length > 128) return null;
    return HelperKey(
        key: k,
        accountName: raw['accountName'] is String ? raw['accountName'] as String : '',
        label: raw['label'] is String ? raw['label'] as String : '');
  }
}

abstract class HelperKeyStore {
  Future<HelperKey?> load();
  Future<void> save(HelperKey k);
  Future<void> clear();
}

class MemoryHelperKeyStore implements HelperKeyStore {
  HelperKey? _k;
  @override
  Future<HelperKey?> load() async => _k;
  @override
  Future<void> save(HelperKey k) async => _k = k;
  @override
  Future<void> clear() async => _k = null;
}

class SecureHelperKeyStore implements HelperKeyStore {
  SecureHelperKeyStore({SecureKeyValueStore? storage}) : _s = storage ?? const FlutterSecureKeyValueStore();
  final SecureKeyValueStore _s;
  static const String _key = 'olive_recovery_helper_key';

  @override
  Future<HelperKey?> load() async {
    final String? raw = await _s.read(_key);
    if (raw == null) return null;
    try {
      return HelperKey.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(HelperKey k) => _s.write(_key, jsonEncode(k.toJson()));

  @override
  Future<void> clear() => _s.delete(_key);
}

// ---- answers the screens draw ---------------------------------------------------------------------------------------

/// A recovery was started on this phone. The code is kept in secure storage; this is what the screen says.
class RecoveryStarted {
  const RecoveryStarted({required this.readyAt, required this.soleParent, required this.accountName, required this.helperRequired});
  final DateTime readyAt;
  final bool soleParent;
  final String accountName;
  final bool helperRequired;
}

/// A helping grown-up started a recovery for someone else. [code] is for the person on the new phone: hand it over
/// yourself, Olive does not send it.
class HelpStarted {
  const HelpStarted({required this.code, required this.readyAt, required this.targetName, required this.requestId});
  final String code;
  final DateTime readyAt;
  final String targetName;
  final String requestId;
}

/// The invite to hand a trusted helper.
class HelperInvite {
  const HelperInvite({required this.code, required this.expiresAt, required this.replacedOlder});
  final String code;
  final DateTime? expiresAt;
  final bool replacedOlder;
}

class RecoveredResult {
  const RecoveredResult({required this.devicesSignedOut, required this.sheetSpent, required this.children});
  final int devicesSignedOut;
  final bool sheetSpent;
  final int children;
}

/// One recovery that names this phone's owner as the trusted helper. First name and times only.
class HelperRequest {
  const HelperRequest({required this.requestId, required this.accountName, required this.startedAt, required this.readyAt, required this.confirmed});
  final String requestId;
  final String accountName;
  final DateTime startedAt;
  final DateTime readyAt;
  final bool confirmed;
}

/// Builds the recovery service for [baseUrl] on this phone's real storage, beside [account].
RecoveryPathsService buildRecoveryPathsService(String baseUrl, FamilyAccountService account) => RecoveryPathsService(
      baseUrl: baseUrl,
      account: account,
      pending: SecurePendingRecoveryStore(),
      helper: SecureHelperKeyStore(),
    );

// ---- the service ----------------------------------------------------------------------------------------------------

class RecoveryPathsService {
  RecoveryPathsService({
    required this.baseUrl,
    required FamilyAccountService account,
    http.Client? client,
    PendingRecoveryStore? pending,
    HelperKeyStore? helper,
    DateTime Function()? now,
    this.deviceLabel = 'This phone',
  })  : _account = account,
        _client = client ?? OliveTransport.clientFor(baseUrl),
        _ownsClient = client == null,
        _pending = pending ?? MemoryPendingRecoveryStore(),
        _helper = helper ?? MemoryHelperKeyStore(),
        _now = now ?? DateTime.now;

  final String baseUrl;
  final String deviceLabel;
  final FamilyAccountService _account;
  final http.Client _client;
  final bool _ownsClient;
  final PendingRecoveryStore _pending;
  final HelperKeyStore _helper;
  final DateTime Function() _now;
  final Map<String, Future<Object?>> _flights = <String, Future<Object?>>{};

  void dispose() {
    if (_ownsClient) _client.close();
  }

  // ---- plumbing ---------------------------------------------------------------------------------

  Future<T> _run<T>(String key, RecoveryAction action, Future<T> Function() body, {String helperName = ''}) {
    final Future<Object?>? running = _flights[key];
    if (running != null) return running.then((Object? v) => v as T);
    final Future<T> f = () async {
      try {
        return await body();
      } on AccountFailure {
        rethrow;
      } catch (e) {
        throw AccountFailure(recoveryProblemFor(e, action, helperName: helperName));
      }
    }();
    _flights[key] = f;
    return f.whenComplete(() => _flights.remove(key));
  }

  static AccountFailure _fix(String message, String reason) =>
      AccountFailure(AccountProblem(message, ProblemKind.fixInput, reason: reason));

  static AccountFailure _unexpected() => const AccountFailure(AccountProblem(
      'The server answered in a way Olive did not expect. Nothing was changed. Look again before you try a second '
      'time.',
      ProblemKind.tryAgain,
      reason: 'unexpected_reply'));

  Future<T?> _safe<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  Future<void> _refuseIfSignedIn() async {
    if (await _account.signInWorks()) {
      throw const AccountFailure(AccountProblem(
          'This phone is already signed in to an account, and it works. You do not need to do this here.',
          ProblemKind.cannot,
          reason: 'already_signed_in'));
    }
  }

  // =============================================================================================
  //  A grown-up whose phone works: the sheet, the helper, the notices, helping someone else
  // =============================================================================================

  Future<RecoverySummary> summary() => _run<RecoverySummary>('summary', RecoveryAction.loadSummary, () async {
        final Map<String, dynamic> j =
            await _account.signedCall((String t) => fetchRecoverySummary(baseUrl, t, client: _client));
        final RecoverySummary? s = RecoverySummary.tryParse(j);
        if (s == null) throw _unexpected();
        return s;
      });

  /// Makes (or replaces) the printed key. Returns it in groups of four. It is shown ONCE: this app does not keep it,
  /// and the server keeps only a hash. Making a new one ends the old one, and any recovery the old one started.
  Future<String> makeSheet({required String pin}) => _run<String>('makeSheet', RecoveryAction.makeSheet, () async {
        if (!looksLikePin(pin)) throw _fix('Type your PIN. It is 4 to 8 digits.', 'pin_required');
        final Map<String, dynamic> r =
            await _account.signedCall((String t) => makeRecoverySheetCall(baseUrl, t, pin: pin, client: _client));
        final Object? key = r['key'];
        if (key is! String || normaliseRecoveryCode(RecoveryCodeKind.sheet, key) == null) throw _unexpected();
        return groupRecoveryCode(normaliseRecoveryCode(RecoveryCodeKind.sheet, key)!);
      });

  /// "Type it back from the paper". True once the server says it matches (and records that it was kept).
  Future<bool> checkSheet(String typed) => _run<bool>('checkSheet', RecoveryAction.checkSheet, () async {
        final String? key = sendableRecoveryCode(RecoveryCodeKind.sheet, typed);
        if (key == null) {
          throw _fix('Type the whole key from your sheet. It has six groups of four letters and numbers.', 'recovery_key_required');
        }
        final Map<String, dynamic> r =
            await _account.signedCall((String t) => checkRecoverySheetCall(baseUrl, t, key: key, client: _client));
        return r['ok'] == true;
      });

  /// Names the ONE trusted helper and makes the invite to hand them. Naming another removes the first.
  Future<HelperInvite> nameHelper({required String name, required String pin}) =>
      _run<HelperInvite>('nameHelper', RecoveryAction.nameHelper, () async {
        final String? label = cleanHelperName(name);
        if (label == null) {
          throw _fix('Type a first name, like Aunt Sam. It can be up to $kHelperNameMax letters and cannot have an @ in it.', 'invalid_label');
        }
        if (!looksLikePin(pin)) throw _fix('Type your PIN. It is 4 to 8 digits.', 'pin_required');
        final Map<String, dynamic> r = await _account
            .signedCall((String t) => nameRecoveryHelperCall(baseUrl, t, pin: pin, label: label, client: _client));
        final Object? code = r['code'];
        if (code is! String || normaliseRecoveryCode(RecoveryCodeKind.helperInvite, code) == null) throw _unexpected();
        return HelperInvite(
            code: groupRecoveryCode(normaliseRecoveryCode(RecoveryCodeKind.helperInvite, code)!),
            expiresAt: r['expiresAt'] is String ? DateTime.tryParse(r['expiresAt'] as String) : null,
            replacedOlder: r['replacedOlder'] == true);
      });

  Future<void> removeHelper({required String pin}) => _run<void>('removeHelper', RecoveryAction.removeHelper, () async {
        if (!looksLikePin(pin)) throw _fix('Type your PIN. It is 4 to 8 digits.', 'pin_required');
        await _account.signedCall((String t) => removeRecoveryHelperCall(baseUrl, t, pin: pin, client: _client));
      });

  /// A grown-up of the family helps ANOTHER grown-up back in. [pin] is their own: that is their yes. The code that
  /// comes back goes to the person on the new phone.
  Future<HelpStarted> startFor({required String targetUserId, required String pin}) =>
      _run<HelpStarted>('startFor', RecoveryAction.startFor, () async {
        if (!isServerId(targetUserId)) throw _fix('Choose who you are helping.', 'target_required');
        if (!looksLikePin(pin)) throw _fix('Type your PIN. It is 4 to 8 digits.', 'pin_required');
        final Map<String, dynamic> r = await _account.signedCall((String t) =>
            startRecoveryForCall(baseUrl, t, targetUserId: targetUserId, pin: pin, client: _client));
        final Object? code = r['code'];
        final DateTime? ready = r['readyAt'] is String ? DateTime.tryParse(r['readyAt'] as String) : null;
        final Object? id = r['requestId'];
        if (code is! String || normaliseRecoveryCode(RecoveryCodeKind.request, code) == null || ready == null || id is! String) {
          throw _unexpected();
        }
        return HelpStarted(
            code: groupRecoveryCode(normaliseRecoveryCode(RecoveryCodeKind.request, code)!),
            readyAt: ready,
            targetName: r['targetName'] is String ? r['targetName'] as String : '',
            requestId: id);
      });

  /// Stops a recovery that is waiting. Anyone who is told about it may stop it, at any time, with their own PIN.
  Future<void> stop({required String requestId, required String pin}) =>
      _run<void>('stop:$requestId', RecoveryAction.stop, () async {
        if (!isServerId(requestId)) throw _fix('That recovery is not here any more.', 'not_found');
        if (!looksLikePin(pin)) throw _fix('Type your PIN. It is 4 to 8 digits.', 'pin_required');
        await _account.signedCall(
            (String t) => stopRecoveryCall(baseUrl, t, requestId: requestId, pin: pin, client: _client));
      });

  // =============================================================================================
  //  The new phone: no sign-in yet
  // =============================================================================================

  Future<PendingRecovery?> pending() => _safe(_pending.load);

  Future<void> clearPending() async {
    try {
      await _pending.clear();
    } catch (_) {}
  }

  /// One grown-up, the printed sheet: starts the recovery (it waits before anything changes) and keeps the code the
  /// new phone finishes with.
  Future<RecoveryStarted> startWithSheet(String typedKey) =>
      _run<RecoveryStarted>('startWithSheet', RecoveryAction.startWithSheet, () async {
        final String? key = sendableRecoveryCode(RecoveryCodeKind.sheet, typedKey);
        if (key == null) {
          throw _fix('Type the whole key from your sheet. It has six groups of four letters and numbers.', 'recovery_key_required');
        }
        await _refuseIfSignedIn();
        final Map<String, dynamic> r =
            await startRecoveryWithSheetCall(baseUrl, sheetKey: key, deviceLabel: deviceLabel, client: _client);
        final Object? code = r['code'];
        final DateTime? ready = r['readyAt'] is String ? DateTime.tryParse(r['readyAt'] as String) : null;
        if (code is! String || normaliseRecoveryCode(RecoveryCodeKind.request, code) == null || ready == null) {
          throw _unexpected();
        }
        final PendingRecovery p = PendingRecovery(
            code: groupRecoveryCode(normaliseRecoveryCode(RecoveryCodeKind.request, code)!),
            readyAt: ready,
            soleParent: true,
            accountName: r['accountName'] is String ? r['accountName'] as String : '',
            helperRequired: r['helperRequired'] == true,
            savedAt: _now());
        await _pending.save(p);
        return RecoveryStarted(
            readyAt: p.readyAt, soleParent: true, accountName: p.accountName, helperRequired: p.helperRequired);
      });

  /// Two or more grown-ups: the code another grown-up of the family handed over. Checked with the server, then kept.
  Future<RecoveryStarted> useGrownUpCode(String typedCode) =>
      _run<RecoveryStarted>('useCode', RecoveryAction.useCode, () async {
        final String? code = sendableRecoveryCode(RecoveryCodeKind.request, typedCode);
        if (code == null) {
          throw _fix('Type the whole code you were given. It has five groups of four letters and numbers.', 'recovery_code_required');
        }
        await _refuseIfSignedIn();
        final Map<String, dynamic> j = await recoveryStatusCall(baseUrl, code: code, client: _client);
        final RecoveryStatus? s = RecoveryStatus.tryParse(j);
        if (s == null) throw _unexpected();
        if (!recoveryIsOpen(s.phase)) {
          throw const AccountFailure(AccountProblem(
              'That recovery is over: it was stopped, it finished, or it ran out. Nothing was changed. Ask them to '
              'start it again.',
              ProblemKind.cannot,
              reason: 'invalid_recovery'));
        }
        await _pending.save(PendingRecovery(
            code: code,
            readyAt: s.readyAt,
            soleParent: s.soleParent,
            accountName: s.accountName,
            helperRequired: s.helperRequired,
            savedAt: _now()));
        return RecoveryStarted(
            readyAt: s.readyAt, soleParent: s.soleParent, accountName: s.accountName, helperRequired: s.helperRequired);
      });

  /// How this phone's recovery is going. Null when there is none. A recovery the server no longer knows is forgotten
  /// here, so a stale code never lingers.
  Future<RecoveryStatus?> status() => _run<RecoveryStatus?>('status', RecoveryAction.checkStatus, () async {
        final PendingRecovery? p = await _safe(_pending.load);
        if (p == null) return null;
        try {
          final RecoveryStatus? s = RecoveryStatus.tryParse(await recoveryStatusCall(baseUrl, code: p.code, client: _client));
          if (s == null) throw _unexpected();
          return s;
        } on ApiException catch (e) {
          if (e.error == 'invalid_recovery') {
            await clearPending();
            return null;
          }
          rethrow;
        }
      });

  /// The new phone gives up. The server is told if it can be reached; this phone forgets either way.
  Future<void> giveUp() async {
    final PendingRecovery? p = await _safe(_pending.load);
    if (p != null) {
      try {
        await cancelRecoveryFromNewPhoneCall(baseUrl, code: p.code, client: _client);
      } catch (_) {
        // A recovery that is not stopped here just runs out; the other phones can stop it too.
      }
    }
    await clearPending();
  }

  /// The new phone finishes once the waiting period is over. Two or more grown-ups: [pin] or [sheetKey] proves it is
  /// the account's own owner (a helping grown-up alone cannot take the account). One grown-up: the sheet already
  /// proved it, and [newPin] (optional) replaces a forgotten PIN. On success this phone is signed in to the SAME
  /// account and its older phones are signed out.
  Future<RecoveredResult> finish({String? pin, String? sheetKey, String? newPin}) =>
      _run<RecoveredResult>('finish', RecoveryAction.finish, () async {
        final PendingRecovery? p = await _safe(_pending.load);
        if (p == null) {
          throw const AccountFailure(AccountProblem(
              'This phone is not waiting on a recovery. Start one first.', ProblemKind.cannot, reason: 'no_pending'));
        }
        String? sendPin;
        if (pin != null && pin.isNotEmpty) {
          if (!looksLikePin(pin)) throw _fix('Your PIN is 4 to 8 digits.', 'pin_required');
          sendPin = pin;
        }
        String? sendKey;
        if (sheetKey != null && sheetKey.trim().isNotEmpty) {
          sendKey = sendableRecoveryCode(RecoveryCodeKind.sheet, sheetKey);
          if (sendKey == null) {
            throw _fix('Type the whole key from your sheet. It has six groups of four letters and numbers.', 'recovery_key_required');
          }
        }
        String? sendNew;
        if (newPin != null && newPin.isNotEmpty) {
          final String? bad = problemForNewPin(newPin);
          if (bad != null) throw _fix(bad, 'invalid_pin_format');
          sendNew = newPin;
        }
        if (!p.soleParent && sendPin == null && sendKey == null) {
          throw _fix('Type your PIN, or the recovery key from your sheet.', 'proof_required');
        }
        final Map<String, dynamic> r;
        try {
          r = await finishRecoveryCall(baseUrl,
              code: p.code, pin: sendPin, sheetKey: sendKey, newPin: sendNew, deviceLabel: deviceLabel, client: _client);
        } on ApiException catch (e) {
          // The recovery is over (stopped, finished, ran out, burned by too many wrong tries): nothing to wait on.
          if (e.error == 'invalid_recovery' || e.error == 'too_many_wrong') await clearPending();
          rethrow;
        }
        await _account.adoptRecoveredSignIn(r);
        await clearPending();
        return RecoveredResult(
            devicesSignedOut: r['devicesSignedOut'] is int ? r['devicesSignedOut'] as int : 0,
            sheetSpent: r['sheetSpent'] == true,
            children: r['children'] is int ? r['children'] as int : 0);
      }, helperName: '');

  // =============================================================================================
  //  A trusted helper: no account, one key, two powers
  // =============================================================================================

  Future<HelperKey?> helperIdentity() => _safe(_helper.load);

  /// The person who was handed an invite opens it on their own phone. They get a helper key, not an account.
  Future<HelperKey> acceptHelperInvite(String typedCode) =>
      _run<HelperKey>('acceptHelper', RecoveryAction.acceptHelper, () async {
        final String? code = sendableRecoveryCode(RecoveryCodeKind.helperInvite, typedCode);
        if (code == null) {
          throw _fix('Type the whole helper code you were given. It has four groups of four letters and numbers.', 'invite_code_required');
        }
        final Map<String, dynamic> r = await acceptRecoveryHelperInviteCall(baseUrl, code: code, client: _client);
        final Object? key = r['helperKey'];
        final HelperKey? k = HelperKey.tryParse(<String, Object?>{
          'key': key,
          'accountName': r['accountName'],
          'label': r['label'],
        });
        if (k == null) throw _unexpected();
        await _helper.save(k);
        return k;
      });

  /// The recoveries that name this helper. First name and times only. A phone that is no longer anyone's helper
  /// forgets its key and says so.
  Future<List<HelperRequest>> helperRequests() => _run<List<HelperRequest>>('helperList', RecoveryAction.helperList, () async {
        final HelperKey? k = await _safe(_helper.load);
        if (k == null) throw const AccountFailure(AccountProblem('This phone is not anyone\'s helper.', ProblemKind.cannot, reason: 'invalid_helper'));
        try {
          final Map<String, dynamic> j = await helperRequestsCall(baseUrl, helperKey: k.key, client: _client);
          final Object? list = j['requests'];
          final List<HelperRequest> out = <HelperRequest>[];
          if (list is List) {
            for (final Object? e in list) {
              if (e is! Map) continue;
              final Object? id = e['requestId'];
              final DateTime? started = e['startedAt'] is String ? DateTime.tryParse(e['startedAt'] as String) : null;
              final DateTime? ready = e['readyAt'] is String ? DateTime.tryParse(e['readyAt'] as String) : null;
              if (id is! String || !isServerId(id) || started == null || ready == null) continue;
              out.add(HelperRequest(
                  requestId: id,
                  accountName: e['accountName'] is String ? e['accountName'] as String : '',
                  startedAt: started,
                  readyAt: ready,
                  confirmed: e['confirmed'] == true));
            }
          }
          return out;
        } on ApiException catch (e) {
          if (e.error == 'invalid_helper') await _safe(() async {
            await _helper.clear();
            return null;
          });
          rethrow;
        }
      });

  /// The helper's whole power: yes ("that is them") or no. A yes does not shorten the wait.
  Future<void> answer({required String requestId, required bool yes}) =>
      _run<void>('answer:$requestId', RecoveryAction.helperAnswer, () async {
        final HelperKey? k = await _safe(_helper.load);
        if (k == null) throw const AccountFailure(AccountProblem('This phone is not anyone\'s helper.', ProblemKind.cannot, reason: 'invalid_helper'));
        if (!isServerId(requestId)) throw _fix('That recovery is not here any more.', 'not_found');
        await helperAnswerCall(baseUrl, helperKey: k.key, requestId: requestId, yes: yes, client: _client);
      });

  /// Stops being a helper on this phone (the grown-up who named them is not told; they can name someone else).
  Future<void> forgetHelper() async {
    try {
      await _helper.clear();
    } catch (_) {}
  }
}
