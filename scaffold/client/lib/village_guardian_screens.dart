// OLIVE BRANCH — suite D VILLAGE, the guardian's side: the hub, the editors and
// the one-page views. No longer UNVERIFIED — verified by CI
// (client/test/village_guardian_screens_test.dart).
//
// GUARDIAN-ONLY. Everything a child sees from Village is written here, by a
// guardian, and only a guardian principal can save it (the service refuses the
// child principal: see village_repositories.dart). The child shell never imports
// this file. Entry point: the guardian Settings hub (Family group) in guardian_more.dart.
//
// ON THIS DEVICE ONLY, said plainly on every hub: nothing here is sent anywhere,
// nothing is shared with her other home, and no school, sitter or grandparent is
// contacted. The sitter pass and the school summary leave the device only because
// a grown-up holds the screen up. Printing is not built.
//
// NOTHING IS WRITTEN FOR YOU. The editors start empty. No sentence about a new
// partner, a family change or a person's role is offered, suggested or filled in;
// names and relationship words on a page are exactly what you typed.
import 'package:flutter/material.dart';

import 'family_structure_logic.dart' show FamilyPrincipal, Person, shownToChild;
import 'family_structure_store.dart' show localFamilyService;
import 'picture_icons.dart';
import 'picture_library.dart';
import 'rhythm_logic.dart' show RvRefused, cleanText, maxLineChars, maxTitleChars;
import 'rhythm_voice_guardian_screens.dart' show askText, refusalText;
import 'village_logic.dart';
import 'village_repositories.dart';

/// The plain-words explanation of a refusal (Village's own codes, then Rhythm's).
String villageRefusalText(String reason) => switch (reason) {
      'bad_number' => 'Please write a phone number with digits only (7 to 15 digits).',
      'too_many_cards' => 'Four cards is the most there is room for.',
      'too_many_stories' => 'Three stories is the most there is room for.',
      'too_many_pages' => 'A story can have up to six pages.',
      'no_pages' => 'A story needs at least one page.',
      'too_many_siblings' => 'Four is the most there is room for.',
      'too_many_contacts' => 'That is the most people there is room for.',
      'too_many_faces' => 'That is the most faces there is room for.',
      'unknown_story' => 'That story is not here any more.',
      'bad_card' || 'bad_page' || 'bad_sibling' || 'bad_contact' || 'bad_picture' => 'Something there did not work. Please check it.',
      'guardian_only' => 'Only a grown-up can change this.',
      _ => refusalText(reason),
    };

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
      );
}

mixin _Reporter<T extends StatefulWidget> on State<T> {
  /// True when the device refused to open the editor's document (only a guardian
  /// principal can): the editor then shows [deniedNote] and nothing else.
  bool denied = false;

  void deny(Object _) {
    if (mounted) setState(() => denied = true);
  }

  Widget get deniedNote => const QuietNote('Only a grown-up can change this.', icon: Icons.lock_outline);

  void say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void report(VillageResult r) => say(r.ok ? 'Saved on this device.' : villageRefusalText(r.reason));
}

class _LocalOnlyNote extends StatelessWidget {
  const _LocalOnlyNote(this.childName, {this.extra});
  final String childName;
  final String? extra;
  @override
  Widget build(BuildContext context) => QuietNote(
      'Kept on this device only. It is not shared with $childName\'s other home yet.${extra == null ? '' : ' $extra'}',
      icon: Icons.phone_android_outlined);
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
            minVerticalPadding: 12, leading: Icon(icon), title: Text(title), subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right), onTap: onTap),
      );
}

/// A picture from any of [groups] (the library's own order).
Future<String?> pickVillagePicture(BuildContext context, Set<PictureGroup> groups) => showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Choose a picture'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: PictureGrid(minTile: 96, children: <Widget>[
              for (final PictureDef p in pictureLibrary)
                if (groups.contains(p.group))
                  PictureTile(key: Key('pick_${p.id}'), picture: p.id, label: p.label, minHeight: 88,
                      onTap: () => Navigator.of(ctx).pop(p.id)),
            ]),
          ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel'))],
      ),
    );

String _ageNote(String childName, int? yearsOld) =>
    villageAgeOrFive(yearsOld) < 5
        ? '$childName is under five, so her side of this does not show yet. It opens from five. The sitter pass, school summary and grandparent page are for grown-ups and work at any age.'
        : 'Her pictures and stories show on $childName\'s device from age five, and only when the switch below is on. The sitter pass, school summary and grandparent page are only ever for grown-ups.';

/// Where a guardian's list of people comes from: the family builder, as
/// (id, label) pairs a child would see (background roles left out). Injectable.
typedef PeopleSource = Future<List<({String id, String label})>> Function();

Future<List<({String id, String label})>> familyBuilderPeople(FamilyPrincipal principal, int yearsOld) async {
  final o = await localFamilyService.overview(principal, yearsOld: yearsOld);
  return <({String id, String label})>[
    for (final Person p in o.intended.people) if (shownToChild(p)) (id: p.id, label: p.label.trim()),
  ];
}

