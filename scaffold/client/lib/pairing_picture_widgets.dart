// OLIVE BRANCH — the small shared widgets of the pairing picture screens: the QR on a white tile, the posture-aware
// layout, the scanner frame, the nameless glyph tile, and the olive-branch mark. UNVERIFIED on a device; widget-tested
// headless (client/test/pairing_picture_screens_test.dart). Design: docs/planning/PERSISTENT-QR-PAIRING.md section 5.
//
// POSTURES (form_factors.dart postureFor): the picture is always the largest element, on a white tile with a quiet
// zone whatever the theme (a dark QR on a dark page does not scan).
//   phone / Fold cover (one column)  picture about 70% of the width, steps under it
//   wide (Fold inner, tablets, any landscape) picture left, steps right
//   Fold half-open (tabletop)        steps on the upper half, picture on the flat lower half
//   scanner                          tabletop: camera fills the upper half, controls below; else camera on top
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'access_scope.dart';
import 'form_factors.dart' as ff;
import 'pairing_match.dart';
import 'pairing_picture.dart';

/// What a camera view calls with each string it reads. The real one is [MobileScanner]; tests inject a fake.
typedef ScannerBuilder = Widget Function(BuildContext context, void Function(String raw) onRaw);

Widget defaultScannerBuilder(BuildContext context, void Function(String raw) onRaw) => MobileScanner(
      key: const Key('pictureScanner'),
      onDetect: (BarcodeCapture cap) {
        final String? raw = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
        if (raw != null) onRaw(raw);
      },
    );

/// The posture a box of this size is in.
ff.Posture postureOf(Size s) => ff.postureFor(ff.Viewport(w: s.width, h: s.height));

/// A QR on a white tile with a quiet zone, whatever the theme.
class PictureTile extends StatelessWidget {
  const PictureTile({super.key, required this.data, required this.size});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: PrettyQrView.data(key: const Key('pictureQr'), data: data, decoration: const PrettyQrDecoration(shape: PrettyQrSmoothSymbol(color: Colors.black))),
      );
}

/// Picture and steps, arranged for the box they are in.
class PictureLayout extends StatelessWidget {
  const PictureLayout({super.key, required this.picture, required this.steps, this.maxPicture = 420});

  /// Receives the side length the picture may use.
  final Widget Function(double size) picture;
  final Widget steps;
  final double maxPicture;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double w = c.maxWidth, h = c.maxHeight.isFinite ? c.maxHeight : 800;
        final ff.Posture p = postureOf(Size(w, h));
        if (p == ff.Posture.foldTabletop) {
          final double side = (h * 0.5 - 24).clamp(120.0, maxPicture);
          return Column(key: const Key('pictureLayoutTabletop'), children: <Widget>[
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: steps)),
            Padding(padding: const EdgeInsets.only(bottom: 8), child: picture(side)),
          ]);
        }
        if (w >= 600 || w > h) {
          final double side = (w * 0.4).clamp(140.0, (h - 24).clamp(140.0, maxPicture));
          return Row(key: const Key('pictureLayoutWide'), crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
            Padding(padding: const EdgeInsets.all(12), child: picture(side)),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: steps)),
          ]);
        }
        final double side = (w * 0.7).clamp(160.0, maxPicture);
        return ListView(key: const Key('pictureLayoutNarrow'), padding: const EdgeInsets.all(12), children: <Widget>[
          Center(child: picture(side)),
          const SizedBox(height: 16),
          steps,
        ]);
      });
}

/// A camera view with its controls below it (tabletop: the camera fills the upper half).
class PictureScannerFrame extends StatelessWidget {
  const PictureScannerFrame({super.key, required this.scanner, required this.controls});
  final Widget scanner, controls;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double h = c.maxHeight.isFinite ? c.maxHeight : 700;
        final bool tabletop = postureOf(Size(c.maxWidth, h)) == ff.Posture.foldTabletop;
        final double cam = tabletop ? h * 0.5 : (h * 0.6).clamp(220.0, 420.0);
        return Column(key: Key(tabletop ? 'scannerFrameTabletop' : 'scannerFrame'), children: <Widget>[
          SizedBox(height: cam, width: double.infinity, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: scanner)),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: controls)),
        ]);
      });
}

const List<Color> kGlyphColours = <Color>[
  Color(0xFFE57373), Color(0xFF64B5F6), Color(0xFF81C784), Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFF4DB6AC),
];

const Map<String, IconData> _glyphIcons = <String, IconData>{
  'sun': Icons.wb_sunny_rounded, 'moon': Icons.nightlight_round, 'star': Icons.star_rounded,
  'cloud': Icons.cloud_rounded, 'tree': Icons.park_rounded, 'fish': Icons.set_meal_rounded,
  'bird': Icons.flutter_dash, 'cat': Icons.pets_rounded, 'dog': Icons.cruelty_free_rounded,
  'boat': Icons.sailing_rounded, 'house': Icons.home_rounded, 'flower': Icons.local_florist_rounded,
  'apple': Icons.apple_rounded, 'ball': Icons.sports_soccer_rounded, 'kite': Icons.paragliding_rounded,
  'bell': Icons.notifications_rounded,
};

IconData glyphIcon(String picture) => _glyphIcons[picture] ?? Icons.star_rounded;

