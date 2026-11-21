// OLIVE BRANCH — the one place that builds the recovery paths for a grown-up's phone. Verified headless
// (client/test/recovery_paths_screens_test.dart). MASTERFILE section 7.22.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 7.22).
//
// Three callers open it, all on a grown-up's phone: the lock screen's "Forgot your PIN?" (a phone that lost its sign-in
// asks "Lost your phone?"), Settings, Family account (signed out: "Lost your phone?"; signed in: "Lost phone safety"),
// and Settings, Safety. Nothing here makes a request: the screens it opens do nothing until a grown-up presses a button.
import 'package:flutter/material.dart';

import 'device_identity.dart';
import 'family_account_entry.dart' show buildFamilyAccountService;
import 'family_account_service.dart';
import 'recovery_paths_screens.dart';
import 'recovery_paths_service.dart';

/// "Lost your phone?" from anywhere a grown-up might look for it.
void openLostPhone(BuildContext context, {required String baseUrl}) {
  final FamilyAccountService account = buildFamilyAccountService(baseUrl);
  final RecoveryPathsService service = buildRecoveryPathsService(baseUrl, account);
  Navigator.of(context)
      .push<void>(MaterialPageRoute<void>(
        builder: (BuildContext _) => LostPhoneScreen(service: service, account: account),
      ))
      .whenComplete(() {
    service.dispose();
    account.dispose();
  });
}

/// "Lost phone safety" for a phone that is signed in: the sheet, the helper, notices, helping someone.
void openRecoverySafety(BuildContext context, {required String baseUrl}) {
  final FamilyAccountService account = buildFamilyAccountService(baseUrl);
  final RecoveryPathsService service = buildRecoveryPathsService(baseUrl, account);
  Navigator.of(context)
      .push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => RecoverySafetyScreen(service: service)))
      .whenComplete(() {
    service.dispose();
    account.dispose();
  });
}

/// Whether this phone holds a sign-in at all (to choose between "Lost your phone?" and "Lost phone safety").
Future<bool> phoneHoldsSignIn() async {
  try {
    final DeviceIdentity? id = await DeviceIdentityStore().load();
    return id != null && id.role == 'guardian';
  } catch (_) {
    return false;
  }
}
