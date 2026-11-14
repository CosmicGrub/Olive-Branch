// OLIVE BRANCH — the care profile screens ("About <child>"): the hub, a part, who sees what, the "show as"
// view, the photos of a doctor's plan, and the one-page doctor sheet. UNVERIFIED until CI runs
// client/test/care_profile_screens_test.dart. MASTERFILE section 8.24.8.
//
// EVERY SCREEN HERE IS THE GUARDIAN SHELL. They are reached from the grown-up's Settings (Family, "About her")
// and the Care and coordination hub, never from her app: no child file imports this file (the structural test
// care_profile_structure_test.dart reads the real sources to prove it). A principal that is not a guardian gets
// one neutral line and nothing is read.
//
// WORDS. Plain, for an adult. The text of every entry is whatever a grown-up typed, with who wrote it and when.
// The app adds the section names, plain instructions and the honest notes below, and no advice of its own.
//
// HONEST ABOUT WHAT IS NOT BUILT. Sharing between phones does not exist yet. What a person is "shown" is what
// the "Show as" screen on THIS phone and the printed sheet will show, and the hub says so in plain words. The
// PIN protects the locked parts on this phone; the file itself is sealed with the phone's own key.
import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

import 'care_local.dart' show CareDoc, CareLocalRefused, CareResult, CareService;
import 'care_profile_logic.dart';
import 'care_profile_store.dart';
import 'emergency_card_local.dart' show EcRefused, EmergencyCardService, LocalEmergencyCard;
import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'growing_care_store.dart' show GrowingCareStores;
import 'growing_care_widgets.dart' show confirmPutAway;
import 'hub_widgets.dart';

/// Asks the phone's photo picker for ONE photo a grown-up chooses; null if none was chosen. A plan needs to be
/// readable, so this asks for more than the small thumbnails the other suites keep. Never called by the app on
/// its own: only when a grown-up taps "Add a photo".
typedef PlanPhotoSource = Future<Uint8List?> Function();

Future<Uint8List?> pickPlanPhoto() async {
  try {
    // No resizing or recompression: a plan has to stay legible, and the plugin would otherwise write a re-encoded copy.
    final XFile? x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return null;
    final Uint8List bytes = await x.readAsBytes();
    // The picker hands back a copy in this app's temporary folder, unsealed. Remove it now that the sealed copy is
    // made from its bytes. Only a file inside the temporary folder is ever deleted: never a photo of the user's own.
    try {
      final String tmp = (await getTemporaryDirectory()).path;
      if (x.path.startsWith(tmp)) await File(x.path).delete();
    } catch (_) {}
    return bytes;
  } catch (_) {
    return null;
  }
}

const String careProfileLocalNote =
    'Kept on this phone only, sealed, and never shown in her app. Every word is a grown-up\'s: the app writes '
    'no medical advice and works out no doses.';

const String careProfileNoSyncNote =
    'Sharing between phones is not built yet. What you choose here decides what "Show as" on this phone and the '
    'printed sheet will show. Nothing is sent to anyone.';

void _snack(BuildContext context, String t) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 4)));

Widget _note(BuildContext context, String text, {Key? key, IconData icon = Icons.info_outline, bool warn = false}) {
  final ColorScheme c = Theme.of(context).colorScheme;
  return Container(
    key: key,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: warn ? c.tertiaryContainer : c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Icon(icon, size: 18, color: warn ? c.onTertiaryContainer : c.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: warn ? c.onTertiaryContainer : c.onSurfaceVariant)),
      ),
    ]),
  );
}

/// The neutral line anyone who is not a grown-up gets.
class CareProfileNotForYou extends StatelessWidget {
  const CareProfileNotForYou({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: const SafeArea(
          child: Center(
            child: Padding(padding: EdgeInsets.all(24), child: Text("There's nothing on this screen for you.", key: Key('careProfileNotForYou'))),
          ),
        ),
      );
}

String _refusal(CareResult<Object?> r) => cpRefusalText(r.reason);

/// The PIN box. Returns true only for a PIN [verify] accepted.
Future<bool> _askPin(BuildContext context, Future<bool> Function(String pin)? verify, {String why = 'This part is for parents only.'}) async {
  if (verify == null) {
    _snack(context, 'Set a PIN for this phone in Settings first. Until then this part stays closed.');
    return false;
  }
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => _PinDialog(verify: verify, why: why),
  );
  return ok == true;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.verify, required this.why});
  final Future<bool> Function(String pin) verify;
  final String why;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _c = TextEditingController();
  String? _message;
  bool _working = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_working) return;
    setState(() => _working = true);
    final bool ok = await widget.verify(_c.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    _c.clear();
    setState(() {
      _working = false;
      _message = 'That is not your PIN, or it is resting for a while.';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Enter your PIN'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(widget.why),
          const SizedBox(height: 8),
          TextField(
            key: const Key('profilePinField'),
            controller: _c,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'PIN'),
            onSubmitted: (_) => unawaited(_go()),
          ),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('profilePinMessage'))),
        ]),
        actions: <Widget>[
          TextButton(key: const Key('profilePinCancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(key: const Key('profilePinOk'), onPressed: _working ? null : () => unawaited(_go()), child: const Text('Open')),
        ],
      );
}

// ================================================================ the hub ===
class CareProfileScreen extends StatefulWidget {
  const CareProfileScreen({
    super.key,
    required this.service,
    required this.plans,
    required this.principal,
    this.childName = 'her',
    this.childAge,
    this.byName,
    this.verifyPin,
    this.meds,
    this.emergency,
    this.binder,
    this.openMedicines,
    this.photoSource,
    this.clock,
  });
  final CareProfileService service;
  final CarePlanPhotoService plans;
  final FamilyPrincipal? principal;
  final String childName;
  final int? childAge;

  /// The grown-up's name for "written by".
  final String? byName;

  /// Checks the guardian PIN; null leaves the locked parts closed.
  final Future<bool> Function(String pin)? verifyPin;