// ================================================================== HUB ======
class VillageGuardianHubScreen extends StatefulWidget {
  const VillageGuardianHubScreen({
    super.key, required this.childName, required this.service, required this.principal, this.yearsOld, this.people,
    this.routineLines,
  });
  final String childName;
  final VillageService service;
  final FamilyPrincipal principal;
  final int? yearsOld;
  final PeopleSource? people;

  /// Reads the step names of the Rhythm routine, for the sitter pass's copy button.
  final Future<List<String>> Function()? routineLines;
  @override
  State<VillageGuardianHubScreen> createState() => _VillageHubState();
}

class _VillageHubState extends State<VillageGuardianHubScreen> with _Reporter<VillageGuardianHubScreen> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    widget.service.loadForGuardian(widget.principal).then((VillageDoc d) {
      if (mounted) setState(() => _on = d.suiteOn);
    }).catchError((Object _) {});
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final String n = widget.childName;
    final VillageService s = widget.service;
    final FamilyPrincipal p = widget.principal;
    return _Page(title: 'Village', children: <Widget>[
      _LocalOnlyNote(n, extra: 'No school, sitter or relative is ever contacted.'),
      const SizedBox(height: 8),
      Text(_ageNote(n, widget.yearsOld), key: const Key('villageAgeNote')),
      SwitchListTile(
        key: const Key('villageSuite'), value: _on, title: Text('Show on $n\'s device'),
        subtitle: const Text('Only her pictures, faces and released stories. The pages for grown-ups are not affected.'),
        onChanged: (bool v) async {
          final VillageResult r = await s.setSuite(p, v);
          if (r.ok) setState(() => _on = v);
          report(r);
        },
      ),
      _Row(key: const Key('rowGrand'), icon: Icons.elderly_outlined, title: 'Grandparent corner',
          subtitle: 'A large-print page you write, to hand a grandparent the device',
          onTap: () => _push(GrandCornerEditorScreen(childName: n, service: s, principal: p))),
      _Row(key: const Key('rowFaces'), icon: Icons.diversity_3_outlined, title: 'Her people, in pictures',
          subtitle: 'Choose a face for each person in your family builder',
          onTap: () => _push(FacesEditorScreen(childName: n, service: s, principal: p,
              people: widget.people ?? () => familyBuilderPeople(p, villageAgeOrFive(widget.yearsOld))))),
      _Row(key: const Key('rowStories'), icon: Icons.auto_stories_outlined, title: 'A story for her',
          subtitle: 'A picture story you write, shown to her only when you release it',
          onTap: () => _push(StoriesScreen(childName: n, service: s, principal: p))),
      _Row(key: const Key('rowShelf'), icon: Icons.photo_library_outlined, title: 'Sibling shelf',
          subtitle: 'Names and pictures; brothers and sisters on this device leave each other pictures',
          onTap: () => _push(SiblingEditorScreen(childName: n, service: s, principal: p))),
      _Row(key: const Key('rowSitter'), icon: Icons.child_care_outlined, title: 'Sitter pass',
          subtitle: 'One page for a trusted adult: routine, allergies, who to reach. You show the screen',
          onTap: () => _push(SitterPassEditorScreen(childName: n, service: s, principal: p, routineLines: widget.routineLines))),
      _Row(key: const Key('rowSchool'), icon: Icons.school_outlined, title: 'School summary',
          subtitle: 'One page about what helps at school, kept here. The school is not contacted',
          onTap: () => _push(SchoolBridgeEditorScreen(childName: n, service: s, principal: p))),
    ]);
  }
}

// ======================================================= grandparent corner ===
class GrandCornerEditorScreen extends StatefulWidget {
  const GrandCornerEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final VillageService service;
  final FamilyPrincipal principal;
  @override
  State<GrandCornerEditorScreen> createState() => _GrandEditorState();
}

