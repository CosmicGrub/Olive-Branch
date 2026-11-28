// OLIVE BRANCH — what a grown-up sees of app updates: Settings > "App updates", and one gentle card on the grown-up's home
// UNVERIFIED on a device; verified by CI headless (client/test).
// screen. ADULT-ONLY: these widgets are built by the guardian shell only (guardian_more.dart's Settings hub and
// guardian_home.dart); the child's shell and the kiosk never import this file (test/update_source_test.dart). The
// child never sees an update screen, a count, a prompt or an error (P1-P11). Verified headless
// (test/update_screens_test.dart: every phase). MASTERFILE 7.24.
//
// VOICE. Plain adult words, one idea per line, no jargon (no "APK", "sideload", "hash", "signature"), honest about what
// happened and about what did NOT: every message that could worry someone says that nothing was changed or lost. An
// update that cannot be checked is "ignored for safety", not an alarm.
import 'dart:async';

import 'package:flutter/material.dart';

import 'update_controller.dart';
import 'update_download.dart' show DownloadProgress;
import 'update_github.dart' show GithubRelease, kGithubOwner, kGithubRepo;
import 'update_manifest.dart';
import 'update_platform.dart';
import 'update_store.dart';
import 'update_transport.dart';

/// The one updater this run uses, installed by the guardian shell's boot (guardian_boot.dart) and by nothing else.
class UpdateHost {
  UpdateHost._();

  /// Null until the updater has started (it starts in the background, so the app never waits for it), and null for good
  /// in a build where the feature is absent.
  static final ValueNotifier<AppUpdater?> notifier = ValueNotifier<AppUpdater?>(null);
}

/// Makes the updater reachable below it, and gives it the chance to look when the app comes back to the front (at most
/// once a day: [AppUpdater.maybeCheckAtOpen] decides).
class UpdateScope extends StatefulWidget {
  /// [updater] is for tests; the app leaves it null and the scope follows [UpdateHost.notifier].
  const UpdateScope({super.key, this.updater, required this.child});
  final AppUpdater? updater;
  final Widget child;

  static AppUpdater? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_UpdateInherited>()?.updater;

  @override
  State<UpdateScope> createState() => _UpdateScopeState();
}

class _UpdateScopeState extends State<UpdateScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  AppUpdater? get _current => widget.updater ?? UpdateHost.notifier.value;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final AppUpdater? u = _current;
      if (u != null) {
        unawaited(u.recheckPermission());
        unawaited(u.maybeCheckAtOpen());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUpdater? fixed = widget.updater;
    if (fixed != null) return _UpdateInherited(updater: fixed, notifier: fixed, child: widget.child);
    return ValueListenableBuilder<AppUpdater?>(
      valueListenable: UpdateHost.notifier,
      child: widget.child,
      builder: (BuildContext context, AppUpdater? u, Widget? child) =>
          u == null ? child! : _UpdateInherited(updater: u, notifier: u, child: child!),
    );
  }
}

class _UpdateInherited extends InheritedNotifier<AppUpdater> {
  const _UpdateInherited({required this.updater, required AppUpdater notifier, required super.child})
      : super(notifier: notifier);
  final AppUpdater updater;
}

// ---- words -----------------------------------------------------------------

String updateSizeWords(int bytes) {
  final double mb = bytes / (1024 * 1024);
  if (mb < 1) return 'under 1 MB';
  return 'about ${mb.round()} MB';
}

const List<String> _months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String updateTimeWords(int? ms, DateTime now) {
  if (ms == null) return 'not yet';
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
  final String hh = t.hour.toString().padLeft(2, '0'), mm = t.minute.toString().padLeft(2, '0');
  final DateTime n = now.toLocal();
  final bool sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
  return sameDay ? 'today at $hh:$mm' : '${t.day} ${_months[t.month - 1]} ${t.year}, $hh:$mm';
}

