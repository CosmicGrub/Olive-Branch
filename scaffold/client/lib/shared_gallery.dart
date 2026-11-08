// OLIVE BRANCH — shared in-app gallery instance. No longer UNVERIFIED —
// verified by CI (`flutter analyze` and `flutter test` run for real in
// tools/verify.sh and .github/workflows/verify.yml).
//
// snapshot_button.dart's own wiring note asks for "one AppGallery instance
// app-wide ... constructed once ... so saves accumulate in one place" —
// this is that one place, added by the navigation wiring pass rather than
// by the group that built AppGallery itself, so every screen offering a
// SnapshotButton or reading AppGalleryScreen shares the same in-memory
// store instead of each constructing (and instantly orphaning) its own.
//
// It is now backed by this device's own storage: [AppGallery.shared] binds to
// the current child's `pictures` area the first time a screen opens it, so
// what she keeps survives a restart (see snapshot_button.dart). The name
// `demoAppGallery` predates that and is kept so existing call sites stay put.
import 'snapshot_button.dart';

final AppGallery demoAppGallery = AppGallery.shared();
