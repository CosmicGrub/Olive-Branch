// OLIVE BRANCH — losing a phone without losing anything: the plain-words and the parsing half. Verified headless
// (client/test/recovery_paths_logic_test.dart, recovery_paths_contract_test.dart). MASTERFILE section 7.22.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 7.22).
//
// WHAT IS HERE. No screen, no storage and no network: code reading and writing (the key on the printed sheet, the
// code a helping grown-up hands over, the helper's invite), the words for time ("about 2 days", "Friday at 9:00
// AM"), the shapes the server answers with, and the one sentence for every reason a recovery call can fail.
//
// THE RULES THE WORDS HOLD TO (and tests hold them to):
//   * Adult words, one idea per sentence. No "token", "credential", "hash", "revoke", "session" or "encrypted".
//   * No server code, status, id or exception text is ever the message ([recoveryProblemFor]).
//   * Every sentence says what is still true: nothing is lost, and what was or was not changed.
//   * A child sees none of it. Nothing here is imported from a child-side file (a test holds that).
import 'dart:async' show TimeoutException;
import 'dart:io' show HandshakeException, SocketException, TlsException;

import 'package:http/http.dart' as http;

import 'api_client.dart' show ApiException;
import 'family_account_logic.dart';
import 'server_transport_policy.dart' show TransportPolicyViolation;

// ---- reading and writing codes --------------------------------------------------------------------------------------

/// The three kinds of code, and how many characters each has (the server's own numbers).
enum RecoveryCodeKind {
  /// The key on the printed recovery sheet: 24 characters, six groups of four.
  sheet(24),

  /// The code a helping grown-up hands to the person on the new phone: 20 characters, five groups.
  request(20),

  /// The invite a grown-up hands their trusted helper: 16 characters, four groups.
  helperInvite(16);

  const RecoveryCodeKind(this.length);
  final int length;
}

const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// What a person typed, as the canonical code, or null when it cannot be one. Spaces, dashes and case are ignored,
/// O reads as 0, and I and L read as 1 (the usual smudges on paper); anything else outside the alphabet is no code.
/// The same reading the server does, so a code that passes here is read the same there.
String? normaliseRecoveryCode(RecoveryCodeKind kind, String raw) {
  if (raw.length > 64) return null;
  final String s = raw
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]+'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp(r'[IL]'), '1');
  if (s.length != kind.length) return null;
  for (final int r in s.runes) {
    if (!_alphabet.contains(String.fromCharCode(r))) return null;
  }
  return s;
}

/// A code in groups of four ("K7Q2-M9XD-..."), the way it is printed and read aloud. Input need not be canonical.
String groupRecoveryCode(String code) {
  final String s = code.replaceAll(RegExp(r'[\s-]+'), '');
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < s.length; i += 4) {
    if (i > 0) b.write('-');
    b.write(s.substring(i, i + 4 > s.length ? s.length : i + 4));
  }
  return b.toString();
}

/// A phone sends the canonical, grouped form so what is on the wire never depends on how it was typed.
String? sendableRecoveryCode(RecoveryCodeKind kind, String raw) {
  final String? n = normaliseRecoveryCode(kind, raw);
  return n == null ? null : groupRecoveryCode(n);
}

/// A first name for the helper: 1 to 40 characters, no control characters, and no "@" (a name, never an address).
const int kHelperNameMax = 40;
String? cleanHelperName(String raw) {
  final String s = raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').trim();
  if (s.isEmpty || s.length > kHelperNameMax || s.contains('@')) return null;
  return s;
}

// ---- time, in words -------------------------------------------------------------------------------------------------

const List<String> _weekdays = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "about 2 days", "about 5 hours", "less than an hour". Never a count-down: a recovery is something to come back to,
/// not to watch.
String waitWords(Duration d) {
  if (d.inMinutes < 60) return 'less than an hour';
  if (d.inHours < 36) {
    final int h = d.inHours;
    return 'about $h ${h == 1 ? 'hour' : 'hours'}';
  }
  final int days = (d.inHours / 24).round();
  return 'about $days days';
}

/// "Friday at 9:00 AM" in the phone's own time, with the date when it is more than six days off.
String whenWords(DateTime t, DateTime now) {
  final DateTime l = t.toLocal();
  final DateTime n = now.toLocal();
  final int h12 = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final String mm = l.minute.toString().padLeft(2, '0');
  final String clock = '$h12:$mm ${l.hour < 12 ? 'AM' : 'PM'}';
  final bool sameDay = l.year == n.year && l.month == n.month && l.day == n.day;
  if (sameDay) return 'today at $clock';
  if (l.difference(n).inDays < 6) return '${_weekdays[l.weekday - 1]} at $clock';
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} at $clock';
}

