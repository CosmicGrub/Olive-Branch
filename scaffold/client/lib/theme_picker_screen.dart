// OLIVE BRANCH — theme customization suite. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and
// run via `flutter analyze` / `flutter test` this session). MASTERFILE
// §8.1, `docs/superpowers/specs/2026-08-21-intuitivism-visual-foundation-
// design.md`.
//
// GUARDIAN-ONLY. Reached from guardian_more.dart's GuardianMoreScreen — this
// session's first real settings surface, and the reason it lives here
// rather than as a new top-level nav concept: guardian_more.dart is already
// the established "guardian sub-hub" the wiring pass hangs screens off of
// (see that file's own header). Nothing in this file is imported by
// child_home.dart or anything it reaches — §8.1's "no settings affordance
// exists at any depth" is a property of THAT file's own import graph, and
// this screen is not part of it. child_no_settings_test.dart proves that
// directly, mirroring transport.test.mjs's own "child shell has no settings
// affordance" contract check as a client-side Dart test too.
//
// SELECTING HAS NO SIDE EFFECT. Tapping a palette card or the light/dark
// toggle only updates this screen's own local `_pending` state and the
// preview area below it (a local `Theme` override, never the ambient app
// theme) — the same "browsing never mutates anything" posture
// game_picker.dart's own cards already have. Only the explicit "Apply"
// button writes anywhere: PUT .../theme (server/routes.mjs, guardian-write/
// child-read, real RLS) when this screen has been given a live session, and
// [onApplied] (an app-wide ThemeController update, when the caller has one
// in scope) either way. Without a live session, Apply gives the same honest
// "not connected in this preview build" feedback guardian_more.dart's own
// Availability tile already gives — never a screen pretending to have
// written somewhere it has not.
//
// A brief, real crossfade on a successful Apply is main_live.dart's own
// concern (`AnimatedTheme` wrapped around `MaterialApp.builder`) — §8.13
// permits user-initiated consequence motion; nothing here loops or moves on
// its own. No score, rank, or "you've tried N themes" tally of any kind —
// P2. This is a preference, not a game.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'form_factors.dart' as ff;
import 'theme.dart';

class ThemePickerScreen extends StatefulWidget {
  const ThemePickerScreen({
    super.key,
    this.initial = defaultAppTheme,
    this.baseUrl,
    this.guardianId,
    this.childId,
    this.httpClient,
    this.onApplied,
  });

  /// The best-known currently-active theme — preselects the pending
  /// selection and the preview. Defaults to [defaultAppTheme], the same
  /// fail-closed fallback main_live.dart's own bootstrap fetch uses, so a
  /// caller with no better answer yet still gets a real, valid starting
  /// point rather than a null check at every call site.
  final AppTheme initial;

  /// Live-session wiring, matching guardian_more.dart's own established
  /// shape for every other optionally-live tile (Availability, Court
  /// export): null in every offline-demo call site, real when threaded from
  /// an actual guardian session. Apply mints its OWN fresh dev-login here
  /// (AvailabilityScreen's own pattern), rather than requiring the caller to
  /// pre-build an [OliveApi].
  final String? baseUrl;
  final String? guardianId;
  final String? childId;

  /// Injectable for tests (package:http/testing.dart's MockClient) —
  /// matches AvailabilityScreen/GuardianMoreScreen's own field.
  final http.Client? httpClient;

  /// Called with the newly-applied [AppTheme] once a live Apply succeeds —
  /// how a caller that DOES have a real `ThemeController` in scope (e.g. a
  /// future live guardian tree rooted at the same `ThemeController`
  /// main_live.dart holds above `MaterialApp`) updates the real app-wide
  /// theme immediately, without this screen needing to know that type
  /// exists. Optional and additive: every existing/offline call site simply
  /// leaves it null, exactly the pattern guardian_more.dart's own
  /// [fetchAgreementOrder]/[registerPasskey] fields already use.
  final void Function(AppTheme)? onApplied;

  @override
  State<ThemePickerScreen> createState() => _ThemePickerScreenState();
}

class _ThemePickerScreenState extends State<ThemePickerScreen> {
  late AppTheme _pending = widget.initial;
  bool _applying = false;

  bool get _liveWired =>
      widget.baseUrl != null && widget.guardianId != null && widget.childId != null;

  void _selectPalette(ThemePalette palette) =>
      setState(() => _pending = _pending.copyWith(palette: palette));

  void _selectBrightness(ThemeBrightness brightness) =>
      setState(() => _pending = _pending.copyWith(brightness: brightness));

