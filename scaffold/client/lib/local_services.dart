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
      area: 'onboarding', scope: LocalScope.child, maxBytes: 16 * 1024,
      what: 'The welcome answers she gave before this device was connected (name, age, a '
          'boy-or-girl tap, colour and birthday month and day, each optional) and that the '
          'questions are finished, kept under the owner "pending-device" until a grown-up '
          'connects the device; then the one answer the server takes is sent and this is '
          'deleted. No score or count is kept.'),
  LocalDataEntry(
      area: 'nicknames', scope: LocalScope.child, maxBytes: 16 * 1024,
      what: 'What she calls each of her grown-ups, if she renamed one (for example Dada or Mama): '
          'a contact id and the word she chose. They are hers: a grown-up can see them but not '
          'change them. No count or ranking.'),
  LocalDataEntry(
      area: 'homegrowth', scope: LocalScope.child, maxBytes: 8 * 1024,
      what: 'The age her home last showed and, after a birthday, whether the "your home grows" page is waiting, '
          'was seen, or was put off with Not now. Nothing else: no count, no streak, no reward.'),
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
          'photo) with an optional short caption. Kept apart from these, and marked as from them, are '
          'the short notes or small photos a grown-up left for her; a grown-up cannot edit or remove '
          'her own. No totals. Sealed on the device; never uploaded.'),
  LocalDataEntry(
      area: 'care', scope: LocalScope.child, encrypted: true, maxBytes: 4 * _mib,
      what: 'Care binder (grown-up side only): sections and contacts a guardian wrote, hospital-mode '
          'notes, and appointment checklists and question lists. Every word is a guardian\'s; the app '
          'adds no medical text. Never shown in her app. Sealed on the device; never uploaded.'),
  LocalDataEntry(
      area: 'emergencycard', scope: LocalScope.child, encrypted: true, maxBytes: 4 * _mib,
      what: 'The emergency card a guardian wrote for hospital mode when there is no live session: '
          'allergies, conditions, medicines, her doctor and contacts, every word typed by a guardian '
          '(the app adds no medical text), plus the version number and the append-only history of '
          'changes (who, when and what it said before; never deleted). Guardian-only. Sealed on the '
          'device; never uploaded.'),
  LocalDataEntry(
      area: 'explainers', scope: LocalScope.child, encrypted: true, maxBytes: 3 * _mib,
      what: 'Picture stories a guardian wrote for her: a title, up to six short pages, an optional '
          'small photo, and whether it is shown to her. The app writes none. Sealed on the device; '
          'never uploaded.'),
  LocalDataEntry(
      area: 'rhythm', scope: LocalScope.child, maxBytes: 256 * 1024,
      what: 'Rhythm, on this device only: the routine and the first-then cards a grown-up set '
          '(pictures and short names), her bag list, how-the-app-feels settings (sound, motion, '
          'brightness), a local "she sleeps in two homes" setting a grown-up set for the bag (off unless set), '
          'and which steps she has ticked TODAY (dropped the next day). No score, '
          'streak or count; nothing is shared with her other home.'),
  LocalDataEntry(
      area: 'newplace', scope: LocalScope.child, maxBytes: 4 * _mib,
      what: 'A new place a grown-up prepared for her: a few room pictures or small room photos '
          'with a short caption each, and a short plan. Rooms only: no address, no map, no '
          'coordinates. Kept only here.'),
  LocalDataEntry(
      area: 'voice', scope: LocalScope.child, maxBytes: 256 * 1024,
      what: 'Voice, on this device only: the grown-ups a guardian wrote down as her helpers (a '
          'name, a picture and a short line each), her personal symbols, and whether a grown-up has '
          'switched Voice on (it is off until they do). What she says with symbols is never kept.'),
  LocalDataEntry(
      area: 'feelings', scope: LocalScope.child, encrypted: true, maxBytes: 64 * 1024,
      what: "Feelings weather: only TODAY's weather picture she picked (older ones are dropped). "
          'Sealed on the device; never shown to anyone, no history, no count.'),
  LocalDataEntry(
      area: 'worries', scope: LocalScope.child, encrypted: true, maxBytes: 2 * _mib,
      what: 'Her worry box: the pictures she tapped and the drawings she made, and whether she '
          'chose to show her grown-up, and, privately, whether the window for grown-ups has opened on one she '
          'showed (only so she can be told the truth if she takes it back). Sealed on the device; a '
          'grown-up sees only what she chose to show; letting one float away deletes it. Never read '
          'or tagged: no score, no count.'),
  LocalDataEntry(
      area: 'access', scope: LocalScope.child, maxBytes: 16 * 1024,
      what: 'Accessibility for her device, as a grown-up set it: read aloud, reduce motion, '
          'roomier reading, larger targets, and whether captions are wanted. Five on/off '
          'switches; nothing else.'),
  LocalDataEntry(
      area: 'village', scope: LocalScope.child, encrypted: true, maxBytes: 128 * 1024,
      what: 'Village, on this device only: a large-print grandparent page, picture stories a guardian '
          'wrote and whether each is released to her (a held one is never shown), the sibling '
          'shelf (names, pictures, and the pictures left on it), and the faces a guardian picked '
          'for her people. Sealed on the device; no count or score; nothing is sent or shared '
          'with her other home.'),
  LocalDataEntry(
      area: 'passes', scope: LocalScope.child, encrypted: true, maxBytes: 64 * 1024,
      what: 'The sitter pass and the school summary a guardian wrote: routine lines, allergies in '
          'the guardian\'s own words, and contact names and numbers as text. Guardian side only, '
          'never in her app. Sealed on the device; it leaves only when a grown-up shows the '
          'screen; no school or sitter is ever contacted.'),
  LocalDataEntry(
      area: 'compass', scope: LocalScope.child, encrypted: true, maxBytes: 32 * 1024,
      what: 'Compass, a guardian\'s own answers to two gentle questions (who is in her life, what '
          'would help) and which of the two accessibility profiles are on. Guardian side only. '
          'Sealed on the device; no score and no label about her; nothing is sent.'),
  LocalDataEntry(
      area: 'role', scope: LocalScope.device, maxBytes: 4 * 1024,
      what: 'Who is using this device, chosen on the very first screen: one word, kid, mom, dad or '
          'someone else. It decides which app opens. It is not a name and grants a grown-up nothing; '
          'a device wipe removes it and the device asks again.'),
  LocalDataEntry(
      area: 'localfamily', scope: LocalScope.guardian, encrypted: true, maxBytes: 16 * 1024,
      what: 'The family a grown-up set up on this device without a server: their name and what she '
          'calls them, her first name and age (locked; changing it needs a grown-up PIN) and '
          'the time zone she lives in. Kept only here until the device is connected; nothing is '
          'uploaded. Sealed on the device.'),
  LocalDataEntry(
      area: 'localpin', scope: LocalScope.guardian, encrypted: true, maxBytes: 4 * 1024,
      what: 'The PIN a grown-up chose for this device only, as a salted slow hash (the PIN itself is never '
          'kept), and the count of wrong tries toward a 15 minute lock. It gates changing her locked '
          'age, clearing data and the settings here. It is not the account PIN and is never sent '
          'anywhere. Sealed on the device.'),
  LocalDataEntry(
      area: 'devicekey', scope: LocalScope.device, encrypted: true, maxBytes: 4 * 1024,
      what: 'This device\'s own signing key for pairing (the secret half never leaves the device). It '
          'lets a grown-up\'s device prove who it is and lets a child\'s device prove it was approved. '
          'It holds no PIN and no personal data. Sealed on the device.'),
  LocalDataEntry(
      area: 'childpairing', scope: LocalScope.device, encrypted: true, maxBytes: 8 * 1024,
      what: 'On a child\'s device: the pairing certificate a grown-up\'s device signed (which child, which '
          'family), that grown-up\'s public key and first name, and the child\'s first name. No PIN. '
          'Sealed on the device.'),
  LocalDataEntry(
      area: 'adultunlock', scope: LocalScope.device, encrypted: true, maxBytes: 4 * 1024,
      what: 'On a child\'s device: a salted slow hash of the grown-up\'s PIN, only so a grown-up can '
          'type it there to leave or unlock the app, and the count of wrong tries toward a 15 minute '
          'lock. The PIN itself is never kept and a child cannot create or change it. Sealed on the device.'),
  LocalDataEntry(
      area: 'pairedkids', scope: LocalScope.guardian, encrypted: true, maxBytes: 16 * 1024,
      what: 'On a grown-up\'s device: the child devices it approved (a certificate id, a device name and '
          'the date), so one can be forgotten later. Sealed on the device.'),
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
