// OLIVE BRANCH — the calm message player: what a delivered message looks and sounds like on the child's Messages
// screen. MASTERFILE section 7.21 (the message player; the receive path it plays from is 7.19) and 8.2 (messages). Covered by flutter test only
// (client/test/message_player_test.dart); UNVERIFIED on a real device: the picture, the sound and the video are not
// yet checked on hardware, and the video_player plugin has not been built into an APK by this change.
//
// WHAT SHE SEES. One quiet screen: a soft picture of who it is from ("<her word for the grown-up> sent a video"),
// the video, the drawing or the photo when there is one, and a big round button to play, pause or watch again.
// A message that is only a nudge ("is thinking of you") is just that sentence. There is no timer, no progress bar,
// no counter, no "new", no badge and no error text of any kind. If the file cannot be had (no signal, the server
// down, a message that has expired or was never a file) the screen is exactly as calm: the sentence and the
// picture of the kind of message, and the way back. Nothing here says "no signal", offers a retry button, or spins
// for ever; the cause goes to the debug log.
//
// WHEN IT COUNTS AS OPENED. "Watched" means played through (DECISIONS.md), and the server records one thing: opened.
// This player tells the inbox the first time the message actually PLAYS or is actually SHOWN:
//   * a video or a voice message: the first moment the player reports it is playing;
//   * a drawing or a photo: the first frame on the screen;
//   * a nudge (no file at all): when its sentence is on the screen.
// Opening the tile alone records nothing, so a message she could not play (offline) stays unopened and can be tried
// again; and a message she did not fully see is never claimed as seen. The server has no separate "played through"
// state (that would need a migration); the owner decision about it is in docs/planning/OPEN-DECISIONS.md.
//
// HOW THE FILE IS FETCHED. The server's signed media URL is a short-lived capability with no session in it
// (GET .../inbox/:id/media-url, then GET /media/...). [parseMediaTicket] refuses any URL that does not point back
// at the server this client already talks to (same scheme, host and port; a relative path must be under /media/),
// so a hostile or confused answer cannot send the app to another host. The bytes are streamed through the app's
// own http client (so certificate pinning and the cleartext rules in server_transport_policy.dart still apply, which
// the platform player's own network stack would bypass) into a temporary file with a size cap, played from there,
// and the file is deleted when the screen closes.
//
// An end-to-end encrypted video ('e2e_video') is ciphertext to this client (the key exchange is not built), so it
// is shown as its sentence only and is NOT recorded as opened: nothing was shown.
//
// A LOCALLY PAIRED TABLET has no server session and is handed no messages; it never constructs any of this.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'form_factors.dart' as ff;

/// What a delivered message is, for the player.
enum PlayerKind {
  /// A sentence and nothing else (a nudge, an unknown kind, an end-to-end encrypted video this client cannot open).
  text,
  video,
  audio,
  picture,
}

/// Maps the inbox row's delivery kind to what the player does with it.
PlayerKind playerKindFor(String payloadKind) => switch (payloadKind) {
      'video_msg' || 'call_clip' => PlayerKind.video,
      'voice_note' => PlayerKind.audio,
      'drawing' || 'photo' => PlayerKind.picture,
      _ => PlayerKind.text,
    };

/// Kinds whose "opened" is recorded the moment their sentence is on the screen (there is no file to wait for).
bool recordsOnDisplay(String payloadKind) => payloadKind == 'nudge';

/// A short-lived, vetted address for one delivered file.
class MediaTicket {
  const MediaTicket(this.uri, this.kind);
  final Uri uri;

  /// The server's own word for the kind of file ('video_msg', 'voice_note', 'drawing', ...). Informational.
  final String kind;
}

