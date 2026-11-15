// OLIVE BRANCH — the screens for sharing a screen from one grown-up to another: the capture, the preview with its two
// tools, the inbox and the viewer. Verified by CI headless (client/test/screen_share_ui_test.dart). Logic, rules and the
// sealed format are in screen_share.dart; read its header first. Plain adult words (section 8.1). Grown-up app only: the
// child shell never builds anything in this file, and the service on a child's device has no recipients at all.
//
//  * "Share this screen" is a quiet icon in the bar of ordinary grown-up screens. It is HIDDEN when there is nobody to
//    send to (a family with one grown-up, or no family record yet) and on any sensitive screen.
//  * It captures the screen ITSELF, inside the app, so it works while system screenshots are blocked.
//  * Before anything leaves the phone the grown-up sees the picture, who it will go to, "Hide names and photos" (solid
//    blocks over the places a screen marked as a child's name or picture with [ShareRedact]; the original is kept only in
//    memory on the preview), an optional note, and how long it lasts.
//  * "Hide names and photos" can only hide what a screen marked. A screen with no marked places says so and the switch
//    stays off, rather than promise something it cannot do.
//  * A received picture is shown on a screen that blocks capture and has no send, share or save action.
// UNVERIFIED on a device: the headless tests are the only proof so far; it needs a hardware pass before it is relied on.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_lock.dart';
import 'screen_privacy.dart';
import 'screen_share.dart';

/// Marks a place that shows a child's name or picture, so "Hide names and photos" can cover it in a shared screen.
class ShareRedact extends StatefulWidget {
  const ShareRedact({super.key, required this.child});
  final Widget child;
  @override
  State<ShareRedact> createState() => _ShareRedactState();
}

