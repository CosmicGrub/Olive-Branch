// OLIVE BRANCH — shared in-app gallery instance. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline).
//
// snapshot_button.dart's own wiring note asks for "one AppGallery instance
// app-wide ... constructed once ... so saves accumulate in one place" —
// this is that one place, added by the navigation wiring pass rather than
// by the group that built AppGallery itself, so every screen offering a
// SnapshotButton or reading AppGalleryScreen shares the same in-memory
// store instead of each constructing (and instantly orphaning) its own.
import 'snapshot_button.dart';

final AppGallery demoAppGallery = AppGallery();
