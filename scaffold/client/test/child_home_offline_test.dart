// OLIVE BRANCH — the child home with NO SIGNAL (offline-first, audit C-06's
// companion): pictures only, never an error screen with raw text; her own home
// from what the device remembers; and a guardian's hidden tile stays hidden.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/child_home_live.dart';
import 'package:olive_client/local_repositories.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/push_channel.dart';
import 'package:olive_client/wear_sync_channel.dart';
import 'package:olive_client/api_client.dart';

class _NoPush extends PushChannel {
  _NoPush() : super(OliveApi('http://unused', 'unused'));
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}
}

class _NoWear extends WearSyncChannel {
  @override
  Future<void> syncSleepsUntilHandover(int sleepsUntilHandover) async {}
  @override
  void listenForCallDad(void Function() onCallDadRequested) {}
}

MockClient _server({required bool up}) => _switchable(() => up);

/// A server whose reachability can change between requests.
MockClient _switchable(bool Function() isUp) => MockClient((http.Request req) async {
      if (!isUp()) throw http.ClientException('no route to host');
      final String p = req.url.path;
      if (p == '/v1/auth/dev-login') return http.Response(jsonEncode(<String, Object?>{'token': 'tok'}), 200);
      if (p == '/v1/me') {
        return http.Response(jsonEncode(<String, Object?>{'displayName': 'Ivy', 'yearsOld': 8}), 200);
      }
      if (p.endsWith('/inbox')) return http.Response(jsonEncode(<String, Object?>{'entries': <Object?>[]}), 200);
      if (p.endsWith('/now')) {
        return http.Response(jsonEncode(<String, Object?>{
          'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York', 'sleepsUntilHandover': 3,
        }), 200);
      }
      if (p.endsWith('/activity-overrides')) {
        return http.Response(jsonEncode(<String, Object?>{
          'overrides': <Object?>[<String, Object?>{'activityKey': 'tile:homework', 'visible': false}],
        }), 200);
      }
      if (p.endsWith('/presence')) return http.Response(jsonEncode(<String, Object?>{'free': null}), 200);
      return http.Response('not found', 404);
    });

Widget _home(MockClient c, {String id = 'child-a'}) => MaterialApp(
    home: LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: id, httpClient: c, wearSync: _NoWear(), pushChannel: _NoPush()));

void main() {
  setUp(() {
    LocalServices.install(LocalServices.memory(childId: 'child-a', isLive: true, demoSeeds: false));
  });

  testWidgets('a good load remembers her name, age and the grown-up\'s hide choices on this device', (t) async {
    await t.pumpWidget(_home(_server(up: true)));
    await t.pumpAndSettle();
    expect(find.text('Hi Ivy'), findsOneWidget);
    expect(find.text('Homework'), findsNothing, reason: 'hidden by the grown-up');

    final ProfileCache c = (await ProfileCacheRepository(LocalServices.current.area('profile', ownerId: 'child-a')).load())!;
    expect(c.displayName, 'Ivy');
    expect(c.yearsOld, 8);
    expect(c.overrides, isNotNull);
  });

  testWidgets('no signal after a good visit: her own home opens from the cache, offline cues are pictures only', (t) async {
    await t.pumpWidget(_home(_server(up: true)));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());

    await t.pumpWidget(_home(_server(up: false))); // same phone, no signal
    await t.pumpAndSettle();

    expect(find.text('Hi Ivy'), findsOneWidget, reason: 'her name, from the cache');
    expect(find.byKey(const Key('childOfflineIcon')), findsOneWidget);
    expect(find.byKey(const Key('childOfflineRetry')), findsOneWidget);
    expect(find.text('Homework'), findsNothing, reason: 'going offline must never unhide what a guardian hid');
    expect(find.textContaining("Couldn't reach"), findsNothing);
    expect(find.textContaining('Something went wrong'), findsNothing);
    expect(find.textContaining('sleeps until'), findsNothing, reason: 'no live handover figure is invented offline');
    expect(find.text('Messages'), findsOneWidget);
  });

  testWidgets('no signal, never seen before: a cloud-off picture and one big refresh button, no text at all', (t) async {
    await t.pumpWidget(_home(_server(up: false)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('childOfflineIcon')), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    final Size retry = t.getSize(find.byKey(const Key('childOfflineRetry')));
    expect(retry.shortestSide, greaterThanOrEqualTo(48));
  });

  testWidgets('refresh recovers into the real live home once the signal is back', (t) async {
    bool up = false;
    final MockClient flaky = _switchable(() => up);
    await t.pumpWidget(_home(flaky));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('childOfflineIcon')), findsOneWidget);
    up = true;
    await t.tap(find.byKey(const Key('childOfflineRetry')));
    await t.pumpAndSettle();
    expect(find.text('Hi Ivy'), findsOneWidget);
    expect(find.byKey(const Key('childOfflineIcon')), findsNothing);
  });

  testWidgets('another child profile on the same phone does not get this child\'s cached home', (t) async {
    await t.pumpWidget(_home(_server(up: true)));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_home(_server(up: false), id: 'child-b'));
    await t.pumpAndSettle();
    expect(find.text('Hi Ivy'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a disk that refuses every write never breaks a good online load', (t) async {
    LocalServices.install(LocalServices(
        store: LocalStore(backend: _BrokenDisk()), childId: 'child-a', isLive: true, demoSeeds: false));
    await t.pumpWidget(_home(_server(up: true)));
    await t.pumpAndSettle();
    expect(find.text('Hi Ivy'), findsOneWidget);
    expect(find.byKey(const Key('childOfflineIcon')), findsNothing);
  });
}

class _BrokenDisk extends MemoryStoreBackend {
  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async => throw const FileSystemException('disk full');
}
