// OLIVE BRANCH — suite C VOICE, the child's screens: feelings weather, worry
// box, my helpers, symbols. No longer UNVERIFIED — verified by CI
// (client/test/voice_screens_test.dart).
//
// PRIVATE FIRST, ON THIS DEVICE ONLY. Nothing on these screens is sent anywhere
// and nothing is shown to anyone automatically.
//  - Feelings weather: a sky for how today feels. Only she can see it; there is
//    no "show" button at all, no history and no count. It is a picture, not a
//    mood, and no sky is good or bad.
//  - Worry box: she taps a picture or draws. Then SHE chooses: keep it, show
//    my grown-up, or let it float away (which is for real). The screen never
//    reads, labels or counts a worry, and shows no number of them.
//  - My helpers: the grown-ups a guardian wrote down, with a picture each. A name
//    and a line. No call button, no message, no map (nothing here goes online).
//  - Symbols: tap pictures to build a short strip; the sentence is those words in
//    order, exactly as tapped. It is read aloud through the optional `speak`
//    seam (picture_icons.dart) and is otherwise just shown large, in quiet. The
//    strip is never stored.
// A grown-up's view of the worries she chose to show is in
// rhythm_voice_guardian_screens.dart; this file never imports it.
import 'package:flutter/material.dart';

import 'family_structure_logic.dart' show FamilyPrincipal;
import 'picture_icons.dart';
import 'picture_library.dart';
import 'rhythm_logic.dart' show RvRefused;
import 'rhythm_screens.dart';
import 'rhythm_voice_repositories.dart';
import 'voice_logic.dart';

// ============================================================ FEELINGS =======
class FeelingsWeatherScreen extends StatelessWidget {
  const FeelingsWeatherScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _FeelingsWeatherScreenView(service: service, speak: speak));
}

class _FeelingsWeatherScreenView extends StatefulWidget {
  const _FeelingsWeatherScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_FeelingsWeatherScreenView> createState() => _FeelingsWeatherScreenState();
}

class _FeelingsWeatherScreenState extends State<_FeelingsWeatherScreenView> {
  String? _picked;
  bool _loaded = false;
  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  @override
  void initState() {
    super.initState();
    widget.service.weatherToday(_me).then((FeelingToday? f) {
      if (mounted) setState(() { _picked = f?.weather; _loaded = true; });
    });
  }

  Future<void> _pick(String id) async {
    SensoryScope.tap(context);
    final RvResult r = await widget.service.pickTodayWeather(_me, id);
    if (r.ok && mounted) setState(() => _picked = id);
  }

  Future<void> _clear() async {
    final RvResult r = await widget.service.forgetWeather(_me);
    if (r.ok && mounted) setState(() => _picked = null);
  }

  @override
  Widget build(BuildContext context) {
    final Speak? speak = SensoryScope.speakFor(context, widget.speak);
    return RvChildPage(
      service: widget.service,
      title: 'The sky in me',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('What is the sky like in you today?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_loaded)
          PictureGrid(children: <Widget>[
            for (final String id in weatherIds)
              PictureTile(
                key: Key('weather_$id'), picture: id, label: pictureLabel(id), speak: speak,
                selected: _picked == id, onTap: () => _pick(id)),
          ]),
        const SizedBox(height: 16),
        const QuietNote('Only you can see this. It stays on this device.'),
        if (_picked != null) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(height: 64, child: OutlinedButton.icon(
              key: const Key('weatherClear'), onPressed: _clear,
              icon: const Icon(Icons.cloud_off_outlined), label: const Text('Clear it'))),
        ],
      ]),
    );
  }
}

// ============================================================== WORRY BOX ====
enum _WorryMode { home, pick, draw, choose }

class WorryBoxScreen extends StatelessWidget {
  const WorryBoxScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _WorryBoxScreenView(service: service, speak: speak));
}

class _WorryBoxScreenView extends StatefulWidget {
  const _WorryBoxScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_WorryBoxScreenView> createState() => _WorryBoxScreenState();
}

