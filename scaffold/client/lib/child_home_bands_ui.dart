// OLIVE BRANCH — the 5-7 and 8-12 child homes, the per-band More page, the 'your home grows' page and the
// local-midnight clock. No longer UNVERIFIED — verified by CI (client/test/child_home_bands_ui_test.dart and
// client/test/child_home_bands_postures_test.dart). Prototype: mod-child.js homeT57 / homeT812 / growPage /
// k.more; round-3 mockups r3a-57-* and r3a-812-*. MASTERFILE §8.1 and §8.2.
//
// What is drawn comes from the TABLE (child_home_bands.dart: layout, renames, More list), which a test holds
// equal to the prototype's own render. This file only turns ids into tiles and routes a tap to a destination
// the CALLER supplies ([BandDestination]), so ChildHome keeps every route it already owned and a tile whose
// destination does not exist is never drawn.
//
// Invariants kept (each one has a test):
//   - No settings affordance at any depth (§8.1) and no count, score, streak, reward or trophy (P1-P11): the only
//     number on any of these screens is her own age on the 'your home grows' eyebrow.
//   - A tile marks news with a DOT, never a number. Messages is never hidden.
//   - Posture: the foldCover cover screen shows the Hero (or the weeks strip) and ONE More tile, as before;
//     every other posture shows the whole home. Rows size to their tallest tile, so 2.0x text grows tiles, it
//     does not overflow them. No fixed pixel heights.
//   - Offline: nothing here asks a server anything.
import 'dart:async';

import 'package:flutter/material.dart';

import 'access_scope.dart';
import 'child_home_bands.dart';
import 'child_home_growth.dart';
import 'cover_collapse.dart';
import 'grownup_labels.dart';
import 'tiered_tile.dart';
import 'ui/olive_art.dart';
import 'ui/olive_base.dart';
import 'ui/olive_palette.dart';
import 'ui/olive_surfaces.dart';

/// The screen a tile opens, or null when there is none (the tile is then not drawn). Built lazily, on tap.
typedef BandDestination = Widget? Function(BuildContext context, String tileId);

/// The prototype's icon names -> the Material icons the shipped child shell already uses.
IconData bandIcon(String proto) => switch (proto) {
      'users' => Icons.people_outline,
      'book' => Icons.menu_book_outlined,
      'palette' => Icons.palette_outlined,
      'calendar' => Icons.calendar_today_outlined,
      'dice' => Icons.extension,
      'chat' => Icons.mail_outline,
      'camera' => Icons.photo_camera_outlined,
      'more' => Icons.more_horiz,
      'list' => Icons.star_border,
      'pencil' => Icons.edit_outlined,
      'smile' => Icons.sentiment_satisfied_alt_outlined,
      'heart' => Icons.favorite_outline,
      'hourglass' => Icons.hourglass_empty,
      'leaf' => Icons.straighten,
      'brush' => Icons.brush_outlined,
      'mic' => Icons.auto_stories_outlined,
      'sparkle' => Icons.auto_awesome_outlined,
      'shield' => Icons.shield_outlined,
      'key' => Icons.timeline_outlined,
      'hand' => Icons.back_hand_outlined,
      'image' => Icons.photo_library_outlined,
      'check' => Icons.check_circle_outline,
      'lock' => Icons.lock_outline,
      'layers' => Icons.layers_outlined,
      _ => Icons.circle_outlined,
    };

const List<String> _weekdays = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Good morning / afternoon / evening, from HER local clock.
String bandGreeting(DateTime now) => now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

// ================================================================== the home ===
class BandHome extends StatelessWidget {
  const BandHome({
    super.key,
    required this.band,
    required this.age,
    required this.childName,
    required this.tileIds,
    required this.destination,
    this.unreadDot = false,
    this.clock,
    this.presence,
    this.footer,
    this.birthdayLine,
    this.onBirthday,
    this.onGrewTap,
    this.speak,
  });