/// The honest words for why something did not work. Every one that could worry says nothing was changed.
String updateFailureWords(UpdateRefusalCode c) {
  switch (c) {
    case UpdateRefusalCode.offline:
      return 'Olive could not reach the update source. This phone may have no connection. Nothing was changed.';
    case UpdateRefusalCode.noSpace:
      return 'There is not enough free space on this phone for the update. Free some up, then try again. Nothing was changed.';
    case UpdateRefusalCode.lowBattery:
      return 'The battery is low. Plug the phone in, then try again. Nothing was changed.';
    case UpdateRefusalCode.needsWifi:
      return 'This phone is not on Wi-Fi. The update will wait for Wi-Fi.';
    case UpdateRefusalCode.hashMismatch:
    case UpdateRefusalCode.sizeMismatch:
    case UpdateRefusalCode.tooMuchData:
    case UpdateRefusalCode.truncated:
      return 'The download was not what was promised, so Olive deleted it. Nothing was installed. '
          'You can try again, ideally on a different connection.';
    case UpdateRefusalCode.badRedirect:
    case UpdateRefusalCode.httpError:
      return 'The update source did not answer properly. Nothing was changed. Try again later.';
    case UpdateRefusalCode.certMismatch:
      return 'This file was not made by the same maker as the Olive on this phone, so Olive deleted it. Nothing was installed.';
    case UpdateRefusalCode.apkMismatch:
      return 'The file was not the update that was announced, so Olive deleted it. Nothing was installed.';
    case UpdateRefusalCode.needsPermission:
      return 'Android needs your OK first. Olive can install updates only if you allow it once in Android settings.';
    case UpdateRefusalCode.kioskLocked:
      return 'This screen is locked. A grown-up needs to leave the locked screen first, then install.';
    case UpdateRefusalCode.installRefused:
      return 'Android did not install the update. Nothing was changed on this phone.';
    case UpdateRefusalCode.installNotFinished:
      return 'The last install did not finish. Nothing was changed. The update is still here if you want to try again.';
    case UpdateRefusalCode.noApkForDevice:
      return 'There is no update built for this phone yet. Nothing was changed.';
    case UpdateRefusalCode.cancelled:
      return 'Stopped. What was downloaded is kept.';
    case UpdateRefusalCode.tooLarge:
    case UpdateRefusalCode.notJson:
    case UpdateRefusalCode.badShape:
    case UpdateRefusalCode.noKeyConfigured:
    case UpdateRefusalCode.unknownKey:
    case UpdateRefusalCode.badSignature:
    case UpdateRefusalCode.wrongApp:
    case UpdateRefusalCode.wrongChannel:
    case UpdateRefusalCode.notYetValid:
    case UpdateRefusalCode.expired:
    case UpdateRefusalCode.replayed:
    case UpdateRefusalCode.rollback:
    case UpdateRefusalCode.badUrl:
    case UpdateRefusalCode.sizeTooLarge:
      return 'An update notice could not be checked, so Olive ignored it for safety. Nothing was changed.';
  }
}

String updateChannelWords(String c) => c == 'stable' ? 'Stable' : (c == 'beta' ? 'Early (beta)' : c);

/// "example.org" from a full address: what an adult can recognise, never the path or anything after it.
String updateSourceHost(List<String> urls) {
  if (urls.isEmpty) return 'none';
  final Uri? u = Uri.tryParse(urls.first);
  final String h = (u == null || u.host.isEmpty) ? 'a custom address' : u.host;
  return urls.length > 1 ? '$h and ${urls.length - 1} more' : h;
}

// ---- the gentle card on the home screen -----------------------------------------

/// One quiet card at the top of the grown-up's home screen: an update is ready, this version is old, or an update just
/// finished. Nothing at all when there is nothing to say, when the build has no updater, or when "Later" was chosen.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUpdater? u = UpdateScope.maybeOf(context);
    if (u == null || !u.enabled) return const SizedBox.shrink();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final WhatsNew? wn = u.whatsNew;
    if (wn != null) {
      return _card(context, scheme,
          key: const Key('updateBannerWhatsNew'),
          icon: Icons.celebration_outlined,
          title: 'Olive was updated to ${wn.versionName}',
          body: wn.headline.isEmpty ? 'Everything on this phone is as you left it.' : wn.headline,
          actions: <Widget>[
            TextButton(key: const Key('updateBannerGotIt'), onPressed: u.dismissWhatsNew, child: const Text('Got it')),
            TextButton(onPressed: () => openAppUpdates(context), child: const Text("What's new")),
          ]);
    }
    if (u.belowMinimum) {
      return _card(context, scheme,
          key: const Key('updateBannerPlease'),
          icon: Icons.system_update_outlined,
          title: 'Please update Olive',
          body: 'This version is getting old. Everything still works and nothing will be lost. '
              'Updating keeps it working well with the rest of your family.',
          actions: <Widget>[
            FilledButton(onPressed: () => openAppUpdates(context), child: const Text('See the update')),
          ]);
    }
    if (u.bannerWanted) {
      final String name = u.manifest?.versionName ?? '';
      return _card(context, scheme,
          key: const Key('updateBannerReady'),
          icon: Icons.system_update_outlined,
          title: u.usesGithub && name.isNotEmpty ? 'Update available: $name' : 'An update is ready',
          body: name.isEmpty ? 'A new version of Olive is available.' : 'Olive $name is available.',
          actions: <Widget>[
            FilledButton(onPressed: () => openAppUpdates(context), child: const Text('See the update')),
            TextButton(key: const Key('updateBannerLater'), onPressed: u.later, child: const Text('Later')),
          ]);
    }
    return const SizedBox.shrink();
  }

  Widget _card(BuildContext context, ColorScheme scheme,
      {required Key key, required IconData icon, required String title, required String body, required List<Widget> actions}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        key: key,
        color: scheme.secondaryContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Icon(icon, color: scheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onSecondaryContainer))),
            ]),
            const SizedBox(height: 6),
            Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: actions),
          ]),
        ),
      ),
    );
  }
}