/// The signed media URL answer ([OliveApi.fetchInboxMediaUrl]) as an address the app may fetch, or null when it is
/// anything else. The address must point back at [baseUrl]: the same scheme, host and port; a relative path must be
/// under /media/ with no dot segments, no authority tricks and no credentials, query pieces beyond the signature, or
/// fragment. Everything else the answer carries is ignored.
MediaTicket? parseMediaTicket(Object? body, String baseUrl) {
  if (body is! Map) return null;
  final Object? raw = body['signedUrl'];
  if (raw is! String || raw.isEmpty || raw.length > 2048) return null;
  if (raw.contains(RegExp(r'[\u0000- \u007f\\]'))) return null;
  final Uri? base = Uri.tryParse(baseUrl);
  if (base == null || !base.hasScheme || base.host.isEmpty) return null;
  // Dart folds dot segments away when it parses, so look at the text as it was sent: a dot segment, or an encoded
  // one, is refused rather than quietly rewritten.
  final String rawPath = raw.split('?').first;
  for (final String seg in rawPath.split('/')) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(seg);
    } catch (_) {
      return null;
    }
    if (decoded == '.' || decoded == '..') return null;
  }
  final Uri? parsed = Uri.tryParse(raw);
  if (parsed == null || parsed.hasFragment || parsed.userInfo.isNotEmpty) return null;
  final Uri target;
  if (parsed.hasScheme || parsed.hasAuthority) {
    // An absolute address: only ever the server this client already talks to.
    if (parsed.scheme != base.scheme || parsed.host.toLowerCase() != base.host.toLowerCase()) return null;
    if (parsed.port != base.port) return null;
    target = parsed;
  } else {
    // A path on that same server.
    if (!raw.startsWith('/') || raw.startsWith('//')) return null;
    target = base.replace(path: parsed.path, query: parsed.hasQuery ? parsed.query : null, fragment: null);
  }
  if (!target.path.startsWith('/media/')) return null;
  final List<String> segments = target.pathSegments;
  for (int i = 0; i < segments.length; i++) {
    if (segments[i] == '..' || segments[i] == '.' || (segments[i].isEmpty && i < segments.length - 1)) return null;
  }
  final Object? kind = body['kind'];
  return MediaTicket(target, kind is String && kind.length <= 32 ? kind : '');
}

/// A downloaded file kept only until [dispose].
class LocalMedia {
  LocalMedia(this.path, [this._onDispose]);
  final String path;
  final Future<void> Function()? _onDispose;
  Future<void> dispose() async {
    try {
      await _onDispose?.call();
    } catch (_) {}
  }
}

/// Fetches a vetted address into a local file. Throws on anything that is not a complete, in-size answer.
typedef MediaFetcher = Future<LocalMedia> Function(Uri uri);

/// The most one message file may be (a short video message is a few megabytes).
const int kMaxMessageMediaBytes = 80 * 1024 * 1024;

/// The real [MediaFetcher]: streams [uri] through [client] into a temporary file, refusing a non-200 answer, a
/// declared or actual size over [maxBytes], and a stalled connection ([stallTimeout] without a byte).
MediaFetcher httpMediaFetcher(
  http.Client client, {
  int maxBytes = kMaxMessageMediaBytes,
  Duration stallTimeout = const Duration(seconds: 20),
  Future<Directory> Function()? tempDir,
}) {
  return (Uri uri) async {
    final http.StreamedResponse res =
        await client.send(http.Request('GET', uri)).timeout(stallTimeout);
    if (res.statusCode != 200) {
      await res.stream.drain<void>().timeout(const Duration(seconds: 5), onTimeout: () {});
      throw HttpException('media answered ${res.statusCode}');
    }
    final int? declared = res.contentLength;
    if (declared != null && declared > maxBytes) throw const HttpException('media too large');
    final Directory dir = await (tempDir ?? getTemporaryDirectory)();
    final File file = File('${dir.path}${Platform.pathSeparator}olive_msg_${DateTime.now().microsecondsSinceEpoch}');
    final IOSink sink = file.openWrite();
    int total = 0;
    try {
      await for (final List<int> chunk in res.stream.timeout(stallTimeout)) {
        total += chunk.length;
        if (total > maxBytes) throw const HttpException('media too large');
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await file.delete();
      } catch (_) {}
      rethrow;
    }
    if (total == 0) {
      try {
        await file.delete();
      } catch (_) {}
      throw const HttpException('media was empty');
    }
    return LocalMedia(file.path, () async {
      if (await file.exists()) await file.delete();
    });
  };
}

/// What the player is doing, as the screen needs to know.
class PlaybackSnapshot {
  const PlaybackSnapshot({this.playing = false, this.completed = false, this.failed = false, this.aspectRatio = 16 / 9});
  final bool playing;
  final bool completed;
  final bool failed;
  final double aspectRatio;
}

/// The thin seam between the screen and the platform's audio/video player, so the screen is tested with a fake.
abstract class MessagePlaybackPort {
  /// Opens a local file. Throws when the platform cannot play it.
  Future<void> openFile(String path);
  Future<void> play();
  Future<void> pause();

  /// Back to the start, playing.
  Future<void> replay();
  ValueNotifier<PlaybackSnapshot> get state;

  /// The picture of a video, or null for sound only.
  Widget? view();
  Future<void> dispose();
}