  /// The existing medicines log, the emergency card and the care binder this profile gathers (each optional).
  final CareService? meds;
  final EmergencyCardService? emergency;
  final GrowingCareStores? binder;

  /// Opens the existing medicines screen (with its dose log and double-dose guard).
  final WidgetBuilder? openMedicines;
  final PlanPhotoSource? photoSource;
  final DateTime Function()? clock;

  @override
  State<CareProfileScreen> createState() => _CareProfileState();
}

class _CareProfileState extends State<CareProfileScreen> {
  CareProfileDoc? _doc;
  CareDoc? _meds;
  LocalEmergencyCard? _card;
  int _photos = 0;
  int _copied = 0;
  bool _refused = false;
  bool _notNow = false;
  List<CpReviewReason> _reasons = const <CpReviewReason>[];

  DateTime _now() => (widget.clock ?? DateTime.now)();
  String get _child => widget.childName;

  @override
  void initState() {
    super.initState();
    unawaited(_load(first: true));
  }

  @override
  void dispose() {
    widget.service.lock();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    if (!canEditStructure(widget.principal)) {
      if (mounted) setState(() => _refused = true);
      return;
    }
    try {
      if (first && widget.binder != null) {
        final CareResult<int> r = await widget.service.importBinder(widget.principal, await widget.binder!.sections.list());
        if (r.ok && (r.value ?? 0) > 0) _copied = r.value!;
      }
      CareDoc? m;
      if (widget.meds != null) {
        try {
          m = await widget.meds!.read(widget.principal);
        } on CareLocalRefused {
          m = null;
        }
      }
      LocalEmergencyCard? card;
      if (widget.emergency != null) {
        try {
          card = (await widget.emergency!.read(widget.principal)).card;
        } on EcRefused {
          card = null;
        }
      }
      final String fp = cpMedicineFingerprint(m);
      if (first) await widget.service.ensureBaseline(widget.principal, fp);
      final CareProfileDoc d2 = await widget.service.read(widget.principal);
      final int photos = (await widget.plans.list(widget.principal)).length;
      if (!mounted) return;
      setState(() {
        _doc = d2;
        _meds = m;
        _card = card;
        _photos = photos;
        _reasons = cpReviewReasons(d2, _now(), medFingerprint: fp, child: _child, childAge: widget.childAge);
      });
    } on CareProfileRefused {
      if (mounted) setState(() => _refused = true);
    }
  }

  Future<void> _go(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    await _load();
  }

  Future<void> _reviewed() async {
    final CareResult<void> r = await widget.service.markReviewed(widget.principal, cpMedicineFingerprint(_meds));
    if (!mounted) return;
    if (!r.ok) _snack(context, _refusal(r));
    await _load();
  }

