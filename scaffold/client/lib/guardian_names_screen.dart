// OLIVE BRANCH — "Ivy calls you": what she calls each of her grown-ups (the
// prototype's ob.names). No longer UNVERIFIED — verified by CI
// (client/test/guardian_hub_parity_test.dart). MASTERFILE §8.5.7, §8.1.
//
// READ-ONLY, on purpose. The words are HERS: she picks one on her own tablet and
// only she can change it. This screen is handed a [NicknameReader], which has no
// setter, so no tap here could write one. It shows, for each grown-up in the local
// family, the name and label they gave, and how she says it ("Ivy calls you Dada").
// With no local family on this device (a build that boots paired) it says so and
// shows nothing invented.
import 'package:flutter/material.dart';

import 'contact_labels.dart';
import 'local_family.dart';
import 'local_services.dart';
import 'ui/olive_ui.dart';

/// The word she uses for [contact] (the nickname she chose, else the age default,
/// else the guardian's own label), as a guardian's settings row shows it.
String herWordFor(GrownupContact contact, {required AgeLockState age, required Map<String, String> nicknames}) =>
    ContactLabels.forChild(contact, age: age, nicknames: nicknames);

/// "Ivy calls you Dada." The guardian-side sentence for one grown-up.
String callsYouLine(String childName, String word) => '$childName calls you $word';

class GuardianNamesScreen extends StatefulWidget {
  const GuardianNamesScreen({super.key, required this.childName, required this.family, this.nicknames});

  final String childName;

  /// The local family, or null when this build has none on this device.
  final LocalFamily? family;

  /// Read-only. Null reads this device's own nicknames store.
  final NicknameReader? nicknames;

  @override
  State<GuardianNamesScreen> createState() => _GuardianNamesScreenState();
}

class _GuardianNamesScreenState extends State<GuardianNamesScreen> {
  Map<String, String>? _nicks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, String> m;
    try {
      m = await (widget.nicknames ?? LocalNicknameRepository(LocalServices.current.area('nicknames'))).load();
    } catch (_) {
      m = const <String, String>{};
    }
    if (mounted) setState(() => _nicks = m);
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.childName;
    final LocalFamily? f = widget.family;
    final Map<String, String>? nicks = _nicks;
    return Scaffold(
      appBar: AppBar(title: Text('$name calls you')),
      body: SafeArea(
        child: nicks == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  if (f == null)
                    const EmptyState(
                      key: Key('namesNoFamily'),
                      title: 'No family on this phone yet',
                      sub: 'Her words for each grown-up show here once a family is set up on this phone.',
                    )
                  else
                    OliveCard(
                      child: Column(children: <Widget>[
                        for (final GrownupContact g in f.grownups)
                          OliveRow(
                            key: Key('namesRow_${g.id}'),
                            icon: OliveIcons.heart,
                            title: '${f.guardianName} (${g.guardianLabel})',
                            sub: callsYouLine(name, herWordFor(g, age: f.ageLock, nicknames: nicks)),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 12),
                  OliveCard(
                    variant: OliveCardVariant.tint,
                    child: Text(
                      'Names belong to $name. Only she can change what she calls you, from her own tablet.',
                      key: const Key('namesHint'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ]),
              ),
      ),
    );
  }
}
