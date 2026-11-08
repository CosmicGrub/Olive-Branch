// OLIVE BRANCH — suites B and C, the guardian's side: the editors and the one
// window onto what she chose to show. No longer UNVERIFIED — verified by CI
// (client/test/rhythm_voice_guardian_screens_test.dart).
//
// GUARDIAN-ONLY. Everything a child sees in Rhythm and Voice is written here, by
// a guardian, and only a guardian principal can save it (the service refuses the
// child principal: see rhythm_voice_repositories.dart). The child shell never
// imports this file. Entry points: the guardian Settings hub (Family group) in
// guardian_more.dart.
//
// ON THIS DEVICE ONLY, said plainly on every hub: nothing here is sent anywhere,
// and nothing is shared with her other home yet (that is parked).
//
// WHAT A GUARDIAN CANNOT DO HERE, by design:
//  - read her feelings weather: no screen, and the service refuses the read;
//  - read her worry box: only the worries she chose to "show my grown-up" appear
//    (SharedWorriesScreen), exactly as she made them, with no note, tag, count or
//    reading of them, and no way to delete one (the box is hers);
//  - label her: "How the app feels" is about the app, never a diagnosis.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'family_structure_logic.dart' show FamilyPrincipal;
import 'picture_icons.dart';
import 'picture_library.dart';
import 'rhythm_logic.dart';
import 'rhythm_voice_gate.dart';
import 'rhythm_voice_repositories.dart';
import 'voice_logic.dart';
import 'voice_screens.dart' show WorryThumb;

/// The plain-words explanation of a refusal.
String refusalText(String reason) => switch (reason) {
      'guardian_only' => 'Only a grown-up can change this.',
      'empty_text' || 'too_long' || 'bad_text' => 'Please use a short name.',
      'looks_like_location' => 'Please leave out addresses and places. Rooms only.',
      'looks_like_number' => 'Please leave out phone numbers.',
      'too_many_steps' || 'too_many_items' || 'too_many_same' || 'too_many_stops' || 'too_many_lines' ||
      'too_many_helpers' || 'too_many_symbols' => 'That is the most there is room for.',
      'duplicate_id' || 'same_card' => 'That one is already there.',
      'photo_too_big' || 'bad_photo' => 'That photo would not work. Choose a smaller picture.',
      'full' => 'There is no more room on this device.',
      _ => 'That did not save.',
    };

typedef PickRoomPhoto = Future<List<int>?> Function();

/// The real photo picker: a gallery pick, scaled and compressed by the platform
/// so it fits the size bound. Tests inject their own.
Future<List<int>?> pickRoomPhotoFromGallery() async {
  final XFile? f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 640, imageQuality: 60);
  return f?.readAsBytes();
}

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

/// Snack-bar helpers for the editors' States; every use re-checks `mounted`.
mixin _Reporter<T extends StatefulWidget> on State<T> {
  void say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void report(RvResult r) => say(r.ok ? 'Saved on this device.' : refusalText(r.reason));
}

Future<String?> pickPicture(BuildContext context, PictureGroup group, {Set<String> hide = const <String>{}}) =>
    showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Choose a picture'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: PictureGrid(minTile: 96, children: <Widget>[
              for (final PictureDef p in picturesIn(group))
                if (!hide.contains(p.id))
                  PictureTile(key: Key('pick_${p.id}'), picture: p.id, label: p.label, minHeight: 88,
                      onTap: () => Navigator.of(ctx).pop(p.id)),
            ]),
          ),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel'))],
      ),
    );

Future<String?> askText(BuildContext context, String title, String initial, {String? hint, int maxLength = maxTitleChars}) {
  final TextEditingController c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: TextField(key: const Key('askText'), controller: c, autofocus: true, maxLength: maxLength,
          decoration: InputDecoration(hintText: hint)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        FilledButton(key: const Key('askTextOk'), onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('OK')),
      ],
    ),
  );
}

