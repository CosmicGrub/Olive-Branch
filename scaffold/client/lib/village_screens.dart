// OLIVE BRANCH — suite D VILLAGE, the child's screens: her people in pictures, a
// story a grown-up chose to release, and the sibling shelf. No longer UNVERIFIED —
// verified by CI (client/test/village_screens_test.dart).
//
// Picture-first (she is five going on six), every target at least 64dp, calm.
// OFFLINE AND ON-DEVICE: these screens read what a guardian wrote on THIS device.
// There is no editor here (the child shell has no settings, §8.1); the guardian
// side is village_guardian_screens.dart, which this file never imports.
//
// What she can never reach from here: the sitter pass, the school summary and the
// grandparent page (guardian side only, and the service has no child reader for
// them), and any story a guardian has not released. No screen shows a count, a bar,
// a star or a streak (P2); the sibling shelf never says how many pictures it holds.
// Her people's NAMES are the ones a guardian chose in the family builder, as the
// model derived them; this file adds no role word, no "step", no "new".
// Read-aloud is the optional `speak` seam (see picture_icons.dart), falling back to
// the app's own read-aloud when it is on for her.
import 'package:flutter/material.dart';

import 'compass_logic.dart' show AlertKind;
import 'family_structure_logic.dart' show ChildPerson, ChildPlace, FamilyPrincipal;
import 'family_structure_store.dart' show FamilyChildSnapshot;
import 'picture_icons.dart';
import 'picture_library.dart';
import 'read_aloud.dart' show ReadAloudScope;
import 'village_logic.dart';
import 'village_repositories.dart';
import 'visual_alert.dart';

/// The principal a child screen acts as: this child, on this device.
FamilyPrincipal villageChildPrincipal(VillageService s) => FamilyPrincipal(roleName: 'child', childId: s.childId);

Speak? _speakOf(BuildContext context, Speak? explicit) => explicit ?? ReadAloudScope.speakFnIfEnabled(context);

class _ChildPage extends StatelessWidget {
  const _ChildPage({required this.title, required this.body});
  final String title;
  final Widget body;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body)),
      );
}

class _SpeakerButton extends StatelessWidget {
  const _SpeakerButton({required this.label, required this.speak});
  final String label;
  final Speak speak;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 48, height: 48,
      child: IconButton(tooltip: 'Hear $label', icon: const Icon(Icons.volume_up_outlined), onPressed: () => speak(label)));
}

// ============================================================ MY PEOPLE =====
/// Her people, drawn the way a guardian arranged them in the family builder:
/// grouped by home, a face and the name she uses. Tap a face to hear the name.
class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({super.key, required this.service, required this.snapshot, this.speak});
  final VillageService service;
  final FamilyChildSnapshot snapshot;
  final Speak? speak;
  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeState();
}

class _FamilyTreeState extends State<FamilyTreeScreen> {
  Map<String, String> _faces = const <String, String>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.service.faces(villageChildPrincipal(widget.service)).then((Map<String, String> f) {
      if (mounted) setState(() { _faces = f; _loaded = true; });
    }).catchError((Object _) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<ChildPlace> places = widget.snapshot.view.places;
    final Speak? speak = _speakOf(context, widget.speak);
    return _ChildPage(
      title: 'My people',
      body: !_loaded
          ? const SizedBox.shrink()
          : places.isEmpty
              ? const QuietNote('Nobody is here yet.', icon: Icons.people_outline)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  for (final ChildPlace pl in places) _place(context, pl, speak),
                ]),
    );
  }

  Widget _place(BuildContext context, ChildPlace pl, Speak? speak) => Padding(
        key: Key('treePlace_${pl.id}'),
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(pl.kind == 'home' ? Icons.home_outlined : Icons.favorite_border, size: 32),
            const SizedBox(width: 10),
            Expanded(child: Text(pl.name, style: Theme.of(context).textTheme.titleLarge)),
            if (speak != null) _SpeakerButton(label: pl.name, speak: speak),
          ]),
          const SizedBox(height: 10),
          PictureGrid(minTile: 104, children: <Widget>[
            for (final ChildPerson p in pl.people) _Face(person: p, picture: _faces[p.id], speak: speak),
          ]),
        ]),
      );
}

