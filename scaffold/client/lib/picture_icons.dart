// OLIVE BRANCH — the drawings behind the picture library, and the picture-first
// widgets suites B and C share. No longer UNVERIFIED — verified by CI
// (client/test/picture_library_test.dart and client/test/rhythm_screens_test.dart).
//
// Material icons stand in for a commissioned, diverse picture set (an open owner
// decision). Swapping the set changes [pictureIcon] and nothing else.
//
// READ-ALOUD SEAM (SEAM(child-accessibility)). Every child tile takes an optional
// `speak` callback, the same `Future<void> Function(String)` shape child_home.dart
// and tts_channel.dart's buildSpeakCallback already use. When it is null a tile
// shows no speaker at all and nothing is spoken. When the child accessibility
// work lands, pass its speaker through ChildMoreScreen and every tile here gains
// read-aloud with no other change. Nothing in this file talks to a speech engine.
import 'package:flutter/material.dart';


typedef Speak = Future<void> Function(String text);

const Map<String, IconData> _icons = <String, IconData>{
  'wake-up': Icons.wb_sunny_outlined,
  'breakfast': Icons.free_breakfast_outlined,
  'get-dressed': Icons.checkroom_outlined,
  'teeth': Icons.sentiment_satisfied_outlined,
  'shoes': Icons.directions_walk,
  'coat': Icons.dry_cleaning_outlined,
  'bag': Icons.backpack_outlined,
  'bath': Icons.bathtub_outlined,
  'pyjamas': Icons.bedtime_outlined,
  'book': Icons.menu_book_outlined,
  'song': Icons.music_note,
  'cuddle': Icons.favorite_border,
  'lights-out': Icons.nightlight_outlined,
  'tidy': Icons.cleaning_services_outlined,
  'wash-hands': Icons.clean_hands_outlined,
  'snack': Icons.cookie_outlined,
  'drink': Icons.local_drink_outlined,
  'toilet': Icons.wc,
  'car': Icons.directions_car_outlined,
  'play': Icons.toys_outlined,
  'owl': Icons.pets_outlined,
  'teddy': Icons.smart_toy_outlined,
  'blanket': Icons.bed_outlined,
  'night-light': Icons.lightbulb_outline,
  'boots': Icons.umbrella_outlined,
  'lunch': Icons.lunch_dining_outlined,
  'bottle': Icons.water_drop_outlined,
  'toothbrush': Icons.brush_outlined,
  'library-book': Icons.auto_stories_outlined,
  'glasses': Icons.visibility_outlined,
  'door': Icons.door_front_door_outlined,
  'hall': Icons.meeting_room_outlined,
  'my-room': Icons.star_outline,
  'bed': Icons.single_bed_outlined,
  'window': Icons.window_outlined,
  'kitchen': Icons.kitchen_outlined,
  'bathroom': Icons.shower_outlined,
  'garden': Icons.yard_outlined,
  'grandparent': Icons.elderly_outlined,
  'aunt-uncle': Icons.people_outline,
  'teacher': Icons.school_outlined,
  'friend': Icons.handshake_outlined,
  'neighbour': Icons.home_outlined,
  'counsellor': Icons.support_agent_outlined,
  'sibling': Icons.family_restroom_outlined,
  'grown-up': Icons.person_outline,
  'worry-dark': Icons.dark_mode_outlined,
  'worry-noise': Icons.volume_up_outlined,
  'worry-apart': Icons.swap_horiz,
  'worry-new-place': Icons.home_work_outlined,
  'worry-tummy': Icons.healing_outlined,
  'worry-storm': Icons.thunderstorm_outlined,
  'worry-school': Icons.school_outlined,
  'worry-dream': Icons.cloud_outlined,
  'worry-other': Icons.more_horiz,
  'sunny': Icons.wb_sunny_outlined,
  'cloudy': Icons.cloud_outlined,
  'rainy': Icons.water_drop_outlined,
  'stormy': Icons.thunderstorm_outlined,
  'windy': Icons.air,
  'foggy': Icons.foggy,
  'sym-i': Icons.person_outline,
  'sym-want': Icons.back_hand_outlined,
  'sym-more': Icons.add_circle_outline,
  'sym-stop': Icons.front_hand_outlined,
  'sym-help': Icons.waving_hand_outlined,
  'sym-hurt': Icons.healing_outlined,
  'sym-tired': Icons.bedtime_outlined,
  'sym-play': Icons.toys_outlined,
  'sym-yes': Icons.check_circle_outline,
  'sym-no': Icons.cancel_outlined,
  'sym-eat': Icons.restaurant_outlined,
  'sym-drink': Icons.local_drink_outlined,
  'sym-toilet': Icons.wc,
  'sym-hug': Icons.favorite_border,
  'sym-look': Icons.visibility_outlined,
  'sym-all-done': Icons.done_all,
  'sym-bath': Icons.bathtub_outlined,
  'sym-book': Icons.menu_book_outlined,
  'sym-music': Icons.music_note,
  'sym-outside': Icons.park_outlined,
  'sym-sleep': Icons.bedtime_outlined,
  'sym-blanket': Icons.bed_outlined,
  'sym-owl': Icons.pets_outlined,
  'sym-home': Icons.home_outlined,
};

