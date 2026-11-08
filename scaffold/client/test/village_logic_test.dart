// OLIVE BRANCH — suite D (Village) pure logic: every bound, every refusal, the
// tolerant readers, the printable page, and the age gate. Every deny path is a
// real assertion.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/picture_library.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/village_logic.dart';

import 'village_support.dart';

void refused(void Function() f, String reason) {
  try {
    f();
  } on RvRefused catch (e) {
    expect(e.reason, reason);
    return;
  }
  fail('expected RvRefused($reason)');
}

const FamilyStructure twoHomes = FamilyStructure(
  homes: <Home>[Home(id: 'h1', name: 'Mom\'s', childSleeps: true), Home(id: 'h2', name: 'Dad\'s', childSleeps: true)],
  people: <Person>[
    Person(id: 'p1', label: 'Mom', role: 'parent', homeId: 'h1', contact: <String>['live_call']),
    Person(id: 'p2', label: 'Dad', role: 'parent', homeId: 'h2', contact: <String>['live_call']),
  ],
);

ChildView viewOf(FamilyStructure s, String band, {Map<String, bool>? suites}) =>
    deriveChildView(s, band, suites, null, today: day);

void main() {
  group('phone numbers are text a guardian wrote', () {
    test('digits, spaces and + - ( ) . are kept, tidied', () {
      expect(cleanPhone('  555   0142 '), '555 0142');
      expect(cleanPhone('+44 (0) 20 7946 0958'), '+44 (0) 20 7946 0958');
      expect(cleanPhone('555-0142'), '555-0142');
    });

    test('letters, too few or too many digits, empty and non-strings are refused', () {
      for (final Object? bad in <Object?>['call mom', '555 01', '1234567890123456', '', '   ', null, 5, '555 0142 ext 9', '555;0142']) {
        refused(() => cleanPhone(bad), 'bad_number');
      }
    });

    test('a number is never turned into anything dialable: no tel: or link in the stored shape', () {
      final String json = jsonEncode(sampleGrand().toJson());
      expect(json.toLowerCase(), isNot(contains('tel:')));
      expect(json.toLowerCase(), isNot(contains('http')));
    });
  });

  group('cleanLines', () {
    test('blank lines drop; text is single-spaced; order is kept', () {
      expect(cleanLines(<String>['  a   b ', '', '   ', 'c'], maxLines: 4), <String>['a b', 'c']);
    });

    test('too many lines, a too-long line, an address and a non-string are all refused, never cut', () {
      refused(() => cleanLines(List<String>.filled(5, 'x'), maxLines: 4), 'too_many_lines');
      refused(() => cleanLines(<String>['x' * (maxPassLineChars + 1)], maxLines: 4), 'too_long');
      refused(() => cleanLines(<String>['Meet at 12 Oak Street'], maxLines: 4), 'looks_like_location');
      refused(() => cleanLines(<Object?>['ok', 5], maxLines: 4), 'bad_text');
      refused(() => cleanLines('not a list', maxLines: 4), 'bad_text');
    });

    test('exactly the maximum number of full-length lines is allowed', () {
      expect(cleanLines(List<String>.filled(maxPassLines, 'x' * maxPassLineChars), maxLines: maxPassLines).length, maxPassLines);
    });
  });

  group('grandparent corner', () {
    test('a good corner round-trips and keeps its order', () {
      final GrandCorner g = sampleGrand();
      final GrandCorner? back = GrandCorner.tryFromJson(jsonDecode(jsonEncode(g.toJson())));
      expect(back!.name, 'Nana');
      expect(back.cards.map((GrandCard c) => c.id), <String>['g1', 'g2']);
      expect(back.phone!.number, '555 0199');
      expect(back.isEmpty, isFalse);
      expect(const GrandCorner().isEmpty, isTrue);
    });

    test('at most four huge buttons', () {
      final List<GrandCard> five = <GrandCard>[
        for (int i = 0; i < 5; i++) GrandCard(id: 'g$i', picture: 'book', title: 'T$i'),
      ];
      refused(() => makeGrandCorner(cards: five), 'too_many_cards');
      expect(makeGrandCorner(cards: five.take(4).toList()).cards.length, 4);
    });

    test('a card needs a library picture from the allowed groups; a worry or symbol picture is refused', () {
      for (final String bad in <String>['worry-dark', 'sym-i', 'sunny', 'nope']) {
        refused(() => makeGrandCorner(cards: <GrandCard>[GrandCard(id: 'a', picture: bad, title: 'T')]), 'bad_card');
      }
    });

    test('duplicate ids, empty titles, address-like text and an over-long card text are refused', () {
      refused(() => makeGrandCorner(cards: const <GrandCard>[
            GrandCard(id: 'a', picture: 'book', title: 'T'), GrandCard(id: 'a', picture: 'song', title: 'U'),
          ]), 'duplicate_id');
      refused(() => makeGrandCorner(cards: const <GrandCard>[GrandCard(id: 'a', picture: 'book', title: '')]), 'bad_card');
      refused(() => makeGrandCorner(cards: const <GrandCard>[GrandCard(id: 'a', picture: 'book', title: 'T', text: 'Come to 14 Elm Road')]), 'bad_card');
      refused(() => makeGrandCorner(cards: <GrandCard>[GrandCard(id: 'a', picture: 'book', title: 'T', text: 'x' * (maxGrandTextChars + 1))]), 'bad_card');
    });

    test('a phone line needs a real number', () {
      refused(() => makeGrandCorner(phone: const PhoneLine(who: 'Mom', number: 'call me')), 'bad_number');
      refused(() => makeGrandCorner(phone: const PhoneLine(who: '', number: '555 0199')), 'empty_text');
    });

    test('a damaged document yields what is salvageable, never an exception', () {
      expect(GrandCorner.tryFromJson('x'), isNull);
      expect(GrandCorner.tryFromJson(<String, Object?>{'name': 5}), isNull);
      final GrandCorner? g = GrandCorner.tryFromJson(<String, Object?>{
        'name': 'Nana',
        'cards': <Object?>[
          <String, Object?>{'id': 'a', 'picture': 'book', 'title': 'Ok', 'text': ''},
          <String, Object?>{'id': 'a', 'picture': 'book', 'title': 'Dup', 'text': ''},
          <String, Object?>{'id': 'b', 'picture': 'nope', 'title': 'Bad', 'text': ''},
          5,
        ],
        'phone': <String, Object?>{'who': 'Mom', 'number': 'xx'},
      });
      expect(g!.cards.single.title, 'Ok');
      expect(g.phone, isNull);
    });
  });

  group('welcome story', () {
    test('a new story is HELD: nothing releases it', () {
      final WelcomeStory s = sampleStory();
      expect(s.released, isFalse);
      expect(s.releasedOn, isNull);
      expect(s.copyWith(releasedOn: day).released, isTrue);
      expect(s.copyWith(releasedOn: day).copyWith(hold: true).released, isFalse);
    });

    test('1 to 6 pages, each a library picture and short text', () {
      refused(() => makeStory(id: 'a', title: 'T', pages: const <StoryPage>[]), 'no_pages');
      final List<StoryPage> seven = <StoryPage>[for (int i = 0; i < 7; i++) const StoryPage(picture: 'door', text: 'x')];
      refused(() => makeStory(id: 'a', title: 'T', pages: seven), 'too_many_pages');
      expect(makeStory(id: 'a', title: 'T', pages: seven.take(6).toList()).pages.length, 6);
      refused(() => makeStory(id: 'a', title: 'T', pages: const <StoryPage>[StoryPage(picture: 'worry-dark', text: 'x')]), 'bad_page');
      refused(() => makeStory(id: 'a', title: 'T', pages: <StoryPage>[StoryPage(picture: 'door', text: 'x' * (maxWelcomePageChars + 1))]), 'bad_page');
      refused(() => makeStory(id: 'a b', title: 'T', pages: const <StoryPage>[StoryPage(picture: 'door', text: 'x')]), 'bad_id');
      refused(() => makeStory(id: 'a', title: ' ', pages: const <StoryPage>[StoryPage(picture: 'door', text: 'x')]), 'empty_text');
    });

    test('the reader refuses a story with an impossible release date or no pages', () {
      final Map<String, Object?> good = sampleStory().toJson();
      expect(WelcomeStory.tryFromJson(good), isNotNull);
      expect(WelcomeStory.tryFromJson(<String, Object?>{...good, 'releasedOn': '2026-13-40'}), isNull);
      expect(WelcomeStory.tryFromJson(<String, Object?>{...good, 'pages': <Object?>[]}), isNull);
      expect(WelcomeStory.tryFromJson(<String, Object?>{...good, 'id': 'a b'}), isNull);
      expect(WelcomeStory.tryFromJson(<String, Object?>{...good, 'releasedOn': day})!.released, isTrue);
    });

    test('NOTHING is generated: no library text or code path writes words about a person, a partner or a role', () {
      // The only text in a story is what a guardian typed; the logic has no template.
      final String json = jsonEncode(sampleStory().toJson());
      for (final String banned in <String>['step', 'partner', 'new mum', 'new dad', 'divorce', 'stepmother', 'boyfriend', 'girlfriend']) {
        expect(json.toLowerCase(), isNot(contains(banned)));
      }
      expect(sampleStory().pages.map((StoryPage p) => p.text), <String>['We open the door.', 'We eat together.']);
    });
  });

  group('sibling shelf', () {
    SiblingShelf base() => withSiblings(const SiblingShelf(), sampleSiblings());

    test('a picture is left for a known sibling and taken down again', () {
      SiblingShelf s = leaveNote(base(), const ShelfNote(id: 'n1', toId: 'b1', picture: 'teddy'));
      expect(s.notesFor('b1').single.picture, 'teddy');
      expect(s.notesFor('b2'), isEmpty);
      s = takeDownNote(s, 'n1');
      expect(s.notes, isEmpty);
      expect(takeDownNote(s, 'nope').notes, isEmpty);
    });

    test('an unknown sibling, a picture outside the kit and a repeated id are refused', () {
      refused(() => leaveNote(base(), const ShelfNote(id: 'n1', toId: 'zz', picture: 'teddy')), 'unknown_sibling');
      refused(() => leaveNote(base(), const ShelfNote(id: 'n1', toId: 'b1', picture: 'worry-dark')), 'bad_picture');
      refused(() => leaveNote(base(), const ShelfNote(id: 'n1', toId: 'b1', picture: 'bath')), 'bad_picture');
      final SiblingShelf s = leaveNote(base(), const ShelfNote(id: 'n1', toId: 'b1', picture: 'teddy'));
      refused(() => leaveNote(s, const ShelfNote(id: 'n1', toId: 'b2', picture: 'owl')), 'duplicate_id');
    });

    test('a full shelf never says full: the oldest picture drops off', () {
      SiblingShelf s = base();
      for (int i = 0; i < maxNotesPerSibling + 2; i++) {
        s = leaveNote(s, ShelfNote(id: 'n$i', toId: 'b1', picture: 'teddy'));
      }
      expect(s.notesFor('b1').length, maxNotesPerSibling);
      expect(s.notesFor('b1').first.id, 'n2');
      expect(s.notesFor('b1').last.id, 'n${maxNotesPerSibling + 1}');
    });

    test('at most four siblings, no duplicates, names and pictures checked', () {
      refused(() => withSiblings(const SiblingShelf(), <SiblingSlot>[for (int i = 0; i < 5; i++) SiblingSlot(id: 'b$i', name: 'N$i', picture: 'sibling')]), 'too_many_siblings');
      refused(() => withSiblings(const SiblingShelf(), const <SiblingSlot>[SiblingSlot(id: 'b', name: 'A', picture: 'sibling'), SiblingSlot(id: 'b', name: 'B', picture: 'sibling')]), 'duplicate_id');
      refused(() => withSiblings(const SiblingShelf(), const <SiblingSlot>[SiblingSlot(id: 'b', name: 'A', picture: 'bath')]), 'bad_sibling');
      refused(() => withSiblings(const SiblingShelf(), const <SiblingSlot>[SiblingSlot(id: 'b', name: '', picture: 'sibling')]), 'bad_sibling');
    });

    test('removing a sibling takes their pictures with them', () {
      SiblingShelf s = leaveNote(base(), const ShelfNote(id: 'n1', toId: 'b1', picture: 'teddy'));
      s = leaveNote(s, const ShelfNote(id: 'n2', toId: 'b2', picture: 'owl'));
      final SiblingShelf next = withSiblings(s, <SiblingSlot>[sampleSiblings().last]);
      expect(next.siblings.map((SiblingSlot x) => x.id), <String>['b2']);
      expect(next.notes.map((ShelfNote n) => n.id), <String>['n2']);
      expect(clearNotes(s).notes, isEmpty);
      expect(clearNotes(s).siblings.length, 2);
    });

    test('the stored shape has no author, no time, no read mark and no count (P2)', () {
      final Map<String, Object?> j = leaveNote(base(), const ShelfNote(id: 'n1', toId: 'b1', picture: 'teddy')).toJson();
      final String text = jsonEncode(j);
      for (final String banned in <String>['from', 'author', 'time', 'seen', 'read', 'count', 'total', 'score', 'streak']) {
        expect(text, isNot(contains('"$banned')), reason: banned);
      }
      expect(((j['notes']! as List).single as Map<String, Object?>).keys.toSet(), <String>{'id', 'toId', 'picture'});
    });

    test('the reader drops orphan notes, repeated ids and anything over a sibling\'s limit', () {
      final SiblingShelf s = SiblingShelf.fromJson(<String, Object?>{
        'siblings': <Object?>[
          <String, Object?>{'id': 'b1', 'name': 'Leo', 'picture': 'sibling'},
          <String, Object?>{'id': 'b1', 'name': 'Dup', 'picture': 'sibling'},
        ],
        'notes': <Object?>[
          for (int i = 0; i < 9; i++) <String, Object?>{'id': 'n$i', 'toId': 'b1', 'picture': 'teddy'},
          <String, Object?>{'id': 'o', 'toId': 'gone', 'picture': 'teddy'},
          <String, Object?>{'id': 'n1', 'toId': 'b1', 'picture': 'owl'},
        ],
      });
      expect(s.siblings.length, 1);
      expect(s.notes.length, maxNotesPerSibling);
      expect(SiblingShelf.fromJson(null).isEmpty, isTrue);
    });
  });

  group('sitter pass', () {
    test('the page holds exactly what a guardian wrote, in a fixed reading order', () {
      final SitterPass p = sampleSitter();
      expect(sitterSections(p).map((PassSection s) => s.heading), <String>['Allergies', 'Routine', 'Good to know', 'Who to reach']);
      expect(sitterSections(p).first.lines, <String>['Cashews (written by Mom)']);
      expect(sitterSections(p).last.lines.single, 'Mom (her mum): 555 0142, best after 9');
    });

    test('empty sections are left out, and an empty pass says it is empty', () {
      final SitterPass p = makeSitterPass(allergies: const <String>['Peanuts']);
      expect(sitterSections(p).map((PassSection s) => s.heading), <String>['Allergies']);
      expect(makeSitterPass().isEmpty, isTrue);
      expect(sitterSections(makeSitterPass()), isEmpty);
    });

    test('the plain text is the same words as the screen and no more', () {
      final SitterPass p = sampleSitter();
      final String t = passText(p.title, <String>['For ${p.forWho}', p.when], sitterSections(p));
      expect(t, contains('Friday evening'));
      expect(t, contains('For Aunt Mia'));
      expect(t, contains('- Cashews (written by Mom)'));
      expect(t, contains('- Mom (her mum): 555 0142, best after 9'));
      expect(t.split('\n').where((String l) => l.startsWith('- ')).length, 6);
    });

    test('bounds: 8 lines per list, 80 characters per line, 5 contacts', () {
      refused(() => makeSitterPass(routine: List<String>.filled(maxPassLines + 1, 'x')), 'too_many_lines');
      refused(() => makeSitterPass(allergies: <String>['x' * (maxPassLineChars + 1)]), 'too_long');
      refused(() => makeSitterPass(contacts: <PassContact>[for (int i = 0; i < 6; i++) PassContact(id: 'c$i', name: 'N', number: '555 0142')]), 'too_many_contacts');
    });

    test('a contact needs a name and a real number; ids must be unique', () {
      refused(() => makeSitterPass(contacts: const <PassContact>[PassContact(id: 'c', name: 'Mom', number: 'soon')]), 'bad_contact');
      refused(() => makeSitterPass(contacts: const <PassContact>[PassContact(id: 'c', name: '', number: '555 0142')]), 'bad_contact');
      refused(() => makeSitterPass(contacts: const <PassContact>[PassContact(id: 'c', name: 'A', number: '555 0142'), PassContact(id: 'c', name: 'B', number: '555 0143')]), 'duplicate_id');
      refused(() => makeSitterPass(contacts: const <PassContact>[PassContact(id: 'c d', name: 'A', number: '555 0142')]), 'bad_id');
    });

    test('an address in any line is refused (P3)', () {
      refused(() => makeSitterPass(notes: const <String>['Back by 10, we are at 44 Maple Avenue']), 'looks_like_location');
    });

    test('there is no link, expiry, opened-by or sent-to field: it cannot leave the device by itself', () {
      final Set<String> keys = sampleSitter().toJson().keys.toSet();
      expect(keys, <String>{'title', 'forWho', 'when', 'routine', 'allergies', 'notes', 'contacts', 'writtenOn'});
      expect(SitterPass.tryFromJson(sampleSitter().toJson())!.contacts.single.name, 'Mom');
    });

    test('a damaged pass does not load rather than loading half-trusted', () {
      final Map<String, Object?> j = sampleSitter().toJson();
      expect(SitterPass.tryFromJson(<String, Object?>{...j, 'routine': 'x'}), isNull);
      expect(SitterPass.tryFromJson(<String, Object?>{...j, 'writtenOn': 'yesterday'}), isNull);
      expect(SitterPass.tryFromJson(<String, Object?>{...j, 'allergies': List<String>.filled(20, 'x')}), isNull);
      expect(SitterPass.tryFromJson(null), isNull);
    });
  });

  group('school summary', () {
    test('the page shows what a guardian wrote, in order', () {
      expect(schoolSections(sampleSchool()).map((PassSection s) => s.heading), <String>['What helps', 'Allergies', 'Who collects her', 'Who to reach']);
    });

    test('a school NAME only: an address or coordinates are refused (P3), and no contact with a school exists', () {
      refused(() => makeSchoolBridge(school: '12 Oak Street'), 'looks_like_location');
      refused(() => makeSchoolBridge(school: '51.5072, -0.1276'), 'looks_like_location');
      expect(sampleSchool().toJson().keys.toSet(), <String>{'school', 'className', 'helps', 'allergies', 'pickup', 'notes', 'contacts', 'writtenOn'});
    });

    test('bounds: pickup and notes 4 lines each, contacts 4', () {
      refused(() => makeSchoolBridge(pickup: List<String>.filled(5, 'x')), 'too_many_lines');
      refused(() => makeSchoolBridge(notes: List<String>.filled(5, 'x')), 'too_many_lines');
      refused(() => makeSchoolBridge(contacts: <PassContact>[for (int i = 0; i < 5; i++) PassContact(id: 'c$i', name: 'N', number: '555 0142')]), 'too_many_contacts');
      refused(() => makeSchoolBridge(school: 'x' * (maxSchoolNameChars + 1)), 'too_long');
    });

    test('round-trips, and a damaged one does not load', () {
      expect(SchoolBridge.tryFromJson(jsonDecode(jsonEncode(sampleSchool().toJson())))!.school, 'Oak Primary');
      expect(SchoolBridge.tryFromJson(<String, Object?>{...sampleSchool().toJson(), 'pickup': List<String>.filled(9, 'x')}), isNull);
      expect(makeSchoolBridge().isEmpty, isTrue);
    });
  });

  group('the village document', () {
    test('everything round-trips; every field falls back on its own when damaged', () {
      final VillageDoc d = VillageDoc(
          suiteOn: false, grand: sampleGrand(), stories: <WelcomeStory>[sampleStory()],
          shelf: withSiblings(const SiblingShelf(), sampleSiblings()), faces: const <String, String>{'p1': 'grandparent'});
      final VillageDoc b = VillageDoc.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(b.suiteOn, isFalse);
      expect(b.grand!.cards.length, 2);
      expect(b.stories.single.id, 's1');
      expect(b.shelf.siblings.length, 2);
      expect(b.faces, <String, String>{'p1': 'grandparent'});
      final VillageDoc junk = VillageDoc.fromJson(<String, Object?>{'suiteOn': 'x', 'grand': 3, 'stories': 'x', 'shelf': 4, 'faces': 'y'});
      expect(junk.suiteOn, isTrue);
      expect(junk.grand, isNull);
      expect(junk.stories, isEmpty);
      expect(junk.faces, isEmpty);
      expect(VillageDoc.fromJson(null).suiteOn, isTrue);
    });

    test('faces keep only person-group pictures and at most 24', () {
      final VillageDoc d = VillageDoc.fromJson(<String, Object?>{
        'faces': <String, Object?>{
          'a': 'grandparent', 'b': 'bath', 'c d': 'friend', 'e': 5,
          for (int i = 0; i < 30; i++) 'x$i': 'friend',
        }
      });
      expect(d.faces.containsKey('b'), isFalse);
      expect(d.faces.containsKey('c d'), isFalse);
      expect(d.faces.length, maxFaces);
    });

    test('at most three stories, none repeated', () {
      final VillageDoc d = VillageDoc.fromJson(<String, Object?>{
        'stories': <Object?>[for (int i = 0; i < 5; i++) sampleStory(id: 's$i').toJson(), sampleStory(id: 's0').toJson()],
      });
      expect(d.stories.length, maxWelcomeStories);
    });

    test('the passes document keeps both passes and survives junk', () {
      final PassesDoc d = PassesDoc(sitter: sampleSitter(), school: sampleSchool());
      final PassesDoc b = PassesDoc.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(b.sitter!.title, 'Friday evening');
      expect(b.school!.school, 'Oak Primary');
      expect(PassesDoc.fromJson('x').sitter, isNull);
      expect(d.copyWith(clearSitter: true).sitter, isNull);
      expect(d.copyWith(clearSchool: true).school, isNull);
    });

    test('the largest legal documents fit under the catalogue ceilings', () {
      final VillageDoc full = VillageDoc(
        grand: makeGrandCorner(name: 'N' * maxNameChars, cards: <GrandCard>[
          for (int i = 0; i < maxGrandCards; i++) GrandCard(id: 'g${'x' * 60}$i', picture: 'book', title: 'T' * maxNameChars, text: 'x' * maxGrandTextChars),
        ], phone: PhoneLine(who: 'W' * maxNameChars, number: '+44 (0) 20 7946 0958', note: 'n' * maxLineChars)),
        stories: <WelcomeStory>[
          for (int i = 0; i < maxWelcomeStories; i++)
            makeStory(id: 's${'x' * 60}$i', title: 'T' * maxNameChars, pages: <StoryPage>[
              for (int j = 0; j < maxWelcomePages; j++) StoryPage(picture: 'door', text: 'x' * maxWelcomePageChars),
            ]),
        ],
        shelf: SiblingShelf(siblings: <SiblingSlot>[
          for (int i = 0; i < maxSiblings; i++) SiblingSlot(id: 'b${'x' * 60}$i', name: 'N' * maxNameChars, picture: 'sibling'),
        ], notes: <ShelfNote>[
          for (int i = 0; i < maxSiblings; i++)
            for (int j = 0; j < maxNotesPerSibling; j++) ShelfNote(id: 'n${'x' * 55}${i}_$j', toId: 'b${'x' * 60}$i', picture: 'teddy'),
        ]),
        faces: <String, String>{for (int i = 0; i < maxFaces; i++) 'p${'x' * 60}$i': 'grandparent'},
      );
      expect(VillageDoc.fromJson(full.toJson()).stories.length, maxWelcomeStories, reason: 'the maximal doc is itself legal');
      expect(jsonBytes(full.toJson()), lessThan(128 * 1024));

      final PassesDoc passes = PassesDoc(
        sitter: makeSitterPass(
            title: 'T' * maxTitleChars, forWho: 'F' * maxTitleChars, when: 'W' * maxTitleChars,
            routine: List<String>.filled(maxPassLines, 'r' * maxPassLineChars),
            allergies: List<String>.filled(maxPassLines, 'a' * maxPassLineChars),
            notes: List<String>.filled(maxPassLines, 'n' * maxPassLineChars),
            contacts: <PassContact>[for (int i = 0; i < maxPassContacts; i++) PassContact(id: 'c$i', name: 'N' * maxTitleChars, relation: 'R' * maxTitleChars, number: '555 0142', bestTimes: 'B' * maxTitleChars)]),
        school: makeSchoolBridge(
            school: 'S' * maxSchoolNameChars, className: 'C' * maxTitleChars,
            helps: List<String>.filled(maxPassLines, 'h' * maxPassLineChars), allergies: List<String>.filled(maxPassLines, 'a' * maxPassLineChars),
            pickup: List<String>.filled(4, 'p' * maxPassLineChars), notes: List<String>.filled(4, 'n' * maxPassLineChars),
            contacts: <PassContact>[for (int i = 0; i < maxSchoolContacts; i++) PassContact(id: 'c$i', name: 'N' * maxTitleChars, relation: 'R' * maxTitleChars, number: '555 0142', bestTimes: 'B' * maxTitleChars)]),
      );
      expect(jsonBytes(passes.toJson()), lessThan(64 * 1024));
    });
  });

  group('the age gate (reuses the family-structure model)', () {
    VillageDoc withEverything() => VillageDoc(
        stories: <WelcomeStory>[sampleStory(id: 'held'), sampleStory(id: 'out').copyWith(releasedOn: day)],
        shelf: withSiblings(const SiblingShelf(), sampleSiblings()));

    test('age fails closed to five, never older', () {
      expect(villageAgeOrFive(null), 5);
      expect(villageAgeOrFive(-1), 5);
      expect(villageAgeOrFive(double.nan), 5);
      expect(villageAgeOrFive('seven'), 5);
      expect(villageAgeOrFive(6), 6);
      expect(villageAgeOrFive(6.9), 6);
    });

    test('with no snapshot and an unknown age she is five: the shelf and a released story show, her people stay off', () {
      final VillageTiles t = villageTilesFor(yearsOld: null, doc: withEverything());
      expect(t.siblings, isTrue);
      expect(t.stories, <String>['out']);
      expect(t.familyTree, isFalse, reason: 'with no model the structure is unknown: it is not guessed');
    });

    test('a held story is never listed, a released one is', () {
      final VillageTiles t = villageTilesFor(view: viewOf(twoHomes, 't57'), doc: withEverything());
      expect(t.stories, <String>['out']);
      expect(villageTilesFor(view: viewOf(twoHomes, 't57'), doc: VillageDoc(stories: <WelcomeStory>[sampleStory()])).stories, isEmpty);
    });

    test('her people in pictures show when the model has people at home for her', () {
      expect(villageTilesFor(view: viewOf(twoHomes, 't57'), doc: const VillageDoc()).familyTree, isTrue);
      expect(villageTilesFor(view: viewOf(const FamilyStructure(), 't57'), doc: const VillageDoc()).familyTree, isFalse);
    });

    test('the model\'s own people switch turns her people off', () {
      final ChildView off = viewOf(twoHomes, 't57', suites: <String, bool>{'myPeople': false});
      expect(villageTilesFor(view: off, doc: const VillageDoc()).familyTree, isFalse);
    });

    test('the youngest band gets nothing, whatever a guardian wrote', () {
      expect(villageTilesFor(view: viewOf(twoHomes, 't34'), doc: withEverything()).any, isFalse);
      expect(villageTilesFor(yearsOld: 4, doc: withEverything()).any, isFalse);
      expect(villageTilesFor(yearsOld: 3, doc: withEverything()).any, isFalse);
    });

    test('the guardian\'s switch turns all of it off', () {
      expect(villageTilesFor(view: viewOf(twoHomes, 't57'), suiteOn: false, doc: withEverything()).any, isFalse);
    });

    test('a model that gives her no More hub gives these no home', () {
      final ChildView v = viewOf(twoHomes, 't57');
      final ChildView noMore = ChildView(
          band: v.band, homeVariant: v.homeVariant, tiles: <String>[for (final String x in v.tiles) if (x != 'more') x],
          heroPersonId: v.heroPersonId, wordsBesidePictures: v.wordsBesidePictures, speakEveryWord: v.speakEveryWord,
          plainGreeting: v.plainGreeting, places: v.places, features: v.features, areas: v.areas, ladder: v.ladder,
          birthdayVisible: v.birthdayVisible);
      expect(villageTilesFor(view: noMore, doc: withEverything()).any, isFalse);
    });

    test('older bands see them too (5 and over, through 8 to 12 and 13+)', () {
      for (final String b in <String>['t57', 't812', 't13']) {
        expect(villageTilesFor(view: viewOf(twoHomes, b), doc: withEverything()).any, isTrue, reason: b);
      }
    });

    test('nothing authored means no tile, so she is never handed an empty screen', () {
      expect(villageTilesFor(view: viewOf(const FamilyStructure(), 't57'), doc: const VillageDoc()).any, isFalse);
    });
  });

  test('every picture the village allows has a spoken name and none is a worry or a symbol', () {
    for (final PictureDef p in pictureLibrary) {
      if (isPictureIn(p.id, villagePictures)) {
        expect(<PictureGroup>[PictureGroup.worry, PictureGroup.symbolCore, PictureGroup.symbolExtra, PictureGroup.weather].contains(p.group), isFalse);
        expect(p.label, isNotEmpty);
      }
    }
    expect(shelfPictures.contains(PictureGroup.worry), isFalse);
  });
}
