// OLIVE BRANCH — the people in the village, and what one grown-up can do about another: pause, end (together, or with a
// long notice), the limits agreement with its think-over, and the Standing OK. UNVERIFIED on a device; pure Dart, runs
// headless in CI (client/test/village_people_test.dart). Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 4.4, 4.5,
// 5.2 and 6.2, and the owner's co-parent rules: nobody removes another parent alone; either parent may pause, which is
// reversible and visible to all; ending needs both parents, or a 14 day wait with a notice on every device.
//
// WHAT THIS IS. The adult-side service behind the "People in the village" screens (village_people_screens.dart). It signs
// entries the reduce rule (family_ledger_state.dart) reads, then asks the reduce rule whether it took them; an entry the
// rule refuses is taken back and said in plain words, so a screen can never promise what the rule would not do. The rule,
// not this file, decides everything.
//
// WHAT THIS IS NOT. It does not enforce anything on a child's tablet or anywhere outside the family record: a paused
// carer's phone is shown as paused here, and a tablet that checks the record before it lets a phone in is a later wave. It
// does not rotate the family keys when someone is ended (a phone that was ended still holds the keys it already had). It
// carries no read receipts and says nothing a child could see: nothing in a child file imports this one (a test guards it).
import 'dart:typed_data';

import 'family_ledger.dart';
import 'family_ledger_state.dart';
import 'family_profiles.dart';
import 'family_state.dart';
import 'welcome_logic.dart' show cleanName, dateWords, profileLine;

/// Why something could not be done, in words a grown-up reads. [code] is for tests.
class PeopleRefused implements Exception {
  const PeopleRefused(this.code, this.words);
  final String code, words;
  @override
  String toString() => 'PeopleRefused($code)';
}

/// The three things a limits agreement may switch off for a parent, in the words the screens use.
const Map<int, String> kLimitWords = <int, String>{
  6: 'Change family settings and parental controls',
  8: 'Connect a child’s device',
  11: 'Welcome other people',
};

String limitWords(int c) => kLimitWords[c] ?? 'Something else';

/// One person in the village, as a list line and a page.
class PersonCard {
  PersonCard({
    required this.gidHex,
    required this.name,
    required this.isParent,
    required this.isMe,
    required this.line,
    required this.welcomedBy,
    required this.pausedBy,
    required this.pausedAtMs,
    required this.notice,
    required this.limits,
    required this.settlingUntilMs,
    required this.standingUntilMs,
    required this.iWelcomedThem,
  });
  final String gidHex, name, line;
  final bool isParent, isMe, iWelcomedThem;
  final String? welcomedBy, pausedBy;
  final int? pausedAtMs, settlingUntilMs, standingUntilMs;
  final EndNotice? notice;
  final List<int> limits;

  bool get paused => pausedBy != null;
}

/// Something waiting for a yes or a no from this grown-up (a limits agreement, an end that needs their yes, a request
/// to loosen limits, a parent's end by agreement).
class PendingAsk {
  PendingAsk({
    required this.hashHex,
    required this.type,
    required this.kind,
    required this.askerName,
    required this.subjectName,
    required this.limits,
    required this.expMs,
    required this.answerFromMs,
    required this.needsMyAnswer,
    required this.mine,
    required this.status,
  });
  final String hashHex, type, kind, askerName, subjectName, status;
  final List<int> limits;
  final int expMs;

  /// A yes is counted only from this time (the think-over); 0 when it may be answered at once.
  final int answerFromMs;
  final bool needsMyAnswer, mine;

  /// 'limits' (limits on a parent), 'loosen' (a limited parent asks for fewer), 'end-carer' (an end that needs the
  /// welcoming parent's yes) or 'remove' (ending a parent together).
  bool get open => status == 'pending';
}

class PeopleOverview {
  PeopleOverview({
    required this.people,
    required this.asks,
    required this.notices,
    required this.iAmPaused,
    required this.myLimits,
    required this.myStandingUntilMs,
    required this.iAmSettling,
    required this.iCanAct,
  });
  final List<PersonCard> people;
  final List<PendingAsk> asks;

