// OLIVE BRANCH — the optional family account, as one object the screens talk to. Verified headless against the
// real route shapes (client/test/family_account_service_test.dart, family_account_contract_test.dart).
// MASTERFILE section 8.5.13.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 8.5.13).
//
// WHAT THIS IS. The guardian client half of the server's identity routes (server/routes.mjs, migration 0050):
//
//   sign up      POST /v1/auth/signup        invite-only: an operator-issued, single-use code, a name, a time zone and
//                                            a PIN. Returns a session and the device's long-lived credential.
//   sign in      POST /v1/auth/session/refresh (this device, automatic) or a code from another signed-in device
//                                            (POST /v1/device-pairing/redeem, pairing_redeem_screen.dart).
//   get back in  POST /v1/auth/recover       when NO phone is signed in any more: a recovery code from whoever
//                                            runs the server AND the account's own PIN (migration 0053).
//                                            Signs the account's earlier phones out.
//   add a child  POST /v1/children           own-PIN step-up. The same transaction gives the caller the guardianship.
//   invite       POST /v1/children/:id/guardianships        own-PIN step-up.
//   join         GET  /v1/guardian-invites/:id, POST .../accept, POST .../bootstrap (a new person) or POST .../claim
//                (an existing account addressed by the invite's email).
//   confirm      POST /v1/guardian-invites/:id/confirm      the INVITER, with their PIN: the only step that gives the
//                invited adult access. POST .../decline turns them away.
//
// WHAT IT PROMISES (and tests hold it to):
//   * OPTIONAL. Nothing here is needed for anything else to work. No call is made until a grown-up asks for one, and
//     no failure here is ever raised outside the account screens. A phone with no account is the normal phone.
//   * ADULT WORDS, PLAIN FAILURES. Every failure leaves as an [AccountFailure] carrying a sentence ([problemFor]).
//     No server code, status or exception text is ever the message.
//   * RESUMABLE. Progress is derived from what the server says plus two small local records ([AccountRecord], and
//     [PendingJoin] in secure storage). Closing the app between any two steps loses nothing that was done.
//   * NOTHING SECRET IS KEPT BEYOND NEED. A PIN is held only for the one call that needs it. The sign-in credential
//     goes to [DeviceIdentityStore] and nowhere else. If saving it fails after the server made the account, the
//     credential is held in memory and the screen says so plainly ([hasUnsavedSignIn], [retrySaveSignIn]): it is
//     shown by the server only once.
//   * TWO TAPS ARE ONE REQUEST. A double-tap on any action shares the request already in flight.
//   * INPUT IS CHECKED HERE TOO. A caller that skips the form still cannot send an invite code that is not an id
//     (it would go into a URL path), a name with control characters, or a future birth date.
import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'auth_session.dart';
import 'device_identity.dart';
import 'family_account_logic.dart';
import 'family_account_store.dart';
import 'server_transport_policy.dart' show OliveTransport;

/// A child on the account, as the server lists her for this grown-up.
class AccountChild {
  const AccountChild({required this.id, required this.name, required this.role, required this.birthDate});
  final String id;
  final String name;
  final String role;

  /// `YYYY-MM-DD`, or empty when the server did not say.
  final String birthDate;

  static AccountChild? tryParse(Map<String, dynamic> j) {
    final Object? id = j['id'];
    if (id is! String || !isServerId(id)) return null;
    String s(Object? v) => v is String ? v : '';
    return AccountChild(
        id: id, name: s(j['displayName']), role: s(j['role']), birthDate: s(j['birthDate']));
  }
}

/// Everything the account screen draws from, in one read.
class AccountSnapshot {
  const AccountSnapshot({
    required this.signedIn,
    required this.serverReached,
    required this.step,
    this.children = const <AccountChild>[],
    this.invites = const <InviteView>[],
    this.hasPin,
    this.joining,
    this.record,
    this.unsavedSignIn = false,
  });

  /// This phone holds a sign-in for an account.
  final bool signedIn;

