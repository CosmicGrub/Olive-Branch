// OLIVE BRANCH — step 0 of a first run: "Who is using this device?".
// No longer UNVERIFIED — verified by CI (client/test/role_picker_screen_test.dart).
// MASTERFILE §8.5.8.
//
// Owner requirement, 2026-11-08: the onboarding follows ROLES. Three big picture
// choices (Kid, Mom, Dad) and a smaller "Someone else" (a grandparent or another
// guardian; the coordinator's addition beyond the owner's three).
//
// Built for a child who cannot read yet, because a child is who this is most likely
// to be handed to:
//  * PICTURE FIRST: each choice is a large face with one short word under it. The
//    question is a picture-and-words header, not a paragraph.
//  * 64dp TARGETS everywhere ([kChildTarget]); the three faces are far larger.
//  * READ ALOUD on request: a speaker (when the app has a read-aloud scope) reads the
//    question and the choices; long-press on a face says its word. Speech starts only
//    from a tap or a long-press (read_aloud.dart), never by itself.
//  * NO PRESSURE: nothing is timed, counted or compared; no "step 1 of 7"; a choice
//    is highlighted first and only a second, clearly separate tap ("That's me")
//    commits it, so a mis-tap by a small finger costs nothing.
//
// The screen only reports the choice. Storing it and booting the right shell is the
// caller's job (live_boot_plan.dart, main_live.dart), and a role grants nothing.
import 'package:flutter/material.dart';

import 'access_settings.dart' show kChildTarget;
import 'device_role.dart';
import 'onboarding_shared.dart' show ChildOnboardingScaffold;
import 'read_aloud.dart';

const String kRolePickerQuestion = 'Who is using this device?';

IconData _iconFor(DeviceRole r) => switch (r) {
      DeviceRole.kid => Icons.child_care_rounded,
      DeviceRole.mom => Icons.face_3_rounded,
      DeviceRole.dad => Icons.face_6_rounded,
      DeviceRole.other => Icons.diversity_1_rounded,
    };

class RolePickerScreen extends StatefulWidget {
  const RolePickerScreen({super.key, required this.onPicked, this.initial});

  /// Fires once, when "That's me" is tapped on a highlighted choice.
  final ValueChanged<DeviceRole> onPicked;

  /// Pre-highlighted choice (tests, a device that is re-asking).
  final DeviceRole? initial;

  @override
  State<RolePickerScreen> createState() => _RolePickerScreenState();
}

class _RolePickerScreenState extends State<RolePickerScreen> {
  DeviceRole? _picked;
  final Object _owner = Object();
  ReadAloudController? _reader;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reader = ReadAloudScope.maybeOf(context);
  }

  @override
  void dispose() {
    _reader?.release(_owner);
    super.dispose();
  }

  String get _wholeQuestion =>
      '$kRolePickerQuestion Kid. Mom. Dad. Or someone else, like a grandparent or another grown-up.';

  Future<void> _say(String text) async {
    await _reader?.speak(text, owner: _owner);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool canSpeak = _reader != null;
    return ChildOnboardingScaffold(
      title: kRolePickerQuestion,
      subtitle: 'Tap the picture that is you.',
      continueLabel: "That's me",
      continueEnabled: _picked != null,
      onContinue: _picked == null ? null : () => widget.onPicked(_picked!),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        if (canSpeak)
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: kChildTarget,
              height: kChildTarget,
              child: IconButton(
                key: const Key('roleSpeaker'),
                tooltip: 'Read this out loud',
                icon: Icon(Icons.volume_up_rounded, size: 32, color: scheme.primary),
                onPressed: () => _say(_wholeQuestion),
              ),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final DeviceRole r in <DeviceRole>[DeviceRole.kid, DeviceRole.mom, DeviceRole.dad])
              _BigRoleTile(
                role: r,
                selected: _picked == r,
                onTap: () => setState(() => _picked = r),
                onLongPress: canSpeak ? () => _say(r.title) : null,
              ),
          ],
        ),
        const SizedBox(height: 20),
        _SmallRoleTile(
          selected: _picked == DeviceRole.other,
          onTap: () => setState(() => _picked = DeviceRole.other),
          onLongPress: canSpeak ? () => _say('Someone else, like a grandparent or another grown-up') : null,
        ),
      ]),
    );
  }
}

class _BigRoleTile extends StatelessWidget {
  const _BigRoleTile({required this.role, required this.selected, required this.onTap, this.onLongPress});
  final DeviceRole role;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: role.title,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: Key('role_${role.wire}'),
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96, minHeight: 124),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(_iconFor(role), size: 56, color: selected ? scheme.onPrimary : scheme.primary),
                const SizedBox(height: 8),
                Text(role.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: selected ? scheme.onPrimary : scheme.onSurface)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallRoleTile extends StatelessWidget {
  const _SmallRoleTile({required this.selected, required this.onTap, this.onLongPress});
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Someone else, like a grandparent or another grown-up',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: const Key('role_other'),
        color: selected ? scheme.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kChildTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                Icon(_iconFor(DeviceRole.other), size: 28, color: selected ? scheme.onPrimary : scheme.primary),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(DeviceRole.other.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700, color: selected ? scheme.onPrimary : scheme.onSurface)),
                    Text('A grandparent or another grown-up',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
