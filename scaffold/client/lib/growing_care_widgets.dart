// OLIVE BRANCH — small shared pieces for the Growing (G) and Care (F) screens.
// No longer UNVERIFIED — verified by CI (client/test/growing_screens_test.dart and
// client/test/care_screens_test.dart). MASTERFILE section 8.17.
//
// Nothing here talks to a network. [PhotoSource] is the one door a photo comes
// in through: the app's default asks the photo picker for a SMALL image (320 px,
// compressed) so what is kept is a thumbnail, never a camera original; a test
// hands in bytes directly.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'growing_care_logic.dart';

/// Asks for one photo and returns its (small) bytes, or null if none was chosen.
typedef PhotoSource = Future<Uint8List?> Function();

/// The photo picker, asked for a small image. A cancelled or failed pick is null.
Future<Uint8List?> pickSmallPhoto() async {
  try {
    final XFile? x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 320, maxHeight: 320, imageQuality: 60);
    return x == null ? null : await x.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Smallest comfortable touch target for her side (MASTERFILE section 8.4).
const double childTarget = 64;

void showRefusal(BuildContext context, CareRefused e) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(e.message), duration: const Duration(seconds: 4)));
}

/// A kept photo, drawn small. A bad image shows a plain icon, never an error.
class ThumbImage extends StatelessWidget {
  const ThumbImage(this.bytes, {super.key, this.size = 72});
  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size, height: size,
          child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true,
              errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                  const Center(child: Icon(Icons.image_outlined))),
        ),
      );
}

/// The honest "where this lives" line shown on every screen of these suites.
class LocalOnlyBanner extends StatelessWidget {
  const LocalOnlyBanner(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: <Widget>[
            const Icon(Icons.phone_android_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text(text, key: const Key('localOnlyNote'))),
          ]),
        ),
      );
}

/// A yyyy-mm-dd text field with a calendar button beside it.
class IsoDateField extends StatelessWidget {
  const IsoDateField({
    super.key, required this.controller, required this.label, required this.today,
    this.future = false,
  });
  final TextEditingController controller;
  final String label;
  final String today;

  /// True when the date is for something ahead (a capsule): the calendar then
  /// opens on tomorrow and reaches up to 18 years out.
  final bool future;

  Future<void> _pick(BuildContext context) async {
    final DateTime base = DateTime.tryParse(controller.text) ?? DateTime.parse(today);
    final DateTime t = DateTime.parse(today);
    final DateTime first = future ? t.add(const Duration(days: 1)) : DateTime(t.year - 30);
    final DateTime last = future ? DateTime(t.year + maxCapsuleYearsAhead, t.month, t.day) : t;
    final DateTime? d = await showDatePicker(
        context: context,
        initialDate: base.isBefore(first) ? first : (base.isAfter(last) ? last : base),
        firstDate: first, lastDate: last);
    if (d != null) controller.text = isoOf(d);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          labelText: label, hintText: 'yyyy-mm-dd', border: const OutlineInputBorder(),
          suffixIcon: IconButton(
              key: Key('pick_${label.toLowerCase().replaceAll(' ', '_')}'),
              tooltip: 'Pick from a calendar', icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => _pick(context)),
        ),
      );
}

/// Asks before a thing is put away for good.
Future<bool> confirmPutAway(BuildContext context, String what, {String keep = 'Keep it', String go = 'Put it away'}) async {
  final bool? yes = await showDialog<bool>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      title: Text(what),
      content: const Text('It will be gone from this device.'),
      actions: <Widget>[
        TextButton(key: const Key('confirmKeep'), onPressed: () => Navigator.of(c).pop(false), child: Text(keep)),
        TextButton(key: const Key('confirmGo'), onPressed: () => Navigator.of(c).pop(true), child: Text(go)),
      ],
    ),
  );
  return yes ?? false;
}

/// One photo chooser row used by the guardian editors: shows the chosen photo
/// and lets a guardian pick or clear it.
class PhotoPickerRow extends StatelessWidget {
  const PhotoPickerRow({super.key, required this.bytes, required this.onPick, required this.onClear, this.label = 'Add a photo'});
  final Uint8List? bytes;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        if (bytes != null) ...<Widget>[ThumbImage(bytes!, size: 56), const SizedBox(width: 10)],
        OutlinedButton.icon(
            key: const Key('pickPhoto'), onPressed: onPick, icon: const Icon(Icons.photo_outlined),
            label: Text(bytes == null ? label : 'Change photo')),
        if (bytes != null) IconButton(key: const Key('clearPhoto'), tooltip: 'Remove photo', onPressed: onClear, icon: const Icon(Icons.close)),
      ]);
}
