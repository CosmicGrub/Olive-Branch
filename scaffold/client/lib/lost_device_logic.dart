// OLIVE BRANCH — the logic of a lost or stolen phone or tablet, with no screens. UNVERIFIED on a device; pure Dart,
// runs headless in CI (client/test/lost_device_logic_test.dart).
//
// THREE JOBS.
//  1. [FamilyDeviceView]: one row of "Phones and tablets" as the server describes it, and what a grown-up may do with it.
//  2. [LostDeviceActions]: the five things a grown-up can say (mark as lost, I have it, it is lost, erase it, call the
//     erase off), each behind their own PIN. The real one talks to the family's server; tests use a fake.
//  3. [LostPhoneCoordinator]: what a LOST grown-up phone does when it hears what happened to it. It never deletes by
//     itself: being marked or cut off only locks the app and stops anything new. Only an ERASE its owner ordered (and
//     the family's server held for 24 hours, and the phone's own credential proved) wipes the app's copy on that phone,
//     and then says so. Nothing is ever erased from a CHILD'S tablet, and a child's tablet never runs any of this.
//
// WHAT "ERASE" IS NOT. It is not a way to reach into a phone and take things from it, to look at it, or to find it:
// the phone does it to itself, on its own next contact, from a signed word it already trusts, and no place or network
// name is ever asked for or sent. Every record stays with the family (the server, the other phones, the backup).
import 'api_client.dart';
import 'device_standing.dart';
import 'lost_device_words.dart';

/// One phone or tablet of the family, as the server sent it. Never a credential, never a place.
class FamilyDeviceView {
  const FamilyDeviceView({
    required this.id,
    required this.isChild,
    required this.label,
    required this.ownerName,
    required this.isThisDevice,
    required this.isOwn,
    required this.state,
    required this.pausedAt,
    required this.revokeDueAt,
    required this.incidentId,
    required this.markedByName,
    required this.markedByMe,
    required this.canMarkLost,
    required this.canFound,
    required this.canConfirmLost,
    required this.eraseOrdered,
    required this.eraseDueAt,
    required this.erased,
    required this.canOrderErase,
    required this.canCancelErase,
  });

  final String id, label, state;
  final bool isChild, isThisDevice, isOwn, markedByMe;
  final String? ownerName, markedByName, incidentId;
  final DateTime? pausedAt, revokeDueAt, eraseDueAt;
  final bool canMarkLost, canFound, canConfirmLost, eraseOrdered, erased, canOrderErase, canCancelErase;

  bool get isPaused => state == 'paused';
  bool get isRevoked => state == 'revoked';

  /// A row the server sent that is not shaped as expected is dropped, never half-shown.
  static FamilyDeviceView? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'], role = raw['role'], state = raw['state'];
    if (id is! String || id.isEmpty || role is! String || state is! String) return null;
    if (state != 'active' && state != 'paused' && state != 'revoked') return null;
    bool b(String k) => raw[k] == true;
    String? str(String k) => raw[k] is String && (raw[k] as String).isNotEmpty ? raw[k] as String : null;
    DateTime? at(String k) => str(k) == null ? null : DateTime.tryParse(str(k)!)?.toLocal();
    return FamilyDeviceView(
      id: id,
      isChild: role == 'child',
      label: str('label') ?? '',
      ownerName: str('ownerName'),
      isThisDevice: b('isThisDevice'),
      isOwn: b('isOwn'),
      state: state,
      pausedAt: at('pausedAt'),
      revokeDueAt: at('revokeDueAt'),
      incidentId: str('incidentId'),
      markedByName: str('markedByName'),
      markedByMe: b('markedByMe'),
      canMarkLost: b('canMarkLost'),
      canFound: b('canFound'),
      canConfirmLost: b('canConfirmLost'),
      eraseOrdered: b('eraseOrdered'),
      eraseDueAt: at('eraseDueAt'),
      erased: b('erased'),
      canOrderErase: b('canOrderErase') && role != 'child', // a tablet is never offered the erase, whatever was sent
      canCancelErase: b('canCancelErase') && role != 'child',
    );
  }

  static List<FamilyDeviceView> listFromJson(Object? raw) {
    if (raw is! Map || raw['devices'] is! List) return const <FamilyDeviceView>[];
    return <FamilyDeviceView>[
      for (final Object? d in raw['devices'] as List)
        if (FamilyDeviceView.fromJson(d) != null) FamilyDeviceView.fromJson(d)!,
    ];
  }

  /// The plain name for this row, with a tablet named for her only by the first name a grown-up gave it.
  String displayName({String? childName}) => LostDeviceWords.deviceName(
      isChild: isChild, ownerName: ownerName, childName: childName, isThisDevice: isThisDevice);
}