  /// False when the server could not be asked just now. The rest is then what the phone remembers.
  final bool serverReached;
  final AccountStep step;
  final List<AccountChild> children;

  /// The invites this grown-up has sent, for every child on the account.
  final List<InviteView> invites;

  /// Whether the account has a PIN. Null when unknown.
  final bool? hasPin;
  final PendingJoin? joining;
  final AccountRecord? record;

  /// The account exists but this phone could not save the sign-in, so it will be lost when the app closes.
  final bool unsavedSignIn;

  List<InviteView> get waitingForYou =>
      <InviteView>[for (final InviteView i in invites) if (i.state == InviteState.waitingForYou) i];
}

/// A made invite, to hand to the other grown-up. Olive does not send it.
class CreatedInvite {
  const CreatedInvite({required this.code, required this.role, required this.label, this.expiresAt});
  final String code;
  final String role;
  final String label;
  final DateTime? expiresAt;
}

/// What the person who holds an invite code is shown before they decide.
class InviteLookup {
  const InviteLookup({
    required this.id,
    required this.role,
    required this.label,
    required this.maskedEmail,
    required this.alreadyOpened,
    this.expiresAt,
  });
  final String id;
  final String role;
  final String label;
  final String maskedEmail;

  /// Someone has already opened it (possibly this phone, earlier).
  final bool alreadyOpened;
  final DateTime? expiresAt;
}

enum JoinStatus {
  /// The inviter has not answered yet.
  waiting,

  /// The inviter said yes: this account now has access.
  confirmed,

  /// The inviter decided not to add this account.
  turnedAway,

  /// The invite ran out or was cancelled.
  over,
}

class FamilyAccountService {
  FamilyAccountService({
    required this.baseUrl,
    http.Client? client,
    DeviceIdentityStore? identityStore,
    AccountRecordStore? record,
    PendingJoinStore? pending,
    DateTime Function()? now,
    this.onSignedOut,
    this.deviceLabel = 'This phone',
  })  : _client = client ?? OliveTransport.clientFor(baseUrl),
        _ownsClient = client == null,
        _identityStore = identityStore ?? DeviceIdentityStore(),
        _record = record ?? MemoryAccountRecordStore(),
        _pending = pending ?? MemoryPendingJoinStore(),
        _now = now ?? DateTime.now;

  final String baseUrl;
  final String deviceLabel;
  final http.Client _client;
  final bool _ownsClient;
  final DeviceIdentityStore _identityStore;
  final AccountRecordStore _record;
  final PendingJoinStore _pending;
  final DateTime Function() _now;
  /// Fired when the sign-in ends for good (signed out, removed from the account, or the account was closed).
  final void Function()? onSignedOut;

  DeviceIdentity? _unsaved;
  final Map<String, Future<Object?>> _flights = <String, Future<Object?>>{};

  /// The account was made but this phone could not keep the sign-in. See the file header.
  bool get hasUnsavedSignIn => _unsaved != null;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  // ---- plumbing ---------------------------------------------------------------------------------

  /// Runs [body] once for [key]; a second call while it runs gets the same answer. Every failure becomes an
  /// [AccountFailure] in words.
  Future<T> _run<T>(String key, AccountAction action, Future<T> Function() body) {
    final Future<Object?>? running = _flights[key];
    if (running != null) return running.then((Object? v) => v as T);
    final Future<T> f = () async {
      try {
        return await body();
      } on AccountFailure {
        rethrow;
      } catch (e) {
        throw AccountFailure(problemFor(e, action));
      }
    }();
    _flights[key] = f;
    return f.whenComplete(() => _flights.remove(key));
  }

  static AccountFailure _fix(String message, String reason) =>
      AccountFailure(AccountProblem(message, ProblemKind.fixInput, reason: reason));

  static const AccountProblem _notSignedIn = AccountProblem(
      'You are not signed in on this phone. Sign in, or make an account, to carry on.',
      ProblemKind.needsSignIn,
      reason: 'not_signed_in');

