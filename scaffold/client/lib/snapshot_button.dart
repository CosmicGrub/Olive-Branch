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
//
// KEPT ON THIS DEVICE. [AppGallery] is now backed by [SavedPicturesRepository]
// (LocalStore area `pictures`, scoped to the child), so what she keeps survives
// a restart — and "My saved pictures" is finally real. A picture is stored as
// what makes it (a doodle's strokes, a colouring's region fills), small and
// vector, not as a raster; a plain photo-tap stores only where and when. It is
// kept only on this device (neverToDeviceGallery still holds): not in the phone
// gallery, not uploaded, not in any export. Doodle desk and the colouring page
// are the honest callers of [SnapshotButton]: they pass `capture`, so the tap
// keeps the actual picture. She can put a picture away again (long-press); the
// store never silently evicts one to make room, it says it is full instead.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'colouring_screen.dart' show ColouringThumbnail;
import 'doodle_desk.dart' show DoodleThumbnail;
import 'local_services.dart';
import 'local_store.dart';

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
  const AppPhoto({
    required this.id,
    required this.surface,
    required this.savedAt,
    this.kind = 'snapshot',
    this.data,
  });
  final String id;
  final String surface;
  final DateTime savedAt;

  /// 'snapshot' (a photo-tap, no content), 'doodle' or 'colouring'.
  final String kind;

  /// What makes the picture, as plain JSON: a doodle's strokes or a
  /// colouring's region fills. Null for a bare snapshot.
  final Map<String, Object?>? data;
}

/// A single stored picture may not exceed this many bytes of JSON; one huge
/// doodle must not be able to crowd out everything else she has kept.
const int maxSavedPictureBytes = 768 * 1024;

const Set<String> savedPictureKinds = <String>{'snapshot', 'doodle', 'colouring'};

/// The on-device store behind "My saved pictures": one document key per
/// picture in the child's `pictures` namespace.
class SavedPicturesRepository {
  SavedPicturesRepository(this._ns);
  factory SavedPicturesRepository.forChild([String? childId]) =>
      SavedPicturesRepository(LocalServices.current.area('pictures', ownerId: childId));
  final LocalNamespace _ns;

  /// The namespace this repository writes (for tests).
  String get namespaceName => _ns.spec.name;

  /// True when [other] writes the very same open namespace (same store AND
  /// same child scope), so a gallery knows whether it needs to rebind.
  bool sameStoreAs(SavedPicturesRepository other) => identical(_ns, other._ns);

  static String _key(String id) => 'p.${id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}';

  /// Oldest first.
  Future<List<AppPhoto>> load() async {
    final List<AppPhoto> out = <AppPhoto>[];
    for (final String k in await _ns.list()) {
      final Object? raw = await _ns.get(k);
      if (raw is! Map) continue;
      final Object? id = raw['id'], surface = raw['surface'], at = raw['savedAt'], kind = raw['kind'];
      if (id is! String || surface is! String || at is! String || kind is! String) continue;
      final DateTime? when = DateTime.tryParse(at);
      if (when == null || !savedPictureKinds.contains(kind)) continue;
      final Object? data = raw['data'];
      out.add(AppPhoto(
          id: id, surface: surface, savedAt: when, kind: kind,
          data: data is Map ? Map<String, Object?>.from(data) : null));
    }
    out.sort((AppPhoto a, AppPhoto b) => a.savedAt.compareTo(b.savedAt));
    return out;
  }

  /// Throws [LocalStoreFull] when the box is full or this one picture is over
  /// [maxSavedPictureBytes]; nothing is written and nothing is evicted.
  Future<void> add(AppPhoto p) async {
    final Map<String, Object?> row = <String, Object?>{
      'id': p.id,
      'surface': p.surface,
      'savedAt': p.savedAt.toIso8601String(),
      'kind': p.kind,
      if (p.data != null) 'data': p.data,
    };
    if (utf8.encode(jsonEncode(row)).length > maxSavedPictureBytes) {
      throw LocalStoreFull(_ns.spec.name, maxSavedPictureBytes);
    }
    await _ns.put(_key(p.id), row);
  }

  Future<void> remove(String id) => _ns.delete(_key(id));
}

/// The app's OWN gallery — never the platform photo library. Backed by
/// [SavedPicturesRepository] when it has one, so it survives a restart; a bare
/// `AppGallery()` is in-memory only (tests, previews).
///
/// [AppGallery.shared] auto-binds to this device's child the first time a
/// screen uses it ([ensureBound]), and rebinds if the child scope changes.
class AppGallery extends ChangeNotifier {
  AppGallery({SavedPicturesRepository? repository}) : _repo = repository, _autoBind = false;

