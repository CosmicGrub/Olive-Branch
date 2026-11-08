// OLIVE BRANCH — the one place an app run decides WHERE its on-device data
// lives and WHOSE it is. No longer UNVERIFIED — verified by CI
// (client/test/local_services_test.dart).
//
// Three jobs.
//
// 1. SCOPING. Every namespace is named for its owner: `child.<childId>.<area>`
//    for a child's own things, `guardian.<guardianId>.<area>` for a grown-up's,
//    `device.<area>` for nothing personal. One device can therefore hold more
//    than one child profile later without their data touching, and wiping one
//    profile is a prefix delete. A live build refuses the literal 'demo-child'
//    as a scope (see [LocalServices.scopeChild]); only the offline preview and
//    tests, which are not live, may use it.
//
// 2. THE CATALOGUE. [localDataCatalogue] is the single, reviewable list of
//    everything this app writes to the device: the area, what it holds,
//    whether it is encrypted, how large it may grow. Namespace specs are
//    built FROM it, the 'Clear data on this device' screen shows it, and
//    MASTERFILE section 8.15 documents it; a test fails if any of those drift.
//    Nothing is stored that is not in this list.
//
// 3. THE CURRENT INSTANCE. Screens reach storage through
//    [LocalServices.current]. It defaults to an in-memory instance (tests and
//    the preview before boot), so a screen built without any setup works and
//    simply does not survive a restart; `main*.dart` installs the real,
//    directory-backed one with [LocalServices.boot].
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'device_identity.dart';
import 'local_store.dart';
import 'sha256.dart';
import 'store_cipher.dart';

/// Whose data an area belongs to.
enum LocalScope { child, guardian, device }

/// One line of the on-device data catalogue.
class LocalDataEntry {
  const LocalDataEntry({
    required this.area,
    required this.scope,
    required this.what,
    this.encrypted = false,
    this.maxBytes = 512 * 1024,
    this.schema = 1,
  });

  /// The last part of the namespace name.
  final String area;
  final LocalScope scope;

  /// Plain words for the guardian: what is kept, and what is deliberately not.
  final String what;
  final bool encrypted;
  final int maxBytes;
  final int schema;
}

const int _mib = 1024 * 1024;

