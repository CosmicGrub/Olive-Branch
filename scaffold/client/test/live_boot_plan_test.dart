// OLIVE BRANCH — live_boot_plan.dart tests: which app the unified live entry opens, for every
// combination, and the guardian's three-way boot gate. No longer UNVERIFIED — verified by CI.
// MASTERFILE §8.5.8, §8.5.9.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_role.dart';
import 'package:olive_client/live_boot_plan.dart';

BootRoute route({
  LiveTarget target = LiveTarget.unified,
  bool child = false,
  bool guardian = false,
  String? stored,
  DeviceRole? role,
  bool family = false,
  bool pin = false,
  bool childPairing = false,
}) =>
    decideBoot(BootFacts(
      target: target,
      hasChildDefine: child,
      hasGuardianDefine: guardian,
      storedIdentityRole: stored,
      role: role,
      hasLocalFamily: family,
      hasLocalPin: pin,
      hasLocalChildPairing: childPairing,
    ));

void main() {
  group('a Kid device a grown-up approved on the same network', () {
    test('opens her home, not the first run', () {
      expect(route(role: DeviceRole.kid, childPairing: true), BootRoute.childPairedLocal);
    });
    test('a pairing without the Kid role (or a server identity) changes nothing else', () {
      expect(route(childPairing: true), BootRoute.rolePicker);
      expect(route(role: DeviceRole.mom, childPairing: true), BootRoute.guardianOnboarding);
      expect(route(stored: 'child', childPairing: true), BootRoute.childPaired);
    });
  });

  group('step 0: no identity and no role asks who is using the device', () {
    test('a fresh device opens the role picker', () {
      expect(route(), BootRoute.rolePicker);
      expect(route(target: LiveTarget.guardianDev), BootRoute.rolePicker);
    });

    test('a local family or PIN alone is not a role: the picker still comes first', () {
      expect(route(family: true, pin: true), BootRoute.rolePicker);
    });
  });

  group('the role picks the shell (role picker routing for all four roles)', () {
    test('Kid opens the child first run', () {
      expect(route(role: DeviceRole.kid), BootRoute.kidFirstRun);
    });

    for (final DeviceRole r in <DeviceRole>[DeviceRole.mom, DeviceRole.dad, DeviceRole.other]) {
      test('${r.title} with no local family opens the guardian onboarding', () {
        expect(route(role: r), BootRoute.guardianOnboarding);
      });

      test('${r.title} with a local family but NO local PIN still runs the onboarding (it cannot open offline)', () {
        expect(route(role: r, family: true), BootRoute.guardianOnboarding);
      });

      test('${r.title} with a local PIN but NO local family still runs the onboarding', () {
        expect(route(role: r, pin: true), BootRoute.guardianOnboarding);
      });

      test('${r.title} with a local family AND a local PIN opens the guardian home with no server', () {
        expect(route(role: r, family: true, pin: true), BootRoute.guardianOffline);
      });
    }

    test('a Kid never opens the guardian shell, whatever the device also holds', () {
      expect(route(role: DeviceRole.kid, family: true, pin: true), BootRoute.kidFirstRun);
    });
  });

  group('a connected device is whatever the server says it is', () {
    test('a stored guardian identity opens the guardian shell, a child one the child shell', () {
      expect(route(stored: 'guardian'), BootRoute.guardianPaired);
      expect(route(stored: 'child'), BootRoute.childPaired);
    });

    test('the identity wins over a stored role', () {
      expect(route(stored: 'child', role: DeviceRole.mom), BootRoute.childPaired);
      expect(route(stored: 'guardian', role: DeviceRole.kid), BootRoute.guardianPaired);
    });
  });

  group('the dev defines are unchanged and read nothing', () {
    test('OLIVE_CHILD_ID boots the child shell on the unified target, beating identity and role', () {
      expect(route(child: true), BootRoute.childDev);
      expect(route(child: true, stored: 'guardian', role: DeviceRole.mom), BootRoute.childDev);
    });

    test('OLIVE_GUARDIAN_ID boots the guardian shell', () {
      expect(route(guardian: true), BootRoute.guardianDev);
      expect(route(guardian: true, target: LiveTarget.guardianDev), BootRoute.guardianDev);
      expect(route(guardian: true, stored: 'child', role: DeviceRole.kid), BootRoute.guardianDev);
    });

    test('on the legacy guardian target OLIVE_CHILD_ID only names the child she looks at: it does NOT boot the child shell',
        () {
      expect(route(child: true, target: LiveTarget.guardianDev), BootRoute.rolePicker);
      expect(route(child: true, guardian: true, target: LiveTarget.guardianDev), BootRoute.guardianDev);
    });

    test('with both defines on the unified target the child define wins (as the old child target did)', () {
      expect(route(child: true, guardian: true), BootRoute.childDev);
    });
  });

  group('the unified entry (main_live.dart) really maps every route to a boot', () {
    final String src = File('lib/main_live.dart')
        .readAsStringSync()
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('every BootRoute that is reachable without a define has a case that boots something', () {
      final String sw = src.substring(src.indexOf('switch (route) {'), src.indexOf('Future<bool> _safeBool'));
      for (final BootRoute r in BootRoute.values) {
        expect(sw, contains('case BootRoute.${r.name}:'), reason: r.name);
      }
      expect(sw, contains('await _bootWithOnboardingGate(childId: stored!.targetId'));
      expect(sw, contains('await bootGuardianPaired(stored!);'));
      expect(sw, contains('runApp(const _RolePickerApp(onPicked: _onRolePicked));'));
      expect(sw, contains('await _startKidFirstRun();'));
      expect(sw, contains('await bootGuardianFlow(role!, reuseStorage: true);'));
    });

    test('picking a role stores it, then boots that role\'s own first run', () {
      final String fn = src.substring(src.indexOf('Future<void> _onRolePicked('), src.indexOf('Future<void> _startKidFirstRun()'));
      expect(fn.indexOf('LocalDeviceRoleRepository('), lessThan(fn.indexOf('bootGuardianFlow(')));
      expect(fn, contains('if (role.isGuardian) {'));
      expect(fn, contains('await _startKidFirstRun();'));
    });
  });

  group('the guardian boot gate: the old offline server-PIN trap is gone', () {
    test('the server says yes: go in, whatever the local PIN', () {
      expect(resolveGuardianEntry(serverHasPin: true, localPinSet: false), GuardianEntry.home);
      expect(resolveGuardianEntry(serverHasPin: true, localPinSet: true), GuardianEntry.home);
    });

    test('the server says NO: the server-PIN setup, exactly as before, even if a local PIN exists', () {
      expect(resolveGuardianEntry(serverHasPin: false, localPinSet: false), GuardianEntry.serverPinSetup);
      expect(resolveGuardianEntry(serverHasPin: false, localPinSet: true), GuardianEntry.serverPinSetup,
          reason: 'a local PIN never stands in for the account PIN while a session can be asked');
    });

    test('the server cannot be asked: a local PIN is sufficient to enter', () {
      expect(resolveGuardianEntry(serverHasPin: null, localPinSet: true), GuardianEntry.home);
    });

    test('the server cannot be asked and there is no local PIN: set a local one, which works offline', () {
      expect(resolveGuardianEntry(serverHasPin: null, localPinSet: false), GuardianEntry.localPinSetup);
    });
  });
}
