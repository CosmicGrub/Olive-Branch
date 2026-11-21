// OLIVE BRANCH — which on-device area goes into which backup, and how a restore merges it with what is already on the
// phone. UNVERIFIED on a device; pure Dart (client/test/backup_classes_test.dart). Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// THREE BACKUPS, THREE KEYS (backup_keys.dart).
//   family   what the grown-ups wrote and kept: care binder, emergency card, medicines log, expenses and handover notes,
//            the family record, settings. Locked to the family's recovery sheet.
//   keep     her pictures, memory box, lists, stories and the like: things she made or chose to keep that are not secret
//            from the family. Locked to a key her tablet holds. A family may choose to write that key on a keepsake
//            sheet (owner decision); without one, a grown-up can carry the backup to a new tablet but cannot open it.
//   private  her journal, worry box, feelings, teen choices and door marks. Locked to a key her tablet holds and that is
//            written on NO sheet and given to NO grown-up's phone, so no grown-up key opens it (P7). It reaches a
//            replacement tablet only from the old tablet, through the hand-over code.
// Settings a grown-up chose for her home (accessibility, routine, helpers, her place) are in BOTH the family backup and
// her keep backup, so a replacement tablet can keep her home exactly as it was without asking a grown-up to redo it.
//
// EVERY AREA IN [localDataCatalogue] MUST BE CLASSIFIED HERE (a test fails otherwise), so a new area cannot be added
// and silently left out of a backup, or silently put under the wrong key.
import 'local_services.dart';

enum BackupKind {
  family('family'),
  hersKeep('hers-keep'),
  hersPrivate('hers-private');

  const BackupKind(this.word);

  /// The wire and file word. Never change one.
  final String word;

  static BackupKind? fromWord(Object? w) {
    for (final BackupKind k in BackupKind.values) {
      if (k.word == w) return k;
    }
    return null;
  }
}

/// Where an area goes.
enum AreaFate { family, hersKeep, hersPrivate, familyAndHersKeep, never }

/// How a restore combines a backup's copy with what the phone already holds.
enum MergeRule {
  /// Union of keys; for a key held on both sides: the higher `version`, else the newer stamp, else lists are joined
  /// without repeats, else the phone's own value stays. The other value is set aside, never dropped.
  deep,

  /// For signed or chained records (the family record, the sharing log): never rewrite one value from another source.
  /// Keys the phone lacks are added; a key held on both sides keeps the phone's value and the backup's is set aside.
  keyUnion,
}

class BackupAreaRule {
  const BackupAreaRule(this.fate, {this.merge = MergeRule.deep, required this.why});
  final AreaFate fate;
  final MergeRule merge;

  /// Plain words: why it is where it is.
  final String why;
}

const BackupAreaRule _family = BackupAreaRule(AreaFate.family, why: 'Written and kept by a grown-up.');
const BackupAreaRule _record = BackupAreaRule(AreaFate.family,
    merge: MergeRule.keyUnion, why: 'A signed record of the family; a restore never rewrites it from another copy.');
const BackupAreaRule _both = BackupAreaRule(AreaFate.familyAndHersKeep,
    why: 'A setting a grown-up chose for her home, so a new tablet keeps her home as it was.');
const BackupAreaRule _keep = BackupAreaRule(AreaFate.hersKeep, why: 'Something she made or chose to keep.');
const BackupAreaRule _private = BackupAreaRule(AreaFate.hersPrivate,
    why: 'Hers alone. No grown-up key opens it, and it is on no recovery sheet.');

