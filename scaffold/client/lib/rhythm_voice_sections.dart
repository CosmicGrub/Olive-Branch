// OLIVE BRANCH — the Rhythm and Voice tiles in the child's "More for you" hub.
// No longer UNVERIFIED — verified by CI (client/test/rhythm_voice_sections_test.dart).
//
// The tiles are the shared TieredTile (64dp floor, picture-first), shown ONLY
// when rhythm_voice_gate.dart's `tilesFor` says so: the family-structure model's
// age band and More hub, the guardian's two suite switches, and (for what a
// guardian must author) that it has been authored. Until the device has been
// read, nothing is shown, so a tile never flashes in and out.
//
// This file is part of the child shell: it never reaches a guardian screen.
import 'package:flutter/material.dart';

import 'family_structure_store.dart' show FamilyChildSnapshot;
import 'hub_widgets.dart';
import 'picture_icons.dart';
import 'rhythm_logic.dart';
import 'rhythm_screens.dart';
import 'rhythm_voice_gate.dart';
import 'rhythm_voice_repositories.dart';
import 'tiered_tile.dart';
import 'voice_logic.dart';
import 'voice_screens.dart';

class _Loaded {
  const _Loaded(this.rhythm, this.voice, this.place);
  final RhythmDoc rhythm;
  final VoiceDoc voice;
  final PlacePlan? place;
}

class RhythmVoiceSections extends StatefulWidget {
  const RhythmVoiceSections({super.key, required this.service, this.family, this.yearsOld, this.speak});
  final RhythmVoiceService service;

  /// The family-structure model's derived view for her; null when none has been
  /// built (then the age comes from [yearsOld], failing closed to five).
  final FamilyChildSnapshot? family;
  final int? yearsOld;
  final Speak? speak;

  @override
  State<RhythmVoiceSections> createState() => _RhythmVoiceSectionsState();
}

class _RhythmVoiceSectionsState extends State<RhythmVoiceSections> {
  _Loaded? _l;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = childPrincipalFor(widget.service);
      final _Loaded l = _Loaded(await widget.service.loadRhythm(me), await widget.service.loadVoice(me),
          await widget.service.loadPlace(me));
      if (mounted) setState(() => _l = l);
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
    final _Loaded? l = _l;
    if (l == null) return const SizedBox.shrink();
    final RhythmVoiceTiles t = tilesFor(
      view: widget.family?.view, yearsOld: widget.yearsOld,
      rhythmOn: l.rhythm.suiteOn, voiceOn: l.voice.suiteOn,
      routine: l.rhythm.routine, board: l.rhythm.board, packing: l.rhythm.packing,
      place: l.place, helpers: l.voice.helpers,
    );
    final RhythmVoiceService s = widget.service;
    final Speak? sp = widget.speak;
    // TieredTile outside a grid needs an explicit height; it grows with the text size
    // so a long label at large text never overflows its tile.
    // At large text the tiles go one to a row, so a long label has the width it needs.
    final double scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.2);
    final bool single = scale >= 1.3;
    final double h = single ? 72 + 30 * scale : 56 + 64 * scale;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      if (t.anyRhythm)
        HubSection(title: 'My day', children: <Widget>[
          _Grid(single: single, children: <Widget>[
            if (t.routine)
              TieredTile(key: const Key('rvTile_routine'), icon: Icons.checklist_outlined,
                  label: l.rhythm.routine!.title, height: h,
                  onTap: (_) => _open(MyRoutineScreen(service: s, speak: sp))),
            if (t.firstThen)
              TieredTile(key: const Key('rvTile_firstThen'), icon: Icons.swap_horiz, label: 'First, then', height: h,
                  onTap: (_) => _open(FirstThenScreen(service: s, speak: sp))),
            if (t.packingBuddy)
              TieredTile(key: const Key('rvTile_packing'), icon: Icons.backpack_outlined, label: 'My bag', height: h,
                  onTap: (_) => _open(PackingBuddyScreen(service: s, speak: sp))),
            if (t.newPlace)
              TieredTile(key: const Key('rvTile_newPlace'), icon: Icons.home_outlined, label: l.place!.name, height: h,
                  onTap: (_) => _open(NewPlaceScreen(service: s, speak: sp))),
          ]),
        ]),
      if (t.anyVoice)
        HubSection(title: 'My voice', children: <Widget>[
          _Grid(single: single, children: <Widget>[
            if (t.weather)
              TieredTile(key: const Key('rvTile_weather'), icon: Icons.wb_cloudy_outlined, label: 'The sky in me', height: h,
                  onTap: (_) => _open(FeelingsWeatherScreen(service: s, speak: sp))),
            if (t.worryBox)
              TieredTile(key: const Key('rvTile_worry'), icon: Icons.inventory_2_outlined, label: 'Worry box', height: h,
                  onTap: (_) => _open(WorryBoxScreen(service: s, speak: sp))),
            if (t.helpers)
              TieredTile(key: const Key('rvTile_helpers'), icon: Icons.people_outline, label: 'My helpers', height: h,
                  onTap: (_) => _open(MyHelpersScreen(service: s, speak: sp))),
            if (t.symbols)
              TieredTile(key: const Key('rvTile_symbols'), icon: Icons.record_voice_over_outlined,
                  label: 'Say it with pictures', height: h,
                  onTap: (_) => _open(SymbolBoardScreen(service: s, speak: sp))),
          ]),
        ]),
    ]);
  }
}

/// Two tiles to a row, wrapping; one column on the narrowest screens.
class _Grid extends StatelessWidget {
  const _Grid({required this.children, required this.single});
  final List<Widget> children;
  final bool single;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        const double gap = 10;
        final int cols = single || c.maxWidth < 300 ? 1 : 2;
        final double w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: <Widget>[
          for (final Widget ch in children) SizedBox(width: w, child: ch),
        ]);
      });
}
