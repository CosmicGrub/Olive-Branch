// OLIVE BRANCH — the plain adult words for a lost or stolen phone or tablet. Pure Dart, no screens, so one test can read
// every sentence (client/test/lost_device_words_test.dart: short sentences, no fear words, the honest limit present,
// nothing a child could be shown).
//
// WHO SEES THESE. Grown-ups only, on grown-up phones. A child's tablet shows none of it (MASTERFILE section 2.1, P1 to
// P11): a paused or cut-off tablet keeps working for her and she reads no notice, count or reason.
//
// THE HONEST LIMIT, on purpose and in plain words. Marking a phone as lost stops NEW things reaching it and keeps every
// record safe in the family. It cannot take back what was already on the phone: someone who had it open when they took
// it could have read what was on it at that moment. So these screens never say "your records stay locked" without
// saying that, and they never promise more than the app does (the app cannot lock a phone from far away, and it never
// says "stolen").

/// The sentence that says what a mark can and cannot do. Every screen that offers "Mark as lost" shows it.
const String kLostHonestLimit =
    'Marking a phone as lost stops anything new reaching it. It cannot take back what was already on the phone: '
    'if someone had it open when they took it, they could have read what was on it then.';

String _first(String name) => name.trim().isEmpty ? 'Their' : name.trim();

String _possessive(String name) {
  final String n = _first(name);
  return n.endsWith('s') ? "$n'" : "$n's";
}

/// What a grown-up reads on the screen that lists phones and tablets.
class LostDeviceWords {
  const LostDeviceWords._();

  static const String screenTitle = 'Phones and tablets';
  static const String screenIntro =
      'See every phone and tablet in your family. If one is lost, you can cut it off from new updates. '
      'Nothing is deleted, and you can undo it.';
  static const String loadError = "Couldn't load your phones and tablets. Check your connection.";
  static const String settingsSubtitle = 'Lost one? Cut it off from new updates. Nothing is deleted';

  /// Who a device belongs to, for a list row.
  static String deviceName({required bool isChild, required String? ownerName, required String? childName, required bool isThisDevice}) {
    if (isThisDevice) return 'This phone';
    if (isChild) return childName == null || childName.trim().isEmpty ? "A child's tablet" : '${_possessive(childName)} tablet';
    return '${_possessive(ownerName ?? '')} phone';
  }

  // ---- L1: marking --------------------------------------------------------------------------------------------
  static String markTitle({required String name, required bool isChild, required bool isOwn}) {
    if (isChild) return 'Mark ${_possessive(name)} tablet as lost?';
    if (isOwn) return 'Mark your other phone as lost?';
    return 'Mark ${_possessive(name)} phone as lost?';
  }

  static const List<String> markLines = <String>[
    'New family updates will stop going to it.',
    'Nothing is deleted. Your family\'s records stay safe.',
    kLostHonestLimit,
    'You can undo this at any time in the next 3 days.',
  ];

  static String markToldLine({required bool isOwn, required bool isChild, required String name}) =>
      isChild ? 'Every grown-up will be told.' : (isOwn ? 'Every grown-up will be told.' : '${_first(name)} will be told, and can say "I have it". Every grown-up will be told.');

  static const String markButton = 'Mark as lost';
  static const String notNow = 'Not now';
  static const String pinWhy = 'Marking a phone as lost needs your PIN.';
  static const String pinTitle = 'Enter your PIN';

  static String markedDone(String deviceName) => '$deviceName is marked as lost. Every grown-up will be told.';

  // ---- L2: told on the owner's other devices ------------------------------------------------------------------
  static String ownerTitle() => 'Your phone was marked as lost';
  static String ownerBody(String who) =>
      '${_first(who)} marked your phone as lost. If you have it, tap "I have it" and everything goes back to normal. '
      'You will type your PIN on it once.';
  static const String foundButton = 'I have it';
  static const String lostButton = 'It is lost';

  // ---- L3: notice to every grown-up ---------------------------------------------------------------------------
  static String noticeTitle(String deviceName) => '$deviceName is marked as lost';
  static const List<String> noticeLines = <String>[
    'New family updates will not go to it.',
    'What was on it before is not erased. Anyone who had it open could have read that.',
    'Your own records are not affected.',
  ];
  static String noticeFoundTitle(String deviceName) => '$deviceName was found';
  static const String noticeFoundLine = 'It is back in use.';
  static String noticeFinalTitle(String deviceName) => '$deviceName was removed from the family';
  static const String noticeFinalLine = 'It can no longer get anything new. If it turns up, add it again with a new code.';

  // ---- the state line on a device row -------------------------------------------------------------------------
  /// "Cut off from new updates. Becomes final in about 3 days."
  static String pausedLine({required String? markedBy, required String endsIn}) =>
      'Marked as lost${markedBy == null ? '' : ' by ${_first(markedBy)}'}. Cut off from new updates. Nothing is deleted. '
      'Final in $endsIn unless it is found.';
  static const String removedLine = 'Removed from the family.';