  /// Plain lines every grown-up phone shows for as long as they are true (pauses, running notices, limits in force).
  final List<String> notices;
  final bool iAmPaused, iAmSettling, iCanAct;
  final List<int> myLimits;
  final int? myStandingUntilMs;

  List<PendingAsk> get forMe => <PendingAsk>[for (final PendingAsk a in asks) if (a.open && a.needsMyAnswer) a];
  List<PendingAsk> get waitingOnOthers => <PendingAsk>[for (final PendingAsk a in asks) if (a.open && a.mine) a];
}

/// What happened when a grown-up acted: said at once on the screen.
enum EndResult { ended, askedWelcomer, noticeGiven }

class PeopleService {
  PeopleService({required this.context, required this.repository, required this.nowMs, required this.childName});

  final FamilyContext context;
  final FamilyRepository repository;
  final int Function() nowMs;
  final String childName;

  Future<void> _persist() => repository.save(context.snapshot());

  /// Either happens in full or not at all (the lists are put back if anything throws).
  Future<T> _all<T>(Future<T> Function() body) async {
    final List<LedgerEntry> entries = List<LedgerEntry>.of(context.entries);
    final List<LedgerVote> votes = List<LedgerVote>.of(context.votes);
    try {
      return await body();
    } catch (e) {
      context.entries
        ..clear()
        ..addAll(entries);
      context.votes
        ..clear()
        ..addAll(votes);
      if (e is PeopleRefused) rethrow;
      throw const PeopleRefused('not-saved', 'That could not be saved on this phone, so nothing was changed. Please try again.');
    }
  }

  // ---- reading ------------------------------------------------------------------------------------------------

  String _name(LedgerState s, String? gid) {
    for (final LedgerMember m in s.members) {
      if (m.gidHex == gid) return m.name;
    }
    return 'A parent';
  }

