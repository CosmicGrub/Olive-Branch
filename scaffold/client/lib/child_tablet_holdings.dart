// OLIVE BRANCH — what a CHILD'S TABLET may hold, so that a lost or stolen tablet gives away the least.
// UNVERIFIED on a device; pure Dart, runs headless in CI (client/test/child_tablet_holdings_test.dart).
//
// THE RULE. A child's tablet holds her own things and the copies a grown-up chose to release to her. It never holds a
// grown-up's working records: the care binder's sections, the emergency card, medicines and expenses, the about-her
// profile, doctor's-plan photos, the sitter and school pages, the compass answers, and everything kept under a grown-up's
// own scope (their PIN check, their family ledger, their updates, their learning, their shared screens, the pairing list
// of tablets). Those live on a grown-up's phone. A stolen tablet is therefore a thief holding HER side only, and her
// private areas (her journal, her worry box, her feelings) were never in any family copy to begin with.
//
// HOW IT IS KEPT. On a child's tablet ([LocalServices.childTablet]) every area in [kGrownUpOnlyAreas] is opened with a
// zero-byte limit: reading it gives nothing, and any attempt to write to it is refused by the same "store is full" door
// every other limit uses. It never crashes a screen (nothing on the tablet writes these) and it never deletes anything
// (nothing is erased from a tablet). A test fails when a new area is added to the catalogue without being put in one of
// the two lists below, so this can never quietly go stale.
//
// WHAT IS NOT HERE. The family key and the grown-up-only key: a child's keyring cannot store the grown-up-only key at
// all (family_keys.dart), and that is tested in its own file.
import 'local_services.dart';

/// Areas that belong on a grown-up's phone and are never written on a child's tablet.
const Set<String> kGrownUpOnlyAreas = <String>{
  // grown-up working records, scoped by child because they are ABOUT her
  'coordination', // medicines, dose log, expenses, handover log
  'aboutchild', // the about-her profile
  'aboutplans', // photos of a doctor's plan
  'emergencycard', // the emergency card
  'passes', // sitter pass and school summary
  'compass', // a grown-up's own answers
  // everything under a grown-up's own scope
  'localfamily',
  'localpin',
  'pairedkids',
  'familyledger',
  'trust',
  'familysync',
  'learn',
  'screenshares',
};

/// Areas a child's tablet may hold: hers, the copies released to her, and the device's own small records.
const Set<String> kChildTabletAreas = <String>{
  // hers
  'journal', 'lists', 'pictures', 'stories', 'jokes', 'lessons', 'collections', 'ladder', 'teen', 'colour', 'profile',
  'onboarding', 'nicknames', 'homegrowth', 'outbox', 'memorybox', 'mymarks', 'feelings', 'worries', 'playsave',
  // released to her, or kept for her shell to show
  'family', 'growing', 'care', 'explainers', 'rhythm', 'newplace', 'voice', 'access', 'plan', 'daytime', 'village',
  // the device's own records (a word, a key, a pairing)
  'role', 'devicekey', 'childpairing', 'adultunlock', 'account',
};

/// May a child's tablet write this catalogued area?
bool childTabletMayHold(String area) => kChildTabletAreas.contains(area);

/// Catalogue areas that are in NEITHER list: a decision somebody still has to make. A test requires this to be empty.
List<String> unclassifiedAreas() => <String>[
      for (final LocalDataEntry e in localDataCatalogue)
        if (!kGrownUpOnlyAreas.contains(e.area) && !kChildTabletAreas.contains(e.area)) e.area,
    ];

/// Names in a list that are not in the catalogue (a typo, or an area that was removed).
List<String> unknownAreasInLists() => <String>[
      for (final String a in <String>{...kGrownUpOnlyAreas, ...kChildTabletAreas})
        if (!localDataCatalogue.any((LocalDataEntry e) => e.area == a)) a,
    ];

/// The plain words for the report that says what a stolen tablet holds (used by the tests and the docs, never shown to
/// a child).
List<String> childTabletHoldsSummary() => <String>[
      for (final LocalDataEntry e in localDataCatalogue)
        if (kChildTabletAreas.contains(e.area)) e.area,
    ];