  /// "about 3 days", "about 5 hours", "less than an hour".
  static String endsIn(DateTime due, DateTime now) {
    final Duration d = due.difference(now);
    if (d.inMinutes < 60) return 'less than an hour';
    if (d.inHours < 48) return 'about ${d.inHours} hours';
    return 'about ${d.inDays} days';
  }

  static const String foundDone = 'Done. It is back in use. It will ask for its owner\'s PIN once.';
  static const String lostDone = 'Done. It was removed from the family. If it turns up, add it again with a new code.';

  static const String confirmLostTitle = 'It is lost for good?';
  static const String confirmLostBody =
      'It will be removed from the family now. Nothing in your family\'s records is deleted. '
      'If it turns up, you can add it again with a new code.';
  static const String confirmLostButton = 'Remove it';

  // ---- refusals, in plain words ---------------------------------------------------------------------------
  static String refusal(String error) => switch (error) {
        'rate_limited' => 'That phone was marked a few times today already. Try again tomorrow, or ask another grown-up.',
        'owner_only' => 'Only the owner of that phone can do that from here. They have been told.',
        'already_revoked' => 'That phone was already removed from the family.',
        'too_late' => 'The 3 days are over, so it was removed. If you find it, add it again with a new code.',
        'stale_incident' => 'That answer was for an earlier report. Refresh and look again.',
        'not_paused' => 'That phone is not marked as lost any more. Refresh and look again.',
        'this_device' => 'You are holding that phone. Use another phone to mark it.',
        'not_found' => "That phone isn't one of your family's.",
        _ => "That didn't work. Check your connection and try again.",
      };

  // ---- on the lost phone itself (when it makes contact) ----------------------------------------------------------
  static const String pausedCoverTitle = 'This phone is paused';
  static const String pausedCoverBody =
      'A grown-up in your family paused it. Nothing was deleted. If this is your phone, say "I have it" from another '
      'family phone, then check again here.';
  static const String checkAgain = 'Check again';
  static const String pausedStillPaused = 'Still paused.';
  static const String pinCoverTitle = 'Use this phone again?';
  static const String pinCoverBody = 'We will check it is really yours with your PIN.';
  static const String pinCoverButton = 'Check my PIN';
  static const String pinCoverLater = 'Not yet';
  static const String pinWrong = "That PIN doesn't match. Try again.";
  static const String pinLocked = 'Too many wrong tries. Try again in 15 minutes.';

  static const String cutOffCoverTitle = 'This phone was removed from the family';
  static const String cutOffCoverBody =
      'It no longer holds your family\'s records. They are safe with the family. To use it again, add it with a new code.';
  static String cutOffUnsent(int n) => n <= 0
      ? ''
      : (n == 1
          ? 'One thing you wrote here had not been sent yet. It is kept safe and will be sent when you add this phone again.'
          : '$n things you wrote here had not been sent yet. They are kept safe and will be sent when you add this phone again.');

  /// Every sentence a grown-up can be shown by this file, for the words test.
  static List<String> everySentence() => <String>[
        screenTitle, screenIntro, loadError, settingsSubtitle, kLostHonestLimit,
        markTitle(name: 'Alex', isChild: false, isOwn: false), markTitle(name: 'Ivy', isChild: true, isOwn: false),
        markTitle(name: '', isChild: false, isOwn: true),
        ...markLines, markToldLine(isOwn: false, isChild: false, name: 'Alex'), markToldLine(isOwn: true, isChild: false, name: ''),
        markButton, notNow, pinWhy, pinTitle, markedDone('Alex\'s phone'),
        ownerTitle(), ownerBody('Sam'), foundButton, lostButton,
        noticeTitle('Alex\'s phone'), ...noticeLines, noticeFoundTitle('Alex\'s phone'), noticeFoundLine,
        noticeFinalTitle('Alex\'s phone'), noticeFinalLine,
        pausedLine(markedBy: 'Sam', endsIn: 'about 3 days'), removedLine,
        foundDone, lostDone, confirmLostTitle, confirmLostBody, confirmLostButton,
        for (final String e in <String>['rate_limited', 'owner_only', 'already_revoked', 'too_late', 'stale_incident', 'not_paused', 'this_device', 'not_found', 'x'])
          refusal(e),
        pausedCoverTitle, pausedCoverBody, checkAgain, pausedStillPaused, pinCoverTitle, pinCoverBody, pinCoverButton,
        pinCoverLater, pinWrong, pinLocked, cutOffCoverTitle, cutOffCoverBody, cutOffUnsent(1), cutOffUnsent(3),
      ];
}