class _GrandEditorState extends State<GrandCornerEditorScreen> with _Reporter<GrandCornerEditorScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _who = TextEditingController();
  final TextEditingController _number = TextEditingController();
  final TextEditingController _note = TextEditingController();
  List<GrandCard> _cards = <GrandCard>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.service.loadForGuardian(widget.principal).then((VillageDoc d) {
      if (!mounted) return;
      final GrandCorner? g = d.grand;
      setState(() {
        _name.text = g?.name ?? '';
        _cards = <GrandCard>[...?g?.cards];
        _who.text = g?.phone?.who ?? '';
        _number.text = g?.phone?.number ?? '';
        _note.text = g?.phone?.note ?? '';
        _loaded = true;
      });
    }).catchError((Object e) { deny(e); });
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _who, _number, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addCard() async {
    if (_cards.length >= maxGrandCards) return say(villageRefusalText('too_many_cards'));
    final String? pic = await pickVillagePicture(context, villagePictures);
    if (pic == null || !mounted) return;
    final String? title = await askText(context, 'Name this button', pictureLabel(pic));
    if (title == null || !mounted) return;
    final String? text = await askText(context, 'What should it say? (optional)', '', maxLength: maxGrandTextChars);
    if (text == null || !mounted) return;
    try {
      final GrandCard c = GrandCard(
          id: widget.service.newId('g'), picture: pic, title: cleanText(title),
          text: cleanText(text, max: maxGrandTextChars, allowEmpty: true));
      setState(() => _cards = <GrandCard>[..._cards, c]);
    } on RvRefused catch (e) {
      say(villageRefusalText(e.reason));
    }
  }

  PhoneLine? _phone() {
    if (_who.text.trim().isEmpty && _number.text.trim().isEmpty) return null;
    return PhoneLine(who: _who.text, number: _number.text, note: _note.text);
  }

  Future<void> _save() async =>
      report(await widget.service.saveGrandCorner(
          widget.principal, GrandCorner(name: _name.text, cards: _cards, phone: _phone())));

  void _show() {
    try {
      final GrandCorner g = makeGrandCorner(name: _name.text, cards: _cards, phone: _phone());
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GrandCornerScreen(corner: g)));
    } on RvRefused catch (e) {
      say(villageRefusalText(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Grandparent corner', children: <Widget>[
        _LocalOnlyNote(widget.childName, extra: 'Calling and sending pictures are not built; this page only shows what you write.'),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        if (_loaded) ...<Widget>[
          TextField(key: const Key('grandName'), controller: _name, maxLength: maxTitleChars,
              decoration: const InputDecoration(labelText: 'What do you call them? (for "Hello, ...")', border: OutlineInputBorder())),
          for (final GrandCard c in _cards)
            Card(
              key: Key('grandCard_${c.id}'),
              child: ListTile(
                leading: PictureGlyph(c.picture, size: 24), title: Text(c.title),
                subtitle: c.text.isEmpty ? null : Text(c.text),
                trailing: IconButton(key: Key('grandRemove_${c.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _cards = <GrandCard>[for (final GrandCard x in _cards) if (x.id != c.id) x])),
              ),
            ),
          OutlinedButton.icon(key: const Key('grandAdd'), onPressed: _addCard, icon: const Icon(Icons.add), label: const Text('Add a big button')),
          const SizedBox(height: 12),
          Text('A phone line, written down', style: Theme.of(context).textTheme.titleMedium),
          const Text('Shown as large text. The app never dials it.'),
          const SizedBox(height: 6),
          TextField(key: const Key('grandPhoneWho'), controller: _who, maxLength: maxNameChars,
              decoration: const InputDecoration(labelText: 'Whose number', border: OutlineInputBorder())),
          TextField(key: const Key('grandPhoneNumber'), controller: _number, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Number', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(key: const Key('grandPhoneNote'), controller: _note, maxLength: maxLineChars,
              decoration: const InputDecoration(labelText: 'A short note (optional)', border: OutlineInputBorder())),
          FilledButton(key: const Key('grandSave'), onPressed: _save, child: const Text('Save')),
          TextButton(key: const Key('grandShow'), onPressed: _show, child: const Text('Show it large')),
          TextButton(
              key: const Key('grandClear'),
              onPressed: () async {
                final VillageResult r = await widget.service.saveGrandCorner(widget.principal, null);
                if (r.ok) {
                  setState(() {
                    _name.clear(); _who.clear(); _number.clear(); _note.clear(); _cards = <GrandCard>[];
                  });
                }
                report(r);
              },
              child: const Text('Clear this page')),
        ],
      ]);
}

/// The large-print page itself: huge buttons, nothing that could be broken. A
/// card opens its text in very large type. Shown by a grown-up handing over the device.
class GrandCornerScreen extends StatelessWidget {
  const GrandCornerScreen({super.key, required this.corner});
  final GrandCorner corner;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ColorScheme c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(corner.name.isEmpty ? 'Hello' : 'Hello, ${corner.name}', style: const TextStyle(fontSize: 26))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          if (corner.isEmpty) Text('Nothing has been written here yet.', key: const Key('grandEmpty'), style: t.headlineSmall),
          for (int i = 0; i < corner.cards.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                key: Key('grandBig_${corner.cards[i].id}'),
                color: i == 0 ? c.primary : c.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: corner.cards[i].text.isEmpty
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (BuildContext ctx) => AlertDialog(
                              title: Text(corner.cards[i].title, style: const TextStyle(fontSize: 28)),
                              content: Text(corner.cards[i].text, key: const Key('grandBigText'), style: const TextStyle(fontSize: 26, height: 1.4)),
                              actions: <Widget>[
                                SizedBox(height: 64, child: TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close', style: TextStyle(fontSize: 22)))),
                              ])),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 96),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: <Widget>[
                        Icon(pictureIcon(corner.cards[i].picture), size: 48, color: i == 0 ? c.onPrimary : c.onSurface),
                        const SizedBox(width: 16),
                        Expanded(child: Text(corner.cards[i].title,
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: i == 0 ? c.onPrimary : c.onSurface))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          if (corner.phone != null)
            Container(
              key: const Key('grandPhone'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Prefer the phone?', style: TextStyle(fontSize: 22, color: c.onSecondaryContainer)),
                Text('${corner.phone!.who}: ${corner.phone!.number}',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c.onSecondaryContainer)),
                if (corner.phone!.note.isNotEmpty)
                  Text(corner.phone!.note, style: TextStyle(fontSize: 22, color: c.onSecondaryContainer)),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ============================================================== faces ========
class FacesEditorScreen extends StatefulWidget {
  const FacesEditorScreen({super.key, required this.childName, required this.service, required this.principal, required this.people});
  final String childName;
  final VillageService service;
  final FamilyPrincipal principal;
  final PeopleSource people;
  @override
  State<FacesEditorScreen> createState() => _FacesEditorState();
}

class _FacesEditorState extends State<FacesEditorScreen> with _Reporter<FacesEditorScreen> {
  List<({String id, String label})> _people = <({String id, String label})>[];
  Map<String, String> _faces = <String, String>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<({String id, String label})> ppl = <({String id, String label})>[];
    try {
      ppl = await widget.people();
    } catch (_) {}
    try {
      final VillageDoc d = await widget.service.loadForGuardian(widget.principal);
      if (mounted) setState(() { _people = ppl; _faces = d.faces; _loaded = true; });
    } catch (e) {
      deny(e);
    }
  }

  Future<void> _choose(String id) async {
    final String? pic = await pickVillagePicture(context, facePictures);
    if (pic == null || !mounted) return;
    report(await widget.service.setFace(widget.principal, id, pic));
    await _load();
  }

  Future<void> _plain(String id) async {
    report(await widget.service.setFace(widget.principal, id, null));
    await _load();
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Her people, in pictures', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        const Text('The names come from your family builder, exactly as you chose them. Here you only choose the face she sees beside each name.',
            key: Key('facesNote')),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        if (_loaded && _people.isEmpty)
          const QuietNote('Nobody is in the family builder yet. Add people there first.', icon: Icons.people_outline),
        for (final ({String id, String label}) p in _people)
          Card(
            key: Key('faceRow_${p.id}'),
            child: ListTile(
              leading: _faces[p.id] == null ? const CircleAvatar(child: Icon(Icons.person_outline)) : PictureGlyph(_faces[p.id]!, size: 24),
              title: Text(p.label),
              subtitle: Text(_faces[p.id] == null ? 'Shows her first letter' : pictureLabel(_faces[p.id])),
              onTap: () => _choose(p.id),
              trailing: _faces[p.id] == null
                  ? null
                  : IconButton(key: Key('facePlain_${p.id}'), tooltip: 'Use the first letter', icon: const Icon(Icons.close), onPressed: () => _plain(p.id)),
            ),
          ),
      ]);
}

// ============================================================== stories ======
class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final VillageService service;
  final FamilyPrincipal principal;
  @override
  State<StoriesScreen> createState() => _StoriesState();
}

class _StoriesState extends State<StoriesScreen> with _Reporter<StoriesScreen> {
  List<WelcomeStory> _stories = <WelcomeStory>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final VillageDoc d = await widget.service.loadForGuardian(widget.principal);
      if (mounted) setState(() { _stories = d.stories; _loaded = true; });
    } catch (e) {
      deny(e);
    }
  }

  Future<void> _edit(WelcomeStory? s) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StoryEditorScreen(childName: widget.childName, service: widget.service, principal: widget.principal, story: s)));
    await _load();
  }

  Future<void> _release(WelcomeStory s) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Show "${s.title}" to ${widget.childName}?'),
        content: const Text('It will appear on her device, in her village, until you hold it again. Release it when you are ready for her to see it.'),
        actions: <Widget>[
          TextButton(key: const Key('releaseNo'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not yet')),
          FilledButton(key: const Key('releaseYes'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Show her')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    report(await widget.service.releaseStory(widget.principal, s.id));
    await _load();
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'A story for her', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        const Text('You write every word. Nothing is suggested or filled in for you. A story stays held, and she cannot see it, until you release it. Changing a story holds it again.',
            key: Key('storiesNote')),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        if (_loaded && _stories.isEmpty) const QuietNote('No stories yet.', icon: Icons.auto_stories_outlined),
        for (final WelcomeStory s in _stories)
          Card(
            key: Key('story_${s.id}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(child: Text(s.title, style: Theme.of(context).textTheme.titleMedium)),
                  Text(s.released ? 'Released' : 'Held', key: Key('storyState_${s.id}')),
                ]),
                Wrap(spacing: 8, children: <Widget>[
                  TextButton(key: Key('storyEdit_${s.id}'), onPressed: () => _edit(s), child: const Text('Edit')),
                  if (!s.released) FilledButton(key: Key('storyRelease_${s.id}'), onPressed: () => _release(s), child: const Text('Release to her')),
                  if (s.released)
                    OutlinedButton(
                        key: Key('storyHold_${s.id}'),
                        onPressed: () async {
                          report(await widget.service.holdStory(widget.principal, s.id));
                          await _load();
                        },
                        child: const Text('Hold it again')),
                  TextButton(
                      key: Key('storyRemove_${s.id}'),
                      onPressed: () async {
                        report(await widget.service.removeStory(widget.principal, s.id));
                        await _load();
                      },
                      child: const Text('Remove')),
                ]),
              ]),
            ),
          ),
        OutlinedButton.icon(key: const Key('storyAdd'), onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Write a story')),
      ]);
}