  Future<void> _writeHeads() async {
    final CpHeads? cur = _doc == null ? null : cpHeadsToday(_doc!, _now());
    // The dialog's controllers are not disposed here: its closing animation still draws the field after this
    // returns. They hold no resource beyond their own memory.
    final TextEditingController c = TextEditingController(text: cur?.text ?? '');
    String? err;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AlertDialog(
          title: const Text("Today's heads-up"),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('One short note for today. It is gone at midnight and is never kept as a log.'),
            const SizedBox(height: 8),
            TextField(key: const Key('headsField'), controller: c, maxLength: cpMaxHeadsChars, maxLines: 4, minLines: 2, autofocus: true),
            if (err != null) Text(err!, key: const Key('headsError')),
          ]),
          actions: <Widget>[
            TextButton(key: const Key('headsCancel'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              key: const Key('headsSave'),
              onPressed: () async {
                final CareResult<void> r = await widget.service.setHeads(widget.principal, c.text, byName: widget.byName);
                if (r.ok) {
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } else {
                  set(() => err = r.reason == 'tone' ? '${cpRefusalText('tone')} $careProfileToneGuidance' : _refusal(r));
                }
              },
              child: const Text('Save for today'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _birthday() async {
    int? m = _doc?.birthMonth, d = _doc?.birthDay;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AlertDialog(
          title: Text("$_child's birthday"),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('Only so the profile can ask "is this still right?" once a year. Kept on this phone.'),
            const SizedBox(height: 8),
            DropdownButton<int>(
              key: const Key('birthMonth'),
              isExpanded: true,
              hint: const Text('Month'),
              value: m,
              items: <DropdownMenuItem<int>>[
                for (int i = 1; i <= 12; i++) DropdownMenuItem<int>(value: i, child: Text(<String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][i - 1])),
              ],
              onChanged: (int? v) => set(() => m = v),
            ),
            DropdownButton<int>(
              key: const Key('birthDay'),
              isExpanded: true,
              hint: const Text('Day'),
              value: d,
              items: <DropdownMenuItem<int>>[for (int i = 1; i <= 31; i++) DropdownMenuItem<int>(value: i, child: Text('$i'))],
              onChanged: (int? v) => set(() => d = v),
            ),
          ]),
          actions: <Widget>[
            TextButton(key: const Key('birthClear'), onPressed: () async {
              await widget.service.setBirthday(widget.principal, null, null);
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            }, child: const Text('Forget it')),
            FilledButton(key: const Key('birthSave'), onPressed: () async {
              final CareResult<void> r = await widget.service.setBirthday(widget.principal, m, d);
              if (!ctx.mounted) return;
              if (r.ok) {
                Navigator.of(ctx).pop(true);
              } else {
                _snack(ctx, _refusal(r));
              }
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _openPart(CareProfilePart p) async {
    if (p == CareProfilePart.meds) {
      if (widget.openMedicines == null) {
        _snack(context, 'Medications are not available here.');
        return;
      }
      await _go(Builder(builder: widget.openMedicines!));
      return;
    }
    await _go(CareProfilePartScreen(
      service: widget.service,
      principal: widget.principal,
      part: p,
      childName: _child,
      byName: widget.byName,
      verifyPin: widget.verifyPin,
      clock: widget.clock,
    ));
  }

  String _count(CareProfilePart p) {
    final CareProfileDoc? d = _doc;
    if (d == null) return '';
    if (p.locked && !widget.service.isUnlocked) return 'Behind your PIN';
    final int n = cpEntriesOf(d, p).length;
    final int diff = cpDisagreements(d, p).length;
    final String base = n == 0 ? 'Nothing written yet' : '$n written';
    return diff == 0 ? base : '$base. $diff to agree on';
  }

  @override
  Widget build(BuildContext context) {
    if (_refused || !canEditStructure(widget.principal)) return const CareProfileNotForYou();
    final CareProfileDoc? d = _doc;
    final CpHeads? heads = d == null ? null : cpHeadsToday(d, _now());
    final int medCount = cpMedicineLines(_meds).length;
    final int? age = widget.childAge;
    final int? bm = d?.birthMonth;
    return Scaffold(
      appBar: AppBar(title: Text('About $_child')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          _note(context, '$careProfileLocalNote $careProfileNoSyncNote', key: const Key('profileBanner'), icon: Icons.shield_outlined),
          if (_copied > 0)
            _note(context, 'Copied $_copied ${_copied == 1 ? 'section' : 'sections'} from your care binder. The binder still has its own copy and nothing in it was changed. This was a one-time copy: later changes in the binder do not reach here, so write new ones here.', key: const Key('profileCopied')),
          if (!_notNow)
            for (final CpReviewReason r in _reasons)
              Card(
                key: ValueKey<String>('review-${r.kind.name}'),
                child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(r.text),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: <Widget>[
                    FilledButton(key: const Key('reviewYes'), onPressed: () => unawaited(_reviewed()), child: const Text('Yes, still right')),
                    TextButton(key: const Key('reviewNotNow'), onPressed: () => setState(() => _notNow = true), child: const Text('Not now')),
                  ]),
                ])),
              ),
          // Today's heads-up
          Card(
            key: const Key('headsCard'),
            child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(careProfilePartTitle(CareProfilePart.heads, _child), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (heads == null)
                const Text('Nothing for today.', key: Key('headsEmpty'))
              else ...<Widget>[
                Text(heads.text, key: const Key('headsText')),
                Text('written by ${heads.byName.isEmpty ? cpUnnamedGuardian : heads.byName}, today', style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 4),
              Text(careProfilePartHint(CareProfilePart.heads), style: Theme.of(context).textTheme.bodySmall),
              Wrap(spacing: 8, children: <Widget>[
                FilledButton.tonal(key: const Key('headsWrite'), onPressed: () => unawaited(_writeHeads()), child: Text(heads == null ? 'Write one for today' : 'Change it')),
                if (heads != null)
                  TextButton(key: const Key('headsClear'), onPressed: () async {
                    await widget.service.clearHeads(widget.principal);
                    await _load();
                  }, child: const Text('Clear it')),
              ]),
            ])),
          ),
          for (final CareProfilePart p in <CareProfilePart>[CareProfilePart.safe, CareProfilePart.everyday, CareProfilePart.helps])
            HubTile(
              key: ValueKey<String>('part-${p.name}'),
              icon: switch (p) {
                CareProfilePart.safe => Icons.health_and_safety_outlined,
                CareProfilePart.everyday => Icons.wb_sunny_outlined,
                _ => Icons.favorite_border,
              },
              title: careProfilePartTitle(p, _child),
              subtitle: _count(p),
              onTap: () => unawaited(_openPart(p)),
            ),
          HubTile(
            key: const Key('part-meds'),
            icon: Icons.medication_outlined,
            title: careProfilePartTitle(CareProfilePart.meds, _child),
            subtitle: widget.meds == null ? 'Open Medications' : (medCount == 0 ? 'None written. Dose log and double-dose guard' : '$medCount written. Dose log and double-dose guard'),
            onTap: () => unawaited(_openPart(CareProfilePart.meds)),
          ),
          if (_card != null && !_card!.isEmpty)
            _note(context, 'Her emergency card (allergies, doctor, contacts) is read from where you wrote it and goes on the doctor sheet. It is not copied.', key: const Key('profileCardNote')),
          const SizedBox(height: 4),
          for (final CareProfilePart p in <CareProfilePart>[CareProfilePart.health, CareProfilePart.moods])
            HubTile(
              key: ValueKey<String>('part-${p.name}'),
              icon: p == CareProfilePart.health ? Icons.lock_outline : Icons.lock_person_outlined,
              title: careProfilePartTitle(p, _child),
              subtitle: '${_count(p)}. Parents only',
              onTap: () => unawaited(_openPart(p)),
            ),
          const SizedBox(height: 8),
          HubTile(
            key: const Key('openSharing'),
            icon: Icons.group_outlined,
            title: 'Who sees what',
            subtitle: d == null || d.people.isEmpty ? 'Nobody yet. Sharing between phones is not built' : '${d.people.length} on this phone. Sharing between phones is not built',
            onTap: () => unawaited(_go(CareProfileSharingScreen(
              service: widget.service, plans: widget.plans, principal: widget.principal, childName: _child, byName: widget.byName,
              meds: widget.meds, clock: widget.clock,
            ))),
          ),
          HubTile(
            key: const Key('openPlans'),
            icon: Icons.photo_library_outlined,
            title: "Photos of a doctor's plan",
            subtitle: _photos == 0 ? 'Kept sealed on this phone' : '$_photos kept sealed on this phone',
            onTap: () => unawaited(_go(CareProfilePlansScreen(plans: widget.plans, principal: widget.principal, byName: widget.byName, photoSource: widget.photoSource ?? pickPlanPhoto))),
          ),
          HubTile(
            key: const Key('openSheet'),
            icon: Icons.print_outlined,
            title: 'Sheet for the doctor',
            subtitle: 'One page, built from what you wrote',
            onTap: () => unawaited(_go(CareProfileSheetScreen(
              service: widget.service, plans: widget.plans, principal: widget.principal, childName: _child,
              meds: widget.meds, emergency: widget.emergency, verifyPin: widget.verifyPin, clock: widget.clock,
            ))),
          ),
          HubTile(
            key: const Key('openBirthday'),
            icon: Icons.cake_outlined,
            title: "$_child's birthday",
            subtitle: bm == null ? 'Optional. For the yearly "still right?"' : 'Month $bm, day ${d?.birthDay}',
            onTap: () => unawaited(_birthday()),
          ),
          const Divider(height: 28),
          SwitchListTile(
            key: const Key('teenPreview'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Preview a teen\'s "My health sheet"'),
            subtitle: const Text('Off. Nothing is shown on any child\'s device: whether a teen should have one is still to be decided.'),
            value: d?.teenPreview ?? false,
            onChanged: d == null ? null : (bool v) async {
              await widget.service.setTeenPreview(widget.principal, v);
              await _load();
            },
          ),
          if (d != null && d.teenPreview && age != null && age >= 13 && age <= 17)
            OutlinedButton(
              key: const Key('teenSeeSheet'),
              onPressed: () => unawaited(_go(CareProfileTeenSheetScreen(doc: d, meds: _meds, childName: _child, age: age))),
              child: const Text('See the sheet a teen would get'),
            ),
          if (d != null && d.teenPreview && (age == null || age < 13 || age > 17))
            const Text('A teen sheet applies from 13 to 17.', key: Key('teenNotTeen')),
        ]),
      ),
    );
  }
}