  /// 't57' or 't812' (see [kBandsDrawnHere]).
  final String band;
  final int age;
  final String childName;

  /// The ids to draw, in layout order (visibleHomeIds): this widget never adds one.
  final List<String> tileIds;
  final BandDestination destination;
  final bool unreadDot;
  final DateTime Function()? clock;

  /// Her grown-up's card (who is free now), when the live shell knows one.
  final Widget? presence;

  /// A quiet line under it (the sleeps-until-handover line, when the live shell knows it).
  final Widget? footer;

  /// The quiet birthday line in her birthday week (information only, family_structure_screens.dart's birthdayLine),
  /// and what it opens. Null = no line.
  final String? birthdayLine;
  final VoidCallback? onBirthday;

  /// Set when she tapped Not now on the grow page: shows the quiet 'Your home grew' row.
  final VoidCallback? onGrewTap;

  /// Reads a title aloud when it is tapped and read-aloud is on (null = none).
  final Future<void> Function(String)? speak;

  HomeLayout get _layout => homeLayoutFor(band, age: age);

  Widget _tile(BuildContext context, String id, {bool featured = false, bool hero = false, double? height}) {
    final BandTile def = kBandTiles[id]!;
    final String title = bandTileTitle(id, band);
    return TieredTile(
      key: hero && id == 'day' ? const Key('childHomeHero') : id == 'people' ? const Key('childHomeMyPeople') : Key('bandTile.$id'),
      icon: bandIcon(def.icon), label: title, featured: featured, hero: hero, height: height,
      unreadDot: id == 'msgs' && unreadDot,
      onTap: (BuildContext c) {
        speak?.call(title);
        final Widget? to = destination(c, id);
        if (to != null) _push(c, to);
      },
    );
  }

  Widget _rows(List<Widget> tiles, int cols, {Key? key}) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += cols) {
      final List<Widget> chunk = tiles.sublist(i, i + cols > tiles.length ? tiles.length : i + cols);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          for (int j = 0; j < cols; j++) ...<Widget>[
            if (j > 0) const SizedBox(width: 10),
            Expanded(child: j < chunk.length ? chunk[j] : const SizedBox.shrink()),
          ],
        ])),
      ));
    }
    return Column(key: key, children: rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: Key('bandHome.$band'),
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final double w = constraints.maxWidth;
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final double roomy = AccessScope.of(context).roomierReading ? roomyLineHeight / 1.2 : 1.0;
        final double hs = textScale.clamp(1.0, 1.6) * roomy;
        final DateTime now = (clock ?? DateTime.now)();
        final List<String> hero = _layout.hero.where(tileIds.contains).toList();
        final List<String> strip = _layout.strip.where(tileIds.contains).toList();
        final List<String> featured = _layout.featured.where(tileIds.contains).toList();
        final List<String> standard = _layout.standard.where(tileIds.contains).toList();
        final int featuredCols = w >= 900 ? 4 : 2;
        final int standardCols = _layout.standardColumns == 4 && w < 520 ? 2 : _layout.standardColumns;

        final bool t57 = band == 't57';
        final String eyebrow = t57 ? bandGreeting(now) : _weekdays[now.weekday - 1];
        final String title = t57 ? 'Hi, $childName' : '${bandGreeting(now)}, $childName';
        final Widget header = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(eyebrow, key: const Key('bandEyebrow'), style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(title, key: const Key('bandTitle'), style: Theme.of(context).textTheme.headlineMedium),
            if (birthdayLine != null)
              TextButton(key: const Key('birthdayLine'), onPressed: onBirthday, child: Text(birthdayLine!)),
          ]),
        );

        final Widget? grew = onGrewTap == null ? null : Padding(padding: const EdgeInsets.only(bottom: 10), child: GrewCard(onTap: onGrewTap!));

        // The Hero (5-7: My day) or the strip (8-12: My weeks) is one wide tile.
        Widget? lead;
        final String? leadId = hero.isNotEmpty ? hero.first : (strip.isNotEmpty ? strip.first : null);
        if (leadId != null) {
          lead = Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _tile(context, leadId, featured: true, hero: true, height: (hero.isNotEmpty ? 140 : 96) * hs),
          );
        }
        final List<Widget> aside = <Widget>[
          if (presence != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: presence),
          if (footer != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: footer),
        ];

        final Widget full = SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            header,
            ...aside,
            ?lead,
            ?grew,
            if (featured.isNotEmpty)
              _rows(<Widget>[for (final String id in featured) _tile(context, id, featured: true, height: 96 * hs)], featuredCols,
                  key: const Key('childHomeFeaturedGrid')),
            if (standard.isNotEmpty)
              _rows(<Widget>[for (final String id in standard) _tile(context, id, height: 76 * hs)], standardCols,
                  key: const Key('childHomeStandardGrid')),
          ]),
        );

        // foldCover: the one load-bearing thing, and ONE More tile that opens the whole home.
        final Widget collapsed = SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            header,
            ...aside,
            ?lead,
            ?grew,
            SizedBox(width: double.infinity, child: TieredTile(
              key: const Key('bandCollapsedMore'), icon: Icons.more_horiz, label: 'More', height: 84 * hs,
              onTap: (BuildContext c) => _push(c, Scaffold(appBar: AppBar(title: const Text('More')), body: SafeArea(child: full))),
            )),
          ]),
        );
        return CoverCollapse(full: full, collapsed: collapsed);
      })),
    );
  }
}

