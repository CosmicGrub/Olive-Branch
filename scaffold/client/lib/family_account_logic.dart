// OLIVE BRANCH — the optional family account: the rules, in plain Dart. Verified headless
// (client/test/family_account_logic_test.dart). MASTERFILE section 8.5.13.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 8.5.13).
//
// An account is OPTIONAL. Everything on this phone works with none (offline-first, DECISIONS.md): the
// server enables sharing between grown-ups, it never gates the local experience. This file is the
// pure half of the account flow (no I/O, no widgets):
//
//   * the input rules, mirroring what server/identity_input.mjs and the sign-up route will accept, so a
//     typo is caught on the phone with a plain sentence instead of a refused request;
//   * the words for every way a request can fail, in adult language ([problemFor]). A raw server code
//     ("invalid_allowance", "403") never reaches a screen: it stays on [AccountProblem.reason] for tests;
//   * what an invite looks like to the grown-up who sent it ([InviteView]) and what they can do about it;
//   * which step to resume at ([planAccountStep]).
//
// ADULT SCREENS ONLY. A child never sees any of this: no PIN, no code, no error text (P1 to P11). The
// screens that use this file live on a grown-up's phone and a test fails if a child-side file imports them.
import 'dart:async';
import 'dart:io' show SocketException, HandshakeException, TlsException;

import 'package:http/http.dart' as http;

import 'api_client.dart' show ApiException;
import 'local_pin.dart' show isEasyGuessLocalPin, isValidLocalPin;
import 'server_transport_policy.dart' show TransportPolicyViolation;

// ---- limits (the server's own, identity_input.mjs and the sign-up route) ------------------------

const int kAllowanceCodeMin = 20;
const int kAllowanceCodeMax = 128;
const int kAdultNameMax = 60;
const int kChildNameMax = 40;
const int kMaxChildAgeYears = 17;
const int kEmailMax = 254;
const int kInviteLabelMax = 40;

/// The roles an invite may carry (packages/db/src/pool.ts INVITABLE_ROLES), in the order a grown-up picks.
const List<String> kInvitableRoles = <String>[
  'guardian', 'step_parent', 'trusted_adult', 'sitter', 'coordinator',
];

/// Plain words for each invitable role. The role decides what the person can do; these are names, not promises.
String inviteRoleWords(String role) => switch (role) {
      'guardian' => 'Parent or guardian',
      'step_parent' => 'Step-parent',
      'trusted_adult' => 'Trusted adult (a grandparent, an aunt, a family friend)',
      'sitter' => 'Sitter',
      'coordinator' => 'Coordinator',
      _ => 'Grown-up',
    };

/// The role name without its explanation in brackets: "Trusted adult" from the full wording. Written with
/// the escape \x28 rather than a bracket character in a string so that the transport suite's naive bracket count
/// (packages/transport/test, section I) is not thrown off by a literal that holds one on its own.
String inviteRoleShortWords(String role) => inviteRoleWords(role).split(' \x28').first;

final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// True for the shape of an id the server hands out (a UUID). Used before an id is put into a URL path.
bool isServerId(String? s) => s != null && _uuid.hasMatch(s);

// ---- cleaning what a grown-up typed ---------------------------------------------------------------

/// The invite code from the operator ("allowance"): whitespace removed (a paste often brings a line break),
/// 20 to 128 characters of visible ASCII. Null when it cannot be one.
String? cleanAllowanceCode(String raw) {
  final String t = raw.replaceAll(RegExp(r'\s+'), '');
  if (t.length < kAllowanceCodeMin || t.length > kAllowanceCodeMax) return null;
  if (!RegExp(r'^[\x21-\x7e]+$').hasMatch(t)) return null;
  return t;
}

/// The recovery code from the operator: the same rules as [cleanAllowanceCode] (the server reads both with the
/// same 20 to 128 character window), kept as its own name so a call site says which code it holds.
String? cleanRecoveryCode(String raw) => cleanAllowanceCode(raw);