class _WorryBoxScreenState extends State<_WorryBoxScreenView> {
  _WorryMode _mode = _WorryMode.home;
  String? _picture;
  List<List<double>> _strokes = const <List<double>>[];
  String? _message;
  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  void _go(_WorryMode m, {String? message}) => setState(() { _mode = m; _message = message; });

  Future<void> _end({required bool show}) async {
    RvResult r;
    if (_picture != null) {
      r = await widget.service.putWorryPicture(_me, _picture!, showGrownUp: show);
    } else {
      r = await widget.service.putWorryDrawing(_me, _strokes, showGrownUp: show);
    }
    if (!mounted) return;
    _picture = null;
    _strokes = const <List<double>>[];
    if (r.ok) {
      _go(_WorryMode.home, message: show ? 'Your grown-up can see this one.' : 'It is in the box.');
    } else if (r.reason == 'box_full') {
      _go(_WorryMode.home, message: 'The box is full. Let one float away first.');
    } else {
      _go(_WorryMode.home, message: 'That did not go in. Try again.');
    }
  }

  void _floatNew() {
    // Never written: nothing to delete, nothing left behind.
    _picture = null;
    _strokes = const <List<double>>[];
    _go(_WorryMode.home, message: 'It floated away.');
  }

  @override
  Widget build(BuildContext context) {
    final Speak? speak = SensoryScope.speakFor(context, widget.speak);
    return RvChildPage(
      service: widget.service,
      title: 'My worry box',
      body: switch (_mode) {
        _WorryMode.home => _home(context),
        _WorryMode.pick => _pick(context, speak),
        _WorryMode.draw => _draw(context),
        _WorryMode.choose => _choose(context, speak),
      },
    );
  }

  Widget _home(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Container(
          constraints: const BoxConstraints(minHeight: 130), padding: const EdgeInsets.all(12), alignment: Alignment.center,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.inventory_2_outlined, size: 48),
            const SizedBox(height: 6),
            Text('Put a worry in the box', style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
        const SizedBox(height: 12),
        if (_message != null) ...<Widget>[
          Text(_message!, key: const Key('worryMessage'), textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
        ],
        Row(children: <Widget>[
          Expanded(child: PictureTile(key: const Key('worryPick'), picture: 'worry-other', label: 'Pick a picture',
              onTap: () => _go(_WorryMode.pick))),
          const SizedBox(width: 12),
          Expanded(child: _ToolTile(key: const Key('worryDraw'), icon: Icons.brush_outlined, label: 'Draw it',
              onTap: () => _go(_WorryMode.draw))),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 64, child: OutlinedButton.icon(
            key: const Key('worryLook'), icon: const Icon(Icons.inventory_2_outlined), label: const Text('Look in the box'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => WorryShelfScreen(service: widget.service, speak: widget.speak))))),
      ]);

  Widget _pick(BuildContext context, Speak? speak) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('Which picture is closest?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        PictureGrid(children: <Widget>[
          for (final PictureDef p in picturesIn(PictureGroup.worry))
            PictureTile(key: Key('worryPic_${p.id}'), picture: p.id, label: p.label, speak: speak,
                onTap: () { _picture = p.id; _go(_WorryMode.choose); }),
        ]),
        const SizedBox(height: 12),
        TextButton(key: const Key('worryBack'), onPressed: () => _go(_WorryMode.home), child: const Text('Back')),
      ]);

  Widget _draw(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('Draw it however you like.', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        WorryPad(key: const Key('worryPad'), onChanged: (List<List<double>> s) => _strokes = s),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(child: SizedBox(height: 64, child: FilledButton(
              key: const Key('worryDrawDone'),
              onPressed: () {
                if (_strokes.isNotEmpty) _go(_WorryMode.choose);
              },
              child: const Text('I have drawn it')))),
          const SizedBox(width: 12),
          Expanded(child: SizedBox(height: 64, child: OutlinedButton(
              key: const Key('worryDrawBack'),
              onPressed: () { _strokes = const <List<double>>[]; _go(_WorryMode.home); },
              child: const Text('Back')))),
        ]),
      ]);

  Widget _choose(BuildContext context, Speak? speak) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Center(
        child: _picture != null
            ? PictureGlyph(_picture!, size: 64)
            : SizedBox(width: 160, height: 160, child: WorryDrawingView(strokes: _strokes)),
      ),
      const SizedBox(height: 16),
      Text('Then you choose', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      PictureTile(key: const Key('worryKeep'), picture: 'worry-other', label: 'Keep it in the box',
          minHeight: 72, showLabel: true, onTap: () => _end(show: false)),
      const SizedBox(height: 10),
      PictureTile(key: const Key('worryShow'), picture: 'grown-up', label: 'Show my grown-up',
          minHeight: 72, onTap: () => _end(show: true)),
      const SizedBox(height: 10),
      PictureTile(key: const Key('worryFloat'), picture: 'worry-dream', label: 'Let it float away',
          minHeight: 72, onTap: _floatNew),
    ]);
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Semantics(
      button: true, label: label,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18), onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              ExcludeSemantics(child: Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(20)),
                  child: Icon(icon, size: 40, color: c.onPrimaryContainer))),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ])),
          ),
        ),
      ),
    );
  }
}

