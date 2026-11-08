// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_test.dart).
// OLIVE BRANCH — status and feedback.
//
//   StatusPill      <- kit `K.status(kind, text)`: queued sent delivering delivered watched failed banked.
//                      Shape + icon + word, never colour alone.
//   OliveNotice / OliveBanner <- kit `K.notice(o)` / `K.banner(tone, text, ic)`
//   OfflineBanner   <- kit `K.offlineBanner(o)`
//   OliveToast + showOliveToast <- kit `K.toast(text, o)` (a SnackBar underneath)
//   EmptyState      <- kit `K.emptyState(o)`; `EmptyState.child` is picture only (no text)
//   ErrorState      <- kit `K.errorState(o)`; `ErrorState.child` is picture only (no text)
//   OliveSkeleton   <- kit `K.skeleton(kind, n)`: row card text tile hero (static, no shimmer)
//   PermissionPrompt<- kit `K.permission(o)`
//
// Replaces (adoption wave): degradation_banner.dart's banner, ad-hoc SnackBars, the per-screen
// "nothing here yet" Text/Icon columns, CircularProgressIndicator loading states.
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'olive_art.dart';
import 'olive_base.dart';
import 'olive_palette.dart';
import 'olive_surfaces.dart';

/// The message-delivery states of the kit, plus `delivering` (on the wire now).
enum StatusKind { queued, sent, delivering, delivered, watched, failed, banked }

/// Kit `K.status`. Every state differs in SHAPE (dashed outline, solid, ringed, bold edge), ICON and
/// WORD, so no state depends on colour alone (WCAG 1.4.1). The word is always present, and is the
/// semantic label.
class StatusPill extends StatelessWidget {
  const StatusPill(this.kind, {super.key, this.text, this.small = false});

  final StatusKind kind;
  /// Overrides the default word ("Queued", "Sent", ...), e.g. "Watched 7:04".
  final String? text;
  final bool small;

  static String defaultWord(StatusKind k) => switch (k) {
        StatusKind.queued => 'Queued',
        StatusKind.sent => 'Sent',
        StatusKind.delivering => 'Sending',
        StatusKind.delivered => 'Delivered',
        StatusKind.watched => 'Watched',
        StatusKind.failed => 'Failed',
        StatusKind.banked => 'Banked',
      };

  /// The icon of each state (distinct per state).
  static String iconFor(StatusKind k) => switch (k) {
        StatusKind.queued => OliveIcons.clock,
        StatusKind.sent => OliveIcons.check,
        StatusKind.delivering => OliveIcons.send,
        StatusKind.delivered => OliveIcons.check2,
        StatusKind.watched => OliveIcons.eye,
        StatusKind.failed => OliveIcons.warn,
        StatusKind.banked => OliveIcons.hourglass,
      };

  /// The outline treatment of each state: 'dashed', 'solid', 'bold', 'ring' or 'none'. Together with
  /// [iconFor] and [defaultWord] this is what tells the states apart besides colour.
  static String edgeFor(StatusKind k) => switch (k) {
        StatusKind.queued => 'dashed',
        StatusKind.delivering => 'solid',
        StatusKind.failed => 'bold',
        StatusKind.watched => 'ring',
        _ => 'none',
      };

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final edge = edgeFor(kind);
    final tone = switch (kind) {
      StatusKind.queued => OliveTone.info,
      StatusKind.sent || StatusKind.delivering || StatusKind.delivered => OliveTone.pri,
      StatusKind.watched => OliveTone.ok,
      StatusKind.failed => OliveTone.bad,
      StatusKind.banked => OliveTone.warn,
    };
    final fg = p.toneFg(tone);
    final bg = kind == StatusKind.queued ? Colors.transparent : p.toneBg(tone);
    final word = text ?? defaultWord(kind);
    final pill = CustomPaint(
      // Queued: a dashed outline. Delivering: a solid outline. Failed: a bold solid outline.
      // Watched: an inner ring. Others: filled with no outline.
      foregroundPainter: _PillEdgePainter(
        color: fg,
        dashed: edge == 'dashed',
        solid: edge == 'solid' || edge == 'bold',
        ring: edge == 'ring',
        strong: edge == 'bold',
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(small ? 6 : 8, small ? 2 : 3, small ? 8 : 10, small ? 2 : 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          OliveIcon(iconFor(kind), size: small ? 12 : 14, strokeWidth: 2.2, color: fg),
          const SizedBox(width: 5),
          Flexible(child: Text(word, style: OliveText.strong(context, color: fg, size: small ? 11 : 12).copyWith(height: 1.2))),
        ]),
      ),
    );
    return Semantics(label: word, container: true, child: ExcludeSemantics(child: pill));
  }
}

