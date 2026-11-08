// OLIVE BRANCH — suite G (Growing) screens: time capsule, first times, memory
// box, pencil marks. No longer UNVERIFIED — verified by CI
// (client/test/growing_screens_test.dart). MASTERFILE section 8.17.
//
// LOCAL ONLY, and every screen says so. Grown-up side (time capsule, first
// times, growing marks) is where a guardian writes; her side (memory box, her
// growth picture, firsts she was shown, opened letters) is picture-first, 64 dp
// targets, read-only except for the memory box, which is hers.
//
// Rules the screens keep:
//  - A sealed capsule shows a guardian only its title and dates; the words and
//    photo appear when its day comes by THIS DEVICE'S CLOCK (said plainly on the
//    screen) or when a guardian chooses to open it early.
//  - There is no number of firsts, no streak, no list of firsts "still to come".
//  - Her growth picture is lines on a doorframe with a month under each: no
//    centimetres, no percentile, no average, no other child.
//  - Her memory box is hers: nothing resurfaces on its own and nothing here
//    sends or counts anything. No audio capture exists in this app yet, so it
//    keeps pictures and photos only.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'colouring_screen.dart' show ColouringThumbnail;
import 'doodle_desk.dart' show DoodleThumbnail;
import 'growing_care_logic.dart';
import 'growing_care_store.dart';
import 'growing_care_widgets.dart';
import 'shared_gallery.dart';
import 'snapshot_button.dart' show AppGallery, AppPhoto;

String _fmt(String iso) => dayMonthYear(iso);

// ======================================================= guardian: capsule ===
class TimeCapsuleScreen extends StatefulWidget {
  const TimeCapsuleScreen({super.key, this.childName = 'Ivy', this.stores, this.now, this.photoSource});
  final String childName;
  final GrowingCareStores? stores;
  final DateTime Function()? now;
  final PhotoSource? photoSource;

  @override
  State<TimeCapsuleScreen> createState() => _TimeCapsuleScreenState();
}

class _TimeCapsuleScreenState extends State<TimeCapsuleScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  late final DateTime Function() _now = widget.now ?? DateTime.now;
  final IdMaker _ids = IdMaker();
  List<TimeCapsule> _all = <TimeCapsule>[];
  bool _loaded = false;

  String get _today => isoOf(_now());

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<TimeCapsule> all = await _s.capsules.list();
    all.sort((TimeCapsule a, TimeCapsule b) => a.opensOn.compareTo(b.opensOn));
    if (mounted) setState(() { _all = all; _loaded = true; });
  }

  Future<void> _add() async {
    final bool? saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => _CapsuleForm(stores: _s, now: _now, ids: _ids, photoSource: widget.photoSource ?? pickSmallPhoto)));
    if (saved == true) await _load();
  }

  Future<void> _unseal(TimeCapsule c) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext x) => AlertDialog(
        title: const Text('Open this early?'),
        content: const Text('Once opened, it stays open. Only do this if you mean to.'),
        actions: <Widget>[
          TextButton(key: const Key('keepSealed'), onPressed: () => Navigator.of(x).pop(false), child: const Text('Keep it sealed')),
          TextButton(key: const Key('openNow'), onPressed: () => Navigator.of(x).pop(true), child: const Text('Open it')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _s.capsules.save(c.unsealed(_today));
    } on CareRefused catch (e) {
      if (mounted) showRefusal(context, e);
    }
    await _load();
  }

  Future<void> _remove(TimeCapsule c) async {
    if (!await confirmPutAway(context, 'Remove "${c.title}"?')) return;
    await _s.capsules.remove(c.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final String today = _today;
    return Scaffold(
      appBar: AppBar(title: const Text('Time capsule')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const LocalOnlyBanner(capsuleClockNote),
        const SizedBox(height: 8),
        if (!_loaded) const Center(child: CircularProgressIndicator()),
        if (_loaded && _all.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text(
              'Nothing sealed yet. Write a note for a day to come, and it stays closed until then.',
              key: Key('capsuleEmpty'), textAlign: TextAlign.center)),
        for (final TimeCapsule c in _all) _CapsuleCard(
            key: ValueKey<String>('capsule-${c.id}'), view: c.forGuardian(today),
            onUnseal: () => _unseal(c), onRemove: () => _remove(c)),
        const SizedBox(height: 12),
        FilledButton.icon(
            key: const Key('sealSomething'), onPressed: _add,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.lock_outline), label: const Text('Seal something for later')),
      ])),
    );
  }
}

