// OLIVE BRANCH — the adult's connected-devices list with keeping watch: New badge, paused, "still yours?", stop behind
// the PIN, plain-language history and its tamper warning. UNVERIFIED on a device; headless, real hashing, no sockets.
// Design: docs/planning/PERSISTENT-QR-PAIRING.md layer 5.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connected_devices_screen.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/pairing_trust.dart';

Uint8List _k(int f) => Uint8List.fromList(List<int>.filled(32, f));

Future<void> _act(WidgetTester t, Future<void> Function() gesture) async {
  await t.runAsync(() async {
    await gesture();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await t.pump();
  await _pump(t);
}

Future<void> _pump(WidgetTester t) async {
  for (int i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

class _Rig {
  _Rig(this.kids, this.trust, this.pin);
  final MemoryPairedKidsRepository kids;
  final TrustBook trust;
  final LocalPinService pin;
}

Future<_Rig> _rig(WidgetTester t, {DateTime? addedAt}) async {
  final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
  // The clock reads [addedAt] while the device is added, then real time (so later actions are "now").
  DateTime? clock = addedAt;
  final TrustBook book = TrustBook(MemoryTrustRepository(), now: () => clock ?? DateTime.now());
  final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
  await t.runAsync(() async {
    await pin.setPin('4829');
    await kids.add(PairedKid(certId: 'c1', childDeviceKey: _k(1), childId: 'k', deviceName: 'Ivy tablet', issuedAtMs: 1));
    await book.add(certId: 'c1', deviceKey: _k(1), deviceName: 'Ivy tablet', role: PairedRole.child, addedBy: 'Sam');
    clock = null;
  });
  return _Rig(kids, book, pin);
}

Future<void> _show(WidgetTester t, _Rig r) async {
  await t.pumpWidget(MaterialApp(home: ConnectedDevicesScreen(kids: r.kids, childName: 'Ivy', trust: r.trust, pin: r.pin)));
  await _pump(t);
}

void main() {
  testWidgets('a newly added device shows who added it and a New badge with the time left', (t) async {
    final _Rig r = await _rig(t, addedAt: DateTime.now().subtract(const Duration(hours: 1)));
    await _show(t, r);
    expect(find.byKey(const Key('connectedNew_c1')), findsOneWidget);
    expect(find.textContaining('23 hours left'), findsOneWidget);
    expect(find.textContaining('by Sam'), findsOneWidget);
    expect(find.byKey(const Key('connectedHistory')), findsOneWidget);
  });

  testWidgets('a device whose key changed shows as paused, in plain words', (t) async {
    final _Rig r = await _rig(t);
    await t.runAsync(() => r.trust.observe('c1', _k(9)));
    await _show(t, r);
    expect(find.byKey(const Key('connectedPaused_c1')), findsOneWidget);
    expect(find.text('Paused: this device changed. Is this still Ivy tablet?'), findsOneWidget);
  });

  testWidgets('after 60 days without contact: "Is this device still yours?"; Keep clears it', (t) async {
    final _Rig r = await _rig(t, addedAt: DateTime.now().subtract(const Duration(days: 61)));
    await _show(t, r);
    expect(find.text('Is this device still yours?'), findsOneWidget);
    await _act(t, () => t.tap(find.byKey(const Key('connectedKeep_c1'))));
    expect(find.text('Is this device still yours?'), findsNothing);
  });

  testWidgets('stop needs the PIN: a wrong PIN changes nothing, the right one stops it, says what it does not do, and is in the history', (t) async {
    final _Rig r = await _rig(t);
    await _show(t, r);
    await t.tap(find.byKey(const Key('connectedStop_c1')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('keeps what is on it until it is reset'), findsOneWidget);
    await t.enterText(find.byKey(const Key('stopPinField')), '1111');
    await _act(t, () => t.tap(find.byKey(const Key('stopConfirm'))));
    expect(find.text('That is not your PIN.'), findsOneWidget);
    expect(await r.kids.load(), hasLength(1));
    await t.enterText(find.byKey(const Key('stopPinField')), '4829');
    await _act(t, () => t.tap(find.byKey(const Key('stopConfirm'))));
    await t.pump(const Duration(milliseconds: 400));
    await _pump(t);
    expect(await r.kids.load(), isEmpty);
    expect(await t.runAsync(() => r.trust.isRefused(_k(1))), isTrue);
    expect(find.byKey(const Key('connectedEmpty')), findsOneWidget);
  });

  testWidgets('the history reads in plain words and warns when the chain is broken', (t) async {
    final _Rig r = await _rig(t);
    await t.runAsync(() => r.trust.note(HistoryKind.newCode));
    await _show(t, r);
    await t.tap(find.byKey(const Key('connectedHistory')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Ivy tablet was added.'), findsOneWidget);
    expect(find.text('You made a new code. Old copies stopped working.'), findsOneWidget);
    expect(find.byKey(const Key('connectedHistoryBroken')), findsNothing);

    // Remove the first line behind the app's back: the list is now flagged.
    final TrustState s = (await t.runAsync(() => r.trust.repo.load()))!;
    await t.runAsync(() => r.trust.repo.save(TrustState(s.devices, s.history.sublist(1), s.refusedKeys, s.settle)));
    await t.pumpWidget(const SizedBox());
    await _show(t, r);
    expect(find.byKey(const Key('connectedHistoryBroken')), findsOneWidget);
  });

  testWidgets('without a trust book the older screen is unchanged: no badge, no stop button', (t) async {
    final _Rig r = await _rig(t);
    await t.pumpWidget(MaterialApp(home: ConnectedDevicesScreen(kids: r.kids, childName: 'Ivy')));
    await _pump(t);
    expect(find.byKey(const Key('connectedNew_c1')), findsNothing);
    expect(find.byKey(const Key('connectedStop_c1')), findsNothing);
    expect(find.byKey(const Key('connectedForget_c1')), findsOneWidget);
  });
}
