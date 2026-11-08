// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_gallery_test.dart).
// OLIVE BRANCH — the component gallery. This is how the owner compares the Flutter app against the
// prototype: every component, scene, spot illustration and icon of the library, on one screen, in
// light AND dark, at text scale 1.0 AND 2.0, as guardian or as child, in any of the seven palettes.
//
// Reachable from the guardian More hub ("Design (demo)", only where showDemoTiles is true: the offline
// demo build or a dev build) and from the dev entry point lib/main_ui_gallery.dart. Nothing here talks
// to a server or reads family data; every specimen is invented sample content.
//
// Open the prototype next to it: docs/superpowers/mockups/live/index.html (the kit's own atlas).
import 'package:flutter/material.dart';

import '../theme.dart';
import '../theme_data.dart';
import 'olive_ui.dart';

/// Which brightness variants the gallery shows.
enum GalleryBrightness { light, dark, both }

/// The component gallery screen.
class OliveUiGalleryScreen extends StatefulWidget {
  const OliveUiGalleryScreen({
    super.key,
    this.initialBrightness = GalleryBrightness.both,
    this.initialTextScale = 1.0,
    this.initialAudience = OliveAudience.guardian,
    this.initialPalette = ThemePalette.olive,
  });

  final GalleryBrightness initialBrightness;
  final double initialTextScale;
  final OliveAudience initialAudience;
  final ThemePalette initialPalette;

  @override
  State<OliveUiGalleryScreen> createState() => _OliveUiGalleryScreenState();
}

class _OliveUiGalleryScreenState extends State<OliveUiGalleryScreen> {
  late GalleryBrightness _brightness = widget.initialBrightness;
  late double _scale = widget.initialTextScale;
  late OliveAudience _audience = widget.initialAudience;
  late ThemePalette _palette = widget.initialPalette;

  static const _palettes = ThemePalette.values;

