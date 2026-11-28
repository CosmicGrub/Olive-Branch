// OLIVE BRANCH — the grown-up's screens for the tablet update path. Verified headless
// UNVERIFIED on a device; verified by CI headless (client/test).
// (test/tablet_update_screens_test.dart). MASTERFILE section 7.25.
//
// TWO SURFACES, BOTH ADULT-ONLY.
//   1. [TabletUpdateCard] — inside Guardian mode on the child's tablet (guardian_escalation_screen.dart), which is only
//      reachable after a grown-up proved themselves with the PIN and the biometric. It draws nothing at all when this
//      build has no update machinery. The child's own screens (ChildHome and everything under it) never contain it,
//      never count, never badge and never prompt (P1 to P11); a test holds that line.
//   2. [ShareUpdateScreen] — on the grown-up's own phone, behind its settings, where a grown-up says "Share with the
//      tablet".
//
// WORDS. Plain, calm, for adults: what is happening, what is safe, what to do next. Failures say that nothing was
// installed and nothing was lost. The kiosk is explained in the one sentence a grown-up needs: Android has to let go of
// the "App is pinned" lock for a moment so its own installer can show, and the app puts it back afterwards.
import 'dart:async';

import 'package:flutter/material.dart';

import 'play_confirm_card.dart';
import 'tablet_update_port.dart';
import 'tablet_update_receiver.dart';
import 'tablet_update_sender.dart';
import 'tablet_update_service.dart';
import 'tablet_update_store.dart';

/// "12.3 MB" for a grown-up. Never shown on a child surface.
String friendlyMegabytes(int bytes) {
  final double mb = bytes / (1024 * 1024);
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}

class TabletUpdateCard extends StatelessWidget {
  const TabletUpdateCard({super.key, this.service, required this.adultPresent});

  /// Null means "the app-wide one"; a test passes its own.
  final TabletUpdateService? service;

  /// True while a grown-up is proved at this tablet (the Guardian-mode escalation is live).
  final bool Function() adultPresent;

  @override
  Widget build(BuildContext context) {
    final TabletUpdateService? s = service ?? TabletUpdateService.current;
    if (s == null || !s.available) return const SizedBox.shrink();
    return _TabletUpdateBody(service: s, adultPresent: adultPresent);
  }
}

class _TabletUpdateBody extends StatefulWidget {
  const _TabletUpdateBody({required this.service, required this.adultPresent});
  final TabletUpdateService service;
  final bool Function() adultPresent;

  @override
  State<_TabletUpdateBody> createState() => _TabletUpdateBodyState();
}

