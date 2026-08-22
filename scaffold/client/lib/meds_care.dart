// OLIVE BRANCH — guardian shell, meds & care. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §9.6.1,
// §9.6.2, §5.8, §6.7. Renders MARKUP screen 'meds'.
//
// "Care information between guardians; never a surface the child carries."
// Not navigated to from any child-facing widget in this codebase (see
// child_home.dart — its tile grid has no meds/care entry at any depth).
//
// Ported 1:1 from packages/care/src/care.ts's medication section: DoseStatus,
// DoseKey, DoseRecord, AlreadyAdministered, doseKey(), recordDose(),
// prnAllowed(). The exchange-day double-dose guard is the point of this
// screen: dosing errors cluster at exchanges, and the collision message
// names the other parent and the local time, and NOTHING else — no blame
// framing, no notification to the child (§9.6.1).
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

// ================================================================ care.ts ===
enum DoseStatus { given, skipped, refused, missed }

class DoseKey {
  const DoseKey({required this.medicationId, required this.localDate, required this.slot});
  final String medicationId;
  final String localDate; // 'YYYY-MM-DD', child-local
  final String slot;      // 'morning' | 'evening' | 'prn' ...
}

class DoseRecord {
  const DoseRecord({required this.medicationId, required this.localDate, required this.slot,
    required this.administeredAt, required this.byUserName, required this.status});
  final String medicationId;
  final String localDate;
  final String slot;
  final DateTime administeredAt;
  final String byUserName;
  final DoseStatus status;
}

/// §9.6.1 — name the parent and the local time, state what is next, stop.
/// Any further framing reads as an accusation, and none of it is the
/// child's to see.
class AlreadyAdministered implements Exception {
  AlreadyAdministered(this.by, this.atLocal);
  final String by;
  final String atLocal;
  String get message => '$by gave this dose at $atLocal.';
}

/// The key is the CHILD's local date — an 8am dose in one house and "the
/// morning dose" in the other are the same slot on the same child-local day.
DoseKey doseKey(String medicationId, String slot, DateTime childLocalDate) => DoseKey(
  medicationId: medicationId, slot: slot,
  localDate: '${childLocalDate.year}-${childLocalDate.month.toString().padLeft(2, '0')}-'
    '${childLocalDate.day.toString().padLeft(2, '0')}');

class RecordDoseResult {
  const RecordDoseResult.ok(this.record) : error = null;
  const RecordDoseResult.blocked(this.error) : record = null;
  final DoseRecord? record;
  final AlreadyAdministered? error;
  bool get ok => error == null;
}

RecordDoseResult recordDose(List<DoseRecord> existing, DoseKey k,
  {required DateTime administeredAt, required String byUserName, required DoseStatus status}) {
  final Iterable<DoseRecord> clashes = existing.where((DoseRecord d) =>
    d.medicationId == k.medicationId && d.localDate == k.localDate &&
    d.slot == k.slot && d.status == DoseStatus.given);
  if (clashes.isNotEmpty && status == DoseStatus.given) {
    final DoseRecord clash = clashes.first;
    return RecordDoseResult.blocked(
      AlreadyAdministered(clash.byUserName, _clock(clash.administeredAt)));
  }
  return RecordDoseResult.ok(DoseRecord(medicationId: k.medicationId, localDate: k.localDate,
    slot: k.slot, administeredAt: administeredAt, byUserName: byUserName, status: status));
}

/// PRN (as-needed) doses are not slot-bound and must not collide.
bool prnAllowed(List<DoseRecord> existing, String medicationId, DateTime at, double minGapHours) {
  final List<DoseRecord> forMed = existing.where((DoseRecord d) => d.medicationId == medicationId)
    .toList()..sort((DoseRecord a, DoseRecord b) => b.administeredAt.compareTo(a.administeredAt));
  if (forMed.isEmpty) return true;
  return at.difference(forMed.first.administeredAt).inMinutes >= minGapHours * 60;
}

String _clock(DateTime d) {
  final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final String min = d.minute.toString().padLeft(2, '0');
  return '$h12:$min ${d.hour >= 12 ? 'PM' : 'AM'}';
}

// ============================================================== the demo ===
class _Medication {
  _Medication({required this.id, required this.name, required this.dose,
    required this.slots, this.isPrn = false, this.minGapHours = 4});
  final String id;
  final String name;
  final String dose;
  final List<String> slots;
  final bool isPrn;
  final double minGapHours;
}

class MedsCareScreen extends StatefulWidget {
  const MedsCareScreen({super.key, this.childName = 'Ivy'});
  final String childName;
  @override
  State<MedsCareScreen> createState() => _MedsCareScreenState();
}

