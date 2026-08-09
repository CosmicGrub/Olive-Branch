// OLIVE BRANCH — shared list-tile chrome for the navigation hubs the
// wiring pass adds (games_hub.dart, child_more.dart, guardian_more.dart).
// UNVERIFIED (no Flutter toolchain in tools/verify.sh's automated
// pipeline).
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

class HubTile extends StatelessWidget {
  const HubTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
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
                  child: Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            )),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
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