/// EVERYTHING this app writes to the device. See the file header.
const List<LocalDataEntry> localDataCatalogue = <LocalDataEntry>[
  LocalDataEntry(
      area: 'journal', scope: LocalScope.child, encrypted: true, maxBytes: 4 * _mib,
      what: 'Her private journal entries (text and date). Sealed on the device; '
          'no grown-up can open them (P7).'),
  LocalDataEntry(
      area: 'lists', scope: LocalScope.child,
      what: 'Her wants and needs lists: the words she typed and whether she ticked them. '
          'No prices (P4).'),
  LocalDataEntry(
      area: 'pictures', scope: LocalScope.child, maxBytes: 12 * _mib,
      what: 'Doodles and colourings she chose to keep, and photo-taps, as the strokes or '
          'fills that make them. Kept only here; never in the phone gallery, never uploaded.'),
  LocalDataEntry(
      area: 'stories', scope: LocalScope.child,
      what: 'Stories she starred and the place she bookmarked. A story code, its title and the '
          'date. No read counts.'),
  LocalDataEntry(
      area: 'jokes', scope: LocalScope.child,
      what: 'Jokes she starred: the joke id and the date. No tallies.'),
  LocalDataEntry(
      area: 'lessons', scope: LocalScope.child,
      what: 'Things she taught a grown-up: the title, how, and the date. '
          'No grade, level or score.'),
  LocalDataEntry(
      area: 'collections', scope: LocalScope.child,
      what: 'Collections she has shown: names she added, with the date. No totals or targets.'),
  LocalDataEntry(
      area: 'ladder', scope: LocalScope.child,
      what: 'Which growing-up steps she has reached and which she has already been told about. '
          'Only ever grows; nothing is taken back.'),
  LocalDataEntry(
      area: 'colour', scope: LocalScope.child,
      what: 'Colour of the day for this device: the last two weeks of colour days (only the '
          'latest is ever used or shown; older ones are dropped), the art style, and the play '
          'window the grown-up set. No tally of picks.'),
  LocalDataEntry(
      area: 'family', scope: LocalScope.child, encrypted: true, maxBytes: 4 * _mib,
      what: 'Family structure a grown-up built and released on this device: who is in her life, '
          'her homes, the append-only history of changes, and guardian-written stories. '
          'Sealed on the device; never uploaded.'),
  LocalDataEntry(
      area: 'profile', scope: LocalScope.child,
      what: 'A small cache so a child who started the app online can open it with no signal: '
          'her first name, her age in whole years, that she finished the welcome tour, and '
          "the grown-up's last hide/pace choices for her (so offline never unhides anything)."),
  LocalDataEntry(
      area: 'outbox', scope: LocalScope.child, maxBytes: 2 * _mib,
      what: 'Things she made while offline that are waiting to go, so a restart does not lose '
          'them. Never shown to her as a queue.'),
  LocalDataEntry(
      area: 'growing', scope: LocalScope.child, encrypted: true, maxBytes: 8 * _mib,
      what: 'Growing (grown-up side): time capsules a guardian sealed (a note, the opening date, '
          'an optional small photo), first times a guardian kept (title, date, note, small photo), '
          'pencil-mark heights a guardian recorded, and which of these suites are switched on. '
          'No counts, streaks or comparison with other children. Sealed on the device; never uploaded.'),
  LocalDataEntry(
      area: 'memorybox', scope: LocalScope.child, encrypted: true, maxBytes: 6 * _mib,
      what: 'Her memory box: pictures she chose to keep (a copy of a doodle or colouring, or a small '
          'photo) with an optional short caption. No totals. Sealed on the device; never uploaded.'),
  LocalDataEntry(
      area: 'care', scope: LocalScope.child, encrypted: true, maxBytes: 4 * _mib,
      what: 'Care binder (grown-up side only): sections and contacts a guardian wrote, hospital-mode '
          'notes, and appointment checklists and question lists. Every word is a guardian\'s; the app '
          'adds no medical text. Never shown in her app. Sealed on the device; never uploaded.'),
  LocalDataEntry(
      area: 'explainers', scope: LocalScope.child, encrypted: true, maxBytes: 3 * _mib,
      what: 'Picture stories a guardian wrote for her: a title, up to six short pages, an optional '
          'small photo, and whether it is shown to her. The app writes none. Sealed on the device; '
          'never uploaded.'),
  LocalDataEntry(
      area: 'learn', scope: LocalScope.guardian, encrypted: true, maxBytes: 2 * _mib,
      what: 'Parent Learn: the guardian\'s settings and, only if they chose to save them, '
          'their reflections and own rules list. Sealed on the device; default private; '
          'turning a setting off forgets what it stored.'),
];

/// Looks an area up in [localDataCatalogue]; throws for an unknown one, so a
/// new area cannot be written without being listed.
LocalDataEntry localDataEntry(String area) =>
    localDataCatalogue.firstWhere((LocalDataEntry e) => e.area == area,
        orElse: () => throw ArgumentError('"$area" is not in localDataCatalogue'));

final RegExp _plainId = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

/// A namespace-safe form of an id. UUIDs and the app's own ids pass through
/// unchanged; anything else is lower-cased, stripped to safe characters, and
/// suffixed with a short hash of the original so two different ids can never
/// collapse into one scope.
String scopeId(String raw) {
  final String lower = raw.toLowerCase();
  if (_plainId.hasMatch(lower) && lower == raw) return raw;
  final String cleaned = lower.replaceAll(RegExp(r'[^a-z0-9-]+'), '-').replaceAll(RegExp(r'^-+'), '');
  final String head = cleaned.isEmpty ? 'id' : cleaned.substring(0, cleaned.length.clamp(0, 40));
  return '$head-${sha256Hex(raw).substring(0, 10)}';
}

class LocalServices {
  LocalServices({
    required this.store,
    required this.childId,
    this.guardianId = 'local-guardian',
    this.isLive = false,
    this.demoSeeds = true,
    this.keyring,
  }) {
    scopeChild(childId); // fails fast on an illegal live scope
  }