class _LocalOnlyNote extends StatelessWidget {
  const _LocalOnlyNote(this.childName);
  final String childName;
  @override
  Widget build(BuildContext context) => QuietNote(
      'Kept on this device only. It is not shared with $childName\'s other home yet.',
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

String _ageNote(String childName, int? yearsOld) {
  final String band = bandFor(yearsOld: yearsOld);
  return band == 't34'
      ? '$childName is under five, so none of this shows on her device yet. It opens from five.'
      : 'Shown on $childName\'s device from age five, and only when the switch below is on.';
}

// =============================================================== B HUB =======
class RhythmGuardianHubScreen extends StatefulWidget {
  const RhythmGuardianHubScreen({super.key, required this.childName, required this.service, required this.principal,
      this.yearsOld, this.pickPhoto});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  final int? yearsOld;
  final PickRoomPhoto? pickPhoto;
  @override
  State<RhythmGuardianHubScreen> createState() => _RhythmGuardianHubState();
}

class _RhythmGuardianHubState extends State<RhythmGuardianHubScreen> with _Reporter<RhythmGuardianHubScreen> {
  bool _on = true;
  @override
  void initState() {
    super.initState();
    widget.service.loadRhythm(widget.principal).then((RhythmDoc d) {
      if (mounted) setState(() => _on = d.suiteOn);
    }).catchError((Object _) {});
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final String n = widget.childName;
    final RhythmVoiceService s = widget.service;
    final FamilyPrincipal p = widget.principal;
    return _Page(title: 'Routine and rhythm', children: <Widget>[
      _LocalOnlyNote(n),
      const SizedBox(height: 8),
      Text(_ageNote(n, widget.yearsOld), key: const Key('rhythmAgeNote')),
      SwitchListTile(
        key: const Key('rhythmSuite'), value: _on, title: Text('Show on $n\'s device'),
        onChanged: (bool v) async {
          final RvResult r = await s.setRhythmSuite(p, v);
          if (r.ok) setState(() => _on = v);
          report(r);
        },
      ),
      _Row(key: const Key('rowRoutine'), icon: Icons.checklist_outlined, title: 'One routine',
          subtitle: 'Pictures in order, like bedtime', onTap: () => _push(RoutineEditorScreen(childName: n, service: s, principal: p))),
      _Row(key: const Key('rowBoard'), icon: Icons.swap_horiz, title: 'First, then',
          subtitle: 'Two cards: what happens first, what next', onTap: () => _push(FirstThenEditorScreen(childName: n, service: s, principal: p))),
      _Row(key: const Key('rowPacking'), icon: Icons.backpack_outlined, title: 'Packing buddy',
          subtitle: 'The picture list for the exchange bag', onTap: () => _push(PackingEditorScreen(childName: n, service: s, principal: p))),
      _Row(key: const Key('rowPlace'), icon: Icons.home_outlined, title: 'A new place',
          subtitle: 'A gentle preview: rooms and a short plan',
          onTap: () => _push(NewPlaceEditorScreen(childName: n, service: s, principal: p, pickPhoto: widget.pickPhoto ?? pickRoomPhotoFromGallery))),
      _Row(key: const Key('rowSensory'), icon: Icons.tune, title: 'How the app feels',
          subtitle: 'Sound, motion and brightness on her device', onTap: () => _push(SensoryEditorScreen(childName: n, service: s, principal: p))),
    ]);
  }
}

// ========================================================= ROUTINE EDITOR ====
class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<RoutineEditorScreen> with _Reporter<RoutineEditorScreen> {
  Routine _r = const Routine();
  final TextEditingController _title = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.service.loadRhythm(widget.principal).then((RhythmDoc d) {
      if (!mounted) return;
      setState(() {
        _r = d.routine ?? const Routine();
        _title.text = _r.title;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _try(Routine Function() change) {
    try {
      setState(() => _r = change());
    } on RvRefused catch (e) {
      say(refusalText(e.reason));
    }
  }

  Future<void> _add() async {
    final String? pic = await pickPicture(context, PictureGroup.routine);
    if (pic == null || !mounted) return;
    _try(() => addStep(_r, newStep(widget.service.newId('s'), pic)));
  }

  Future<void> _rename(RoutineStep s) async {
    final String? t = await askText(context, 'Name this step', s.label);
    if (t == null || !mounted) return;
    _try(() {
      final RoutineStep n = RoutineStep(id: s.id, picture: s.picture, label: cleanText(t));
      return Routine(title: _r.title, steps: <RoutineStep>[for (final RoutineStep x in _r.steps) x.id == s.id ? n : x]);
    });
  }

  Future<void> _save() async {
    try {
      final Routine r = renameRoutine(_r, _title.text);
      final RvResult res = await widget.service.saveRoutine(widget.principal, r);
      if (res.ok) setState(() => _r = r);
      report(res);
    } on RvRefused catch (e) {
      say(refusalText(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'One routine', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        if (_loaded) ...<Widget>[
          TextField(key: const Key('routineTitle'), controller: _title, maxLength: maxTitleChars,
              decoration: const InputDecoration(labelText: 'Name of the routine', border: OutlineInputBorder())),
          for (int i = 0; i < _r.steps.length; i++)
            Card(
              key: Key('step_${_r.steps[i].id}'),
              child: ListTile(
                leading: PictureGlyph(_r.steps[i].picture, size: 24),
                title: Text(_r.steps[i].label),
                onTap: () => _rename(_r.steps[i]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  IconButton(key: Key('stepUp_${_r.steps[i].id}'), tooltip: 'Move up', icon: const Icon(Icons.arrow_upward),
                      onPressed: i == 0 ? null : () => _try(() => moveStep(_r, i, i - 1))),
                  IconButton(key: Key('stepDown_${_r.steps[i].id}'), tooltip: 'Move down', icon: const Icon(Icons.arrow_downward),
                      onPressed: i == _r.steps.length - 1 ? null : () => _try(() => moveStep(_r, i, i + 1))),
                  IconButton(key: Key('stepRemove_${_r.steps[i].id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline),
                      onPressed: () => _try(() => removeStep(_r, _r.steps[i].id))),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('stepAdd'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add a step')),
          const SizedBox(height: 8),
          FilledButton(key: const Key('routineSave'), onPressed: _save, child: const Text('Save')),
          TextButton(key: const Key('routineClear'), onPressed: () async {
            final RvResult r = await widget.service.clearRoutine(widget.principal);
            if (r.ok) setState(() { _r = const Routine(); _title.text = _r.title; });
            report(r);
          }, child: const Text('Remove the routine from her device')),
        ],
      ]);
}

// ======================================================= FIRST, THEN EDITOR ==
class FirstThenEditorScreen extends StatefulWidget {
  const FirstThenEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  @override
  State<FirstThenEditorScreen> createState() => _FirstThenEditorState();
}

class _FirstThenEditorState extends State<FirstThenEditorScreen> with _Reporter<FirstThenEditorScreen> {
  String? _first;
  String? _then;
  @override
  void initState() {
    super.initState();
    widget.service.loadRhythm(widget.principal).then((RhythmDoc d) {
      if (mounted) setState(() { _first = d.board?.first.picture; _then = d.board?.then.picture; });
    });
  }

  Future<void> _choose(bool first) async {
    final String? p = await pickPicture(context, PictureGroup.routine);
    if (p != null && mounted) setState(() => first ? _first = p : _then = p);
  }

  Future<void> _save() async {
    if (_first == null || _then == null) return say('Choose both cards first.');
    try {
      final RvResult r = await widget.service.saveBoard(widget.principal, makeBoard(boardCard(_first!), boardCard(_then!)));
      report(r);
    } on RvRefused catch (e) {
      say(refusalText(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'First, then', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(child: PictureTile(key: const Key('boardPickFirst'), picture: _first ?? 'wake-up',
              label: _first == null ? 'Choose First' : 'First: ${pictureLabel(_first)}', onTap: () => _choose(true))),
          const SizedBox(width: 12),
          Expanded(child: PictureTile(key: const Key('boardPickThen'), picture: _then ?? 'play',
              label: _then == null ? 'Choose Then' : 'Then: ${pictureLabel(_then)}', onTap: () => _choose(false))),
        ]),
        const SizedBox(height: 12),
        FilledButton(key: const Key('boardSave'), onPressed: _save, child: const Text('Save')),
        TextButton(key: const Key('boardClear'), onPressed: () async {
          final RvResult r = await widget.service.clearBoard(widget.principal);
          if (r.ok) setState(() { _first = null; _then = null; });
          report(r);
        }, child: const Text('Remove the cards from her device')),
      ]);
}

// ========================================================= PACKING EDITOR ====
class PackingEditorScreen extends StatefulWidget {
  const PackingEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  @override
  State<PackingEditorScreen> createState() => _PackingEditorState();
}

class _PackingEditorState extends State<PackingEditorScreen> with _Reporter<PackingEditorScreen> {
  PackingList _l = const PackingList();
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    widget.service.loadRhythm(widget.principal).then((RhythmDoc d) {
      if (mounted) setState(() { _l = d.packing; _loaded = true; });
    });
  }

  void _try(PackingList Function() change) {
    try {
      setState(() => _l = change());
    } on RvRefused catch (e) {
      say(refusalText(e.reason));
    }
  }

  Future<void> _add({required bool same}) async {
    final String? pic = await pickPicture(context, PictureGroup.thing, hide: _l.items.map((PackItem i) => i.picture).toSet());
    if (pic == null || !mounted) return;
    _try(() => addPackItem(_l, newPackItem(widget.service.newId('p'), pic, same: same)));
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Packing buddy', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        const Text('Things to bring are ticked by her. Things that are the same wherever she sleeps are shown calmly, never ticked.'),
        if (_loaded) ...<Widget>[
          for (final PackItem i in _l.items)
            Card(
              key: Key('item_${i.id}'),
              child: ListTile(
                leading: PictureGlyph(i.picture, size: 24),
                title: Text(i.label),
                subtitle: Text(i.same ? 'Same in both homes' : 'To bring'),
                trailing: IconButton(key: Key('itemRemove_${i.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline),
                    onPressed: () => _try(() => removePackItem(_l, i.id))),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('itemAddBring'), onPressed: () => _add(same: false),
              icon: const Icon(Icons.add), label: const Text('Add a thing to bring')),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('itemAddSame'), onPressed: () => _add(same: true),
              icon: const Icon(Icons.favorite_border), label: const Text('Add a thing that is the same in both homes')),
          const SizedBox(height: 8),
          FilledButton(key: const Key('packingSave'), onPressed: () async {
            final RvResult r = await widget.service.savePacking(widget.principal, _l);
            report(r);
          }, child: const Text('Save')),
          TextButton(key: const Key('packingNewBag'), onPressed: () async {
            final RvResult r = await widget.service.newBag(widget.principal);
            say(r.ok ? 'A fresh bag: her ticks are cleared.' : refusalText(r.reason));
          }, child: const Text('Start a new bag (clear her ticks)')),
        ],
      ]);
}

// ======================================================= NEW PLACE EDITOR ====
class NewPlaceEditorScreen extends StatefulWidget {
  const NewPlaceEditorScreen({super.key, required this.childName, required this.service, required this.principal,
      required this.pickPhoto});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  final PickRoomPhoto pickPhoto;
  @override
  State<NewPlaceEditorScreen> createState() => _NewPlaceEditorState();
}

class _NewPlaceEditorState extends State<NewPlaceEditorScreen> with _Reporter<NewPlaceEditorScreen> {
  final TextEditingController _name = TextEditingController();
  List<PlaceStop> _stops = <PlaceStop>[];
  List<String> _plan = <String>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.service.loadPlace(widget.principal).then((PlacePlan? p) {
      if (!mounted) return;
      setState(() {
        _name.text = p?.name ?? 'A new place';
        _stops = <PlaceStop>[...?p?.stops];
        _plan = <String>[...?p?.plan];
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addStop({required bool withPhoto}) async {
    if (_stops.length >= maxPlaceStops) return say(refusalText('too_many_stops'));
    final String? room = await pickPicture(context, PictureGroup.room);
    if (room == null || !mounted) return;
    final String? caption = await askText(context, 'A few words for this room', pictureLabel(room),
        hint: 'Rooms only, no address', maxLength: maxLineChars);
    if (caption == null || !mounted) return;
    try {
      List<int>? bytes;
      if (withPhoto) {
        bytes = await widget.pickPhoto();
        if (bytes == null) return;
      }
      final PlaceStop s = newStop(widget.service.newId('t'), room, caption, photoBytes: bytes);
      if (mounted) setState(() => _stops = <PlaceStop>[..._stops, s]);
    } on RvRefused catch (e) {
      say(refusalText(e.reason));
    }
  }

  Future<void> _addLine() async {
    if (_plan.length >= maxPlanLines) return say(refusalText('too_many_lines'));
    final String? t = await askText(context, 'A line of the plan', '', hint: 'We arrive and put the owl on the bed', maxLength: maxLineChars);
    if (t == null || !mounted) return;
    try {
      final String line = cleanText(t, max: maxLineChars);
      setState(() => _plan = <String>[..._plan, line]);
    } on RvRefused catch (e) {
      say(refusalText(e.reason));
    }
  }

  Future<void> _save() async {
    try {
      final PlacePlan p = makePlan(_name.text, _stops, _plan);
      final RvResult r = await widget.service.savePlace(widget.principal, p);
      report(r);
    } on RvRefused catch (e) {
      say(refusalText(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'A new place', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        const Text('Rooms only: no street address, no map, no coordinates.'),
        if (_loaded) ...<Widget>[
          const SizedBox(height: 8),
          TextField(key: const Key('placeName'), controller: _name, maxLength: maxTitleChars,
              decoration: const InputDecoration(labelText: 'What to call it', border: OutlineInputBorder())),
          for (final PlaceStop s in _stops)
            Card(
              key: Key('stop_${s.id}'),
              child: ListTile(
                leading: PictureGlyph(s.room, size: 24),
                title: Text(s.caption),
                subtitle: Text(s.photoB64 == null ? 'Picture of a room' : 'With a photo'),
                trailing: IconButton(key: Key('stopRemove_${s.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _stops = <PlaceStop>[for (final PlaceStop x in _stops) if (x.id != s.id) x])),
              ),
            ),
          OutlinedButton.icon(key: const Key('stopAdd'), onPressed: () => _addStop(withPhoto: false),
              icon: const Icon(Icons.add), label: const Text('Add a room')),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('stopAddPhoto'), onPressed: () => _addStop(withPhoto: true),
              icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add a room with a photo')),
          const SizedBox(height: 12),
          Text('The plan', style: Theme.of(context).textTheme.titleMedium),
          for (int i = 0; i < _plan.length; i++)
            ListTile(
              key: Key('line_$i'), title: Text(_plan[i]),
              trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _plan = <String>[for (int j = 0; j < _plan.length; j++) if (j != i) _plan[j]])),
            ),
          OutlinedButton.icon(key: const Key('lineAdd'), onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('Add a line')),
          const SizedBox(height: 12),
          FilledButton(key: const Key('placeSave'), onPressed: _save, child: const Text('Save')),
          TextButton(key: const Key('placeClear'), onPressed: () async {
            final RvResult r = await widget.service.savePlace(widget.principal, null);
            if (r.ok) setState(() { _stops = <PlaceStop>[]; _plan = <String>[]; });
            report(r);
          }, child: const Text('Remove it from her device')),
        ],
      ]);
}

// ======================================================== SENSORY EDITOR =====
class SensoryEditorScreen extends StatefulWidget {
  const SensoryEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  @override
  State<SensoryEditorScreen> createState() => _SensoryEditorState();
}

class _SensoryEditorState extends State<SensoryEditorScreen> with _Reporter<SensoryEditorScreen> {
  SensoryProfile _p = const SensoryProfile();
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    widget.service.loadRhythm(widget.principal).then((RhythmDoc d) {
      if (mounted) setState(() { _p = d.sensory; _loaded = true; });
    });
  }

  Future<void> _set(SensoryProfile next) async {
    final RvResult r = await widget.service.saveSensory(widget.principal, next);
    if (r.ok && mounted) setState(() => _p = next);
    report(r);
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'How the app feels', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        const Text('These describe the app on her device, not her. Nothing here is a label.'),
        if (_loaded) ...<Widget>[
          const SizedBox(height: 12),
          Text('Sound', style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<SoundLevel>(
            key: const Key('sensorySound'),
            segments: const <ButtonSegment<SoundLevel>>[
              ButtonSegment<SoundLevel>(value: SoundLevel.off, label: Text('Off')),
              ButtonSegment<SoundLevel>(value: SoundLevel.low, label: Text('Low')),
              ButtonSegment<SoundLevel>(value: SoundLevel.medium, label: Text('Medium')),
              ButtonSegment<SoundLevel>(value: SoundLevel.full, label: Text('Full')),
            ],
            selected: <SoundLevel>{_p.sound},
            onSelectionChanged: (Set<SoundLevel> s) => _set(_p.copyWith(sound: s.first)),
          ),
          SwitchListTile(key: const Key('sensoryMotion'), value: _p.reduceMotion, title: const Text('No motion'),
              subtitle: const Text('Pages simply change'), onChanged: (bool v) => _set(_p.copyWith(reduceMotion: v))),
          SwitchListTile(key: const Key('sensoryHaptics'), value: _p.hapticsOff, title: const Text('No buzzing'),
              onChanged: (bool v) => _set(_p.copyWith(hapticsOff: v))),
          const ListTile(key: Key('sensoryFlash'), leading: Icon(Icons.flash_off_outlined), title: Text('No flashing, ever'),
              subtitle: Text('This is always so.')),
          Text('Brightest the app may be', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            key: const Key('sensoryBrightness'),
            value: _p.brightnessCeiling.toDouble(), min: minBrightnessPercent.toDouble(), max: 100, divisions: 7,
            label: '${_p.brightnessCeiling}%',
            onChanged: (double v) => setState(() => _p = _p.copyWith(brightnessCeiling: v.round())),
            onChangeEnd: (double v) => _set(_p.copyWith(brightnessCeiling: v.round())),
          ),
        ],
      ]);
}

// ================================================================ C HUB ======
class VoiceGuardianHubScreen extends StatefulWidget {
  const VoiceGuardianHubScreen({super.key, required this.childName, required this.service, required this.principal,
      this.yearsOld});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  final int? yearsOld;
  @override
  State<VoiceGuardianHubScreen> createState() => _VoiceGuardianHubState();
}

class _VoiceGuardianHubState extends State<VoiceGuardianHubScreen> with _Reporter<VoiceGuardianHubScreen> {
  bool _on = true;
  @override
  void initState() {
    super.initState();
    widget.service.loadVoice(widget.principal).then((VoiceDoc d) {
      if (mounted) setState(() => _on = d.suiteOn);
    }).catchError((Object _) {});
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final String n = widget.childName;
    final RhythmVoiceService s = widget.service;
    final FamilyPrincipal p = widget.principal;
    return _Page(title: 'Her voice', children: <Widget>[
      _LocalOnlyNote(n),
      const SizedBox(height: 8),
      Text(_ageNote(n, widget.yearsOld), key: const Key('voiceAgeNote')),
      SwitchListTile(
        key: const Key('voiceSuite'), value: _on, title: Text('Show on $n\'s device'),
        onChanged: (bool v) async {
          final RvResult r = await s.setVoiceSuite(p, v);
          if (r.ok) setState(() => _on = v);
          report(r);
        },
      ),
      _Row(key: const Key('rowHelpers'), icon: Icons.people_outline, title: '$n\'s helpers',
          subtitle: 'The grown-ups she can go to', onTap: () => _push(HelpersEditorScreen(childName: n, service: s, principal: p))),
      _Row(key: const Key('rowSymbols'), icon: Icons.record_voice_over_outlined, title: 'Her symbols',
          subtitle: 'Add a few words to her picture board', onTap: () => _push(SymbolsEditorScreen(childName: n, service: s, principal: p))),
      _Row(key: const Key('rowShown'), icon: Icons.inventory_2_outlined, title: 'Worries she chose to show you',
          subtitle: 'Only what she picked "show my grown-up" for', onTap: () => _push(SharedWorriesScreen(childName: n, service: s, principal: p))),
      const SizedBox(height: 8),
      const QuietNote('The weather picture and the worry box are hers. You cannot open them; only the worries '
          'she chooses to show you appear here.', icon: Icons.lock_outline),
    ]);
  }
}

// ======================================================== HELPERS EDITOR =====
class HelpersEditorScreen extends StatefulWidget {
  const HelpersEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  @override
  State<HelpersEditorScreen> createState() => _HelpersEditorState();
}

class _HelpersEditorState extends State<HelpersEditorScreen> with _Reporter<HelpersEditorScreen> {
  List<Helper> _hs = <Helper>[];
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    widget.service.loadVoice(widget.principal).then((VoiceDoc d) {
      if (mounted) setState(() { _hs = d.helpers; _loaded = true; });
    });
  }

  Future<void> _save(List<Helper> next) async {
    final RvResult r = await widget.service.saveHelpers(widget.principal, next);
    if (r.ok && mounted) setState(() => _hs = next);
    report(r);
  }

  Future<void> _add() async {
    if (_hs.length >= maxHelpers) return say(refusalText('too_many_helpers'));
    final String? pic = await pickPicture(context, PictureGroup.person);
    if (pic == null || !mounted) return;
    final String? name = await askText(context, 'Their name, as she says it', '');
    if (name == null || !mounted) return;
    final String? line = await askText(context, 'A short line for her (optional)', '',
        hint: 'Knock on the door at the end of the hall', maxLength: maxLineChars);
    if (line == null || !mounted) return;
    try {
      // Not yet said yes: she will not see them until a grown-up records it.
      final Helper h = makeHelper(id: widget.service.newId('h'), name: name, picture: pic, line: line);
      await _save(<Helper>[..._hs, h]);
    } on RvRefused catch (e) {
      say(refusalText(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) => _Page(title: '${widget.childName}\'s helpers', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        const Text('Choose these with her. Each person should say yes first; tick the box when they have. '
            'She only sees people who have said yes.'),
        if (_loaded) ...<Widget>[
          for (final Helper h in _hs)
            Card(
              key: Key('helperRow_${h.id}'),
              child: Column(children: <Widget>[
                ListTile(
                  leading: PictureGlyph(h.picture, size: 24), title: Text(h.name),
                  subtitle: Text(h.line.isEmpty ? pictureLabel(h.picture) : '${pictureLabel(h.picture)}: ${h.line}'),
                  trailing: IconButton(key: Key('helperRemove_${h.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline),
                      onPressed: () => _save(<Helper>[for (final Helper x in _hs) if (x.id != h.id) x])),
                ),
                CheckboxListTile(
                  key: Key('helperYes_${h.id}'), value: h.saidYes, title: const Text('They have said yes'),
                  onChanged: (bool? v) => _save(<Helper>[
                    for (final Helper x in _hs)
                      x.id == h.id ? Helper(id: x.id, name: x.name, picture: x.picture, line: x.line, saidYes: v == true) : x
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(key: const Key('helperAdd'), onPressed: _add, icon: const Icon(Icons.person_add_alt_outlined),
              label: const Text('Add someone')),
        ],
      ]);
}

// ======================================================== SYMBOLS EDITOR =====
class SymbolsEditorScreen extends StatefulWidget {
  const SymbolsEditorScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  @override
  State<SymbolsEditorScreen> createState() => _SymbolsEditorState();
}

class _SymbolsEditorState extends State<SymbolsEditorScreen> with _Reporter<SymbolsEditorScreen> {
  List<String> _on = <String>[];
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    widget.service.loadVoice(widget.principal).then((VoiceDoc d) {
      if (mounted) setState(() { _on = d.personalSymbols; _loaded = true; });
    });
  }

  Future<void> _toggle(String id) async {
    final List<String> next = _on.contains(id) ? <String>[for (final String x in _on) if (x != id) x] : <String>[..._on, id];
    final RvResult r = await widget.service.savePersonalSymbols(widget.principal, next);
    if (r.ok && mounted) setState(() => _on = next);
    if (mounted && !r.ok) say(refusalText(r.reason));
  }

  @override
  Widget build(BuildContext context) => _Page(title: 'Her symbols', children: <Widget>[
        _LocalOnlyNote(widget.childName),
        const SizedBox(height: 8),
        const Text('Her board always has the core words. Add up to eight more. What she says is never kept.'),
        const SizedBox(height: 12),
        if (_loaded)
          PictureGrid(minTile: 96, children: <Widget>[
            for (final PictureDef p in picturesIn(PictureGroup.symbolExtra))
              PictureTile(key: Key('extra_${p.id}'), picture: p.id, label: p.label, minHeight: 96,
                  selected: _on.contains(p.id), onTap: () => _toggle(p.id)),
          ]),
      ]);
}

// ====================================================== WORRIES SHOWN TO YOU =
/// The one window a guardian has onto the worry box: what she chose to show.
class SharedWorriesScreen extends StatefulWidget {
  const SharedWorriesScreen({super.key, required this.childName, required this.service, required this.principal});
  final String childName;
  final RhythmVoiceService service;
  final FamilyPrincipal principal;
  @override
  State<SharedWorriesScreen> createState() => _SharedWorriesState();
}

class _SharedWorriesState extends State<SharedWorriesScreen> with _Reporter<SharedWorriesScreen> {
  List<Worry>? _shown;
  @override
  void initState() {
    super.initState();
    widget.service.worriesShownToGrownUp(widget.principal).then((List<Worry> w) {
      if (mounted) setState(() => _shown = w);
    }).catchError((Object _) {
      if (mounted) setState(() => _shown = const <Worry>[]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Worry>? w = _shown;
    return _Page(title: 'Worries she chose to show you', children: <Widget>[
      QuietNote('Only worries ${widget.childName} chose to show you appear here. They are exactly as she made '
          'them. Nothing here is read, tagged or counted, and the box stays hers.', icon: Icons.favorite_border),
      const SizedBox(height: 12),
      if (w != null && w.isEmpty)
        const Text('Nothing here right now. That is her choice.', key: Key('sharedEmpty'))
      else if (w != null)
        Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
          for (final Worry x in w)
            Column(key: Key('shared_${x.id}'), mainAxisSize: MainAxisSize.min, children: <Widget>[
              WorryThumb(worry: x, size: 140),
              if (x.kind == WorryKind.picture) Text(pictureLabel(x.picture)),
            ]),
        ]),
    ]);
  }
}
