// OLIVE BRANCH — child shell, "teach me something". UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.9.3,
// §9.14. Renders MARKUP screen 'teachMe': "she teaches him something from
// her week."
//
// A 1:1 port of the teach-me functions from
// packages/maturation/src/family.ts (teach / askAgain / lessonArtifact /
// whoTeachesWhom / LESSON_SEEDS / TEACH_FORBIDDEN), kept close to the TS
// originals for the same auditability reason lock_controller.dart gives for
// lock.ts.
//
// The roles are inverted from every other teaching surface in the product:
// SHE is the curriculum here, not him. §21.5 lists this as the one feature
// that gets *better* as she ages rather than fading, and the only "metric"
// the spec allows anywhere near it is binary and warm — whether the lesson
// was asked for again — never a grade, level, or score. `auditLesson()`
// below exists to keep that true in code, not just in a comment.
import 'package:flutter/material.dart';

// ======== ported from packages/maturation/src/family.ts (teach me) =========
enum TeachMedium { demonstrate, draw, record, doTogether }

extension TeachMediumUi on TeachMedium {
  String get label => switch (this) {
    TeachMedium.demonstrate => 'Show them',
    TeachMedium.draw => 'Draw it',
    TeachMedium.record => 'Record it',
    TeachMedium.doTogether => 'Do it together',
  };
  IconData get icon => switch (this) {
    TeachMedium.demonstrate => Icons.front_hand_outlined,
    TeachMedium.draw => Icons.brush_outlined,
    TeachMedium.record => Icons.videocam_outlined,
    TeachMedium.doTogether => Icons.groups_outlined,
  };
}

class Lesson {
  const Lesson({
    required this.id, required this.fromUserId, required this.title,
    required this.medium, required this.taughtAt, this.askedAgain = 0,
  });
  final String id;
  final String fromUserId;
  final String title;
  final TeachMedium medium;
  final DateTime taughtAt;
  /// She can ask to be taught it again — or here, since she is the teacher,
  /// he can ask to be taught it again. That is the only metric this feature
  /// allows anywhere near it (§9.14).
  final int askedAgain;

  Lesson _withAskAgain() => Lesson(id: id, fromUserId: fromUserId, title: title,
    medium: medium, taughtAt: taughtAt, askedAgain: askedAgain + 1);
}

class TeachResult {
  const TeachResult.ok(this.lesson) : reason = null;
  const TeachResult.refused() : lesson = null, reason = 'no_title';
  final Lesson? lesson;
  final String? reason;
  bool get ok => lesson != null;
}

TeachResult teach(String id, String fromUserId, String title, TeachMedium medium, DateTime at) {
  final t = title.trim();
  if (t.isEmpty) return const TeachResult.refused();
  return TeachResult.ok(Lesson(id: id, fromUserId: fromUserId, title: t, medium: medium, taughtAt: at));
}

List<Lesson> askAgain(List<Lesson> lessons, String id) =>
    [for (final l in lessons) l.id == id ? l._withAskAgain() : l];

/// A lesson asked for twice is the signal worth acting on — the same rule
/// §9.14 gives a story (asking again is the only honest measure a child
/// gives you). Returns whether it has crossed that line; the real backend
/// would also materialize a preserved media_artifact copy, which this
/// no-backend demo has nowhere to put.
bool lessonBecamePreserved(Lesson l) => l.askedAgain >= 1;

const lessonSeeds = <String>[
  'How to tie a bowline', 'Why the sky goes red at sunset', 'A card trick',
  'How to whistle with two fingers', 'The names of three clouds',
  'How to fold a paper aeroplane that actually flies',
  'What the moon is doing this week', 'How to skim a stone',
  'A word in another language you use every day',
  'How to tell if bread is done', 'Where our name comes from',
  'How to draw a horse that looks like a horse',
  'What I did at school today, properly explained',
  'How a lock works', 'Why boats float', 'A song I know all the words to',
];

class WhoTeaches {
  const WhoTeaches({required this.parentTeaches, required this.childTeaches});
  final bool parentTeaches;
  final bool childTeaches;
}

/// From about six, she teaches too. Below that, mostly the other direction.
WhoTeaches whoTeachesWhom(int childAge) =>
    WhoTeaches(parentTeaches: true, childTeaches: childAge >= 6);

/// No grading, ever. This is the feature where that temptation is strongest.
const teachForbidden = <String>[
  'score', 'grade', 'level', 'mastery', 'progress', 'passed', 'failed',
  'assessment', 'quiz', 'test', 'correct', 'incorrect', 'streak',
];

class LessonAudit {
  const LessonAudit.ok() : leaks = const [];
  const LessonAudit.failed(this.leaks);
  final List<String> leaks;
  bool get ok => leaks.isEmpty;
}

LessonAudit auditLesson(Map<String, dynamic> v) {
  final leaks = <String>{};
  void walk(dynamic x) {
    if (x is List) {
      for (final e in x) { walk(e); }
      return;
    }
    if (x is Map) {
      for (final entry in x.entries) {
        final key = entry.key.toString().toLowerCase();
        if (teachForbidden.contains(key)) leaks.add(entry.key.toString());
        walk(entry.value);
      }
    }
  }
  walk(v);
  return leaks.isEmpty ? const LessonAudit.ok() : LessonAudit.failed(leaks.toList());
}
// =============================================================================

