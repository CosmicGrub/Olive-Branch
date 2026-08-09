// OLIVE BRANCH -- PRIVATE BUILD ONLY, DO NOT SHIP. Tests for
// lib/private_storybooks/private_storybook_reader.dart -- see that
// directory's README.md before this branch goes anywhere near a release.
//
// Imports and pumps PrivateStorybookReaderScreen directly with a
// hand-built StorybookEntry, independent of the manifest and of
// child_more.dart's compile-time gate (see that file's own test for the
// gate itself). flutter_html renders its output through RichText/Text
// spans depending on the element, so text lookups here pass
// findRichText: true to catch both.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/private_storybooks/private_storybook_manifest.dart';
import 'package:olive_client/private_storybooks/private_storybook_reader.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

const sampleEntry = StorybookEntry(
  id: 'sample-001',
  title: 'The Sample Story',
  description: 'A tiny placeholder tale used to test the reader end to end.',
  assetPath: 'assets/private_storybooks/sample_story.html',
);

void main() {
  // See private_storybook_shelf_test.dart's own comment: each test loads
  // the same real HTML asset via rootBundle, and CachingAssetBundle's
  // process-lifetime cache combined with AutomatedTestWidgetsFlutterBinding's
  // per-test zones can otherwise hang a second testWidgets case awaiting an
  // already-resolved cached Future. Clearing between tests avoids it.
  tearDown(() => rootBundle.clear());

  group('PrivateStorybookReaderScreen', () {
    testWidgets('renders the sample HTML content via flutter_html', (tester) async {
      await tester.pumpWidget(wrap(const PrivateStorybookReaderScreen(entry: sampleEntry)));
      await tester.pumpAndSettle();

      // The <h1> from the sample HTML, actually rendered by flutter_html --
      // not just the AppBar title (which shows the same string, so this
      // alone wouldn't prove the HTML parsed; the paragraph text below is
      // the real proof it did).
      expect(find.textContaining('The Sample Story', findRichText: true), findsWidgets);
      // Text from the sample <p>, proving the body actually rendered.
      expect(find.textContaining('paper boat', findRichText: true), findsOneWidget);
      // Text from the sample <em>, proving inline markup rendered too.
      expect(find.textContaining('Replace this file with a real story',
          findRichText: true), findsOneWidget);
    });

    testWidgets('scrollable and themed, not a raw unstyled web page', (tester) async {
      await tester.pumpWidget(wrap(const PrivateStorybookReaderScreen(entry: sampleEntry)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privateStorybookReaderScroll')), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('no settings affordance on this child-facing screen', (tester) async {
      await tester.pumpWidget(wrap(const PrivateStorybookReaderScreen(entry: sampleEntry)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('an entry pointing at a missing asset fails visibly, not blank',
        (tester) async {
      const missing = StorybookEntry(
        id: 'missing', title: 'Missing', description: '',
        assetPath: 'assets/private_storybooks/does_not_exist.html');
      await tester.pumpWidget(wrap(const PrivateStorybookReaderScreen(entry: missing)));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load this story"), findsOneWidget);
    });
  });
}