// ---- what the server says -------------------------------------------------------------------------------------------

/// Where a recovery stands. Words from the server's own phase names.
enum RecoveryPhase { waiting, waitingForHelper, ready, stopped, done, expired, unknown }

RecoveryPhase recoveryPhaseFromWire(Object? v) => switch (v) {
      'waiting' => RecoveryPhase.waiting,
      'waiting_for_helper' => RecoveryPhase.waitingForHelper,
      'ready' => RecoveryPhase.ready,
      'stopped' => RecoveryPhase.stopped,
      'done' => RecoveryPhase.done,
      'expired' => RecoveryPhase.expired,
      _ => RecoveryPhase.unknown,
    };

/// Whether the recovery is still going (it can still be stopped, and it can still finish).
bool recoveryIsOpen(RecoveryPhase p) =>
    p == RecoveryPhase.waiting || p == RecoveryPhase.waitingForHelper || p == RecoveryPhase.ready;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
String _str(Object? v) => v is String ? v : '';
bool _bool(Object? v) => v == true;

/// The printed recovery sheet of the signed-in grown-up. The key itself is never here: the server keeps only a hash.
class SheetState {
  const SheetState({required this.exists, this.createdAt, this.confirmedAt, this.lastCheckedAt, this.spentNeedsNew = false});
  final bool exists;
  final DateTime? createdAt;

  /// The person typed it back from the paper: "you kept it".
  final DateTime? confirmedAt;
  final DateTime? lastCheckedAt;

  /// The last sheet was used to get back in and no new one has been made.
  final bool spentNeedsNew;

  bool get kept => exists && confirmedAt != null;

  static const SheetState none = SheetState(exists: false);

  static SheetState parse(Object? j) {
    if (j is! Map) return none;
    return SheetState(
        exists: _bool(j['exists']),
        createdAt: _time(j['createdAt']),
        confirmedAt: _time(j['confirmedAt']),
        lastCheckedAt: _time(j['lastCheckedAt']),
        spentNeedsNew: _bool(j['spentNeedsNew']));
  }
}

enum HelperPhase { none, invited, active }

/// The one trusted helper. Only a first name and where their invite stands.
class HelperState {
  const HelperState({required this.phase, this.label = '', this.inviteExpiresAt});
  final HelperPhase phase;
  final String label;
  final DateTime? inviteExpiresAt;

  static const HelperState none = HelperState(phase: HelperPhase.none);

  static HelperState parse(Object? j) {
    if (j is! Map) return none;
    final HelperPhase p = switch (j['state']) {
      'invited' => HelperPhase.invited,
      'active' => HelperPhase.active,
      _ => HelperPhase.none,
    };
    if (p == HelperPhase.none) return none;
    return HelperState(phase: p, label: _str(j['label']), inviteExpiresAt: _time(j['inviteExpiresAt']));
  }
}

/// One recovery, as a signed-in grown-up is told about it (on every phone they have).
class RecoveryNotice {
  const RecoveryNotice({
    required this.requestId,
    required this.phase,
    required this.soleParent,
    required this.accountName,
    required this.aboutMe,
    required this.startedByMe,
    required this.startedByName,
    required this.createdAt,
    required this.readyAt,
    required this.helperRequired,
    required this.helperConfirmed,
    this.endedAt,
    this.stoppedBy,
  });

  final String requestId;
  final RecoveryPhase phase;

  /// Started with the printed sheet (one grown-up), not by another grown-up.
  final bool soleParent;
  final String accountName;

  /// The recovery is of THIS grown-up's own account.
  final bool aboutMe;
  final bool startedByMe;
  final String startedByName;
  final DateTime createdAt;
  final DateTime readyAt;
  final bool helperRequired;
  final bool helperConfirmed;
  final DateTime? endedAt;
  final String? stoppedBy;

  static RecoveryNotice? tryParse(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['requestId'];
    final DateTime? created = _time(j['createdAt']);
    final DateTime? ready = _time(j['readyAt']);
    if (id is! String || !isServerId(id) || created == null || ready == null) return null;
    return RecoveryNotice(
        requestId: id,
        phase: recoveryPhaseFromWire(j['phase']),
        soleParent: j['mode'] == 'sole_parent',
        accountName: _str(j['accountName']),
        aboutMe: _bool(j['aboutMe']),
        startedByMe: _bool(j['startedByMe']),
        startedByName: _str(j['startedByName']),
        createdAt: created,
        readyAt: ready,
        helperRequired: _bool(j['helperRequired']),
        helperConfirmed: _bool(j['helperConfirmed']),
        endedAt: _time(j['endedAt']),
        stoppedBy: j['stoppedBy'] is String ? j['stoppedBy'] as String : null);
  }
}

