// OLIVE BRANCH — changing her LOCKED age, behind the guardian PIN. No longer
// UNVERIFIED — verified by CI (client/test/age_lock_screens_test.dart).
// MASTERFILE §8.5.10.
//
// Her age is locked the moment it is entered (the kid picker locks 5 to 15, the guardian
// onboarding locks 3 to 17; contact_labels.dart `lockKidAge`/`changeAge`). The only way to
// move it afterwards is HERE, and only after the local PIN gate passes: ask for the PIN,
// then offer 3 to 17, then save. A wrong PIN, a locked PIN or Cancel changes nothing.
// A store that cannot be written says so and leaves the old age in place.
//
// Why a PIN at all: the age decides the default words (Mommy/Daddy at a locked 5 to 15)
// and what opens for her; a child who could re-tap a bigger number would be choosing her
// own tier (the same reasoning as §8.5.2). The grown-up's PIN is the proof it is a grown-up.
import 'package:flutter/material.dart';

import 'contact_labels.dart';
import 'guardian_local_scope.dart';
import 'local_family.dart';
import 'local_pin_screens.dart';

/// Runs the whole flow. Returns the new family when the age really changed, else null.
Future<LocalFamily?> changeLockedAgeFlow(BuildContext context, GuardianLocalController local) async {
  final LocalFamily? family = local.family;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  if (family == null) {
    messenger.showSnackBar(const SnackBar(content: Text('There is no family set up on this device.')));
    return null;
  }
  final bool ok = await askLocalPin(
    context,
    local.services.pin,
    title: 'Enter your PIN',
    why: "${family.childName}'s age is locked. Your PIN lets you change it.",
  );
  if (!ok || !context.mounted) return null;
  final int? picked = await showDialog<int>(
    context: context,
    builder: (BuildContext ctx) => _AgeDialog(name: family.childName, current: family.age),
  );
  if (picked == null || picked == family.age) return null;
  final LocalFamily next = family.changeAgeWithPin(picked, guardianPinOk: true);
  try {
    await local.saveFamily(next);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not keep that on this device. Her age is unchanged.')));
    return null;
  }
  messenger.showSnackBar(SnackBar(content: Text("${family.childName} is now ${next.age}.")));
  return next;
}

class _AgeDialog extends StatefulWidget {
  const _AgeDialog({required this.name, required this.current});
  final String name;
  final int current;

  @override
  State<_AgeDialog> createState() => _AgeDialogState();
}

class _AgeDialogState extends State<_AgeDialog> {
  late int _age = widget.current;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text("How old is ${widget.name}?"),
        content: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (int a = kGuardianAgeMin; a <= kGuardianAgeMax; a++)
            ChoiceChip(
              key: Key('lockAge_$a'),
              label: Text('$a'),
              selected: _age == a,
              onSelected: (_) => setState(() => _age = a),
            ),
        ]),
        actions: <Widget>[
          TextButton(
            key: const Key('lockAgeCancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('lockAgeSave'),
            onPressed: () => Navigator.of(context).pop(_age),
            child: const Text('Save'),
          ),
        ],
      );
}