// ================================================================ one part ===
class CareProfilePartScreen extends StatefulWidget {
  const CareProfilePartScreen({
    super.key,
    required this.service,
    required this.principal,
    required this.part,
    this.childName = 'her',
    this.byName,
    this.verifyPin,
    this.clock,
  });
  final CareProfileService service;
  final FamilyPrincipal? principal;
  final CareProfilePart part;
  final String childName;
  final String? byName;
  final Future<bool> Function(String pin)? verifyPin;
  final DateTime Function()? clock;

  @override
  State<CareProfilePartScreen> createState() => _PartState();
}

class _PartState extends State<CareProfilePartScreen> {
  CareProfileDoc? _doc;
  bool _gated = false;
  bool _refused = false;
  bool _showAway = false;

  String get _me => (widget.principal?.userId as String?) ?? '';

  @override
  void initState() {
    super.initState();
    // After the first frame: the PIN box is a dialog, and a route cannot be pushed while this screen is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  @override
  void dispose() {
    if (widget.part.locked) widget.service.lock();
    super.dispose();
  }

  Future<void> _open() async {
    if (!canEditStructure(widget.principal)) {
      setState(() => _refused = true);
      return;
    }
    if (widget.part.locked && !widget.service.isUnlocked) {
      // The dialog hands the PIN to the service, which opens the part only if the guardian PIN check accepts it.
      final bool ok = await _askPin(
        context,
        widget.verifyPin == null ? null : (String pin) => widget.service.unlock(widget.principal, widget.verifyPin, pin),
      );
      if (!ok) {
        if (mounted) unawaited(Navigator.of(context).maybePop());
        return;
      }
    }
    await _reload();
  }

  Future<void> _reload() async {
    try {
      final CareProfileDoc d = await widget.service.read(widget.principal);
      if (mounted) {
        setState(() {
          _doc = d;
          _gated = true;
        });
      }
    } on CareProfileRefused {
      if (mounted) setState(() => _refused = true);
    }
  }

  Future<void> _write({CpEntry? existing, String? versionOf}) async {
    final TextEditingController title = TextEditingController(text: existing?.title ?? '');
    final TextEditingController text = TextEditingController(text: existing?.text ?? '');
    String? err;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AlertDialog(
          title: Text(existing != null ? 'Change what you wrote' : (versionOf != null ? 'Write my version' : 'Add to ${careProfilePartTitle(widget.part, widget.childName)}')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              if (versionOf == null)
                TextField(key: const Key('entryTitle'), controller: title, maxLength: cpMaxTitleChars, decoration: const InputDecoration(labelText: 'A short name (optional)')),
              TextField(key: const Key('entryText'), controller: text, maxLength: cpMaxTextChars, maxLines: 8, minLines: 3, autofocus: true, decoration: const InputDecoration(labelText: 'In your own words')),
              if (err != null) Text(err!, key: const Key('entryError')),
            ]),
          ),
          actions: <Widget>[
            TextButton(key: const Key('entryCancel'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              key: const Key('entrySave'),
              onPressed: () async {
                final CareResult<Object?> r = existing != null
                    ? await widget.service.editEntry(widget.principal, existing.id, text.text, title: title.text, byName: widget.byName)
                    : versionOf != null
                        ? await widget.service.addMyVersion(widget.principal, versionOf, text.text, byName: widget.byName)
                        : await widget.service.addEntry(widget.principal, widget.part, text.text, title: title.text, byName: widget.byName);
                if (r.ok) {
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } else {
                  set(() => err = r.reason == 'tone'
                      ? '${cpRefusalText('tone')} (${(r.detail?['found'] as List<Object?>? ?? const <Object?>[]).join(', ')}) $careProfileToneGuidance'
                      : _refusal(r));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _history(CpEntry e) => showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('What changed'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('A plain note so the grown-ups can see each other\'s changes. It is short on purpose, it is not a record of anything, and it is not exported.', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final CpRevision r in e.revisions.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${r.byName.isEmpty ? cpUnnamedGuardian : r.byName} changed this on ${cpDate(r.at)}. It used to say: ${r.text}'),
                ),
            ]),
          ),
          actions: <Widget>[TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
        ),
      );

  Future<void> _do(Future<CareResult<Object?>> Function() f) async {
    final CareResult<Object?> r = await f();
    if (!mounted) return;
    if (!r.ok) _snack(context, _refusal(r));
    await _reload();
  }

  bool _mine(CpEntry e) => e.byId == _me || (e.fromBinderId != null && e.byId.isEmpty);

  Widget _entryCard(CpEntry e, {bool inGroup = false, bool away = false}) => Card(
        key: ValueKey<String>('entry-${e.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            if (e.title.isNotEmpty) Text(e.title, style: Theme.of(context).textTheme.titleMedium),
            Text(e.text),
            const SizedBox(height: 4),
            Text(cpWrittenBy(e), key: ValueKey<String>('by-${e.id}'), style: Theme.of(context).textTheme.bodySmall),
            Wrap(spacing: 8, children: <Widget>[
              if (away)
                TextButton(key: ValueKey<String>('back-${e.id}'), onPressed: () => unawaited(_do(() => widget.service.bringBack(widget.principal, e.id, byName: widget.byName))), child: const Text('Bring it back'))
              else ...<Widget>[
                if (inGroup)
                  FilledButton.tonal(key: ValueKey<String>('use-${e.id}'), onPressed: () => unawaited(_do(() => widget.service.settle(widget.principal, e.id, byName: widget.byName))), child: const Text('Use this one')),
                if (_mine(e)) TextButton(key: ValueKey<String>('edit-${e.id}'), onPressed: () => unawaited(_write(existing: e)), child: const Text('Change')),
                if (!_mine(e) && e.title.isNotEmpty && !inGroup)
                  TextButton(key: ValueKey<String>('mine-${e.id}'), onPressed: () => unawaited(_write(versionOf: e.id)), child: const Text('Write my version')),
                if (e.revisions.isNotEmpty) TextButton(key: ValueKey<String>('hist-${e.id}'), onPressed: () => unawaited(_history(e)), child: Text('What changed (${e.revisions.length})')),
                if (_mine(e))
                  TextButton(key: ValueKey<String>('away-${e.id}'), onPressed: () async {
                    if (!await confirmPutAway(context, 'Put away "${e.title.isEmpty ? 'this' : e.title}"?', go: 'Put it away')) return;
                    await _do(() => widget.service.putAway(widget.principal, e.id, byName: widget.byName));
                  }, child: const Text('Put away')),
              ],
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_refused || !canEditStructure(widget.principal)) return const CareProfileNotForYou();
    final CareProfileDoc? d = _doc;
    final String title = careProfilePartTitle(widget.part, widget.childName);
    if (d == null || !_gated) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: const SafeArea(child: Center(child: Text('This part is closed.', key: Key('partClosed')))));
    }
    final List<List<CpEntry>> groups = cpDisagreements(d, widget.part);
    final Set<String> grouped = <String>{for (final List<CpEntry> g in groups) for (final CpEntry e in g) e.id};
    final List<CpEntry> plain = <CpEntry>[for (final CpEntry e in cpEntriesOf(d, widget.part)) if (!grouped.contains(e.id)) e];
    final List<CpEntry> away = cpEntriesOf(d, widget.part, retired: true);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(key: const Key('addEntry'), onPressed: () => unawaited(_write()), icon: const Icon(Icons.add), label: const Text('Add')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
          _note(context, '${careProfilePartHint(widget.part)} $careProfileLocalNote', key: const Key('partBanner')),
          if (widget.part.locked)
            _note(context, 'Open for a few minutes after your PIN, then it closes again. The file is sealed with this phone\'s own key; your PIN decides who gets to see it here.', key: const Key('lockedNote'), icon: Icons.lock_outline),
          if (groups.isEmpty && plain.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing written yet. Add what you know, in your own words.', key: Key('partEmpty'))),
          for (final List<CpEntry> g in groups) ...<Widget>[
            _note(context, 'These differ${g.first.title.isEmpty ? '' : ' (${g.first.title})'}. Both are shown until you agree.', key: ValueKey<String>('differ-${g.first.id}'), icon: Icons.compare_arrows, warn: true),
            for (final CpEntry e in g) _entryCard(e, inGroup: true),
          ],
          for (final CpEntry e in plain) _entryCard(e),
          if (away.isNotEmpty)
            TextButton(key: const Key('showAway'), onPressed: () => setState(() => _showAway = !_showAway), child: Text(_showAway ? 'Hide put-away entries' : 'Put away (${away.length})')),
          if (_showAway) for (final CpEntry e in away) _entryCard(e, away: true),
        ]),
      ),
    );
  }
}

// ================================================================ who sees what ===
class CareProfileSharingScreen extends StatefulWidget {
  const CareProfileSharingScreen({
    super.key,
    required this.service,
    required this.plans,
    required this.principal,
    this.childName = 'her',
    this.byName,
    this.meds,
    this.clock,
  });
  final CareProfileService service;
  final CarePlanPhotoService plans;
  final FamilyPrincipal? principal;
  final String childName;
  final String? byName;
  final CareService? meds;
  final DateTime Function()? clock;