class _CapsuleCard extends StatelessWidget {
  const _CapsuleCard({super.key, required this.view, required this.onUnseal, required this.onRemove});
  final GuardianCapsuleView view;
  final VoidCallback onUnseal;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(view.open ? Icons.lock_open_outlined : Icons.lock_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(view.title, style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 4),
          Text(view.open ? 'Opened (it opens on ${_fmt(view.opensOn)})' : 'Sealed. Opens on ${_fmt(view.opensOn)}.'),
          if (!view.open) const Padding(padding: EdgeInsets.only(top: 6),
              child: Text('The words stay hidden, even from you, until it opens.', key: Key('sealedHidden'))),
          if (view.open && view.note != null && view.note!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(view.note!, key: const Key('capsuleNote'))),
          if (view.open && view.thumb != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: ThumbImage(view.thumb!, size: 96)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: <Widget>[
            if (!view.open)
              OutlinedButton(key: const Key('unseal'), onPressed: onUnseal, child: const Text('Open it early')),
            TextButton(key: const Key('removeCapsule'), onPressed: onRemove, child: const Text('Remove')),
          ]),
        ]),
      ));
}

class _CapsuleForm extends StatefulWidget {
  const _CapsuleForm({required this.stores, required this.now, required this.ids, required this.photoSource});
  final GrowingCareStores stores;
  final DateTime Function() now;
  final IdMaker ids;
  final PhotoSource photoSource;

  @override
  State<_CapsuleForm> createState() => _CapsuleFormState();
}

class _CapsuleFormState extends State<_CapsuleForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _opens = TextEditingController();
  Uint8List? _thumb;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _opens.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final Uint8List? b = await widget.photoSource();
    if (b == null || !mounted) return;
    final String? why = thumbRefusal(b);
    if (why != null) {
      setState(() => _error = refusalMessage(why));
      return;
    }
    setState(() { _thumb = b; _error = null; });
  }

  Future<void> _seal() async {
    final String today = isoOf(widget.now());
    final TimeCapsule c = TimeCapsule(
        id: widget.ids.next('c'), title: _title.text.trim(), note: _note.text.trim(),
        sealedOn: today, opensOn: _opens.text.trim(), thumb: _thumb);
    try {
      await widget.stores.capsules.save(c);
      if (mounted) Navigator.of(context).pop(true);
    } on CareRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Seal something')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          const LocalOnlyBanner(capsuleClockNote),
          const SizedBox(height: 12),
          TextField(key: const Key('capsuleTitle'), controller: _title, maxLength: maxTitleChars,
              decoration: const InputDecoration(labelText: 'A name for it', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(key: const Key('capsuleNoteField'), controller: _note, maxLines: 6, maxLength: maxCapsuleNoteChars,
              decoration: const InputDecoration(labelText: 'What you want to say', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          IsoDateField(key: const Key('capsuleOpens'), controller: _opens, label: 'Opens on',
              today: isoOf(widget.now()), future: true),
          const SizedBox(height: 8),
          PhotoPickerRow(bytes: _thumb, onPick: _pick, onClear: () => setState(() => _thumb = null)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const Key('formError'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(key: const Key('sealIt'), onPressed: _seal,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Seal it')),
        ])),
      );
}

// ===================================================== guardian: first times ==
class FirstTimesScreen extends StatefulWidget {
  const FirstTimesScreen({super.key, this.childName = 'Ivy', this.stores, this.now, this.photoSource});
  final String childName;
  final GrowingCareStores? stores;
  final DateTime Function()? now;
  final PhotoSource? photoSource;

  @override
  State<FirstTimesScreen> createState() => _FirstTimesScreenState();
}

class _FirstTimesScreenState extends State<FirstTimesScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  late final DateTime Function() _now = widget.now ?? DateTime.now;
  final IdMaker _ids = IdMaker();
  List<FirstTime> _all = <FirstTime>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<FirstTime> all = firstsNewestFirst(await _s.firsts.list());
    if (mounted) setState(() { _all = all; _loaded = true; });
  }

  Future<void> _add() async {
    final bool? saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => _FirstForm(stores: _s, now: _now, ids: _ids, photoSource: widget.photoSource ?? pickSmallPhoto)));
    if (saved == true) await _load();
  }

  Future<void> _toggleHer(FirstTime f, bool v) async {
    try {
      await _s.firsts.save(FirstTime(id: f.id, title: f.title, on: f.on, note: f.note, thumb: f.thumb, showHer: v));
    } on CareRefused catch (e) {
      if (mounted) showRefusal(context, e);
    }
    await _load();
  }

  Future<void> _remove(FirstTime f) async {
    if (!await confirmPutAway(context, 'Remove "${f.title}"?')) return;
    await _s.firsts.remove(f.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('First times')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          const LocalOnlyBanner('$localOnlyNote A record of what happened, never a to-do list.'),
          const SizedBox(height: 8),
          if (!_loaded) const Center(child: CircularProgressIndicator()),
          if (_loaded && _all.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text(
                'When something happens for the first time, add it here.', key: Key('firstsEmpty'), textAlign: TextAlign.center)),
          for (final FirstTime f in _all) Card(
              key: ValueKey<String>('first-${f.id}'),
              child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  if (f.thumb != null) ...<Widget>[ThumbImage(f.thumb!, size: 64), const SizedBox(width: 10)],
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(f.title, style: Theme.of(context).textTheme.titleMedium),
                    Text(_fmt(f.on)),
                    if (f.note.isNotEmpty) Text(f.note),
                  ])),
                ]),
                SwitchListTile(
                    key: ValueKey<String>('showHer-${f.id}'), contentPadding: EdgeInsets.zero,
                    title: const Text('Show her this one'), value: f.showHer, onChanged: (bool v) => _toggleHer(f, v)),
                Align(alignment: Alignment.centerRight,
                    child: TextButton(key: ValueKey<String>('removeFirst-${f.id}'), onPressed: () => _remove(f), child: const Text('Remove'))),
              ]))),
          const SizedBox(height: 12),
          FilledButton.icon(
              key: const Key('addFirst'), onPressed: _add,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.add), label: const Text('A first happened')),
        ])),
      );
}

