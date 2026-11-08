// OLIVE BRANCH — child shell, "teach me something". No longer UNVERIFIED —
// verified by CI (`flutter analyze` and `flutter test` run for real in
// tools/verify.sh and .github/workflows/verify.yml). MASTERFILE §9.9.3, §9.14.
// Renders MARKUP screen 'teachMe': "she teaches him something from her week."
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
//
// KEPT ON THIS DEVICE. What she taught is stored by [LessonsRepository]
// (LocalStore area `lessons`): the title, how, the date, and ONE bit — whether
// it was asked for again (the only metric §9.14 allows). The running
// askedAgain count is reduced to that bit on the way to disk, so no tally is
// stored; no grade, level or score exists to store. The lesson's author is the
// device's own child id ([LocalServices.childId]), never a literal demo id in
// a live build.
import 'dart:async';
import 'package:flutter/material.dart';
import 'access_settings.dart' show kChildTarget;
import 'access_scope.dart' show motionDuration;
import 'local_services.dart';
import 'local_store.dart';

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

/// The lessons' on-device store. See the file header for what is (and is not)
/// kept.
class LessonsRepository {
  LessonsRepository(this._ns);
  factory LessonsRepository.forChild([String? childId]) =>
      LessonsRepository(LocalServices.current.area('lessons', ownerId: childId));
  final LocalNamespace _ns;
  static const String _key = 'lessons';

  /// Null means "never saved".
  Future<List<Lesson>?> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! List) return null;
    final List<Lesson> out = <Lesson>[];
    for (final Object? o in raw) {
      if (o is! Map) continue;
      final Object? id = o['id'], from = o['fromUserId'], title = o['title'], m = o['medium'], at = o['taughtAt'];
      if (id is! String || from is! String || title is! String || m is! String || at is! String) continue;
      TeachMedium? medium;
      for (final TeachMedium v in TeachMedium.values) {
        if (v.name == m) medium = v;
      }
      final DateTime? taught = DateTime.tryParse(at);
      if (medium == null || taught == null) continue;
      out.add(Lesson(
          id: id, fromUserId: from, title: title, medium: medium, taughtAt: taught,
          askedAgain: o['askedAgain'] == true ? 1 : 0));
    }
    return out;
  }

  Future<void> save(List<Lesson> lessons) => _ns.put(_key, <Object?>[
        for (final Lesson l in lessons)
          <String, Object?>{
            'id': l.id,
            'fromUserId': l.fromUserId,
            'title': l.title,
            'medium': l.medium.name,
            'taughtAt': l.taughtAt.toIso8601String(),
            // One bit, never the running count.
            'askedAgain': l.askedAgain > 0,
          },
      ]);
}

class TeachMeScreen extends StatefulWidget {
  const TeachMeScreen({
    super.key,
    required this.childName,
    required this.childAge,
    this.parentName = 'Dad',
    this.initialLessons = const [],
    this.repository,
    this.childId,
  });

  final String childName;
  final int childAge;
  final String parentName;
  final List<Lesson> initialLessons;

  /// Null means the app's on-device lessons for [childId].
  final LessonsRepository? repository;

  /// Null means this device's child ([LocalServices.childId]).
  final String? childId;

  @override
  State<TeachMeScreen> createState() => _TeachMeScreenState();
}

class _TeachMeScreenState extends State<TeachMeScreen> {
  late List<Lesson> _lessons;
  final _controller = TextEditingController();
  TeachMedium _medium = TeachMedium.demonstrate;
  late final String _childId = widget.childId ?? LocalServices.current.childId;
  late final LessonsRepository _repo =
      widget.repository ?? LessonsRepository.forChild(widget.childId);

  @override
  void initState() {
    super.initState();
    _lessons = List.of(widget.initialLessons);
    _controller.addListener(_onTextChanged);
    unawaited(_hydrate());
  }

  Future<void> _hydrate() async {
    try {
      final stored = await _repo.load();
      if (!mounted || stored == null) return;
      setState(() => _lessons = stored);
    } catch (_) {
      // Unreadable lessons were quarantined by the store; start fresh.
    }
  }