/// Where she draws. Reports strokes normalised to 0..1, bounded, and quantised
/// by the logic layer when the worry is made. Nothing is read from the drawing.
class WorryPad extends StatefulWidget {
  const WorryPad({super.key, required this.onChanged});
  final ValueChanged<List<List<double>>> onChanged;
  @override
  State<WorryPad> createState() => _WorryPadState();
}

class _WorryPadState extends State<WorryPad> {
  final List<List<double>> _strokes = <List<double>>[];

  double _n(double v, double max) => max <= 0 ? 0 : (v / max).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double side = c.maxWidth.clamp(200.0, 420.0);
        return Center(
          child: Container(
            width: side, height: side,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(18)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (DragStartDetails d) {
                if (_strokes.length >= maxStrokes) return;
                setState(() => _strokes.add(<double>[_n(d.localPosition.dx, side), _n(d.localPosition.dy, side)]));
                widget.onChanged(_copy());
              },
              onPanUpdate: (DragUpdateDetails d) {
                if (_strokes.isEmpty) return;
                final List<double> s = _strokes.last;
                if (s.length >= maxPointsPerStroke * 2) return;
                setState(() => s..add(_n(d.localPosition.dx, side))..add(_n(d.localPosition.dy, side)));
                widget.onChanged(_copy());
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CustomPaint(painter: _StrokePainter(_strokes, Theme.of(context).colorScheme.onSurface),
                    size: Size.square(side)),
              ),
            ),
          ),
        );
      });

  List<List<double>> _copy() => <List<double>>[for (final List<double> s in _strokes) List<double>.of(s)];
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes, this.color);
  final List<List<double>> strokes;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final List<double> s in strokes) {
      if (s.length == 2) {
        canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), 2.5, p..style = PaintingStyle.fill);
        p.style = PaintingStyle.stroke;
        continue;
      }
      final Path path = Path()..moveTo(s[0] * size.width, s[1] * size.height);
      for (int i = 2; i + 1 < s.length; i += 2) {
        path.lineTo(s[i] * size.width, s[i + 1] * size.height);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

/// A drawing exactly as she made it. Used for her own box and, for a worry she
/// chose to show, in a grown-up's window.
class WorryDrawingView extends StatelessWidget {
  const WorryDrawingView({super.key, required this.strokes});
  final List<List<double>> strokes;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(14)),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(painter: _StrokePainter(strokes, Theme.of(context).colorScheme.onSurface),
                child: const SizedBox.expand())),
      );
}

/// One worry as a tile: its picture or its drawing, and nothing else.
class WorryThumb extends StatelessWidget {
  const WorryThumb({super.key, required this.worry, this.size = 96});
  final Worry worry;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size, height: size,
        child: worry.kind == WorryKind.picture
            ? FittedBox(child: PictureGlyph(worry.picture!, size: 44))
            : WorryDrawingView(strokes: worry.strokes!),
      );
}

/// "Look in the box": her own worries, and her three choices for each. There is
/// no number, no sort by how often, no "most", no tag.
class WorryShelfScreen extends StatelessWidget {
  const WorryShelfScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _WorryShelfScreenView(service: service, speak: speak));
}