/// A grown-up of the family who could be helped back in.
class CanHelp {
  const CanHelp({required this.userId, required this.name});
  final String userId;
  final String name;
}

/// Everything the recovery screens draw from, in one read.
class RecoverySummary {
  const RecoverySummary({
    required this.sheet,
    required this.helper,
    required this.open,
    required this.recentEnded,
    required this.canHelp,
    required this.secondParentHours,
    required this.soleParentHours,
  });

  final SheetState sheet;
  final HelperState helper;
  final List<RecoveryNotice> open;
  final List<RecoveryNotice> recentEnded;
  final List<CanHelp> canHelp;
  final int secondParentHours;
  final int soleParentHours;

  static RecoverySummary? tryParse(Map<String, dynamic> j) {
    List<RecoveryNotice> notices(Object? v) =>
        v is List ? <RecoveryNotice>[for (final Object? e in v) if (RecoveryNotice.tryParse(e) != null) RecoveryNotice.tryParse(e)!] : <RecoveryNotice>[];
    final Object? help = j['canHelp'];
    final Object? waits = j['waits'];
    final List<CanHelp> people = <CanHelp>[];
    if (help is List) {
      for (final Object? e in help) {
        if (e is Map && e['userId'] is String && isServerId(e['userId'] as String)) {
          people.add(CanHelp(userId: e['userId'] as String, name: _str(e['name'])));
        }
      }
    }
    int hours(Object? v, int fallback) => v is num && v > 0 ? v.round() : fallback;
    return RecoverySummary(
        sheet: SheetState.parse(j['sheet']),
        helper: HelperState.parse(j['helper']),
        open: notices(j['open']),
        recentEnded: notices(j['recentEnded']),
        canHelp: people,
        secondParentHours: waits is Map ? hours(waits['secondParentHours'], 48) : 48,
        soleParentHours: waits is Map ? hours(waits['soleParentHours'], 72) : 72);
  }
}

/// How the new phone's own recovery is going (from the code it holds).
class RecoveryStatus {
  const RecoveryStatus({
    required this.phase,
    required this.soleParent,
    required this.accountName,
    required this.readyAt,
    required this.helperRequired,
    required this.helperConfirmed,
    this.stoppedBy,
  });
  final RecoveryPhase phase;
  final bool soleParent;
  final String accountName;
  final DateTime readyAt;
  final bool helperRequired;
  final bool helperConfirmed;
  final String? stoppedBy;

  static RecoveryStatus? tryParse(Map<String, dynamic> j) {
    final DateTime? ready = _time(j['readyAt']);
    if (ready == null) return null;
    return RecoveryStatus(
        phase: recoveryPhaseFromWire(j['phase']),
        soleParent: j['mode'] == 'sole_parent',
        accountName: _str(j['accountName']),
        readyAt: ready,
        helperRequired: _bool(j['helperRequired']),
        helperConfirmed: _bool(j['helperConfirmed']),
        stoppedBy: j['stoppedBy'] is String ? j['stoppedBy'] as String : null);
  }
}

// ---- the sentence for a notice --------------------------------------------------------------------------------------

/// The one calm sentence that heads a notice. No names of children, no places, no counts.
String noticeSentence(RecoveryNotice n, DateTime now) {
  final String when = whenWords(n.readyAt, now);
  final String who = n.accountName.isEmpty ? 'a grown-up' : n.accountName;
  if (n.soleParent) {
    final String helper = n.helperRequired
        ? (n.helperConfirmed ? ' Their trusted helper has said yes.' : ' Their trusted helper also has to say yes.')
        : '';
    return n.aboutMe
        ? 'Your printed recovery sheet was used to start getting your account back on a new phone. It waits until '
            '$when.$helper If this was not you, stop it now.'
        : "$who's printed recovery sheet was used to start getting their account back on a new phone. It waits until "
            '$when.$helper';
  }
  if (n.startedByMe) return 'You are helping $who get back in on a new phone. It waits until $when.';
  final String starter = n.startedByName.isEmpty ? 'Another grown-up' : n.startedByName;
  return n.aboutMe
      ? '$starter started getting your account onto a new phone. It waits until $when. If you did not ask for this, '
          'stop it now.'
      : '$starter is helping $who get back in on a new phone. It waits until $when.';
}