class _ShareRedactState extends State<ShareRedact> {
  ShareScopeData? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ShareScopeData? s = ShareScope.maybeOf(context);
    if (!identical(s, _scope)) {
      _scope?._marks.remove(this);
      _scope = s;
      _scope?._marks.add(this);
    }
  }

  @override
  void dispose() {
    _scope?._marks.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What the capture scope hands to the screens below it.
class ShareScopeData {
  ShareScopeData({required this.boundaryKey, required this.service, required this.lock});
  final GlobalKey boundaryKey;
  final ScreenShareService? service;
  final AppLockController? lock;
  final Set<_ShareRedactState> _marks = <_ShareRedactState>{};
}

class ShareScope extends InheritedWidget {
  const ShareScope({super.key, required this.data, required super.child});
  final ShareScopeData data;
  static ShareScopeData? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShareScope>()?.data;
  @override
  bool updateShouldNotify(ShareScope old) => !identical(old.data, data);
}

/// Sits above the Navigator in the grown-up app. Makes the whole app one capture target and offers the service.
class ShareCaptureScope extends StatefulWidget {
  const ShareCaptureScope({super.key, required this.service, required this.child});
  final ScreenShareService? service;
  final Widget child;
  @override
  State<ShareCaptureScope> createState() => _ShareCaptureScopeState();
}

class _ShareCaptureScopeState extends State<ShareCaptureScope> {
  final GlobalKey _key = GlobalKey(debugLabel: 'shareBoundary');
  ShareScopeData? _data;

  @override
  Widget build(BuildContext context) {
    final AppLockController? lock = AppLockScope.maybeOf(context);
    final ShareScopeData? old = _data;
    if (old == null || !identical(old.service, widget.service) || !identical(old.lock, lock)) {
      _data = ShareScopeData(boundaryKey: _key, service: widget.service, lock: lock);
      if (old != null) _data!._marks.addAll(old._marks);
    }
    return ShareScope(data: _data!, child: RepaintBoundary(key: _key, child: widget.child));
  }
}

/// A captured screen: the picture as the phone drew it, and the places a screen marked as a name or a picture.
class ShareCapture {
  ShareCapture(this.image, this.hideRects);
  final ui.Image image;

  /// In the picture's own pixels.
  final List<Rect> hideRects;
  void dispose() => image.dispose();
}

/// Captures the whole app as it is drawn now. Null when it cannot be done.
Future<ShareCapture?> captureScreen(ShareScopeData scope, {double maxRatio = 1.5}) async {
  final BuildContext? ctx = scope.boundaryKey.currentContext;
  if (ctx == null) return null;
  final RenderObject? ro = ctx.findRenderObject();
  if (ro is! RenderRepaintBoundary || !ro.attached) return null;
  final double ratio = min(maxRatio, View.of(ctx).devicePixelRatio);
  final ui.Image image = await ro.toImage(pixelRatio: ratio);
  final List<Rect> rects = <Rect>[];
  for (final _ShareRedactState m in scope._marks) {
    if (!m.mounted) continue;
    final ModalRoute<Object?>? route = ModalRoute.of(m.context);
    if (route != null && !route.isCurrent) continue;
    final RenderObject? r = m.context.findRenderObject();
    if (r is! RenderBox || !r.attached || !r.hasSize) continue;
    final Offset topLeft = ro.globalToLocal(r.localToGlobal(Offset.zero));
    rects.add(Rect.fromLTWH(topLeft.dx * ratio, topLeft.dy * ratio, r.size.width * ratio, r.size.height * ratio));
  }
  return ShareCapture(image, rects);
}

/// Makes the PNG that would be sent: the picture, with solid blocks over the marked places when [hideNames], scaled down
/// until it fits [kShareMaxImageBytes]. Null if it cannot be made small enough.
Future<Uint8List?> renderShare(ShareCapture cap, {required bool hideNames}) async {
  for (final double scale in <double>[1.0, 0.75, 0.5, 0.35]) {
    final int w = max(1, (cap.image.width * scale).round()), h = max(1, (cap.image.height * scale).round());
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    c.drawImageRect(cap.image, Rect.fromLTWH(0, 0, cap.image.width.toDouble(), cap.image.height.toDouble()),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..filterQuality = FilterQuality.medium);
    if (hideNames) {
      final Paint block = Paint()..color = const Color(0xFF455A64);
      for (final Rect r in cap.hideRects) {
        // Solid, not blurred: a blur can be partly undone, a block cannot. A little margin so edges do not peek out.
        c.drawRect(Rect.fromLTRB(r.left * scale - 4, r.top * scale - 4, r.right * scale + 4, r.bottom * scale + 4), block);
      }
    }
    final ui.Picture pic = rec.endRecording();
    final ui.Image out = await pic.toImage(w, h);
    final ByteData? data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    pic.dispose();
    if (data == null) continue;
    final Uint8List png = data.buffer.asUint8List();
    if (png.length <= kShareMaxImageBytes) return png;
  }
  return null;
}

/// The "Share this screen" icon for a grown-up screen's bar. Takes no room when there is nobody to send to.
class ShareScreenAction extends StatefulWidget {
  const ShareScreenAction({super.key});
  @override
  State<ShareScreenAction> createState() => _ShareScreenActionState();
}

class _ShareScreenActionState extends State<ShareScreenAction> {
  List<ShareRecipient> _who = const <ShareRecipient>[];
  ScreenShareService? _for;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ScreenShareService? s = ShareScope.maybeOf(context)?.service;
    if (identical(s, _for)) return;
    _for = s;
    _who = const <ShareRecipient>[];
    if (s != null) unawaited(_load(s));
  }

  Future<void> _load(ScreenShareService s) async {
    List<ShareRecipient> who;
    try {
      who = await s.recipients();
    } catch (_) {
      who = const <ShareRecipient>[];
    }
    if (mounted && identical(_for, s)) setState(() => _who = who);
  }

  Future<void> _tap() async {
    final ShareScopeData? scope = ShareScope.maybeOf(context);
    final ScreenShareService? svc = scope?.service;
    if (scope == null || svc == null || _busy) return;
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (scope.lock?.sensitiveNow ?? false) {
      messenger.showSnackBar(const SnackBar(content: Text('This screen can not be shared.')));
      return;
    }
    setState(() => _busy = true);
    final ShareCapture? cap;
    try {
      cap = await captureScreen(scope);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (cap == null) {
      messenger.showSnackBar(const SnackBar(content: Text('That screen could not be captured. Nothing was sent.')));
      return;
    }
    final ShareCapture taken = cap;
    await nav.push<void>(MaterialPageRoute<void>(
        builder: (_) => ShareScreenPreview(service: svc, capture: taken, recipients: _who)));
    taken.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sensitive = (ShareScope.maybeOf(context)?.lock?.sensitiveNow) ?? false;
    if (_who.isEmpty || sensitive) return const SizedBox.shrink();
    return IconButton(
      key: const Key('shareScreenAction'),
      tooltip: 'Share this screen with another grown-up',
      icon: const Icon(Icons.mobile_screen_share_outlined),
      onPressed: _busy ? null : _tap,
    );
  }
}

/// Before it sends: the picture, who gets it, the two tools, how long it lasts.
class ShareScreenPreview extends StatefulWidget {
  const ShareScreenPreview({super.key, required this.service, required this.capture, required this.recipients});
  final ScreenShareService service;
  final ShareCapture capture;
  final List<ShareRecipient> recipients;
  @override
  State<ShareScreenPreview> createState() => _ShareScreenPreviewState();
}

class _ShareScreenPreviewState extends State<ShareScreenPreview> {
  bool _hide = false, _working = false;
  int _days = kShareDefaultExpiryDays;
  late ShareRecipient _to = widget.recipients.first;
  final TextEditingController _note = TextEditingController();
  Uint8List? _png;
  bool _pngHidden = false; // whether the bytes in [_png] were drawn with names hidden
  int _renderSeq = 0; // only the newest render may fill [_png]
  String? _result;
  bool _sentOk = false;

  @override
  void initState() {
    super.initState();
    unawaited(_render());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    final int seq = ++_renderSeq;
    final bool hide = _hide && widget.capture.hideRects.isNotEmpty;
    // Send stays off until the newest picture is ready, so the picture and the 'hidden' flag always agree.
    if (_png != null) setState(() => _png = null);
    final Uint8List? p = await renderShare(widget.capture, hideNames: hide);
    if (!mounted || seq != _renderSeq) return; // a newer render has started: this result is stale
    setState(() {
      _png = p;
      _pngHidden = hide;
    });
  }

  Future<void> _send() async {
    final Uint8List? p = _png;
    if (p == null || _working) return;
    setState(() => _working = true);
    try {
      final ShareSendOutcome o = await widget.service.send(
          png: p, to: _to, namesHidden: _pngHidden, note: _note.text.trim(), expiryDays: _days);
      if (!mounted) return;
      setState(() {
        _sentOk = true;
        _result = o == ShareSendOutcome.sent
            ? 'Sent to ${_to.name}.'
            : "${_to.name} isn't nearby. It will go when your phones meet.";
      });
    } on ShareRefused {
      if (mounted) setState(() => _result = 'That could not be shared. Nothing was sent.');
    } catch (_) {
      if (mounted) setState(() => _result = 'That could not be kept on this phone. Nothing was sent.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canHide = widget.capture.hideRects.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Share this screen')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          Card(
            key: const Key('shareBanner'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('This goes to ${_to.name} only, inside Olive. Never to a child, and never out to the phone\'s '
                  'own share menu.'),
            ),
          ),
          const SizedBox(height: 12),
          if (_png == null)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Image.memory(_png!, key: const Key('sharePreviewImage'), fit: BoxFit.contain,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stack) => const Text('The preview could not be shown.')),
            ),
          const SizedBox(height: 12),
          if (widget.recipients.length > 1)
            RadioGroup<String>(
              groupValue: _to.keyHex,
              onChanged: (String? v) {
                if (v == null) return;
                setState(() => _to = widget.recipients.firstWhere((ShareRecipient r) => r.keyHex == v));
              },
              child: Column(children: <Widget>[
                for (final ShareRecipient r in widget.recipients)
                  RadioListTile<String>(key: Key('shareTo_${r.keyHex}'), title: Text(r.name), value: r.keyHex),
              ]),
            ),
          SwitchListTile(
            key: const Key('shareHideNames'),
            title: const Text('Hide names and photos'),
            subtitle: Text(canHide
                ? 'Covers the places on this screen that show a child\'s name or picture.'
                : 'Nothing on this screen is marked as a child\'s name or picture, so there is nothing for this to hide. '
                    'Look at the picture before you send it.'),
            value: _hide && canHide,
            onChanged: canHide
                ? (bool v) {
                    setState(() => _hide = v);
                    unawaited(_render());
                  }
                : null,
          ),
          TextField(
            key: const Key('shareNote'),
            controller: _note,
            maxLength: kShareMaxNoteChars,
            decoration: const InputDecoration(labelText: 'Add a note (optional)'),
          ),
          ListTile(
            title: const Text('Lasts'),
            trailing: DropdownButton<int>(
              key: const Key('shareDays'),
              value: _days,
              items: const <int>[1, 3, 7, 14, 30]
                  .map((int d) => DropdownMenuItem<int>(value: d, child: Text(d == 1 ? '1 day' : '$d days')))
                  .toList(),
              onChanged: (int? v) => setState(() => _days = v ?? _days),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
                'You can take it back at any time, and it goes by itself when the time is up. Honest limit: a grown-up who '
                'has it could photograph their screen with another device, and Olive cannot stop that.',
                key: Key('shareLimit')),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_result!, key: const Key('shareResult')),
            ),
          if (_sentOk)
            FilledButton(key: const Key('shareDone'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done'))
          else
            FilledButton(
                key: const Key('shareSend'),
                onPressed: _png == null || _working ? null : _send,
                child: Text('Send to ${_to.name}')),
        ]),
      ),
    );
  }
}

