// OLIVE BRANCH — her side of "picture stories": read-only. No longer UNVERIFIED —
// verified by CI (client/test/care_screens_test.dart). MASTERFILE section 8.17.
//
// A guardian wrote these and chose to show them; this file is everything her
// app can do with them: list the shown ones and read one a page at a time. It
// imports no care screen and no care repository, only the narrow
// [ChildExplainerReader], so it cannot reach the care binder, hospital notes or
// appointment prep (a test reads this file's source to hold that line). The app
// writes no story and gives no advice; every word is the guardian's.
import 'dart:async';

import 'package:flutter/material.dart';

import 'growing_care_logic.dart';
import 'growing_care_store.dart';
import 'growing_care_widgets.dart';
import 'access_scope.dart' show readingAlign, readingStyleOf;
import 'read_aloud.dart' show ReadAloudScope;

/// The stories a guardian chose to show her. Nothing here writes.
class ExplainerStoriesScreen extends StatefulWidget {
  const ExplainerStoriesScreen({super.key, this.reader, this.speak});
  final ChildExplainerReader? reader;
  final Future<void> Function(String text)? speak;

  @override
  State<ExplainerStoriesScreen> createState() => _ExplainerStoriesScreenState();
}

class _ExplainerStoriesScreenState extends State<ExplainerStoriesScreen> {
  late final ChildExplainerReader _reader = widget.reader ?? GrowingCareStores.forChild().childExplainers();
  List<ExplainerStory>? _stories;

  @override
  void initState() {
    super.initState();
    unawaited(_reader.shown().then((List<ExplainerStory> s) { if (mounted) setState(() => _stories = s); }));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Stories for you')),
        body: SafeArea(child: _stories == null ? const SizedBox.shrink() : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          if (_stories!.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nothing here yet.', textAlign: TextAlign.center)),
          for (final ExplainerStory s in _stories!) Card(
              key: ValueKey<String>('hers-${s.id}'),
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExplainerPagerScreen(story: s, speak: widget.speak))),
                child: Container(
                  constraints: const BoxConstraints(minHeight: childTarget + 16), padding: const EdgeInsets.all(12),
                  child: Row(children: <Widget>[
                    if (s.thumb != null) ThumbImage(s.thumb!, size: 72) else const Icon(Icons.menu_book_outlined, size: 48),
                    const SizedBox(width: 14),
                    Expanded(child: Text(s.title, style: Theme.of(context).textTheme.titleLarge)),
                  ]),
                ),
              )),
        ])),
      );
}

/// One story, a page at a time. Big Back and Next buttons, dots for where she
/// is (no "page 2 of 5"), and a read-aloud button when speech is wired.
class ExplainerPagerScreen extends StatefulWidget {
  const ExplainerPagerScreen({super.key, required this.story, this.speak});
  final ExplainerStory story;
  final Future<void> Function(String text)? speak;

  @override
  State<ExplainerPagerScreen> createState() => _ExplainerPagerScreenState();
}

class _ExplainerPagerScreenState extends State<ExplainerPagerScreen> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final List<String> pages = widget.story.pages;
    final bool last = _i == pages.length - 1;
    final Future<void> Function(String)? speak = widget.speak ?? ReadAloudScope.speakFnIfEnabled(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.story.title), actions: <Widget>[
        if (speak != null)
          IconButton(key: const Key('readAloud'), tooltip: 'Read it to me', icon: const Icon(Icons.volume_up_outlined),
              onPressed: () => unawaited(speak(pages[_i]))),
      ]),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: <Widget>[
        if (widget.story.thumb != null && _i == 0) Padding(padding: const EdgeInsets.only(bottom: 16), child: ThumbImage(widget.story.thumb!, size: 160)),
        Expanded(child: Center(child: SingleChildScrollView(child: Text(pages[_i], key: const Key('storyText'),
            textAlign: readingAlign(context, TextAlign.center),
            style: readingStyleOf(context, Theme.of(context).textTheme.headlineSmall!.copyWith(height: 1.4)))))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          for (int d = 0; d < pages.length; d++) Container(
              margin: const EdgeInsets.all(4), width: 10, height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: d == _i ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant)),
        ]),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(child: OutlinedButton.icon(key: const Key('storyBack'), onPressed: _i == 0 ? null : () => setState(() => _i--),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(childTarget)),
              icon: const Icon(Icons.arrow_back), label: const Text('Back'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(key: const Key('storyNext'),
              onPressed: () => last ? Navigator.of(context).pop() : setState(() => _i++),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(childTarget)),
              icon: Icon(last ? Icons.check : Icons.arrow_forward), label: Text(last ? 'All done' : 'Next'))),
        ]),
      ]))),
    );
  }
}