  List<Widget> _variants(Widget Function(BuildContext) build) {
    final modes = switch (_brightness) {
      GalleryBrightness.light => [ThemeBrightness.light],
      GalleryBrightness.dark => [ThemeBrightness.dark],
      GalleryBrightness.both => [ThemeBrightness.light, ThemeBrightness.dark],
    };
    return [
      for (final m in modes)
        _Variant(
          theme: AppTheme(palette: _palette, brightness: m),
          scale: _scale,
          audience: _audience,
          label: '${m.name} · ${_palette.name} · text ${_scale.toStringAsFixed(1)} · ${_audience.name}',
          specimen: build,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    return Scaffold(
      appBar: AppBar(title: const Text('UI gallery')),
      body: ListView.builder(
        key: const Key('oliveGalleryList'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: sections.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _controls();
          final s = sections[i - 1];
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Semantics(header: true, child: Text(s.$1, style: Theme.of(context).textTheme.titleLarge)),
              if (s.$2.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2, bottom: 8), child: Text(s.$2, style: Theme.of(context).textTheme.bodySmall)),
              ..._variants(s.$3).expand((w) => [w, const SizedBox(height: 10)]),
            ]),
          );
        },
      ),
    );
  }

  Widget _controls() {
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(t, style: Theme.of(context).textTheme.labelMedium));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Compare against the prototype: docs/superpowers/mockups/live/index.html',
          style: Theme.of(context).textTheme.bodySmall),
      label('Brightness'),
      SegmentedControl(
        key: const Key('galleryBrightness'),
        items: const [SegmentItem('Light'), SegmentItem('Dark'), SegmentItem('Both')],
        selected: _brightness.index,
        onChanged: (i) => setState(() => _brightness = GalleryBrightness.values[i]),
      ),
      label('Text size'),
      SegmentedControl(
        key: const Key('galleryScale'),
        items: const [SegmentItem('1.0'), SegmentItem('2.0')],
        selected: _scale >= 2 ? 1 : 0,
        onChanged: (i) => setState(() => _scale = i == 1 ? 2.0 : 1.0),
      ),
      label('Who is it for'),
      SegmentedControl(
        key: const Key('galleryAudience'),
        items: const [SegmentItem('Guardian'), SegmentItem('Child')],
        selected: _audience.index,
        onChanged: (i) => setState(() => _audience = OliveAudience.values[i]),
      ),
      label('Palette'),
      FilterChips(
        wrap: true,
        items: [for (final p in _palettes) SegmentItem(p.name)],
        selected: {_palettes.indexOf(_palette)},
        onToggle: (i) => setState(() => _palette = _palettes[i]),
      ),
    ]);
  }

  // (title, note, builder)
  List<(String, String, Widget Function(BuildContext))> _sections() => [
        ('Icons', 'The kit 24-grid stroke icon set (${OliveIcons.all.length} icons), same names.', _icons),
        ('Scenes', 'Soft, warm scene illustrations. Palette-aware.', _scenes),
        ('Spot illustrations', 'The leaf is the celebration image. No stars, scores or trophies.', _spots),
        ('Buttons and chips', 'OliveButton, OliveIconButton, OliveChip, OliveSectionLabel, OliveDivider.', _buttons),
        ('Cards', 'OliveCard: standard, tint, flat, raised, sunk, outline, interactive, hero, hero warm.', _cards),
        ('Tiles', 'OliveTile: hero, featured, standard, and the child picture tile with a dot.', _tiles),
        ('Rows and data', 'OliveRow, KeyValueRow, StatTile, OliveAvatar, AvatarStack.', _rows),
        ('Status and feedback', 'StatusPill, OliveNotice, OliveBanner, OfflineBanner, OliveToast.', _status),
        ('Empty, error, loading, permission', 'EmptyState and ErrorState (child variants are pictures only), OliveSkeleton, PermissionPrompt.', _states),
        ('Controls', 'SegmentedControl, FilterChips, toggles, radios, checks, sliders, form fields, PinPad.', _controlsSection),
        ('Progress and time', 'OliveStepper, OliveSteps, OliveProgress, Timeline, ScheduleGrid, MonthCalendar.', _flow),
        ('Media', 'RecordButton, Waveform, PlayerChrome, QrCard (placeholder, not scannable).', _media),
        ('Layers', 'OliveBottomSheet and OliveDialog, shown in place and as real routes.', _layers),
      ];

  // ------------------------------------------------------------------ specimens
  static Widget _gap([double h = 12]) => SizedBox(height: h);

  static Widget _icons(BuildContext context) {
    final p = OlivePalette.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final n in OliveIcons.all)
        SizedBox(
          width: 84,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            OliveIcon(n, size: 28, color: p.ink),
            const SizedBox(height: 4),
            Text(n, textAlign: TextAlign.center, style: OliveText.cap(context).copyWith(fontSize: 11)),
          ]),
        ),
    ]);
  }

  static Widget _scenes(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final n in kOliveSceneNames) ...[
          Text(n, style: OliveText.label(context)),
          const SizedBox(height: 4),
          OliveScene(n),
          _gap(),
        ],
      ]);

  static Widget _spots(BuildContext context) => Wrap(spacing: 14, runSpacing: 14, children: [
        for (final n in kOliveSpotNames)
          Column(mainAxisSize: MainAxisSize.min, children: [
            OliveSpot(n),
            const SizedBox(height: 4),
            Text(n, style: OliveText.cap(context)),
          ]),
        Column(mainAxisSize: MainAxisSize.min, children: [
          const OliveSpot('family', accentPlate: true),
          const SizedBox(height: 4),
          Text('accent plate', style: OliveText.cap(context)),
        ]),
      ]);

  static Widget _buttons(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OliveButton('Send', onPressed: () {}, icon: OliveIcons.send),
          OliveButton('Tonal', onPressed: () {}, kind: OliveButtonKind.tonal),
          OliveButton('Ghost', onPressed: () {}, kind: OliveButtonKind.ghost),
          OliveButton('Remove', onPressed: () {}, kind: OliveButtonKind.danger, icon: OliveIcons.trash),
          const OliveButton('Disabled'),
          OliveButton('Small', onPressed: () {}, size: OliveButtonSize.sm),
          OliveButton('Large', onPressed: () {}, size: OliveButtonSize.lg),
        ]),
        _gap(),
        OliveButton('Full width', onPressed: () {}, full: true),
        _gap(),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OliveIconButton(OliveIcons.chevL, label: 'Back', onPressed: () {}),
          OliveIconButton(OliveIcons.mic, label: 'Record', onPressed: () {}, kind: OliveButtonKind.pri),
          OliveIconButton(OliveIcons.share, label: 'Share', onPressed: () {}, kind: OliveButtonKind.tonal),
          OliveIconButton(OliveIcons.trash, label: 'Delete', onPressed: () {}, kind: OliveButtonKind.danger),
          OliveIconButton(OliveIcons.x, label: 'Close', onPressed: () {}, small: true),
        ]),
        _gap(),
        const Wrap(spacing: 6, runSpacing: 6, children: [
          OliveChip('Quiet'),
          OliveChip('Primary', tone: OliveTone.pri, icon: OliveIcons.leaf),
          OliveChip('Fine', tone: OliveTone.ok, icon: OliveIcons.check),
          OliveChip('Careful', tone: OliveTone.warn),
          OliveChip('Problem', tone: OliveTone.bad),
          OliveChip('Note', tone: OliveTone.info, small: true),
        ]),
        const OliveSectionLabel('Section label', trailing: OliveChip('3', small: true)),
        _gap(8),
        const OliveDivider(),
        _gap(8),
        const OliveDivider(text: 'or'),
      ]);

  static Widget _cards(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final v in OliveCardVariant.values) ...[
          OliveCard(
            variant: v,
            onTap: v == OliveCardVariant.interactive ? () {} : null,
            semanticLabel: v == OliveCardVariant.interactive ? 'Interactive card' : null,
            child: Builder(builder: (cc) {
              final fg = DefaultTextStyle.of(cc).style.color;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.name, style: OliveText.head(cc, color: fg)),
                const SizedBox(height: 4),
                Text('A card on the page. Soft edges, tinted depth.', style: TextStyle(color: fg)),
              ]);
            }),
          ),
          _gap(10),
        ],
      ]);

  static Widget _tiles(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OliveTile.hero(title: 'Ivy is up', sub: 'Before school, 7:42', icon: OliveIcons.sun, scene: 'day', badge: '2', onTap: () {}),
        _gap(),
        OliveTile.featured(title: 'Letters', sub: 'One new from Dad', icon: OliveIcons.mail, badge: '1', onTap: () {}),
        _gap(),
        Row(children: [
          for (final t in const [('Games', OliveIcons.dice), ('Colour', OliveIcons.palette), ('Read', OliveIcons.book)]) ...[
            Expanded(child: OliveTile.standard(title: t.$1, icon: t.$2, onTap: () {})),
            if (t.$1 != 'Read') const SizedBox(width: 8),
          ],
        ]),
        _gap(),
        Text('Child picture tiles (a dot, never a number)', style: OliveText.label(context)),
        _gap(6),
        OliveAudienceScope(
          audience: OliveAudience.child,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: OliveTile.picture(title: 'Dad', spot: 'video', showDot: true, onTap: () {})),
            const SizedBox(width: 8),
            Expanded(child: OliveTile.picture(title: 'Stories', spot: 'leaf', onTap: () {})),
          ]),
        ),
      ]);

  static Widget _rows(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OliveRowGroup(children: [
          OliveRow(title: 'Bedtime story', sub: 'Tonight, 7:30', icon: OliveIcons.book, onTap: () {}),
          const OliveRow(title: 'Medicine', sub: 'Morning dose given', icon: OliveIcons.pill, tone: OliveTone.ok, trailing: StatusPill(StatusKind.delivered, small: true)),
          OliveRow(title: 'Clock is ahead', sub: 'Check this phone', icon: OliveIcons.clock, tone: OliveTone.warn, onTap: () {}),
          const OliveRow(title: 'Not sent', icon: OliveIcons.warn, tone: OliveTone.bad),
          const OliveRow(title: 'Dad', icon: OliveIcons.user, tone: OliveTone.info),
        ]),
        _gap(),
        const OliveCard(child: KeyValueList([('Recorded', 'Tuesday'), ('Length', '1:10'), ('Seen by', 'Mom, Dad')])),
        _gap(),
        const Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: 150, child: StatTile(label: 'Next handover', value: '3', unit: 'sleeps', note: 'Friday', icon: OliveIcons.calendar)),
          SizedBox(width: 150, child: StatTile(label: 'Letters', value: '4', note: 'this month')),
        ]),
        _gap(),
        const Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OliveAvatar('I'),
          OliveAvatar('D', tone: OliveTone.accent, presence: true),
          OliveAvatar('M', tone: OliveTone.ok, presence: false),
          OliveAvatar('G', tone: OliveTone.info, ring: true),
          OliveAvatar('H', tone: OliveTone.quiet),
          AvatarStack([AvatarSpec('I'), AvatarSpec('D', tone: OliveTone.accent), AvatarSpec('M'), AvatarSpec('G'), AvatarSpec('H')], size: 34),
        ]),
      ]);

  static Widget _status(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in StatusKind.values) StatusPill(k),
          const StatusPill(StatusKind.watched, text: 'Watched 7:04', small: true),
        ]),
        _gap(),
        const OliveNotice(tone: OliveTone.warn, title: 'Clock ahead', text: 'This phone is 4 minutes ahead, so some times may look off.', actionLabel: 'See why'),
        _gap(8),
        OliveNotice(tone: OliveTone.ok, title: 'All caught up', text: 'Nothing is waiting.', onDismiss: () {}),
        _gap(8),
        const OliveNotice(tone: OliveTone.bad, title: 'Not sent', text: 'The letter is safe and will try again.'),
        _gap(8),
        const OliveNotice(tone: OliveTone.info, text: 'Letters are kept for 12 months.'),
        _gap(8),
        const OliveBanner('Welcome back. Three things are new.', tone: OliveTone.pri),
        _gap(8),
        const OfflineBanner(actionLabel: 'Retry'),
        _gap(8),
        const OliveToast('Message banked', icon: OliveIcons.check, tone: OliveTone.ok, actionLabel: 'Undo'),
        _gap(8),
        Builder(builder: (c) => Align(alignment: Alignment.centerLeft, child: OliveButton('Show a toast', kind: OliveButtonKind.tonal, onPressed: () => showOliveToast(c, 'Saved on this phone', icon: OliveIcons.check)))),
      ]);

  static Widget _states(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        EmptyState(spot: 'envelope', title: 'No letters yet', sub: 'When someone writes to you it will appear here.', actionLabel: 'Write one', onAction: () {}),
        const Divider(),
        ErrorState(onAction: () {}, detail: 'E-4012'),
        const Divider(),
        Text('Child: pictures only, no words', style: OliveText.label(context)),
        const OliveAudienceScope(audience: OliveAudience.child, child: Row(children: [
          Expanded(child: EmptyState.child(spot: 'family', semanticLabel: 'Nothing here yet')),
          Expanded(child: ErrorState.child()),
        ])),
        const Divider(),
        const OliveSkeleton(SkeletonKind.hero),
        _gap(8),
        const OliveSkeleton(SkeletonKind.row, count: 2),
        _gap(8),
        const OliveSkeleton(SkeletonKind.card),
        _gap(8),
        const OliveSkeleton(SkeletonKind.text, count: 3),
        _gap(8),
        const Row(children: [Expanded(child: OliveSkeleton(SkeletonKind.tile)), SizedBox(width: 8), Expanded(child: OliveSkeleton(SkeletonKind.tile))]),
        _gap(),
        PermissionPrompt(
          title: 'Allow the camera?',
          body: 'So she can show Dad what she made.',
          why: const ['Only while a call is open', 'Nothing is recorded unless you say so'],
          onAllow: () {},
          onDeny: () {},
        ),
      ]);

  static Widget _controlsSection(BuildContext context) => const _ControlsSpecimen();

  static Widget _flow(BuildContext context) => const _FlowSpecimen();

  static Widget _media(BuildContext context) => const _MediaSpecimen();

  static Widget _layers(BuildContext context) => const _LayersSpecimen();
}

