// FAMILY SIMULATION contact sheet: renders the app's REAL screens for a few of the
// simulation's synthetic families / ages at key moments and writes PNGs to
// client/build/family-sim-contact-sheet/ (gitignored). `node tools/family-sim/contact-sheet.mjs`
// then assembles them into one HTML sheet. The assertions are only that every screen builds and
// produces a real image; the pictures are the evidence.
//
//   flutter test -j 2 test/family_sim_contact_sheet_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_home_bands.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_screens.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/first_run_flow.dart';
import 'package:olive_client/grownup_labels.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/onboarding_draft.dart';
import 'package:olive_client/pairing_redeem_screen.dart';
import 'package:olive_client/play_notice.dart';
import 'package:olive_client/role_picker_screen.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_data.dart';

const FamilyPrincipal _guardian = FamilyPrincipal(roleName: 'guardian', userId: 'g1');
const FamilyPrincipal _childP = FamilyPrincipal(roleName: 'child', childId: 'c1');
final DateTime _fixed = DateTime(2026, 11, 13, 16, 30);

Map<String, Object?> _person(String id, String label, String role, String? home, List<String> contact) =>
    <String, Object?>{'id': id, 'label': label, 'role': role, 'homeId': home, 'contact': contact, 'away': null};
Map<String, Object?> _home(String id, String name) => <String, Object?>{'id': id, 'name': name, 'childSleeps': true};

FamilyService _svc() => FamilyService(MemoryFamilyStore(), clock: () => _fixed);

/// Tanaka-Brooks: two homes, two guardians and a step-parent figure (family 4 in the simulation).
Future<FamilyService> _tanakaBrooks(int years) async {
  final FamilyService s = _svc();
  Future<void> add(Map<String, Object?> op) =>
      s.addChange(_guardian, actorName: 'Kei', yearsOld: years, op: op, timing: Timing.now.toJson());
  await add(<String, Object?>{'op': 'put_home', 'home': _home('h1', "Kei's house")});
  await add(<String, Object?>{'op': 'put_home', 'home': _home('h2', "Dana's house")});
  await add(<String, Object?>{'op': 'put_person', 'person': _person('p1', 'Kei', 'guardian', 'h1', <String>['live_call', 'message'])});
  await add(<String, Object?>{'op': 'put_person', 'person': _person('p2', 'Dana', 'guardian', 'h2', <String>['live_call'])});
  return s;
}