class _FirstForm extends StatefulWidget {
  const _FirstForm({required this.stores, required this.now, required this.ids, required this.photoSource});
  final GrowingCareStores stores;
  final DateTime Function() now;
  final IdMaker ids;
  final PhotoSource photoSource;

  @override
  State<_FirstForm> createState() => _FirstFormState();
}

class _FirstFormState extends State<_FirstForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  late final TextEditingController _on = TextEditingController(text: isoOf(widget.now()));
  Uint8List? _thumb;
  bool _showHer = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _on.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final Uint8List? b = await widget.photoSource();
    if (b == null || !mounted) return;
    final String? why = thumbRefusal(b);
    setState(() { if (why != null) { _error = refusalMessage(why); } else { _thumb = b; _error = null; } });
  }

  Future<void> _save() async {
    final String today = isoOf(widget.now());
    final String on = _on.text.trim();
    if (isoOf(DateTime.tryParse(on) ?? DateTime(1900)) == on && on.compareTo(today) > 0) {
      setState(() => _error = refusalMessage('date_in_future'));
      return;
    }
    try {
      await widget.stores.firsts.save(FirstTime(
          id: widget.ids.next('f'), title: _title.text.trim(), on: on, note: _note.text.trim(),
          thumb: _thumb, showHer: _showHer));
      if (mounted) Navigator.of(context).pop(true);
    } on CareRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('A first happened')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          TextField(key: const Key('firstTitle'), controller: _title, maxLength: maxTitleChars,
              decoration: const InputDecoration(labelText: 'What happened', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          IsoDateField(key: const Key('firstDate'), controller: _on, label: 'When', today: isoOf(widget.now())),
          const SizedBox(height: 8),
          TextField(key: const Key('firstNote'), controller: _note, maxLines: 3, maxLength: maxFirstNoteChars,
              decoration: const InputDecoration(labelText: 'A few words (optional)', border: OutlineInputBorder())),
          PhotoPickerRow(bytes: _thumb, onPick: _pick, onClear: () => setState(() => _thumb = null)),
          SwitchListTile(key: const Key('firstShowHer'), contentPadding: EdgeInsets.zero,
              title: const Text('Show her this one'), value: _showHer, onChanged: (bool v) => setState(() => _showHer = v)),
          if (_error != null) Text(_error!, key: const Key('formError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton(key: const Key('saveFirst'), onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Keep it')),
        ])),
      );
}

// ================================================== guardian: growing marks ===
class PencilMarksScreen extends StatefulWidget {
  const PencilMarksScreen({super.key, this.childName = 'Ivy', this.stores, this.now, this.photoSource});
  final String childName;
  final GrowingCareStores? stores;
  final DateTime Function()? now;
  final PhotoSource? photoSource;