class StoryEditorScreen extends StatefulWidget {
  const StoryEditorScreen({super.key, required this.childName, required this.service, required this.principal, this.story});
  final String childName;
  final VillageService service;
  final FamilyPrincipal principal;
  final WelcomeStory? story;
  @override
  State<StoryEditorScreen> createState() => _StoryEditorState();
}

class _StoryEditorState extends State<StoryEditorScreen> with _Reporter<StoryEditorScreen> {
  final TextEditingController _title = TextEditingController();
  List<StoryPage> _pages = <StoryPage>[];
  late final String _id;

  @override
  void initState() {
    super.initState();
    _id = widget.story?.id ?? widget.service.newId('st');
    _title.text = widget.story?.title ?? '';
    _pages = <StoryPage>[...?widget.story?.pages];
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _addPage() async {
    if (_pages.length >= maxWelcomePages) return say(villageRefusalText('too_many_pages'));
    final String? pic = await pickVillagePicture(context, villagePictures);
    if (pic == null || !mounted) return;
    final String? text = await askText(context, 'What does this page say?', '', maxLength: maxWelcomePageChars);
    if (text == null || !mounted) return;
    try {
      setState(() => _pages = <StoryPage>[..._pages, StoryPage(picture: pic, text: cleanText(text, max: maxWelcomePageChars))]);
    } on RvRefused catch (e) {
      say(villageRefusalText(e.reason));
    }
  }

  Future<void> _save() async {
    final VillageResult r = await widget.service.saveStory(
        widget.principal, WelcomeStory(id: _id, title: _title.text, pages: _pages));
    report(r);
    if (r.ok && mounted) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Write a story', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        TextField(key: const Key('storyTitle'), controller: _title, maxLength: maxTitleChars,
            decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
        for (int i = 0; i < _pages.length; i++)
          Card(
            key: Key('storyPageRow_$i'),
            child: ListTile(
              leading: PictureGlyph(_pages[i].picture, size: 24), title: Text(_pages[i].text),
              trailing: IconButton(key: Key('storyPageRemove_$i'), tooltip: 'Remove page', icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _pages = <StoryPage>[for (int j = 0; j < _pages.length; j++) if (j != i) _pages[j]])),
            ),
          ),
        OutlinedButton.icon(key: const Key('storyPageAdd'), onPressed: _addPage, icon: const Icon(Icons.add), label: const Text('Add a page')),
        const SizedBox(height: 8),
        FilledButton(key: const Key('storySave'), onPressed: _save, child: const Text('Save (held until you release it)')),
      ]);
}