  Future<void> _apply() async {
    if (!_liveWired) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Theme changes need a live session — not connected in this preview build.'),
        duration: Duration(seconds: 3)));
      return;
    }
    setState(() => _applying = true);
    try {
      final token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      try {
        await api.putTheme(widget.childId!,
            themePalette: _pending.palette.name, themeBrightness: _pending.brightness.name);
      } finally {
        if (widget.httpClient == null) api.close();
      }
      widget.onApplied?.call(_pending);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Applied.'), duration: Duration(seconds: 2)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is ApiException ? "Couldn't save: ${e.error}" : "Couldn't save — try again."),
        duration: const Duration(seconds: 3)));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewScheme = colorSchemeFor(_pending);
    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // Same real §8.11.1 posture technique game_picker.dart/
          // court_export.dart already migrated onto — column COUNT adapts
          // by device; the color identity below does not (colorSchemeFor is
          // called with the SAME [_pending] regardless of viewport).
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final int cross = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Pick a look', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Preview it, then Apply — nothing changes until you do.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 128 * textScale.clamp(1.0, 2.0),
              ),
              children: [
                for (final palette in ThemePalette.values)
                  _PaletteCard(
                    palette: palette,
                    meta: themePaletteCatalogue[palette]!,
                    selected: palette == _pending.palette,
                    onTap: () => _selectPalette(palette),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Brightness', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ThemeBrightness>(
              key: const Key('brightnessToggle'),
              segments: const [
                ButtonSegment(
                    value: ThemeBrightness.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(
                    value: ThemeBrightness.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {_pending.brightness},
              onSelectionChanged: (s) => _selectBrightness(s.first),
            ),
            const SizedBox(height: 24),
            Text('Preview', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // A LOCAL Theme override, scoped to this preview card only —
            // never Theme.of(context) for the rest of this screen, and never
            // the ambient MaterialApp theme. Exactly the "preview the
            // PENDING selection... apply the candidate AppTheme to a preview
            // area... not the whole app" the spec calls for.
            Theme(
              key: const Key('themePreview'),
              data: ThemeData(colorScheme: previewScheme, useMaterial3: true),
              child: Builder(builder: (context) {
                final cs = Theme.of(context).colorScheme;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: cs.surface, borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant)),
                  child: Row(children: [
                    Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                        child: Icon(themePaletteCatalogue[_pending.palette]!.icon,
                            color: cs.onPrimary)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(themePaletteCatalogue[_pending.palette]!.title,
                          style: TextStyle(
                              color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                              backgroundColor: cs.primaryContainer,
                              foregroundColor: cs.onPrimaryContainer,
                              disabledBackgroundColor: cs.primaryContainer,
                              disabledForegroundColor: cs.onPrimaryContainer),
                          child: const Text('Sample button')),
                    ])),
                  ]),
                );
              }),
            ),
            const SizedBox(height: 28),
            SizedBox(
                height: 52,
                child: FilledButton(
                  key: const Key('applyThemeButton'),
                  onPressed: _applying ? null : _apply,
                  child: _applying
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Apply'),
                )),
          ]);
        }),
      ),
    );
  }
}

/// This screen's own small local copy of game_picker.dart's `_GameCard`
/// visual shape (icon/swatch, title, one-line description, press-in
/// consequence motion) — Dart library privacy is per-file, so `_GameCard`
/// itself is unreachable here, the same reason game_draw_together.dart
/// already keeps its own small copies of `doodle_desk.dart`'s private
/// painter/swatch shapes rather than reaching into that file's privates.
/// Adapted for single-select (a `selected` outline/check) rather than
/// game_picker.dart's plain tap-to-play.
class _PaletteCard extends StatefulWidget {
  const _PaletteCard(
      {required this.palette, required this.meta, required this.selected, required this.onTap});
  final ThemePalette palette;
  final ThemePaletteMeta meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PaletteCard> createState() => _PaletteCardState();
}

class _PaletteCardState extends State<_PaletteCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cardScheme = colorSchemeFor(AppTheme(palette: widget.palette, brightness: ThemeBrightness.light));
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${widget.meta.title}. ${widget.meta.blurb}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        // Consequence motion only, same 120ms budget as game_picker.dart's
        // own card — driven entirely by the tap, never a loop (§8.13).
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64), // §8.4 touch target
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: widget.selected ? cs.primary : Colors.transparent, width: 3),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(widget.meta.icon, size: 26, color: cardScheme.onPrimaryContainer),
                const Spacer(),
                if (widget.selected)
                  Icon(Icons.check_circle, size: 20, color: cs.primary),
              ]),
              const Spacer(),
              Text(widget.meta.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: cardScheme.onPrimaryContainer)),
              const SizedBox(height: 4),
              Text(widget.meta.blurb,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: cardScheme.onPrimaryContainer)),
            ]),
          ),
        ),
      ),
    );
  }
}
