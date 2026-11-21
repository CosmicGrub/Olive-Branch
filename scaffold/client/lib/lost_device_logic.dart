// OLIVE BRANCH — a lost or stolen phone or tablet: the plain-words and the parsing half. Verified headless
// (client/test/lost_device_logic_test.dart, lost_device_contract_test.dart). MASTERFILE section 7.23.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 7.23).
//
// WHAT IS HERE. No screen, no storage and no network: what a family device looks like on the wire, the sentence for
// each state it can be in, the honest "what this does and does not do" paragraphs, and the one sentence for every
// reason a lost-device call can fail.
//
// THE RULES THE WORDS HOLD TO (and tests hold them to):
//   * Adult words, one idea per sentence. No "token", "credential", "hash", "revoke", "session" or "encrypted".
//   * No server code, status, id or exception text is ever the message ([lostProblemFor]).
//   * Every sentence says what is still true: nothing is deleted, and what can still be undone.
//   * The limits are said out loud: Olive cannot reach a phone that is switched off or offline, cannot find it and
//     cannot lock another company's phone. It does not promise more than it does.
//   * A child sees none of it. Nothing here is imported from a child-side file (a test holds that), and no child's
//     name, picture or count appears in a sentence.
import 'api_client.dart' show ApiException;
import 'family_account_logic.dart';
import 'recovery_paths_logic.dart' show RecoveryAction, recoveryProblemFor, waitWords, whenWords;

/// Where a phone or tablet stands. Words from the server's own standings.
enum DeviceStanding { active, paused, revoked }

DeviceStanding standingFromWire(Object? v) => switch (v) {
      'paused' => DeviceStanding.paused,
      'revoked' => DeviceStanding.revoked,
      _ => DeviceStanding.active,
    };

/// The state of an order to erase the app's copy on a lost grown-up's phone.
enum WipeProgress { none, ordered, done }

WipeProgress wipeFromWire(Object? v) => switch (v) {
      'ordered' => WipeProgress.ordered,
      'done' => WipeProgress.done,
      _ => WipeProgress.none,
    };

/// One phone or tablet of the family, as the signed-in grown-up may see and act on it. Never a credential, a place or
/// a child's name: the label is whatever the person called the device, the owner is a grown-up's first name.
class FamilyDevice {
  const FamilyDevice({
    required this.id,
    required this.isTablet,
    required this.label,
    required this.ownerName,
    required this.isThisDevice,
    required this.isOwn,
    required this.standing,
    required this.pausedAt,
    required this.revokeDueAt,
    required this.incidentId,
    required this.markedByName,
    required this.markedByMe,
    required this.canMarkLost,
    required this.canFound,
    required this.canConfirmLost,
    required this.wipe,
    required this.canOrderWipe,
    required this.canCancelWipe,
  });

  final String id;
  final bool isTablet;
  final String label;
  final String? ownerName;
  final bool isThisDevice;
  final bool isOwn;
  final DeviceStanding standing;
  final DateTime? pausedAt;
  final DateTime? revokeDueAt;
  final String? incidentId;
  final String? markedByName;
  final bool markedByMe;
  final bool canMarkLost;
  final bool canFound;
  final bool canConfirmLost;
  final WipeProgress wipe;
  final bool canOrderWipe;
  final bool canCancelWipe;

  /// Refuses a record with no usable id; every other field falls back to the safest reading (no action offered).
  static FamilyDevice? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    DateTime? when(Object? v) => v is String ? DateTime.tryParse(v) : null;
    String? text(Object? v, int max) => v is String && v.isNotEmpty ? (v.length > max ? v.substring(0, max) : v) : null;
    return FamilyDevice(
      id: id,
      isTablet: raw['role'] == 'child',
      label: text(raw['label'], 60) ?? (raw['role'] == 'child' ? 'Tablet' : 'Phone'),
      ownerName: text(raw['ownerName'], 80),
      isThisDevice: raw['isThisDevice'] == true,
      isOwn: raw['isOwn'] == true,
      standing: standingFromWire(raw['state']),
      pausedAt: when(raw['pausedAt']),
      revokeDueAt: when(raw['revokeDueAt']),
      incidentId: text(raw['incidentId'], 64),
      markedByName: text(raw['markedByName'], 80),
      markedByMe: raw['markedByMe'] == true,
      canMarkLost: raw['canMarkLost'] == true,
      canFound: raw['canFound'] == true,
      canConfirmLost: raw['canConfirmLost'] == true,
      wipe: wipeFromWire(raw['wipe']),
      canOrderWipe: raw['canOrderWipe'] == true,
      canCancelWipe: raw['canCancelWipe'] == true,
    );
  }

  /// What the screens call it: "Your phone (Pixel)", "Sam's phone", "A tablet (Kitchen)". Never an id.
  String get title {
    if (isTablet) return label.isEmpty ? 'A tablet' : 'Tablet: $label';
    if (isOwn) return label.isEmpty ? 'Your phone' : 'Your phone: $label';
    final String who = ownerName == null || ownerName!.isEmpty ? "Another grown-up's" : "$ownerName's";
    return label.isEmpty ? '$who phone' : '$who phone: $label';
  }
}