/// How an ended recovery ended, in one line. Nothing about an ended recovery is ever a mystery.
String endedSentence(RecoveryNotice n) {
  if (n.phase == RecoveryPhase.done) return 'It finished: the account is on a new phone, and the older phones were signed out.';
  final String how = switch (n.stoppedBy) {
    'owner_phone' => 'It was stopped from the account\'s own phone.',
    'other_parent' => 'It was stopped by another grown-up.',
    'helper' => 'The trusted helper said no.',
    'new_phone' => 'The new phone gave up.',
    'too_many_wrong' => 'It was stopped after too many wrong tries.',
    'sheet_replaced' => 'A new recovery sheet was made, so it stopped.',
    'replaced_by_recovery' => 'A different recovery finished first.',
    'expired' => 'Nobody finished it in time, so it ran out.',
    _ => 'It was stopped.',
  };
  return '$how Nothing changed.';
}

// ---- failures, in words ---------------------------------------------------------------------------------------------

/// What the grown-up was doing when a call failed.
enum RecoveryAction {
  makeSheet,
  checkSheet,
  nameHelper,
  removeHelper,
  loadSummary,
  startFor,
  stop,
  startWithSheet,
  useCode,
  checkStatus,
  giveUp,
  finish,
  acceptHelper,
  helperList,
  helperAnswer,
}

/// Every reason the recovery routes can answer with. A test reads server/routes.mjs and packages/db/src/pool.ts and
/// fails if one there is missing from this set, so a new server answer cannot reach a person as a bare code.
const Set<String> kRecoveryKnownReasons = <String>{
  // own-PIN step-up and the session
  'guardian_session_required', 'pin_required', 'pin_incorrect', 'pin_locked', 'pin_not_set',
  'device_revoked', 'invalid_device_credential', 'account_deactivated', 'rate_limited',
  // the sheet
  'account_not_found', 'recovery_key_required', 'no_sheet', 'wrong_key', 'invalid_sheet',
  // the helper
  'invalid_label', 'invite_code_required', 'invalid_invite', 'helper_key_required', 'invalid_helper',
  'answer_required', 'not_found',
  // the recovery itself
  'target_required', 'not_family', 'ask_other_grownup', 'too_many_open', 'too_many_recent',
  'recovery_rate_limited', 'recovery_code_required', 'invalid_recovery', 'too_early', 'waiting_for_helper',
  'proof_required', 'wrong_proof', 'too_many_wrong', 'invalid_pin_format',
};

const String _nothingLost = 'Nothing is lost.';

/// Turns anything that can go wrong into words. Never returns an exception's text, a status code or a reason code.
/// Reuses [AccountProblem] so the screens share one shape with the family account screens.
AccountProblem recoveryProblemFor(Object error, RecoveryAction action, {String helperName = ''}) {
  if (error is AccountFailure) return error.problem;
  if (error is TransportPolicyViolation) {
    return const AccountProblem(
        "This copy of Olive isn't set up to reach a server, so this can't be done from it.", ProblemKind.cannot,
        reason: 'transport_policy');
  }
  if (error is ApiException) return _forApi(error, action, helperName);
  if (error is TimeoutException || error is SocketException || error is http.ClientException ||
      error is HandshakeException || error is TlsException) {
    return const AccountProblem(
        "Olive couldn't reach the server, or didn't hear back. Check your connection and try again. "
        '$_nothingLost If you are not sure it went through, look again before you try a second time.',
        ProblemKind.tryAgain,
        reason: 'network');
  }
  return const AccountProblem('Something went wrong on this phone. Nothing was changed. Try again.',
      ProblemKind.tryAgain, reason: 'unexpected');
}