  @override
  State<PencilMarksScreen> createState() => _PencilMarksScreenState();
}

class _PencilMarksScreenState extends State<PencilMarksScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  late final DateTime Function() _now = widget.now ?? DateTime.now;
  final IdMaker _ids = IdMaker();
  final TextEditingController _cm = TextEditingController();
  late final TextEditingController _on = TextEditingController(text: isoOf(_now()));
  List<PencilMark> _all = <PencilMark>[];
  Uint8List? _thumb;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _cm.dispose();
    _on.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<PencilMark> all = await _s.marks.list();
    all.sort((PencilMark a, PencilMark b) => b.on.compareTo(a.on));
    if (mounted) setState(() { _all = all; _loaded = true; });
  }

  Future<void> _pick() async {
    final Uint8List? b = await (widget.photoSource ?? pickSmallPhoto)();
    if (b == null || !mounted) return;
    final String? why = thumbRefusal(b);
    setState(() { if (why != null) { _error = refusalMessage(why); } else { _thumb = b; _error = null; } });
  }

  Future<void> _add() async {
    final int? cm = int.tryParse(_cm.text.trim());
    final String on = _on.text.trim();
    if (cm == null) {
      setState(() => _error = refusalMessage('bad_height'));
      return;
    }
    if (on.compareTo(isoOf(_now())) > 0) {
      setState(() => _error = refusalMessage('date_in_future'));
      return;
    }
    try {
      await _s.marks.save(PencilMark(id: _ids.next('m'), on: on, cm: cm, thumb: _thumb));
      _cm.clear();
      setState(() { _thumb = null; _error = null; });
      await _load();
    } on CareRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _remove(PencilMark m) async {
    if (!await confirmPutAway(context, 'Remove this mark?')) return;
    await _s.marks.remove(m.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Growing marks')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          const LocalOnlyBanner('$localOnlyNote These heights are your own record. Her app shows her only a picture '
              'of her marks, with no numbers and no one to compare with.'),
          const SizedBox(height: 8),
          if (_loaded) SizedBox(height: 200, child: DoorframePicture(marks: growthPicture(_all))),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(child: TextField(key: const Key('markCm'), controller: _cm, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Height (cm)', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: IsoDateField(key: const Key('markDate'), controller: _on, label: 'Date', today: isoOf(_now()))),
          ]),
          const SizedBox(height: 8),
          PhotoPickerRow(bytes: _thumb, onPick: _pick, onClear: () => setState(() => _thumb = null), label: 'Add a photo by the doorframe'),
          if (_error != null) Text(_error!, key: const Key('formError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          FilledButton.icon(key: const Key('addMark'), onPressed: _add,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.straighten), label: const Text("Add today's mark")),
          const SizedBox(height: 12),
          for (final PencilMark m in _all) Card(
              key: ValueKey<String>('mark-${m.id}'),
              child: ListTile(
                leading: m.thumb == null ? const Icon(Icons.straighten) : ThumbImage(m.thumb!, size: 48),
                title: Text('${m.cm} cm'), subtitle: Text(_fmt(m.on)),
                trailing: IconButton(key: ValueKey<String>('removeMark-${m.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: () => _remove(m)),
              )),
        ])),
      );
}

/// Her doorframe: a post with a pencil line for each mark and a month beside
/// it. No scale, no numbers, nothing to compare with.
class DoorframePicture extends StatelessWidget {
  const DoorframePicture({super.key, required this.marks});
  final List<GrowthMarkView> marks;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double h = c.maxHeight.isFinite ? c.maxHeight : 240;
      return Container(
        key: const Key('doorframe'),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant)),
        child: Stack(children: <Widget>[
          Positioned(left: 24, top: 8, bottom: 8, width: 10,
              child: DecoratedBox(decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(4)))),
          if (marks.isEmpty)
            const Center(child: Text('The doorframe is waiting for its first mark.', textAlign: TextAlign.center)),
          for (final GrowthMarkView m in marks)
            Positioned(
              left: 24, right: 16, bottom: 12 + (h - 56) * m.fraction,
              child: Row(key: ValueKey<String>('doormark-${m.id}'), children: <Widget>[
                Container(width: 44, height: 4, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text(m.label, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
        ]),
      );
    });
  }
}

// ============================================================ her: marks ====
class GrowthPictureScreen extends StatefulWidget {
  const GrowthPictureScreen({super.key, this.childName = 'Ivy', this.lens});
  final String childName;
  final ChildGrowingLens? lens;