  /// The one app-wide instance: binds itself to [LocalServices.current].
  AppGallery.shared() : _repo = null, _autoBind = true;

  SavedPicturesRepository? _repo;
  final bool _autoBind;
  final List<AppPhoto> _photos = <AppPhoto>[];
  bool _loaded = false;
  int _bindGeneration = 0;

  /// Newest first — a gallery you just added to should show what you just
  /// took without scrolling.
  List<AppPhoto> get photos => List<AppPhoto>.unmodifiable(_photos.reversed);

  /// True once what was kept on this device has been read in.
  bool get loaded => _loaded;

  /// For [AppGallery.shared]: bind to the current child's store (again, if the
  /// scope changed since) and read what was kept. A no-op for an explicitly
  /// constructed gallery.
  void ensureBound() {
    if (!_autoBind) return;
    final SavedPicturesRepository fresh = SavedPicturesRepository.forChild();
    if (_repo?.sameStoreAs(fresh) ?? false) return;
    _repo = fresh;
    _photos.clear();
    _loaded = false;
    unawaited(load());
  }

  /// Reads what was kept on this device; anything added since stays.
  Future<void> load() async {
    final SavedPicturesRepository? repo = _repo;
    if (repo == null) return;
    final int gen = ++_bindGeneration;
    try {
      final List<AppPhoto> stored = await repo.load();
      if (gen != _bindGeneration || repo != _repo) return;
      final Set<String> have = _photos.map((AppPhoto p) => p.id).toSet();
      _photos
        ..addAll(stored.where((AppPhoto p) => !have.contains(p.id)))
        ..sort((AppPhoto a, AppPhoto b) => a.savedAt.compareTo(b.savedAt));
    } catch (_) {
      // Unreadable store: it was quarantined; she starts with an empty box.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Shows [p] at once and keeps it on this device in the background
  /// (see [keep] to learn whether the device could).
  void add(AppPhoto p) => unawaited(keep(p));

  /// Shows [p] at once, then keeps it on this device. Resolves false — and
  /// takes it back out — if the device could not keep it (box full).
  Future<bool> keep(AppPhoto p) async {
    _photos.add(p);
    notifyListeners();
    final SavedPicturesRepository? repo = _repo;
    if (repo == null) return true;
    try {
      await repo.add(p);
      return true;
    } catch (_) {
      _photos.removeWhere((AppPhoto x) => x.id == p.id);
      notifyListeners();
      return false;
    }
  }

  /// After a device wipe: drop everything held in memory and unbind, so the
  /// next screen that uses this gallery rebinds to the (now empty) store.
  void forget() {
    _photos.clear();
    _repo = null;
    _loaded = false;
    _bindGeneration++;
    notifyListeners();
  }

  /// Puts a picture away: gone from the list and from this device.
  Future<void> remove(String id) async {
    _photos.removeWhere((AppPhoto x) => x.id == id);
    notifyListeners();
    try {
      await _repo?.remove(id);
    } catch (_) {
      // Nothing useful to tell her; the next load simply shows it again.
    }
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
    this.kind = 'snapshot',
    this.capture,
    this.compact = false,
    this.icon = Icons.photo_camera_outlined,
    this.tooltip = 'Save a photo of this to your gallery',
    this.savedMessage,
    this.nothingToKeepMessage = 'Make something first, then keep it.',
  });

  final String currentSurface;
  final AppGallery gallery;
  final VoidCallback? onSaved;

  /// What gets stored: 'snapshot' (a bare photo-tap) or, for a surface that
  /// makes a picture, 'doodle' / 'colouring'.
  final String kind;

  /// Returns what makes the picture right now (strokes, fills), or null when
  /// there is nothing to keep yet. Null [capture] means a bare snapshot.
  final Map<String, Object?>? Function()? capture;

  /// An app-bar sized icon button instead of a floating button.
  final bool compact;
  final IconData icon;
  final String tooltip;

  /// Overrides the "Saved to your gallery." line (e.g. "Kept on this device.").
  final String? savedMessage;
  final String nothingToKeepMessage;

  bool get _available => !screenshotScopedOffSurfaces.contains(currentSurface);

  void _press(BuildContext context) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ScreenshotCaptureResult result = captureScreenshot(currentSurface);
    if (!result.ok) {
      // Reachable only if screenshotScopedOffSurfaces and _available
      // ever drift apart — kept as a real branch, not an assert, so a
      // future refactor fails safe (a message) rather than silently.
      messenger.showSnackBar(
          SnackBar(content: Text(result.advice!), duration: const Duration(seconds: 2)));
      return;
    }
    Map<String, Object?>? data;
    if (capture != null) {
      data = capture!();
      if (data == null) {
        messenger.showSnackBar(SnackBar(
            content: Text(nothingToKeepMessage), duration: const Duration(seconds: 2)));
        return;
      }
    }
    gallery.ensureBound();
    final DateTime now = DateTime.now();
    final Future<bool> kept = gallery.keep(AppPhoto(
        id: 'shot-${now.microsecondsSinceEpoch}',
        surface: currentSurface,
        savedAt: now,
        kind: kind,
        data: data));
    onSaved?.call();
    messenger.showSnackBar(SnackBar(
        content: Text(savedMessage ?? result.message!), duration: const Duration(seconds: 2)));
    // The picture is on screen at once; if the device could not keep it, say
    // so gently rather than leave her thinking it is safe.
    unawaited(kept.then((bool ok) {
      if (!ok) {
        messenger.showSnackBar(const SnackBar(
            content: Text("Your picture box is full, so that one couldn't be kept. "
                'Put one away to make room.'),
            duration: Duration(seconds: 4)));
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    // Visibly absent, never merely disabled, on a call surface — see file
    // header. SizedBox.shrink() leaves no icon, no ghost, no tap target.
    if (!_available) return const SizedBox.shrink();
    if (compact) {
      return IconButton(
        key: const Key('snapshotButton'),
        tooltip: tooltip,
        iconSize: 28,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: () => _press(context),
        icon: Icon(icon),
      );
    }
    return SizedBox(
      width: 56, height: 56, // >=48dp target with room to spare
      child: FloatingActionButton(
        key: const Key('snapshotButton'),
        heroTag: 'snapshotButton-$currentSurface',
        tooltip: tooltip,
        onPressed: () => _press(context),
        child: Icon(icon),
      ),
    );
  }
}

/// Her own gallery, viewed — proof the photo went somewhere real rather than
/// vanishing into a demo button. Year-grouping (MARKUP screen 'gallery') is
/// a guardian-surface concern for the works-gallery group; this is the
/// snapshot feature's own small, flat list.
class AppGalleryScreen extends StatefulWidget {
  const AppGalleryScreen({super.key, required this.gallery});
  final AppGallery gallery;

  @override
  State<AppGalleryScreen> createState() => _AppGalleryScreenState();
}

class _AppGalleryScreenState extends State<AppGalleryScreen> {
  @override
  void initState() {
    super.initState();
    // Reads what was kept on this device (a no-op for a gallery that was
    // handed its own repository or has none).
    widget.gallery.ensureBound();
  }

  /// Long-press: ask gently, then put the picture away for good.
  Future<void> _putAway(AppPhoto photo) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Put this picture away?'),
        content: const Text('It will be gone from this device.'),
        actions: <Widget>[
          TextButton(
              key: const Key('keepPicture'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it')),
          TextButton(
              key: const Key('putAwayPicture'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Put it away')),
        ],
      ),
    );
    if (yes == true) await widget.gallery.remove(photo.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your gallery')),
        body: AnimatedBuilder(
          animation: widget.gallery,
          builder: (context, _) {
            final List<AppPhoto> photos = widget.gallery.photos;
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
              itemBuilder: (context, i) => GestureDetector(
                key: ValueKey<String>('picture-${photos[i].id}'),
                onLongPress: () => _putAway(photos[i]),
                child: _PhotoTile(photos[i]),
              ),
            );
          },
        ),
      );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile(this.photo);
  final AppPhoto photo;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Map<String, Object?>? data = photo.data;
    Widget child = Icon(Icons.image_outlined, color: scheme.onPrimaryContainer, size: 32);
    // A kept doodle or colouring is drawn from what makes it. A bare
    // photo-tap has no content to draw, so it stays an honest placeholder icon
    // rather than a faked thumbnail.
    if (photo.kind == 'doodle' && data != null) {
      child = DoodleThumbnail(data: data);
    } else if (photo.kind == 'colouring' && data != null) {
      child = ColouringThumbnail(data: data);
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: scheme.primaryContainer),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
    );
  }
}
