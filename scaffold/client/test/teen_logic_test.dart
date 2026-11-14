// OLIVE BRANCH — the rules of the 13 to 17 shell and the 18 handover (lib/teen_logic.dart). UNVERIFIED until CI runs it.
// Every rule is a unit here: her own calendar, her free times, the ask and its seven days, the consent log, the
// privacy contract, the 30 days after take and go, staying in touch by choice on both sides, the 90-day heads-up.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/take_and_go_screen.dart' show auditTakeAndGoCopy;
import 'package:olive_client/teen_logic.dart';

final DateTime t0 = DateTime(2026, 11, 9, 9);

void main() {
  group('her calendar', () {
    test('she edits from 14 and only looks before it', () {
      expect(canEditOwnCalendar(13), isFalse);
      expect(canEditOwnCalendar(14), isTrue);
      expect(canEditOwnCalendar(17), isTrue);
    });

    test('a title is trimmed and cut to 60; nothing left means no event', () {
      expect(cleanEventTitle('   '), isNull);
      expect(cleanEventTitle('  Study group '), 'Study group');
      expect(cleanEventTitle('x' * 80)!.length, kEventTitleMax);
    });

    test('an event is hers alone until she picks who; only those she picked can see it', () {
      const TeenEvent mine = TeenEvent(id: 'a', year: 2026, month: 11, day: 12, title: 'Dentist');
      expect(mine.share.isPrivate, isTrue);
      expect(eventsSharedWith(<TeenEvent>[mine], 'mom'), isEmpty);
      final TeenEvent shared = TeenEvent(id: 'b', year: 2026, month: 11, day: 12, title: 'Lesson', share: const EventShare.with_(<String>{'dad'}));
      expect(eventsSharedWith(<TeenEvent>[mine, shared], 'dad').map((TeenEvent e) => e.id), <String>['b']);
      expect(eventsSharedWith(<TeenEvent>[mine, shared], 'mom'), isEmpty, reason: 'the other grown-up is not shown it');
    });

    test('events on a day, in the order she made them', () {
      final List<TeenEvent> all = <TeenEvent>[
        const TeenEvent(id: '1', year: 2026, month: 11, day: 9, title: 'A'),
        const TeenEvent(id: '2', year: 2026, month: 11, day: 10, title: 'B'),
        const TeenEvent(id: '3', year: 2026, month: 11, day: 9, title: 'C'),
      ];
      expect(eventsOn(all, 2026, 11, 9).map((TeenEvent e) => e.title), <String>['A', 'C']);
    });

    test('an event survives JSON and a damaged one is dropped, never fatal', () {
      final TeenEvent e = TeenEvent(id: 'x', year: 2026, month: 3, day: 4, title: 'Test', share: const EventShare.with_(<String>{'mom', 'dad'}));
      final TeenEvent? back = TeenEvent.fromJson(e.toJson());
      expect(back!.title, 'Test');
      expect(back.share.sees('mom') && back.share.sees('dad'), isTrue);
      expect(TeenEvent.fromJson(<String, Object?>{'id': 'x', 'y': 2026, 'm': 13, 'd': 1, 'title': 'bad month'}), isNull);
      expect(TeenEvent.fromJson('junk'), isNull);
    });
  });

  group('her free times', () {
    test('three parts of the day, school days and weekends, toggled one at a time', () {
      FreeTimes f = const FreeTimes();
      f = f.toggled(false, 'pm').toggled(true, 'eve');
      expect(f.schoolDays, <String>{'pm'});
      expect(f.weekends, <String>{'eve'});
      f = f.toggled(false, 'pm');
      expect(f.schoolDays, isEmpty);
    });

    test('what a grown-up sees is in her words and never says why she is busy', () {
      final FreeTimes f = const FreeTimes().toggled(false, 'am').toggled(false, 'pm').asPublished();
      expect(f.describe(), 'School days free before school, after school. Weekends nothing shown.');
      expect(f.describe().toLowerCase(), isNot(contains('busy')));
      expect(f.describe().toLowerCase(), isNot(contains('because')));
      expect(f.published, isTrue);
    });

    test('JSON keeps only the known parts of the day', () {
      final FreeTimes f = FreeTimes.fromJson(<String, Object?>{'wd': <Object?>['am', 'bogus'], 'we': <Object?>['eve'], 'published': true});
      expect(f.schoolDays, <String>{'am'});
      expect(f.published, isTrue);
      expect(FreeTimes.fromJson(7).published, isFalse);
    });
  });

  group('the ask', () {
    test('only three kinds exist; the journal, messages, where she is and what she hid can never be asked for', () {
      expect(ShareKind.values.map((ShareKind k) => k.name).toSet(), <String>{'freeTimes', 'calendar', 'pictures'});
      for (final String never in kNeverAskable) {
        expect(isAskable(never), isFalse, reason: never);
        expect(const AskLedger().canAsk('mom', never, t0, herAge: 17).reason, 'not_askable', reason: never);
        expect(const AskLedger().ask('a1', 'mom', never, t0, herAge: 17), isNull, reason: never);
      }
      for (final ShareKind k in ShareKind.values) {
        expect(isAskable(k.name), isTrue);
      }
    });

    test('a kind that does not exist at her age cannot be asked yet', () {
      expect(const AskLedger().canAsk('mom', 'freeTimes', t0, herAge: 14).reason, 'too_young');
      expect(const AskLedger().canAsk('mom', 'freeTimes', t0, herAge: 15).ok, isTrue);
      expect(const AskLedger().canAsk('mom', 'calendar', t0, herAge: 13).reason, 'too_young');
    });

    test('one open ask per grown-up and kind', () {
      final AskLedger l = const AskLedger().ask('a1', 'mom', 'calendar', t0, herAge: 15)!;
      expect(l.canAsk('mom', 'calendar', t0, herAge: 15).reason, 'pending');
      expect(l.canAsk('dad', 'calendar', t0, herAge: 15).ok, isTrue, reason: 'the other grown-up is a different ask');
      expect(l.canAsk('mom', 'pictures', t0, herAge: 15).ok, isTrue);
    });

    test('a no is final for seven days: the same ask is refused until the seventh day has passed', () {
      AskLedger l = const AskLedger().ask('a1', 'mom', 'calendar', t0, herAge: 15)!;
      l = l.answer('a1', AskAnswer.no, t0);
      final DateTime day6 = t0.add(const Duration(days: 6, hours: 23, minutes: 59));
      final DateTime day7 = t0.add(const Duration(days: kAskWaitDays));
      final AskCheck at6 = l.canAsk('mom', 'calendar', day6, herAge: 15);
      expect(at6.ok, isFalse);
      expect(at6.reason, 'waiting');
      expect(at6.waitUntil, day7);
      expect(l.ask('a2', 'mom', 'calendar', day6, herAge: 15), isNull);
      expect(l.canAsk('mom', 'calendar', day7, herAge: 15).ok, isTrue, reason: 'the seventh day opens it again');
      expect(l.ask('a2', 'mom', 'calendar', day7, herAge: 15), isNotNull);
    });

    test('a no to one grown-up or one thing does not close the others', () {
      AskLedger l = const AskLedger().ask('a1', 'mom', 'calendar', t0, herAge: 15)!;
      l = l.answer('a1', AskAnswer.no, t0);
      expect(l.canAsk('dad', 'calendar', t0, herAge: 15).ok, isTrue);
      expect(l.canAsk('mom', 'pictures', t0, herAge: 15).ok, isTrue);
    });

    test('a yes shares only with that grown-up, and she can stop; stopping is a no, so seven days run from then', () {
      AskLedger l = const AskLedger().ask('a1', 'mom', 'pictures', t0, herAge: 15)!;
      l = l.answer('a1', AskAnswer.yes, t0);
      expect(l.sharingWith(ShareKind.pictures), <String>{'mom'});
      expect(l.sharingWith(ShareKind.calendar), isEmpty);
      expect(l.canAsk('mom', 'pictures', t0, herAge: 15).reason, 'already_sharing');
      final DateTime stop = t0.add(const Duration(days: 20));
      l = l.stop('a1', stop);
      expect(l.sharingWith(ShareKind.pictures), isEmpty);
      expect(l.canAsk('mom', 'pictures', stop.add(const Duration(days: 3)), herAge: 15).reason, 'waiting');
      expect(l.canAsk('mom', 'pictures', stop.add(const Duration(days: 7)), herAge: 15).ok, isTrue);
    });

    test('an answer is only ever added: an answered ask cannot be re-answered and nothing is removed', () {
      AskLedger l = const AskLedger().ask('a1', 'mom', 'calendar', t0, herAge: 15)!;
      l = l.answer('a1', AskAnswer.no, t0);
      final AskLedger again = l.answer('a1', AskAnswer.yes, t0.add(const Duration(days: 1)));
      expect(again.asks.single.answer, AskAnswer.no);
      expect(again.asks.length, 1);
    });

    test('the consent log is derived from the asks: every ask and every answer, newest first', () {
      AskLedger l = const AskLedger().ask('a1', 'mom', 'calendar', t0, herAge: 15)!;
      l = l.answer('a1', AskAnswer.yes, t0.add(const Duration(hours: 1)));
      l = l.stop('a1', t0.add(const Duration(days: 2)));
      final List<ConsentLine> log = consentLog(l);
      expect(log.map((ConsentLine x) => x.event), <String>['stopped', 'yes', 'asked']);
      expect(consentLog(const AskLedger()), isEmpty);
    });

    test('the ledger survives JSON and drops a damaged entry', () {
      AskLedger l = const AskLedger().ask('a1', 'mom', 'calendar', t0, herAge: 15)!;
      l = l.answer('a1', AskAnswer.no, t0);
      final AskLedger back = AskLedger.fromJson(l.toJson());
      expect(back.asks.single.answer, AskAnswer.no);
      expect(back.asks.single.answeredAt, t0);
      expect(AskLedger.fromJson(<String, Object?>{'asks': <Object?>[<String, Object?>{'id': 1}, 'x']}).asks, isEmpty);
    });
  });

  group('the privacy contract', () {
    List<ContractRow> rows({int age = 15, List<String> who = const <String>['Mom', 'Dad']}) => privacyContract(who, age: age);
    ContractRow row(List<ContractRow> r, String start) => r.firstWhere((ContractRow x) => x.title.startsWith(start));

    test('the journal, where she is and what she hides are NO for every grown-up, at every age', () {
      for (final int age in <int>[13, 15, 17, 18]) {
        for (final String t in <String>['Your journal', 'Where you are', 'Things you hide']) {
          expect(row(rows(age: age), t).values.every((Seen s) => s == Seen.no), isTrue, reason: '$t at $age');
        }
      }
    });

    test('messages go to one grown-up only: she sees Mom, Dad does not', () {
      final List<ContractRow> r = rows();
      expect(row(r, 'Messages you send to Mom').values, <Seen>[Seen.see, Seen.no]);
      expect(row(r, 'Messages you send to Dad').values, <Seen>[Seen.no, Seen.see]);
    });

    test('free times are what she publishes from 15, and nothing before', () {
      expect(row(rows(age: 14), 'Your free times').values, <Seen>[Seen.no, Seen.no]);
      expect(row(rows(age: 15), 'Your free times').values, <Seen>[Seen.see, Seen.see]);
    });

    test('events and pictures are her choice, each one', () {
      expect(row(rows(), 'Events you add').values, <Seen>[Seen.choose, Seen.choose]);
      expect(row(rows(), 'Pictures you show').values, <Seen>[Seen.choose, Seen.choose]);
    });

    test('it is symmetrical, plain, and carries no number at all', () {
      for (final ContractRow r in rows()) {
        expect('${r.title} ${r.sub}', isNot(matches(RegExp(r'\d'))), reason: r.title);
      }
      expect(privacyReverse(2), contains('The same rules, the other way'));
      expect(privacyReverse(2), contains('their messages to each other'));
      expect(privacyReverse(1), isNot(contains('to each other')));
    });

    test('one grown-up, or none known, still gives a whole table', () {
      expect(privacyContract(<String>['Your grown-up'], age: 14).every((ContractRow r) => r.values.length == 1), isTrue);
    });
  });

  group('the 18 handover', () {
    test('four equal paths; none is a default and none is marked as better', () {
      expect(HandoverChoice.values.length, 4);
      const HandoverRecord none = HandoverRecord();
      expect(none.choice, isNull);
      expect(none.chosen, isFalse);
      for (final HandoverChoice c in HandoverChoice.values) {
        final String words = '${c.title} ${c.sub}'.toLowerCase();
        expect(words, isNot(contains('recommend')));
        expect(words, isNot(contains('best')));
        expect(auditTakeAndGoCopy('${c.title}. ${c.sub}').ok, isTrue, reason: '${c.name}: ${auditTakeAndGoCopy('${c.title}. ${c.sub}').found}');
      }
    });

    test('take and go keeps the app copy for 30 days; keep and both keep it for good', () {
      final HandoverRecord take = const HandoverRecord().chose(HandoverChoice.take, t0);
      expect(take.keepUntil, t0.add(const Duration(days: kTakeAndGoKeepDays)));
      expect(const HandoverRecord().chose(HandoverChoice.keep, t0).keepUntil, isNull);
      expect(const HandoverRecord().chose(HandoverChoice.both, t0).keepUntil, isNull);
      expect(const HandoverRecord().chose(HandoverChoice.later, t0).keepUntil, isNull);
    });

    test('she can change her mind inside the 30 days, and the others are never closed', () {
      final HandoverRecord take = const HandoverRecord().chose(HandoverChoice.take, t0);
      expect(take.canChange(t0.add(const Duration(days: 29))), isTrue);
      expect(take.canChange(t0.add(const Duration(days: 30))), isFalse);
      expect(const HandoverRecord().chose(HandoverChoice.keep, t0).canChange(t0.add(const Duration(days: 400))), isTrue);
    });

    test('the app copy is removed only after take and go, with her own copy saved and checked, and 30 days on', () {
      final HandoverRecord take = const HandoverRecord().chose(HandoverChoice.take, t0);
      final DateTime late = t0.add(const Duration(days: 31));
      expect(take.purgeDue(late), isFalse, reason: 'no saved copy: nothing is ever removed');
      final HandoverRecord copied = take.copyMade(t0.add(const Duration(minutes: 5)), '/x/my-copy.json');
      expect(copied.purgeDue(t0.add(const Duration(days: 29))), isFalse);
      expect(copied.purgeDue(t0.add(const Duration(days: 30))), isTrue);
      for (final HandoverChoice c in <HandoverChoice>[HandoverChoice.keep, HandoverChoice.both, HandoverChoice.later]) {
        final HandoverRecord r = const HandoverRecord().chose(c, t0).copyMade(t0, '/x');
        expect(r.purgeDue(t0.add(const Duration(days: 999))), isFalse, reason: c.name);
      }
    });

    test('switching to a path that makes no copy forgets the copy made for the other one', () {
      final HandoverRecord both = const HandoverRecord().chose(HandoverChoice.both, t0).copyMade(t0, '/x');
      expect(both.chose(HandoverChoice.keep, t0).copyMadeAt, isNull);
      expect(both.chose(HandoverChoice.take, t0).copyMadeAt, t0, reason: 'a path that makes a copy keeps the one she has');
    });

    test('the record survives JSON', () {
      final HandoverRecord r = const HandoverRecord().chose(HandoverChoice.both, t0).copyMade(t0, '/x/a.json');
      final HandoverRecord b = HandoverRecord.fromJson(r.toJson());
      expect(b.choice, HandoverChoice.both);
      expect(b.copyPath, '/x/a.json');
      expect(HandoverRecord.fromJson('junk').chosen, isFalse);
    });

    test('the heads-up is the 90 days before the 18th birthday, and not on the day or any other birthday', () {
      expect(handoverHeadsUp(turnsYears: 18, sleepsUntil: 90), isTrue);
      expect(handoverHeadsUp(turnsYears: 18, sleepsUntil: 91), isFalse);
      expect(handoverHeadsUp(turnsYears: 18, sleepsUntil: 1), isTrue);
      expect(handoverHeadsUp(turnsYears: 18, sleepsUntil: 0), isFalse);
      expect(handoverHeadsUp(turnsYears: 17, sleepsUntil: 30), isFalse);
      expect(atHandover(17), isFalse);
      expect(atHandover(18), isTrue);
      expect(atHandover(19), isTrue);
    });

    test('a grown-up note is trimmed and cut', () {
      expect(cleanHandoverNote('  '), isNull);
      expect(cleanHandoverNote(' I am proud. ')!, 'I am proud.');
      expect(cleanHandoverNote('y' * 700)!.length, kHandoverNoteMax);
    });
  });

  group('staying in touch needs both sides, channel by channel', () {
    test('only what she offers AND they ask for is live', () {
      StayInTouch t = const StayInTouch().offer(Channel.messages, true).offer(Channel.calls, true);
      t = t.want('mom', <Channel>{Channel.messages, Channel.calendar});
      expect(t.liveWith('mom'), <Channel>{Channel.messages});
      expect(t.stateWith('mom'), TouchState.ready);
    });

    test('she offering with nobody asking is waiting for them; them asking with nothing offered is waiting for her', () {
      expect(const StayInTouch().offer(Channel.calls, true).stateWith('dad'), TouchState.waitingForThem);
      expect(const StayInTouch().want('dad', <Channel>{Channel.calls}).stateWith('dad'), TouchState.waitingForHer);
      expect(const StayInTouch().stateWith('dad'), TouchState.notAsked);
    });

    test('they ask for what she did not offer: nothing is live', () {
      final StayInTouch t = const StayInTouch().offer(Channel.messages, true).want('mom', <Channel>{Channel.calendar});
      expect(t.liveWith('mom'), isEmpty);
      expect(t.stateWith('mom'), TouchState.waitingForHer);
    });

    test('either side ends it with one tap, and a new ask begins again', () {
      StayInTouch t = const StayInTouch().offer(Channel.messages, true).want('mom', <Channel>{Channel.messages});
      t = t.end('mom');
      expect(t.liveWith('mom'), isEmpty);
      expect(t.stateWith('mom'), TouchState.ended);
      t = t.want('mom', <Channel>{Channel.messages});
      expect(t.stateWith('mom'), TouchState.ready, reason: 'a fresh ask from them is a fresh ask');
    });

    test('one grown-up ending it does not touch the other', () {
      StayInTouch t = const StayInTouch().offer(Channel.messages, true).want('mom', <Channel>{Channel.messages}).want('dad', <Channel>{Channel.messages});
      t = t.end('mom');
      expect(t.stateWith('dad'), TouchState.ready);
    });

    test('it survives JSON', () {
      final StayInTouch t = const StayInTouch().offer(Channel.calls, true).want('mom', <Channel>{Channel.calls}).end('dad');
      final StayInTouch b = StayInTouch.fromJson(t.toJson());
      expect(b.offered, <Channel>{Channel.calls});
      expect(b.liveWith('mom'), <Channel>{Channel.calls});
      expect(b.ended, <String>{'dad'});
    });
  });

  group('nothing in the rules is a count, a score, a streak or a place (P1 to P11)', () {
    test('no stored shape carries such a key', () {
      final List<Map<String, Object?>> shapes = <Map<String, Object?>>[
        const TeenEvent(id: 'a', year: 2026, month: 1, day: 1, title: 't').toJson(),
        const FreeTimes().toJson(),
        const AskLedger().ask('a', 'mom', 'calendar', t0, herAge: 15)!.toJson(),
        const HandoverRecord().chose(HandoverChoice.take, t0).toJson(),
        const StayInTouch().toJson(),
      ];
      final String all = shapes.toString().toLowerCase();
      for (final String bad in <String>['score', 'streak', 'count', 'total', 'rank', 'lat', 'lng', 'latitude', 'longitude', 'location', 'age:']) {
        expect(all, isNot(contains(bad)), reason: bad);
      }
    });
  });
}