String _when(int ms) {
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Screens other grown-ups sent, screens this phone sent (with Take back), and the quiet history lines.
class ScreenShareInboxScreen extends StatefulWidget {
  const ScreenShareInboxScreen({super.key, required this.service});
  final ScreenShareService service;
  @override
  State<ScreenShareInboxScreen> createState() => _ScreenShareInboxScreenState();
}

class _ScreenShareInboxScreenState extends State<ScreenShareInboxScreen> {
  List<ReceivedShare> _in = const <ReceivedShare>[];
  List<OutgoingShare> _out = const <OutgoingShare>[];
  List<ShareLogLine> _log = const <ShareLogLine>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<ReceivedShare> i = await widget.service.inbox();
      final List<OutgoingShare> o = await widget.service.sent();
      final List<ShareLogLine> l = await widget.service.history();
      if (mounted) {
        setState(() {
          _in = i;
          _out = o;
          _log = l;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) => SensitiveScreen(
        child: Scaffold(
          appBar: AppBar(title: const Text('Screens shared between grown-ups')),
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
              const Text(
                  'A picture of a screen, sent from one grown-up to another inside Olive. It is sealed to one phone, '
                  'goes by itself when its time is up, and can be taken back. It never goes to a child.',
                  key: Key('inboxIntro')),
              const SizedBox(height: 16),
              Text('Sent to you', style: Theme.of(context).textTheme.titleMedium),
              if (_loaded && _in.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Nothing here.', key: Key('inboxEmpty'))),
              for (final ReceivedShare r in _in)
                ListTile(
                  key: Key('inboxItem_${r.idHex}'),
                  title: Text('From ${r.fromName}'),
                  subtitle: Text('${_when(r.createdAtMs)}. Goes ${_when(r.expiresAtMs)}.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(builder: (_) => ScreenShareViewer(service: widget.service, share: r)));
                    unawaited(_load());
                  },
                ),
              const SizedBox(height: 16),
              Text('Sent by this phone', style: Theme.of(context).textTheme.titleMedium),
              if (_loaded && _out.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Nothing here.', key: Key('sentEmpty'))),
              for (final OutgoingShare o in _out)
                ListTile(
                  key: Key('sentItem_${o.idHex}'),
                  title: Text('To ${o.toName}'),
                  subtitle: Text(switch (o.status) {
                    'sent' => 'Sent. Goes ${_when(o.expiresAtMs)}.',
                    'retracting' => "Taken back. ${o.toName}'s phone will be told when it is nearby.",
                    _ => "${o.toName} isn't nearby. It will go when your phones meet.",
                  }),
                  trailing: o.status == 'retracting'
                      ? null
                      : TextButton(
                          key: Key('takeBack_${o.idHex}'),
                          onPressed: () async {
                            await widget.service.takeBack(o.idHex);
                            unawaited(_load());
                          },
                          child: const Text('Take back')),
                ),
              if (_log.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text('Family history', style: Theme.of(context).textTheme.titleMedium),
                for (final ShareLogLine l in _log)
                  ListTile(dense: true, title: Text(l.text), subtitle: Text(_when(l.atMs))),
              ],
            ]),
          ),
        ),
      );
}

/// One received picture. Blocks capture, and has no send, share or save: it can only be put away.
class ScreenShareViewer extends StatefulWidget {
  const ScreenShareViewer({super.key, required this.service, required this.share});
  final ScreenShareService service;
  final ReceivedShare share;
  @override
  State<ScreenShareViewer> createState() => _ScreenShareViewerState();
}

class _ScreenShareViewerState extends State<ScreenShareViewer> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.service.markSeen(widget.share.idHex));
  }

  @override
  Widget build(BuildContext context) {
    final ReceivedShare r = widget.share;
    return SensitiveScreen(
      child: Scaffold(
        appBar: AppBar(title: Text('From ${r.fromName}')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            Text('Sent ${_when(r.createdAtMs)}. Goes ${_when(r.expiresAtMs)}.', key: const Key('viewerWhen')),
            if (r.namesHidden) const Text('Names and photos were hidden by the sender.', key: Key('viewerHidden')),
            if (r.note.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(r.note, key: const Key('viewerNote'))),
            const SizedBox(height: 8),
            InteractiveViewer(
                child: Image.memory(r.png,
                    key: const Key('viewerImage'),
                    fit: BoxFit.contain,
                    errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                        const Text('This picture could not be shown.', key: Key('viewerBroken')))),
            const SizedBox(height: 12),
            const Text(
                'This picture stays inside Olive. It can not be sent on from here. Honest limit: someone could photograph '
                'this screen with another device, and Olive cannot stop that.',
                key: Key('viewerLimit')),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('viewerPutAway'),
              onPressed: () async {
                final NavigatorState nav = Navigator.of(context);
                await widget.service.putAway(r.idHex);
                unawaited(nav.maybePop());
              },
              child: const Text('Put it away'),
            ),
          ]),
        ),
      ),
    );
  }
}