  Future<PeopleOverview> overview() async {
    final int now = nowMs();
    final LedgerState s = await context.state(nowMs: now);
    if (!s.ok) {
      return PeopleOverview(
          people: const <PersonCard>[], asks: const <PendingAsk>[], notices: const <String>[], iAmPaused: false,
          myLimits: const <int>[], myStandingUntilMs: null, iAmSettling: false, iCanAct: false);
    }
    final LedgerDevice? me = s.deviceFor(context.device.publicKey);
    final String myGid = me?.gidHex ?? '';
    final bool parent = me?.kind == 'guardian';
    final List<PersonCard> people = <PersonCard>[
      for (final LedgerMember m in s.members)
        PersonCard(
          gidHex: m.gidHex,
          name: m.name,
          isParent: m.isGuardian,
          isMe: m.gidHex == myGid,
          line: m.isGuardian
              ? (s.limitsOf(m.gidHex).isEmpty ? 'Parent' : 'Parent, with limits')
              : (m.profile == null ? 'Carer' : profileLine(m.profile!)),
          welcomedBy: m.welcomedByGidHex == null ? null : _name(s, m.welcomedByGidHex),
          pausedBy: s.pauseOf(m.gidHex) == null ? null : _name(s, s.pauseOf(m.gidHex)!.byGidHex),
          pausedAtMs: s.pauseOf(m.gidHex)?.atMs,
          notice: s.noticeFor(m.gidHex),
          limits: s.limitsOf(m.gidHex),
          settlingUntilMs: s.devices
              .where((LedgerDevice d) => d.gidHex == m.gidHex && d.settlingAt(now))
              .map((LedgerDevice d) => d.settleUntilMs)
              .fold<int?>(null, (int? a, int b) => a == null || b > a ? b : a),
          standingUntilMs: s.standingActive(m.gidHex) ? s.standing[m.gidHex] : null,
          iWelcomedThem: m.welcomedByGidHex == myGid && myGid.isNotEmpty,
        ),
    ]..sort((PersonCard a, PersonCard b) {
        if (a.isParent != b.isParent) return a.isParent ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    final Map<String, LedgerEntry> byHash = <String, LedgerEntry>{for (final LedgerEntry e in context.entries) e.hashHex: e};
    final List<PendingAsk> asks = <PendingAsk>[];
    for (final PendingItem p in s.pending) {
      if (p.type != EntryType.limitsAgree && p.type != EntryType.accessEnd && p.type != EntryType.guardianRemove) continue;
      if (p.status == 'lapsed' || p.status == 'declined') continue;
      final LedgerEntry? e = byHash[p.hashHex];
      if (e == null) continue;
      final String subjectGid = hexOf(e.body['gid']! as Uint8List);
      final String askerGid = p.proposerGidHex ?? '';
      final List<int> limits = e.type == EntryType.limitsAgree
          ? <int>[for (final Object? x in e.body['limits']! as List) x! as int]
          : const <int>[];
      final String kind = e.type == EntryType.limitsAgree
          ? (subjectGid == askerGid ? 'loosen' : 'limits')
          : (e.type == EntryType.guardianRemove ? 'remove' : 'end-carer');
      asks.add(PendingAsk(
        hashHex: p.hashHex,
        type: p.type,
        kind: kind,
        askerName: _name(s, askerGid),
        subjectName: _name(s, subjectGid),
        limits: limits,
        expMs: p.expMs ?? 0,
        answerFromMs: p.notBeforeMs ?? 0,
        needsMyAnswer: parent && p.requiredGidsHex.contains(myGid) && !p.yesGidsHex.contains(myGid),
        mine: askerGid == myGid,
        status: p.status,
      ));
    }
    final List<String> notices = <String>[];
    for (final PauseInfo p in s.paused) {
      final String who = _name(s, p.gidHex), by = _name(s, p.byGidHex);
      final LedgerMember m = s.members.firstWhere((LedgerMember x) => x.gidHex == p.gidHex);
      notices.add(m.isGuardian
          ? '$by paused $who’s access on ${dateWords(p.atMs)}. $who can still see everything, answer requests and leave. Another parent can resume it.'
          : '$by paused $who’s access on ${dateWords(p.atMs)}. Any other parent can resume it.');
    }
    for (final EndNotice n in s.endNotices) {
      final String who = _name(s, n.gidHex), by = _name(s, n.byGidHex);
      notices.add('$by gave notice that $who’s place in $childName’s village will end on ${dateWords(n.effMs)}. '
          '$by can take this back until then. $who can still see everything, answer requests and leave.');
    }
    for (final LedgerMember m in s.members) {
      final List<int> l = s.limitsOf(m.gidHex);
      if (l.isNotEmpty) {
        notices.add('${m.name} agreed to these limits: ${<String>[for (final int c in l) limitWords(c).toLowerCase()].join('; ')}.');
      }
      if (s.standingActive(m.gidHex)) {
        notices.add('${m.name} said yes in advance to look-only requests until ${dateWords(s.standing[m.gidHex]!)}.');
      }
    }
    return PeopleOverview(
      people: people,
      asks: asks,
      notices: notices,
      iAmPaused: s.isPaused(myGid),
      myLimits: s.limitsOf(myGid),
      myStandingUntilMs: s.standingActive(myGid) ? s.standing[myGid] : null,
      iAmSettling: me?.settlingAt(now) ?? false,
      iCanAct: s.canAct(context.device.publicKey, now),
    );
  }

  // ---- doing --------------------------------------------------------------------------------------------------

  /// Signs [type] with [body] and asks the reduce rule whether it took it. Taken back and refused in words if not.
  Future<LedgerEntry> _write(String type, Map<String, Object?> body, {int? at}) async {
    final int now = at ?? nowMs();
    final LedgerState s = await context.state(nowMs: now);
    if (!s.ok) throw const PeopleRefused('no-family', 'There is no village on this phone yet.');
    final LedgerDevice? me = s.deviceFor(context.device.publicKey);
    if (me == null || me.kind != 'guardian') {
      throw const PeopleRefused('not-a-parent', 'Only a parent’s phone can do this.');
    }
    return _all(() async {
      final LedgerEntry e = await LedgerEntry.sign(context.device, type: type, prev: s.heads, issuedAtMs: now, body: body);
      context.entries.add(e);
      final LedgerState s2 = await context.state(nowMs: now);
      final String? why = s2.rejected[e.hashHex] ?? s2.voided[e.hashHex];
      if (why != null) throw _words(why);
      await _persist();
      return e;
    });
  }

  PeopleRefused _words(String code) {
    switch (code) {
      case 'signer-paused':
        return const PeopleRefused(
            'paused', 'Your access is paused, so you cannot start this. You can still look, answer and leave. Another parent can resume you.');
      case 'signer-settling':
        return const PeopleRefused('settling', 'This phone is still settling in. You can do this once that ends.');
      case 'cannot-pause-yourself':
        return const PeopleRefused('yourself', 'You cannot pause yourself. You can leave the village from your own page.');
      case 'already-paused':
        return const PeopleRefused('already-paused', 'That access is already paused.');
      case 'not-paused':
        return const PeopleRefused('not-paused', 'That access is not paused.');
      case 'notice-already-running':
        return const PeopleRefused('notice-running', 'A notice is already running for that person.');
      case 'parents-end-together-or-by-notice':
        return const PeopleRefused('parent-end', 'A parent cannot be ended by one person at once. End it together, or give 14 days’ notice.');
      case 'welcome-limited':
      case 'settings-limited':
      case 'connect-limited':
        return const PeopleRefused('limited', 'You agreed to a limit that switches this off for you.');
      case 'not-a-loosening':
        return const PeopleRefused('not-looser', 'That list is not shorter than the one you have now.');
      case 'not-tighter':
        return const PeopleRefused('not-tighter', 'That list does not add to the limits you have now.');
      case 'nobody-to-agree':
        return const PeopleRefused('nobody', 'There is no other parent to ask.');
      case 'mutual-pause':
        return const PeopleRefused('both-paused', 'Both of you paused each other at the same moment, so neither pause stands. Look again, then decide.');
      default:
        return PeopleRefused('refused', 'That could not be done: $code.');
    }
  }

  Uint8List _g(String gid) => fromHex(gid);

  /// Either parent may pause another person at once. It is visible to every parent, never a removal, and any OTHER parent
  /// can resume it.
  Future<void> pause(String gidHex) => _write(EntryType.accessPause, <String, Object?>{'gid': _g(gidHex)});

  Future<void> resume(String gidHex) => _write(EntryType.accessResume, <String, Object?>{'gid': _g(gidHex)});

  /// Ends a carer: at once if this parent welcomed them, otherwise a request that needs the welcoming parent's yes.
  Future<EndResult> endCarer(String gidHex) async {
    final LedgerState s = await context.state(nowMs: nowMs());
    final LedgerMember? m = s.members.where((LedgerMember x) => x.gidHex == gidHex).firstOrNull;
    if (m == null || m.kind != 'carer') {
      throw const PeopleRefused('not-a-carer', 'Only a carer can be ended this way. A parent is ended together, or by notice.');
    }
    final LedgerEntry e = await _write(EntryType.accessEnd, <String, Object?>{'gid': _g(gidHex), 'reason': 'ended'});
    final LedgerState s2 = await context.state(nowMs: nowMs());
    return s2.members.any((LedgerMember x) => x.gidHex == gidHex) && s2.pending.any((PendingItem p) => p.hashHex == e.hashHex)
        ? EndResult.askedWelcomer
        : EndResult.ended;
  }

  /// A notice that someone's place will end in 14 days. Any parent, for anyone. Only the one who gave it can take it back.
  Future<void> giveNotice(String gidHex) =>
      _write(EntryType.accessEnd, <String, Object?>{'gid': _g(gidHex), 'reason': 'notice'});

  Future<void> cancelNotice(String gidHex) async {
    final LedgerState s = await context.state(nowMs: nowMs());
    final EndNotice? n = s.noticeFor(gidHex);
    if (n == null) throw const PeopleRefused('no-notice', 'There is no notice running for that person.');
    await _write(EntryType.accessEndCancel, <String, Object?>{'end': fromHex(n.hashHex)});
  }

  /// Ending a parent together: the other parent has to agree on their own phone.
  Future<void> proposeEndTogether(String gidHex) => _write(EntryType.guardianRemove,
      <String, Object?>{'gid': _g(gidHex), 'exp': nowMs() + kApprovalLifetimeMs});

  /// Asks another parent to agree to limits. Nothing changes until they say yes on their own phone, after a day.
  Future<void> proposeLimits(String gidHex, List<int> caps) {
    final List<int> sorted = (caps.toSet().toList()..sort());
    if (sorted.isEmpty) throw const PeopleRefused('no-limits', 'Choose at least one thing to limit.');
    final int now = nowMs();
    return _write(EntryType.limitsAgree,
        <String, Object?>{'gid': _g(gidHex), 'limits': sorted, 'until': now + kThinkOverMs}, at: now);
  }

  /// A parent adds to the limits they have agreed to. Immediate, and the other parent is told.
  Future<void> tightenMine(List<int> caps) async {
    final LedgerState s = await context.state(nowMs: nowMs());
    final String me = s.deviceFor(context.device.publicKey)?.gidHex ?? '';
    final List<int> all = <int>{...s.limitsOf(me), ...caps}.toList()..sort();
    await _write(EntryType.limitsTighten, <String, Object?>{'gid': _g(me), 'limits': all});
  }

  /// A limited parent asks for a shorter list (or none). The other parents have to agree.
  Future<void> askLoosen(List<int> keep) async {
    final LedgerState s = await context.state(nowMs: nowMs());
    final String me = s.deviceFor(context.device.publicKey)?.gidHex ?? '';
    final List<int> sorted = keep.toSet().toList()..sort();
    final int now = nowMs();
    await _write(EntryType.limitsAgree, <String, Object?>{'gid': _g(me), 'limits': sorted, 'until': now}, at: now);
  }

  /// A yes in advance to look-only welcomes until [days] from now (at most 90). Writing a new one replaces the old.
  Future<void> standingOk(int days) {
    if (days < 1 || days > kStandingMaxMs ~/ kMsPerDay) {
      throw const PeopleRefused('days', 'Choose between 1 and 90 days.');
    }
    return _writeStanding(nowMs() + days * kMsPerDay);
  }

  Future<void> takeBackStanding() => _writeStanding(0);

  Future<void> _writeStanding(int until) async {
    final LedgerState s = await context.state(nowMs: nowMs());
    final String me = s.deviceFor(context.device.publicKey)?.gidHex ?? '';
    await _write(EntryType.standingOk, <String, Object?>{'gid': _g(me), 'until': until});
  }

  /// A yes or a no to something waiting for this grown-up (limits, a carer's end, a parent's end together, a request to
  /// loosen). A limits agreement may be answered with a yes only once its think-over has ended; a no at any time.
  Future<void> answer(String hashHex, {required bool yes}) async {
    final PeopleOverview o = await overview();
    final PendingAsk? a = o.asks.where((PendingAsk x) => x.hashHex == hashHex).firstOrNull;
    final int now = nowMs();
    if (a == null || !a.open) throw const PeopleRefused('gone', 'That is not waiting any more.');
    if (!a.needsMyAnswer) throw const PeopleRefused('not-yours', 'That is not waiting for your answer.');
    if (yes && now < a.answerFromMs) {
      throw PeopleRefused('think-over', 'Take your time. You can answer yes from ${dateWords(a.answerFromMs)} onward. You can say no at any moment.');
    }
    final LedgerVote v = await LedgerVote.sign(context.device, target: fromHex(hashHex), answer: yes ? 'yes' : 'no', atMs: now);
    await _all(() async {
      context.votes.add(v);
      await _persist();
    });
  }

  /// The asker takes their own request back (nothing was changed by it).
  Future<void> withdraw(String hashHex) async {
    final PeopleOverview o = await overview();
    final PendingAsk? a = o.asks.where((PendingAsk x) => x.hashHex == hashHex).firstOrNull;
    if (a == null || !a.open || !a.mine) throw const PeopleRefused('not-yours', 'Only the person who asked can take it back.');
    final LedgerVote v = await LedgerVote.sign(context.device, target: fromHex(hashHex), answer: 'withdraw', atMs: nowMs());
    await _all(() async {
      context.votes.add(v);
      await _persist();
    });
  }
}

/// A short name for a person, never longer than the screens expect (kept here so tests and screens agree).
String shortName(String s) => cleanName(s, max: 24);
