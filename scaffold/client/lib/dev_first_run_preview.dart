// OLIVE BRANCH — DEVELOPMENT BUILDS ONLY: open the grown-up's first run on a phone that is already set up, so the
// "Choose your PIN" step can be seen on a real device without wiping it. MASTERFILE §8.5.9.
//
// OFF BY DEFAULT. It is a compile-time flag, --dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true, passed only by
// tools/device-sync.sh and only when the developer sets OLIVE_DEV_FIRST_RUN_PREVIEW=1. A store or release cut never
// passes it, so [kDevGuardianFirstRunPreview] is the constant false and this whole screen is dropped from the build.
// tools/check-dev-first-run.mjs fails CI if any other file passes or names the define.
//
// WHAT IT DOES. It runs the REAL [GuardianOnboardingFlow] over an IN-MEMORY store: the questions, the PIN keypad, the
// confirmation, the warning and the mismatch handling are the real ones, but nothing is read from or written to this
// phone. The phone's real family, PIN and sign-in are never touched, and the PIN typed here is discarded when the
// app closes. Finishing shows a plain "preview finished" page and stops there: it never boots the real app.
import 'package:flutter/material.dart';

import 'device_role.dart';
import 'guardian_local_scope.dart';
import 'guardian_onboarding.dart';
import 'local_pin.dart' show kLocalPinIterations;
import 'theme.dart';
import 'theme_data.dart';

const bool kDevGuardianFirstRunPreview = bool.fromEnvironment('OLIVE_DEV_GUARDIAN_FIRST_RUN');

class DevGuardianFirstRunPreviewApp extends StatefulWidget {
  const DevGuardianFirstRunPreviewApp({super.key, this.services, this.role = DeviceRole.mom});

  /// Tests pass their own in-memory services; the app builds a fresh in-memory set.
  final GuardianLocalServices? services;
  final DeviceRole role;

  @override
  State<DevGuardianFirstRunPreviewApp> createState() => _DevGuardianFirstRunPreviewAppState();
}

class _DevGuardianFirstRunPreviewAppState extends State<DevGuardianFirstRunPreviewApp> {
  late final GuardianLocalServices _services =
      widget.services ?? GuardianLocalServices.memory(pinIterations: kLocalPinIterations);
  bool _finished = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Olive (first-run preview)',
        theme: buildThemeData(defaultAppTheme),
        home: _finished
            ? const Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Preview finished. Nothing was saved on this phone. '
                        'Install a build without the preview setting to use the app.',
                        key: Key('devFirstRunPreviewDone'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              )
            : GuardianOnboardingFlow(
                role: widget.role,
                services: _services,
                onFinished: (_) => setState(() => _finished = true),
              ),
      );
}
