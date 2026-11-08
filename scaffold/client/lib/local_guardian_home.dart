// OLIVE BRANCH — the guardian home with NO server: the local family's home screen.
// No longer UNVERIFIED — verified by CI (client/test/local_guardian_home_test.dart).
// MASTERFILE §8.5.9.
//
// What an offline grown-up reaches: the same [GuardianHome] the live build shows, fed from
// the local family instead of /now and /ribbon. Audit finding A-G2 was that an offline
// launch landed on a server-PIN setup that could not be left; this is where it lands now.
//
// HONEST ABOUT WHAT IT DOES NOT KNOW. There is no ribbon (that is a server route), no
// "state sentence" and no overlap: [GuardianHome] renders none of those when they are empty,
// exactly as its live wrapper already does for the two the server also lacks. Her clock is the
// phone's own clock when her home zone is "same as this phone"; for any other zone the phone
// has no zone database to convert with, so her clock is left empty and the zone's name is
// shown instead, until the device is connected. Every tile that needs a server still says so
// the way it does in the preview build.
//
// A one-line band says plainly that this is on this device only and how to connect (Settings,
// under Account) when the build can connect.
import 'package:flutter/material.dart';

import 'calendar_day_logic.dart' show formatTimeOfDay, hhmmNow;
import 'guardian_home.dart';
import 'guardian_local_scope.dart';
import 'local_family.dart';

class LocalGuardianHome extends StatelessWidget {
  const LocalGuardianHome({super.key, required this.family, this.nowHhmm});
  final LocalFamily family;

  /// "HH:mm" for tests; the phone's clock when null.
  final String? nowHhmm;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String phoneClock = formatTimeOfDay(nowHhmm ?? hhmmNow());
    final bool sameZone = family.homeZone == kHomeZoneDevice;
    final GuardianLocalController? local = GuardianLocalScope.maybeOf(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: <Widget>[
          Container(
            key: const Key('localHomeBand'),
            width: double.infinity,
            color: scheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              local?.onConnect != null
                  ? 'On this device only. To share it with your family, connect it in Settings, under Account.'
                  : 'On this device only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
          Expanded(
            child: GuardianHome(
              childName: family.childName,
              childLocalTime: sameZone ? phoneClock : '',
              childZoneAbbr: sameZone ? DateTime.now().timeZoneName : homeZoneLabel(family.homeZone),
              actorLocalTime: phoneClock,
              childBands: const <RibbonBand>[],
              actorBands: const <RibbonBand>[],
            ),
          ),
        ]),
      ),
    );
  }
}