  @override
  State<CareProfileSharingScreen> createState() => _SharingState();
}

class _SharingState extends State<CareProfileSharingScreen> {
  CareProfileDoc? _doc;
  bool _refused = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final CareProfileDoc d = await widget.service.read(widget.principal);
      if (mounted) setState(() => _doc = d);
    } on CareProfileRefused {
      if (mounted) setState(() => _refused = true);
    }
  }

  Future<void> _do(Future<CareResult<Object?>> Function() f) async {
    final CareResult<Object?> r = await f();
    if (!mounted) return;
    if (!r.ok) _snack(context, _refusal(r));
    await _reload();
  }

  Future<void> _add() async {
    final TextEditingController name = TextEditingController();
    CpPersonKind kind = CpPersonKind.carer;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AlertDialog(
          title: const Text('Add a person'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            TextField(key: const Key('personName'), controller: name, maxLength: cpMaxNameChars, autofocus: true, decoration: const InputDecoration(labelText: 'Their name')),
            DropdownButton<CpPersonKind>(
              key: const Key('personKind'),
              isExpanded: true,
              value: kind,
              items: <DropdownMenuItem<CpPersonKind>>[for (final CpPersonKind k in CpPersonKind.values) DropdownMenuItem<CpPersonKind>(value: k, child: Text(cpPersonKindTitle(k)))],
              onChanged: (CpPersonKind? v) => set(() => kind = v ?? kind),
            ),
            const Text('This only sets what "Show as" on this phone shows them. Nothing is sent.'),
          ]),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(key: const Key('personSave'), onPressed: () async {
              final CareResult<String> r = await widget.service.addPerson(widget.principal, name.text, kind, byName: widget.byName);
              if (!ctx.mounted) return;
              if (r.ok) {
                Navigator.of(ctx).pop(true);
              } else {
                _snack(ctx, _refusal(r));
              }
            }, child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true) await _reload();
  }

  String _until(CpGrant g) {
    if (g.until == null) return 'until you take it back';
    final DateTime l = g.until!.toLocal();
    return 'until ${cpDate(l)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _row(CpPerson p) {
    final DateTime now = _now();
    return Card(
      key: ValueKey<String>('person-${p.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(p.name, style: Theme.of(context).textTheme.titleMedium),
          Text(cpPersonKindTitle(p.kind), style: Theme.of(context).textTheme.bodySmall),
          for (final CareProfilePart part in CareProfilePart.values.where((CareProfilePart x) => x.shareable))
            Builder(builder: (BuildContext context) {
              final bool allowed = cpMayGrant(p.kind, part);
              final CpGrant? g = p.grants[part];
              final bool on = g != null && g.activeAt(now);
              final String sub = !allowed
                  ? 'Not for this kind of person'
                  : g == null
                      ? 'Not shown'
                      : (on ? 'Shown ${_until(g)}' : 'Ended');
              return Row(children: <Widget>[
                Expanded(
                  child: SwitchListTile(
                    key: ValueKey<String>('grant-${p.id}-${part.name}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(careProfilePartTitle(part, widget.childName)),
                    subtitle: Text(sub),
                    value: on,
                    onChanged: allowed
                        ? (bool v) => unawaited(_do(() => widget.service.setGrant(widget.principal, p.id, part, on: v)))
                        : null,
                  ),
                ),
                if (allowed)
                  PopupMenuButton<String>(
                    key: ValueKey<String>('box-${p.id}-${part.name}'),
                    tooltip: 'How long',
                    icon: const Icon(Icons.timer_outlined),
                    onSelected: (String v) {
                      final DateTime n = _now().toUtc();
                      final DateTime? until = switch (v) {
                        'tonight' => cpTonightEnds(_now()),
                        'day' => n.add(const Duration(hours: 24)),
                        'week' => n.add(const Duration(days: 7)),
                        _ => null,
                      };
                      unawaited(_do(() => widget.service.setGrant(widget.principal, p.id, part, until: until)));
                    },
                    itemBuilder: (BuildContext c) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'tonight', child: Text('Just tonight (until 6 in the morning)')),
                      PopupMenuItem<String>(value: 'day', child: Text('24 hours')),
                      PopupMenuItem<String>(value: 'week', child: Text('7 days')),
                      PopupMenuItem<String>(value: 'open', child: Text('Until I take it back')),
                    ],
                  ),
              ]);
            }),
          Wrap(spacing: 8, children: <Widget>[
            FilledButton.tonal(key: ValueKey<String>('tonight-${p.id}'), onPressed: () => unawaited(_do(() => widget.service.grantTonight(widget.principal, p.id))), child: const Text('Show for tonight')),
            OutlinedButton(
              key: ValueKey<String>('showAs-${p.id}'),
              onPressed: () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CareProfileViewAsScreen(
                    service: widget.service, plans: widget.plans, principal: widget.principal, personId: p.id,
                    childName: widget.childName, meds: widget.meds, clock: widget.clock)))),
              child: Text('Show as ${p.name}'),
            ),
            TextButton(key: ValueKey<String>('removePerson-${p.id}'), onPressed: () async {
              if (!await confirmPutAway(context, 'Remove ${p.name}?', go: 'Remove')) return;
              await _do(() => widget.service.removePerson(widget.principal, p.id));
            }, child: const Text('Remove')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_refused || !canEditStructure(widget.principal)) return const CareProfileNotForYou();
    final CareProfileDoc? d = _doc;
    return Scaffold(
      appBar: AppBar(title: const Text('Who sees what')),
      floatingActionButton: FloatingActionButton.extended(key: const Key('addPerson'), onPressed: () => unawaited(_add()), icon: const Icon(Icons.person_add_alt_outlined), label: const Text('Add a person')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
          _note(context, careProfileNoSyncNote, key: const Key('sharingNoSync'), warn: true),
          _note(context, '${widget.childName} never sees any of this. Health history and Moods and habits are for parents only and cannot be shared with anyone. A view-only person can be shown Keep ${widget.childName} safe and nothing else. A grown-up with a say in her care always sees everything, including what is hidden from someone else.', key: const Key('sharingRules')),
          if (d != null && d.people.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nobody added yet.', key: Key('peopleEmpty'))),
          if (d != null) for (final CpPerson p in d.people) _row(p),
        ]),
      ),
    );
  }
}

