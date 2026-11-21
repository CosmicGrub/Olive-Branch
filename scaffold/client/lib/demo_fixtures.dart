// OLIVE BRANCH - the invented demo content, in ONE file, behind ONE guard.
//
// Medicines, an emergency card with phone numbers and an insurance member id, and a fixed grown-up PIN are
// all made up for the offline preview (lib/main.dart) and for tests. A real family must never meet any of
// them: an invented medicine on a real child's screen, or a PIN that anyone who reads the source knows, is
// worse than an empty screen. So:
//
//   * Every literal lives here and nowhere else in lib/ (test/demo_fixtures_guard_test.dart checks that).
//   * Every accessor is `if (kDebugMode) { return <content>; } return <nothing>;`. kDebugMode is a compile-time
//     constant, false in a profile or release build, so the compiler drops the branch and the literals never
//     reach the built app. tools/check-release-literals.mjs reads the built release and fails if any of the
//     strings in tools/demo-literals.json is in it (the release-smoke workflow runs it on the real APK).
//   * LocalServices.demoSeeds is a second, runtime switch (default false): the preview turns it on, a real
//     build never does.
//
// Nothing here is advice. The medicines are names and amounts a screen can draw; nobody should read them as
// a recommendation, which is one more reason they stay in debug builds.
import 'package:flutter/foundation.dart' show kDebugMode;

/// One invented medicine for the meds screen preview.
class DemoMed {
  const DemoMed({
    required this.id,
    required this.name,
    required this.dose,
    required this.slots,
    this.isPrn = false,
    this.minGapHours,
  });
  final String id;
  final String name;
  final String dose;
  final List<String> slots;
  final bool isPrn;

  /// Null = no minimum gap set (the rule is never invented).
  final double? minGapHours;
}

/// The invented medicine list. Empty outside a debug build.
List<DemoMed> demoMedications() {
  if (kDebugMode) {
    return const <DemoMed>[
      DemoMed(id: 'demo-a', name: 'Methylphenidate', dose: '10 mg', slots: <String>['morning']),
      DemoMed(id: 'demo-b', name: 'Cetirizine', dose: '5 mg', slots: <String>['evening']),
      DemoMed(id: 'demo-c', name: 'Albuterol inhaler', dose: '2 puffs', slots: <String>['prn'], isPrn: true, minGapHours: 4),
    ];
  }
  return const <DemoMed>[];
}

/// The invented "Shared medical record" allergy and condition lines. Empty outside a debug build.
List<String> demoAllergies() {
  if (kDebugMode) return const <String>['Peanuts — carries an EpiPen'];
  return const <String>[];
}

List<String> demoConditions() {
  if (kDebugMode) return const <String>['Mild asthma'];
  return const <String>[];
}

/// One invented contact line (name, phone) for the demo emergency card.
class DemoContact {
  const DemoContact(this.name, this.phone);
  final String name;
  final String phone;
}

/// The invented emergency card. [DemoCard.none] outside a debug build.
class DemoCard {
  const DemoCard({
    required this.bloodType,
    required this.allergies,
    required this.medicines,
    required this.guardians,
    required this.pediatricianName,
    required this.pediatricianPractice,
    required this.pediatricianPhone,
    required this.insuranceProvider,
    required this.insuranceMemberId,
  });
  final String bloodType;
  final List<String> allergies;
  final List<(String, String)> medicines;
  final List<DemoContact> guardians;
  final String pediatricianName;
  final String pediatricianPractice;
  final String pediatricianPhone;
  final String insuranceProvider;
  final String insuranceMemberId;
}

/// The demo card, or null (outside a debug build).
DemoCard? demoEmergencyCard() {
  if (kDebugMode) {
    return const DemoCard(
      bloodType: 'O positive',
      allergies: <String>['Peanuts — carries an EpiPen, in her backpack side pocket'],
      medicines: <(String, String)>[
        ('Cetirizine', '5 mg — once daily, evening'),
        ('Albuterol inhaler', '2 puffs — as needed for wheezing'),
      ],
      guardians: <DemoContact>[
        DemoContact('Mom — Claire Solomon', '(617) 555-0142'),
        DemoContact('Dad — Marcus Solomon', '(617) 555-0198'),
      ],
      pediatricianName: 'Dr. Priya Nair',
      pediatricianPractice: 'Riverbend Pediatrics',
      pediatricianPhone: '(617) 555-0177',
      insuranceProvider: 'BlueBridge Family Health',
      insuranceMemberId: 'BBH-7734-2201',
    );
  }
  return null;
}

/// The preview build's stand-in grown-up code, or null (outside a debug build, where nothing is accepted).
String? demoGuardianPin() {
  if (kDebugMode) return '1273';
  return null;
}