  /// A fresh in-memory instance with a real (random-key) cipher, so even the
  /// private namespaces behave exactly as on a device. For tests and the
  /// offline preview before boot.
  factory LocalServices.memory({
    String childId = 'demo-child',
    String guardianId = 'local-guardian',
    bool isLive = false,
    bool demoSeeds = true,
    MemoryStoreBackend? backend,
  }) =>
      LocalServices(
        store: LocalStore(
            backend: backend ?? MemoryStoreBackend(),
            cipher: AesGcmStoreCipher(AesGcmStoreCipher.newKey())),
        childId: childId,
        guardianId: guardianId,
        isLive: isLive,
        demoSeeds: demoSeeds,
      );

  final LocalStore store;

  /// The child profile this device is showing. A live build always has a real
  /// one (a paired device's target id, or the dev provisioning id).
  final String childId;
  final String guardianId;

  /// True for a build wired to a real backend: no demo ids, no demo seeds.
  final bool isLive;

  /// Whether screens may show their invented example content (the preview
  /// build's sample list items and collections) when nothing is stored yet.
  /// Live builds set this false: a real family never sees invented content.
  final bool demoSeeds;

  /// Held only to drop the encryption key on a wipe.
  final StoreCipherKeyring? keyring;

  static LocalServices _current = LocalServices.memory();
  static LocalServices get current => _current;
  static void install(LocalServices services) => _current = services;

  /// Puts a fresh in-memory instance back. For test tear-downs.
  static void resetForTest() => _current = LocalServices.memory();

  /// The directory-backed, encrypted instance a real app run uses. Needs the
  /// platform channels (path_provider, flutter_secure_storage), so tests build
  /// a [LocalServices] directly instead.
  static Future<LocalServices> boot({
    required String childId,
    String guardianId = 'local-guardian',
    required bool isLive,
    SecureKeyValueStore secure = const FlutterSecureKeyValueStore(),
    Directory? rootOverride,
  }) async {
    final Directory docs = rootOverride ?? await getApplicationDocumentsDirectory();
    final Directory root =
        rootOverride ?? Directory('${docs.path}${Platform.pathSeparator}olive_store');
    final StoreCipherKeyring keyring = StoreCipherKeyring(secure);
    final LocalServices s = LocalServices(
      store: LocalStore(backend: DirectoryStoreBackend(root), cipher: await keyring.cipher()),
      childId: childId,
      guardianId: guardianId,
      isLive: isLive,
      demoSeeds: !isLive,
      keyring: keyring,
    );
    install(s);
    return s;
  }

  /// The scope id for [id] (default: this device's child). Throws a
  /// [StateError] in a live build for the preview literal 'demo-child', so a
  /// live screen can never write into the demo scope.
  String scopeChild([String? id]) {
    final String raw = id ?? childId;
    if (isLive && raw == 'demo-child') {
      throw StateError('a live build must not scope data to the literal "demo-child"');
    }
    return scopeId(raw);
  }

  String namespaceName(LocalDataEntry e, {String? ownerId}) => switch (e.scope) {
        LocalScope.child => 'child.${scopeChild(ownerId)}.${e.area}',
        LocalScope.guardian => 'guardian.${scopeId(ownerId ?? guardianId)}.${e.area}',
        LocalScope.device => 'device.${e.area}',
      };

  /// The namespace for a catalogued [area], owned by [ownerId] (default: this
  /// device's child or guardian, per the area's scope).
  LocalNamespace area(String area, {String? ownerId}) {
    final LocalDataEntry e = localDataEntry(area);
    return store.open(NamespaceSpec(
        name: namespaceName(e, ownerId: ownerId),
        schema: e.schema,
        encrypted: e.encrypted,
        maxBytes: e.maxBytes));
  }

  /// Everything this device holds for one child profile.
  Future<void> forgetChild(String id) => store.deleteWithPrefix('child.${scopeChild(id)}.');

  /// The device wipe: every document, every quarantined copy, and the
  /// encryption key. Pairing credentials in secure storage are NOT touched;
  /// that is the paired-devices screen's job.
  Future<void> wipeAll() async {
    await store.wipe();
    await keyring?.erase();
  }
}

/// Plain-words list of the catalogue, for the clear-data screen and docs.
String describeLocalData() => <String>[
      for (final LocalDataEntry e in localDataCatalogue)
        '${e.area} (${e.scope.name}${e.encrypted ? ', encrypted' : ''}): ${e.what}',
    ].join('\n');
