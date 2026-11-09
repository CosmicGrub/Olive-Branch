// OLIVE BRANCH — LocalDiscovery releases its event subscription (on-device
// performance pass).
//
// bonsoir's discovery stream is a platform-channel broadcast. start() used to
// call .listen() and throw the subscription away, so stop() could never cancel
// it: every pairing session left a live listener behind (holding the object),
// and an event arriving after stop() closed the controllers would throw.
import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_discovery.dart';

BonsoirDiscoveryEvent lostEvent(String name) => BonsoirDiscoveryEvent(
      type: BonsoirDiscoveryEventType.discoveryServiceLost,
      service: BonsoirService(
          name: '$name-guardian', type: '_olive._tcp', port: 1, attributes: <String, String>{'name': name}),
    );

void main() {
  test('events reach the lost stream while listening', () async {
    final LocalDiscovery d = LocalDiscovery(role: 'child', displayName: 'Maya', servePort: 1);
    final StreamController<BonsoirDiscoveryEvent> events = StreamController<BonsoirDiscoveryEvent>.broadcast();
    addTearDown(events.close);
    d.listenToEvents(events.stream);
    final Future<String> lost = d.lost.first;
    // A peer must be seen (resolved) before its disappearance means anything; it is only ever called by its seat.
    events.add(BonsoirDiscoveryEvent(
        type: BonsoirDiscoveryEventType.discoveryServiceResolved,
        service: ResolvedBonsoirService(
            name: 'Dad-guardian', type: '_gp._tcp', port: 1, host: '10.0.0.2',
            attributes: <String, String>{'s': '2', 'k': 'peer-token'})));
    await Future<void>.delayed(Duration.zero);
    events.add(lostEvent('Dad'));
    expect(await lost, 'Player two');
    await d.stop();
  });

  test('stop() cancels the subscription: the source has no listener afterwards', () async {
    final LocalDiscovery d = LocalDiscovery(role: 'child', displayName: 'Maya', servePort: 1);
    final StreamController<BonsoirDiscoveryEvent> events = StreamController<BonsoirDiscoveryEvent>.broadcast();
    addTearDown(events.close);
    d.listenToEvents(events.stream);
    expect(events.hasListener, isTrue);
    await d.stop();
    expect(events.hasListener, isFalse, reason: 'the subscription was cancelled, not leaked');
  });

  test('an event that arrives after stop() is ignored, not thrown', () async {
    final LocalDiscovery d = LocalDiscovery(role: 'child', displayName: 'Maya', servePort: 1);
    final StreamController<BonsoirDiscoveryEvent> events = StreamController<BonsoirDiscoveryEvent>.broadcast();
    addTearDown(events.close);
    d.listenToEvents(events.stream);
    await d.stop();
    final List<Object> uncaught = <Object>[];
    await runZonedGuarded(() async {
      events.add(lostEvent('Dad'));
      await Future<void>.delayed(Duration.zero);
    }, (Object e, StackTrace s) => uncaught.add(e));
    expect(uncaught, isEmpty);
  });

  test('listening again replaces (cancels) the previous subscription', () async {
    final LocalDiscovery d = LocalDiscovery(role: 'child', displayName: 'Maya', servePort: 1);
    final StreamController<BonsoirDiscoveryEvent> a = StreamController<BonsoirDiscoveryEvent>.broadcast();
    final StreamController<BonsoirDiscoveryEvent> b = StreamController<BonsoirDiscoveryEvent>.broadcast();
    addTearDown(a.close);
    addTearDown(b.close);
    d.listenToEvents(a.stream);
    d.listenToEvents(b.stream);
    await Future<void>.delayed(Duration.zero);
    expect(a.hasListener, isFalse);
    expect(b.hasListener, isTrue);
    await d.stop();
  });
}