/// The list the screen draws, newest working devices first (the server's own order), with the devices that are cut off
/// for good listed last so they never crowd out one that still matters.
List<FamilyDevice> parseFamilyDevices(Object? body) {
  if (body is! Map || body['devices'] is! List) return const <FamilyDevice>[];
  final List<FamilyDevice> out = <FamilyDevice>[];
  for (final Object? e in body['devices'] as List) {
    final FamilyDevice? d = FamilyDevice.tryParse(e);
    if (d != null) out.add(d);
  }
  return <FamilyDevice>[
    ...out.where((FamilyDevice d) => d.standing != DeviceStanding.revoked),
    ...out.where((FamilyDevice d) => d.standing == DeviceStanding.revoked),
  ];
}

/// The answer to one action (mark, found, confirm, order or cancel): the state the device is in now.
class DeviceActionResult {
  const DeviceActionResult({required this.deviceId, required this.standing, required this.incidentId, required this.revokeDueAt, required this.already});
  final String deviceId;
  final DeviceStanding standing;
  final String? incidentId;
  final DateTime? revokeDueAt;
  final bool already;

  static DeviceActionResult? tryParse(Object? raw) {
    if (raw is! Map || raw['deviceId'] is! String) return null;
    return DeviceActionResult(
      deviceId: raw['deviceId'] as String,
      standing: standingFromWire(raw['state']),
      incidentId: raw['incidentId'] is String ? raw['incidentId'] as String : null,
      revokeDueAt: raw['revokeDueAt'] is String ? DateTime.tryParse(raw['revokeDueAt'] as String) : null,
      already: raw['already'] == true,
    );
  }
}

// ---- the words ------------------------------------------------------------------------------------------------------

const String kNothingDeleted = 'Nothing is deleted. Every message, picture and record stays safe with your family.';

/// One line under a device on the list.
String deviceStatusLine(FamilyDevice d, DateTime now) {
  switch (d.standing) {
    case DeviceStanding.active:
      return d.isThisDevice ? 'This is the phone in your hand.' : 'Working normally.';
    case DeviceStanding.paused:
      final String by = d.markedByMe
          ? 'You marked it as lost'
          : d.markedByName == null
              ? 'It was marked as lost'
              : '${d.markedByName} marked it as lost';
      final DateTime? due = d.revokeDueAt;
      final String tail = due == null
          ? ''
          : ' If nobody says "I have it" it is cut off for good ${whenWords(due, now)}.';
      return '$by. It is paused and gets nothing new.$tail';
    case DeviceStanding.revoked:
      return 'Cut off for good. It can only come back by being added again.';
  }
}

/// The notice every grown-up sees while a phone or tablet is marked as lost: who, what it means, and until when.
String lostNoticeSentence(FamilyDevice d, DateTime now) {
  final String by = d.markedByMe
      ? ' by you'
      : d.markedByName == null
          ? ''
          : ' by ${d.markedByName}';
  final DateTime? due = d.revokeDueAt;
  final String until = due == null ? '' : ' It can come back until ${whenWords(due, now)}.';
  return '${d.title} was marked as lost$by. It is paused and gets nothing new. $kNothingDeleted$until';
}

/// One line about the erase order, or null when there is nothing to say.
String? wipeStatusLine(FamilyDevice d) => switch (d.wipe) {
      WipeProgress.none => null,
      WipeProgress.ordered => "Waiting to erase Olive's copy on that phone. It happens the next time the phone is online.",
      WipeProgress.done => "That phone has erased Olive's copy of your family's records. Your family's records are safe.",
    };

/// The honest paragraph shown BEFORE a grown-up marks a device as lost. Says what happens, what does not, and the limits.
String markLostExplanation(FamilyDevice d) {
  final String what = d.isTablet ? 'tablet' : 'phone';
  return 'This stops the $what getting anything new from your family, right away. $kNothingDeleted '
      'You have 3 days to change your mind: tap "I have it" and the $what comes back. '
      'If nobody does, after 3 days it is cut off for good.';
}

/// What marking as lost CANNOT do. Always shown with the explanation, never hidden behind a "more".
String markLostLimits(FamilyDevice d) {
  final String what = d.isTablet ? 'tablet' : 'phone';
  return 'Olive cannot find the $what, lock it, or see where it is. If it is switched off or offline, it keeps what it '
      'already had until it connects. For a phone that was stolen, also lock or trace it with your phone company.';
}

/// Shown before "Erase it when it connects".
const String kEraseExplanation =
    "When the lost phone next connects to the internet, Olive on it will erase its own copy of your family's records. "
    "Your family's records are not touched: they stay with your family and with everyone else's phones. "
    'Only you, the phone\'s owner, can ask for this.';

