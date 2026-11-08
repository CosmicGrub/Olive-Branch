// OLIVE BRANCH — shared list-tile chrome for the navigation hubs the
// wiring pass adds (games_hub.dart, child_more.dart, guardian_more.dart).
// No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs for real in tools/verify.sh's
// automated pipeline — CHANGELOG v0.49.61).
//
// Not a MARKUP screen itself — pure presentation plumbing, the same role
// onboarding_shared.dart's ChildOnboardingScaffold plays for that group.
// SingleChildScrollView + Column is the caller's job, not this file's, but
// every hub built on top of these two widgets follows that convention —
// several parallel groups independently hit and documented the same
// ListView sliver-virtualization pitfall (widgets scrolled below the fold
// silently drop out of the element tree), so this wiring pass avoids it
// from the start rather than rediscovering it.
import 'package:flutter/material.dart';
import 'access_scope.dart' show guardianTargetOf;
import 'read_aloud.dart';

class HubTile extends StatefulWidget {
  const HubTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
    this.readAloud = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  /// Optional, additive — every existing caller (60 call sites across 4
  /// files, pre-dating this field) omits it and keeps getting the plain
  /// chevron below, unchanged. Only storyteller_screen.dart's own bookmark
  /// row supplies one today (its "remove bookmark" button, migrated onto
  /// HubTile from a bare Card+ListTile — design spec: docs/superpowers/
  /// specs/2026-09-15-design-tokens-named-migration-design.md, Fix #4 —
  /// which needs its own real action alongside the row's own onTap-to-
  /// resume, not just a static chevron).
  final Widget? trailing;

  /// Read-aloud for a CHILD's hub row (a speaker and long-press that read the title).
  /// False by default: guardian hubs share this widget and have no speakers.
  final bool readAloud;

  @override
  State<HubTile> createState() => _HubTileState();
}

class _HubTileState extends State<HubTile> {
  ReadAloudController? _ra;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ra = ReadAloudScope.maybeOf(context);
  }

  @override
  void dispose() {
    _ra?.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon, title = widget.title, subtitle = widget.subtitle, onTap = widget.onTap,
        trailing = widget.trailing;
    final ReadAloudController? ra = widget.readAloud ? ReadAloudScope.enabledOf(context) : null;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        // Long-press reads the row's name; a plain tap still opens it.
        onLongPress: ra == null ? null : () => ra.speak(title, owner: this),
        child: Container(
          // 56 always clears the 48dp guardian floor; with "larger targets" it rises to 64.
          constraints: BoxConstraints(minHeight: guardianTargetOf(context) > 56 ? guardianTargetOf(context) : 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(icon, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null) Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(subtitle, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            )),
            const SizedBox(width: 8),
            if (ra != null) SpeakerButton(text: title, label: 'Read "$title" out loud'),
            trailing ?? const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

class HubSection extends StatelessWidget {
  const HubSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 0.6, fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary)),
      ),
      ...children,
    ]),
  );
}