class _PillEdgePainter extends CustomPainter {
  _PillEdgePainter({required this.color, required this.dashed, required this.solid, required this.ring, required this.strong});
  final Color color;
  final bool dashed, solid, ring, strong;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    if (dashed || solid) {
      final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)).deflate(0.75);
      final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = strong ? 2 : 1.5..color = color..isAntiAlias = true;
      if (solid) {
        canvas.drawRRect(rect, paint);
      } else {
        final path = Path()..addRRect(rect);
        for (final PathMetric m in path.computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            canvas.drawPath(m.extractPath(d, (d + 4).clamp(0, m.length)), paint);
            d += 7;
          }
        }
      }
    }
    if (ring) {
      final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)).deflate(0.5);
      canvas.drawRRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = color.withValues(alpha: 0.28));
    }
  }

  @override
  bool shouldRepaint(_PillEdgePainter o) =>
      o.color != color || o.dashed != dashed || o.solid != solid || o.ring != ring || o.strong != strong;
}

String _toneIcon(OliveTone t) => switch (t) {
      OliveTone.ok => OliveIcons.check,
      OliveTone.warn || OliveTone.bad => OliveIcons.warn,
      OliveTone.info => OliveIcons.info,
      _ => OliveIcons.leaf,
    };

/// Kit `K.notice`: a rich inline notice with an icon plate, optional title, text, action and dismiss.
/// `bad` notices are announced as alerts; the others politely.
class OliveNotice extends StatelessWidget {
  const OliveNotice({
    super.key,
    this.tone = OliveTone.info,
    this.title,
    this.text,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final OliveTone tone;
  final String? title;
  final String? text;
  final String? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final fg = p.toneFg(tone);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: p.toneBg(tone),
          borderRadius: BorderRadius.circular(OliveRadius.r2),
          border: Border.all(color: fg.withValues(alpha: 0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: fg.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: Center(child: OliveIcon(icon ?? _toneIcon(tone), size: 20, strokeWidth: 2, color: fg)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (title != null) Text(title!, style: OliveText.head(context, color: fg).copyWith(fontSize: 15)),
              if (text != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(text!, style: OliveText.body(context, color: fg).copyWith(fontSize: 13.5))),
              if (actionLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OlivePressable(
                    onTap: onAction,
                    borderRadius: 12,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(border: Border.all(color: fg, width: 1.5), borderRadius: BorderRadius.circular(12)),
                      child: Text(actionLabel!, style: OliveText.strong(context, color: fg, size: 13)),
                    ),
                  ),
                ),
            ]),
          ),
          if (onDismiss != null)
            OliveIconButton(OliveIcons.x, label: 'Dismiss', onPressed: onDismiss, small: true, kind: OliveButtonKind.tonal, iconSize: 16),
        ]),
      ),
    );
  }
}

/// Kit `K.banner`: the plain one-line banner (icon and words on a tinted strip).
class OliveBanner extends StatelessWidget {
  const OliveBanner(this.text, {super.key, this.tone = OliveTone.info, this.icon});

  final String text;
  final OliveTone tone;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final fg = p.toneFg(tone);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(color: p.toneBg(tone), borderRadius: BorderRadius.circular(OliveRadius.r2)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: OliveIcon(icon ?? _toneIcon(tone), size: 18, strokeWidth: 2, color: fg)),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: OliveText.body(context, color: fg).copyWith(fontSize: 13.5))),
        ]),
      ),
    );
  }
}

