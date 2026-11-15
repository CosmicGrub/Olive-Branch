// OLIVE BRANCH — the screens for sharing a screen between grown-ups: the action that hides itself, the capture, the
// preview with "Hide names and photos", the inbox with Take back, and the viewer that cannot send on. Verified by CI.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/app_lock.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/screen_share.dart';
import 'package:olive_client/screen_share_ui.dart';

import 'family_test_support.dart';

class _Road implements ShareTransport {
  bool open = false;
  final List<Uint8List> sent = <Uint8List>[];
  @override
  Future<bool> deliver(String recipientKeyHex, Uint8List bytes) async {
    sent.add(bytes);
    return open;
  }
}

void main() {
  late P mom, dad, kid;
  late LedgerState state;
  const int now = t0 + 3 * day;

  setUp(() async {
    mom = await P.make(1);
    dad = await P.make(2);
    kid = await P.make(3);
    final Fam fam = await Fam.found(mom);
    await fam.welcomeParent(mom, dad, others: <P>[]);
    await fam.addChild(mom, kid);
    state = await fam.state(now);
  });

  ScreenShareService svc(P who, {_Road? road, bool guardian = true}) => ScreenShareService(
        box: MemoryShareBoxRepository(),
        identity: () async => ShareIdentity(device: who.key, agreement: who.agree, state: state),
        transport: road ?? const NoShareTransport(),
        guardianDevice: guardian,
        nowMs: () => now,
      );

  Future<AppLockController> lock(WidgetTester t) async {
    final AppLockController c = AppLockController(
        pin: LocalPinService(MemoryLocalPinRepository(), iterations: 1000),
        repo: MemoryAppLockPrefsRepository(const AppLockPrefs(lockOnLeave: false, hideRecents: false)),
        secure: SecureScreen(const MethodChannel('olive/none')),
        observe: false);
    await t.runAsync(c.start);
    return c;
  }

  Widget app(AppLockController c, ScreenShareService? s, {bool marked = true}) => MaterialApp(
        builder: (BuildContext ctx, Widget? child) =>
            AppLockScope(controller: c, child: ShareCaptureScope(service: s, child: child!)),
        home: Scaffold(
          appBar: AppBar(title: const Text('Medications'), actions: const <Widget>[ShareScreenAction()]),
          body: Align(
            alignment: Alignment.topLeft,
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (marked) const ShareRedact(child: SizedBox(key: Key('name'), width: 120, height: 30, child: ColoredBox(color: Color(0xFFFFFF00)))),
              const SizedBox(key: Key('plain'), width: 120, height: 30, child: ColoredBox(color: Color(0xFFFFFF00))),
            ]),
          ),
        ),
      );

  void view(WidgetTester t) {
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await t.pumpAndSettle();
  }

  group('the action', () {
    testWidgets('is hidden when there is nobody to send to: a lone grown-up, and a child device', (t) async {
      view(t);
      final AppLockController c = await lock(t);
      await t.pumpWidget(app(c, null));
      await settle(t);
      expect(find.byKey(const Key('shareScreenAction')), findsNothing, reason: 'no service');
      await t.pumpWidget(app(c, svc(kid)));
      await settle(t);
      expect(find.byKey(const Key('shareScreenAction')), findsNothing, reason: 'a child device is not offered it');
      await t.pumpWidget(app(c, ScreenShareService.childDevice()));
      await settle(t);
      expect(find.byKey(const Key('shareScreenAction')), findsNothing);
      c.dispose();
    });

    testWidgets('shows for a grown-up with another grown-up', (t) async {
      view(t);
      final AppLockController c = await lock(t);
      await t.pumpWidget(app(c, svc(mom)));
      await settle(t);
      expect(find.byKey(const Key('shareScreenAction')), findsOneWidget);
      c.dispose();
    });

    testWidgets('is not on a sensitive screen, and a screen that turns sensitive afterwards refuses at the tap', (t) async {
      view(t);
      final AppLockController c = await lock(t);
      final VoidCallback held = c.holdSecure();
      await t.pumpWidget(app(c, svc(mom)));
      await settle(t);
      expect(find.byKey(const Key('shareScreenAction')), findsNothing, reason: 'built while a sensitive screen was showing');
      held();
      final AppLockController c2 = await lock(t);
      await t.pumpWidget(app(c2, svc(mom)));
      await settle(t);
      expect(find.byKey(const Key('shareScreenAction')), findsOneWidget);
      c2.holdSecure();
      await t.tap(find.byKey(const Key('shareScreenAction')));
      await t.pump();
      expect(find.text('This screen can not be shared.'), findsOneWidget);
      expect(find.byKey(const Key('sharePreviewImage')), findsNothing, reason: 'nothing was captured');
      c.dispose();
      c2.dispose();
    });
  });

  group('capture and hiding', () {
    testWidgets('the capture is a real PNG that fits the limit, and the marked place is a solid block when hidden', (t) async {
      view(t);
      final AppLockController c = await lock(t);
      await t.pumpWidget(app(c, svc(mom)));
      await settle(t);
      final ShareScopeData scope = ShareScope.maybeOf(t.element(find.byKey(const Key('name'))))!;
      final ShareCapture? cap = await t.runAsync<ShareCapture?>(() => captureScreen(scope));
      expect(cap, isNotNull);
      expect(cap!.hideRects, hasLength(1));
      final Rect r = t.getRect(find.byKey(const Key('name')));
      expect(cap.hideRects.single.topLeft, r.topLeft);
      expect(cap.hideRects.single.size, r.size);

      Future<List<int>> pixel(Uint8List png, int x, int y) async {
        final ui.Codec codec = await ui.instantiateImageCodec(png);
        final ui.Image img = (await codec.getNextFrame()).image;
        final ByteData d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final int o = (y * img.width + x) * 4;
        return <int>[d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2)];
      }

      final Uint8List? shown = await t.runAsync<Uint8List?>(() => renderShare(cap, hideNames: false));
      final Uint8List? hidden = await t.runAsync<Uint8List?>(() => renderShare(cap, hideNames: true));
      expect(looksLikePng(shown!), isTrue);
      expect(looksLikePng(hidden!), isTrue);
      final int x = (r.left + 60).round(), y = (r.top + 15).round();
      expect((await t.runAsync(() => pixel(shown, x, y)))!, <int>[255, 255, 0], reason: 'shown: the yellow box');
      expect((await t.runAsync(() => pixel(hidden, x, y)))!, <int>[0x45, 0x5A, 0x64], reason: 'hidden: a solid block, not a blur');
      final Rect p = t.getRect(find.byKey(const Key('plain')));
      expect((await t.runAsync(() => pixel(hidden, (p.left + 60).round(), (p.top + 15).round())))!, <int>[255, 255, 0],
          reason: 'an unmarked place is left alone');
      cap.dispose();
      c.dispose();
    });

    testWidgets('a place on a screen that is not the one showing is not hidden or counted', (t) async {
      view(t);
      final AppLockController c = await lock(t);
      await t.pumpWidget(app(c, svc(mom)));
      await settle(t);
      final BuildContext ctx = t.element(find.byKey(const Key('plain')));
      unawaited(Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('covering page')))));
      await t.pumpAndSettle();
      final ShareScopeData scope = ShareScope.maybeOf(ctx)!;
      final ShareCapture? cap = await t.runAsync<ShareCapture?>(() => captureScreen(scope));
      expect(cap!.hideRects, isEmpty);
      cap.dispose();
      c.dispose();
    });
  });

  group('the preview', () {
    // The capture and the picture are made by the engine, which needs the real event loop: let it run, then pump.
    Future<void> openPreview(WidgetTester t) async {
      await t.tap(find.byKey(const Key('shareScreenAction')));
      for (int i = 0; i < 60 && find.byKey(const Key('shareDays')).evaluate().isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 50));
      }
      for (int i = 0; i < 60 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle();
    }

    // Sending seals the picture (real async work), so let the real event loop run until the result line shows.
    Future<void> sendAndWait(WidgetTester t) async {
      await t.tap(find.byKey(const Key('shareSend')));
      for (int i = 0; i < 80 && find.byKey(const Key('shareResult')).evaluate().isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 50));
    }

    testWidgets('shows who it goes to, the honest limit, and sends it (waiting, in plain words)', (t) async {
      view(t);
      final ScreenShareService s = svc(mom);
      final AppLockController c = await lock(t);
      await t.pumpWidget(app(c, s));
      await settle(t);
      await openPreview(t);
      expect(find.byKey(const Key('sharePreviewImage')), findsOneWidget);
      expect(find.textContaining('This goes to Sam only'), findsOneWidget);
      expect(find.byKey(const Key('shareLimit')), findsOneWidget);
      expect(find.textContaining('could photograph'), findsOneWidget);
      await t.enterText(find.byKey(const Key('shareNote')), 'the new schedule');
      await sendAndWait(t);
      expect(find.text("Sam isn't nearby. It will go when your phones meet."), findsOneWidget);
      final OutgoingShare o = (await t.runAsync(s.sent))!.single;
      expect(o.toName, 'Sam');
      expect(o.status, 'waiting');
      expect((await t.runAsync(s.history))!.single.text, 'Mom shared a screen with Sam');
      c.dispose();
    });

    testWidgets('Hide names and photos is on offer where a screen marked something, and the sent picture is the hidden one', (t) async {
      view(t);
      final _Road road = _Road()..open = true;
      final ScreenShareService s = svc(mom, road: road);
      final ScreenShareService sam = svc(dad);
      final AppLockController c = await lock(t);
      await t.pumpWidget(app(c, s));
      await settle(t);
      await openPreview(t);
      final Finder hide = find.byKey(const Key('shareHideNames'));
      expect(t.widget<SwitchListTile>(hide).onChanged, isNotNull);
      await t.tap(hide);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pumpAndSettle();
      await sendAndWait(t);
      expect(find.text('Sent to Sam.'), findsOneWidget);
      final ReceivedShare? got = await t.runAsync(() async {
        await sam.receive(road.sent.single);
        return (await sam.inbox()).single;
      });
      expect(got!.namesHidden, isTrue);
      c.dispose();
    });

    testWidgets('flipping Hide names quickly never leaves the sent picture and its flag disagreeing, and Send waits', (t) async {
      for (final bool endOn in <bool>[true, false]) {
        view(t);
        final _Road road = _Road()..open = true;
        final ScreenShareService s = svc(mom, road: road);
        final ScreenShareService sam = svc(dad);
        final AppLockController c = await lock(t);
        await t.pumpWidget(app(c, s));
        await settle(t);
        final Rect r = t.getRect(find.byKey(const Key('name')));
        final int x = (r.left + 60).round(), y = (r.top + 15).round();
        await openPreview(t);
        final Finder hide = find.byKey(const Key('shareHideNames'));
        // Three quick flips with no waiting in between; the last one decides.
        final List<bool> flips = endOn ? <bool>[true, false, true] : <bool>[true, false, true, false];
        for (int i = 0; i < flips.length; i++) {
          await t.tap(hide);
          await t.pump();
        }
        expect(t.widget<FilledButton>(find.byKey(const Key('shareSend'))).onPressed, isNull,
            reason: 'no sending while a picture is still being drawn');
        for (int i = 0; i < 60 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 50));
        }
        await t.pumpAndSettle();
        expect(t.widget<FilledButton>(find.byKey(const Key('shareSend'))).onPressed, isNotNull);
        await sendAndWait(t);
        final ReceivedShare? got = await t.runAsync(() async {
          await sam.receive(road.sent.single);
          return (await sam.inbox()).single;
        });
        expect(got!.namesHidden, endOn, reason: 'flag follows the last switch position');
        // The bytes are the ones drawn for that position: the marked place is a solid block only when hidden.
        final List<int>? px = await t.runAsync<List<int>>(() async {
          final ui.Codec codec = await ui.instantiateImageCodec(got.png);
          final ui.Image img = (await codec.getNextFrame()).image;
          final ByteData d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final int o = (y * img.width + x) * 4;
          return <int>[d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2)];
        });
        expect(px![0] == 255 && px[1] == 255 && px[2] == 0, !endOn,
            reason: 'yellow shows through only when names are not hidden');
        c.dispose();
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('with nothing marked the switch is off and says so, rather than promise what it cannot do', (t) async {
      view(t);
      final AppLockController c = await lock(t);
      await t.pumpWidget(app(c, svc(mom), marked: false));
      await settle(t);
      await openPreview(t);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('shareHideNames'))).onChanged, isNull);
      expect(find.textContaining('Nothing on this screen is marked'), findsOneWidget);
      c.dispose();
    });

    testWidgets('a store that cannot be written says nothing was sent', (t) async {
      view(t);
      final ScreenShareService broken = ScreenShareService(
          box: _BrokenBox(),
          identity: () async => ShareIdentity(device: mom.key, agreement: mom.agree, state: state),
          nowMs: () => now);
      final AppLockController c = await lock(t);
      await t.pumpWidget(app(c, broken));
      await settle(t);
      await openPreview(t);
      await sendAndWait(t);
      expect(find.textContaining('Nothing was sent'), findsOneWidget);
      c.dispose();
    });
  });

  group('the inbox and the viewer', () {
    testWidgets('a sent picture can be taken back from the list', (t) async {
      view(t);
      final ScreenShareService s = svc(mom);
      final ShareRecipient to = (await t.runAsync(s.recipients))!.single;
      await t.runAsync(() => s.send(png: _png(), to: to, namesHidden: false));
      await t.pumpWidget(MaterialApp(home: ScreenShareInboxScreen(service: s)));
      await settle(t);
      expect(find.text('To Sam'), findsOneWidget);
      expect(find.textContaining("Sam isn't nearby"), findsOneWidget);
      expect(find.text('Mom shared a screen with Sam'), findsOneWidget);
      await t.tap(find.textContaining('Take back'));
      await settle(t);
      expect(find.textContaining('Taken back'), findsOneWidget);
      expect(find.text('Take back'), findsNothing);
    });

    testWidgets('a received picture opens on a screen that blocks capture and has no way to send it on', (t) async {
      view(t);
      final _Road road = _Road()..open = true;
      final ScreenShareService mine = svc(mom, road: road);
      // Built inside runAsync: its first call chains on a future made in the fake-async zone, which would never run.
      final ScreenShareService sam = (await t.runAsync(() async => svc(dad)))!;
      final AppLockController c = await lock(t);
      final ShareRecipient to = (await t.runAsync(mine.recipients))!.single;
      await t.runAsync(() async {
        await mine.send(png: _png(), to: to, namesHidden: true, note: 'look at Thursday');
        await sam.receive(road.sent.single);
      });
      await t.pumpWidget(MaterialApp(home: AppLockScope(controller: c, child: ScreenShareInboxScreen(service: sam))));
      await settle(t);
      expect(c.sensitiveNow, isTrue, reason: 'the inbox itself blocks capture');
      expect(find.textContaining('From Mom'), findsOneWidget);
      await t.tap(find.textContaining('From Mom'));
      await settle(t);
      expect(find.text('look at Thursday'), findsOneWidget);
      expect(find.byKey(const Key('viewerHidden')), findsOneWidget);
      expect(find.byKey(const Key('viewerLimit')), findsOneWidget);
      expect(c.sensitiveNow, isTrue);
      expect(find.byKey(const Key('shareScreenAction')), findsNothing);
      expect(find.byKey(const Key('shareSend')), findsNothing);
      expect(find.textContaining('Share'), findsNothing);
      expect(find.textContaining('Save'), findsNothing);
      await t.tap(find.byKey(const Key('viewerPutAway')));
      await settle(t);
      expect((await t.runAsync(sam.inbox))!, isEmpty);
      c.dispose();
    });
  });
}

Uint8List _png() {
  final List<int> b = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 8, 0, 0, 0, 8];
  b.addAll(<int>[8, 6, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]);
  return Uint8List.fromList(b);
}

class _BrokenBox implements ShareBoxRepository {
  @override
  Future<ShareBoxState> load() async => ShareBoxState();
  @override
  Future<void> save(ShareBoxState s) async => throw StateError('disk full');
}