/// The quiet row on every home after she tapped Not now on the grow page. Tapping it opens the page again.
class GrewCard extends StatelessWidget {
  const GrewCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OliveCard(
        key: const Key('growLaterCard'), onTap: onTap, variant: OliveCardVariant.interactive,
        semanticLabel: 'Your home grew. Look when you want to.',
        child: ConstrainedBox(constraints: BoxConstraints(minHeight: childTargetOf(context) - 28), child: Row(children: <Widget>[
          const OliveIcon('sparkle', size: 26),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text('Your home grew', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text('Look when you want to.', style: Theme.of(context).textTheme.bodySmall),
          ])),
        ])),
      );
}

// ============================================================= the More page ===
/// The band's More page (prototype k.more): its list from the table, a caption, no settings. Everything the
/// older More hub holds (letters, the ladder, the quiet corner, take your things...) is one tap further, under
/// 'Everything else', so nothing that shipped became unreachable.
class ChildBandMoreScreen extends StatefulWidget {
  const ChildBandMoreScreen({
    super.key,
    required this.band,
    required this.age,
    required this.hasBirthday,
    required this.destination,
    this.hidden = const <String>{},
    this.loadHidden,
    this.shelfOn = false,
    this.extras = const <BandMoreExtra>[],
    this.speak,
  });
  final String band;
  final int age;
  final bool hasBirthday;
  final Set<String> hidden;

  /// More tiles to hide once it has asked the device (the guardian's suite switches). Until it answers nothing extra
  /// is hidden; a failure is the caller's to turn into 'hide them' (child_home.dart does).
  final Future<Set<String>> Function()? loadHidden;
  final bool shelfOn;
  final BandDestination destination;

  /// Rows after the table's tiles that are not in the prototype (Homework, Everything else).
  final List<BandMoreExtra> extras;
  final Future<void> Function(String)? speak;

  @override
  State<ChildBandMoreScreen> createState() => _ChildBandMoreState();
}

class _ChildBandMoreState extends State<ChildBandMoreScreen> {
  Set<String> _later = const <String>{};