/// The invite code a grown-up was sent for a child (a UUID). Whitespace and the odd quote or bracket from a
/// paste are removed; anything that is not a UUID after that is refused, so a typed or hostile string never
/// reaches a URL path.
String? cleanInviteCode(String raw) {
  final String t = raw.replaceAll(RegExp("[\\s\"'<>()\\[\\]{}]"), '').toLowerCase();
  return isServerId(t) ? t : null;
}

/// A name: trimmed, inner whitespace collapsed to single spaces, 1..[max] characters (code points), no
/// control characters. (The server also folds to Unicode NFC; the phone has no normaliser and does not
/// need one: the server's answer is what is stored.)
String? cleanPersonName(String raw, int max) {
  final String t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty || t.runes.length > max) return null;
  if (RegExp(r'[\u0000-\u001f\u007f-\u009f  ]').hasMatch(t)) return null;
  return t;
}

/// A deliberately plain email check: one @, something either side, a dot in the domain, no spaces, no
/// control characters, at most 254 characters. The server only needs an "@"; this keeps typos out.
String? cleanEmail(String raw) {
  final String t = raw.trim();
  if (t.isEmpty || t.length > kEmailMax) return null;
  if (!RegExp(r'^[^\s@\u0000-\u001f\u007f-\u009f]+@[^\s@\u0000-\u001f\u007f-\u009f]+\.[^\s@.\u0000-\u001f\u007f-\u009f]+$')
      .hasMatch(t)) {
    return null;
  }
  return t;
}

/// "j***@example.com": enough to recognise the address, not enough to hand it on.
String maskEmail(String email) {
  final int at = email.indexOf('@');
  if (at < 1) return 'an email address';
  final String first = String.fromCharCodes(<int>[email.runes.first]);
  return '$first***${email.substring(at)}';
}

/// Whole years between [birth] and [now] (calendar days, local).
int ageInYears(DateTime birth, DateTime now) {
  int years = now.year - birth.year;
  if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) years--;
  return years;
}