class _WorryShelfScreenView extends StatefulWidget {
  const _WorryShelfScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_WorryShelfScreenView> createState() => _WorryShelfScreenState();
}

class _WorryShelfScreenState extends State<_WorryShelfScreenView> {
  List<Worry> _box = const <Worry>[];
  bool _loaded = false;
  Worry? _open;
  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Worry> b = await widget.service.myWorries(_me);
    if (mounted) {
      setState(() {
        _box = b;
        _loaded = true;
        final String? id = _open?.id;
        _open = id == null ? null : b.cast<Worry?>().firstWhere((Worry? w) => w!.id == id, orElse: () => null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RvChildPage(
      service: widget.service,
      title: 'In the box',
      body: !_loaded
          ? const SizedBox.shrink()
          : _open != null
              ? _detail(context, _open!)
              : _box.isEmpty
                  ? const QuietNote('The box is empty.', icon: Icons.inventory_2_outlined)
                  : Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
                      for (final Worry w in _box)
                        Semantics(
                          button: true, label: w.kind == WorryKind.picture ? pictureLabel(w.picture) : 'A drawing',
                          child: InkWell(
                            key: Key('worry_${w.id}'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() => _open = w),
                            child: Padding(padding: const EdgeInsets.all(4), child: WorryThumb(worry: w)),
                          ),
                        ),
                    ]),
    );
  }

  Widget _detail(BuildContext context, Worry w) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Center(child: WorryThumb(worry: w, size: 180)),
        const SizedBox(height: 8),
        if (w.shown)
          const Center(child: Text('Your grown-up can see this one.', key: Key('worryShownNote')))
        else
          const Center(child: Text('Just yours.', key: Key('worryPrivateNote'))),
        const SizedBox(height: 16),
        if (w.shown)
          PictureTile(key: const Key('worryHide'), picture: 'worry-other', label: 'Keep it just mine', minHeight: 72,
              onTap: () async { await widget.service.showWorryToGrownUp(_me, w.id, false); await _load(); })
        else
          PictureTile(key: const Key('worryShowLater'), picture: 'grown-up', label: 'Show my grown-up', minHeight: 72,
              onTap: () async { await widget.service.showWorryToGrownUp(_me, w.id, true); await _load(); }),
        const SizedBox(height: 10),
        PictureTile(key: const Key('worryFloatAway'), picture: 'worry-dream', label: 'Let it float away', minHeight: 72,
            onTap: () async {
              await widget.service.floatAwayWorry(_me, w.id);
              if (mounted) setState(() => _open = null);
              await _load();
            }),
        const SizedBox(height: 10),
        TextButton(key: const Key('worryShelfBack'), onPressed: () => setState(() => _open = null),
            child: const Text('Back')),
      ]);
}

// ================================================================ HELPERS ====
class MyHelpersScreen extends StatelessWidget {
  const MyHelpersScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _MyHelpersScreenView(service: service, speak: speak));
}

class _MyHelpersScreenView extends StatefulWidget {
  const _MyHelpersScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_MyHelpersScreenView> createState() => _MyHelpersScreenState();
}

class _MyHelpersScreenState extends State<_MyHelpersScreenView> {
  List<Helper>? _helpers;
  Helper? _open;
  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  @override
  void initState() {
    super.initState();
    widget.service.loadVoice(_me).then((VoiceDoc d) {
      if (mounted) setState(() => _helpers = helpersForChild(d.helpers));
    });
  }