void openAppUpdates(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppUpdatesScreen()));
}

// ---- Settings > App updates --------------------------------------------------------

class AppUpdatesScreen extends StatefulWidget {
  const AppUpdatesScreen({super.key, this.updater, this.now});

  /// Tests pass one; the app reads it from [UpdateScope].
  final AppUpdater? updater;
  final DateTime Function()? now;

  @override
  State<AppUpdatesScreen> createState() => _AppUpdatesScreenState();
}

class _AppUpdatesScreenState extends State<AppUpdatesScreen> with WidgetsBindingObserver {
  Timer? _poll;
  final TextEditingController _url = TextEditingController();
  String? _urlProblem;

  AppUpdater? get _u => widget.updater ?? UpdateScope.maybeOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // While this page is open and a Wi-Fi download is waiting, look again now and then.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_u?.pollQueuedDownload()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _url.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) unawaited(_u?.recheckPermission());
  }

  @override
  Widget build(BuildContext context) {
    final AppUpdater? u = _u;
    if (u == null || !u.enabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('App updates')),
        body: const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Updates are not set up in this copy of Olive.', key: Key('updatesOff'))),
      );
    }
    return AnimatedBuilder(
      animation: u,
      builder: (BuildContext context, Widget? _) => Scaffold(
        appBar: AppBar(title: const Text('App updates')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            if (u.whatsNew != null) _whatsNew(context, u),
            if (u.belowMinimum) _pleaseUpdate(context),
            _status(context, u),
            const SizedBox(height: 8),
            _facts(context, u),
            const Divider(height: 32),
            _choices(context, u),
          ]),
        ),
      ),
    );
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  Widget _whatsNew(BuildContext context, AppUpdater u) {
    final WhatsNew w = u.whatsNew!;
    return Card(
      key: const Key('updateWhatsNew'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text("What's new in ${w.versionName}", style: Theme.of(context).textTheme.titleMedium),
          if (w.headline.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(w.headline)),
          for (final String n in w.notes) Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $n')),
          if (w.dataNote.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(w.dataNote, key: const Key('updateDataNote'))),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(key: const Key('updateWhatsNewGotIt'), onPressed: u.dismissWhatsNew, child: const Text('Got it'))),
        ]),
      ),
    );
  }

  Widget _pleaseUpdate(BuildContext context) => Card(
        key: const Key('updateBelowMinimum'),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Text('Please update. This version of Olive is getting old and may not work well with the rest of your '
              "family's phones. Everything on this phone still works, and nothing will be lost or locked."),
        ),
      );

  Widget _status(BuildContext context, AppUpdater u) {
    final TextTheme t = Theme.of(context).textTheme;
    final UpdateManifest? m = u.manifest;
    Widget title(String s) => Text(s, key: const Key('updateStatusTitle'), style: t.titleLarge);
    Widget line(String s, {Key? key}) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(s, key: key));
    final List<Widget> kids = <Widget>[];
    switch (u.phase) {
      case UpdatePhase.off:
        kids.add(title('Updates are not set up'));
      case UpdatePhase.idle:
        kids.add(title('Olive has not checked yet'));
        kids.add(line('Version ${u.environment?.installedVersionName ?? ''}'));
        kids.add(_checkButton(u));
      case UpdatePhase.checking:
        kids.add(title('Looking for an update'));
        kids.add(const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()));
      case UpdatePhase.upToDate:
        kids.add(title('Olive is up to date'));
        kids.add(line('Version ${u.environment?.installedVersionName ?? ''}'));
        kids.add(_checkButton(u));
      case UpdatePhase.available:
      case UpdatePhase.waitingForWifi:
      case UpdatePhase.needsPermission:
      case UpdatePhase.ready:
      case UpdatePhase.installing:
      case UpdatePhase.downloading:
      case UpdatePhase.failed:
        kids.addAll(_updateBody(context, u, m));
    }
    if (u.usesGithub && u.failure != null && _isCheckFailure(u.failure!) && u.phase != UpdatePhase.downloading) {
      // Only a grown-up who pressed the button ever sees this: a check in the background fails silently.
      kids.add(line('Could not check right now. Nothing was changed.', key: const Key('updateFailure')));
    } else if (u.failure != null &&
        (u.phase != UpdatePhase.available || u.failure == UpdateRefusalCode.offline) &&
        u.phase != UpdatePhase.downloading &&
        u.phase != UpdatePhase.installing) {
      kids.add(line(updateFailureWords(u.failure!), key: const Key('updateFailure')));
    } else if (u.failure == UpdateRefusalCode.installNotFinished && u.phase == UpdatePhase.available) {
      kids.add(line(updateFailureWords(u.failure!), key: const Key('updateFailure')));
    }
    return Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids)),
    );
  }

  static bool _isCheckFailure(UpdateRefusalCode c) =>
      c == UpdateRefusalCode.offline ||
      c == UpdateRefusalCode.httpError ||
      c == UpdateRefusalCode.badRedirect ||
      c == UpdateRefusalCode.badUrl ||
      c == UpdateRefusalCode.tooLarge ||
      c == UpdateRefusalCode.tooMuchData ||
      c == UpdateRefusalCode.notJson ||
      c == UpdateRefusalCode.badShape;

  Widget _checkButton(AppUpdater u) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton(
            key: const Key('updateCheckNow'),
            onPressed: u.busy ? null : () => unawaited(u.checkNow()),
            child: Text(u.usesGithub ? 'Check for updates' : 'Check now')),
      );

  Widget _missed(BuildContext context, AppUpdater u) {
    final List<GithubRelease> older = u.missedReleases;
    if (older.isEmpty) return const SizedBox.shrink();
    final TextTheme t = Theme.of(context).textTheme;
    return Column(key: const Key('updateMissed'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Padding(padding: const EdgeInsets.only(top: 14), child: Text('Also since this version', style: t.titleSmall)),
      for (final GithubRelease r in older)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('Olive ${r.versionName}${r.prerelease ? ' (preview)' : ''}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (r.headline.isNotEmpty) Text(r.headline),
            for (final String n in r.notes) Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $n')),
          ]),
        ),
    ]);
  }

  List<Widget> _updateBody(BuildContext context, AppUpdater u, UpdateManifest? m) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool play = u.flavor == UpdateFlavor.play;
    final String name = m?.versionName ?? '';
    final String size = m != null && !play ? ' · ${updateSizeWords(u.apk?.size ?? 0)}' : '';
    final List<Widget> kids = <Widget>[];
    switch (u.phase) {
      case UpdatePhase.downloading:
        kids.add(Text('Downloading the update', key: const Key('updateStatusTitle'), style: t.titleLarge));
      case UpdatePhase.ready:
        kids.add(Text(play ? 'Ready to finish' : 'Ready to install', key: const Key('updateStatusTitle'), style: t.titleLarge));
      case UpdatePhase.installing:
        kids.add(Text('Waiting for Android', key: const Key('updateStatusTitle'), style: t.titleLarge));
      case UpdatePhase.waitingForWifi:
        kids.add(Text('Waiting for Wi-Fi', key: const Key('updateStatusTitle'), style: t.titleLarge));
      case UpdatePhase.needsPermission:
        kids.add(Text('One thing to allow first', key: const Key('updateStatusTitle'), style: t.titleLarge));
      case UpdatePhase.failed:
        kids.add(Text('That did not work', key: const Key('updateStatusTitle'), style: t.titleLarge));
      default:
        kids.add(Text('An update is ready', key: const Key('updateStatusTitle'), style: t.titleLarge));
    }
    if (u.phase != UpdatePhase.failed || m != null) {
      kids.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(name.isEmpty ? 'A new version of Olive' : 'Olive $name$size', key: const Key('updateVersionLine'))));
      if (m != null && m.headline.isNotEmpty) {
        kids.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(m.headline, style: t.titleSmall)));
      }
      if (m != null) {
        kids.add(Column(key: const Key('updateNotes'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          for (final String n in m.notes) Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $n')),
        ]));
        if (u.usesGithub && u.offerIsPrerelease) {
          kids.add(const Padding(
              padding: EdgeInsets.only(top: 6), child: Text('This is a preview version.', key: Key('updatePreviewNote'))));
        }
        if (u.usesGithub) kids.add(_missed(context, u));
      }
    }
    switch (u.phase) {
      case UpdatePhase.available:
        if (play) {
          kids.add(_btn('updatePlayStart', 'Update', () => u.startPlayUpdate()));
        } else {
          kids.add(const SizedBox(height: 12));
          kids.add(Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            FilledButton(
                key: const Key('updateDownloadWifi'),
                onPressed: () => unawaited(u.downloadOnWifi()),
                child: const Text('Download on Wi-Fi')),
            OutlinedButton(
                key: const Key('updateDownloadNow'),
                onPressed: () => unawaited(_downloadNow(context, u)),
                child: Text(u.usesGithub ? 'Update now' : 'Download now')),
            TextButton(key: const Key('updateLater'), onPressed: () => unawaited(u.later()), child: const Text('Later')),
          ]));
        }
      case UpdatePhase.waitingForWifi:
        kids.add(const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('It will download by itself the next time this phone is on Wi-Fi and Olive is open. '
                'What has already downloaded is kept.')));
        kids.add(const SizedBox(height: 12));
        kids.add(Wrap(spacing: 8, children: <Widget>[
          OutlinedButton(
              key: const Key('updateDownloadNow'), onPressed: () => unawaited(_downloadNow(context, u)), child: const Text('Download now')),
          TextButton(key: const Key('updateLater'), onPressed: () => unawaited(u.later()), child: const Text('Later')),
        ]));
      case UpdatePhase.downloading:
        final DownloadProgress? p = u.progress;
        kids.add(Padding(
            padding: const EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(key: const Key('updateProgress'), value: p == null || p.totalBytes == 0 ? null : p.fraction)));
        if (p != null && p.totalBytes > 0) {
          kids.add(Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${(p.doneBytes / (1024 * 1024)).floor()} MB of ${(p.totalBytes / (1024 * 1024)).ceil()} MB',
                  key: const Key('updateProgressText'))));
        }
        if (!play) {
          kids.add(const SizedBox(height: 10));
          kids.add(TextButton(key: const Key('updateStop'), onPressed: u.stopDownload, child: const Text('Stop')));
        }
      case UpdatePhase.ready:
        if (play) {
          kids.add(_btn('updatePlayFinish', 'Restart to finish', () => u.finishPlayUpdate()));
        } else {
          kids.add(const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text("Android will ask you to confirm. Your family's information stays on this phone.")));
          kids.add(_btn('updateInstall', 'Install', () => u.install()));
        }
      case UpdatePhase.needsPermission:
        kids.add(const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Android asks you to allow Olive to install updates, once. Nothing is installed until you confirm.')));
        kids.add(_btn('updateOpenSettings', 'Open Android settings', () => u.openInstallSettings()));
      case UpdatePhase.installing:
        kids.add(const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Please answer the question Android is asking. If you did not see it, come back here and try again.')));
      case UpdatePhase.failed:
        kids.add(const SizedBox(height: 10));
        kids.add(_checkButton(u));
      default:
        break;
    }
    return kids;
  }

  Widget _btn(String key, String label, Future<void> Function() onTap) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(key: Key(key), onPressed: () => unawaited(onTap()), child: Text(label))),
      );

  Future<void> _downloadNow(BuildContext context, AppUpdater u) async {
    final UpdateEnvironment? e = u.environment;
    final UpdateManifest? m = u.manifest;
    if (e != null && !e.onUnmeteredWifi && m != null) {
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          key: const Key('updateMobileDataDialog'),
          title: const Text('Use mobile data?'),
          content: Text(e.roaming
              ? 'You are roaming, which can cost extra. The update is ${updateSizeWords(u.apk?.size ?? 0)}.'
              : 'This phone is not on Wi-Fi. The update is ${updateSizeWords(u.apk?.size ?? 0)} and may use your mobile data.'),
          actions: <Widget>[
            TextButton(key: const Key('updateMobileDataNo'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(key: const Key('updateMobileDataYes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Download')),
          ],
        ),
      );
      if (go != true) return;
    }
    await u.downloadNow();
  }

  Widget _facts(BuildContext context, AppUpdater u) {
    final DateTime now = _now();
    final UpdateState s = u.state;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text('Last checked: ${updateTimeWords(s.lastCheckMs, now)}', key: const Key('updateLastCheck'), style: t.bodyMedium),
      if (s.lastUpdatedName.isNotEmpty)
        Text('Last updated to ${s.lastUpdatedName} ${updateTimeWords(s.lastUpdatedMs, now)}',
            key: const Key('updateLastVersion'), style: t.bodyMedium),
      Text('Installed: ${u.environment?.installedVersionName ?? ''}', style: t.bodyMedium),
    ]);
  }

  Widget _choices(BuildContext context, AppUpdater u) {
    final UpdateState s = u.state;
    final bool play = u.flavor == UpdateFlavor.play;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text('Choices', style: Theme.of(context).textTheme.titleMedium),
      SwitchListTile(
        key: const Key('updateAutoCheck'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Look for updates by itself'),
        subtitle: const Text('About once a day, when Olive is opened.'),
        value: s.autoCheck,
        onChanged: (bool v) => unawaited(u.setAutoCheck(v)),
      ),
      if (!play)
        SwitchListTile(
          key: const Key('updateWifiOnly'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Only on Wi-Fi'),
          subtitle: const Text('Never uses mobile data unless you press Download now.'),
          value: s.wifiOnly,
          onChanged: (bool v) => unawaited(u.setWifiOnly(v)),
        ),
      if (!play && u.usesGithub) ...<Widget>[
        const SizedBox(height: 8),
        const Text('Where updates come from: GitHub releases of $kGithubOwner/$kGithubRepo (github.com)',
            key: Key('updateSource')),
        const SizedBox(height: 8),
        const Text(
            'Updates from GitHub are as trustworthy as that GitHub account: Olive checks that the file is the size and '
            'fingerprint the release states, and Android only accepts a file made by the same maker as this Olive. '
            'Preview builds are signed with a public test key, so they only update a copy signed the same way. '
            'The stronger way, updates signed by the maker with a private key, is used instead whenever one is set up.',
            key: Key('updateGithubHonesty')),
      ],
      if (!play && !u.usesGithub) ...<Widget>[
        const SizedBox(height: 8),
        Text('Where updates come from: ${updateSourceHost(u.manifestUrls)}', key: const Key('updateSource')),
        const SizedBox(height: 8),
        TextField(
          key: const Key('updateSourceField'),
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
              labelText: 'Use a different source (a web address)',
              errorText: _urlProblem,
              border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: <Widget>[
          FilledButton(
              key: const Key('updateSourceSave'),
              onPressed: () async {
                final String? why = await u.setManifestUrl(_url.text);
                if (!mounted) return;
                setState(() => _urlProblem = why == null ? null : 'Olive can only use a secure web address (https). $why.');
                if (why == null) _url.clear();
              },
              child: const Text('Use this source')),
          if (s.manifestUrl != null)
            TextButton(
                key: const Key('updateSourceReset'),
                onPressed: () async {
                  await u.setManifestUrl(null);
                  if (mounted) setState(() => _urlProblem = null);
                },
                child: const Text('Go back to the usual source')),
        ]),
        const SizedBox(height: 12),
        Text('Channel', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          key: const Key('updateChannel'),
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'stable', label: Text('Stable')),
            ButtonSegment<String>(value: 'beta', label: Text('Early (beta)')),
          ],
          selected: <String>{u.channel == 'beta' ? 'beta' : 'stable'},
          onSelectionChanged: (Set<String> v) => unawaited(u.setChannel(v.first)),
        ),
        const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Stable is for everyday use. Early versions come sooner and may have rough edges.')),
      ],
      const SizedBox(height: 16),
      Text(
          u.usesGithub
              ? 'Android always asks you to confirm first. Nothing is ever installed in the background.'
              : 'Olive only installs an update that was signed by its maker, and Android always asks you to confirm '
                  'first. Nothing is ever installed in the background.'),
    ]);
  }
}