// ================================================================ show as ===
class CareProfileViewAsScreen extends StatefulWidget {
  const CareProfileViewAsScreen({
    super.key,
    required this.service,
    required this.plans,
    required this.principal,
    required this.personId,
    this.childName = 'her',
    this.meds,
    this.clock,
  });
  final CareProfileService service;
  final CarePlanPhotoService plans;
  final FamilyPrincipal? principal;
  final String personId;
  final String childName;
  final CareService? meds;
  final DateTime Function()? clock;

  @override
  State<CareProfileViewAsScreen> createState() => _ViewAsState();
}

class _ViewAsState extends State<CareProfileViewAsScreen> {
  CareProfileDoc? _doc;
  CareDoc? _med;
  List<CpPlanPhoto> _photos = const <CpPlanPhoto>[];
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final CareProfileDoc d = await widget.service.read(widget.principal);
      CareDoc? m;
      if (widget.meds != null) {
        try {
          m = await widget.meds!.read(widget.principal);
        } on CareLocalRefused {
          m = null;
        }
      }
      final List<CpPlanPhoto> ph = await widget.plans.list(widget.principal);
      if (mounted) {
        setState(() {
          _doc = d;
          _med = m;
          _photos = ph;
        });
      }
    } on CareProfileRefused {
      if (mounted) setState(() => _refused = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_refused || !canEditStructure(widget.principal)) return const CareProfileNotForYou();
    final CareProfileDoc? d = _doc;
    if (d == null) return Scaffold(appBar: AppBar(), body: const SafeArea(child: SizedBox.shrink()));
    CpPerson? person;
    for (final CpPerson p in d.people) {
      if (p.id == widget.personId) person = p;
    }
    if (person == null) return Scaffold(appBar: AppBar(), body: const SafeArea(child: Center(child: Text('That person is not here any more.'))));
    final DateTime now = (widget.clock ?? DateTime.now)();
    final List<CpPartView> parts = cpViewFor(d, person, now, meds: _med);
    final bool safe = parts.any((CpPartView v) => v.part == CareProfilePart.safe);
    return Scaffold(
      appBar: AppBar(title: Text('Shown to ${person.name}')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          _note(context, 'This is what ${person.name} may be shown right now. It follows what you chose and the time boxes. Leaving this screen is not locked: to hand over the phone, use your phone\'s own screen pinning. $careProfileNoSyncNote', key: const Key('viewAsNote'), warn: true),
          if (parts.isEmpty) Text('Nothing is shared with ${person.name} right now.', key: const Key('viewAsEmpty')),
          for (final CpPartView v in parts) ...<Widget>[
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(careProfilePartTitle(v.part, widget.childName), style: Theme.of(context).textTheme.titleMedium)),
            if (v.part == CareProfilePart.heads && v.heads != null)
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('${v.heads!.text}\nwritten by ${v.heads!.byName.isEmpty ? cpUnnamedGuardian : v.heads!.byName}, today', key: const Key('viewAsHeads')))),
            if (v.part == CareProfilePart.meds)
              if (v.medicines.isEmpty) const Text('None written.') else for (final CpMedLine m in v.medicines) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(m.text))),
            for (final CpEntry e in v.entries)
              Card(
                child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  if (e.title.isNotEmpty) Text(e.title, style: Theme.of(context).textTheme.titleSmall),
                  Text(e.text),
                  Text(cpWrittenBy(e), style: Theme.of(context).textTheme.bodySmall),
                ])),
              ),
            if (v.part != CareProfilePart.heads && v.part != CareProfilePart.meds && v.entries.isEmpty) const Text('Nothing written.'),
          ],
          if (safe && _photos.isNotEmpty) ...<Widget>[
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text("A doctor's plan", style: Theme.of(context).textTheme.titleMedium)),
            for (final CpPlanPhoto p in _photos) _PlanCard(photo: p),
          ],
        ]),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.photo, this.onRemove});
  final CpPlanPhoto photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey<String>('plan-${photo.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(photo.label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Image.memory(photo.bytes, fit: BoxFit.contain, errorBuilder: (BuildContext c, Object e, StackTrace? s) => const Center(child: Icon(Icons.image_outlined))),
            ),
            Text('kept by ${photo.byName.isEmpty ? cpUnnamedGuardian : photo.byName}, ${cpDate(photo.at)}', style: Theme.of(context).textTheme.bodySmall),
            if (onRemove != null) TextButton(key: ValueKey<String>('removePlan-${photo.id}'), onPressed: onRemove, child: const Text('Remove')),
          ]),
        ),
      );
}

