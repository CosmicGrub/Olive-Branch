// OLIVE BRANCH — the one place that builds the optional family account screen for a grown-up's phone. Verified
// headless (client/test/family_account_screens_test.dart). MASTERFILE section 8.5.13.
//
// Two callers open it: the Settings hub on a phone that is NOT connected ([GuardianLocalController.onAccount], set in
// guardian_boot.dart) and the same hub on a connected phone (guardian_more.dart). Both come here so the wiring is the
// same: the secure-storage sign-in, the on-device record of how far setup got, and the invite waiting to be finished.
//
// Nothing here makes a request. The screen it opens does nothing until a grown-up presses a button.
import 'package:flutter/material.dart';

import 'device_identity.dart';
import 'family_account_screens.dart';
import 'family_account_service.dart';
import 'family_account_store.dart';
import 'guardian_local_scope.dart';
import 'local_family.dart' show LocalFamily, kHomeZoneDevice;
import 'local_services.dart';

/// Builds the service for [baseUrl] on this phone's real storage.
FamilyAccountService buildFamilyAccountService(String baseUrl, {void Function()? onSignedOut}) =>
    FamilyAccountService(
      baseUrl: baseUrl,
      identityStore: DeviceIdentityStore(),
      record: accountRecordStoreFor(LocalServices.current),
      pending: SecurePendingJoinStore(),
      onSignedOut: onSignedOut,
    );

/// Opens the family account page. [onCodeRedeemed] receives the result of signing in with a code from another phone
/// (the caller stores it and reopens the connected shell, as for any connect).
void openFamilyAccount(
  BuildContext context, {
  required String baseUrl,
  Future<void> Function(Map<String, dynamic> result)? onCodeRedeemed,
}) {
  final LocalFamily? f = GuardianLocalScope.maybeOf(context)?.family;
  final FamilyAccountService service = buildFamilyAccountService(baseUrl);
  Navigator.of(context)
      .push<void>(MaterialPageRoute<void>(
        builder: (BuildContext _) => FamilyAccountScreen(
          service: service,
          baseUrl: baseUrl,
          suggestedName: f?.guardianName,
          suggestedChildName: f?.childName,
          suggestedZone: (f != null && f.homeZone != kHomeZoneDevice) ? f.homeZone : null,
          suggestedChildAge: f?.age,
          onCodeRedeemed: onCodeRedeemed,
        ),
      ))
      .whenComplete(service.dispose);
}
