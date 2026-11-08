// OLIVE BRANCH — the door to "My people" from her More hub. No longer UNVERIFIED —
// verified by CI (client/test/my_people_screen_test.dart). MASTERFILE §8.5.10.
//
// Loads what this device knows (the local family's grown-ups and locked age, else two neutral
// placeholders and the age lock cached with her profile) and her own nickname store, then shows
// [MyPeopleScreen]. All three are injectable; the defaults are this device's own sealed store,
// scoped to the current child. Nothing here reads a server.
import 'package:flutter/material.dart';

import 'contact_labels.dart';
import 'grownup_roster.dart';
import 'local_family.dart';
import 'local_pin.dart' show kLocalGuardianScope;
import 'local_repositories.dart';
import 'local_services.dart';
import 'my_people_screen.dart';

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
    final LocalServices s = LocalServices.current;
    AgeLockState cached = AgeLockState(age: widget.fallbackAge);
    try {
      final ProfileCache? p = await ProfileCacheRepository(s.area('profile')).load();
      if (p != null && p.yearsOld != null) cached = AgeLockState(age: p.yearsOld, locked: p.ageLocked);
    } catch (_) {
      // An unreadable cache is simply "no locked age".
    }
    return loadKidRoster(
      LocalStoreLocalFamilyRepository(s.area('localfamily', ownerId: kLocalGuardianScope)),
      fallbackAge: cached,
    );
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