AccountProblem _forApi(ApiException e, RecoveryAction a, String helperName) {
  final String code = e.error;
  AccountProblem fix(String m) => AccountProblem(m, ProblemKind.fixInput, reason: code);
  AccountProblem cannot(String m) => AccountProblem(m, ProblemKind.cannot, reason: code);
  AccountProblem wait(String m) => AccountProblem(m, ProblemKind.wait, reason: code);

  if (e.statusCode == 429 || code == 'rate_limited' || code == 'recovery_rate_limited') {
    return wait('There were too many wrong tries in a short time. Wait a few minutes, then try again. '
        'This does not lock anyone out of their own phone.');
  }
  if (e.statusCode >= 500) {
    return const AccountProblem(
        'The server had a problem, so Olive cannot be sure that went through. $_nothingLost Look at the screen again '
        'before you try a second time.',
        ProblemKind.tryAgain,
        reason: 'server_error');
  }
  switch (code) {
    // the session and the own-PIN step-up
    case 'guardian_session_required':
    case 'device_revoked':
    case 'invalid_device_credential':
      return const AccountProblem('Your sign-in on this phone has ended. Sign in again to carry on.',
          ProblemKind.needsSignIn,
          reason: 'signed_out');
    case 'account_deactivated':
    case 'account_not_found':
      return cannot("The server can't find this account any more. Ask whoever runs your server.");
    case 'pin_required':
      return fix('Type your PIN. It is 4 to 8 digits.');
    case 'invalid_pin_format':
      return fix('A PIN is 4 to 8 digits, with no letters or spaces.');
    case 'pin_incorrect':
      return fix("That PIN isn't right. Check it and try again.");
    case 'pin_locked':
      return wait('Too many wrong PINs on this account. Try again in 15 minutes.');
    case 'pin_not_set':
      return cannot('This account does not have a PIN yet. Set one first, then try again.');
    // the sheet
    case 'recovery_key_required':
      return fix('Type the recovery key from your sheet. It has six groups of four letters and numbers.');
    case 'no_sheet':
      return cannot('There is no recovery sheet yet. Make one first.');
    case 'wrong_key':
      return fix("That isn't the key from your sheet. Look at the paper again. Nothing was changed.");
    case 'invalid_sheet':
      return fix("That recovery key didn't match. Check each group on the paper. If you made a newer sheet, use the "
          'newest one. Nothing was changed.');
    // the helper
    case 'invalid_label':
      return fix('Type a first name, like Aunt Sam. It can be up to 40 letters and cannot have an @ in it.');
    case 'invite_code_required':
      return fix('Type the helper code you were given. It has four groups of four letters and numbers.');
    case 'invalid_invite':
      return fix("That helper code didn't work. It may have a typo, it may have been used already, or it may have run "
          'out. Ask them to make you a new one.');
    case 'helper_key_required':
    case 'invalid_helper':
      return cannot('This phone is not anyone\'s helper any more. They may have taken you off, or named someone else. '
          'You do not need to do anything.');
    case 'answer_required':
      return fix('Choose yes or no.');
    // the recovery
    case 'target_required':
      return fix('Choose who you are helping.');
    case 'not_family':
      return cannot("That person isn't another grown-up in your family, so you can't do this for them.");
    case 'ask_other_grownup':
      return cannot('Another grown-up in your family has a phone that works. For safety, ask them to help you from '
          'their phone: it is the quickest way back, and it needs their yes. Nothing was changed.');
    case 'too_many_open':
      return cannot('A few recoveries are already waiting for this account. Stop the ones you do not recognise, then '
          'try again.');
    case 'too_many_recent':
      return wait('A lot of recoveries were started for this account today. Wait until tomorrow. $_nothingLost');
    case 'recovery_code_required':
      return fix('Type the code you were given. It has five groups of four letters and numbers.');
    case 'invalid_recovery':
      return a == RecoveryAction.finish || a == RecoveryAction.checkStatus
          ? cannot('This recovery is over: it was stopped, it finished, or it ran out. Nothing was changed. You can '
              'start again.')
          : fix("That code didn't work. It may have a typo, it may have been stopped, or it may have run out. Check "
              'it, or ask them for a new one.');
    case 'too_early':
      return wait('It is not time yet. The waiting period is not over. Nothing was changed.');
    case 'waiting_for_helper':
      return wait(helperName.isEmpty
          ? 'The waiting time is over. Now your trusted helper has to say yes.'
          : 'The waiting time is over. Now $helperName has to say yes.');
    case 'proof_required':
      return fix('Type your PIN, or the recovery key from your sheet.');
    case 'wrong_proof':
      return fix("That PIN or key isn't right. Check it and try again. After five wrong tries this recovery stops, "
          'and you can start a new one. Nobody else is locked out.');
    case 'too_many_wrong':
      return cannot('There were too many wrong tries, so this recovery was stopped. Nothing was changed, and every '
          'other phone still works. You can start again.');
    case 'not_found':
      return cannot('That recovery is not here any more. It may have finished or been stopped.');
  }
  return const AccountProblem('That did not work. Nothing was changed. Try again in a little while.',
      ProblemKind.tryAgain,
      reason: 'unknown');
}
