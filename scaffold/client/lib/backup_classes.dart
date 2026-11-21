// OLIVE BRANCH — which areas a backup takes, and which it never does. UNVERIFIED on a device; pure Dart, runs headless
// in CI. See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// EVERY catalogued area is classed here, and a test fails if one is missing, so a new area cannot be added without
// someone deciding whether a backup keeps it (and under which key).
//
//   family    A grown-up's own records (care notes, the medicines log, the emergency card, the family ledger, ...).
//             Taken by a GROWN-UP'S phone into the family backup, opened with the family's recovery sheet.
//   home      Things a grown-up set up for her home (routine, plan, accessibility, colour, ...). Taken by BOTH: by a
//             grown-up's phone into the family backup, and by her tablet into her keepsake backup, so a replacement
//             tablet keeps her home without a grown-up's key ever opening her own things.
//   private   Hers: her pictures, her memory box, her marks on the door, her lists, stories and jokes, what she calls
//             her grown-ups. Taken ONLY by her tablet, into the keepsake backup. No grown-up's backup key opens it,
//             and no grown-up's phone writes it.
//   never     Not in any backup: the private journal, worry box, feelings weather and teen areas (sealed so that no
//             grown-up and no key opens them, P7); what is only for today or for one game; and what belongs to one
//             device alone (its pairing key, PIN check, role). A restored phone makes its own.
import 'backup_crypto.dart' show BackupKind;
import 'local_services.dart';

enum BackupClass { family, home, private, never }

const Map<String, BackupClass> kBackupClass = <String, BackupClass>{
  // grown-up side
  'care': BackupClass.family,
  'emergencycard': BackupClass.family,
  'coordination': BackupClass.family,
  'aboutchild': BackupClass.family,
  'aboutplans': BackupClass.family,
  'growing': BackupClass.family,
  'passes': BackupClass.family,
  'compass': BackupClass.family,
  'familyledger': BackupClass.family,
  'familysync': BackupClass.family,
  'trust': BackupClass.family,
  'pairedkids': BackupClass.family,
  'learn': BackupClass.family,
  'localfamily': BackupClass.family,
  'outbox': BackupClass.family,
  // her home, as a grown-up set it
  'access': BackupClass.home,
  'plan': BackupClass.home,
  'rhythm': BackupClass.home,
  'newplace': BackupClass.home,
  'voice': BackupClass.home,
  'colour': BackupClass.home,
  'profile': BackupClass.home,
  'homegrowth': BackupClass.home,
  'ladder': BackupClass.home,
  'lessons': BackupClass.home,
  'village': BackupClass.home,
  'family': BackupClass.home,
  'explainers': BackupClass.home,
  // hers
  'pictures': BackupClass.private,
  'memorybox': BackupClass.private,
  'mymarks': BackupClass.private,
  'lists': BackupClass.private,
  'stories': BackupClass.private,
  'jokes': BackupClass.private,
  'collections': BackupClass.private,
  'nicknames': BackupClass.private,
  // never
  'journal': BackupClass.never,
  'worries': BackupClass.never,
  'feelings': BackupClass.never,
  'teen': BackupClass.never,
  'daytime': BackupClass.never,
  'playsave': BackupClass.never,
  'onboarding': BackupClass.never,
  'screenshares': BackupClass.never,
  'role': BackupClass.never,
  'devicekey': BackupClass.never,
  'childpairing': BackupClass.never,
  'adultunlock': BackupClass.never,
  'localpin': BackupClass.never,
  'account': BackupClass.never,
  'backupstate': BackupClass.never,
  'backupaside': BackupClass.never,
  'restoreundo': BackupClass.never,
};

BackupClass backupClassOf(String area) => kBackupClass[area] ?? BackupClass.never;

/// Whether a backup of [kind] may take [area]. An area that is not classed is never taken.
bool backupTakes(BackupKind kind, String area) {
  final BackupClass c = backupClassOf(area);
  return switch (kind) {
    BackupKind.family => c == BackupClass.family || c == BackupClass.home,
    BackupKind.keepsake => c == BackupClass.private || c == BackupClass.home,
  };
}

/// One stored document, named the way the store names it.
class AreaName {
  const AreaName(this.scope, this.owner, this.area);
  final LocalScope scope;

  /// The child or grown-up id; empty for a device-wide area.
  final String owner;
  final String area;

  String get namespace => switch (scope) {
        LocalScope.child => 'child.$owner.$area',
        LocalScope.guardian => 'guardian.$owner.$area',
        LocalScope.device => 'device.$area',
      };

  @override
  bool operator ==(Object other) => other is AreaName && other.namespace == namespace;
  @override
  int get hashCode => namespace.hashCode;
}

/// Reads a store document name. Null for anything that is not exactly a catalogued area under its own scope (a
/// stray file, a restore's safety copy, a name with extra parts).
AreaName? parseAreaName(String name) {
  final List<String> p = name.split('.');
  if (p.length == 2 && p[0] == 'device') {
    final bool known = localDataCatalogue.any((LocalDataEntry e) => e.area == p[1] && e.scope == LocalScope.device);
    return known ? AreaName(LocalScope.device, '', p[1]) : null;
  }
  if (p.length == 3 && (p[0] == 'child' || p[0] == 'guardian')) {
    final LocalScope scope = p[0] == 'child' ? LocalScope.child : LocalScope.guardian;
    final bool known = localDataCatalogue.any((LocalDataEntry e) => e.area == p[2] && e.scope == scope);
    return known && p[1].isNotEmpty ? AreaName(scope, p[1], p[2]) : null;
  }
  return null;
}