/// [MessagePlaybackPort] over the video_player plugin (ExoPlayer on Android). Plays video and sound.
class VideoPlayerPlayback implements MessagePlaybackPort {
  VideoPlayerController? _c;
  @override
  final ValueNotifier<PlaybackSnapshot> state = ValueNotifier<PlaybackSnapshot>(const PlaybackSnapshot());
  bool _hasPicture = false;

  @override
  Future<void> openFile(String path) async {
    final VideoPlayerController c = VideoPlayerController.file(File(path));
    _c = c;
    await c.initialize();
    _hasPicture = c.value.size.width > 0 && c.value.size.height > 0;
    c.addListener(_sync);
    _sync();
  }

  void _sync() {
    final VideoPlayerController? c = _c;
    if (c == null) return;
    final VideoPlayerValue v = c.value;
    final bool done = v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 150) &&
        !v.isPlaying;
    state.value = PlaybackSnapshot(
        playing: v.isPlaying,
        completed: done,
        failed: v.hasError,
        aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9);
  }

  @override
  Future<void> play() async => _c?.play();
  @override
  Future<void> pause() async => _c?.pause();
  @override
  Future<void> replay() async {
    await _c?.seekTo(Duration.zero);
    await _c?.play();
  }

  @override
  Widget? view() => (_c != null && _hasPicture) ? VideoPlayer(_c!) : null;

  @override
  Future<void> dispose() async {
    final VideoPlayerController? c = _c;
    _c = null;
    c?.removeListener(_sync);
    await c?.dispose();
    state.dispose();
  }
}

/// Draws a downloaded picture. [onShown] is called when its first frame is on the screen, [onFailed] if it cannot be
/// drawn. Replaceable in tests (an image decode needs real I/O).
typedef PictureBuilder = Widget Function(BuildContext context, String path, VoidCallback onShown, VoidCallback onFailed);

Widget defaultPictureBuilder(BuildContext context, String path, VoidCallback onShown, VoidCallback onFailed) {
  return Image.file(
    File(path),
    fit: BoxFit.contain,
    gaplessPlayback: true,
    frameBuilder: (BuildContext c, Widget child, int? frame, bool sync) {
      if (frame != null || sync) WidgetsBinding.instance.addPostFrameCallback((_) => onShown());
      return child;
    },
    errorBuilder: (BuildContext c, Object e, StackTrace? s) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onFailed());
      return const SizedBox.shrink();
    },
  );
}

IconData playerIconFor(String payloadKind) => switch (payloadKind) {
      'voice_note' => Icons.graphic_eq_rounded,
      'drawing' => Icons.brush_outlined,
      'photo' => Icons.photo_outlined,
      'nudge' => Icons.favorite_border,
      _ => Icons.play_arrow_rounded,
    };

enum _Phase { loading, shown, idle }

/// The player. [loadTicket] asks the server for the vetted address (null for a message with no file, or when no
/// server is reachable); [fetchMedia] turns it into a local file; [onOpened] is called once, the first time the
/// message really plays or is really shown (see the file header).
class MessagePlayerScreen extends StatefulWidget {
  const MessagePlayerScreen({
    super.key,
    required this.line,
    required this.payloadKind,
    required this.loadTicket,
    required this.fetchMedia,
    required this.onOpened,
    this.playbackFactory,
    this.pictureBuilder = defaultPictureBuilder,
    this.resolveTimeout = const Duration(seconds: 15),
  });

  /// "Mommy sent a video", already in her words.
  final String line;

  /// The delivery kind from the inbox ('video_msg', 'voice_note', 'drawing', 'photo', 'nudge', ...).
  final String payloadKind;
  final Future<MediaTicket?> Function() loadTicket;
  final MediaFetcher fetchMedia;
  final Future<void> Function() onOpened;
  final MessagePlaybackPort Function()? playbackFactory;
  final PictureBuilder pictureBuilder;
  final Duration resolveTimeout;

  @override
  State<MessagePlayerScreen> createState() => _MessagePlayerScreenState();
}