  @override
  State<GrowthPictureScreen> createState() => _GrowthPictureScreenState();
}

class _GrowthPictureScreenState extends State<GrowthPictureScreen> {
  late final ChildGrowingLens _lens = widget.lens ?? GrowingCareStores.forChild().childLens();
  List<GrowthMarkView>? _marks;

  @override
  void initState() {
    super.initState();
    unawaited(_lens.growth().then((List<GrowthMarkView> m) { if (mounted) setState(() => _marks = m); }));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My doorframe')),
        body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: <Widget>[
          Text('Look how you are growing, ${widget.childName}.', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Expanded(child: _marks == null ? const SizedBox.shrink() : DoorframePicture(marks: _marks!)),
        ]))),
      );
}

// ============================================================ her: firsts ===
class MyFirstsScreen extends StatefulWidget {
  const MyFirstsScreen({super.key, this.lens});
  final ChildGrowingLens? lens;

  @override
  State<MyFirstsScreen> createState() => _MyFirstsScreenState();
}

class _MyFirstsScreenState extends State<MyFirstsScreen> {
  late final ChildGrowingLens _lens = widget.lens ?? GrowingCareStores.forChild().childLens();
  List<FirstTime>? _firsts;

  @override
  void initState() {
    super.initState();
    unawaited(_lens.shownFirsts().then((List<FirstTime> f) { if (mounted) setState(() => _firsts = f); }));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Times I did something new')),
        body: SafeArea(child: _firsts == null ? const SizedBox.shrink() : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          if (_firsts!.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nothing here yet.', textAlign: TextAlign.center)),
          for (final FirstTime f in _firsts!) Card(
              key: ValueKey<String>('myfirst-${f.id}'),
              child: Container(
                constraints: const BoxConstraints(minHeight: childTarget), padding: const EdgeInsets.all(12),
                child: Row(children: <Widget>[
                  if (f.thumb != null) ...<Widget>[ThumbImage(f.thumb!, size: 80), const SizedBox(width: 12)] else ...<Widget>[const Icon(Icons.star_outline, size: 40), const SizedBox(width: 12)],
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(f.title, style: Theme.of(context).textTheme.titleMedium),
                    Text(monthYear(f.on)),
                    if (f.note.isNotEmpty) Text(f.note),
                  ])),
                ]),
              )),
        ])),
      );
}

// ============================================================ her: letters ==
/// Letters whose day has come. A sealed capsule is simply not here.
class LettersOpenedScreen extends StatefulWidget {
  const LettersOpenedScreen({super.key, this.lens});
  final ChildGrowingLens? lens;

  @override
  State<LettersOpenedScreen> createState() => _LettersOpenedScreenState();
}

class _LettersOpenedScreenState extends State<LettersOpenedScreen> {
  late final ChildGrowingLens _lens = widget.lens ?? GrowingCareStores.forChild().childLens();
  List<TimeCapsule>? _letters;

  @override
  void initState() {
    super.initState();
    unawaited(_lens.openedLetters().then((List<TimeCapsule> l) { if (mounted) setState(() => _letters = l); }));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('A letter for you')),
        body: SafeArea(child: _letters == null ? const SizedBox.shrink() : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          if (_letters!.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nothing here yet.', textAlign: TextAlign.center)),
          for (final TimeCapsule c in _letters!) Card(
              key: ValueKey<String>('letter-${c.id}'),
              child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(c.title, style: Theme.of(context).textTheme.titleLarge),
                if (c.thumb != null) Padding(padding: const EdgeInsets.only(top: 8), child: ThumbImage(c.thumb!, size: 160)),
                if (c.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.note, style: Theme.of(context).textTheme.bodyLarge)),
              ]))),
        ])),
      );
}

// ========================================================= her: memory box ==
class MemoryBoxScreen extends StatefulWidget {
  const MemoryBoxScreen({super.key, this.childName = 'Ivy', this.stores, this.gallery, this.photoSource, this.now});
  final String childName;
  final GrowingCareStores? stores;
  final AppGallery? gallery;
  final PhotoSource? photoSource;
  final DateTime Function()? now;

  @override
  State<MemoryBoxScreen> createState() => _MemoryBoxScreenState();
}

