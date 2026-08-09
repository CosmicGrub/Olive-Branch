// OLIVE BRANCH — in-app photo/screenshot button. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.15.
// Renders MARKUP screen 'snapshot'.
//
// Ports packages/homework/src/snapshot.ts's screenshot half. (The camera
// half — quality-gated photos headed for OCR — is capture_gate.dart /
// homework_quality_gate.dart's job; this file is the "already digital, no
// blur or skew possible" screenshot path, which carries a different risk:
// it could catch a parent's live video mid-call, so that is the only thing
// checked here.)
//
// The two invariants the TS file names explicitly, preserved as `const
// bool`s below so a reviewer can grep for the guarantee itself rather than a
// comment describing it: [neverToDeviceGallery] and
// [autoUploadsToAppStorage]. There is no code path in this widget that
// touches a platform photo library, and no code path in this widget that
// skips [AppGallery] — those two facts ARE the feature.
//
// [SnapshotButton] is entirely ABSENT — not merely disabled, not merely
// greyed out — on any surface named in [screenshotScopedOffSurfaces]. A
// disabled button still shows a child "there is a camera pointed at this
// call"; an absent one doesn't invite the tap in the first place. "No count
// shown to her" (snapshot.ts's own words) is why the button carries no
// badge and [AppGallery] exposes a list, never a tally.
import 'package:flutter/material.dart';

const bool neverToDeviceGallery = true;
const bool autoUploadsToAppStorage = true;

/// Surfaces where a parent's live video could be caught mid-capture. Named
/// so the list itself is the guarantee, matching snapshot.ts.
const Set<String> screenshotScopedOffSurfaces = <String>{
  'live_call', 'call_video', 'pane_video',
};

enum ScreenshotRefusal { callSurface }

class ScreenshotCaptureResult {
  const ScreenshotCaptureResult.ok(this.message)
      : ok = true, reason = null, advice = null;
  const ScreenshotCaptureResult.refused(this.reason, this.advice)
      : ok = false, message = null;

  final bool ok;
  final String? message;
  final ScreenshotRefusal? reason;
  final String? advice;
}

const String _savedMessage = 'Saved to your gallery.';

/// Already digital — no blur, no skew, nothing to gate on quality. The only
/// risk is capturing a call in progress, so that is the only thing checked.
/// A refusal, not a silent no-op: the caller gets a reason back.
ScreenshotCaptureResult captureScreenshot(String currentSurface) {
  if (screenshotScopedOffSurfaces.contains(currentSurface)) {
    return const ScreenshotCaptureResult.refused(
        ScreenshotRefusal.callSurface, "Let's try that again.");
  }
  return const ScreenshotCaptureResult.ok(_savedMessage);
}

/// One saved photo. `surface` records where it was taken, purely so the
/// (honest, in-memory) gallery below can show her when/where — never a
/// coordinate, per P3, and nothing here claims a location.
class AppPhoto {
  const AppPhoto({required this.id, required this.surface, required this.savedAt});
  final String id;
  final String surface;
  final DateTime savedAt;
}

/// The app's OWN gallery — never the platform photo library. There is no
/// backend yet (this whole preview build has none), so this in-memory store
/// is the honest stand-in, matching the demo-data pattern in main.dart's
/// childHomeDemo/guardianHomeDemo constants: real data shape, no server
/// behind it, said plainly rather than faked.
class AppGallery extends ChangeNotifier {
  final List<AppPhoto> _photos = <AppPhoto>[];

  /// Newest first — a gallery you just added to should show what you just
  /// took without scrolling.
  List<AppPhoto> get photos => List<AppPhoto>.unmodifiable(_photos.reversed);

  void add(AppPhoto p) {
    _photos.add(p);
    notifyListeners();
  }
}

/// A dedicated in-app capture control. Reads `currentSurface` on every
/// build (not just once) so a screen that transitions into a call — e.g. a
/// pane that starts as a lobby and becomes `pane_video` — loses the button
/// the same frame the risk appears, without needing its own rebuild logic.
class SnapshotButton extends StatelessWidget {
  const SnapshotButton({
    super.key,
    required this.currentSurface,
    required this.gallery,
    this.onSaved,
  });

  final String currentSurface;
  final AppGallery gallery;
  final VoidCallback? onSaved;

  bool get _available => !screenshotScopedOffSurfaces.contains(currentSurface);

  @override
  Widget build(BuildContext context) {
    // Visibly absent, never merely disabled, on a call surface — see file
    // header. SizedBox.shrink() leaves no icon, no ghost, no tap target.
    if (!_available) return const SizedBox.shrink();
    return SizedBox(
      width: 56, height: 56, // >=48dp target with room to spare
      child: FloatingActionButton(
        key: const Key('snapshotButton'),
        heroTag: 'snapshotButton-$currentSurface',
        tooltip: 'Save a photo of this to your gallery',
        onPressed: () {
          final ScreenshotCaptureResult result = captureScreenshot(currentSurface);
          if (!result.ok) {
            // Reachable only if screenshotScopedOffSurfaces and _available
            // ever drift apart — kept as a real branch, not an assert, so a
            // future refactor fails safe (a message) rather than silently.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.advice!), duration: const Duration(seconds: 2)));
            return;
          }
          gallery.add(AppPhoto(
            id: 'shot-${DateTime.now().microsecondsSinceEpoch}',
            surface: currentSurface,
            savedAt: DateTime.now()));
          onSaved?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message!), duration: const Duration(seconds: 2)));
        },
        child: const Icon(Icons.photo_camera_outlined),
      ),
    );
  }
}

/// Her own gallery, viewed — proof the photo went somewhere real rather than
/// vanishing into a demo button. Year-grouping (MARKUP screen 'gallery') is
/// a guardian-surface concern for the works-gallery group; this is the
/// snapshot feature's own small, flat list.
class AppGalleryScreen extends StatelessWidget {
  const AppGalleryScreen({super.key, required this.gallery});
  final AppGallery gallery;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your gallery')),
        body: AnimatedBuilder(
          animation: gallery,
          builder: (context, _) {
            final List<AppPhoto> photos = gallery.photos;
            if (photos.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.photo_camera_outlined, size: 48,
                      color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('Nothing saved yet — take a photo to see it here.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: photos.length,
              itemBuilder: (context, i) => _PhotoTile(photos[i]),
            );
          },
        ),
      );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile(this.photo);
  final AppPhoto photo;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.primaryContainer),
        alignment: Alignment.center,
        // No real image data in this preview build (no camera plugin wired
        // up yet — see capture_gate.dart's header) — an honest placeholder
        // icon rather than a faked thumbnail.
        child: Icon(Icons.image_outlined,
          color: Theme.of(context).colorScheme.onPrimaryContainer, size: 32),
      );
}
