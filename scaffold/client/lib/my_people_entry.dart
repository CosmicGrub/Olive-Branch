// OLIVE BRANCH — the door to "My people" from her More hub. No longer UNVERIFIED —
// verified by CI (client/test/my_people_screen_test.dart). MASTERFILE §8.5.10.
//
// Loads what this device knows (the local family's grown-ups and locked age, else two neutral
// placeholders and the age lock cached with her profile) and her own nickname store, then shows
// [MyPeopleScreen]. All three are injectable; the defaults are this device's own sealed store,
// scoped to the current child. Nothing here reads a server.
import 'package:flutter/material.dart';

import 'contact_labels.dart';
import 'grownup_labels.dart';
import 'grownup_roster.dart';
import 'local_family.dart';
import 'local_pin.dart' show kLocalGuardianScope;
import 'local_repositories.dart';
import 'local_services.dart';
import 'my_people_screen.dart';

/// What this device knows about her grown-ups and her locked age: the local family if there is one,
/// else the placeholders and the age lock cached with her profile. Never throws.
Future<KidRoster> loadKidRosterForDevice({int? fallbackAge, LocalServices? services}) async {
  final LocalServices s = services ?? LocalServices.current;
  AgeLockState cached = AgeLockState(age: fallbackAge);
  try {
    final ProfileCache? p = await ProfileCacheRepository(s.area('profile')).load();
    if (p != null && p.yearsOld != null) cached = AgeLockState(age: p.yearsOld, locked: p.ageLocked);
  } catch (_) {
    // An unreadable cache is simply "no locked age".
  }
  try {
    return await loadKidRoster(
      LocalStoreLocalFamilyRepository(s.area('localfamily', ownerId: kLocalGuardianScope)),
      fallbackAge: cached,
    );
  } catch (_) {
    return KidRoster(contacts: placeholderGrownups(), known: false, age: cached);
  }
}

/// Installs the [GrownupLabelScope] at the root of the child shell (the label-adoption follow-up): every
/// child-facing screen then says what SHE calls her grown-ups (her word, else Mommy/Daddy at a locked 5 to 15,
/// else the grown-up's label). Only READS her nicknames. With nobody known it shows the neutral words, as
/// [GrownupLabels.none] does, never a guessed Dad. Until the device answers it renders the child without a scope.
class KidLabelsHost extends StatefulWidget {
  const KidLabelsHost({super.key, required this.child, this.childId, this.loadRoster, this.reader});
  final Widget child;
  final String? childId;
  final Future<KidRoster> Function()? loadRoster;
  final NicknameReader? reader;

  @override
  State<KidLabelsHost> createState() => _KidLabelsHostState();
}

class _KidLabelsHostState extends State<KidLabelsHost> {
  KidRoster? _roster;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final KidRoster r = await (widget.loadRoster ?? loadKidRosterForDevice)();
    if (mounted) setState(() => _roster = r);
  }

  @override
  Widget build(BuildContext context) {
    final KidRoster? r = _roster;
    if (r == null || !r.known) {
      // Placeholders are not people: screens keep their neutral words.
      return GrownupLabelsProvider(
          contacts: const <GrownupContact>[], age: r?.age ?? const AgeLockState(),
          childId: widget.childId, reader: widget.reader, child: widget.child);
    }
    return GrownupLabelsProvider(
        contacts: r.contacts, age: r.age, childId: widget.childId, reader: widget.reader, child: widget.child);
  }
}

class MyPeopleEntry extends StatefulWidget {
  const MyPeopleEntry({super.key, this.loadRoster, this.nicknames, this.fallbackAge});

  /// Null: this device's local family, else the placeholders.
  final Future<KidRoster> Function()? loadRoster;

  /// Null: `child.<id>.nicknames` of the current child.
  final NicknameRepository? nicknames;

  /// The age to use when neither the local family nor the cached profile has a locked one.
  final int? fallbackAge;

  @override
  State<MyPeopleEntry> createState() => _MyPeopleEntryState();
}

class _MyPeopleEntryState extends State<MyPeopleEntry> {
  late final Future<KidRoster> _roster = _load();

  Future<KidRoster> _load() async {
    final Future<KidRoster> Function()? custom = widget.loadRoster;
    if (custom != null) return custom();
    return loadKidRosterForDevice(fallbackAge: widget.fallbackAge);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<KidRoster>(
        future: _roster,
        builder: (BuildContext context, AsyncSnapshot<KidRoster> snap) {
          final KidRoster? r = snap.data;
          if (r == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('My people')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          return MyPeopleScreen(
            contacts: r.contacts,
            age: r.age,
            nicknames: widget.nicknames ?? LocalNicknameRepository(LocalServices.current.area('nicknames')),
          );
        },
      );
}