class _TabletUpdateBodyState extends State<_TabletUpdateBody> {
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
    widget.service.refresh();
  }

  @override
  void didUpdateWidget(_TabletUpdateBody old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      old.service.removeListener(_changed);
      widget.service.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    super.dispose();
  }

  TabletUpdateService get s => widget.service;
  bool Function() get adult => widget.adultPresent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Widget> kids = <Widget>[];
    final WhatsNew? wn = s.whatsNew;
    if (wn != null) kids.add(_whatsNewCard(theme, wn));
    kids.add(Card(
      key: const Key('tabletUpdateCard'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(padding: const EdgeInsets.all(16), child: _content(context, theme)),
    ));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids);
  }

  Widget _whatsNewCard(ThemeData theme, WhatsNew wn) => Card(
        key: const Key('tabletUpdateWhatsNew'),
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Updated to Olive Branch ${wn.versionName}', style: theme.textTheme.titleMedium),
            if (wn.headline.isNotEmpty) Text(wn.headline),
            for (final String n in wn.notes) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $n')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(key: const Key('tabletUpdateWhatsNewDone'), onPressed: s.dismissWhatsNew, child: const Text('Got it')),
            ),
          ]),
        ),
      );

  Widget _notes(List<String> notes) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[for (final String n in notes) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $n'))],
      );

  Widget _words(String text, {Key? key}) => Text(text, key: key);

  List<Widget> _ownOption(bool primary) {
    final OwnUpdateOffer? o = s.ownOffer;
    if (o == null) return const <Widget>[];
    final Widget b = primary
        ? FilledButton(key: const Key('tabletUpdateFetchOwn'), onPressed: () => s.fetchOwn(adultPresent: adult), child: const Text('Download on this tablet'))
        : OutlinedButton(key: const Key('tabletUpdateFetchOwn'), onPressed: () => s.fetchOwn(adultPresent: adult), child: const Text('Download on this tablet instead'));
    return <Widget>[b];
  }

  Widget _fromPhone(bool primary) {
    void go() => unawaited(s.startReceiving(adultPresent: adult));
    return primary
        ? FilledButton(key: const Key('tabletUpdateFromPhone'), onPressed: go, child: const Text('Get it from the phone'))
        : OutlinedButton(key: const Key('tabletUpdateFromPhone'), onPressed: go, child: const Text('Get it from the phone'));
  }

  Widget _content(BuildContext context, ThemeData theme) {
    final TabletUpdateView v = s.view;
    final TabletUpdateReceiver? r = s.receiver;
    switch (v) {
      case TabletUpdateView.none:
        final bool online = s.ownOffer != null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(online ? 'An update is available' : 'Update this tablet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          _words(online
              ? 'This tablet is online and can download it itself. Or take it from your phone, with no internet.'
              : 'If your phone has an update ready, this tablet can take it from the phone. No internet is needed.'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[..._ownOption(true), _fromPhone(!online)]),
        ]);
      case TabletUpdateView.listening:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Looking for your phone', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          _words('On your phone, open Settings, then Share update with the tablet. Keep the two close together.'),
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
          const SizedBox(height: 10),
          TextButton(key: const Key('tabletUpdateStop'), onPressed: s.stopReceiving, child: const Text('Stop looking')),
        ]);
      case TabletUpdateView.offered:
        final VerifiedUpdate u = r!.offered!;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Your phone has Olive Branch ${u.versionName}', style: theme.textTheme.titleMedium),
          if (u.headline.isNotEmpty) Text(u.headline),
          _notes(u.notes),
          const SizedBox(height: 6),
          Text('${friendlyMegabytes(u.apk.size)}. Nothing is installed yet.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: <Widget>[
            FilledButton(key: const Key('tabletUpdateGet'), onPressed: s.acceptOffer, child: const Text('Get it')),
            TextButton(key: const Key('tabletUpdateNotNow'), onPressed: s.stopReceiving, child: const Text('Not now')),
          ]),
        ]);
      case TabletUpdateView.downloading:
        final double? p = s.progress;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Getting the update', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          _words('Keep the phone close. If it is interrupted, it carries on from where it stopped.'),
          const SizedBox(height: 10),
          LinearProgressIndicator(key: const Key('tabletUpdateProgress'), value: p),
          const SizedBox(height: 10),
          TextButton(key: const Key('tabletUpdateStop'), onPressed: s.stopReceiving, child: const Text('Stop')),
        ]);
      case TabletUpdateView.paused:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Lost touch with the phone', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          _words(tabletUpdateAdultWords(TabletUpdateCode.lostTouch)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: <Widget>[
            FilledButton(key: const Key('tabletUpdateTryAgain'), onPressed: () => s.startReceiving(adultPresent: adult), child: const Text('Try again')),
            TextButton(key: const Key('tabletUpdateStop'), onPressed: s.stopReceiving, child: const Text('Stop')),
          ]),
        ]);
      case TabletUpdateView.verifying:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Checking the update', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ]);
      case TabletUpdateView.ready:
        final StagedUpdate st = s.staged!;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('An update is ready', style: theme.textTheme.titleMedium),
          Text('Olive Branch ${st.versionName}. Install it?'),
          if (st.headline.isNotEmpty) Text(st.headline),
          _notes(st.notes),
          const SizedBox(height: 8),
          _words('Android will ask you to confirm. To let it, this tablet lets go of the "App is pinned" lock for a '
              'moment and holds it again afterwards. Nothing on the tablet is lost.'),
          if (s.result != null) ...<Widget>[
            const SizedBox(height: 8),
            _words(tabletUpdateAdultWords(s.result!), key: const Key('tabletUpdateResult')),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            FilledButton(key: const Key('tabletUpdateInstall'), onPressed: () => s.install(adultPresent: adult), child: const Text('Install it')),
            TextButton(key: const Key('tabletUpdateDiscard'), onPressed: s.discardStaged, child: const Text('Not now')),
          ]),
        ]);
      case TabletUpdateView.checkingInstall:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Checking before installing', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ]);
      case TabletUpdateView.installing:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Follow Android on the screen', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          _words('Tap Install when Android asks. When it says the app is installed, tap Open. '
              'If Android asks whether to pin the app again, choose Start.'),
        ]);
      case TabletUpdateView.refused:
        final TabletUpdateCode code = s.result ?? r?.refusal ?? TabletUpdateCode.cancelled;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('The update was not taken', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          _words(tabletUpdateAdultWords(code), key: const Key('tabletUpdateResult')),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[..._ownOption(true), _fromPhone(s.ownOffer == null)]),
        ]);
    }
  }
}

