// OLIVE BRANCH — guardian-only "Data on this device" and its PIN-gated wipe.
// No longer UNVERIFIED — verified by CI (client/test/clear_local_data_screen_test.dart).
//
// MASTERFILE section 8.15 (on-device data). The offline-first foundation keeps
// a child's own things on the phone (local_store.dart); this is where a grown-up
// SEES exactly what is kept — the list below is rendered from the very
// catalogue the storage code builds its namespaces from, so it cannot drift from
// what is really written — and can clear all of it.
//
// DESIGN:
//  - Guardian-only. It is reachable from the guardian hub (guardian_more.dart)
//    and nowhere on the child side (child_no_settings_contract_test.dart holds
//    that line).
//  - PIN-gated, FAIL CLOSED. The grown-up's PIN is checked by [verifyPin]; if
//    none is wired (no live session to check against) the screen says so and the
//    action stays unavailable — it never "accepts" a PIN it cannot check. A
//    verifier that throws counts as a wrong PIN. After a correct PIN there is
//    one more plain confirmation, because this cannot be undone.
//  - What a wipe does: deletes EVERY on-device document (journal, lists,
//    pictures, stories, jokes, lessons, collections, ladder, colour, profile
//    cache, outbox, Parent Learn), every quarantined damaged copy, and the
//    encryption key (so any copy of the encrypted files someone kept is
//    unreadable too). What it does NOT do: it does not unpair this device or
//    sign anyone out (that is the paired-devices screen), and it touches
//    nothing on the server — nothing here was ever uploaded.
//  - Export-free. Nothing on this screen, or in what it lists, is part of the
//    court export, and there is no "export this data" button by design: a
//    child's journal and pictures are not evidence this app can hand to anyone
//    (P7). The only thing that leaves this screen is the deletion.
import 'package:flutter/material.dart';

import 'local_services.dart';
import 'maturation_ladder.dart' show childSeenRungReveals;
import 'shared_gallery.dart';

class ClearLocalDataScreen extends StatefulWidget {
  const ClearLocalDataScreen({
    super.key,
    required this.verifyPin,
    this.services,
    this.onCleared,
  });

  /// Checks the grown-up's PIN; true only for a PIN that was really verified.
  /// Null means there is nothing to check it against, and the wipe stays
  /// unavailable.
  final Future<bool> Function(String pin)? verifyPin;

  /// Null means [LocalServices.current].
  final LocalServices? services;

  /// Called once after a successful wipe.
  final VoidCallback? onCleared;

  @override
  State<ClearLocalDataScreen> createState() => _ClearLocalDataScreenState();
}

enum _Phase { idle, checking, wrongPin, cleared, failed }

class _ClearLocalDataScreenState extends State<ClearLocalDataScreen> {
  final TextEditingController _pin = TextEditingController();
  _Phase _phase = _Phase.idle;

  LocalServices get _services => widget.services ?? LocalServices.current;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    final Future<bool> Function(String pin)? verify = widget.verifyPin;
    if (verify == null || _pin.text.isEmpty) return;
    setState(() => _phase = _Phase.checking);
    bool ok;
    try {
      ok = await verify(_pin.text);
    } catch (_) {
      ok = false; // fail closed: a check that cannot run is a wrong PIN
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _phase = _Phase.wrongPin);
      return;
    }
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear everything on this device?'),
        content: const Text(
            'This removes everything listed here from this phone and cannot be undone. '
            'Nothing is removed from anywhere else, because nothing here was ever sent anywhere.'),
        actions: <Widget>[
          TextButton(
              key: const Key('clearDataCancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it')),
          TextButton(
              key: const Key('clearDataConfirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear it')),
        ],
      ),
    );
    if (!mounted) return;
    if (sure != true) {
      setState(() => _phase = _Phase.idle);
      return;
    }
    try {
      await _services.wipeAll();
      // The two pieces of in-process state that mirror what was on disk.
      demoAppGallery.forget();
      childSeenRungReveals.clear();
      _pin.clear();
      if (!mounted) return;
      setState(() => _phase = _Phase.cleared);
      widget.onCleared?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool canVerify = widget.verifyPin != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Data on this device')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(
              'Olive keeps a few things on this phone so they are still here after a restart. '
              'They stay on this phone: they are never uploaded, never part of the court export, '
              'and no scores, streaks or counters are stored.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            for (final LocalDataEntry e in localDataCatalogue)
              Card(
                key: ValueKey<String>('data-${e.area}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Icon(e.encrypted ? Icons.lock_outline : Icons.phone_android_outlined,
                        color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Text(_label(e), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(e.what, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        if (e.encrypted)
                          Text('Sealed with encryption on this phone.',
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 16),
            Text('Clear data on this device',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Removes everything above, including the key that seals the private parts. '
              'It does not unpair this phone or sign anyone out.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (!canVerify)
              Container(
                key: const Key('clearDataUnavailable'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(
                    'Clearing needs your PIN, and there is no way to check it in this build yet '
                    '(it is checked with the server). Nothing has been cleared.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSecondaryContainer)),
              )
            else ...<Widget>[
              TextField(
                key: const Key('clearDataPin'),
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                    labelText: 'Your PIN', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {
                  if (_phase == _Phase.wrongPin) _phase = _Phase.idle;
                }),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('clearDataButton'),
                  onPressed: _phase == _Phase.checking || _pin.text.isEmpty ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear data on this device'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_phase == _Phase.wrongPin)
              Text('That PIN did not match. Nothing was cleared.',
                  key: const Key('clearDataWrongPin'), style: text.bodyMedium?.copyWith(color: scheme.error)),
            if (_phase == _Phase.cleared)
              Text('Cleared. This phone no longer holds any of the above.',
                  key: const Key('clearDataDone'), style: text.bodyMedium),
            if (_phase == _Phase.failed)
              Text('Something stopped the clearing part-way. Try again.',
                  key: const Key('clearDataFailed'), style: text.bodyMedium?.copyWith(color: scheme.error)),
          ]),
        ),
      ),
    );
  }

  static String _label(LocalDataEntry e) => switch (e.area) {
        'journal' => 'Private journal',
        'lists' => 'Wants and needs',
        'pictures' => 'Saved pictures',
        'stories' => 'Stories she kept',
        'jokes' => 'Jokes she starred',
        'lessons' => 'Things she taught',
        'collections' => 'Collections',
        'ladder' => 'Growing-up steps',
        'colour' => "Today's colour",
        'profile' => 'Offline start-up',
        'outbox' => 'Waiting to send',
        'learn' => 'Parent Learn',
        'rhythm' => 'Routine and rhythm',
        'newplace' => 'A new place',
        'voice' => 'Her helpers and symbols',
        'feelings' => 'Feelings weather',
        'worries' => 'Worry box',
        'village' => 'Village',
        'passes' => 'Sitter pass and school summary',
        'compass' => 'Family compass',
        'emergencycard' => 'Emergency card (grown-up side)',
        'memorybox' => 'Her memory box',
        _ => e.area,
      };
}
