// OLIVE BRANCH — first run, her gender. No longer UNVERIFIED — verified by
// CI (a Flutter toolchain runs for real in tools/verify.sh's automated
// pipeline — CHANGELOG v0.49.61). Onboarding & Guardian Access sub-project 1
// (docs/superpowers/specs/2026-09-12-onboarding-identity-pin-design.md).
// §8.5. Signal fix, Automatic First-Run Detection (docs/superpowers/specs/
// 2026-09-14-automatic-first-run-detection-design.md): a Skip now writes
// too — see LIVE WIRING below.
//
// Renders MARKUP screen 'obGender'. Mirrors onboarding_age.dart's structure
// exactly — the same ChildOnboardingScaffold/TapChoice shared chrome from
// onboarding_shared.dart, two tap options plus an explicit Skip, never a
// forced choice — but unlike every onboarding screen before it, EVERY real
// completion here is genuinely PERSISTED: this is the first route in the
// whole onboarding pipeline that any first-run screen's tapped answer has
// ever actually reached (db/migrations/0031_child_profile.sql's own header
// has the full account of that pre-existing gap).
//
// Gender is captured but drives NOTHING else in this codebase — nothing here
// is a score, a rank, or a streak (P2/§8.13 are not at stake: a bare,
// unscored, non-comparative fact, the same shape a favourite kind or a
// starred game already takes), and no guardian-facing read route exists for
// it in this pass (the design spec's own explicit scope boundary). MASTERFILE
// §8.5.0's ENTRY_CHOICE_GRANTS_NO_AUTHORITY concern does not apply here
// either — that is about routing real guardian authority off a child's
// self-reported signal, and nothing here grants or gates anything at all.
//
// LIVE WIRING (childId/baseUrl/sessionToken/httpClient, optional and
// additive): reused unchanged from ChildMoreScreen's own already-
// authenticated session, threaded through onboarding_flow.dart, the same
// established pattern letters_screen.dart already uses for a live screen
// reached through this exact chain. `_finish()` calls
// OliveApi.putChildGender() once and awaits it before advancing —
// UNCONDITIONALLY as of Automatic First-Run Detection, on a real tap AND on
// Skip, passing `null` for a Skip rather than skipping the call: an explicit
// NULL gender is now a real, meaningful "onboarding completed, gender
// declined" answer (a real row, a real `set_at`), not the fabricated state
// this file's own header used to warn against creating. This is the fix for
// the exact ambiguity that spec exists to close — `child_profile`'s mere
// row-absence was provably indistinguishable between "never opened the app"
// and "opened it, onboarded, and chose Skip." Still best-effort: a failed
// write is swallowed rather than shown, the same "nothing here may fail and
// no step may trap her" rule onboarding_logic.dart's own header states for
// every step in this flow — see `_finish()`'s own doc comment for what a
// failed write means for the new boot gate that now depends on it.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'onboarding_logic.dart';
import 'onboarding_shared.dart';

class ObGenderScreen extends StatefulWidget {
  const ObGenderScreen({
    super.key,
    required this.onContinue,
    this.childId = 'demo-child',
    this.baseUrl,
    this.sessionToken,
    this.httpClient,
  });

  final ValueChanged<GenderStep> onContinue;
  /// Live-session wiring, reused unchanged from ChildMoreScreen's own
  /// already-authenticated session (see file header) -- this screen reuses
  /// that already-authenticated session directly, the same established
  /// pattern letters_screen.dart already uses, rather than minting its own
  /// fresh devLoginFor() session.
  final String childId;
  final String? baseUrl;
  final String? sessionToken;
  final http.Client? httpClient;

  bool get _isLive => baseUrl != null && sessionToken != null;

  @override
  State<ObGenderScreen> createState() => _ObGenderScreenState();
}

class _ObGenderScreenState extends State<ObGenderScreen> {
  String? _tapped;
  bool _saving = false;

  /// The ONLY place this screen ever calls the network -- called
  /// UNCONDITIONALLY now (Automatic First-Run Detection, docs/superpowers/
  /// specs/2026-09-14-automatic-first-run-detection-design.md), on a real
  /// Boy/Girl tap AND on Skip: [step.selected] is `null` on Skip
  /// (acceptGender()'s own contract), and `putChildGender()` now accepts
  /// that `null` as a real, meaningful value -- "onboarding completed,
  /// gender declined" -- rather than something this screen must avoid
  /// sending. This is the fix for the exact ambiguity that spec exists to
  /// close: `child_profile`'s mere row-absence used to be indistinguishable
  /// between "never opened the app" and "opened it, onboarded, and chose
  /// Skip"; writing a real row (with a real `set_at`) on EVERY completion,
  /// not just a chosen gender, removes that ambiguity for good.
  Future<void> _finish(String? tapped) async {
    final step = acceptGender(tapped);
    if (widget._isLive) {
      setState(() => _saving = true);
      try {
        final OliveApi api = OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
        await api.putChildGender(widget.childId, step.selected);
        if (widget.httpClient == null) api.close();
      } catch (_) {
        // Best-effort -- see file header: a failed write here must never
        // trap her on this screen. Gender drives nothing downstream, so a
        // silent miss here costs nothing a retry (redo the welcome tour)
        // can't fix later. A failed write here also means `hasOnboarded`
        // stays false, so a boot-gated child simply sees this flow again
        // next launch -- never silently treated as onboarded when the row
        // genuinely never landed.
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    widget.onContinue(step);
  }

  @override
  Widget build(BuildContext context) {
    return ChildOnboardingScaffold(
      title: 'Are you a boy or a girl?',
      subtitle: "Tap one -- or skip it, if you'd rather not say.",
      continueEnabled: !_saving,
      onContinue: () => _finish(_tapped),
      onSkip: () => _finish(null),
      body: Wrap(
        spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
        children: [
          TapChoice(key: const ValueKey('gender_boy'), label: 'Boy',
            selected: _tapped == 'boy', minSide: 56,
            onTap: () => setState(() => _tapped = 'boy')),
          TapChoice(key: const ValueKey('gender_girl'), label: 'Girl',
            selected: _tapped == 'girl', minSide: 56,
            onTap: () => setState(() => _tapped = 'girl')),
        ],
      ),
    );
  }
}
