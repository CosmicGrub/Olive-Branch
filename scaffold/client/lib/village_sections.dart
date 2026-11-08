// OLIVE BRANCH — the Village tiles in the child's "More for you" hub. No longer
// UNVERIFIED — verified by CI (client/test/village_sections_test.dart).
//
// The tiles are the shared TieredTile (64dp floor, picture-first), shown ONLY when
// village_logic.dart's `villageTilesFor` says so: the family-structure model's age
// band, More hub and `people` area mode, the guardian's Village switch, and (for
// what a guardian must author) that it has been authored and, for a story,
// RELEASED. Until the device has been read nothing is shown, so a tile never
// flashes in and out.
//
// This file is part of the child shell: it never reaches a guardian screen, and
// the sitter pass, the school summary and the grandparent page have no tile here.
// It reads only through the service's child-side methods, so a held story is
// never even loaded here.
import 'package:flutter/material.dart';

import 'access_scope.dart' show AccessScope;
import 'family_structure_store.dart' show FamilyChildSnapshot;
import 'hub_widgets.dart';
import 'picture_icons.dart';
import 'tiered_tile.dart';
import 'village_logic.dart';
import 'village_repositories.dart';
import 'village_screens.dart';

class VillageSections extends StatefulWidget {
  const VillageSections({super.key, required this.service, this.family, this.yearsOld, this.speak});
  final VillageService service;

  /// The family-structure model's derived view for her; null when none has been
  /// built (then the age comes from [yearsOld], failing closed to five).
  final FamilyChildSnapshot? family;
  final int? yearsOld;
  final Speak? speak;

  @override
  State<VillageSections> createState() => _VillageSectionsState();
}

class _VillageSectionsState extends State<VillageSections> {
  VillageDoc? _doc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // The child's own narrow reads: suite state, released stories, shelf.
      final me = villageChildPrincipal(widget.service);
      final bool on = await widget.service.suiteOn(me);
      final List<WelcomeStory> stories = on ? await widget.service.releasedStories(me) : const <WelcomeStory>[];
      final ChildShelfView shelf =
          on ? await widget.service.shelf(me) : const ChildShelfView(<SiblingSlot>[], <ShelfNote>[]);
      final VillageDoc d = VillageDoc(suiteOn: on, stories: stories, shelf: SiblingShelf(siblings: shelf.siblings));
      if (mounted) setState(() => _doc = d);
    } catch (_) {
      // an unreadable device shows no tiles rather than a broken screen
    }
  }

  Future<void> _open(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final VillageDoc? d = _doc;
    if (d == null) return const SizedBox.shrink();
    final VillageTiles t =
        villageTilesFor(view: widget.family?.view, yearsOld: widget.yearsOld, suiteOn: d.suiteOn, doc: d);
    if (!t.any) return const SizedBox.shrink();
    final VillageService s = widget.service;
    final Speak? sp = widget.speak;
    final double scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.2);
    final bool single = scale >= 1.3;
    final double roomy = AccessScope.of(context).roomierReading ? 1.25 : 1.0;
    final double h = (single ? 72 + 30 * scale : 56 + 64 * scale) * roomy + 30;
    final Map<String, WelcomeStory> byId = <String, WelcomeStory>{for (final WelcomeStory x in d.stories) x.id: x};
    return HubSection(title: 'My village', children: <Widget>[
      LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        const double gap = 10;
        final int cols = single || c.maxWidth < 300 ? 1 : 2;
        final double w = (c.maxWidth - gap * (cols - 1)) / cols;
        final List<Widget> tiles = <Widget>[
          if (t.familyTree)
            TieredTile(
                key: const Key('vilTile_tree'), icon: Icons.diversity_3_outlined, label: 'Faces of my people', height: h,
                onTap: (_) => _open(FamilyTreeScreen(service: s, snapshot: widget.family!, speak: sp))),
          for (final String id in t.stories)
            TieredTile(
                key: Key('vilTile_story_$id'), icon: Icons.auto_stories_outlined, label: byId[id]!.title, height: h,
                onTap: (_) => _open(WelcomeStoryScreen(service: s, storyId: id, speak: sp))),
          if (t.siblings)
            TieredTile(
                key: const Key('vilTile_shelf'), icon: Icons.photo_library_outlined, label: 'Our shelf', height: h,
                onTap: (_) => _open(SiblingSpaceScreen(service: s, speak: sp))),
        ];
        return Wrap(spacing: gap, runSpacing: gap, children: <Widget>[
          for (final Widget ch in tiles) SizedBox(width: w, child: ch),
        ]);
      }),
    ]);
  }
}