/// A nameless window tile: a picture and a colour, no text, no digits. Semantics carry no name either.
class GlyphTile extends StatelessWidget {
  const GlyphTile({super.key, required this.glyph, this.size = 72});
  final WindowGlyph glyph;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: kGlyphColours[glyph.colour % kGlyphColours.length], borderRadius: BorderRadius.circular(size / 4)),
          child: Icon(glyphIcon(glyph.picture), size: size * 0.6, color: Colors.white),
        ),
      );
}

/// A single gentle appearance, no loop (so it never keeps a screen animating): the olive branch.
class OliveBranchMark extends StatelessWidget {
  const OliveBranchMark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.6, end: 1),
        duration: motionDuration(context, 700),
        curve: Curves.easeOutBack,
        builder: (BuildContext context, double v, Widget? child) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: v, child: child)),
        child: Icon(Icons.eco_rounded, key: const Key('oliveBranchMark'), size: size, color: const Color(0xFF8A9A5B)),
      );
}

// ---------------------------------------------------------------------------------------------------------------
// Match: three pictures and a colour, never a word on the child's screen.

const List<IconData> _matchIcons = <IconData>[
  Icons.wb_sunny_rounded, Icons.nightlight_round, Icons.star_rounded, Icons.cloud_rounded, Icons.park_rounded, Icons.set_meal_rounded, Icons.flutter_dash, Icons.pets_rounded,
  Icons.cruelty_free_rounded, Icons.sailing_rounded, Icons.home_rounded, Icons.local_florist_rounded, Icons.apple_rounded, Icons.sports_soccer_rounded, Icons.paragliding_rounded, Icons.notifications_rounded,
  Icons.vpn_key_rounded, Icons.menu_book_rounded, Icons.directions_car_rounded, Icons.directions_bus_rounded, Icons.train_rounded, Icons.flight_rounded, Icons.rocket_launch_rounded, Icons.pedal_bike_rounded,
  Icons.beach_access_rounded, Icons.ac_unit_rounded, Icons.umbrella_rounded, Icons.water_drop_rounded, Icons.eco_rounded, Icons.emoji_nature_rounded, Icons.filter_vintage_rounded, Icons.spa_rounded,
  Icons.local_cafe_rounded, Icons.toys_rounded, Icons.extension_rounded, Icons.palette_rounded, Icons.phone_android_rounded, Icons.tv_rounded, Icons.headphones_rounded, Icons.mic_rounded,
  Icons.cake_rounded, Icons.icecream_rounded, Icons.local_pizza_rounded, Icons.cookie_rounded, Icons.bakery_dining_rounded, Icons.lunch_dining_rounded, Icons.egg_alt_rounded, Icons.emoji_food_beverage_rounded,
  Icons.music_note_rounded, Icons.piano_rounded, Icons.directions_boat_rounded, Icons.school_rounded, Icons.shopping_bag_rounded, Icons.watch_rounded, Icons.schedule_rounded, Icons.lightbulb_rounded,
  Icons.card_giftcard_rounded, Icons.celebration_rounded, Icons.emoji_events_rounded, Icons.favorite_rounded, Icons.diamond_rounded, Icons.anchor_rounded, Icons.flag_rounded, Icons.photo_camera_rounded,
];

const List<IconData> _matchShapeIcons = <IconData>[
  Icons.circle, Icons.square_rounded, Icons.change_history_rounded, Icons.pentagon_rounded,
  Icons.radio_button_unchecked_rounded, Icons.hexagon_rounded, Icons.favorite_border_rounded, Icons.add_rounded,
];

const List<Color> kMatchColourValues = <Color>[
  Color(0xFFE57373), Color(0xFFFFB74D), Color(0xFFFFD54F), Color(0xFF81C784),
  Color(0xFF4DB6AC), Color(0xFF64B5F6), Color(0xFFBA68C8), Color(0xFFF48FB1),
];

IconData matchIcon(int picture) => _matchIcons[picture % _matchIcons.length];
IconData matchShapeIcon(int colour) => _matchShapeIcons[colour % _matchShapeIcons.length];

/// A set of three pictures on a colour, with a shape in the corner so colour is never the only cue. [forChild]
/// excludes every semantic label: the child's screen carries no word, not even for a screen reader.
class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.set, this.iconSize = 48, this.forChild = false});
  final MatchSet set;
  final double iconSize;
  final bool forChild;

  @override
  Widget build(BuildContext context) {
    final Widget card = Container(
      padding: EdgeInsets.all(iconSize * 0.25),
      decoration: BoxDecoration(
        color: kMatchColourValues[set.colour % kMatchColourValues.length],
        borderRadius: BorderRadius.circular(iconSize * 0.4),
      ),
      child: Stack(clipBehavior: Clip.none, children: <Widget>[
        Padding(
          padding: EdgeInsets.only(top: iconSize * 0.1),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            for (final int p in set.pictures)
              Padding(padding: EdgeInsets.symmetric(horizontal: iconSize * 0.08), child: Icon(matchIcon(p), size: iconSize, color: Colors.white)),
          ]),
        ),
        Positioned(right: 0, top: -iconSize * 0.18, child: Icon(matchShapeIcon(set.colour), size: iconSize * 0.4, color: Colors.white70)),
      ]),
    );
    if (forChild) return ExcludeSemantics(child: card);
    return Semantics(container: true, label: '${kMatchColours[set.colour]} ${kMatchShapes[set.colour]}, ${set.names.join(', ')}', child: ExcludeSemantics(child: card));
  }
}