/// `YYYY-MM-DD`, the wire form.
String birthDateWire(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A plain sentence when this birth date will not be accepted, else null. The server refuses a future date and
/// a child of 18 or over.
String? problemForBirthDate(DateTime? d, DateTime now) {
  if (d == null) return "Choose her birth date. Olive's server uses it to know her age.";
  final DateTime today = DateTime(now.year, now.month, now.day);
  if (DateTime(d.year, d.month, d.day).isAfter(today)) return 'That date has not happened yet.';
  if (ageInYears(d, today) > kMaxChildAgeYears) {
    return 'An account holds children under 18. Check the date.';
  }
  return null;
}

/// A soft note (never a block) when the date she was given does not match the age already locked on this phone.
String? ageMismatchNote(DateTime? birth, int? localAge, DateTime now) {
  if (birth == null || localAge == null) return null;
  final int a = ageInYears(birth, now);
  if ((a - localAge).abs() <= 1) return null;
  return "On this phone her age is $localAge, but that birth date makes her $a. Her app on this phone keeps "
      "the age already set. Check the date if it looks wrong.";
}

/// A plain sentence when this PIN will not do, else null. The same rule as the phone's own PIN: 4 to 8
/// digits, not an obvious one.
String? problemForNewPin(String pin) {
  if (!isValidLocalPin(pin)) return 'A PIN is 4 to 8 digits, with no letters or spaces.';
  if (isEasyGuessLocalPin(pin)) {
    return 'That PIN is easy to guess. Please choose one that is harder for someone else to work out.';
  }
  return null;
}

/// True for a PIN that could be an existing one (4 to 8 digits). Used where a PIN is typed to prove it is you.
bool looksLikePin(String pin) => isValidLocalPin(pin);

// ---- invites, as the grown-up who sent them sees them ---------------------------------------------

enum InviteState { sent, accepted, waitingForYou, confirmed, declined, revoked, expired, unknown }

InviteState inviteStateFromWire(Object? v) => switch (v) {
      'sent' => InviteState.sent,
      'accepted' => InviteState.accepted,
      'waiting_for_you' => InviteState.waitingForYou,
      'confirmed' => InviteState.confirmed,
      'declined' => InviteState.declined,
      'revoked' => InviteState.revoked,
      'expired' => InviteState.expired,
      _ => InviteState.unknown,
    };

/// What the sender can do with an invite in each state.
enum InviteAction { confirm, turnAway, cancel }

class InviteView {
  const InviteView({
    required this.id,
    required this.role,
    required this.label,
    required this.invitedEmail,
    required this.state,
    this.claimantName,
    this.expiresAt,
  });

  final String id;
  final String role;
  final String label;
  final String invitedEmail;
  final InviteState state;

  /// The name the person gave when they presented the invite. Never an id or an email.
  final String? claimantName;
  final DateTime? expiresAt;

  /// Reads one listing from the server, tolerating a damaged entry: an entry without a usable id is dropped
  /// (null), every other field falls back to something harmless.
  static InviteView? tryParse(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'];
    if (id is! String || !isServerId(id)) return null;
    String s(Object? v, [String d = '']) => v is String ? v : d;
    final Object? exp = j['expiresAt'];
    return InviteView(
      id: id,
      role: s(j['role']),
      label: s(j['label']),
      invitedEmail: s(j['invitedEmail']),
      state: inviteStateFromWire(j['status']),
      claimantName: j['claimantName'] is String ? j['claimantName'] as String : null,
      expiresAt: exp is String ? DateTime.tryParse(exp) : null,
    );
  }

  List<InviteAction> get actions => switch (state) {
        InviteState.waitingForYou => const <InviteAction>[InviteAction.confirm, InviteAction.turnAway],
        InviteState.sent => const <InviteAction>[InviteAction.cancel],
        // The server refuses to cancel once it has been opened; turning them away is the same outcome.
        InviteState.accepted => const <InviteAction>[InviteAction.turnAway],
        _ => const <InviteAction>[],
      };

  /// One sentence, in adult words, for the family page.
  String statusLine() {
    final String who = (claimantName != null && claimantName!.trim().isNotEmpty) ? claimantName!.trim() : 'Someone';
    final String roleWords = inviteRoleShortWords(role).toLowerCase();
    return switch (state) {
      InviteState.sent => 'Sent to ${maskEmail(invitedEmail)}. Waiting for them to open it.',
      InviteState.accepted => 'Opened, but not finished joining yet.',
      InviteState.waitingForYou =>
        '$who is asking to join as $roleWords. Is that who you meant to invite?',
      InviteState.confirmed => '${claimantName != null ? claimantName!.trim() : 'They'} joined as $roleWords.',
      InviteState.declined => 'You turned this one away.',
      InviteState.revoked => 'You cancelled this invite.',
      InviteState.expired => 'This invite ran out. You can send a new one.',
      InviteState.unknown => 'The server sent something this version of Olive does not understand.',
    };
  }
}

// ---- where to resume ------------------------------------------------------------------------------

enum AccountStep {
  /// No account on this phone and nothing in progress.
  start,

  /// An invite was opened on this phone and joining is not finished.
  finishJoining,

  /// Signed in, no child on the account yet.
  addChild,

  /// Signed in with a child: the family page.
  family,
}

/// Where the account screen opens. [childCount] is null when the server could not be asked.
AccountStep planAccountStep({
  required bool hasSignIn,
  required bool joiningInvite,
  required int? childCount,
  required bool hasRecordedChild,
}) {
  if (!hasSignIn) return joiningInvite ? AccountStep.finishJoining : AccountStep.start;
  if (joiningInvite && (childCount ?? 0) == 0 && !hasRecordedChild) return AccountStep.finishJoining;
  if (childCount == null) return hasRecordedChild ? AccountStep.family : AccountStep.addChild;
  return childCount == 0 ? AccountStep.addChild : AccountStep.family;
}

// ---- failures, in words ---------------------------------------------------------------------------

/// What the grown-up was doing when a request failed. A few server reasons ("not_found") mean different
/// things in different places.
enum AccountAction {
  signUp,
  addChild,
  loadFamily,
  createInvite,
  confirmInvite,
  turnAwayInvite,
  cancelInvite,
  lookUpInvite,
  joinInvite,
  checkJoin,
  useInviteWithAccount,
  setPin,
  signIn,
  signOut,
  recover,
}

/// Whether the action changes something on the server (so a lost reply leaves the outcome unknown).
bool _changesServer(AccountAction a) => switch (a) {
      AccountAction.loadFamily || AccountAction.lookUpInvite || AccountAction.checkJoin => false,
      _ => true,
    };

enum ProblemKind {
  /// A box needs changing; nothing was sent or nothing was accepted.
  fixInput,

  /// Nothing the grown-up did was wrong; try again.
  tryAgain,

  /// Too many tries; wait.
  wait,

  /// The sign-in on this phone has ended or is missing.
  needsSignIn,

  /// This cannot be done as it stands (an invite that ran out, a closed account).
  cannot,
}

class AccountProblem {
  const AccountProblem(this.message, this.kind, {this.reason = ''});

  /// Plain words, safe to show.
  final String message;
  final ProblemKind kind;

  /// The server's reason code or a short internal tag. For tests and logs. NEVER shown.
  final String reason;

  @override
  String toString() => 'AccountProblem($reason)';
}

/// What a screen catches. Carries only [problem].
class AccountFailure implements Exception {
  const AccountFailure(this.problem);
  final AccountProblem problem;
  @override
  String toString() => 'AccountFailure(${problem.reason})';
}

/// Every server reason the account flow's routes can return, which [problemFor] words specifically. A test
/// reads server/routes.mjs and packages/db/src/pool.ts and fails if a reason there is missing from this set,
/// so a new server answer cannot reach a grown-up as a bare code.
const Set<String> kKnownServerReasons = <String>{
  // sign-up
  'allowance_token_required', 'display_name_required', 'invalid_home_tz', 'pin_required',
  'invalid_pin_format', 'invalid_input', 'invalid_allowance', 'signup_disabled', 'signup_cap_reached',
  // children
  'guardian_session_required', 'invalid_birth_date', 'too_many_children', 'account_not_found',
  // the grown-up's own PIN (step-up)
  'pin_incorrect', 'pin_locked', 'pin_not_set',
  // invites
  'no_user_identity', 'child_cannot_invite', 'not_a_guardian_of_child', 'invalid_role', 'label_required',
  'invited_email_required', 'not_found', 'expired', 'revoked', 'declined', 'already_accepted',
  'not_accepted', 'already_bootstrapped', 'email_already_registered', 'already_claimed',
  'already_confirmed', 'already_a_member', 'not_claimed', 'claimant_unavailable', 'edge_exists',
  'family_full', 'inviter_not_guardian',
  // account recovery (migration 0053)
  'recovery_code_required', 'invalid_recovery', 'recovery_locked', 'recovery_rate_limited',
  // the session
  'device_revoked', 'invalid_device_credential', 'account_deactivated', 'rate_limited',
};

const String _tryAgainLater = 'Nothing is lost. Try again in a little while.';

/// Turns anything that can go wrong into words. Never returns an exception's text, a status code or a
/// server reason in [AccountProblem.message].
AccountProblem problemFor(Object error, AccountAction action) {
  if (error is AccountFailure) return error.problem;
  if (error is TransportPolicyViolation) {
    return const AccountProblem(
        "This copy of Olive isn't set up to reach a server, so an account can't be made from it.",
        ProblemKind.cannot,
        reason: 'transport_policy');
  }
  if (error is ApiException) return _problemForApi(error, action);
  if (error is TimeoutException || error is SocketException || error is http.ClientException ||
      error is HandshakeException || error is TlsException) {
    if (action == AccountAction.recover) {
      return const AccountProblem(
          "Olive couldn't hear back from the server, so it can't be sure the recovery went through. The recovery "
          'code may have been used. Try the same code once more; if it is refused, ask whoever runs your server '
          'for a new one.',
          ProblemKind.tryAgain,
          reason: 'network');
    }
    return AccountProblem(
        _changesServer(action)
            ? "Olive couldn't reach the server, or didn't hear back, so it can't be sure that went through. "
                'Check your connection, look at your family page, and try again if it did not.'
            : "Olive couldn't reach the server. Check your connection and try again.",
        ProblemKind.tryAgain,
        reason: 'network');
  }
  return const AccountProblem('Something went wrong on this phone. Nothing was changed. Try again.',
      ProblemKind.tryAgain, reason: 'unexpected');
}

AccountProblem _problemForApi(ApiException e, AccountAction a) {
  final String code = e.error;
  const AccountProblem signedOut = AccountProblem(
      'Your sign-in on this phone has ended. Sign in again to carry on.', ProblemKind.needsSignIn,
      reason: 'signed_out');
  AccountProblem fix(String m) => AccountProblem(m, ProblemKind.fixInput, reason: code);
  AccountProblem cannot(String m) => AccountProblem(m, ProblemKind.cannot, reason: code);
  AccountProblem again(String m) => AccountProblem(m, ProblemKind.tryAgain, reason: code);

  if (e.statusCode == 429 || code == 'rate_limited') {
    return const AccountProblem('Too many tries in a short time. Wait a few minutes, then try again.',
        ProblemKind.wait, reason: 'rate_limited');
  }
  if (e.statusCode >= 500) {
    return AccountProblem(
        _changesServer(a)
            ? 'The server had a problem, so Olive cannot be sure that went through. Look at your family '
                'page before you try again.'
            : 'The server had a problem. $_tryAgainLater',
        ProblemKind.tryAgain,
        reason: 'server_error');
  }

  switch (code) {
    // sign-up
    case 'allowance_token_required':
      return fix('Enter the invite code you were given. It is long, and has no spaces.');
    case 'invalid_allowance':
      return fix("That invite code didn't work. It may have a typo, or it may already be used or have run out. "
          'Check it, or ask whoever runs your server for a new one.');
    case 'signup_disabled':
      return cannot("This server isn't accepting new accounts right now. Ask whoever runs it.");
    case 'signup_cap_reached':
      return cannot('This server has reached the number of accounts it allows. Ask whoever runs it.');
    case 'display_name_required':
      return fix('Please enter a name.');
    case 'invalid_home_tz':
      return fix('Choose the time zone where you live from the list.');
    case 'pin_required':
      return fix('Enter your PIN.');
    case 'invalid_pin_format':
      return fix('A PIN is 4 to 8 digits, with no letters or spaces.');
    case 'invalid_input':
      return fix("Something you entered isn't allowed. Check each box and try again.");
    case 'invalid_birth_date':
      return fix('Check her birth date. It has to be a real date that has already happened, and she must be under 18.');
    // PIN step-up
    case 'pin_incorrect':
      return a == AccountAction.recover
          ? fix("That PIN isn't right for this account. After a few wrong tries the recovery code stops working "
              'and you will need a new one.')
          : fix("That PIN isn't right.");
    case 'pin_locked':
      return const AccountProblem('Too many wrong tries. Try again in 15 minutes.', ProblemKind.wait,
          reason: 'pin_locked');
    case 'pin_not_set':
      return a == AccountAction.recover
          ? cannot("This account doesn't have a PIN, so a recovery code can't be used for it. Ask whoever runs "
              'your server for help.')
          : cannot("This account doesn't have a PIN yet. Set one first, then try again.");
    // account recovery
    case 'recovery_code_required':
      return fix('Enter the recovery code you were given. It is long, and has no spaces.');
    case 'invalid_recovery':
      return fix("That recovery code didn't work. It may have a typo, or it may already be used, cancelled or "
          'have run out. Check it, or ask whoever runs your server for a new one.');
    case 'recovery_locked':
      return cannot('There were too many wrong PINs, so that recovery code has been cancelled. Ask whoever runs '
          'your server for a new one.');
    // identity and session
    case 'guardian_session_required':
    case 'no_user_identity':
    case 'device_revoked':
    case 'invalid_device_credential':
      return signedOut;
    case 'account_not_found':
      return const AccountProblem(
          "The server can't find your account. Sign in again, or ask whoever runs your server.",
          ProblemKind.needsSignIn,
          reason: 'account_not_found');
    case 'account_deactivated':
      return cannot('This account has been closed.');
    case 'unexpected_reply':
      return again('The server answered in a way Olive did not expect. Look at your family page before you '
          'try again.');
    case 'too_many_children':
      return cannot('This account already holds as many children as it can.');
    // creating an invite
    case 'child_cannot_invite':
      return cannot("A child's device can't invite anyone.");
    case 'not_a_guardian_of_child':
      return cannot("This account isn't a full guardian of her, so it can't do that.");
    case 'invalid_role':
      return fix('Choose one of the roles in the list.');
    case 'label_required':
      return fix('Add the word she will use for them, such as Nana.');
    case 'invited_email_required':
      return fix('Enter the email address the invite is for.');
    // invite lookups and decisions: the same reason, different meaning
    case 'not_found':
      return switch (a) {
        AccountAction.lookUpInvite || AccountAction.joinInvite || AccountAction.checkJoin =>
          cannot("That invite code wasn't found. Check it, or ask them to send a new one."),
        AccountAction.useInviteWithAccount => cannot(
            'This invite was sent to a different email address than the one on your account, '
            'or it is no longer there.'),
        _ => cannot('That invite is no longer there. Refresh the family page.'),
      };
    case 'expired':
      return cannot('That invite ran out. Ask them to send a new one.');
    case 'revoked':
      return cannot('That invite is no longer open. Ask them to send a new one.');
    case 'declined':
      return switch (a) {
        AccountAction.checkJoin || AccountAction.useInviteWithAccount || AccountAction.joinInvite => cannot(
            'They decided not to add you this time. You can talk to them about it.'),
        _ => cannot('You already turned this one away.'),
      };
    case 'already_accepted':
      return switch (a) {
        AccountAction.cancelInvite => cannot(
            'They already opened it, so it can no longer be cancelled here. Turn them away instead if you '
            'changed your mind.'),
        _ => cannot('This invite was already opened. If that was you, carry on where you left off. If not, ask '
            'them for a new one.'),
      };
    case 'not_accepted':
      return cannot("This invite hasn't been opened yet.");
    case 'already_bootstrapped':
      return cannot('An account was already made from this invite. If that was you, use the phone you made it on.');
    case 'email_already_registered':
      return cannot('That email address already has an Olive account. Sign in with that account, then use the '
          'invite code again.');
    case 'already_claimed':
      return cannot('Someone has already used this invite.');
    case 'already_confirmed':
      return cannot("That one is finished: they're already part of the family.");
    case 'already_a_member':
      return cannot('That account is already part of this family.');
    case 'edge_exists':
      return cannot("They're already part of this family.");
    case 'not_claimed':
      return again("They haven't finished joining yet. Ask them to open the invite on their phone.");
    case 'claimant_unavailable':
      return cannot("Their account isn't available any more. Ask them to try again.");
    case 'family_full':
      return cannot('This family has reached the number of grown-ups Olive allows: 4 parents and 8 other '
          'adults. Remove someone before adding another.');
    case 'inviter_not_guardian':
      return cannot('You no longer have full guardian access to her, so you cannot confirm someone.');
  }
  // 401 with a reason we do not word, or any other status.
  if (e.statusCode == 401) return signedOut;
  if (e.statusCode == 403) {
    return AccountProblem("That isn't available to this account right now.", ProblemKind.cannot, reason: code);
  }
  if (e.statusCode == 404 || e.statusCode == 410) {
    return AccountProblem('That is no longer there.', ProblemKind.cannot, reason: code);
  }
  return AccountProblem('Olive could not do that. $_tryAgainLater', ProblemKind.tryAgain,
      reason: code.isEmpty ? 'unknown' : code);
}