void main() {
  final String outDir = '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}family-sim-contact-sheet';
  final ThemeData theme = buildThemeData(const AppTheme(palette: ThemePalette.olive, brightness: ThemeBrightness.light));
  final List<Map<String, String>> manifest = <Map<String, String>>[];
  Future<void> loadFont(String family, List<String> paths) async {
    final FontLoader l = FontLoader(family);
    for (final String p in paths) {
      final File f = File(p);
      if (f.existsSync()) l.addFont(Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await l.load();
  }

  setUpAll(() async {
    Directory(outDir).createSync(recursive: true);
    // flutter test renders every font as boxes unless the real ones are loaded: use the app's bundled fonts and the SDK's icon font.
    final String fonts = '${Directory.current.path}/assets/fonts';
    await loadFont('AtkinsonHyperlegible', <String>['$fonts/AtkinsonHyperlegible-Regular.ttf', '$fonts/AtkinsonHyperlegible-Bold.ttf']);
    await loadFont('BricolageGrotesque', <String>['$fonts/BricolageGrotesque.ttf']);
    await loadFont('JetBrainsMono', <String>['$fonts/JetBrainsMono.ttf']);
    final String root = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}/flutter';
    await loadFont('MaterialIcons', <String>['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });
  tearDownAll(() => File('$outDir${Platform.pathSeparator}manifest.json').writeAsStringSync(jsonEncode(manifest)));

  Future<void> shoot(WidgetTester t, String file, String title, String who, Widget screen,
      {Size size = const Size(412, 892), bool settle = true}) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    final GlobalKey key = GlobalKey();
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: RepaintBoundary(key: key, child: screen)));
    if (settle) {
      await t.pumpAndSettle();
    } else {
      await t.pump(const Duration(milliseconds: 400));
    }
    int bytes = 0;
    await t.runAsync(() async {
      final RenderRepaintBoundary ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await ro.toImage(pixelRatio: 2);
      final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
      final List<int> png = bd!.buffer.asUint8List();
      File('$outDir${Platform.pathSeparator}$file.png').writeAsBytesSync(png);
      bytes = png.length;
    });
    expect(bytes, greaterThan(2000), reason: '$file rendered a real image');
    expect(t.takeException(), isNull, reason: '$file built without an exception');
    manifest.add(<String, String>{'file': '$file.png', 'title': title, 'who': who});
  }

  Widget labelled(Widget child, int years) => GrownupLabelScope(
      labels: GrownupLabels(
          contacts: const <GrownupContact>[
            GrownupContact(id: 'g1', guardianLabel: 'Kei', kind: GrownupKind.mom),
            GrownupContact(id: 'g2', guardianLabel: 'Dana', kind: GrownupKind.dad),
          ],
          age: AgeLockState(age: years, locked: true)),
      child: child);

  Future<Widget> kidHome(String name, int years) async {
    final FamilyService s = await _tanakaBrooks(years);
    final FamilyChildSnapshot snap = await s.childSnapshot(_childP, childId: 'c1', yearsOld: years);
    return labelled(
        ChildHome(childName: name, presence: null, sleepsUntilHandover: null, unreadCount: 1, family: snap, childAge: years, clock: () => _fixed),
        years);
  }

  testWidgets('first run: welcome (Okafor-Reyes, a new device)', (WidgetTester t) async {
    await shoot(t, '01_first_run', 'First run: Welcome', 'Okafor-Reyes, a brand-new install',
        FirstRunFlow(baseUrl: 'http://olive.test', draftRepository: MemoryOnboardingDraftRepository(),
            httpClient: MockClient((http.Request r) async => http.Response('{}', 404)), onRedeemed: (_) {}));
  });

  testWidgets('role picker', (WidgetTester t) async {
    await shoot(t, '02_role_picker', 'Who is using this device?', 'any family, first launch', RolePickerScreen(onPicked: (_) {}));
  });

  testWidgets('pairing: a child device enters the code', (WidgetTester t) async {
    await shoot(t, '03_pairing', "Pairing: Wren's tablet", 'Okafor-Reyes, child device (age 6)',
        PairingRedeemScreen(baseUrl: 'http://olive.test', role: 'child', onRedeemed: (_) {},
            httpClient: MockClient((http.Request r) async => http.Response('{}', 404))));
  });

  for (final (String file, String band, String name, int age) in <(String, String, String, int)>[
    ('04_child_home_t34', 't34', 'Pip', 4), ('05_child_home_t57', 't57', 'Wren', 6),
    ('06_child_home_t812', 't812', 'Juno', 9), ('07_child_home_t1317', 't1317', 'Nour', 16),
  ]) {
    testWidgets('child home $band', (WidgetTester t) async {
      await shoot(t, file, 'Child home, $band', '$name, age $age', await kidHome(name, age), size: const Size(412, 860));
    });
  }

  testWidgets('guardian home', (WidgetTester t) async {
    await shoot(t, '08_guardian_home', 'Guardian home', 'Tanaka-Brooks, Kei', const GuardianHome(
        childName: 'Moss', childLocalTime: '4:30 PM', childZoneAbbr: 'PST',
        actorLocalTime: '4:30 PM PST', childStateSentence: 'Moss is just home from school',
        childBands: <RibbonBand>[RibbonBand(0.0, 0.4, Colors.green, 'school'), RibbonBand(0.4, 0.6, Colors.orange, 'home time')],
        actorBands: <RibbonBand>[RibbonBand(0.0, 0.5, Colors.blue, 'work'), RibbonBand(0.5, 0.5, Colors.green, 'free')],
        overlapLabel: 'both free 5:00-6:00 PM'), size: const Size(412, 860));
  });

  testWidgets('a play notice (the other device went away)', (WidgetTester t) async {
    await shoot(t, '09_play_notice_away', 'Play notice: the other device stepped away', 'Marlowes, Juno (9)',
        const Scaffold(body: Center(child: PlaySessionNotice(kind: PlayNoticeKind.away))), size: const Size(412, 500));
    await shoot(t, '10_play_notice_ended', 'Play notice: the game ended', 'Marlowes, Juno (9)',
        Scaffold(body: Center(child: PlaySessionNotice(kind: PlayNoticeKind.ended, onLeave: () {}))), size: const Size(412, 500));
  });

  testWidgets('family structure (two homes)', (WidgetTester t) async {
    final FamilyService s = await _tanakaBrooks(11);
    await shoot(t, '11_family_structure', 'Family structure', 'Tanaka-Brooks, Kei (guardian)',
        FamilyStructureScreen(ctx: FamilyContext(service: s, principal: _guardian, actorName: 'Kei', childName: 'Moss', yearsOld: 11)),
        size: const Size(412, 1100));
  });
}
