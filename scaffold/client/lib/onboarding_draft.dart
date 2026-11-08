// OLIVE BRANCH — the welcome-tour draft: answers given BEFORE this device is
// connected to a family. No longer UNVERIFIED — verified by CI
// (client/test/onboarding_draft_test.dart, first_run_flow_test.dart).
//
// The owner's order for the child build (2026-11-08) is: the welcome
// questions first, then "Connect this device" as the LAST step. A device with
// no identity has no session, so every answer is collected into this local
// draft and sent only after pairing succeeds.
//
// Three small pieces, in the repository pattern of her_colour_store.dart /
// local_repositories.dart:
//
//  1. [OnboardingDraft], the answers, and what they are NOT: nothing here is a
//     score, a count or a rank (P2); the one bit [complete] only says the
//     questions are finished so a restart resumes at the connect step.
//  2. [OnboardingDraftRepository]: abstract; [MemoryOnboardingDraftRepository]
//     for tests; [LocalOnboardingDraftRepository] over one LocalStore
//     namespace (`child.pending-device.onboarding`, [kPendingDeviceScope]).
//     A not-yet-paired device has no child id, so it never uses the literal
//     'demo-child' (a live build refuses that scope).
//  3. [syncOnboardingDraft] and [DraftRetry]: send the draft through the new
//     authenticated session, clear it only once the server has it (or already
//     had a profile), and otherwise KEEP it and retry with backoff. Never
//     throws; never carries error text; never loses answers.
//
// What the server can take today: the child-session route PUT .../profile
// takes the gender (or an explicit null for "declined"), and that same write
// is what flips `hasOnboarded` (§8.5.5). Name, age, colour and birthday have
// no child-session route; they have never been sent anywhere, and still are
// not. They stay in the draft until it is cleared (see MASTERFILE §8.5.6).
import 'dart:async';

import 'local_store.dart';

/// The owner id of the draft's namespace: `child.pending-device.onboarding`.
const String kPendingDeviceScope = 'pending-device';

class OnboardingDraft {
  const OnboardingDraft({
    this.name,
    this.age,
    this.gender,
    this.colourId,
    this.birthdayMonth,
    this.birthdayDay,
    this.complete = false,
  });

  /// Exactly what she typed; null when she skipped the step.
  final String? name;
  /// What she tapped (never authoritative; §8.5.2); null when skipped.
  final int? age;
  /// 'boy' | 'girl' | null (skipped). This is the one answer the server takes.
  final String? gender;
  final String? colourId;
  final int? birthdayMonth;
  final int? birthdayDay;
  /// True once every question has been walked (each may have been skipped).
  final bool complete;

  Map<String, Object?> toJson() => <String, Object?>{
        if (name != null) 'name': name,
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        if (colourId != null) 'colourId': colourId,
        if (birthdayMonth != null) 'birthdayMonth': birthdayMonth,
        if (birthdayDay != null) 'birthdayDay': birthdayDay,
        'complete': complete,
      };

  /// Fail-closed decode: a field of the wrong type is dropped, never trusted.
  static OnboardingDraft fromJson(Map<String, Object?> m) => OnboardingDraft(
        name: m['name'] is String ? m['name'] as String : null,
        age: m['age'] is int ? m['age'] as int : null,
        gender: (m['gender'] == 'boy' || m['gender'] == 'girl') ? m['gender'] as String : null,
        colourId: m['colourId'] is String ? m['colourId'] as String : null,
        birthdayMonth: m['birthdayMonth'] is int ? m['birthdayMonth'] as int : null,
        birthdayDay: m['birthdayDay'] is int ? m['birthdayDay'] as int : null,
        complete: m['complete'] == true,
      );
}

abstract class OnboardingDraftRepository {
  Future<OnboardingDraft?> load();
  Future<void> save(OnboardingDraft draft);
  Future<void> clear();
}

class MemoryOnboardingDraftRepository implements OnboardingDraftRepository {
  MemoryOnboardingDraftRepository([this._draft]);
  OnboardingDraft? _draft;
  @override
  Future<OnboardingDraft?> load() async => _draft;
  @override
  Future<void> save(OnboardingDraft draft) async => _draft = draft;
  @override
  Future<void> clear() async => _draft = null;
}

class LocalOnboardingDraftRepository implements OnboardingDraftRepository {
  LocalOnboardingDraftRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'draft';

  @override
  Future<OnboardingDraft?> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return null;
    return OnboardingDraft.fromJson(Map<String, Object?>.from(raw));
  }

  @override
  Future<void> save(OnboardingDraft draft) => _ns.put(_key, draft.toJson());

  @override
  Future<void> clear() => _ns.delete(_key);
}