class TeachMeScreen extends StatefulWidget {
  const TeachMeScreen({
    super.key,
    required this.childName,
    required this.childAge,
    this.parentName = 'Dad',
    this.initialLessons = const [],
  });

  final String childName;
  final int childAge;
  final String parentName;
  final List<Lesson> initialLessons;

  @override
  State<TeachMeScreen> createState() => _TeachMeScreenState();
}

class _TeachMeScreenState extends State<TeachMeScreen> {
  late List<Lesson> _lessons;
  final _controller = TextEditingController();
  TeachMedium _medium = TeachMedium.demonstrate;
  int _nextId = 1;

  @override
  void initState() {
    super.initState();
    _lessons = List.of(widget.initialLessons);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _pickSeed(String seed) => setState(() => _controller.text = seed);

  void _sendLesson() {
    final result = teach('local-${_nextId++}', 'demo-child', _controller.text, _medium, DateTime.now());
    if (!result.ok) return;
    setState(() { _lessons.insert(0, result.lesson!); _controller.clear(); });
  }

  // Demo-only affordance: in the real app this flips when the OTHER side's
  // showcase (packages/showcase) records that he asked to be taught the
  // lesson again — there is no live channel between two demo builds here, so
  // a small control on her own tile stands in for it honestly rather than
  // faking a notification that has nothing real behind it.
  void _simulateAskedAgain(Lesson l) => setState(() => _lessons = askAgain(_lessons, l.id));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final who = whoTeachesWhom(widget.childAge);
    return Scaffold(
      appBar: AppBar(title: const Text('Teach me something')),
      // SingleChildScrollView + Column, NOT ListView — a sliver list only
      // realizes children near the viewport, which would silently drop
      // taught lessons scrolled below the fold from the widget tree. Same
      // fix message_banking.dart already documents for the same bug class.
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.emoji_objects_outlined, color: scheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(child: Text(
                who.childTeaches
                  ? 'Your turn to be the teacher. Show ${widget.parentName} something you know '
                    "from this week — there's nothing to get right or wrong, just you teaching."
                  : "You'll get to teach ${widget.parentName} things too, starting around when "
                    "you're six. For now, they're the one teaching.",
                style: TextStyle(fontSize: 13, color: scheme.onSecondaryContainer))),
            ])),
          if (who.childTeaches) ...[
            const SizedBox(height: 18),
            Card(child: Padding(padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Need an idea?', style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15, color: scheme.primary)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final seed in lessonSeeds.take(8))
                  ActionChip(label: Text(seed, style: const TextStyle(fontSize: 12.5)),
                    onPressed: () => _pickSeed(seed)),
                ]),
                const SizedBox(height: 16),
                TextField(controller: _controller, minLines: 2, maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'What do you want to teach them?',
                    border: OutlineInputBorder())),
                const SizedBox(height: 14),
                const Text('How will you teach it?', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final m in TeachMedium.values)
                  ChoiceChip(
                    avatar: Icon(m.icon, size: 18),
                    label: Text(m.label),
                    selected: _medium == m,
                    onSelected: (_) => setState(() => _medium = m)),
                ]),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, height: 48,
                  child: FilledButton.icon(
                    onPressed: _controller.text.trim().isEmpty ? null : _sendLesson,
                    icon: const Icon(Icons.send_outlined),
                    label: Text('Teach ${widget.parentName}'))),
              ]))),
          ],
          const SizedBox(height: 22),
          if (_lessons.isNotEmpty) ...[
            Text("What you've taught ${widget.parentName}",
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 10),
            for (final l in _lessons)
              _LessonTile(key: ValueKey(l.id), lesson: l, parentName: widget.parentName,
                onAskedAgain: () => _simulateAskedAgain(l)),
          ] else if (who.childTeaches)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nothing taught yet — pick an idea above whenever you feel like it.',
                style: TextStyle(color: Colors.black45, fontSize: 13.5))),
        ]),
      )),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({super.key, required this.lesson, required this.parentName, required this.onAskedAgain});
  final Lesson lesson;
  final String parentName;
  final VoidCallback onAskedAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final askedAgain = lesson.askedAgain > 0;
    return Card(margin: const EdgeInsets.only(bottom: 10),
      child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(lesson.medium.icon, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
          ]),
          const SizedBox(height: 6),
          Text(lesson.medium.label, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          AnimatedSwitcher(duration: const Duration(milliseconds: 300),
            child: askedAgain
              ? Padding(key: const ValueKey('asked'), padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.favorite, size: 15, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text('$parentName asked to hear this again — kept forever now.',
                      style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w600))),
                  ]))
              : const SizedBox.shrink(key: ValueKey('not-asked')),
          ),
          if (!askedAgain)
            Align(alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onAskedAgain,
                child: Text('$parentName asked for this again',
                  style: const TextStyle(fontSize: 11.5)))),
        ]),
      ));
  }
}