class _MedsCareScreenState extends State<MedsCareScreen> {
  final DateTime _today = DateTime.utc(2026, 8, 4);

  final List<_Medication> _meds = <_Medication>[
    _Medication(id: 'methylphenidate', name: 'Methylphenidate', dose: '10 mg',
      slots: <String>['morning']),
    _Medication(id: 'cetirizine', name: 'Cetirizine', dose: '5 mg', slots: <String>['evening']),
    _Medication(id: 'albuterol', name: 'Albuterol inhaler', dose: '2 puffs',
      slots: <String>['prn'], isPrn: true, minGapHours: 4),
  ];

  final List<DoseRecord> _records = <DoseRecord>[];
  String? _banner;

  final List<String> _allergies = <String>['Peanuts — carries an EpiPen'];
  final List<String> _conditions = <String>['Mild asthma'];

  void _logDose(_Medication med, String slot, {required DoseStatus status}) {
    if (med.isPrn) {
      final bool ok = prnAllowed(_records, med.id, DateTime.now(), med.minGapHours);
      if (!ok) {
        setState(() => _banner = "Too soon for another ${med.name} dose — "
          'wait at least ${med.minGapHours.toStringAsFixed(0)} hours between doses.');
        return;
      }
      setState(() {
        _records.add(DoseRecord(medicationId: med.id, localDate: doseKey(med.id, slot, _today).localDate,
          slot: slot, administeredAt: DateTime.now(), byUserName: 'You', status: status));
        _banner = null;
      });
      return;
    }
    final DoseKey key = doseKey(med.id, slot, _today);
    final RecordDoseResult result = recordDose(_records, key,
      administeredAt: DateTime.now(), byUserName: 'You', status: status);
    setState(() {
      if (result.ok) {
        _records.add(result.record!);
        _banner = null;
      } else {
        // Exactly the ported message: names the parent and the local time,
        // nothing more.
        _banner = result.error!.message;
      }
    });
  }

  bool _givenToday(_Medication med, String slot) => _records.any((DoseRecord r) =>
    r.medicationId == med.id && r.slot == slot &&
    r.localDate == doseKey(med.id, slot, _today).localDate && r.status == DoseStatus.given);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Meds & care')),
    // Guardian-only (see file header). On a wide tablet/desktop viewport the
    // single column is only ever capped to a comfortable reading width and
    // centered, never split. Same real columnsAt() gate every other width
    // decision in the app uses.
    body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final double textScale = MediaQuery.textScalerOf(context).scale(1);
      final bool capWidth = ff.columnsAt(
          ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
      final Widget content = ListView(padding: const EdgeInsets.all(16), children: [
        Text('Between guardians only — ${widget.childName} never sees this screen.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (_banner != null)
          Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 18,
                color: Theme.of(context).colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(child: Text(_banner!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSecondaryContainer))),
            ])),
        const _SectionLabel('Scheduled medications'),
        const SizedBox(height: 8),
        for (final _Medication med in _meds.where((_Medication m) => !m.isPrn))
          Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${med.name} · ${med.dose}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final String slot in med.slots)
                Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(slot[0].toUpperCase() + slot.substring(1))),
                    if (_givenToday(med, slot))
                      const Chip(label: Text('Given today'))
                    else
                      // 48dp minimum tap target — was 44dp (finding #3).
                      SizedBox(height: 48, child: FilledButton(
                        onPressed: () => _logDose(med, slot, status: DoseStatus.given),
                        child: const Text('Log dose'))),
                  ])),
            ]))),
        const SizedBox(height: 12),
        const _SectionLabel('As needed'),
        const SizedBox(height: 8),
        for (final _Medication med in _meds.where((_Medication m) => m.isPrn))
          Card(child: Padding(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: Text('${med.name} · ${med.dose}',
                style: const TextStyle(fontWeight: FontWeight.w600))),
              // 48dp minimum tap target — was 44dp (finding #3).
              SizedBox(height: 48, child: OutlinedButton(
                onPressed: () => _logDose(med, 'prn', status: DoseStatus.given),
                child: const Text('Log PRN dose'))),
            ]))),
        const SizedBox(height: 20),
        const _SectionLabel('Shared medical record'),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Allergies', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final String a in _allergies) Text(a),
            const SizedBox(height: 12),
            const Text('Conditions', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final String c in _conditions) Text(c),
          ]))),
      ]);
      return capWidth
          ? Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                  child: content))
          : content;
    })),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700,
      letterSpacing: 0.5, color: Theme.of(context).colorScheme.primary));
}