/// The result of one of the five things a grown-up can say: either it worked, or a plain refusal.
class LostActionResult {
  const LostActionResult.ok({this.incidentId, this.eraseOrdered}) : error = null;
  const LostActionResult.refused(this.error)
      : incidentId = null,
        eraseOrdered = null;
  final String? error, incidentId;
  final bool? eraseOrdered;
  bool get ok => error == null;
}

abstract class LostDeviceActions {
  Future<List<FamilyDeviceView>> load();
  Future<LostActionResult> mark(String deviceId, String pin);
  Future<LostActionResult> found(String deviceId, String incidentId, String pin);
  Future<LostActionResult> confirmLost(String deviceId, String incidentId, String pin);
  Future<LostActionResult> orderErase(String deviceId, String incidentId, String pin);
  Future<LostActionResult> cancelErase(String deviceId, String incidentId, String pin);
}

/// The real thing: the family's server, through the process's own signed-in session.
class ApiLostDeviceActions implements LostDeviceActions {
  ApiLostDeviceActions(this.apiFor);

  /// Gives a fresh [OliveApi] and is closed by this class after each call (the one the app already builds per call).
  final Future<OliveApi> Function() apiFor;

  Future<T> _with<T>(Future<T> Function(OliveApi api) body) async {
    final OliveApi api = await apiFor();
    try {
      return await body(api);
    } finally {
      api.close();
    }
  }

  Future<LostActionResult> _run(Future<Map<String, dynamic>> Function(OliveApi api) call) async {
    try {
      final Map<String, dynamic> r = await _with(call);
      return LostActionResult.ok(incidentId: r['incidentId'] as String?, eraseOrdered: r['eraseOrdered'] as bool?);
    } on ApiException catch (e) {
      return LostActionResult.refused(e.error);
    }
  }

  @override
  Future<List<FamilyDeviceView>> load() => _with((OliveApi api) async => FamilyDeviceView.listFromJson(await api.fetchFamilyDevices()));

  @override
  Future<LostActionResult> mark(String id, String pin) => _run((OliveApi a) => a.markDeviceLost(id, pin));

  @override
  Future<LostActionResult> found(String id, String inc, String pin) => _run((OliveApi a) => a.deviceFound(id, inc, pin));

  @override
  Future<LostActionResult> confirmLost(String id, String inc, String pin) =>
      _run((OliveApi a) => a.confirmDeviceLost(id, inc, pin));

  @override
  Future<LostActionResult> orderErase(String id, String inc, String pin) =>
      _run((OliveApi a) => a.orderDeviceErase(id, inc, pin));

  @override
  Future<LostActionResult> cancelErase(String id, String inc, String pin) =>
      _run((OliveApi a) => a.cancelDeviceErase(id, inc, pin));
}

/// What a lost grown-up phone does when the family's server tells it the erase word. Every part is injected so the
/// whole thing runs in a test: the real app passes [LocalServices.wipeAll], [AuthSession.sayErased] and the secure
/// identity store.
class LostPhoneCoordinator {
  LostPhoneCoordinator({
    required this.wipeLocal,
    required this.tellServer,
    required this.clearIdentity,
    this.attempts = 3,
  });

  /// Erases the app's copy of the family on THIS phone (its sealed store and the key that opens it).
  final Future<void> Function() wipeLocal;

  /// POST /v1/auth/session/erased; true when the server took it. Never throws.
  final Future<bool> Function(String deviceId, String credential) tellServer;

  /// Forgets the phone's own sign-in once the server knows (so it does not try again).
  final Future<void> Function() clearIdentity;
  final int attempts;

  bool _running = false;

  /// True when this run erased the phone. Safe to call twice at once (the second call does nothing).
  Future<bool> erase(String deviceId, String credential) async {
    if (_running || DeviceStanding.value == DeviceStandingState.erased) return false;
    _running = true;
    try {
      await wipeLocal();
      // The word is kept AFTER the wipe (in the fresh, empty store), so a phone that restarts before it could tell the
      // server still knows it is erased and tries again ([retryTelling]).
      DeviceStanding.set(DeviceStandingState.erased);
      await _tell(deviceId, credential);
      return true;
    } finally {
      _running = false;
    }
  }

  Future<void> _tell(String deviceId, String credential) async {
    for (int i = 0; i < attempts; i++) {
      if (await tellServer(deviceId, credential)) {
        await clearIdentity();
        return;
      }
    }
  }

  /// The server said the erase word. A phone that has not erased yet erases; one that already did (and could not tell
  /// the server) just tries to tell it again.
  Future<void> heardErase(String deviceId, String credential) async {
    if (DeviceStanding.value == DeviceStandingState.erased) {
      await retryTelling(deviceId, credential);
    } else {
      await erase(deviceId, credential);
    }
  }

  /// At the next start of an erased phone that could not reach the server the first time.
  Future<void> retryTelling(String? deviceId, String? credential) async {
    if (DeviceStanding.value != DeviceStandingState.erased || deviceId == null || credential == null) return;
    await _tell(deviceId, credential);
  }
}
