// OLIVE BRANCH — "Share with another grown-up", real-device verification entry point. DEV VERIFICATION ONLY, the same
// posture as every other main_local_*_test.dart (see main_live_child_call_test.dart for the fuller account). Analysed by CI;
// the on-device run is manual and not part of CI. UNVERIFIED on a device until that run is done and recorded.
//
// WHAT IT IS. A bare grown-up app over the REAL sealed on-device store and the REAL same-Wi-Fi road (mDNS and HTTP on the
// phone's LAN), with nothing else: no role picker, no PIN, no server. Two screens:
//   * "Share with another grown-up" (FamilyPhonesScreen): add a second phone with a code, join one, Share now, the shared
//     emergency card, the screens sent between grown-ups.
//   * "A screen to share" (a care-looking page with the quiet Share this screen icon in its bar): once two phones are
//     paired and the second has settled in, the icon appears and a picture of this page can be sent.
// It uses the same services the real grown-up app builds (GuardianLocalServices.from), so what it proves is what ships.
//
// RUN (two phones on one Wi-Fi, one build each; device serials are passed to adb at run time, never written here):
//   flutter run --target=lib/main_local_family_test.dart --dart-define=OLIVE_DEV_NO_SETTLE=true
// OLIVE_DEV_NO_SETTLE=true founds a family whose added phone does not wait 24 hours before it can be sent a screen. A
// store or release cut never passes it. Then:
//   1. Phone A: Share with another grown-up, Add another grown-up's phone, Show a code.
//   2. Phone B: Share with another grown-up, Join another grown-up's phone, pick the window with A's two words, type the code.
//   3. Both screens show the same word and picture. A taps Yes, add them.
//   4. Either phone: Share now over Wi-Fi. The emergency card (write one on A first: the card is shared from the page that
//      opens under "emergency card") appears on the other phone, beside its own card.
//   5. A screen to share: tap the icon in the bar, Send. The other phone finds it under Screens shared between grown-ups.
// To start again, clear the app's data (Android Settings, Apps, Olive, Storage).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emergency_card_local.dart';
import 'family_phones_screen.dart';
import 'family_structure_logic.dart' show FamilyPrincipal;
import 'guardian_local_scope.dart';
import 'local_services.dart';
import 'screen_share_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
  final LocalServices ls = await LocalServices.boot(childId: 'dev-family-test', isLive: true);
  runApp(_App(GuardianLocalServices.from(ls)));
}

class _App extends StatelessWidget {
  const _App(this.services);
  final GuardianLocalServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (family test)',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green), useMaterial3: true),
    builder: (BuildContext c, Widget? child) => FamilyRoadKeeper(
      hub: services.familyHub,
      child: ShareCaptureScope(service: services.shares, child: child!),
    ),
    home: _Home(services),
  );
}

class _Home extends StatelessWidget {
  const _Home(this.services);
  final GuardianLocalServices services;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Olive (family test)'), actions: const <Widget>[ShareScreenAction()]),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('A screen to share', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        const Text('Medicines: the morning dose is at 8:00. (Example text to send as a picture.)'),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('devFamilyOpen'),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => FamilyPhonesScreen(
                hub: services.familyHub!,
                childId: 'dev-family-test',
                principal: const FamilyPrincipal(roleName: 'guardian', userId: 'local-guardian'),
                cardService: EmergencyCardService.forChild('dev-family-test'),
                childName: 'her',
                defaultName: 'Grown-up',
              ),
            ),
          ),
          child: const Text('Share with another grown-up'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('devFamilyCard'),
          onPressed: () async {
            const FamilyPrincipal me = FamilyPrincipal(roleName: 'guardian', userId: 'local-guardian');
            final EmergencyCardService svc = EmergencyCardService.forChild('dev-family-test');
            final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
            final EmergencyCardDoc d = await svc.read(me);
            final EcResult r = await svc.save(
              me,
              LocalEmergencyCard(
                allergies: <String>['Example allergy'],
                doctor: EcDoctor(name: 'Dr Example', phone: '555-0100'),
                contacts: <EcContact>[EcContact(name: 'Example contact', relation: 'grandmother', phone: '555-0101')],
              ),
              expectedVersion: d.version,
            );
            m.showSnackBar(
              SnackBar(
                content: Text(r.ok ? 'An example card was written on this phone.' : 'The card was not changed.'),
              ),
            );
          },
          child: const Text('Write an example emergency card'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(
            context,
          ).push<void>(MaterialPageRoute<void>(builder: (_) => ScreenShareInboxScreen(service: services.shares!))),
          child: const Text('Screens shared between grown-ups'),
        ),
      ],
    ),
  );
}