/// Kit `K.offlineBanner`: the calm "you are offline" strip. Reassures rather than alarms.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.text = 'You are offline',
    this.sub = 'Messages are kept safe and will go when you are back.',
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String sub;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
            color: p.surface3, borderRadius: BorderRadius.circular(OliveRadius.r2), border: Border.all(color: p.line)),
        child: Row(children: [
          OliveIcon(OliveIcons.wifioff, size: 20, strokeWidth: 2, color: p.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(text, style: OliveText.strong(context, size: 14)),
              Text(sub, style: OliveText.cap(context, color: p.ink2)),
            ]),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 8),
            OliveButton(actionLabel!, onPressed: onAction, kind: OliveButtonKind.ghost, size: OliveButtonSize.sm),
          ],
        ]),
      ),
    );
  }
}

/// Kit `K.toast` (inline form). Use [showOliveToast] to float one above the content.
class OliveToast extends StatelessWidget {
  const OliveToast(this.text, {super.key, this.icon, this.tone, this.actionLabel, this.onAction});

  final String text;
  final String? icon;
  /// ok or bad tints the icon (kit `.toast.ok .ico`).
  final OliveTone? tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final iconColor = switch (tone) { OliveTone.ok => p.okC, OliveTone.bad => p.badC, _ => p.bg };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(16), boxShadow: p.shadow(3)),
        child: Row(children: [
          if (icon != null) ...[OliveIcon(icon!, size: 18, strokeWidth: 2, color: iconColor), const SizedBox(width: 10)],
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(text, style: OliveText.strong(context, color: p.bg, size: 14)))),
          if (actionLabel != null)
            OlivePressable(
              onTap: onAction,
              borderRadius: 10,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(actionLabel!, style: OliveText.strong(context, color: p.priC, size: 13.5)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Shows an [OliveToast] as a floating SnackBar (kit `K.toast`, which sits above the tab bar).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showOliveToast(
  BuildContext context,
  String text, {
  String? icon,
  OliveTone? tone,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  return messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    duration: duration,
    content: OliveToast(text, icon: icon, tone: tone, actionLabel: actionLabel, onAction: () {
      messenger.hideCurrentSnackBar();
      onAction?.call();
    }),
  ));
}

/// Kit `K.emptyState`: a spot illustration, a title, a sentence and an optional action.
/// [EmptyState.child] is the child's version: the picture alone, no words at all.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.sub, this.spot = 'leaf', this.actionLabel, this.onAction})
      : _childVariant = false, semanticLabel = null;

  /// Picture only. [semanticLabel] is for screen readers and is never drawn.
  const EmptyState.child({super.key, this.spot = 'leaf', this.semanticLabel})
      : title = '', sub = null, actionLabel = null, onAction = null, _childVariant = true;

  final String title;
  final String? sub;
  final String spot;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? semanticLabel;
  final bool _childVariant;

  @override
  Widget build(BuildContext context) {
    if (_childVariant) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: OliveSpot(spot, size: 128, semanticLabel: semanticLabel),
        ),
      );
    }
    final p = OlivePalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          OliveSpot(spot),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: OliveText.head(context).copyWith(fontSize: 19, height: 1.15)),
          if (sub != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(sub!, textAlign: TextAlign.center, style: OliveText.body(context, color: p.ink3).copyWith(fontSize: 13.5)),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            OliveButton(actionLabel!, onPressed: onAction, kind: OliveButtonKind.tonal),
          ],
        ]),
      ),
    );
  }
}