/// The grown-up's phone: "Share with the tablet". Behind the phone's settings; the confirmation card for a tablet's
/// first connection appears over it, as in every Play-together screen.
class ShareUpdateScreen extends StatefulWidget {
  const ShareUpdateScreen({super.key, this.service, this.tabletName = 'the tablet'});
  final TabletUpdateService? service;
  final String tabletName;

  @override
  State<ShareUpdateScreen> createState() => _ShareUpdateScreenState();
}

class _ShareUpdateScreenState extends State<ShareUpdateScreen> {
  TabletUpdateService? get _s => widget.service ?? TabletUpdateService.current;
  HeldUpdate? _held;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _s?.addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    final HeldUpdate? h = await _s?.held();
    if (!mounted) return;
    setState(() {
      _held = h;
      _loaded = true;
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final TabletUpdateService? s = _s;
    if (s != null) {
      s.removeListener(_changed);
      s.stopSharing();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TabletUpdateService? s = _s;
    final ThemeData theme = Theme.of(context);
    final TabletUpdateSender? sender = s?.sender;
    final Widget body;
    if (s == null || !s.available) {
      body = const Text('Updates are not set up on this build.');
    } else if (!_loaded) {
      body = const LinearProgressIndicator();
    } else if (_held == null) {
      body = const Text('This phone does not have an update waiting to share. When it finds and checks one, it will be here.',
          key: Key('shareNone'));
    } else {
      final VerifiedUpdate u = _held!.update;
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Olive Branch ${u.versionName}', style: theme.textTheme.titleLarge),
        if (u.headline.isNotEmpty) Text(u.headline),
        for (final String n in u.notes) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $n')),
        const SizedBox(height: 4),
        Text(friendlyMegabytes(u.apk.size), style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        if (sender == null || sender.phase == SenderPhase.idle || sender.phase == SenderPhase.stopped || sender.phase == SenderPhase.refused || sender.phase == SenderPhase.delivered) ...<Widget>[
          if (sender?.phase == SenderPhase.delivered)
            const Text('Done. The tablet has the update. A grown-up installs it on the tablet.', key: Key('shareDone'))
          else if (sender?.phase == SenderPhase.refused)
            const Text('The tablet did not take the update. Nothing was installed.', key: Key('shareRefused'))
          else if (s.result != null)
            Text(tabletUpdateAdultWords(s.result!), key: const Key('shareResult')),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('shareStart'),
            onPressed: () => s.startSharing(adultPresent: () => true),
            child: Text('Share with ${widget.tabletName}'),
          ),
        ] else ...<Widget>[
          Text(
            sender.phase == SenderPhase.offering
                ? 'Waiting for the tablet. On the tablet, tap the small shield, enter the PIN, then choose Get it from the phone.'
                : 'Sending to the tablet. Keep the two close together.',
            key: const Key('shareStatus'),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: sender.phase == SenderPhase.sending && sender.apkSize > 0 ? sender.sentApkBytes / sender.apkSize : null),
          const SizedBox(height: 10),
          TextButton(key: const Key('shareStop'), onPressed: s.stopSharing, child: const Text('Stop sharing')),
        ],
      ]);
    }
    return PlayConfirmOverlay(
      pairing: s?.link?.pairing,
      child: Scaffold(
        appBar: AppBar(title: const Text('Share update with the tablet')),
        body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: body)),
      ),
    );
  }
}