  AuthSession _install(DeviceIdentity id) {
    final AuthSession s = AuthSession.device(
        baseUrl: baseUrl, identity: id, store: _identityStore, client: _client, now: _now,
        onSignedOut: onSignedOut);
    AuthSession.use(s);
    return s;
  }

  /// The session this phone signs requests with: the installed one, else one built from the stored identity.
  Future<AuthSession> _session() async {
    final AuthSession? cur = AuthSession.current;
    if (cur != null && !cur.hasEnded) return cur;
    DeviceIdentity? id;
    try {
      id = await _identityStore.load();
    } catch (_) {
      id = null;
    }
    if (id == null || id.role != 'guardian') throw const AccountFailure(_notSignedIn);
    return _install(id);
  }

  /// One signed call. A 401 is answered once with a fresh session, like [OliveApi] does; a second is final.
  Future<T> _authed<T>(Future<T> Function(String token) call) async {
    final AuthSession s = await _session();
    final String token = await s.token();
    try {
      return await call(token);
    } on DeviceRevokedException {
      await s.handleRevoked();
      rethrow;
    } on UnauthorizedException catch (e) {
      // The free identity calls do not recognise this reason themselves; a cut-off phone ends its session.
      if (e.error == 'device_revoked') {
        await s.handleRevoked();
        rethrow;
      }
      if (!s.canRefresh) rethrow;
      return await call(await s.refresh());
    }
  }

  /// A phone holds one account sign-in. Making or joining another would overwrite the first one's key, which the
  /// server shows only once, and leave that account with no way back in from this phone.
  Future<void> _assertNotSignedIn() async {
    if (_unsaved != null || await _hasStoredSignIn()) {
      throw const AccountFailure(AccountProblem(
          'This phone is already signed in to an account. Sign out of it first, or use this invite with that account.',
          ProblemKind.cannot,
          reason: 'already_signed_in'));
    }
  }

  Future<bool> _hasStoredSignIn() async {
    final AuthSession? cur = AuthSession.current;
    if (cur != null && !cur.hasEnded) return true;
    try {
      final DeviceIdentity? id = await _identityStore.load();
      return id != null && id.role == 'guardian';
    } catch (_) {
      return false;
    }
  }

  /// Keep the sign-in the server gave once. One quiet retry; then hold it in memory and say so.
  Future<void> _keepSignIn(DeviceIdentity id) async {
    for (int i = 0; i < 2; i++) {
      try {
        await _identityStore.save(id);
        _unsaved = null;
        return;
      } catch (_) {
        // try once more, then hold it
      }
    }
    _unsaved = id;
  }

  /// After the account was made: the saving may have failed, but the session works for this run.
  Future<void> _afterAccountMade(Map<String, dynamic> r, {required String userKey}) async {
    final Object? token = r['token'];
    final Object? userId = r[userKey];
    final Object? deviceId = r['deviceId'];
    final Object? cred = r['deviceCredential'];
    if (token is! String || userId is! String || deviceId is! String || cred is! String) {
      throw const AccountFailure(AccountProblem(
          'The server answered in a way Olive did not expect. Look at your family page before you try again.',
          ProblemKind.tryAgain,
          reason: 'unexpected_reply'));
    }
    final DeviceIdentity id = DeviceIdentity(
        sessionToken: token, deviceId: deviceId, role: 'guardian', targetId: userId, deviceCredential: cred);
    await _keepSignIn(id);
    _install(id);
  }