// ================================================================ doctor's plan photos ===
class CareProfilePlansScreen extends StatefulWidget {
  const CareProfilePlansScreen({super.key, required this.plans, required this.principal, this.byName, required this.photoSource});
  final CarePlanPhotoService plans;
  final FamilyPrincipal? principal;
  final String? byName;
  final PlanPhotoSource photoSource;

  @override
  State<CareProfilePlansScreen> createState() => _PlansState();
}

class _PlansState extends State<CareProfilePlansScreen> {
  List<CpPlanPhoto> _photos = const <CpPlanPhoto>[];
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<CpPlanPhoto> p = await widget.plans.list(widget.principal);
      if (mounted) setState(() => _photos = p);
    } on CareProfileRefused {
      if (mounted) setState(() => _refused = true);
    }
  }

  Future<void> _add() async {
    final TextEditingController label = TextEditingController();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Add a photo of a plan'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Text('You choose the photo and you name it. It is kept sealed on this phone. The app does not read it or turn it into text.'),
          TextField(key: const Key('planLabel'), controller: label, maxLength: cpMaxLabelChars, autofocus: true, decoration: const InputDecoration(labelText: 'What is it? (for example, the asthma plan)')),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(key: const Key('planChoose'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Choose a photo')),
        ],
      ),
    );
    final String text = label.text;
    if (go != true || !mounted) return;
    final Uint8List? bytes = await widget.photoSource();
    if (bytes == null || !mounted) return;
    final CareResult<String> r = await widget.plans.add(widget.principal, text, bytes, byName: widget.byName ?? '');
    if (!mounted) return;
    if (!r.ok) _snack(context, _refusal(r));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_refused || !canEditStructure(widget.principal)) return const CareProfileNotForYou();
    return Scaffold(
      appBar: AppBar(title: const Text("Photos of a doctor's plan")),
      floatingActionButton: FloatingActionButton.extended(key: const Key('addPlan'), onPressed: () => unawaited(_add()), icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add a photo')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
          _note(context, 'Photos you chose, kept sealed on this phone, never in the gallery and never in her app. Up to $cpMaxPlanPhotos. The app does not take, change or read them.', key: const Key('plansBanner'), icon: Icons.shield_outlined),
          if (_photos.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No photos yet.', key: Key('plansEmpty'))),
          for (final CpPlanPhoto p in _photos)
            _PlanCard(photo: p, onRemove: () async {
              if (!await confirmPutAway(context, 'Remove "${p.label}"?', go: 'Remove')) return;
              await widget.plans.remove(widget.principal, p.id);
              await _load();
            }),
        ]),
      ),
    );
  }
}

