// OLIVE BRANCH — the guardian's first run: a LOCAL family, a local PIN, and
// "Connect this device" last. No longer UNVERIFIED — verified by CI
// (client/test/guardian_onboarding_test.dart). MASTERFILE §8.5.9.
//
// Owner requirement, 2026-11-08: a Mom, a Dad or someone else gets their own
// onboarding. Audit findings A-G1/A-G2: until now a new parent could not start at all (the
// only way in was a pairing code another guardian made) and an offline launch landed on a
// server-PIN setup that could not be left. Everything before the last step runs with NO
// server:
//
//   1. You: your name, and what she calls you (Mom, Dad, or a word you choose).
//   2. Her: first name and age (3 to 17). THE AGE IS LOCKED: it comes out as the
//      locked age that gives Mommy/Daddy at 5 to 15, and changing it later needs the PIN
//      below. The kid picker she will see stays 5 to 15; a grown-up may set 3 to 17.
//   3. Her time zone: "same as this phone" or one of a short list.
//   4. A PIN for this device (local_pin.dart). Not skippable: it is what lets this device
//      open offline. It is not the account PIN.
//   5. Connect this device (pairing_redeem_screen.dart, `localFirst`): LAST, and only
//      when a server exists ([serverAvailable]). "Not now" is a real way on: the family
//      keeps working offline and connecting stays in Settings > Account.
//
// The family and the PIN are saved when step 4 ends, BEFORE step 5, so a restart (or "Not
// now") never repeats steps 1 to 4. A store that cannot be written is said plainly and
// holds the grown-up on step 4 to try again; nothing is reported saved that is not.
//
// This does not create a server account, send anything, or grant any authority: it is a
// local record (local_family.dart). Connecting does not upload it either: no server route
// takes it.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'contact_labels.dart';
import 'device_role.dart';
import 'guardian_local_scope.dart';
import 'local_family.dart';
import 'local_pin_screens.dart';
import 'pairing_redeem_screen.dart';

enum GuardianOnboardingStage { you, her, zone, pin, connect }

class GuardianOnboardingFlow extends StatefulWidget {
  const GuardianOnboardingFlow({
    super.key,
    required this.role,
    required this.services,
    required this.onFinished,
    this.serverAvailable = false,
    this.baseUrl = '',
    this.onRedeemed,
    this.httpClient,
  });

  final DeviceRole role;
  final GuardianLocalServices services;

  /// The local family is saved and the PIN is set; the grown-up chose not to (or cannot)
  /// connect. The caller opens the offline guardian home.
  final void Function(LocalFamily family) onFinished;

  /// True in a live build (there is a server to connect to). False hides step 5.
  final bool serverAvailable;
  final String baseUrl;

  /// A successful redeem at step 5. The caller stores the identity and boots the connected
  /// guardian shell.
  final void Function(Map<String, dynamic> result)? onRedeemed;
  final http.Client? httpClient;

  @override
  State<GuardianOnboardingFlow> createState() => _GuardianOnboardingFlowState();
}

