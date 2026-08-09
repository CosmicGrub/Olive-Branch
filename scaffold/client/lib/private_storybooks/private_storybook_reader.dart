// PRIVATE BUILD ONLY -- DO NOT SHIP -- see
// scaffold/client/lib/private_storybooks/README.md before ever merging this
// branch anywhere near a release.
//
// The "read it" half of this feature. Renders the book's HTML asset via
// flutter_html, which only ever renders markup -- it has no JavaScript
// engine, unlike webview_flutter. That is a real security requirement, not
// a style preference: this renders on a child-facing surface, and nothing
// dropped into assets/private_storybooks/ should ever be able to execute
// script. The page is themed against this app's own ColorScheme/textTheme
// so it reads as a native screen, not an embedded web page.
library private_storybook_reader;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_html/flutter_html.dart';

import 'private_storybook_manifest.dart';

class PrivateStorybookReaderScreen extends StatefulWidget {
  const PrivateStorybookReaderScreen({super.key, required this.entry});
  final StorybookEntry entry;

  @override
  State<PrivateStorybookReaderScreen> createState() =>
      _PrivateStorybookReaderScreenState();
}

class _PrivateStorybookReaderScreenState
    extends State<PrivateStorybookReaderScreen> {
  late final Future<String> _html = rootBundle.loadString(widget.entry.assetPath);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.title)),
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _html,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const _ReaderError();
            }
            return SingleChildScrollView(
              key: const Key('privateStorybookReaderScroll'),
              padding: const EdgeInsets.all(20),
              child: Html(
                data: snapshot.data!,
                style: {
                  'body': Style(
                    fontSize: FontSize(17),
                    color: scheme.onSurface,
                    margin: Margins.zero,
                  ),
                  'h1': Style(
                    fontSize: FontSize(theme.textTheme.headlineSmall?.fontSize ?? 24),
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                    margin: Margins.only(bottom: 12),
                  ),
                  'p': Style(margin: Margins.only(bottom: 12)),
                  'em': Style(color: scheme.onSurfaceVariant),
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(28), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 48,
          color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 14),
        const Text("Couldn't load this story", textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ])),
  );
}