  void _persist() {
    unawaited(() async {
      try {
        await _repo.save(_lessons);
      } catch (_) {
        // Leaves the list on screen for this visit.
      }
    }());
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
    final now = DateTime.now();
    final result = teach('lesson-${now.microsecondsSinceEpoch}', _childId, _controller.text, _medium, now);
    if (!result.ok) return;
    setState(() { _lessons.insert(0, result.lesson!); _controller.clear(); });
    _persist();
  }

  // Demo-only affordance: in the real app this flips when the OTHER side's
  // showcase (packages/showcase) records that he asked to be taught the
  // lesson again — there is no live channel between two demo builds here, so
  // a small control on her own tile stands in for it honestly rather than
  // faking a notification that has nothing real behind it.
  void _simulateAskedAgain(Lesson l) {
    setState(() => _lessons = askAgain(_lessons, l.id));
    _persist();
  }

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
          // 12, matching the compact inline info-banner role used elsewhere
          // (expenses_screen.dart, meds_care.dart, morning_briefing.dart,
          // care_note.dart, guardian_setup.dart) — was 16, a leftover from
          // before the radius sweep.
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.emoji_objects_outlined, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(child: Text(
                who.childTeaches
                  ? 'Your turn to be the teacher. Show ${widget.parentName} something you know '
                    "from this week — there's nothing to get right or wrong, just you teaching."
                  : "You'll get to teach ${widget.parentName} things too, starting around when "
                    "you're six. For now, they're the one teaching.",
                style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSecondaryContainer))),
            ])),
          if (who.childTeaches) ...[
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Need an idea?', style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final seed in lessonSeeds.take(8))
                  ActionChip(label: Text(seed, style: Theme.of(context).textTheme.labelMedium),
                    onPressed: () => _pickSeed(seed)),
                ]),
                const SizedBox(height: 16),
                TextField(controller: _controller, minLines: 2, maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'What do you want to teach them?',
                    border: OutlineInputBorder())),
                const SizedBox(height: 16),
                Text('How will you teach it?', style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final m in TeachMedium.values)
                  ChoiceChip(
                    avatar: Icon(m.icon, size: 18),
                    label: Text(m.label),
                    selected: _medium == m,
                    onSelected: (_) => setState(() => _medium = m)),
                ]),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, height: kChildTarget,
                  child: FilledButton.icon(
                    onPressed: _controller.text.trim().isEmpty ? null : _sendLesson,
                    icon: const Icon(Icons.send_outlined),
                    label: Text('Teach ${widget.parentName}'))),
              ]))),
          ],
          const SizedBox(height: 24),
          if (_lessons.isNotEmpty) ...[
            Text("What you've taught ${widget.parentName}",
              style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 12),
            for (final l in _lessons)
              _LessonTile(key: ValueKey(l.id), lesson: l, parentName: widget.parentName,
                onAskedAgain: () => _simulateAskedAgain(l)),
          ] else if (who.childTeaches)
            Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(child: Column(children: [
                // Deliberately a different glyph than the banner's
                // emoji_objects_outlined above, so the empty state doesn't
                // visually duplicate the icon already on screen.
                Icon(Icons.lightbulb_outline, size: 40, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('Nothing taught yet — pick an idea above whenever you feel like it.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
              ]))),
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
    return Card(margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(lesson.medium.icon, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(lesson.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Text(lesson.medium.label, style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant)),
          AnimatedSwitcher(duration: motionDuration(context, 300),
            child: askedAgain
              ? Padding(key: const ValueKey('asked'), padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.favorite, size: 15, color: scheme.primary),
                    const SizedBox(width: 4),
                    Expanded(child: Text('$parentName asked to hear this again — kept forever now.',
                      style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600))),
                  ]))
              : const SizedBox.shrink(key: ValueKey('not-asked')),
          ),
          if (!askedAgain)
            Align(alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onAskedAgain,
                child: Text('$parentName asked for this again',
                  style: Theme.of(context).textTheme.labelMedium))),
        ]),
      ));
  }
}