// ================================================================ siblings ===
class SiblingEditorScreen extends StatefulWidget {
  const SiblingEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final VillageService service;
  final FamilyPrincipal principal;
  @override
  State<SiblingEditorScreen> createState() => _SiblingEditorState();
}

class _SiblingEditorState extends State<SiblingEditorScreen> with _Reporter<SiblingEditorScreen> {
  List<SiblingSlot> _sibs = <SiblingSlot>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.service.loadForGuardian(widget.principal).then((VillageDoc d) {
      if (mounted) setState(() { _sibs = d.shelf.siblings; _loaded = true; });
    }).catchError((Object e) { deny(e); });
  }

  Future<void> _add() async {
    if (_sibs.length >= maxSiblings) return say(villageRefusalText('too_many_siblings'));
    final String? pic = await pickVillagePicture(context, facePictures);
    if (pic == null || !mounted) return;
    final String? name = await askText(context, 'Their name, as you write it', '');
    if (name == null || !mounted) return;
    try {
      setState(() => _sibs = <SiblingSlot>[..._sibs, SiblingSlot(id: widget.service.newId('b'), name: cleanText(name), picture: pic)]);
    } on RvRefused catch (e) {
      say(villageRefusalText(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Sibling shelf', children: <Widget>[
        _LocalOnlyNote(widget.childName, extra: 'Brothers and sisters who use this device leave each other pictures here.'),
        const SizedBox(height: 8),
        const Text('Names are exactly what you type. The shelf never shows how many pictures it holds, and keeps no record of who left one.', key: Key('shelfNote')),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        if (_loaded)
          for (final SiblingSlot s in _sibs)
            Card(
              key: Key('sibRow_${s.id}'),
              child: ListTile(
                leading: PictureGlyph(s.picture, size: 24), title: Text(s.name),
                trailing: IconButton(key: Key('sibRemove_${s.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _sibs = <SiblingSlot>[for (final SiblingSlot x in _sibs) if (x.id != s.id) x])),
              ),
            ),
        OutlinedButton.icon(key: const Key('sibAdd'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add a brother or sister')),
        const SizedBox(height: 8),
        FilledButton(key: const Key('sibSave'), onPressed: () async => report(await widget.service.saveSiblings(widget.principal, _sibs)), child: const Text('Save')),
        TextButton(
            key: const Key('sibClearPictures'),
            onPressed: () async => report(await widget.service.clearShelfPictures(widget.principal)),
            child: const Text('Take every picture down')),
      ]);
}

// ========================================================= passes (shared) ===
/// Lines of text, one per line: shows and parses a multi-line field.
class _LinesField extends StatelessWidget {
  const _LinesField({required super.key, required this.controller, required this.label, this.hint});
  final TextEditingController controller;
  final String label;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
            controller: controller, minLines: 2, maxLines: 6,
            decoration: InputDecoration(labelText: label, helperText: hint ?? 'One item on each line', border: const OutlineInputBorder())),
      );
}

List<String> _linesOf(TextEditingController c) => c.text.split('\n');

String _joined(List<String> l) => l.join('\n');

class _ContactsEditor extends StatelessWidget {
  const _ContactsEditor({required this.idPrefix, required this.contacts, required this.max, required this.onChanged, required this.newId});
  final String idPrefix;
  final List<PassContact> contacts;
  final int max;
  final ValueChanged<List<PassContact>> onChanged;
  final String Function(String prefix) newId;

  Future<void> _add(BuildContext context) async {
    final PassContact? c = await showDialog<PassContact>(context: context, builder: (BuildContext ctx) => _ContactDialog(id: newId('c')));
    if (c != null) onChanged(<PassContact>[...contacts, c]);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        const SizedBox(height: 8),
        Text('Who to reach', style: Theme.of(context).textTheme.titleMedium),
        for (final PassContact c in contacts)
          Card(
            key: Key('${idPrefix}Contact_${c.id}'),
            child: ListTile(
              title: Text(contactLine(c)),
              trailing: IconButton(key: Key('${idPrefix}ContactRemove_${c.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline),
                  onPressed: () => onChanged(<PassContact>[for (final PassContact x in contacts) if (x.id != c.id) x])),
            ),
          ),
        if (contacts.length < max)
          OutlinedButton.icon(key: Key('${idPrefix}ContactAdd'), onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('Add a person')),
      ]);
}

/// A plain, high-contrast, single-column page. Black on white at any theme, so a
/// photo of the screen or a printed copy reads the same. It states where it is
/// kept and when it was written; it adds no word of its own about the child.
class PassPageScreen extends StatelessWidget {
  const PassPageScreen({super.key, required this.heading, required this.header, required this.sections, this.writtenOn});
  final String heading;
  final List<String> header;
  final List<PassSection> sections;
  final String? writtenOn;

  @override
  Widget build(BuildContext context) {
    const TextStyle body = TextStyle(fontSize: 20, height: 1.35, color: Colors.black);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(heading), backgroundColor: Colors.white, foregroundColor: Colors.black),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(key: const Key('passPage'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(heading, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.black)),
            for (final String h in header)
              if (h.isNotEmpty) Text(h, style: body),
            if (sections.isEmpty) const Padding(padding: EdgeInsets.only(top: 16), child: Text('Nothing has been written yet.', key: Key('passEmpty'), style: body)),
            for (final PassSection s in sections) ...<Widget>[
              const SizedBox(height: 18),
              Text(s.heading, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black)),
              for (final String l in s.lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $l', style: body)),
            ],
            const SizedBox(height: 24),
            Text('Written by a grown-up${writtenOn == null ? '' : ' on $writtenOn'}. Kept on this device; shown only when it is held up.',
                key: const Key('passFooter'), style: const TextStyle(fontSize: 14, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}

// ============================================================== sitter pass ==
class SitterPassEditorScreen extends StatefulWidget {
  const SitterPassEditorScreen({super.key, required this.childName, required this.service, required this.principal, this.routineLines});
  final String childName;
  final VillageService service;
  final FamilyPrincipal principal;

  /// Where "copy from her routine" reads its step names (a guardian's own, from
  /// Rhythm). Null hides the button.
  final Future<List<String>> Function()? routineLines;
  @override
  State<SitterPassEditorScreen> createState() => _SitterEditorState();
}

class _SitterEditorState extends State<SitterPassEditorScreen> with _Reporter<SitterPassEditorScreen> {
  final TextEditingController _title = TextEditingController(text: 'Tonight');
  final TextEditingController _for = TextEditingController();
  final TextEditingController _when = TextEditingController();
  final TextEditingController _routine = TextEditingController();
  final TextEditingController _allergies = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  List<PassContact> _contacts = <PassContact>[];
  String? _writtenOn;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.service.loadPasses(widget.principal).then((PassesDoc d) {
      if (!mounted) return;
      final SitterPass? p = d.sitter;
      setState(() {
        if (p != null) {
          _title.text = p.title; _for.text = p.forWho; _when.text = p.when; _routine.text = _joined(p.routine);
          _allergies.text = _joined(p.allergies); _notes.text = _joined(p.notes); _contacts = <PassContact>[...p.contacts];
          _writtenOn = p.writtenOn;
        }
        _loaded = true;
      });
    }).catchError((Object e) { deny(e); });
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_title, _for, _when, _routine, _allergies, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  SitterPass _draft() => SitterPass(
      title: _title.text, forWho: _for.text, when: _when.text, routine: _linesOf(_routine), allergies: _linesOf(_allergies),
      notes: _linesOf(_notes), contacts: _contacts);

  Future<void> _save() async {
    final VillageResult r = await widget.service.saveSitterPass(widget.principal, _draft());
    report(r);
    if (r.ok) {
      final PassesDoc d = await widget.service.loadPasses(widget.principal);
      if (mounted) setState(() => _writtenOn = d.sitter?.writtenOn);
    }
  }

  void _show() {
    try {
      final SitterPass p = makeSitterPass(
          title: _title.text, forWho: _for.text, when: _when.text, routine: _linesOf(_routine),
          allergies: _linesOf(_allergies), notes: _linesOf(_notes), contacts: _contacts);
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PassPageScreen(
              heading: p.title, header: <String>[if (p.forWho.isNotEmpty) 'For ${p.forWho}', p.when],
              sections: sitterSections(p), writtenOn: _writtenOn ?? widget.service.today())));
    } on RvRefused catch (e) {
      say(villageRefusalText(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Sitter pass', children: <Widget>[
        _LocalOnlyNote(widget.childName, extra: 'It leaves this device only when you hold the screen up. No link is made and nobody is contacted.'),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        if (_loaded) ...<Widget>[
          TextField(key: const Key('sitterTitle'), controller: _title, maxLength: maxTitleChars, decoration: const InputDecoration(labelText: 'Page title', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(key: const Key('sitterFor'), controller: _for, maxLength: maxTitleChars, decoration: const InputDecoration(labelText: 'For (a name, optional)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(key: const Key('sitterWhen'), controller: _when, maxLength: maxTitleChars, decoration: const InputDecoration(labelText: 'When (words, optional)', border: OutlineInputBorder())),
          _LinesField(key: const Key('sitterAllergies'), controller: _allergies, label: 'Allergies, in your own words', hint: 'One on each line. The app adds and checks nothing.'),
          _LinesField(key: const Key('sitterRoutine'), controller: _routine, label: 'Routine'),
          if (widget.routineLines != null)
            TextButton(
                key: const Key('sitterCopyRoutine'),
                onPressed: () async {
                  final List<String> l = await widget.routineLines!();
                  if (mounted && l.isNotEmpty) setState(() => _routine.text = _joined(l));
                },
                child: const Text('Copy the step names from her routine')),
          _LinesField(key: const Key('sitterNotes'), controller: _notes, label: 'Good to know'),
          _ContactsEditor(idPrefix: 'sitter', contacts: _contacts, max: maxPassContacts, onChanged: (List<PassContact> c) => setState(() => _contacts = c), newId: widget.service.newId),
          const SizedBox(height: 8),
          FilledButton(key: const Key('sitterSave'), onPressed: _save, child: const Text('Save')),
          TextButton(key: const Key('sitterShow'), onPressed: _show, child: const Text('Show the page')),
          TextButton(
              key: const Key('sitterClear'),
              onPressed: () async {
                final VillageResult r = await widget.service.saveSitterPass(widget.principal, null);
                if (r.ok) {
                  setState(() {
                    _title.text = 'Tonight'; for (final TextEditingController c in <TextEditingController>[_for, _when, _routine, _allergies, _notes]) { c.clear(); }
                    _contacts = <PassContact>[]; _writtenOn = null;
                  });
                }
                report(r);
              },
              child: const Text('Clear this page')),
        ],
      ]);
}

// ============================================================ school bridge ==
class SchoolBridgeEditorScreen extends StatefulWidget {
  const SchoolBridgeEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final VillageService service;
  final FamilyPrincipal principal;
  @override
  State<SchoolBridgeEditorScreen> createState() => _SchoolEditorState();
}

class _SchoolEditorState extends State<SchoolBridgeEditorScreen> with _Reporter<SchoolBridgeEditorScreen> {
  final TextEditingController _school = TextEditingController();
  final TextEditingController _class = TextEditingController();
  final TextEditingController _helps = TextEditingController();
  final TextEditingController _allergies = TextEditingController();
  final TextEditingController _pickup = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  List<PassContact> _contacts = <PassContact>[];
  String? _writtenOn;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.service.loadPasses(widget.principal).then((PassesDoc d) {
      if (!mounted) return;
      final SchoolBridge? s = d.school;
      setState(() {
        if (s != null) {
          _school.text = s.school; _class.text = s.className; _helps.text = _joined(s.helps); _allergies.text = _joined(s.allergies);
          _pickup.text = _joined(s.pickup); _notes.text = _joined(s.notes); _contacts = <PassContact>[...s.contacts]; _writtenOn = s.writtenOn;
        }
        _loaded = true;
      });
    }).catchError((Object e) { deny(e); });
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_school, _class, _helps, _allergies, _pickup, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  SchoolBridge _draft() => SchoolBridge(
      school: _school.text, className: _class.text, helps: _linesOf(_helps), allergies: _linesOf(_allergies),
      pickup: _linesOf(_pickup), notes: _linesOf(_notes), contacts: _contacts);

  Future<void> _save() async {
    final VillageResult r = await widget.service.saveSchoolBridge(widget.principal, _draft());
    report(r);
    if (r.ok) {
      final PassesDoc d = await widget.service.loadPasses(widget.principal);
      if (mounted) setState(() => _writtenOn = d.school?.writtenOn);
    }
  }

  void _show() {
    try {
      final SchoolBridge s = makeSchoolBridge(
          school: _school.text, className: _class.text, helps: _linesOf(_helps), allergies: _linesOf(_allergies),
          pickup: _linesOf(_pickup), notes: _linesOf(_notes), contacts: _contacts);
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PassPageScreen(
              heading: s.school.isEmpty ? 'School summary' : s.school, header: <String>[s.className],
              sections: schoolSections(s), writtenOn: _writtenOn ?? widget.service.today())));
    } on RvRefused catch (e) {
      say(villageRefusalText(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'School summary', children: <Widget>[
        _LocalOnlyNote(widget.childName, extra: 'The school is not contacted and nothing arrives from it. You show or hand over this page.'),
        const SizedBox(height: 8),
        const Text('Write only what you want the school to read. Nothing about grades or behaviour is carried here.', key: Key('schoolNote')),
        const SizedBox(height: 8),
        if (denied) deniedNote,
        if (_loaded) ...<Widget>[
          TextField(key: const Key('schoolName'), controller: _school, maxLength: maxSchoolNameChars, decoration: const InputDecoration(labelText: 'School name (no address)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(key: const Key('schoolClass'), controller: _class, maxLength: maxTitleChars, decoration: const InputDecoration(labelText: 'Class or teacher (optional)', border: OutlineInputBorder())),
          _LinesField(key: const Key('schoolHelps'), controller: _helps, label: 'What helps'),
          _LinesField(key: const Key('schoolAllergies'), controller: _allergies, label: 'Allergies, in your own words'),
          _LinesField(key: const Key('schoolPickup'), controller: _pickup, label: 'Who collects her (names as you write them)', hint: 'Up to four lines'),
          _LinesField(key: const Key('schoolNotes'), controller: _notes, label: 'Good to know', hint: 'Up to four lines'),
          _ContactsEditor(idPrefix: 'school', contacts: _contacts, max: maxSchoolContacts, onChanged: (List<PassContact> c) => setState(() => _contacts = c), newId: widget.service.newId),
          const SizedBox(height: 8),
          FilledButton(key: const Key('schoolSave'), onPressed: _save, child: const Text('Save')),
          TextButton(key: const Key('schoolShow'), onPressed: _show, child: const Text('Show the page')),
          TextButton(
              key: const Key('schoolClear'),
              onPressed: () async {
                final VillageResult r = await widget.service.saveSchoolBridge(widget.principal, null);
                if (r.ok) {
                  setState(() {
                    for (final TextEditingController c in <TextEditingController>[_school, _class, _helps, _allergies, _pickup, _notes]) { c.clear(); }
                    _contacts = <PassContact>[]; _writtenOn = null;
                  });
                }
                report(r);
              },
              child: const Text('Clear this page')),
        ],
      ]);
}

/// The "who to reach" form. It owns its own controllers, so they live exactly as
/// long as the dialog does (including its closing animation).
class _ContactDialog extends StatefulWidget {
  const _ContactDialog({required this.id});
  final String id;
  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _rel = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _best = TextEditingController();

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _rel, _phone, _best]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Who to reach'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(key: const Key('contactName'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(key: const Key('contactRelation'), controller: _rel, decoration: const InputDecoration(labelText: 'Who they are to her (as you would write it)')),
            TextField(key: const Key('contactNumber'), controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
            TextField(key: const Key('contactBest'), controller: _best, decoration: const InputDecoration(labelText: 'Best times (optional)')),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
              key: const Key('contactOk'),
              onPressed: () => Navigator.of(context).pop(
                  PassContact(id: widget.id, name: _name.text, relation: _rel.text, number: _phone.text, bestTimes: _best.text)),
              child: const Text('Add')),
        ],
      );
}
