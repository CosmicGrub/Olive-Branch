// OLIVE BRANCH — the Feelings corner: one calm page that gathers her feelings tools. No longer UNVERIFIED —
// verified by CI (client/test/feelings_corner_test.dart). Prototype k.feel; parity row 310; MASTERFILE section 8.17.
//
// The prototype groups four picture-led rows under one "Feelings" page: the sky she feels (weather), the worry box,
// her helpers and her symbols. Those four screens already exist (voice_screens.dart); this page is only the doorway.
// It shows exactly the rows rhythm_voice_gate.dart's [tilesFor] says she has, and the page is offered only when she
// has at least one (a guardian's Voice switch is off until they turn it on, so by default there is no Feelings tile
// and nothing here is reachable).
//
// Not here, on purpose: the prototype's "Tell a grown-up" list of video-call buttons. Calls go over the network, which
// is parked; a button that cannot place a call would be a fake success. Showing a worry to a grown-up stays where it
// has always been, inside the Worry box ("show my grown-up" or "float away").
//
// P1 / P2 / P7: no number, count, streak or score on this page; the weather she picks is never shown to anyone and
// has no history; what she puts in the worry box is shown to a grown-up only if she chooses. Rows are read-aloud
// capable and clear the child's 64 dp floor (HubTile).
import 'package:flutter/material.dart';

import 'family_structure_store.dart' show FamilyChildSnapshot;
import 'hub_widgets.dart';
import 'picture_icons.dart' show Speak;
import 'rhythm_screens.dart' show childPrincipalFor;
import 'rhythm_voice_gate.dart';
import 'rhythm_voice_repositories.dart';
import 'voice_screens.dart';

/// Which of her four feelings tools she has right now. Fails closed: an unreadable device has none.
Future<RhythmVoiceTiles> feelingsToolsFor({
  required RhythmVoiceService service,
  FamilyChildSnapshot? family,
  int? yearsOld,
}) async {
  try {
    final me = childPrincipalFor(service);
    final rhythm = await service.loadRhythm(me);
    final voice = await service.loadVoice(me);
    return tilesFor(
        view: family?.view, yearsOld: yearsOld,
        rhythmOn: rhythm.suiteOn, voiceOn: voice.suiteOn, twoHomesSetting: rhythm.twoHomes,
        helpers: voice.helpers);
  } catch (_) {
    return RhythmVoiceTiles.none;
  }
}

class FeelingsCornerScreen extends StatefulWidget {
  const FeelingsCornerScreen({super.key, required this.service, this.family, this.yearsOld, this.speak});
  final RhythmVoiceService service;
  final FamilyChildSnapshot? family;
  final int? yearsOld;
  final Speak? speak;

  @override
  State<FeelingsCornerScreen> createState() => _FeelingsCornerScreenState();
}

class _FeelingsCornerScreenState extends State<FeelingsCornerScreen> {
  RhythmVoiceTiles? _t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final RhythmVoiceTiles t =
        await feelingsToolsFor(service: widget.service, family: widget.family, yearsOld: widget.yearsOld);
    if (mounted) setState(() => _t = t);
  }

  void _open(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final RhythmVoiceTiles? t = _t;
    final RhythmVoiceService s = widget.service;
    final Speak? sp = widget.speak;
    return Scaffold(
      appBar: AppBar(title: const Text('Feelings')),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: t == null
                          ? const SizedBox.shrink()
                          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                              Text('Whatever you feel is okay. Pick what helps.', style: Theme.of(context).textTheme.bodyLarge),
                              const SizedBox(height: 8),
                              if (t.weather)
                                HubTile(
                                    key: const Key('feelWeather'), readAloud: true, icon: Icons.wb_cloudy_outlined,
                                    title: 'The sky in me', subtitle: 'Pick the sky that feels like you',
                                    onTap: () => _open(FeelingsWeatherScreen(service: s, speak: sp))),
                              if (t.worryBox)
                                HubTile(
                                    key: const Key('feelWorry'), readAloud: true, icon: Icons.inventory_2_outlined,
                                    title: 'Worry box', subtitle: 'Put a worry in the box',
                                    onTap: () => _open(WorryBoxScreen(service: s, speak: sp))),
                              if (t.helpers)
                                HubTile(
                                    key: const Key('feelHelpers'), readAloud: true, icon: Icons.people_outline,
                                    title: 'My helpers', subtitle: 'People who help',
                                    onTap: () => _open(MyHelpersScreen(service: s, speak: sp))),
                              if (t.symbols)
                                HubTile(
                                    key: const Key('feelSymbols'), readAloud: true, icon: Icons.record_voice_over_outlined,
                                    title: 'Say it with pictures', subtitle: 'Tap to talk',
                                    onTap: () => _open(SymbolBoardScreen(service: s, speak: sp))),
                            ]))))),
    );
  }
}