class _MessagePlayerScreenState extends State<MessagePlayerScreen> with WidgetsBindingObserver {
  late final PlayerKind _kind = playerKindFor(widget.payloadKind);
  _Phase _phase = _Phase.loading;
  MessagePlaybackPort? _port;
  LocalMedia? _media;
  String? _picturePath;
  bool _openedTold = false;
  bool _disposed = false;
  PlaybackSnapshot _snap = const PlaybackSnapshot();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final MessagePlaybackPort? p = _port;
    _port = null;
    p?.state.removeListener(_onPlayback);
    unawaited(() async {
      try {
        await p?.dispose();
      } catch (_) {}
      await _media?.dispose();
    }());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _snap.playing) unawaited(_port?.pause());
  }

  void _tellOpened() {
    if (_openedTold || _disposed) return;
    _openedTold = true;
    unawaited(() async {
      try {
        await widget.onOpened();
      } catch (e) {
        debugPrint('[olive.player] opened not recorded (nothing is shown to her): $e');
      }
    }());
  }

  void _calm(Object why) {
    debugPrint('[olive.player] not playing, shown calmly: $why');
    if (!_disposed && mounted) setState(() => _phase = _Phase.idle);
  }

  Future<void> _start() async {
    if (_kind == PlayerKind.text) {
      // Only a nudge has nothing more to wait for. Anything else of this kind (an encrypted video, an unknown kind)
      // is a sentence we cannot back with a file, and is not claimed as seen.
      if (mounted) setState(() => _phase = _Phase.shown);
      if (recordsOnDisplay(widget.payloadKind)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tellOpened());
      }
      return;
    }
    try {
      final MediaTicket? ticket = await widget.loadTicket().timeout(widget.resolveTimeout);
      if (ticket == null) return _calm('no file for this message');
      final LocalMedia media = await widget.fetchMedia(ticket.uri).timeout(const Duration(minutes: 3));
      if (_disposed) {
        await media.dispose();
        return;
      }
      _media = media;
      if (_kind == PlayerKind.picture) {
        if (mounted) setState(() => _picturePath = media.path);
        // The first frame reports itself through the picture builder; until then she sees the calm placeholder.
        return;
      }
      final MessagePlaybackPort port = (widget.playbackFactory ?? VideoPlayerPlayback.new)();
      _port = port;
      await port.openFile(media.path);
      if (_disposed) return;
      port.state.addListener(_onPlayback);
      if (mounted) setState(() => _phase = _Phase.shown);
      await port.play();
    } catch (e) {
      _calm(e);
    }
  }

  void _onPlayback() {
    final MessagePlaybackPort? p = _port;
    if (p == null || _disposed) return;
    final PlaybackSnapshot s = p.state.value;
    if (s.failed) return _calm('the player failed');
    if (s.playing) _tellOpened();
    if (mounted) setState(() => _snap = s);
  }

  void _pictureShown() {
    if (_disposed) return;
    if (mounted && _phase != _Phase.shown) setState(() => _phase = _Phase.shown);
    _tellOpened();
  }

  void _pictureFailed() {
    if (_disposed || _picturePath == null) return;
    debugPrint('[olive.player] the picture could not be drawn, shown calmly');
    if (mounted) {
      setState(() {
        _picturePath = null;
        _phase = _Phase.idle;
      });
    }
  }

  Future<void> _toggle() async {
    final MessagePlaybackPort? p = _port;
    if (p == null) return;
    try {
      if (_snap.completed) {
        await p.replay();
      } else if (_snap.playing) {
        await p.pause();
      } else {
        await p.play();
      }
    } catch (e) {
      _calm(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasControls = _port != null && _phase == _Phase.shown;
    final Widget? view = _port?.view();
    final Widget media;
    if (_picturePath != null) {
      media = widget.pictureBuilder(context, _picturePath!, _pictureShown, _pictureFailed);
    } else if (view != null && _phase == _Phase.shown) {
      media = AspectRatio(aspectRatio: _snap.aspectRatio, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: view));
    } else {
      media = CircleAvatar(
          key: const Key('playerPicture'),
          radius: 56,
          backgroundColor: scheme.primaryContainer,
          child: Icon(playerIconFor(widget.payloadKind), size: 56, color: scheme.onPrimaryContainer));
    }
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('Messages')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Flexible(child: Center(child: media)),
                  const SizedBox(height: 16),
                  Text(widget.line, key: const Key('playerLine'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                  if (hasControls) ...<Widget>[
                    const SizedBox(height: 16),
                    Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      IconButton.filled(
                        key: const Key('playerToggle'),
                        iconSize: 40,
                        tooltip: _snap.completed ? 'Again' : (_snap.playing ? 'Pause' : 'Play'),
                        onPressed: _toggle,
                        icon: Icon(_snap.completed ? Icons.replay_rounded : (_snap.playing ? Icons.pause_rounded : Icons.play_arrow_rounded)),
                      ),
                      if (_snap.completed) ...<Widget>[
                        const SizedBox(width: 16),
                        IconButton.filledTonal(
                          key: const Key('playerDone'),
                          iconSize: 40,
                          tooltip: 'Done',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.check_rounded),
                        ),
                      ],
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
