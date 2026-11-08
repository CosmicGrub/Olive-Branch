// OLIVE BRANCH — how a screen asks "what does SHE call this grown-up?".
// No longer UNVERIFIED — verified by CI (client/test/grownup_labels_test.dart,
// client/test/label_adoption_test.dart). MASTERFILE §8.5.7.
//
// The pure resolver is contact_labels.dart (nickname, then the age default
// Mommy/Daddy, then the guardian's label). This file is only the PLUMBING that
// lets every child-facing screen reach it without a name being passed through
// every constructor:
//
//  - [GrownupLabels] is an immutable snapshot (the grown-ups, her locked age,
//    her nicknames). [GrownupLabels.nameFor] is what ANY child-facing screen
//    prints. With no family known, or an id it does not know, the answer is the
//    neutral 'your grown-up' ([neutralGrownUp]) — never a guessed 'Dad'.
//  - [GrownupLabelScope] is an InheritedWidget carrying a snapshot; a screen
//    calls [GrownupLabelScope.of] and gets [GrownupLabels.none] when no scope is
//    installed (every test and the bare preview), so a screen built without any
//    setup still works and shows the neutral words.
//  - [GrownupLabelsProvider] loads her nicknames from the child's own
//    `child.<id>.nicknames` area through [LocalServices] and installs the scope.
//    It only ever READS: nothing here writes a nickname, and a guardian can
//    never overwrite one (the only writer is [NicknameRepository], held by the
//    child's rename screen).
//
// A guardian's own screens use [GrownupLabels.forGuardian], which shows both
// ("Dad (Ivy calls you Dada)") where a nickname exists.
import 'package:flutter/widgets.dart';

import 'contact_labels.dart';
import 'game_logic.dart' show neutralGrownUp;
import 'local_services.dart';

export 'game_logic.dart' show neutralGrownUp, asSubject;

/// An immutable snapshot of who her grown-ups are and what she calls them.
class GrownupLabels {
  const GrownupLabels({
    this.contacts = const <GrownupContact>[],
    this.age = const AgeLockState(),
    this.nicknames = const <String, String>{},
    this.primaryId,
  });

  /// Nobody known: every child-facing name is the neutral 'your grown-up'.
  static const GrownupLabels none = GrownupLabels();

  final List<GrownupContact> contacts;
  final AgeLockState age;
  final Map<String, String> nicknames;

  /// Which contact the child shell means by "your grown-up" when a screen has
  /// no id of its own (the one who is on the other end of a game, say).
  final String? primaryId;

  /// The contact for [id], else the primary one (or the only one), else null.
  GrownupContact? contact([String? id]) {
    if (id != null) {
      for (final GrownupContact c in contacts) {
        if (c.id == id) return c;
      }
      return null;
    }
    if (primaryId != null) return contact(primaryId);
    return contacts.length == 1 ? contacts.first : null;
  }

  /// True when a child-facing screen can name a real grown-up.
  bool get hasPrimary => contact() != null;

  /// What SHE sees for [id] (default: the primary grown-up). Neutral when no
  /// such grown-up is known.
  String nameFor([String? id]) {
    final GrownupContact? c = contact(id);
    if (c == null) return neutralGrownUp;
    return ContactLabels.forChild(c, age: age, nicknames: nicknames);
  }

  /// What a GUARDIAN sees for [id]: their label, plus how she says it if she
  /// renamed it. Falls back to the neutral phrase for an unknown id.
  String forGuardian(String? id, {required String childName}) {
    final GrownupContact? c = contact(id);
    if (c == null) return neutralGrownUp;
    return ContactLabels.forGuardian(c, childName: childName, nicknames: nicknames);
  }

  /// Names for a two-home rhythm (the weeks screen): the first two grown-ups
  /// as she says them, padded with neutral placeholders.
  List<String> twoNames() => <String>[
        for (int i = 0; i < 2; i++) i < contacts.length ? nameFor(contacts[i].id) : kNeutralHomeNames[i],
      ];
}

/// Used when a rhythm needs two names and no family is known.
const List<String> kNeutralHomeNames = <String>['Grown-up one', 'Grown-up two'];

class GrownupLabelScope extends InheritedWidget {
  const GrownupLabelScope({super.key, required this.labels, required super.child});
  final GrownupLabels labels;

  /// The snapshot in scope, or [GrownupLabels.none].
  static GrownupLabels of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GrownupLabelScope>()?.labels ?? GrownupLabels.none;

  /// The same, without subscribing: for a tap handler or a route builder that
  /// reads the names once when it runs.
  static GrownupLabels read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GrownupLabelScope>()?.labels ?? GrownupLabels.none;

  @override
  bool updateShouldNotify(GrownupLabelScope old) =>
      old.labels.contacts != labels.contacts ||
      old.labels.primaryId != labels.primaryId ||
      old.labels.age.age != labels.age.age ||
      old.labels.age.locked != labels.age.locked ||
      !_sameMap(old.labels.nicknames, labels.nicknames);

  static bool _sameMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final MapEntry<String, String> e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

/// Loads her nicknames (read-only) and installs a [GrownupLabelScope] for the
/// subtree. Pass [reader] in tests; otherwise it reads the child's own
/// `nicknames` area through [services] (default [LocalServices.current]).
class GrownupLabelsProvider extends StatefulWidget {
  const GrownupLabelsProvider({
    super.key,
    required this.contacts,
    required this.child,
    this.primaryId,
    this.age = const AgeLockState(),
    this.reader,
    this.services,
    this.childId,
  });
  final List<GrownupContact> contacts;
  final String? primaryId;
  final AgeLockState age;
  final NicknameReader? reader;
  final LocalServices? services;
  final String? childId;
  final Widget child;

  @override
  State<GrownupLabelsProvider> createState() => _GrownupLabelsProviderState();
}

class _GrownupLabelsProviderState extends State<GrownupLabelsProvider> {
  Map<String, String> _nicknames = const <String, String>{};

  NicknameReader get _reader =>
      widget.reader ??
      LocalNicknameRepository(
          (widget.services ?? LocalServices.current).area('nicknames', ownerId: widget.childId));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GrownupLabelsProvider old) {
    super.didUpdateWidget(old);
    if (old.reader != widget.reader || old.childId != widget.childId || old.services != widget.services) _load();
  }

  Future<void> _load() async {
    Map<String, String> n;
    try {
      n = await _reader.load();
    } catch (_) {
      n = const <String, String>{}; // a store that cannot be read shows the defaults
    }
    if (!mounted) return;
    setState(() => _nicknames = n);
  }

  @override
  Widget build(BuildContext context) => GrownupLabelScope(
        labels: GrownupLabels(
            contacts: widget.contacts, age: widget.age, nicknames: _nicknames, primaryId: widget.primaryId),
        child: widget.child,
      );
}