/// One themed, scaled specimen panel.
class _Variant extends StatelessWidget {
  const _Variant({required this.theme, required this.scale, required this.audience, required this.label, required this.specimen});

  final AppTheme theme;
  final double scale;
  final OliveAudience audience;
  final String label;
  final Widget Function(BuildContext) specimen;

  @override
  Widget build(BuildContext context) {
    final data = buildThemeData(theme);
    return Theme(
      data: data,
      child: Builder(builder: (ctx) {
        final t = Theme.of(ctx);
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: OliveAudienceScope(
            audience: audience,
            child: Container(
              decoration: BoxDecoration(
                color: t.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.colorScheme.outlineVariant),
              ),
              padding: const EdgeInsets.all(14),
              child: Material(
                type: MaterialType.transparency,
                child: DefaultTextStyle(
                  style: t.textTheme.bodyMedium!,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                    const SizedBox(height: 10),
                    specimen(ctx),
                  ]),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ControlsSpecimen extends StatefulWidget {
  const _ControlsSpecimen();

  @override
  State<_ControlsSpecimen> createState() => _ControlsSpecimenState();
}

class _ControlsSpecimenState extends State<_ControlsSpecimen> {
  int _seg = 0;
  int _seg2 = 1;
  final Set<int> _chips = {0, 2};
  bool _toggle = true;
  bool _toggle2 = false;
  int _radio = 0;
  bool _check = true;
  double _slider = 0.6;
  int _pin = 2;

  @override
  Widget build(BuildContext context) {
    final audience = OliveAudienceScope.of(context);
    final digits = audience == OliveAudience.child ? const [4, 8, 1, 9, 3, 6, 2, 7, 5] : const [7, 3, 9, 1, 5, 8, 2, 6, 4];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedControl(items: const [SegmentItem('Today', count: 3), SegmentItem('Week'), SegmentItem('Month')], selected: _seg, onChanged: (i) => setState(() => _seg = i)),
      const SizedBox(height: 10),
      SegmentedControl(
        full: false, small: true,
        items: const [SegmentItem('Mom', icon: OliveIcons.user), SegmentItem('Dad', icon: OliveIcons.user)],
        selected: _seg2, onChanged: (i) => setState(() => _seg2 = i)),
      const SizedBox(height: 10),
      FilterChips(
        items: const [SegmentItem('All'), SegmentItem('Dad'), SegmentItem('Grandma', count: 2), SegmentItem('Letters', icon: OliveIcons.mail)],
        selected: _chips,
        onToggle: (i) => setState(() => _chips.contains(i) ? _chips.remove(i) : _chips.add(i)),
      ),
      const SizedBox(height: 10),
      OliveRowGroup(children: [
        ToggleRow(title: 'Quiet hours', sub: 'After 8 in the evening', icon: OliveIcons.moon, value: _toggle, onChanged: (v) => setState(() => _toggle = v)),
        ToggleRow(title: 'Read aloud', value: _toggle2, onChanged: (v) => setState(() => _toggle2 = v)),
        for (var i = 0; i < 2; i++)
          RadioRow(title: i == 0 ? 'Every day' : 'Weekdays only', sub: i == 0 ? null : 'Skip weekends', selected: _radio == i, onSelected: () => setState(() => _radio = i)),
        CheckRow(title: 'Remind me', value: _check, onChanged: (v) => setState(() => _check = v)),
        SliderRow(title: 'Text size', icon: OliveIcons.eye, value: _slider, onChanged: (v) => setState(() => _slider = v), valueText: _slider > 0.66 ? 'Large' : (_slider > 0.33 ? 'Medium' : 'Small'), startLabel: 'A', endLabel: 'A'),
      ]),
      const SizedBox(height: 14),
      const OliveFormField(label: 'Email', placeholder: 'name@example.com', icon: OliveIcons.mail, required: true, hint: 'Only used to sign you in.'),
      const SizedBox(height: 10),
      const OliveFormField(label: 'Code', initialValue: 'OLIVE-7', error: 'Looks unfinished', suffix: 'of 10'),
      const SizedBox(height: 10),
      const OliveFormField(label: 'Locked', initialValue: 'Cannot change', enabled: false),
      const SizedBox(height: 16),
      Center(
        child: PinPad(
          title: audience == OliveAudience.child ? null : 'Grown-ups only',
          sub: audience == OliveAudience.child ? null : 'Enter your PIN',
          filled: _pin,
          digits: digits,
          includeZero: audience != OliveAudience.child,
          biometric: audience != OliveAudience.child,
          onDigit: (_) => setState(() => _pin = (_pin + 1) % 5),
          onDelete: () => setState(() => _pin = _pin > 0 ? _pin - 1 : 0),
          onBiometric: () {},
        ),
      ),
    ]);
  }
}

class _FlowSpecimen extends StatefulWidget {
  const _FlowSpecimen();

  @override
  State<_FlowSpecimen> createState() => _FlowSpecimenState();
}

class _FlowSpecimenState extends State<_FlowSpecimen> {
  int _sel = 12;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Center(child: OliveStepper(total: 5, active: 3)),
        const SizedBox(height: 14),
        const OliveSteps(labels: ['Role', 'Code', 'Scan'], active: 1),
        const SizedBox(height: 14),
        const OliveProgress(value: 0.6, semanticLabel: 'Upload'),
        const SizedBox(height: 14),
        const Timeline([
          TimelineItem(time: '7:04', title: 'Watched', sub: 'Mom saw it', tone: OliveTone.ok),
          TimelineItem(time: '6:50', title: 'Delivered', icon: OliveIcons.send),
          TimelineItem(title: 'Now', sub: 'Waiting for Dad', state: TimelineState.now),
          TimelineItem(title: 'Later', sub: 'Goodnight call', state: TimelineState.next),
        ]),
        const SizedBox(height: 14),
        const ScheduleGrid(from: 7, to: 18, now: 11, blocks: [
          ScheduleBlockSpec(start: 8.5, end: 15, title: 'School', tone: OliveTone.info),
          ScheduleBlockSpec(start: 9, end: 10.5, title: 'Reading', sub: 'Library', col: 1, cols: 2),
          ScheduleBlockSpec(start: 15.5, end: 17, title: 'Swimming', tone: OliveTone.accent),
        ]),
        const SizedBox(height: 14),
        MonthCalendar(
          year: 2026, month: 11, today: 8, selected: _sel,
          marks: const {1: DayMark.houseA, 2: DayMark.houseA, 5: DayMark.houseB, 6: DayMark.houseB, 4: DayMark.handover, 14: DayMark.event},
          onSelect: (d) => setState(() => _sel = d),
        ),
      ]);
}

class _MediaSpecimen extends StatefulWidget {
  const _MediaSpecimen();

  @override
  State<_MediaSpecimen> createState() => _MediaSpecimenState();
}

class _MediaSpecimenState extends State<_MediaSpecimen> {
  bool _playing = false;
  bool _captions = true;
  double _progress = 0.34;
  RecordState _rec = RecordState.idle;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final s in RecordState.values)
            RecordButton(state: s, time: s == RecordState.idle ? null : '0:12', onPressed: () => setState(() => _rec = s)),
        ]),
        Text('Tap a button above, the next shows:', style: OliveText.cap(context)),
        RecordButton(state: _rec, time: _rec == RecordState.idle ? null : '0:12', size: 72, onPressed: () => setState(() => _rec = RecordState.values[(_rec.index + 1) % 3])),
        const SizedBox(height: 14),
        const Waveform(played: 0.4, seed: 3),
        const SizedBox(height: 8),
        const Waveform(accent: true, seed: 11, height: 32),
        const SizedBox(height: 14),
        PlayerChrome(
          scene: 'garden',
          caption: 'Goodnight, Ivy.',
          progress: _progress,
          playing: _playing,
          captionsOn: _captions,
          onPlayPause: () => setState(() => _playing = !_playing),
          onSeek: (v) => setState(() => _progress = v),
          onCaptions: () => setState(() => _captions = !_captions),
          onFullscreen: () {},
        ),
        const SizedBox(height: 14),
        QrCard(title: 'Scan on her tablet', sub: 'Open Olive and choose “Pair”.', code: 'OLIVE-7K4P', expires: '10 minutes', onCopy: () {}),
      ]);
}