/// Kit `K.errorState`: what went wrong in a sentence, that nothing was lost, and a way to retry.
/// [ErrorState.child] is picture only: a calm picture and a big round retry button with no words.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'That did not work',
    this.sub = 'Nothing was lost. Try again in a moment.',
    this.actionLabel = 'Try again',
    this.onAction,
    this.detail,
  })  : _childVariant = false, semanticLabel = null;

  /// Picture only. [semanticLabel] is for screen readers and is never drawn.
  const ErrorState.child({super.key, this.onAction, this.semanticLabel = 'Something went wrong. Tap to try again.'})
      : title = '', sub = null, actionLabel = null, detail = null, _childVariant = true;

  final String title;
  final String? sub;
  /// Null hides the button (kit `action:false`).
  final String? actionLabel;
  final VoidCallback? onAction;
  /// A short reference code for the grown-up (kit `detail`).
  final String? detail;
  final String? semanticLabel;
  final bool _childVariant;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    if (_childVariant) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const OliveSpot('envelope', size: 112, accentPlate: true),
            const SizedBox(height: 16),
            OlivePressable(
              onTap: onAction,
              semanticLabel: semanticLabel,
              borderRadius: 32,
              minWidth: 64,
              minHeight: 64,
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(color: p.priC, shape: BoxShape.circle),
                child: Center(child: OliveIcon(OliveIcons.refresh, size: 30, strokeWidth: 2, color: p.onPriC)),
              ),
            ),
          ]),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: p.badC, borderRadius: BorderRadius.circular(26)),
              child: Center(child: OliveIcon(OliveIcons.warn, size: 30, strokeWidth: 1.7, color: p.bad)),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: OliveText.head(context).copyWith(fontSize: 19, height: 1.15)),
            if (sub != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(sub!, textAlign: TextAlign.center, style: OliveText.body(context, color: p.ink3).copyWith(fontSize: 13.5)),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 14),
              OliveButton(actionLabel!, onPressed: onAction, kind: OliveButtonKind.tonal, icon: OliveIcons.refresh),
            ],
            if (detail != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(8)),
                child: Text(detail!, style: OliveText.mono(context, color: p.ink3, size: 11)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Kit skeleton kinds.
enum SkeletonKind { row, card, text, tile, hero }

/// Kit `K.skeleton`: placeholder shapes while something loads. Static on purpose: nothing moves by
/// itself (no shimmer), so there is nothing for reduced motion to remove.
class OliveSkeleton extends StatelessWidget {
  const OliveSkeleton(this.kind, {super.key, this.count = 1});

  final SkeletonKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    Widget bar(double frac, {double h = 12}) => FractionallySizedBox(
        widthFactor: frac, alignment: Alignment.centerLeft,
        child: Container(height: h, decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(8))));
    Widget one(int i) {
      switch (kind) {
        case SkeletonKind.card:
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(OliveRadius.r3), border: Border.all(color: p.line)),
            child: Column(children: [bar(0.4), const SizedBox(height: 10), bar(0.9), const SizedBox(height: 10), bar(0.7)]),
          );
        case SkeletonKind.text:
          return bar(const [0.9, 1.0, 0.6][i % 3]);
        case SkeletonKind.tile:
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(19)),
            child: Column(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: p.surface3, shape: BoxShape.circle)),
              const SizedBox(height: 10),
              bar(0.6),
            ]),
          );
        case SkeletonKind.hero:
          return Container(height: 138, decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(26)));
        case SkeletonKind.row:
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: p.surface3, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Column(children: [bar(0.6), const SizedBox(height: 8), bar(0.4)])),
            ]),
          );
      }
    }

    return Semantics(
      label: 'Loading',
      container: true,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (var i = 0; i < count; i++) ...[if (i > 0) const SizedBox(height: 10), one(i)]],
        ),
      ),
    );
  }
}

/// Kit `K.permission`: an in-context explanation card shown BEFORE the system permission dialog.
class PermissionPrompt extends StatelessWidget {
  const PermissionPrompt({
    super.key,
    required this.title,
    required this.body,
    this.icon = OliveIcons.camera,
    this.why = const [],
    this.allowLabel = 'Allow',
    this.denyLabel = 'Not now',
    this.onAllow,
    this.onDeny,
  });

  final String title;
  final String body;
  final String icon;
  final List<String> why;
  final String allowLabel;
  final String denyLabel;
  final VoidCallback? onAllow;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: OliveCard(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: p.priC, borderRadius: BorderRadius.circular(22)),
            child: Center(child: OliveIcon(icon, size: 28, strokeWidth: 1.8, color: p.onPriC)),
          ),
          const SizedBox(height: 8),
          Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: OliveText.head(context).copyWith(fontSize: 19))),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(body, textAlign: TextAlign.center, style: OliveText.body(context, color: p.ink2).copyWith(fontSize: 13.5)),
          ),
          if (why.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final w in why)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: OliveIcon(OliveIcons.check, size: 14, strokeWidth: 2.4, color: p.ok)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(w, style: OliveText.body(context, color: p.ink2).copyWith(fontSize: 13))),
                ]),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            OliveButton(denyLabel, onPressed: onDeny, kind: OliveButtonKind.ghost),
            OliveButton(allowLabel, onPressed: onAllow),
          ]),
        ]),
      ),
    );
  }
}