  @override
  void initState() {
    super.initState();
    final Future<Set<String>> Function()? load = widget.loadHidden;
    if (load != null) {
      load().then((Set<String> s) {
        if (mounted) setState(() => _later = s);
      }, onError: (Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final String band = widget.band;
    final BandDestination destination = widget.destination;
    final Future<void> Function(String)? speak = widget.speak;
    final List<BandMoreExtra> extras = widget.extras;
    final double hs = (MediaQuery.textScalerOf(context).scale(1)).clamp(1.0, 1.6);
    final List<String> ids = moreIdsFor(band, widget.age,
            hasBirthday: widget.hasBirthday, shelfOn: widget.shelfOn, hidden: <String>{...widget.hidden, ..._later})
        .where(kTilesWithDestination.contains)
        .toList();
    final List<Widget> tiles = <Widget>[
      for (final String id in ids)
        TieredTile(
          key: Key('moreTile.$id'), icon: bandIcon(kBandTiles[id]!.icon), label: bandTileTitle(id, band), featured: true, height: 96 * hs,
          onTap: (BuildContext c) {
            speak?.call(bandTileTitle(id, band));
            final Widget? to = destination(c, id);
            if (to != null) _push(c, to);
          },
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final int cols = constraints.maxWidth >= 900 ? 4 : 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(
                band == 't1317' ? 'Everything else, in one place.' : 'Pick something.',
                key: const Key('moreCaption'), style: Theme.of(context).textTheme.bodyLarge)),
            for (int i = 0; i < tiles.length; i += cols)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: IntrinsicHeight(child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                for (int j = 0; j < cols; j++) ...<Widget>[
                  if (j > 0) const SizedBox(width: 10),
                  Expanded(child: i + j < tiles.length ? tiles[i + j] : const SizedBox.shrink()),
                ],
              ]))),
            for (final BandMoreExtra x in extras)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: SizedBox(width: double.infinity, child: TieredTile(
                key: Key(x.key), icon: x.icon, label: x.label, height: 84 * hs,
                onTap: (BuildContext c) => _push(c, x.build(c)),
              ))),
          ]),
        );
      })),
    );
  }
}

/// A row on the band More page that is not one of the prototype's tiles.
class BandMoreExtra {
  const BandMoreExtra({required this.key, required this.icon, required this.label, required this.build});
  final String key;
  final IconData icon;
  final String label;
  final Widget Function(BuildContext context) build;
}

/// 'Draw & colour' (Studio at 13-17): a choice of a doodle or a colouring page (prototype k.draw).
class DrawChoiceScreen extends StatelessWidget {
  const DrawChoiceScreen({super.key, required this.title, required this.doodle, required this.colouring});
  final String title;
  final Widget doodle;
  final Widget colouring;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: <Widget>[
          SizedBox(width: double.infinity, child: TieredTile(
            key: const Key('drawDoodle'), icon: Icons.brush_outlined, label: 'Doodle desk', featured: true, height: 120,
            onTap: (BuildContext c) => _push(c, doodle))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: TieredTile(
            key: const Key('drawColouring'), icon: Icons.palette_outlined, label: 'Colouring', featured: true, height: 120,
            onTap: (BuildContext c) => _push(c, colouring))),
        ]))),
      );
}

// ======================================================== 'your home grows' ===
/// The page shown instead of her home after a birthday crossed one of the keys. Calm: a picture, a lead line, what
/// is new and what stayed, one button and a way to put it off. No number but her age, no badge, no reward.
class ChildGrowScreen extends StatelessWidget {
  const ChildGrowScreen({
    super.key,
    required this.page,
    required this.onShow,
    required this.onLater,
    this.fromName,
    this.destinationExists = true,
    this.speak,
  });
  final GrowPage page;

  /// 'Show me' (the page's own button): the caller marks it seen and opens the destination.
  final VoidCallback onShow;

  /// 'Not now': the caller marks it later.
  final VoidCallback onLater;

  /// 'From Mommy' on the young pages (null: no line).
  final String? fromName;

