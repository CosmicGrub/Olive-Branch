// OLIVE BRANCH — "My people": a child names her own grown-ups. No longer UNVERIFIED —
// verified by CI (client/test/my_people_screen_test.dart). MASTERFILE §8.5.10.
//
// Owner requirement, 2026-11-08: once the age is locked the words become Mommy and Daddy, and
// "let the kid edit what they want to call mommy and daddy, like renaming contacts". This is the
// renaming: a face for each grown-up, a tap, and a bank of words to pick from (Mommy, Mama, Mum,
// Mom, Mummy, Daddy, Dada, Papa, Pop, Dad; [kNicknameBank]) or her own word, typed.
//
// Two places use it. In the FIRST RUN ([firstRun]) it is the step after "who is here" and the
// grown-up's words are optional ("Skip for now"). From her More hub it is a screen of its own,
// reachable any time, with the same faces.
//
// WHAT SHE SEES is [ContactLabels.forChild]: her word, else the age default (Mommy/Daddy at a locked
// 5 to 15 for a Mom or a Dad), else the grown-up's own label. The word she picks is HERS: it is stored
// by [NicknameRepository], the only writer, and no guardian screen is handed that repository
// (a guardian's [NicknameReader] cannot write, so a grown-up can see "Ivy calls you Dada" and never
// change it).
//
// PICTURE-FIRST and calm: a large face per grown-up, 64dp targets (the word bank, the "my own word"
// field and every button), long-press on a face says its name aloud when read-aloud is on. Nothing is
// counted, ranked or timed (P2). A failed save never shows error text: a short, plain "That did not
// save. Try again." and she may try again.
import 'package:flutter/material.dart';

import 'access_settings.dart' show kChildTarget;
import 'contact_labels.dart';
import 'onboarding_shared.dart' show ChildOnboardingScaffold, TapChoice;
import 'read_aloud.dart';

class MyPeopleScreen extends StatefulWidget {
  const MyPeopleScreen({
    super.key,
    required this.contacts,
    required this.age,
    required this.nicknames,
    this.firstRun = false,
    this.onDone,
  });

  final List<GrownupContact> contacts;
  final AgeLockState age;

  /// Hers. The writer; never passed to a guardian screen.
  final NicknameRepository nicknames;

  /// True inside the first run: the onboarding chrome, "Next" and "Skip for now".
  final bool firstRun;

  /// First run only: fires on "Next" or "Skip for now".
  final VoidCallback? onDone;

  @override
  State<MyPeopleScreen> createState() => _MyPeopleScreenState();
}

class _MyPeopleScreenState extends State<MyPeopleScreen> {
  Map<String, String> _nicks = const <String, String>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, String> m;
    try {
      m = await widget.nicknames.load();
    } catch (_) {
      m = const <String, String>{};
    }
    if (!mounted) return;
    setState(() {
      _nicks = m;
      _loaded = true;
    });
  }

  String _nameOf(GrownupContact c) => ContactLabels.forChild(c, age: widget.age, nicknames: _nicks);

  Future<void> _edit(GrownupContact c) async {
    final _Picked? picked = await showModalBottomSheet<_Picked>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => _NameSheet(
        shown: _nameOf(c),
        hasNickname: ContactLabels.cleanNickname(_nicks[c.id]) != null,
      ),
    );
    if (picked == null) return;
    try {
      await widget.nicknames.set(c.id, picked.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That did not save. Try again.')));
      return;
    }
    await _load();
  }

  Widget _faces(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: <Widget>[
        for (final GrownupContact c in widget.contacts)
          Semantics(
            button: true,
            label: _nameOf(c),
            hint: 'Tap to change the name',
            excludeSemantics: true,
            onTap: () => _edit(c),
            child: Material(
              key: Key('person_${c.id}'),
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _edit(c),
                onLongPress: () => speakOnLongPress(context, _nameOf(c)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 140, minHeight: 140),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: scheme.primary,
                        child: Icon(Icons.favorite_rounded, color: scheme.onPrimary, size: 34),
                      ),
                      const SizedBox(height: 10),
                      Text(_nameOf(c),
                          key: Key('personName_${c.id}'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)),
                      const SizedBox(height: 4),
                      Icon(Icons.edit_outlined, size: 22, color: scheme.onPrimaryContainer),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = !_loaded ? const Center(child: CircularProgressIndicator()) : _faces(context);
    if (widget.firstRun) {
      return ChildOnboardingScaffold(
        title: 'What do you call your grown-ups?',
        subtitle: 'Tap a face to pick a name.',
        continueLabel: 'Next',
        onContinue: widget.onDone,
        onSkip: widget.onDone,
        body: body,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My people')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('Tap a face to pick a name.', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
            body,
          ]),
        ),
      ),
    );
  }
}

/// What the sheet reports: a name, or null for "go back to the usual word".
class _Picked {
  const _Picked(this.name);
  final String? name;
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.shown, required this.hasNickname});
  final String shown;
  final bool hasNickname;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  final TextEditingController _own = TextEditingController();

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  void _useOwn() {
    final String? n = ContactLabels.cleanNickname(_own.text);
    if (n != null) Navigator.of(context).pop(_Picked(n));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('What do you call them?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: <Widget>[
              for (final String w in kNicknameBank)
                TapChoice(
                  key: Key('bank_$w'),
                  label: w,
                  selected: w == widget.shown,
                  minSide: kChildTarget,
                  onTap: () => Navigator.of(context).pop(_Picked(w)),
                ),
            ]),
            const SizedBox(height: 20),
            TextField(
              key: const Key('ownName'),
              controller: _own,
              maxLength: kMaxNicknameLength,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: 'Or type your own',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _useOwn(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: kChildTarget,
              child: FilledButton(
                key: const Key('ownNameOk'),
                onPressed: _useOwn,
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('OK', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            if (widget.hasNickname) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                height: kChildTarget,
                child: TextButton(
                  key: const Key('nameReset'),
                  onPressed: () => Navigator.of(context).pop(const _Picked(null)),
                  style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                  child: const Text('Use the usual word'),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