/// What erasing CANNOT do.
const String kEraseLimits =
    'It only happens when the phone is switched on and online. Until then, whatever is on it stays on it. '
    'If you find the phone before it connects, tap "I have it" and the erase is cancelled. Once it has been erased, that '
    'phone has to be added to your family again, like a new one.';

/// Shown on the lost phone itself when it is paused and asks to come back.
const String kPausedPhoneTitle = 'This phone was marked as lost';
const String kPausedPhoneBody =
    'A grown-up in your family marked this phone as lost, so it is paused. Nothing on your family\'s account was deleted. '
    'If you have the phone and it is yours, ask the grown-up to tap "I have it" on another phone. Then type your own PIN '
    'here once.';

const String kErasedPhoneBody =
    "Olive on this phone erased its copy of your family's records, because the phone was marked as lost. Your family's "
    'records are safe. To use Olive here again, ask a grown-up to add this phone to the family.';

// ---- what can go wrong -----------------------------------------------------------------------------------------------

enum LostAction { load, mark, found, confirm, orderWipe, cancelWipe }

/// Every reason the lost-device routes can answer with. A test reads server/routes.mjs and packages/db/src/pool.ts
/// and fails if one there is missing from this set, so a new server answer cannot reach a person as a bare code.
const Set<String> kLostKnownReasons = <String>{
  // this feature's own answers
  'not_found', 'already_revoked', 'this_device', 'rate_limited', 'not_paused', 'stale_incident', 'too_late',
  'owner_only', 'not_a_grown_up_phone', 'already_wiped', 'no_wipe_ordered', 'incident_required',
  // the session and the own-PIN step-up (shared with the recovery screens)
  'guardian_session_required', 'pin_required', 'pin_incorrect', 'pin_locked', 'pin_not_set', 'device_revoked',
  'invalid_device_credential', 'account_deactivated', 'invalid_pin_format',
  // a phone that is itself paused or erased asking to come back
  'device_paused', 'device_credential_required',
};

/// Turns anything that can go wrong into words. Never returns an exception's text, a status code or a reason code.
AccountProblem lostProblemFor(Object error, LostAction action) {
  if (error is AccountFailure) return error.problem;
  if (error is ApiException) {
    AccountProblem cannot(String m) => AccountProblem(m, ProblemKind.cannot, reason: error.error);
    AccountProblem wait(String m) => AccountProblem(m, ProblemKind.wait, reason: error.error);
    switch (error.error) {
      case 'not_found':
        return cannot("That phone isn't on your family's list any more. Pull down to look again. Nothing was changed.");
      case 'already_revoked':
        return cannot('That phone is already cut off for good, so there is nothing more to do. Nothing was deleted.');
      case 'this_device':
        return cannot("You can't do this to the phone in your hand. Use another phone of yours or another grown-up's. "
            'If this phone is the one you want to sign out of, use Sign out in Settings.');
      case 'rate_limited':
        return wait('That phone was marked as lost too many times today. Wait until tomorrow. Nothing was changed.');
      case 'not_paused':
        return cannot(action == LostAction.orderWipe
            ? "Olive can only erase a phone that was marked as lost first. Mark it as lost, then try again. Nothing was changed."
            : 'That phone is not paused any more, so this does not apply. Look again. Nothing was changed.');
      case 'stale_incident':
        return cannot('That phone was marked as lost again since you last looked. Look again, then choose what to do. '
            'Nothing was changed.');
      case 'too_late':
        return cannot('The 3 days are over, so that phone is cut off for good. To use it again, add it to your family '
            'again, like a new phone. Nothing was deleted.');
      case 'owner_only':
        return cannot(action == LostAction.confirm
            ? "Only the phone's owner can make the cut-off final. If they do nothing, it happens by itself after 3 days."
            : action == LostAction.orderWipe || action == LostAction.cancelWipe
                ? "Only the phone's owner can ask for it to be erased. Ask them to do it from their own phone."
                : "The phone's owner marked it as lost themselves, so only they can bring it back. Ask them. Nothing was "
                    'changed.');
      case 'not_a_grown_up_phone':
        return cannot("A child's tablet is never erased by a grown-up. What the child keeps there is hers. You can still "
            'pause the tablet, so it gets nothing new.');
      case 'already_wiped':
        return cannot(action == LostAction.found
            ? "That phone already erased Olive's copy, so there is nothing to bring back. Add it to your family again, "
                'like a new phone.'
            : 'That phone already erased its copy, so this can no longer be changed.');
      case 'no_wipe_ordered':
        return cannot('There is nothing waiting to be erased on that phone. Nothing was changed.');
      case 'incident_required':
        return cannot('Look at the list again, then choose what to do. Nothing was changed.');
    }
  }
  // The shared sentences: wrong PIN, signed out, no signal, a server problem, and anything unexpected.
  return recoveryProblemFor(error, RecoveryAction.loadSummary);
}

/// "in about 2 days" for the deadline of a pause, without a count-down.
String deadlineWords(DateTime due, DateTime now) => due.isAfter(now) ? 'in ${waitWords(due.difference(now))}' : 'now';
