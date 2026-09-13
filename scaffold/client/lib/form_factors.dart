// OLIVE BRANCH — the device matrix, the pure-logic half. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline — manually
// built and run via `flutter analyze` / `flutter test` this session).
// MASTERFILE §8.11.1.
//
// A DELIBERATELY PARTIAL 1:1 port of packages/devices/src/devices.ts's
// §8.11.1 "form factors" section — `Posture`/`Orientation`/`Viewport`/
// `FormFactor`/`FORM_FACTORS`/`NARROWEST`/`factor()`/`postureFor()`/
// `columnsAt()` — same names and shapes as the original, the same
// discipline `device_channels.dart` already applies porting `devices.ts`'s
// §8.11.4 section. §8.11.2's input/stylus subsection and §8.11.3's touch-
// target-floor subsection are not ported here: nothing in this client
// calls either yet, and porting logic with no real caller is exactly the
// "declaration with nothing behind it" MASTERFILE §0 warns against.
//
// Before this port, several screens (`court_export.dart` among them) each
// hand-rolled their own single, arbitrary pixel breakpoint for "wide
// enough" — none of them matched `devices.ts`'s own real posture
// boundaries (600/660/673/768/800/1024/1280), and none of them matched
// each other. `court_export.dart` is the first real consumer of this port,
// fixed in the same pass this file was added — see that file's own header
// for the concrete bug this closes.
library;

enum Posture {
  foldCover, foldMain, foldTabletop, phone,
  tabletSmall, tabletMedium, tabletLarge, desktop, dex,
}

enum Orientation { portrait, landscape }

class Viewport {
  const Viewport({required this.w, required this.h});
  final double w;
  final double h;
}

class FormFactor {
  const FormFactor({
    required this.posture,
    required this.label,
    required this.min,
    required this.orientations,
    required this.columns,
    required this.note,
  });
  final Posture posture;
  final String label;

  /// The SMALLEST viewport this posture must work at, in CSS/logical px.
  final Viewport min;

  /// Orientations that actually occur in the wild for this posture.
  final List<Orientation> orientations;

  /// Layout columns available at scale 1.
  final int columns;
  final String note;
}

/// Same nine rows, same facts, as devices.ts's own FORM_FACTORS.
const List<FormFactor> formFactors = <FormFactor>[
  FormFactor(posture: Posture.foldCover, label: 'Fold, closed',
    min: Viewport(w: 344, h: 882), orientations: [Orientation.portrait], columns: 1,
    note: 'The narrowest thing we support. Every layout must survive 344 px.'),

  FormFactor(posture: Posture.foldMain, label: 'Fold, open',
    min: Viewport(w: 673, h: 841),
    orientations: [Orientation.portrait, Orientation.landscape], columns: 2,
    note: 'Nearly square. The crease runs down the centre, so two-column '
        'gutters are placed there deliberately.'),

  FormFactor(posture: Posture.foldTabletop, label: 'Fold, half-open',
    min: Viewport(w: 673, h: 420), orientations: [Orientation.landscape], columns: 2,
    note: 'Stands by itself, camera at eye level. The only hands-free call '
        'posture the hardware has — video above the crease, controls below.'),

  FormFactor(posture: Posture.phone, label: 'Ordinary phone',
    min: Viewport(w: 360, h: 640), orientations: [Orientation.portrait], columns: 1,
    note: 'A 360 px floor covers everything still sold.'),

  FormFactor(posture: Posture.tabletSmall, label: '7-inch tablet',
    min: Viewport(w: 600, h: 960),
    orientations: [Orientation.portrait, Orientation.landscape], columns: 1,
    note: "The cheap ones. Often the child's only device, and often FireOS."),

  FormFactor(posture: Posture.tabletMedium, label: '8-inch tablet',
    min: Viewport(w: 768, h: 1024),
    orientations: [Orientation.portrait, Orientation.landscape], columns: 2, note: ''),

  FormFactor(posture: Posture.tabletLarge, label: '10-inch tablet',
    min: Viewport(w: 800, h: 1280),
    orientations: [Orientation.portrait, Orientation.landscape], columns: 2,
    note: 'Used in LANDSCAPE more often than portrait — the opposite of a '
        'phone, and the assumption most layouts get wrong.'),

  FormFactor(posture: Posture.desktop, label: 'PC',
    min: Viewport(w: 1024, h: 640), orientations: [Orientation.landscape], columns: 3,
    note: 'Resizable, so the floor is what matters. Windows, and it is where '
        'the guardian shell is genuinely comfortable.'),

  FormFactor(posture: Posture.dex, label: 'Samsung DeX',
    min: Viewport(w: 1280, h: 720), orientations: [Orientation.landscape], columns: 3,
    note: 'The Fold driving a monitor with a mouse. A desktop that is also a '
        'phone, which breaks the assumption that platform implies input.'),
];

/// The narrowest thing supported, anywhere. Every layout is checked against it.
final double narrowest = formFactors.map((f) => f.min.w).reduce((a, b) => a < b ? a : b);

FormFactor? factor(Posture p) {
  for (final f in formFactors) {
    if (f.posture == p) return f;
  }
  return null;
}

Posture postureFor(Viewport v) {
  final bool landscape = v.w > v.h;
  if (v.w >= 1280 && landscape) return Posture.dex;
  if (v.w >= 1024) return Posture.desktop;
  if (v.w >= 800) return Posture.tabletLarge;
  if (v.w >= 768) return Posture.tabletMedium;
  // A short, wide, mid-size viewport is the Fold standing half-open.
  if (v.w >= 600 && landscape && v.h <= 480) return Posture.foldTabletop;
  if (v.w >= 600) {
    return v.w >= 660 && v.h < 900 ? Posture.foldMain : Posture.tabletSmall;
  }
  if (v.w <= 400 && v.h >= 800) return Posture.foldCover;
  return Posture.phone;
}

/// Columns are computed from the EFFECTIVE width — viewport divided by text
/// scale — because a 10-inch tablet at 2.0x type has the effective width of
/// a phone. §8.8.
int columnsAt(Viewport v, [double textScale = 1]) {
  final double eff = v.w / textScale;
  if (eff >= 1024) return 3;
  if (eff >= 660) return 2;
  return 1;
}

/// A typography-driven cap, not a posture boundary — the widest a single
/// column of body text should get before it's capped and centered, so a
/// single-column screen doesn't stretch edge-to-edge on a wide tablet or
/// desktop. Orthogonal to columnsAt(): this only ever applies WITHIN a
/// screen that is still rendering ONE column (columnsAt() < 2 needs no cap
/// at all; a screen that genuinely uses two real columns needs no cap
/// either, since Expanded already bounds each pane). Value chosen for
/// readable prose line length, not a device boundary — do not add this to
/// `formFactors`/`FORM_FACTORS` or treat it as a tenth posture.
const double comfortableReadingWidth = 640;