// ================================================================ the doctor sheet ===
class CareProfileSheetScreen extends StatefulWidget {
  const CareProfileSheetScreen({
    super.key,
    required this.service,
    required this.plans,
    required this.principal,
    this.childName = 'her',
    this.meds,
    this.emergency,
    this.verifyPin,
    this.clock,
  });
  final CareProfileService service;
  final CarePlanPhotoService plans;
  final FamilyPrincipal? principal;
  final String childName;
  final CareService? meds;
  final EmergencyCardService? emergency;
  final Future<bool> Function(String pin)? verifyPin;
  final DateTime Function()? clock;

  @override
  State<CareProfileSheetScreen> createState() => _SheetState();
}

class _SheetState extends State<CareProfileSheetScreen> {
  String? _text;
  bool _refused = false;
  bool _everyday = false, _helps = false, _health = false, _moods = false;
  bool _relocked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_build());
  }

  @override
  void dispose() {
    widget.service.lock();
    super.dispose();
  }

  Future<void> _build() async {
    // The PIN window lapsed since a locked chip was turned on: switch it off and say so, rather than leave it
    // looking selected while its text has quietly gone.
    if (!widget.service.isUnlocked && (_health || _moods)) {
      _health = false;
      _moods = false;
      _relocked = true;
    }
    try {
      final CareProfileDoc d = await widget.service.read(widget.principal);
      CareDoc? m;
      if (widget.meds != null) {
        try {
          m = await widget.meds!.read(widget.principal);
        } on CareLocalRefused {
          m = null;
        }
      }
      LocalEmergencyCard? card;
      if (widget.emergency != null) {
        try {
          card = (await widget.emergency!.read(widget.principal)).card;
        } on EcRefused {
          card = null;
        }
      }
      final List<CpPlanPhoto> ph = await widget.plans.list(widget.principal);
      final String t = cpDoctorSheetText(
        childName: widget.childName,
        doc: d,
        meds: m,
        card: card,
        planPhotoLabels: <String>[for (final CpPlanPhoto p in ph) p.label],
        options: CpSheetOptions(everyday: _everyday, helps: _helps, health: _health, moods: _moods),
        unlocked: widget.service.isUnlocked,
        now: (widget.clock ?? DateTime.now)(),
      );
      if (mounted) setState(() => _text = t);
    } on CareProfileRefused {
      if (mounted) setState(() => _refused = true);
    }
  }

  Future<void> _toggle(String which, bool v) async {
    if (v && (which == 'health' || which == 'moods') && !widget.service.isUnlocked) {
      final bool ok = await _askPin(
        context,
        widget.verifyPin == null ? null : (String pin) => widget.service.unlock(widget.principal, widget.verifyPin, pin),
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() {
      if (v && (which == 'health' || which == 'moods')) _relocked = false;
      switch (which) {
        case 'everyday':
          _everyday = v;
        case 'helps':
          _helps = v;
        case 'health':
          _health = v;
        case 'moods':
          _moods = v;
      }
    });
    await _build();
  }

  @override
  Widget build(BuildContext context) {
    if (_refused || !canEditStructure(widget.principal)) return const CareProfileNotForYou();
    final String? text = _text;
    return Scaffold(
      appBar: AppBar(title: const Text('Sheet for the doctor')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          _note(context, 'Built only from what grown-ups wrote, with who wrote it and when. The app adds no advice. Copy it to print or send it yourself: nothing is sent from here.', key: const Key('sheetBanner')),
          if (_relocked) _note(context, 'The PIN window closed, so Health history and Moods are off the sheet. Turn them on to enter your PIN again.', key: const Key('sheetRelocked'), warn: true),
          Wrap(spacing: 8, children: <Widget>[
            FilterChip(key: const Key('optEveryday'), label: Text(careProfilePartTitle(CareProfilePart.everyday, widget.childName)), selected: _everyday, onSelected: (bool v) => unawaited(_toggle('everyday', v))),
            FilterChip(key: const Key('optHelps'), label: const Text('What helps'), selected: _helps, onSelected: (bool v) => unawaited(_toggle('helps', v))),
            FilterChip(key: const Key('optHealth'), label: const Text('Health history (PIN)'), selected: _health, onSelected: (bool v) => unawaited(_toggle('health', v))),
            FilterChip(key: const Key('optMoods'), label: const Text('Moods and habits (PIN)'), selected: _moods, onSelected: (bool v) => unawaited(_toggle('moods', v))),
          ]),
          const SizedBox(height: 12),
          if (text != null)
            Container(
              key: const Key('doctorSheet'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
              child: SelectableText(text, style: const TextStyle(color: Colors.black87, height: 1.4)),
            ),
          const SizedBox(height: 12),
          if (text != null)
            FilledButton.icon(
              key: const Key('copySheet'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy this text'),
              onPressed: () async {
                final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: text));
                m.showSnackBar(const SnackBar(content: Text("Copied to this phone's clipboard. If it includes Health history or Moods, clear the clipboard after you paste.")));
              },
            ),
        ]),
      ),
    );
  }
}

// ================================================================ a teen's sheet (preview only) ===
/// What a teen's "My health sheet" WOULD hold, shown to a grown-up. There is no door to it on any child's device.
class CareProfileTeenSheetScreen extends StatelessWidget {
  const CareProfileTeenSheetScreen({super.key, required this.doc, required this.meds, required this.childName, required this.age});
  final CareProfileDoc doc;
  final CareDoc? meds;
  final String childName;
  final int age;

  @override
  Widget build(BuildContext context) {
    final ({List<CpEntry> entries, List<CpMedLine> medicines})? s = cpTeenSheet(doc, meds, age: age);
    return Scaffold(
      appBar: AppBar(title: const Text('A teen\'s health sheet')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          _note(context, 'A preview for you. It is not on any child\'s device, and it will not be until the decision about it is made. It would hold only Keep $childName safe and the medicines list.', key: const Key('teenNote'), warn: true),
          if (s == null) const Text('Not available.', key: Key('teenOff')),
          if (s != null) ...<Widget>[
            for (final CpEntry e in s.entries) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('${e.title.isEmpty ? '' : '${e.title}: '}${e.text}\n${cpWrittenBy(e)}'))),
            for (final CpMedLine m in s.medicines) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(m.text))),
          ],
        ]),
      ),
    );
  }
}
