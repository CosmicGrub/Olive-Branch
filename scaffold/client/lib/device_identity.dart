// OLIVE BRANCH — device pairing & provisioning: on-device identity storage.
// UNVERIFIED (no Flutter toolchain in tools/verify.sh's automated pipeline —
// manually built and run via `flutter analyze`/`flutter test` this session,
// same posture every other Dart file in this client carries until a real
// device confirms it). docs/superpowers/specs/2026-09-12-device-pairing
// -provisioning-design.md.
//
// This is the FIRST on-device persistence this app has ever needed --
// main.dart's own header line the design spec quotes directly: "this app has
// zero SharedPreferences (or any storage) usage anywhere." What's stored here
// is a real bearer credential (`sessionToken`) plus the identity it was
// minted for, so `flutter_secure_storage` (Keystore/Keychain-backed) is the
// right tool, not plaintext SharedPreferences.
//
// `SecureKeyValueStore` is a thin seam over the real plugin, not a design
// this file needed for its own sake -- it exists purely so
// pairing_redeem_screen_test.dart / add_device_screen_test.dart /
// paired_devices_list_test.dart can inject an in-memory fake rather than
// hitting a real platform channel `flutter test` has no host implementation
// for, the identical role [http.Client] injection already plays for every
// live screen's own network calls in this codebase.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The real, on-device implementation. `FlutterSecureStorage()` itself is
/// stateless/cheap to construct (it just holds channel method names), so a
/// fresh instance per call is fine -- matches this codebase's own
/// devLoginFor()-per-call posture of not caching something stateful for
/// longer than it needs to live.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// `{sessionToken, deviceId, role, targetId}` -- exactly the design spec's
/// own Flow section wire shape ("stores {sessionToken, deviceId, role,
/// targetId} via flutter_secure_storage").
class DeviceIdentity {
  const DeviceIdentity({
    required this.sessionToken,
    required this.deviceId,
    required this.role,
    required this.targetId,
  });

  final String sessionToken;
  final String deviceId;
  /// 'child' or 'guardian' -- which binary this identity is for. Always
  /// matches the build it was redeemed on (redeemDevicePairingCode()'s own
  /// [role] argument is compiled in, never user-editable — see
  /// pairing_redeem_screen.dart).
  final String role;
  /// The child.id (role == 'child') or app_user.id (role == 'guardian')
  /// this device's sessions are bound to.
  final String targetId;
}

class DeviceIdentityStore {
  DeviceIdentityStore({SecureKeyValueStore? storage})
      : _storage = storage ?? const FlutterSecureKeyValueStore();

  final SecureKeyValueStore _storage;

  static const _kSessionToken = 'olive_paired_device_session_token';
  static const _kDeviceId = 'olive_paired_device_id';
  static const _kRole = 'olive_paired_device_role';
  static const _kTargetId = 'olive_paired_device_target_id';

  Future<void> save(DeviceIdentity identity) async {
    await _storage.write(_kSessionToken, identity.sessionToken);
    await _storage.write(_kDeviceId, identity.deviceId);
    await _storage.write(_kRole, identity.role);
    await _storage.write(_kTargetId, identity.targetId);
  }

  /// An honest absence (no identity ever paired, or storage was cleared) is
  /// `null` -- never a fabricated default identity. A PARTIAL write (only
  /// some of the four keys present -- should never happen since [save]
  /// writes all four, but a prior version's storage format changing, or an
  /// interrupted write, is a real possibility a loader must not paper over)
  /// is also treated as "no identity", not pieced together from whatever
  /// happens to be there.
  Future<DeviceIdentity?> load() async {
    final token = await _storage.read(_kSessionToken);
    final deviceId = await _storage.read(_kDeviceId);
    final role = await _storage.read(_kRole);
    final targetId = await _storage.read(_kTargetId);
    if (token == null || deviceId == null || role == null || targetId == null) return null;
    return DeviceIdentity(sessionToken: token, deviceId: deviceId, role: role, targetId: targetId);
  }

  /// Called on a real `device_revoked` response (api_client.dart's
  /// [DeviceRevokedException]) and from add_device_screen.dart's own
  /// Cancel-before-use path is NOT this -- cancelling an unredeemed CODE
  /// never touches a stored identity, because generating a code never writes
  /// one. This is only ever called once a device has actually redeemed one
  /// and is later cut off.
  Future<void> clear() async {
    await _storage.delete(_kSessionToken);
    await _storage.delete(_kDeviceId);
    await _storage.delete(_kRole);
    await _storage.delete(_kTargetId);
  }
}