class _Face extends StatelessWidget {
  const _Face({required this.person, required this.picture, required this.speak});
  final ChildPerson person;
  final String? picture;
  final Speak? speak;
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    final Widget face = picture != null
        ? PictureGlyph(picture!, size: 44)
        : CircleAvatar(
            radius: 32, backgroundColor: c.primaryContainer,
            child: Text(person.name.characters.first.toUpperCase(),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: c.onPrimaryContainer)));
    return Semantics(
      button: true, label: person.name,
      child: Material(
        key: Key('face_${person.id}'),
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: speak == null ? null : () => speak!(person.name),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                ExcludeSemantics(child: face),
                const SizedBox(height: 6),
                Text(person.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================== A STORY FOR HER ==
/// A picture story a guardian released. One page at a time, Back and Next, and a
/// calm Done at the end; no "page 2 of 6".
class WelcomeStoryScreen extends StatefulWidget {
  const WelcomeStoryScreen({super.key, required this.service, required this.storyId, this.speak});
  final VillageService service;
  final String storyId;
  final Speak? speak;
  @override
  State<WelcomeStoryScreen> createState() => _WelcomeStoryState();
}

class _WelcomeStoryState extends State<WelcomeStoryScreen> {
  WelcomeStory? _story;
  bool _loaded = false;
  int _at = 0;

  @override
  void initState() {
    super.initState();
    widget.service.releasedStories(villageChildPrincipal(widget.service)).then((List<WelcomeStory> all) {
      WelcomeStory? s;
      for (final WelcomeStory x in all) {
        if (x.id == widget.storyId) s = x;
      }
      if (mounted) setState(() { _story = s; _loaded = true; });
    }).catchError((Object _) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final WelcomeStory? s = _story;
    return _ChildPage(
      title: s?.title ?? 'A story',
      body: !_loaded
          ? const SizedBox.shrink()
          : s == null
              ? const QuietNote('This story is not here.', icon: Icons.auto_stories_outlined)
              : _page(context, s),
    );
  }

  Widget _page(BuildContext context, WelcomeStory s) {
    final StoryPage p = s.pages[_at];
    final Speak? speak = _speakOf(context, widget.speak);
    final ColorScheme c = Theme.of(context).colorScheme;
    final bool last = _at == s.pages.length - 1;
    return Column(key: Key('storyPage_$_at'), crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Container(
        height: 200, alignment: Alignment.center,
        decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(22)),
        child: Icon(pictureIcon(p.picture), size: 96, color: c.onPrimaryContainer, semanticLabel: pictureLabel(p.picture)),
      ),
      const SizedBox(height: 14),
      Row(children: <Widget>[
        Expanded(child: Text(p.text, key: const Key('storyText'), style: Theme.of(context).textTheme.headlineSmall)),
        if (speak != null) _SpeakerButton(label: p.text, speak: speak),
      ]),
      const SizedBox(height: 18),
      Row(children: <Widget>[
        if (_at > 0)
          Expanded(child: SizedBox(height: 64, child: OutlinedButton.icon(
              key: const Key('storyBack'), onPressed: () => setState(() => _at--),
              icon: const Icon(Icons.arrow_back), label: const Text('Back')))),
        if (_at > 0) const SizedBox(width: 12),
        Expanded(child: SizedBox(height: 64, child: FilledButton.icon(
            key: Key(last ? 'storyDone' : 'storyNext'),
            onPressed: () => last ? Navigator.of(context).maybePop() : setState(() => _at++),
            icon: Icon(last ? Icons.check : Icons.arrow_forward), label: Text(last ? 'All done' : 'Next')))),
      ]),
    ]);
  }
}

// ============================================================ SIBLING SHELF ==
class SiblingSpaceScreen extends StatefulWidget {
  const SiblingSpaceScreen({super.key, required this.service, this.speak});
  final VillageService service;
  final Speak? speak;
  @override
  State<SiblingSpaceScreen> createState() => _SiblingSpaceState();
}

class _SiblingSpaceState extends State<SiblingSpaceScreen> {
  ChildShelfView _view = const ChildShelfView(<SiblingSlot>[], <ShelfNote>[]);
  bool _loaded = false;
  ScaffoldMessengerState? _messenger;

  FamilyPrincipal get _me => villageChildPrincipal(widget.service);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final ScaffoldMessengerState? m = _messenger;
    if (m != null) clearAlertCues(m);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ChildShelfView v = await widget.service.shelf(_me);
      if (mounted) setState(() { _view = v; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _leave(SiblingSlot to) async {
    final String? pic = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('A picture for ${to.name}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: PictureGrid(minTile: 96, children: <Widget>[
              for (final PictureDef p in <PictureDef>[for (final PictureGroup g in <PictureGroup>[PictureGroup.thing, PictureGroup.weather, PictureGroup.symbolExtra]) ...picturesIn(g)])
                PictureTile(key: Key('shelfPick_${p.id}'), picture: p.id, label: p.label, minHeight: 88,
                    speak: _speakOf(context, widget.speak), onTap: () => Navigator.of(ctx).pop(p.id)),
            ]),
          ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Not now'))],
      ),
    );
    if (pic == null || !mounted) return;
    final VillageResult r = await widget.service.leavePicture(_me, to.id, pic);
    await _load();
    if (mounted && r.ok) showAlertCue(context, AlertKind.pictureLeft);
  }

  Future<void> _takeDown(ShelfNote n) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Take this picture down?'),
        content: Center(heightFactor: 1, child: PictureGlyph(n.picture, size: 56)),
        actions: <Widget>[
          SizedBox(height: 64, child: TextButton(key: const Key('shelfKeep'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it'))),
          SizedBox(height: 64, child: FilledButton(key: const Key('shelfTakeDown'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Take it down'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await widget.service.takeDownPicture(_me, n.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final Speak? speak = _speakOf(context, widget.speak);
    return _ChildPage(
      title: 'Our shelf',
      body: !_loaded
          ? const SizedBox.shrink()
          : _view.siblings.isEmpty
              ? const QuietNote('Your grown-up has not set this up yet.', icon: Icons.photo_library_outlined)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  for (final SiblingSlot s in _view.siblings) _slot(context, s, speak),
                ]),
    );
  }

  Widget _slot(BuildContext context, SiblingSlot s, Speak? speak) {
    final ColorScheme c = Theme.of(context).colorScheme;
    final List<ShelfNote> notes = _view.notesFor(s.id);
    return Container(
      key: Key('shelfSlot_${s.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          PictureGlyph(s.picture, size: 36),
          const SizedBox(width: 12),
          Expanded(child: Text(s.name, style: Theme.of(context).textTheme.titleLarge)),
          if (speak != null) _SpeakerButton(label: s.name, speak: speak),
        ]),
        const SizedBox(height: 10),
        if (notes.isNotEmpty)
          Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
            for (final ShelfNote n in notes)
              Semantics(
                button: true, label: '${pictureLabel(n.picture)}, take it down',
                child: InkWell(
                  key: Key('shelfNote_${n.id}'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _takeDown(n),
                  child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 76, minHeight: 76), child: Center(child: PictureGlyph(n.picture, size: 40))),
                ),
              ),
          ]),
        if (notes.isNotEmpty) const SizedBox(height: 10),
        SizedBox(height: 64, child: FilledButton.icon(
            key: Key('shelfLeave_${s.id}'), onPressed: () => _leave(s),
            icon: const Icon(Icons.add_photo_alternate_outlined), label: Text('Leave a picture for ${s.name}'))),
      ]),
    );
  }
}