  /// Saves the sign-in again after a failed save. Returns true when it is now kept.
  Future<bool> retrySaveSignIn() async {
    final DeviceIdentity? id = _unsaved;
    if (id == null) return true;
    try {
      await _identityStore.save(id);
      _unsaved = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- reading the state --------------------------------------------------------------------------

  Future<AccountSnapshot> snapshot() async {
    final AccountRecord? rec = await _safe(_record.load);
    final PendingJoin? joining = await _safe(_pending.load);
    final bool signedIn = await _hasStoredSignIn() || _unsaved != null;
    if (!signedIn) {
      return AccountSnapshot(
          signedIn: false, serverReached: true, joining: joining, record: rec,
          step: planAccountStep(hasSignIn: false, joiningInvite: joining != null, childCount: null,
              hasRecordedChild: rec?.childId != null));
    }
    try {
      final List<AccountChild> kids = <AccountChild>[];
      final List<InviteView> invites = <InviteView>[];
      bool? hasPin;
      await _authed<void>((String t) async {
        // A retry after a refreshed session runs this again: start clean so nothing is listed twice.
        kids.clear();
        invites.clear();
        for (final Map<String, dynamic> j in await fetchMyChildren(baseUrl, t, client: _client)) {
          final AccountChild? c = AccountChild.tryParse(j);
          if (c != null) kids.add(c);
        }
        for (final AccountChild c in kids) {
          for (final Map<String, dynamic> j
              in await fetchGuardianInvitesForChild(baseUrl, c.id, t, client: _client)) {
            final InviteView? v = InviteView.tryParse(j);
            if (v != null) invites.add(v);
          }
        }
        try {
          final Map<String, dynamic> me = await OliveApi(baseUrl, t, client: _client).fetchMe();
          hasPin = me['hasPin'] is bool ? me['hasPin'] as bool : null;
        } on ApiException {
          hasPin = null;
        }
      });
      // A child the server lists is the truth; keep the local note in step with it.
      if (kids.isNotEmpty && rec?.childId != kids.first.id) {
        await _safe(() => _record.save(
            AccountRecord(stage: AccountStage.childAdded, childId: kids.first.id, at: _now())));
      }
      return AccountSnapshot(
        signedIn: true, serverReached: true, children: kids, invites: invites, hasPin: hasPin,
        joining: joining, record: rec, unsavedSignIn: _unsaved != null,
        step: planAccountStep(hasSignIn: true, joiningInvite: joining != null, childCount: kids.length,
            hasRecordedChild: rec?.childId != null),
      );
    } catch (e) {
      final AccountProblem p = problemFor(e, AccountAction.loadFamily);
      if (p.kind == ProblemKind.needsSignIn) {
        return AccountSnapshot(signedIn: false, serverReached: true, joining: joining, record: rec,
            step: planAccountStep(hasSignIn: false, joiningInvite: joining != null, childCount: null,
                hasRecordedChild: rec?.childId != null));
      }
      // Could not ask: show what the phone remembers, and say so.
      return AccountSnapshot(
          signedIn: true, serverReached: false, joining: joining, record: rec,
          unsavedSignIn: _unsaved != null,
          step: planAccountStep(hasSignIn: true, joiningInvite: joining != null, childCount: null,
              hasRecordedChild: rec?.childId != null));
    }
  }

  Future<T?> _safe<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  // ---- making an account ------------------------------------------------------------------------

  Future<void> signUp({
    required String allowanceCode,
    required String displayName,
    required String homeTz,
    required String pin,
  }) =>
      _run<void>('signUp', AccountAction.signUp, () async {
        await _assertNotSignedIn();
        final String? code = cleanAllowanceCode(allowanceCode);
        if (code == null) throw _fix('Enter the invite code you were given. It is long, and has no spaces.', 'allowance_token_required');
        final String? name = cleanPersonName(displayName, kAdultNameMax);
        if (name == null) throw _fix('Please enter your name.', 'display_name_required');
        if (!_looksLikeZone(homeTz)) throw _fix('Choose the time zone where you live from the list.', 'invalid_home_tz');
        final String? pinProblem = problemForNewPin(pin);
        if (pinProblem != null) throw _fix(pinProblem, 'invalid_pin_format');
        final Map<String, dynamic> r = await signUpWithAllowance(baseUrl,
            allowanceToken: code, displayName: name, homeTz: homeTz, pin: pin,
            deviceLabel: deviceLabel, client: _client);
        await _afterAccountMade(r, userKey: 'userId');
        await _safe(() => _record.save(AccountRecord(stage: AccountStage.signedUp, at: _now())));
      });

  // ---- getting back in ----------------------------------------------------------------------------

  /// Is the sign-in this phone holds still alive? True: it works. False: there is none, or it was ended (this
  /// phone was signed out of the account, or the account was closed; the dead key is removed as a side effect).
  /// A lost connection is thrown, because then nobody can tell.
  Future<bool> _signInIsAlive() async {
    if (_unsaved != null) return true;
    if (!await _hasStoredSignIn()) return false;
    final AuthSession s = await _session();
    try {
      await s.refresh();
      return true;
    } on DeviceRevokedException {
      return false;
    } on ForbiddenException catch (e) {
      if (e.error == 'account_deactivated') return false;
      rethrow;
    }
  }

  /// Gets a grown-up back into their account when no signed-in phone is left: the recovery code the person who
  /// runs the server gave them, and the account's own PIN. The server signs the account's earlier phones out and
  /// this phone becomes its sign-in. Refused (before anything is sent) while this phone's own sign-in still
  /// works. The PIN is held only for the one call.
  Future<void> recoverAccount({required String recoveryCode, required String pin}) =>
      _run<void>('recover', AccountAction.recover, () async {
        final String? code = cleanRecoveryCode(recoveryCode);
        if (code == null) {
          throw _fix('Enter the recovery code you were given. It is long, and has no spaces.', 'recovery_code_required');
        }
        if (!looksLikePin(pin)) throw _fix('Enter your PIN. It is 4 to 8 digits.', 'pin_required');
        if (await _signInIsAlive()) {
          throw const AccountFailure(AccountProblem(
              'This phone is already signed in to an account, and it works. You do not need a recovery code here.',
              ProblemKind.cannot,
              reason: 'already_signed_in'));
        }
        final Map<String, dynamic> r = await recoverAccountWithCode(baseUrl,
            recoveryCode: code, pin: pin, deviceLabel: deviceLabel, client: _client);
        await _afterAccountMade(r, userKey: 'userId');
        await _safe(() => _record.save(AccountRecord(stage: AccountStage.signedUp, at: _now())));
      });

  // ---- hooks for the recovery paths (recovery_paths_service.dart) -----------------------------------

  /// One signed call with this phone's sign-in (refreshed once on a 401, like every call here). Throws
  /// [AccountFailure] when no phone sign-in exists. For the recovery paths, which sit beside the account flow.
  Future<T> signedCall<T>(Future<T> Function(String token) call) => _authed(call);

  /// Whether this phone holds a sign-in that still works. False when there is none or it was ended. A lost
  /// connection is thrown, because then nobody can tell.
  Future<bool> signInWorks() => _signInIsAlive();

  /// The recovery paths got this phone back into its OWN account (the same account id: nothing is made, copied or
  /// moved): keep the new sign-in, install it, and remember the account's first child so the connected shell opens on
  /// her again. Same keeping rules as a new account ([_afterAccountMade]).
  Future<void> adoptRecoveredSignIn(Map<String, dynamic> r) async {
    await _afterAccountMade(r, userKey: 'userId');
    String? childId;
    try {
      final List<AccountChild> kids = await _authed((String t) async => <AccountChild>[
            for (final Map<String, dynamic> c in await fetchMyChildren(baseUrl, t, client: _client))
              if (AccountChild.tryParse(c) != null) AccountChild.tryParse(c)!,
          ]);
      if (kids.isNotEmpty) childId = kids.first.id;
    } catch (_) {
      // The sign-in is the point. The family page lists her again whenever it is opened.
    }
    await _safe(() => _record.save(AccountRecord(
        stage: childId == null ? AccountStage.signedUp : AccountStage.childAdded, childId: childId, at: _now())));
  }

  // ---- a child ------------------------------------------------------------------------------------

  Future<AccountChild> addChild({
    required String displayName,
    required DateTime birthDate,
    required String homeTz,
    required String pin,
  }) =>
      _run<AccountChild>('addChild', AccountAction.addChild, () async {
        final String? name = cleanPersonName(displayName, kChildNameMax);
        if (name == null) throw _fix('Please enter her first name.', 'display_name_required');
        final String? dateProblem = problemForBirthDate(birthDate, _now());
        if (dateProblem != null) throw _fix(dateProblem, 'invalid_birth_date');
        if (!_looksLikeZone(homeTz)) throw _fix('Choose the time zone where she lives from the list.', 'invalid_home_tz');
        if (!looksLikePin(pin)) throw _fix('Enter your PIN. It is 4 to 8 digits.', 'pin_required');
        final Map<String, dynamic> j = await _authed((String t) => createChild(baseUrl, t,
            displayName: name, birthDate: birthDateWire(birthDate), homeTz: homeTz, pin: pin,
            client: _client));
        final AccountChild? c = AccountChild.tryParse(j);
        if (c == null) {
          throw const AccountFailure(AccountProblem(
              'The server answered in a way Olive did not expect. Look at your family page before you try again.',
              ProblemKind.tryAgain,
              reason: 'unexpected_reply'));
        }
        await _safe(() => _record.save(
            AccountRecord(stage: AccountStage.childAdded, childId: c.id, at: _now())));
        return c;
      });

  // ---- inviting another grown-up ----------------------------------------------------------------

  Future<CreatedInvite> createInvite({
    required String childId,
    required String role,
    required String label,
    required String email,
    required String pin,
  }) =>
      _run<CreatedInvite>('createInvite', AccountAction.createInvite, () async {
        if (!isServerId(childId)) throw _fix('Choose which child this is for.', 'invalid_child');
        if (!kInvitableRoles.contains(role)) throw _fix('Choose one of the roles in the list.', 'invalid_role');
        final String? word = cleanPersonName(label, kInviteLabelMax);
        if (word == null) throw _fix('Add the word she will use for them, such as Nana.', 'label_required');
        final String? mail = cleanEmail(email);
        if (mail == null) throw _fix('Enter the email address the invite is for, like name@example.com.', 'invited_email_required');
        if (!looksLikePin(pin)) throw _fix('Enter your PIN. It is 4 to 8 digits.', 'pin_required');
        final Map<String, dynamic> r = await _authed((String t) =>
            OliveApi(baseUrl, t, client: _client).createGuardianInvite(childId,
                role: role, label: word, invitedEmail: mail, pin: pin));
        final Object? inv = r['invite'];
        final Object? id = inv is Map ? inv['id'] : null;
        if (id is! String || !isServerId(id)) {
          throw const AccountFailure(AccountProblem(
              'The server answered in a way Olive did not expect. Look at your family page before you try again.',
              ProblemKind.tryAgain,
              reason: 'unexpected_reply'));
        }
        final Object? exp = (inv as Map)['expiresAt'];
        return CreatedInvite(
            code: id, role: role, label: word, expiresAt: exp is String ? DateTime.tryParse(exp) : null);
      });

  /// The inviter says yes. Own PIN. The only step that gives the invited adult access.
  Future<void> confirmInvite(String inviteId, String pin) =>
      _run<void>('confirm:$inviteId', AccountAction.confirmInvite, () async {
        if (!isServerId(inviteId)) throw _fix('That invite is not valid.', 'invalid_invite');
        if (!looksLikePin(pin)) throw _fix('Enter your PIN. It is 4 to 8 digits.', 'pin_required');
        await _authed((String t) => confirmGuardianInvite(baseUrl, inviteId, t, pin, client: _client));
      });

  /// The inviter turns away whoever presented the invite (also ends one that was opened and not finished).
  Future<void> turnAwayInvite(String inviteId) =>
      _run<void>('decline:$inviteId', AccountAction.turnAwayInvite, () async {
        if (!isServerId(inviteId)) throw _fix('That invite is not valid.', 'invalid_invite');
        await _authed((String t) => declineGuardianInvite(baseUrl, inviteId, t, client: _client));
      });

  /// The inviter cancels an invite nobody has opened.
  Future<void> cancelInvite(String inviteId) =>
      _run<void>('cancel:$inviteId', AccountAction.cancelInvite, () async {
        if (!isServerId(inviteId)) throw _fix('That invite is not valid.', 'invalid_invite');
        await _authed((String t) => revokeGuardianInvite(baseUrl, inviteId, t, client: _client));
      });

  // ---- being invited ------------------------------------------------------------------------------

  /// Reads an invite by its code, before the person decides anything. Changes nothing.
  Future<InviteLookup> lookUpInvite(String rawCode) =>
      _run<InviteLookup>('lookUp', AccountAction.lookUpInvite, () async {
        final String? id = cleanInviteCode(rawCode);
        if (id == null) {
          throw _fix('That does not look like an invite code. It is made of letters, numbers and dashes, '
              'like 3f2a9c1e-….', 'invalid_invite');
        }
        final Map<String, dynamic>? inv = await fetchGuardianInvite(baseUrl, id, client: _client);
        if (inv == null) {
          throw const AccountFailure(AccountProblem(
              "That invite code wasn't found. Check it, or ask them to send a new one.", ProblemKind.cannot,
              reason: 'not_found'));
        }
        if (inv['revokedAt'] != null) {
          throw const AccountFailure(AccountProblem(
              'That invite is no longer open. Ask them to send a new one.', ProblemKind.cannot,
              reason: 'revoked'));
        }
        final Object? expRaw = inv['expiresAt'];
        final DateTime? exp = expRaw is String ? DateTime.tryParse(expRaw) : null;
        if (exp != null && !exp.isAfter(_now())) {
          throw const AccountFailure(AccountProblem(
              'That invite ran out. Ask them to send a new one.', ProblemKind.cannot, reason: 'expired'));
        }
        String s(Object? v) => v is String ? v : '';
        return InviteLookup(
            id: id, role: s(inv['role']), label: s(inv['label']),
            maskedEmail: maskEmail(s(inv['invitedEmail'])), alreadyOpened: inv['acceptedAt'] != null,
            expiresAt: exp);
      });

  /// A new person joins: opens the invite, makes the account from it and signs this phone in. Resumable: if the
  /// invite was already opened FROM THIS PHONE, opening is skipped.
  Future<void> joinAsNew({required String inviteCode, required String displayName}) =>
      _run<void>('join', AccountAction.joinInvite, () async {
        await _assertNotSignedIn();
        final String? id = cleanInviteCode(inviteCode);
        if (id == null) throw _fix('That does not look like an invite code.', 'invalid_invite');
        final String? name = cleanPersonName(displayName, kAdultNameMax);
        if (name == null) throw _fix('Please enter your name.', 'display_name_required');
        final PendingJoin? held = await _safe(_pending.load);
        final bool openedHere = held != null && held.inviteId == id;
        if (!openedHere) {
          try {
            await acceptGuardianInvite(baseUrl, id, client: _client);
            await _safe(() => _pending.save(PendingJoin(inviteId: id, stage: JoinStage.accepted)));
          } on ApiException catch (e) {
            // Opened before but not held here (the save was lost, or an earlier try got this far): the next step is
            // still making the account, and the server refuses a second account for the same invite. Nothing is
            // held for an invite this phone did not open itself.
            if (e.error != 'already_accepted') rethrow;
          }
        }
        final Map<String, dynamic> r = await bootstrapGuardianInvite(baseUrl, id, name, enrol: true, client: _client);
        await _afterAccountMade(r, userKey: 'userId');
        await _pending.save(PendingJoin(inviteId: id, stage: JoinStage.waiting));
        await _safe(() => _record.save(AccountRecord(stage: AccountStage.signedUp, at: _now())));
      });

  /// An existing account (signed in on this phone) presents an invite addressed to its own email.
  Future<void> useInviteWithAccount(String inviteCode) =>
      _run<void>('useWithAccount', AccountAction.useInviteWithAccount, () async {
        final String? id = cleanInviteCode(inviteCode);
        if (id == null) throw _fix('That does not look like an invite code.', 'invalid_invite');
        final PendingJoin? held = await _safe(_pending.load);
        if (held == null || held.inviteId != id) {
          try {
            await acceptGuardianInvite(baseUrl, id, client: _client);
          } on ApiException catch (e) {
            // Opened before (possibly by this same person on another try): claiming is still the next step.
            if (e.error != 'already_accepted') rethrow;
          }
        }
        await _authed((String t) => claimGuardianInvite(baseUrl, id, t, client: _client));
        await _pending.save(PendingJoin(inviteId: id, stage: JoinStage.waiting));
      });

  /// Has the inviter answered? Asking again is safe: it changes nothing while they have not.
  Future<JoinStatus> checkJoin() => _run<JoinStatus>('checkJoin', AccountAction.checkJoin, () async {
        final PendingJoin? held = await _safe(_pending.load);
        if (held == null || held.stage != JoinStage.waiting) {
          throw const AccountFailure(AccountProblem(
              'There is no invite waiting on this phone.', ProblemKind.cannot, reason: 'no_pending_join'));
        }
        try {
          await _authed((String t) => claimGuardianInvite(baseUrl, held.inviteId, t, client: _client));
          return JoinStatus.waiting;
        } on ApiException catch (e) {
          switch (e.error) {
            case 'already_confirmed':
            case 'already_a_member':
              await _pending.clear();
              final List<AccountChild> kids = <AccountChild>[];
              await _authed<void>((String t) async {
                for (final Map<String, dynamic> j in await fetchMyChildren(baseUrl, t, client: _client)) {
                  final AccountChild? c = AccountChild.tryParse(j);
                  if (c != null) kids.add(c);
                }
              });
              if (kids.isNotEmpty) {
                await _safe(() => _record.save(
                    AccountRecord(stage: AccountStage.childAdded, childId: kids.first.id, at: _now())));
              }
              return JoinStatus.confirmed;
            case 'declined':
              await _pending.clear();
              return JoinStatus.turnedAway;
            case 'revoked':
            case 'expired':
              await _pending.clear();
              return JoinStatus.over;
            default:
              rethrow;
          }
        }
      });

  /// Gives up on an invite that was opened here and not finished. Server-side nothing else is needed: an invite
  /// nobody finishes simply runs out.
  Future<void> abandonJoin() => _pending.clear();

  // ---- the account's own PIN ----------------------------------------------------------------------

  /// Sets the first PIN on an account that has none (an account made from an invite starts without one).
  Future<void> setFirstPin(String pin) => _run<void>('setPin', AccountAction.setPin, () async {
        final String? problem = problemForNewPin(pin);
        if (problem != null) throw _fix(problem, 'invalid_pin_format');
        await _authed((String t) => OliveApi(baseUrl, t, client: _client, session: AuthSession.current)
            .setGuardianPin(pin));
      });

  // ---- sign in / out ------------------------------------------------------------------------------

  /// Does this phone's sign-in still work? Asks the server for a fresh session. Returns false when the sign-in
  /// has been ended (the account was closed or this phone was removed from it); true when it works.
  Future<bool> checkSignIn() => _run<bool>('checkSignIn', AccountAction.signIn, () async {
        final AuthSession s = await _session();
        try {
          await s.refresh();
          return true;
        } on DeviceRevokedException {
          return false;
        } on ForbiddenException catch (e) {
          if (e.error == 'account_deactivated') return false;
          rethrow;
        }
      });

  /// Signs this phone out of the account. Returns whether the server confirmed it; false means the sign-in key
  /// may still be valid on the server until a grown-up removes this phone from another device. Local data stays.
  Future<bool> signOut() => _run<bool>('signOut', AccountAction.signOut, () async {
        bool confirmed = false;
        final AuthSession? cur = AuthSession.current;
        if (cur != null && !cur.hasEnded) {
          confirmed = await cur.signOut();
        } else {
          try {
            await _identityStore.clear();
          } catch (_) {}
        }
        _unsaved = null;
        await _safe(_record.clear);
        await _pending.clear();
        return confirmed;
      });

  bool _looksLikeZone(String tz) => RegExp(r'^[A-Za-z_]+(?:/[A-Za-z0-9_+\-]+){0,2}$').hasMatch(tz) && tz.length <= 64;
}