  /// False when the page's destination is not built yet: the button is a plain Okay that marks it seen.
  final bool destinationExists;
  final Future<void> Function(String)? speak;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OlivePalette p = OlivePalette.of(context);
    final String? from = page.teen || page.quiet || fromName == null ? null : 'From $fromName';
    final bool five = page.eyebrow == 'You are 5';
    return Scaffold(
      key: const Key('growPage'),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(from ?? page.eyebrow, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(page.eyebrow, key: const Key('growEyebrow'), style: theme.textTheme.headlineMedium),
            ])),
            if (speak != null && page.say != null)
              IconButton(
                key: const Key('growHear'), tooltip: 'Hear it', iconSize: 32,
                constraints: BoxConstraints(minWidth: childTargetOf(context), minHeight: childTargetOf(context)),
                icon: const Icon(Icons.volume_up_outlined), onPressed: () => speak!(page.say!)),
          ]),
          const SizedBox(height: 12),
          if (!page.teen && !page.quiet && page.scene != null)
            OliveScene(page.scene!, key: const Key('growScene'), borderRadius: 28),
          if (five) ...<Widget>[
            const SizedBox(height: 12),
            OliveCard(variant: OliveCardVariant.tint, child: Center(child: Text('5', key: const Key('growFive'),
                style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w800, color: p.pri)))),
          ],
          const SizedBox(height: 12),
          Text(page.lead, key: const Key('growLead'), style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          OliveCard(child: Column(key: const Key('growChanges'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            for (final GrowItem it in page.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Container(
                    key: Key('growItem.${it.kind}'),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: it.kind == 'keep' ? p.surface3 : p.priC, borderRadius: BorderRadius.circular(12)),
                    child: Center(child: OliveIcon(it.kind == 'keep' ? 'check' : it.kind == 'hers' ? 'lock' : 'plus', size: 18, strokeWidth: 2.2, color: p.onPriC)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(it.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(it.body.replaceAll(GrownupLabels.prototypeBothWords, GrownupLabelScope.of(context).bothNames()),
                        style: theme.textTheme.bodyMedium),
                  ])),
                ]),
              ),
          ])),
          const SizedBox(height: 16),
          if (destinationExists) ...<Widget>[
            OliveButton(page.cta, key: const Key('growShow'), icon: 'arrowR', full: true, onPressed: onShow),
            const SizedBox(height: 8),
            OliveButton('Not now', key: const Key('growLater'), kind: OliveButtonKind.ghost, full: true, onPressed: onLater),
          ] else
            OliveButton('Okay', key: const Key('growOkay'), full: true, onPressed: onShow),
          if (page.teen)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('Nobody else is told that you saw this.',
                key: const Key('growTeenNote'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
        ]),
      )),
    );
  }
}

/// The prototype's grow-page destinations -> the tile ids they open.
const Map<String, String> kGrowDestTile = <String, String>{
  'k.day': 'day', 'k.weeks': 'weeks', 'k.list': 'list', 'k.privacy': 'privacy', 'k.cal': 'cal',
};

// =================================================== the local-midnight clock ===
/// Calls [onMidnight] at every local midnight, with the clock's reading at that moment. It is how her age moves
/// on her birthday with no server: the owner reads the new day and re-lays the home. The timer is cancelled with the
/// widget, and rescheduled after every call. [clock] is injectable so a test (and the parity replay) drives it.
class LocalMidnightWatch extends StatefulWidget {
  const LocalMidnightWatch({super.key, required this.child, required this.onMidnight, this.clock});
  final Widget child;
  final void Function(DateTime now) onMidnight;
  final DateTime Function()? clock;

  @override
  State<LocalMidnightWatch> createState() => _LocalMidnightWatchState();
}

class _LocalMidnightWatchState extends State<LocalMidnightWatch> {
  Timer? _timer;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final Duration d = untilLocalMidnight(_now());
    _timer = Timer(d <= Duration.zero ? const Duration(seconds: 1) : d, _fire);
  }

  void _fire() {
    if (!mounted) return;
    widget.onMidnight(_now());
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
