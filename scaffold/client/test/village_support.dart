// OLIVE BRANCH — shared helpers for the Village and Compass tests. Not a test
// file itself (no main): imported by the village_* and compass_* tests.
import 'package:olive_client/village_logic.dart';
import 'package:olive_client/village_repositories.dart';

export 'rv_support.dart' show app, phone, guardian, ivy, heightOf;

const String day = '2026-11-08';

/// A fixed-clock in-memory service for Ivy.
VillageService freshVillage() => VillageService.memory(childId: 'ivy', clock: () => DateTime(2026, 11, 8, 19));

GrandCorner sampleGrand() => makeGrandCorner(
    name: 'Nana',
    cards: const <GrandCard>[
      GrandCard(id: 'g1', picture: 'book', title: 'Read to Ivy', text: 'Open the blue book on the shelf.'),
      GrandCard(id: 'g2', picture: 'grandparent', title: 'Ivy\'s news'),
    ],
    phone: const PhoneLine(who: 'Mom', number: '555 0199', note: 'Press 1'));

WelcomeStory sampleStory({String id = 's1', String title = 'A new day'}) => makeStory(id: id, title: title, pages: const <StoryPage>[
      StoryPage(picture: 'door', text: 'We open the door.'),
      StoryPage(picture: 'kitchen', text: 'We eat together.'),
    ]);

List<SiblingSlot> sampleSiblings() => const <SiblingSlot>[
      SiblingSlot(id: 'b1', name: 'Leo', picture: 'sibling'),
      SiblingSlot(id: 'b2', name: 'Mia', picture: 'sibling'),
    ];

SitterPass sampleSitter() => makeSitterPass(
    title: 'Friday evening', forWho: 'Aunt Mia', when: 'Friday 6 to 10',
    routine: const <String>['Bath at 7', 'Two books', 'Lights out at 8'],
    allergies: const <String>['Cashews (written by Mom)'],
    notes: const <String>['The hall light stays on'],
    contacts: const <PassContact>[
      PassContact(id: 'c1', name: 'Mom', relation: 'her mum', number: '555 0142', bestTimes: 'after 9'),
    ]);

SchoolBridge sampleSchool() => makeSchoolBridge(
    school: 'Oak Primary', className: 'Ms. Alvarez',
    helps: const <String>['A warning before a change'], allergies: const <String>['Cashews'],
    pickup: const <String>['Mom or Nana'], notes: const <String>[],
    contacts: const <PassContact>[PassContact(id: 'c1', name: 'Mom', number: '555 0142')]);
