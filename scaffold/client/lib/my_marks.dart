// OLIVE BRANCH — her own pencil marks on the door. No longer UNVERIFIED — verified by CI
// (client/test/my_marks_test.dart). Prototype k.growth / kid.mark / kid.markUndo; parity rows 271, 321, 322;
// MASTERFILE section 8.17.
//
// SHE makes the marks. Until now the doorframe was a picture of marks a GROWN-UP recorded, read-only for her; the
// prototype's door is hers: she stands against it, taps where the top of her head is, and a pencil line appears with
// the month beside it. She can rub out the last mark she made (and only that: the grown-up's marks are never hers to
// change, and hers are never theirs).
//
// What is kept (area `child.<id>.mymarks`, sealed): for each mark, the day it was made and how high up the door she
// tapped, as a fraction of the door. There is NO centimetre, no number on screen, no comparison with any other child
// or any chart, and no total (P2): the picture is her own lines against each other. A grown-up's own marks (the
// `growing` area, `pencilMarks` suite) are listed below hers under "From a grown-up", by month only.
//
// No guardian screen reads this area: nothing in the guardian shell imports this file (a source test holds that).
import 'dart:async';

import 'package:flutter/material.dart';

import 'access_settings.dart' show kChildTarget;
import 'growing_care_logic.dart' show GrowthMarkView, isoOf, maxPencilMarks, monthYear;
import 'local_services.dart';
import 'local_store.dart';

/// One pencil line she drew.
class MyMark {
  const MyMark({required this.id, required this.on, required this.permille, required this.at});
  final String id;

  /// yyyy-mm-dd, this device's local day.
  final String on;

  /// How far up the door, 40 (near the floor) to 960 (near the top), in thousandths of the door's height.
  final int permille;

  /// Milliseconds since epoch when it was made: only the order of her marks, so the last one can be rubbed out.
  final int at;

  double get fraction => permille / 1000;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'on': on, 'y': permille, 'at': at};

  static MyMark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'], on = raw['on'], y = raw['y'], at = raw['at'];
    if (id is! String || on is! String || y is! int || at is! int) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(on) || y < 0 || y > 1000) return null;
    return MyMark(id: id, on: on, permille: y, at: at);
  }
}

/// Where her marks are kept. No method takes a reader or a role: only her own screen opens this.
class MyMarksRepository {
  MyMarksRepository(this._ns);
  factory MyMarksRepository.forChild([String? childId]) =>
      MyMarksRepository(LocalServices.current.area('mymarks', ownerId: childId));
  final LocalNamespace _ns;

  static String _key(String id) => 'm.${id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}';

  /// Oldest first.
  Future<List<MyMark>> load() async {
    final List<MyMark> out = <MyMark>[];
    for (final String k in await _ns.list()) {
      final MyMark? m = MyMark.fromJson(await _ns.get(k));
      if (m != null) out.add(m);
    }
    out.sort((MyMark a, MyMark b) => a.at.compareTo(b.at));
    return out;
  }

  /// Throws [LocalStoreFull] when the area is at its ceiling (nothing written).
  Future<void> add(MyMark m) => _ns.put(_key(m.id), m.toJson());

  Future<void> remove(String id) => _ns.delete(_key(id));
}

class MyDoorScreen extends StatefulWidget {
  const MyDoorScreen({super.key, this.childName = 'Ivy', this.repository, this.fromGrownUp, this.now});
  final String childName;

  /// Null means the app's sealed on-device marks for this device's child.
  final MyMarksRepository? repository;

  /// What a grown-up chose to record, shown by month under "From a grown-up" (the caller applies the guardian's
  /// switch and the age rules). Null: none.
  final Future<List<GrowthMarkView>> Function()? fromGrownUp;
  final DateTime Function()? now;

  @override
  State<MyDoorScreen> createState() => _MyDoorScreenState();
}