class _GuardianOnboardingFlowState extends State<GuardianOnboardingFlow> {
  GuardianOnboardingStage _stage = GuardianOnboardingStage.you;
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _label = TextEditingController(text: widget.role.defaultLabel);
  final TextEditingController _child = TextEditingController();
  int? _age;
  String _zone = kHomeZoneDevice;
  String? _error;
  LocalFamily? _saved;

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    _child.dispose();
    super.dispose();
  }

  void _go(GuardianOnboardingStage s) => setState(() {
        _stage = s;
        _error = null;
      });

  void _fromYou() {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Please add your name.');
    if (_label.text.trim().isEmpty) return setState(() => _error = 'Please choose what she should call you.');
    if (_name.text.trim().length > kMaxNameLength || _label.text.trim().length > kMaxNicknameLength) {
      return setState(() => _error = 'That is a little too long.');
    }
    _go(GuardianOnboardingStage.her);
  }

  void _fromHer() {
    if (_child.text.trim().isEmpty) return setState(() => _error = 'Please add her first name.');
    if (_child.text.trim().length > kMaxNameLength) return setState(() => _error = 'That is a little too long.');
    if (_age == null) return setState(() => _error = 'Please choose her age.');
    _go(GuardianOnboardingStage.zone);
  }

  /// Called after the PIN really is stored: now the family record. Both must exist before
  /// the connect step, so a restart does not repeat the questions.
  Future<void> _pinSaved() async {
    final String label = _label.text.trim();
    final LocalFamily family;
    try {
      family = LocalFamily.fromAnswers(
        guardianName: _name.text,
        guardianLabel: label,
        guardianKind: kindForGuardianLabel(label),
        childName: _child.text,
        age: _age!,
        homeZone: _zone,
      );
      await widget.services.families.save(family);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not keep your family on this device. Please try again.');
      return;
    }
    if (!mounted) return;
    _saved = family;
    if (widget.serverAvailable && widget.onRedeemed != null) {
      _go(GuardianOnboardingStage.connect);
    } else {
      widget.onFinished(family);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case GuardianOnboardingStage.you:
        return _page(
          title: 'About you',
          intro: 'This stays on this device. There is nothing to sign up for.',
          nextKey: const Key('goYouNext'),
          onNext: _fromYou,
          children: <Widget>[
            TextField(
              key: const Key('goName'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            Text('What does she call you?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: <Widget>[
              for (final String w in <String>['Mom', 'Dad'])
                ChoiceChip(
                  key: Key('goLabel_$w'),
                  label: Text(w),
                  selected: _label.text.trim() == w,
                  onSelected: (_) => setState(() => _label.text = w),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              key: const Key('goLabel'),
              controller: _label,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Or your own word',
                hintText: widget.role == DeviceRole.other ? 'Grandma, Nana, Uncle Sam' : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );
      case GuardianOnboardingStage.her:
        return _page(
          title: 'About her',
          intro: 'Her age is locked once you set it. Changing it later needs your PIN.',
          nextKey: const Key('goHerNext'),
          onNext: _fromHer,
          children: <Widget>[
            TextField(
              key: const Key('goChild'),
              controller: _child,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Her first name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            Text('How old is she?', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (int a = kGuardianAgeMin; a <= kGuardianAgeMax; a++)
                ChoiceChip(
                  key: Key('goAge_$a'),
                  label: Text('$a'),
                  selected: _age == a,
                  onSelected: (_) => setState(() => _age = a),
                ),
            ]),
          ],
        );
      case GuardianOnboardingStage.zone:
        return _page(
          title: 'Where does she live?',
          intro: 'Her time zone. "Same as this phone" is right for most families.',
          nextKey: const Key('goZoneNext'),
          onNext: () => _go(GuardianOnboardingStage.pin),
          children: <Widget>[
            RadioGroup<String>(
              groupValue: _zone,
              onChanged: (String? v) => setState(() => _zone = v ?? kHomeZoneDevice),
              child: Column(children: <Widget>[
                for (final HomeZone z in kHomeZones)
                  RadioListTile<String>(
                    key: Key('goZone_${z.id}'),
                    value: z.id,
                    title: Text(z.label),
                  ),
              ]),
            ),
          ],
        );
      case GuardianOnboardingStage.pin:
        return _page(
          title: 'A PIN for this device',
          intro: 'It guards your settings, her locked age and clearing data, and works with no '
              'connection. It is not your account PIN.',
          showNext: false,
          children: <Widget>[
            LocalPinSetupForm(
              key: const Key('goPinForm'),
              service: widget.services.pin,
              onSaved: _pinSaved,
              saveLabel: 'Save PIN and continue',
            ),
          ],
        );
      case GuardianOnboardingStage.connect:
        return PairingRedeemScreen(
          baseUrl: widget.baseUrl,
          role: 'guardian',
          localFirst: true,
          httpClient: widget.httpClient,
          onRedeemed: widget.onRedeemed!,
          onNotNow: () => widget.onFinished(_saved!),
        );
    }
  }

  Widget _page({
    required String title,
    required String intro,
    required List<Widget> children,
    VoidCallback? onNext,
    Key? nextKey,
    bool showNext = true,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(intro, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            ...children,
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, key: const Key('goError'), style: TextStyle(color: scheme.error)),
              ),
            if (showNext) ...<Widget>[
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: FilledButton(
                  key: nextKey,
                  onPressed: onNext,
                  child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