/// The icon for [id]; null for an id that is not in the library.
IconData? pictureIconOrNull(Object? id) => id is String ? _icons[id] : null;

IconData pictureIcon(Object? id) => pictureIconOrNull(id) ?? Icons.circle_outlined;

/// A picture on a soft rounded tile.
class PictureGlyph extends StatelessWidget {
  const PictureGlyph(this.id, {super.key, this.size = 56, this.soft = false});
  final String id;
  final double size;

  /// A calmer, paler drawing (a step already done).
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size + 20, height: size + 20,
        decoration: BoxDecoration(
            color: soft ? c.surfaceContainerHighest : c.primaryContainer,
            borderRadius: BorderRadius.circular(20)),
        child: Icon(pictureIcon(id), size: size, color: soft ? c.onSurfaceVariant : c.onPrimaryContainer),
      ),
    );
  }
}

/// A big, picture-first tap target (never under 64dp), with an optional quiet
/// read-aloud speaker (the SEAM above).
class PictureTile extends StatelessWidget {
  const PictureTile({
    super.key,
    required this.picture,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.soft = false,
    this.speak,
    this.showLabel = true,
    this.minHeight = 104,
  });
  final String picture;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool soft;
  final Speak? speak;
  final bool showLabel;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Semantics(
      button: true, selected: selected, label: label,
      child: Material(
        color: selected ? c.secondaryContainer : c.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: selected ? c.primary : c.outlineVariant, width: selected ? 3 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight < 64 ? 64 : minHeight, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(children: <Widget>[
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    PictureGlyph(picture, size: 40, soft: soft),
                    if (showLabel) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
                if (speak != null)
                  Positioned(
                    right: 0, top: 0,
                    child: SizedBox(
                      width: 48, height: 48,
                      child: IconButton(
                        tooltip: 'Hear $label',
                        icon: const Icon(Icons.volume_up_outlined),
                        onPressed: () => speak!(label),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Picture grid that wraps to the width it is given (344dp cover screen up).
class PictureGrid extends StatelessWidget {
  const PictureGrid({super.key, required this.children, this.minTile = 110});
  final List<Widget> children;
  final double minTile;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final int cols = (c.maxWidth / minTile).floor().clamp(2, 6);
        const double gap = 10;
        final double w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: <Widget>[
          for (final Widget ch in children) SizedBox(width: w, child: ch),
        ]);
      });
}

/// True when this subtree should not animate: the device asks for it, or a
/// guardian's "how the app feels" profile does (see [SensoryScope]).
bool reduceMotionOf(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A page for a gentle one-line sentence, used by the quiet states.
class QuietNote extends StatelessWidget {
  const QuietNote(this.text, {super.key, this.icon = Icons.lock_outline});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(children: <Widget>[
        Icon(icon, color: c.onSecondaryContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: c.onSecondaryContainer))),
      ]),
    );
  }
}