class _MyDoorScreenState extends State<MyDoorScreen> {
  late final MyMarksRepository _repo = widget.repository ?? MyMarksRepository.forChild();
  final List<MyMark> _marks = <MyMark>[];
  List<GrowthMarkView> _fromGrownUp = const <GrowthMarkView>[];
  String? _note;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final List<MyMark> m = await _repo.load();
      final List<GrowthMarkView> g = widget.fromGrownUp == null ? const <GrowthMarkView>[] : await widget.fromGrownUp!();
      if (!mounted) return;
      final Set<String> have = _marks.map((MyMark x) => x.id).toSet();
      setState(() {
        _marks
          ..addAll(<MyMark>[for (final MyMark x in m) if (!have.contains(x.id)) x])
          ..sort((MyMark a, MyMark b) => a.at.compareTo(b.at));
        _fromGrownUp = g;
      });
    } catch (_) {
      // An unreadable file was quarantined by the store: the door is simply bare.
    }
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  Future<void> _mark(double fraction) async {
    if (_marks.length >= maxPencilMarks) {
      setState(() => _note = 'The door is full. Rub one out to make room.');
      return;
    }
    final DateTime now = _now();
    final MyMark m = MyMark(
        id: 'g-${now.microsecondsSinceEpoch}', on: isoOf(now),
        permille: (fraction.clamp(0.04, 0.96) * 1000).round(), at: now.millisecondsSinceEpoch);
    setState(() {
      _marks.add(m);
      _note = null;
    });
    try {
      await _repo.add(m);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _marks.removeWhere((MyMark x) => x.id == m.id);
        _note = "That mark couldn't be kept just now.";
      });
    }
  }

  Future<void> _rubOut() async {
    if (_marks.isEmpty) return;
    final MyMark last = _marks.last;
    setState(() {
      _marks.removeLast();
      _note = null;
    });
    try {
      await _repo.remove(last.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _marks.add(last);
        _note = "That mark couldn't be rubbed out just now.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Growing marks')),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                        Text('Stand against the door, then tap where the top of your head is. A pencil line and the month.',
                            style: text.bodyLarge),
                        const SizedBox(height: 12),
                        _Door(marks: _marks, onTap: _mark),
                        if (_note != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(_note!, key: const Key('myDoorNote'), style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                        if (_marks.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          SizedBox(
                              height: kChildTarget,
                              child: OutlinedButton.icon(
                                  key: const Key('myDoorRubOut'),
                                  onPressed: _rubOut,
                                  icon: const Icon(Icons.undo),
                                  label: const Text('Rub out the last mark'))),
                        ],
                        if (_fromGrownUp.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 20),
                          Text('From a grown-up', style: text.titleMedium),
                          const SizedBox(height: 4),
                          for (final GrowthMarkView g in _fromGrownUp)
                            ListTile(
                                key: ValueKey<String>('fromGrownUp-${g.id}'),
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.eco_outlined),
                                title: Text(g.label)),
                        ],
                      ]))))),
    );
  }
}

/// The door: a tall panel. A tap puts a pencil line where she tapped; the month sits beside it.
class _Door extends StatelessWidget {
  const _Door({required this.marks, required this.onTap});
  final List<MyMark> marks;
  final void Function(double fraction) onTap;

  static const double _height = 320;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'The door. Tap to add a pencil mark.',
      child: GestureDetector(
        key: const Key('myDoor'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (TapUpDetails d) => onTap(1 - d.localPosition.dy / _height),
        child: SizedBox(
          height: _height,
          child: Stack(children: <Widget>[
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: scheme.outlineVariant, width: 2)))),
            if (marks.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('The door is waiting for its first mark.', textAlign: TextAlign.center))),
            for (int i = 0; i < marks.length; i++)
              Positioned(
                left: 20, right: 12, bottom: _height * marks[i].fraction - 8,
                child: ExcludeSemantics(
                    child: Row(key: ValueKey<String>('doorLine-${marks[i].id}'), children: <Widget>[
                  Container(
                      width: 56, height: 4,
                      decoration: BoxDecoration(
                          color: i == marks.length - 1 ? scheme.onSurface : scheme.onSurfaceVariant,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Flexible(child: Text(monthYear(marks[i].on), style: text.bodySmall, overflow: TextOverflow.ellipsis)),
                ])),
              ),
          ]),
        ),
      ),
    );
  }
}
