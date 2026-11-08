// OLIVE BRANCH — her colour, the child's side. No longer UNVERIFIED — verified
// by CI (a Flutter toolchain runs for real in tools/verify.sh's automated
// pipeline). MASTERFILE §8.6.3, §8.6.5, §8.6.2, §8.1, P2.
//
// What opens from "Today's colour" on her More screen. If today's one question
// has not been answered it is asked first (ColourDailyScreen, the two-up whose
// one side is always her current colour). Answering ends the question for the
// day. Then she lands here: her colour stated as a plain fact, the art style
// she can look at pictures in, and the colour activities her age allows.
//
// Her colour is an ACCENT, never a theme: HerColourAccent asks applyColour()
// for a stripe, a ring and a flourish, and the budget (max three, never a
// surface, never an emotion label) is enforced there. Nothing on this screen
// says what her colour means; it says what it is.
//
// There is no control on this screen for anything a guardian decides. She
// chooses her colour and, among the styles her guardian allows, how pictures
// look while she plays; the rest is not hers to see (§8.1).
import 'package:flutter/material.dart';
import 'colour_activities_logic.dart';
import 'colour_critter_screen.dart';
import 'colour_daily.dart';
import 'colour_day_logic.dart';
import 'colour_sort_screen.dart';
import 'her_colour_accent.dart';
import 'her_colour_art.dart';
import 'her_colour_store.dart';
import 'hub_widgets.dart';
import 'path_code_screen.dart';
import 'palette_logic.dart';
import 'pixel_garden_screen.dart';

/// The colour used for a child who has none yet: the app looks as it always did,
/// and the activities simply use this one.
const String fallbackColourId = 'sea';

/// The places her colour is asked to appear on this screen (the budget decides).
const List<String> homePlacements = ['accent_stripe', 'avatar_ring', 'header_flourish'];

class HerColourScreen extends StatefulWidget {
  const HerColourScreen({super.key, required this.childName, required this.childAge, this.store,
    this.random});

  final String childName;
  final int childAge;
  /// Null uses the process-wide in-memory store.
  final ChildColourStore? store;
  final double Function()? random;

  @override
  State<HerColourScreen> createState() => _HerColourScreenState();
}

class _HerColourScreenState extends State<HerColourScreen> {
  late final ChildColourStore _store = widget.store ?? sharedColourStore;
  TodayColour? _today;
  ArtSettings _art = defaultArtSettings;
  String? _style;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await _store.today();
    final a = await _store.artStyle();
    if (!mounted) return;
    setState(() { _today = t; _art = a; _style ??= a.artStyle; _loading = false; });
  }

  Future<void> _answer(String id) async {
    final t = await _store.answer(id);
    if (!mounted) return;
    setState(() => _today = t);
  }

  void _open(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final today = _today;
    if (_loading || today == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (today.ask) {
      return ColourDailyScreen(
        currentColourId: today.colourId ?? fallbackColourId, onChoose: _answer, random: widget.random);
    }
    final sw = today.swatch ?? swatchFor(fallbackColourId)!;
    final accent = HerColourAccent.of(today.swatch?.id, homePlacements);
    final style = _art.allowedStyles.contains(_style) ? _style! : _art.artStyle;
    final acts = activitiesFor(age: widget.childAge, codeActivities: _art.codeActivities);
    final label = '${sw.label[0].toUpperCase()}${sw.label.substring(1)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your colour'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(4), child: AccentStripe(accent: accent))),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AccentRing(accent: accent, child: CircleAvatar(
              key: const Key('colourSwatch'), radius: 34, backgroundColor: sw.color)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(today.swatch == null ? 'No colour yet' : 'Today your colour is',
                style: Theme.of(context).textTheme.bodyMedium),
              Row(children: [
                Flexible(child: Text(today.swatch == null ? 'Pick one any time.' : label,
                  key: const Key('colourName'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                if (accent.has('header_flourish')) Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.auto_awesome, key: const Key('colourFlourish'), size: 18, color: accent.color)),
              ]),
            ])),
          ]),
          const SizedBox(height: 20),
          Text('Pictures look like', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final s in _art.allowedStyles) ChoiceChip(
              key: Key('homeStyle_$s'), label: Text(styleName(s)),
              selected: style == s, onSelected: (_) => setState(() => _style = s)),
          ]),
          const SizedBox(height: 12),
          Center(child: ColourArt(key: const Key('homeSample'), recipe: 'round', color: sw.color, style: style, size: 96,
            semanticLabel: 'A sample picture in ${styleName(style)} style')),
          const SizedBox(height: 16),
          for (final a in acts) HubTile(
            key: Key('activity_${a.id}'),
            icon: switch (a.id) {
              'sort' => Icons.category_outlined, 'path' => Icons.route_outlined,
              'critter' => Icons.pets_outlined, _ => Icons.grid_on_outlined },
            title: a.name,
            subtitle: switch (a.id) {
              'sort' => 'Find things that are ${sw.label}',
              'path' => 'Write the steps, press Run',
              'critter' => 'Colour in an animal',
              _ => 'Plant a pixel garden' },
            onTap: () => _open(switch (a.id) {
              'sort' => ColourSortScreen(swatch: sw, style: style),
              'path' => PathCodeScreen(swatch: sw, style: style, age: widget.childAge),
              'critter' => ColourCritterScreen(swatch: sw, allowedStyles: _art.allowedStyles, initialStyle: style),
              _ => PixelGardenScreen(swatch: sw, age: widget.childAge, codeActivities: _art.codeActivities),
            })),
        ]),
      )),
    );
  }
}