/// The table. The keys are exactly the areas of [localDataCatalogue].
const Map<String, BackupAreaRule> kBackupRules = <String, BackupAreaRule>{
  // her private areas
  'journal': _private,
  'worries': _private,
  'feelings': _private,
  'teen': _private,
  'mymarks': _private,
  // her keepsakes and activity
  'pictures': _keep,
  'memorybox': _keep,
  'lists': _keep,
  'stories': _keep,
  'jokes': _keep,
  'lessons': _keep,
  'collections': _keep,
  'ladder': _keep,
  'nicknames': _keep,
  'homegrowth': _keep,
  'outbox': _keep,
  // settings and things a grown-up prepared for her home (family AND her tablet)
  'colour': _both,
  'access': _both,
  'plan': _both,
  'rhythm': _both,
  'voice': _both,
  'profile': _both,
  'newplace': _both,
  'explainers': _both,
  'village': _both,
  'family': _both,
  // the grown-ups' records
  'care': _family,
  'emergencycard': _family,
  'coordination': _family,
  'aboutchild': _family,
  'aboutplans': _family,
  'growing': _family,
  'passes': _family,
  'compass': _family,
  'localfamily': _family,
  'familyledger': _record,
  'familysync': _record,
  'trust': _record,
  'pairedkids': _record,
  // never in any backup
  'learn': BackupAreaRule(AreaFate.never,
      why: 'A grown-up\'s private Parent Learn notes. A family sheet is shared, so they stay on this phone only.'),
  'localpin': BackupAreaRule(AreaFate.never, why: 'A PIN check that belongs to this one phone; a new phone gets a new PIN.'),
  'devicekey': BackupAreaRule(AreaFate.never, why: 'This phone\'s own key; a new phone makes its own.'),
  'childpairing': BackupAreaRule(AreaFate.never, why: 'Belongs to this one tablet; a new tablet is connected again.'),
  'adultunlock': BackupAreaRule(AreaFate.never, why: 'Belongs to this one tablet.'),
  'account': BackupAreaRule(AreaFate.never, why: 'How far this phone got with an account; a new phone signs in again.'),
  'role': BackupAreaRule(AreaFate.never, why: 'Who uses this device; chosen again on a new one.'),
  'onboarding': BackupAreaRule(AreaFate.never, why: 'Only needed until a device is connected.'),
  'daytime': BackupAreaRule(AreaFate.never, why: 'Today only; it starts empty each midnight.'),
  'playsave': BackupAreaRule(AreaFate.never, why: 'A game in progress on one phone; it ends by design.'),
  'screenshares': BackupAreaRule(AreaFate.never, why: 'Shared screens expire; they are not meant to be kept.'),
  'backup': BackupAreaRule(AreaFate.never, why: 'The backup settings of this one device.'),
  'backupkept': BackupAreaRule(AreaFate.never, why: 'Copies already set aside by a restore on this device.'),
  'childkeys': BackupAreaRule(AreaFate.never, why: 'The keys that lock her backups are never inside one.'),
};

bool _inKind(AreaFate f, BackupKind k) => switch (k) {
      BackupKind.family => f == AreaFate.family || f == AreaFate.familyAndHersKeep,
      BackupKind.hersKeep => f == AreaFate.hersKeep || f == AreaFate.familyAndHersKeep,
      BackupKind.hersPrivate => f == AreaFate.hersPrivate,
    };

/// Whether [area] belongs in a backup of [kind].
bool areaInBackup(String area, BackupKind kind) {
  final BackupAreaRule? r = kBackupRules[area];
  return r != null && _inKind(r.fate, kind);
}

/// The areas of one backup kind, in catalogue order.
List<String> areasOfBackup(BackupKind kind) => <String>[
      for (final LocalDataEntry e in localDataCatalogue)
        if (areaInBackup(e.area, kind)) e.area,
    ];

/// What is deliberately left out, in plain words, for the backup screen.
const List<String> kLeftOutWords = <String>[
  'Your PIN for this phone. A new phone gets a new PIN.',
  "This phone's own key. A new phone makes its own.",
  'Games in progress, and the reading and watching time used today.',
  'Pictures of a screen another grown-up shared. They expire.',
  'Your private Parent Learn notes. They stay on this phone only.',
  'Her private journal, worry box, feelings and marks on the door are never in the family backup. '
      'They have their own backup that only her tablet can open.',
];
