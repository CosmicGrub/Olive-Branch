// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_test.dart).
// OLIVE BRANCH — layers above the page.
//
//   OliveBottomSheet <- kit `K.bottomSheet(o)` (title, body, actions, `detent: half|full`, close)
//   OliveDialog      <- kit `K.modal(o)` (icon plate, title, body, one or two actions, tone)
//
// Each is a widget (so the gallery and tests can render it in place) with a `show` helper that puts it
// on a route with the kit's scrim and entrance. Entrances use [OliveTiming] so reduced motion shows
// the layer instantly. Both keep focus inside, close on back, and name themselves to screen readers.
//
// Replaces (adoption wave): ad-hoc showModalBottomSheet / AlertDialog calls.
import 'package:flutter/material.dart';

import 'olive_art.dart';
import 'olive_base.dart';
import 'olive_palette.dart';

/// The kit's scrim: `rgba(6,12,8,.48)`.
Color _scrim() => Colors.black.withValues(alpha: 0.48);

/// Half-height or nearly full-height sheet.
enum SheetDetent { half, full }

/// Kit `K.bottomSheet`. Render it directly, or call [OliveBottomSheet.show].
class OliveBottomSheet extends StatelessWidget {
  const OliveBottomSheet({
    super.key,
    this.title,
    required this.child,
    this.actions = const [],
    this.detent = SheetDetent.half,
    this.onClose,
  });

  final String? title;
  final Widget child;
  /// Buttons laid out in a row of equal widths (wraps to a column at large text).
  final List<Widget> actions;
  final SheetDetent detent;
  /// Shows a close button in the header when set.
  final VoidCallback? onClose;

  /// Presents a sheet. [builder] receives the sheet's own context so content can pop it.
  static Future<T?> show<T>(
    BuildContext context, {
    String? title,
    required WidgetBuilder builder,
    List<Widget> actions = const [],
    SheetDetent detent = SheetDetent.half,
    bool showClose = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _scrim(),
      useSafeArea: true,
      sheetAnimationStyle: AnimationStyle(
        duration: OliveTiming.slow(context),
        reverseDuration: OliveTiming.base(context),
        curve: OliveTiming.spring,
      ),
      builder: (ctx) => OliveBottomSheet(
        title: title,
        detent: detent,
        actions: actions,
        onClose: showClose ? () => Navigator.of(ctx).maybePop() : null,
        child: builder(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final h = MediaQuery.sizeOf(context).height;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Semantics(
        scopesRoute: true,
        namesRoute: title != null,
        label: title,
        explicitChildNodes: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: detent == SheetDetent.full ? h - 34 : h * 0.9),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(OliveRadius.r4)),
              border: Border(top: BorderSide(color: p.line)),
              boxShadow: p.shadow(3),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 38, height: 5,
                      decoration: BoxDecoration(color: p.edge.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(5)),
                    ),
                  ),
                  if (title != null || onClose != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: title == null
                            ? const SizedBox.shrink()
                            : Semantics(header: true, child: Text(title!, style: OliveText.title(context).copyWith(fontSize: 20, height: 1.1))),
                      ),
                      if (onClose != null) OliveIconButton(OliveIcons.x, label: 'Close', small: true, iconSize: 16, onPressed: onClose),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  Flexible(child: SingleChildScrollView(child: child)),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final a in actions) a]),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kit `K.modal`: a centred dialog. Keep it to one decision: a title, a sentence, and one or two
/// buttons. [tone] bad / warn / ok tints the icon plate.
class OliveDialog extends StatelessWidget {
  const OliveDialog({
    super.key,
    required this.title,
    this.body,
    this.icon,
    this.tone = OliveTone.pri,
    this.actions = const [],
    this.stackActions = false,
  });

  final String title;
  final String? body;
  final String? icon;
  final OliveTone tone;
  final List<Widget> actions;
  /// Lay the actions in a column instead of a row.
  final bool stackActions;

  /// Presents a dialog and returns what the buttons pop with.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? body,
    String? icon,
    OliveTone tone = OliveTone.pri,
    required List<Widget> Function(BuildContext dialogContext) actions,
    bool stackActions = false,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: _scrim(),
      animationStyle: AnimationStyle(
        duration: OliveTiming.slow(context),
        reverseDuration: OliveTiming.base(context),
        curve: OliveTiming.spring,
      ),
      builder: (ctx) => OliveDialog(
        title: title,
        body: body,
        icon: icon,
        tone: tone,
        stackActions: stackActions,
        actions: actions(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final audience = OliveAudienceScope.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: title,
        explicitChildNodes: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(OliveRadius.r4),
              border: Border.all(color: p.line),
              boxShadow: p.shadow(3),
            ),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
                if (icon != null) ...[
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(color: p.toneBg(tone), borderRadius: BorderRadius.circular(20)),
                    child: Center(child: OliveIcon(icon!, size: 26, strokeWidth: 1.8, color: p.toneFg(tone))),
                  ),
                  const SizedBox(height: 8),
                ],
                Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: OliveText.title(context).copyWith(fontSize: 20, height: 1.15))),
                if (body != null) ...[
                  const SizedBox(height: 8),
                  Text(body!, textAlign: TextAlign.center, style: OliveText.body(context, color: p.ink2).copyWith(fontSize: 14, height: 1.42)),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  if (stackActions || audience == OliveAudience.child)
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: 8), actions[i]],
                    ])
                  else
                    Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
