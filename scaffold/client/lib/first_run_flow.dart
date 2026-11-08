// OLIVE BRANCH — the child build's first run with "Connect this device" LAST.
// No longer UNVERIFIED — verified by CI (client/test/first_run_flow_test.dart).
// MASTERFILE §8.5.6.
//
// Owner request, 2026-11-08: "make the Connect this device field the final
// step of the onboarding process." A device with no stored identity used to
// open on the pairing screen. It now opens on the welcome questions and ends
// on the connect step:
//
//   questions (offline, onboarding_flow.dart)  ->  saved to the local draft
//     ->  Connect this device (pairing_redeem_screen.dart, closingStep)
//     ->  [caller] store the identity, upload the draft, open her home.
//
// Everything before the connect step runs with NO network and NO session: the
// answers go to [OnboardingDraftRepository] (a LocalStore namespace under the
// 'pending-device' owner in the app; in memory in tests). The draft is saved
// the moment the questions are done, so a restart resumes at the connect step,
// not the beginning (only a quit in the middle of the questions starts those
// again). Skipping is allowed on every question. The connect step cannot be
// skipped, because a device cannot run live without an identity; "Not now"
// goes to a calm waiting screen that keeps the draft and offers the code
// again. A failed draft write never traps her: the answers are held for this
// run and she still reaches the connect step.
//
// This widget is deliberately a plain Navigator-free state switch (stage),
// never a place that touches storage for the identity or the network for the
// upload: [onRedeemed] is the caller's (main_live.dart), as with
// PairingRedeemScreen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'access_settings.dart' show kChildTarget;
import 'onboarding_draft.dart';
import 'onboarding_flow.dart';
import 'onboarding_shared.dart' show ChildOnboardingScaffold;
import 'pairing_redeem_screen.dart';

enum FirstRunStage { loading, questions, connect, waiting }

class FirstRunFlow extends StatefulWidget {
  const FirstRunFlow({
    super.key,
    required this.baseUrl,
    required this.draftRepository,
    required this.onRedeemed,
    this.httpClient,
  });

  final String baseUrl;
  final OnboardingDraftRepository draftRepository;
  final void Function(Map<String, dynamic> result) onRedeemed;
  final http.Client? httpClient;

  @override
  State<FirstRunFlow> createState() => _FirstRunFlowState();
}

class _FirstRunFlowState extends State<FirstRunFlow> {
  FirstRunStage _stage = FirstRunStage.loading;

  @override
  void initState() {
    super.initState();
    unawaited(_resume());
  }

  /// A finished draft means the questions are done: go straight to the last
  /// step. An unreadable store is treated as "nothing saved" -- she answers
  /// again rather than being stuck.
  Future<void> _resume() async {
    OnboardingDraft? draft;
    try {
      draft = await widget.draftRepository.load();
    } catch (_) {
      draft = null;
    }
    if (!mounted) return;
    setState(() => _stage = (draft != null && draft.complete)
        ? FirstRunStage.connect
        : FirstRunStage.questions);
  }

  Future<void> _questionsDone(OnboardingDraft draft) async {
    try {
      await widget.draftRepository.save(draft);
    } catch (_) {
      // Held for this run only; the store being full or unreadable must not
      // stop her reaching the last step. (She would answer again after a
      // restart, which is the honest cost.)
    }
  }

  @override
  Widget build(BuildContext context) => switch (_stage) {
    FirstRunStage.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
    FirstRunStage.questions => OnboardingFlowScreen(
        // No grown-up is known yet and no child id exists: no 'Ivy', no 'Dad',
        // no 'demo-child' in a live build.
        fallbackName: '',
        childId: kPendingDeviceScope,
        includeWho: false,
        introLine: "Let's get to know each other. A few quick questions, then "
            'one last step to connect this device with a grown-up.',
        onDraft: _questionsDone,
        onComplete: () async {
          if (mounted) setState(() => _stage = FirstRunStage.connect);
        },
      ),
    FirstRunStage.connect => PairingRedeemScreen(
        baseUrl: widget.baseUrl,
        role: 'child',
        httpClient: widget.httpClient,
        closingStep: true,
        onRedeemed: widget.onRedeemed,
        onNotNow: () => setState(() => _stage = FirstRunStage.waiting),
      ),
    FirstRunStage.waiting => _WaitingScreen(
        onConnect: () => setState(() => _stage = FirstRunStage.connect)),
  };
}

/// The calm place "Not now" goes. Nothing is lost, nothing is counting.
class _WaitingScreen extends StatelessWidget {
  const _WaitingScreen({required this.onConnect});
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChildOnboardingScaffold(
      title: 'Waiting for a grown-up',
      subtitle: 'Your answers are safe here. When a grown-up is ready, we can '
          'connect this device.',
      showContinueButton: false,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          label: 'Waiting for a grown-up',
          excludeSemantics: true,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.escalator_warning_rounded, size: 84, color: scheme.primary),
            const SizedBox(width: 16),
            Icon(Icons.hourglass_empty_rounded, size: 56, color: scheme.onSurfaceVariant),
          ]),
        ),
        const SizedBox(height: 32),
        SizedBox(height: kChildTarget, child: FilledButton(
          key: const Key('firstRunConnectAgain'),
          onPressed: onConnect,
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16))),
          child: const Text('Connect now',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
      ]),
    );
  }
}
