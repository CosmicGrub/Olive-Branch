// OLIVE BRANCH — the guardian's "Accessibility for her device" screen. No longer
// UNVERIFIED — verified by CI (client/test/access_screen_test.dart). MASTERFILE
// §8.4, §8.8.5, §8.13, §8.21.
//
// Reached from the Settings hub (Her group), inside the guardian shell, the way
// every other settings screen is: a grown-up has already passed the guardian
// gate to be here, and her own app has no path to it at any depth (§8.1).
//
// Five switches, each written plainly and each honest about what it does:
//   * read aloud everywhere — a speaker on tiles and story pages, long-press to
//     hear a tile; never starts by itself;
//   * reduce motion — everything that moves after a tap simply appears;
//   * roomier reading — more space between letters, words and lines, left-aligned;
//   * larger targets — her touch targets from 64dp to 80dp;
//   * captions — NOT BUILT. The switch records a wish and the screen says, in
//     words, that nothing shows because of it yet.
//
// Everything is kept on this device (LocalStore area `access`). It says so, and
// says what that means when her device is a different phone.
import 'package:flutter/material.dart';

import 'access_scope.dart';
import 'access_settings.dart';

class AccessScreen extends StatefulWidget {
  const AccessScreen({super.key, required this.childName, this.controller, this.childAge});
  final String childName;

  /// Null means the app's shared controller.
  final AccessController? controller;

  /// For the read-aloud default line only.
  final int? childAge;

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen> {
  late final AccessController _c = widget.controller ?? sharedAccess;
  String? _note;

  @override
  void initState() {
    super.initState();
    _c.ageYears ??= widget.childAge;
    if (!_c.loaded) _c.load();
  }

  Future<void> _set(AccessSettings Function(AccessSettings) change) async {
    final bool kept = await _c.update(change);
    if (!mounted) return;
    setState(() => _note = kept
        ? 'Saved on this device.'
        : 'Changed for now, but this device could not keep it. It will be lost on restart.');
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.childName;
    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility for her device')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (BuildContext context, Widget? _) {
            final AccessSettings s = _c.value;
            final int? age = _c.ageYears ?? widget.childAge;
            final bool readOn = s.readAloudFor(age);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(
                  'How $name\'s screens read, move and respond. These are kept on this device, '
                  'and only ever read by her app. If her device is a different phone, set them there too.',
                  key: const Key('accessIntro'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _Row(
                  rowKey: const Key('accessReadAloud'),
                  icon: Icons.volume_up_outlined,
                  title: 'Read aloud everywhere',
                  subtitle: s.readAloud == null
                      ? 'Following her age: on for under 8, off from 8. '
                          'A small speaker on tiles and stories; long-press a tile to hear it. '
                          'Never starts by itself.'
                      : 'A small speaker on tiles and stories; long-press a tile to hear it. '
                          'Never starts by itself.',
                  value: readOn,
                  onChanged: (bool v) => _set((AccessSettings a) => a.copyWith(readAloud: v)),
                ),
                if (s.readAloud != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('accessReadAloudAge'),
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: () => _set((AccessSettings a) => a.copyWith(clearReadAloud: true)),
                      child: const Text('Follow her age again'),
                    ),
                  ),
                _Row(
                  rowKey: const Key('accessReduceMotion'),
                  icon: Icons.motion_photos_off_outlined,
                  title: 'Reduce motion',
                  subtitle: 'Anything that moves after a tap just appears instead. '
                      'Her phone\'s own "remove animations" choice is always respected too.',
                  value: s.reduceMotion,
                  onChanged: (bool v) => _set((AccessSettings a) => a.copyWith(reduceMotion: v)),
                ),
                _Row(
                  rowKey: const Key('accessRoomier'),
                  icon: Icons.format_line_spacing,
                  title: 'Roomier reading',
                  subtitle: 'More space between letters, words and lines, and reading text kept '
                      'to the left. The same typeface: evidence for special "dyslexia fonts" is mixed.',
                  value: s.roomierReading,
                  onChanged: (bool v) => _set((AccessSettings a) => a.copyWith(roomierReading: v)),
                ),
                if (s.roomierReading) const _RoomyPreview(),
                _Row(
                  rowKey: const Key('accessLarger'),
                  icon: Icons.touch_app_outlined,
                  title: 'Larger targets',
                  subtitle: 'Her buttons and tiles at least 80 dp instead of 64 dp, for small or '
                      'unsteady hands.',
                  value: s.largerTargets,
                  onChanged: (bool v) => _set((AccessSettings a) => a.copyWith(largerTargets: v)),
                ),
                _Row(
                  rowKey: const Key('accessCaptions'),
                  icon: Icons.closed_caption_outlined,
                  title: 'Captions',
                  subtitle: captionsBuilt
                      ? 'Captions on calls and recordings.'
                      : 'Not built yet. This records that you would like them; nothing shows '
                          'because of it today.',
                  value: s.captions,
                  onChanged: (bool v) => _set((AccessSettings a) => a.copyWith(captions: v)),
                ),
                _Row(
                  rowKey: const Key('accessVisualAlerts'),
                  icon: Icons.notifications_active_outlined,
                  title: 'Alerts she can see',
                  subtitle: 'An alert shows a picture and words that stay until she taps it, with a '
                      'gentle buzz, so nothing is ever sound only. Nothing flashes.',
                  value: s.visualAlerts,
                  onChanged: (bool v) => _set((AccessSettings a) => a.copyWith(visualAlerts: v)),
                ),
                if (_note != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(_note!, key: const Key('accessNote'))),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.rowKey, required this.icon, required this.title,
      required this.subtitle, required this.value, required this.onChanged});
  final Key rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: MergeSemantics(
          child: SwitchListTile(
            key: rowKey,
            secondary: Icon(icon),
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(subtitle),
            value: value,
            onChanged: onChanged,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      );
}

/// What roomier reading looks like, so the choice is made by eye.
class _RoomyPreview extends StatelessWidget {
  const _RoomyPreview();
  @override
  Widget build(BuildContext context) {
    final TextStyle? base = Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        key: const Key('accessRoomyPreview'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12)),
        child: Text('The fox went up the hill and sat down to rest.',
            textAlign: TextAlign.start, style: roomierStyle(base)),
      ),
    );
  }
}