/// What one attempt to deliver the draft came to.
enum DraftSyncOutcome {
  /// No finished draft is waiting.
  nothingPending,
  /// The server took the answers; the draft is cleared.
  uploaded,
  /// The server already had a profile for this child (a re-paired tablet): its
  /// answers win, the draft is discarded and nothing is overwritten.
  serverWon,
  /// Offline or a server error. The draft is kept untouched; try again later.
  deferred,
}

/// One attempt. [fetchHasOnboarded] is the server's answer (GET /v1/me) and
/// [putGender] the profile write; either may throw. Never throws itself.
Future<DraftSyncOutcome> syncOnboardingDraft({
  required OnboardingDraftRepository repo,
  required Future<bool> Function() fetchHasOnboarded,
  required Future<void> Function(String? gender) putGender,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final OnboardingDraft? draft;
  try {
    draft = await repo.load();
  } catch (_) {
    return DraftSyncOutcome.deferred; // unreadable now: leave it where it is
  }
  if (draft == null || !draft.complete) return DraftSyncOutcome.nothingPending;
  final String? gender = draft.gender;
  try {
    final DraftSyncOutcome result = await () async {
      // Ask first: if the server already has a profile it wins, untouched.
      if (await fetchHasOnboarded()) return DraftSyncOutcome.serverWon;
      await putGender(gender);
      return DraftSyncOutcome.uploaded;
    }()
        .timeout(timeout);
    try {
      await repo.clear();
    } catch (_) {
      // Sent but not cleared: the next attempt finds hasOnboarded true and
      // clears it then. Nothing is lost either way.
    }
    return result;
  } catch (_) {
    return DraftSyncOutcome.deferred;
  }
}

/// Retry with backoff after a deferred attempt, for as long as the app runs.
/// Pure of Flutter: the wait is injectable so tests run instantly.
class DraftRetry {
  DraftRetry({
    required this.attempt,
    this.delays = const <Duration>[
      Duration(seconds: 15),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(minutes: 30),
    ],
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? ((Duration d) => Future<void>.delayed(d));

  final Future<DraftSyncOutcome> Function() attempt;
  final List<Duration> delays;
  final Future<void> Function(Duration) _wait;
  bool _stopped = false;
  int attempts = 0;

  void stop() => _stopped = true;

  /// Runs until the draft is delivered, discarded, or the delays run out (the
  /// next launch starts a fresh run, so a long-offline device still delivers).
  Future<DraftSyncOutcome> run() async {
    DraftSyncOutcome last = DraftSyncOutcome.deferred;
    for (final Duration d in delays) {
      if (_stopped) return last;
      await _wait(d);
      if (_stopped) return last;
      attempts++;
      last = await attempt();
      if (last != DraftSyncOutcome.deferred) return last;
    }
    return last;
  }
}

/// The boot step after a successful pairing: deliver whatever the questions
/// left behind, exactly once, and never block her home on it.
///
/// [attempt] is one [syncOnboardingDraft] try. [onDelivered] runs when the
/// server has the answers or already had its own (the caller remembers on the
/// device that the tour is done). When the first try is
/// [DraftSyncOutcome.deferred], a [DraftRetry] is started in the background and
/// returned as `retrying` (production ignores it; tests await it). `first` is
/// the first try's outcome: anything but [DraftSyncOutcome.nothingPending]
/// means a draft existed, so the welcome tour must NOT run again.
Future<({DraftSyncOutcome first, Future<DraftSyncOutcome>? retrying})> deliverPendingDraft({
  required Future<DraftSyncOutcome> Function() attempt,
  required Future<void> Function() onDelivered,
  List<Duration>? retryDelays,
  Future<void> Function(Duration)? wait,
}) async {
  Future<DraftSyncOutcome> one() async {
    final DraftSyncOutcome o = await attempt();
    if (o == DraftSyncOutcome.uploaded || o == DraftSyncOutcome.serverWon) {
      try {
        await onDelivered();
      } catch (_) {
        // Best effort: the next launch asks the server and learns the same.
      }
    }
    return o;
  }

  final DraftSyncOutcome first = await one();
  Future<DraftSyncOutcome>? retrying;
  if (first == DraftSyncOutcome.deferred) {
    final DraftRetry r = retryDelays == null
        ? DraftRetry(attempt: one, wait: wait)
        : DraftRetry(attempt: one, delays: retryDelays, wait: wait);
    retrying = r.run();
  }
  return (first: first, retrying: retrying);
}