  @override
  Widget build(BuildContext context) {
    final Speak? speak = SensoryScope.speakFor(context, widget.speak);
    final List<Helper>? hs = _helpers;
    return RvChildPage(
      service: widget.service,
      title: 'My helpers',
      body: hs == null
          ? const SizedBox.shrink()
          : hs.isEmpty
              ? const QuietNote('Your grown-up will add the people you can go to.', icon: Icons.people_outline)
              : _open != null
                  ? _detail(context, _open!, speak)
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      Text('The grown-ups you can go to', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      PictureGrid(children: <Widget>[
                        for (final Helper h in hs)
                          PictureTile(key: Key('helper_${h.id}'), picture: h.picture, label: h.name, speak: speak,
                              onTap: () => setState(() => _open = h)),
                      ]),
                    ]),
    );
  }

  Widget _detail(BuildContext context, Helper h, Speak? speak) =>
      Column(key: Key('helperDetail_${h.id}'), crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
        PictureGlyph(h.picture, size: 96),
        const SizedBox(height: 12),
        Text(h.name, style: Theme.of(context).textTheme.headlineMedium),
        if (h.line.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(h.line, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ],
        if (speak != null)
          SizedBox(height: 56, child: TextButton.icon(
              onPressed: () => speak(h.line.isEmpty ? h.name : '${h.name}. ${h.line}'),
              icon: const Icon(Icons.volume_up_outlined), label: const Text('Hear this'))),
        const SizedBox(height: 16),
        SizedBox(height: 64, child: OutlinedButton(
            key: const Key('helperBack'), onPressed: () => setState(() => _open = null), child: const Text('Back'))),
      ]);
}

// ================================================================ SYMBOLS ====
class SymbolBoardScreen extends StatelessWidget {
  const SymbolBoardScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _SymbolBoardScreenView(service: service, speak: speak));
}

class _SymbolBoardScreenView extends StatefulWidget {
  const _SymbolBoardScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_SymbolBoardScreenView> createState() => _SymbolBoardScreenState();
}

class _SymbolBoardScreenState extends State<_SymbolBoardScreenView> {
  List<String> _personal = const <String>[];
  List<String> _strip = const <String>[];
  bool _loaded = false;
  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  @override
  void initState() {
    super.initState();
    widget.service.loadVoice(_me).then((VoiceDoc d) {
      if (mounted) setState(() { _personal = d.personalSymbols; _loaded = true; });
    });
  }

  void _tap(String id, Speak? speak) {
    SensoryScope.tap(context);
    try {
      setState(() => _strip = stripAdd(_strip, id));
      speak?.call(pictureLabel(id));
    } on RvRefused {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That is a full sentence. Say it, or take one back.'), duration: Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Speak? speak = SensoryScope.speakFor(context, widget.speak);
    final String sentence = sentenceOf(_strip);
    return RvChildPage(
      service: widget.service,
      title: 'Say it with pictures',
      body: !_loaded
          ? const SizedBox.shrink()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Container(
                key: const Key('symbolStrip'),
                constraints: const BoxConstraints(minHeight: 120),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                child: Column(children: <Widget>[
                  Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: <Widget>[
                    for (final String id in _strip) PictureGlyph(id, size: 32),
                  ]),
                  const SizedBox(height: 8),
                  Text(sentence, key: const Key('symbolSentence'), textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                if (speak != null)
                  Expanded(child: SizedBox(height: 64, child: FilledButton.icon(
                      key: const Key('symbolSay'),
                      onPressed: _strip.isEmpty ? null : () => speak(sentence),
                      icon: const Icon(Icons.volume_up_outlined), label: const Text('Say it')))),
                if (speak != null) const SizedBox(width: 10),
                Expanded(child: SizedBox(height: 64, child: OutlinedButton.icon(
                    key: const Key('symbolBack'),
                    onPressed: _strip.isEmpty ? null : () => setState(() => _strip = stripBack(_strip)),
                    icon: const Icon(Icons.backspace_outlined), label: const Text('Take one back')))),
                const SizedBox(width: 10),
                Expanded(child: SizedBox(height: 64, child: OutlinedButton.icon(
                    key: const Key('symbolClear'),
                    onPressed: _strip.isEmpty ? null : () => setState(() => _strip = const <String>[]),
                    icon: const Icon(Icons.clear), label: const Text('Start again')))),
              ]),
              const SizedBox(height: 14),
              PictureGrid(minTile: 96, children: <Widget>[
                for (final String id in boardSymbols(_personal))
                  PictureTile(key: Key('symbol_$id'), picture: id, label: pictureLabel(id), minHeight: 96,
                      onTap: () => _tap(id, speak)),
              ]),
            ]),
    );
  }
}