class _MemoryBoxScreenState extends State<MemoryBoxScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  late final AppGallery _gallery = widget.gallery ?? demoAppGallery;
  late final DateTime Function() _now = widget.now ?? DateTime.now;
  final IdMaker _ids = IdMaker();
  List<MemoryItem> _items = <MemoryItem>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _gallery.ensureBound();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<MemoryItem> all = await _s.memories.list();
    all.sort((MemoryItem a, MemoryItem b) => b.addedOn.compareTo(a.addedOn));
    if (mounted) setState(() { _items = all; _loaded = true; });
  }

  Future<void> _save(MemoryItem m) async {
    try {
      await _s.memories.save(m);
      await _load();
    } on CareRefused catch (e) {
      if (mounted) showRefusal(context, e);
    }
  }

  Future<void> _keepPicture() async {
    await _gallery.load();
    if (!mounted) return;
    final List<AppPhoto> mine = <AppPhoto>[
      for (final AppPhoto p in _gallery.photos) if (p.data != null && (p.kind == 'doodle' || p.kind == 'colouring')) p,
    ];
    final AppPhoto? chosen = await showModalBottomSheet<AppPhoto>(
      context: context,
      builder: (BuildContext c) => SafeArea(child: mine.isEmpty
          ? const Padding(padding: EdgeInsets.all(24), child: Text('Make a picture first, then you can keep it here.', key: Key('noPicturesYet')))
          : GridView.count(
              crossAxisCount: 3, padding: const EdgeInsets.all(12), mainAxisSpacing: 8, crossAxisSpacing: 8,
              children: <Widget>[
                for (final AppPhoto p in mine) InkWell(
                    key: ValueKey<String>('choose-${p.id}'), onTap: () => Navigator.of(c).pop(p),
                    child: _PictureThumb(kind: p.kind, data: p.data!)),
              ])),
    );
    if (chosen == null) return;
    await _save(MemoryItem(
        id: _ids.next('m'), kind: chosen.kind, addedOn: isoOf(_now()), pictureData: chosen.data));
  }

  Future<void> _keepPhoto() async {
    final Uint8List? b = await (widget.photoSource ?? pickSmallPhoto)();
    if (b == null || !mounted) return;
    await _save(MemoryItem(id: _ids.next('m'), kind: 'photo', addedOn: isoOf(_now()), thumb: b));
  }

  Future<void> _putAway(MemoryItem m) async {
    if (!await confirmPutAway(context, 'Put this away?')) return;
    await _s.memories.remove(m.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My memory box')),
        body: SafeArea(child: Column(children: <Widget>[
          const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: LocalOnlyBanner('Things you chose to keep. They stay on this device.')),
          Expanded(child: !_loaded ? const SizedBox.shrink() : _items.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(Icons.inventory_2_outlined, size: 64),
                  SizedBox(height: 12),
                  Text("It's yours. Keep things here whenever you like.", key: Key('memoryEmpty'), textAlign: TextAlign.center),
                ])))
              : GridView.count(crossAxisCount: 2, padding: const EdgeInsets.all(16), mainAxisSpacing: 12, crossAxisSpacing: 12, children: <Widget>[
                  for (final MemoryItem m in _items) GestureDetector(
                      key: ValueKey<String>('memory-${m.id}'), onLongPress: () => _putAway(m),
                      child: Container(
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Theme.of(context).colorScheme.primaryContainer),
                        clipBehavior: Clip.antiAlias, alignment: Alignment.center,
                        child: m.kind == 'photo' && m.thumb != null
                            ? Image.memory(m.thumb!, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                                errorBuilder: (BuildContext c, Object e, StackTrace? s) => const Icon(Icons.image_outlined, size: 40))
                            : _PictureThumb(kind: m.kind, data: m.pictureData ?? const <String, Object?>{}),
                      )),
                ])),
          Padding(padding: const EdgeInsets.all(16), child: Row(children: <Widget>[
            Expanded(child: FilledButton.icon(
                key: const Key('keepPicture'), onPressed: _keepPicture,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(childTarget)),
                icon: const Icon(Icons.brush_outlined), label: const Text('A picture I made'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(
                key: const Key('keepPhoto'), onPressed: _keepPhoto,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(childTarget)),
                icon: const Icon(Icons.photo_outlined), label: const Text('A photo'))),
          ])),
        ])),
      );
}

class _PictureThumb extends StatelessWidget {
  const _PictureThumb({required this.kind, required this.data});
  final String kind;
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    if (kind == 'doodle') return DoodleThumbnail(data: data);
    if (kind == 'colouring') return ColouringThumbnail(data: data);
    return const Icon(Icons.image_outlined, size: 40);
  }
}