class _LayersSpecimen extends StatelessWidget {
  const _LayersSpecimen();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OliveButton('Open a sheet', kind: OliveButtonKind.tonal, onPressed: () => OliveBottomSheet.show<void>(
                context,
                title: 'Send to',
                showClose: true,
                builder: (c) => Column(children: [
                  OliveRow(title: 'Dad', icon: OliveIcons.user, onTap: () => Navigator.of(c).pop()),
                  OliveRow(title: 'Grandma', icon: OliveIcons.user, onTap: () => Navigator.of(c).pop()),
                ]),
                actions: [Builder(builder: (c) => OliveButton('Done', onPressed: () => Navigator.of(c).pop()))],
              )),
          OliveButton('Open a dialog', kind: OliveButtonKind.tonal, onPressed: () => OliveDialog.show<void>(
                context,
                title: 'Remove this letter?',
                body: 'It stays in the archive for 12 months.',
                icon: OliveIcons.trash,
                tone: OliveTone.bad,
                actions: (c) => [
                  OliveButton('Cancel', kind: OliveButtonKind.ghost, onPressed: () => Navigator.of(c).pop()),
                  OliveButton('Remove', kind: OliveButtonKind.danger, onPressed: () => Navigator.of(c).pop()),
                ],
              )),
        ]),
        const SizedBox(height: 12),
        Text('In place:', style: OliveText.label(context)),
        const SizedBox(height: 6),
        SizedBox(
          height: 360,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.48))),
              OliveBottomSheet(
                title: 'Send to',
                onClose: () {},
                actions: [OliveButton('Done', onPressed: () {})],
                child: const Column(children: [OliveRow(title: 'Dad', icon: OliveIcons.user), OliveRow(title: 'Grandma', icon: OliveIcons.user)]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        ClipRect(
          child: OliveDialog(
            title: 'Remove this letter?',
            body: 'It stays in the archive for 12 months.',
            icon: OliveIcons.trash,
            tone: OliveTone.bad,
            actions: [OliveButton('Cancel', kind: OliveButtonKind.ghost, onPressed: () {}), OliveButton('Remove', kind: OliveButtonKind.danger, onPressed: () {})],
          ),
        ),
      ]);
}
