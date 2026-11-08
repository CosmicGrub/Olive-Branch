// OLIVE BRANCH — shared helpers for the on-device performance tests. Not a test
// file itself (no main).
//
// [RebuildCounter] counts how many times a widget of a given runtime type was
// rebuilt, through Flutter's own debugOnRebuildDirtyWidget hook, so a test can
// say "typing in the box rebuilt N tiles" and print the number it measured.
import 'package:flutter/widgets.dart';

class RebuildCounter {
  RebuildCounter(this.typeName);

  /// `widget.runtimeType.toString()` to count, e.g. '_JournalTile'.
  final String typeName;
  int rebuilds = 0;

  void start() {
    rebuilds = 0;
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      // `builtOnce` is only maintained when debugPrintRebuildDirtyWidgets is
      // on, so it is not used; call start() after the first frame instead.
      if (e.widget.runtimeType.toString() == typeName) rebuilds++;
    };
  }

  void stop() => debugOnRebuildDirtyWidget = null;
}
