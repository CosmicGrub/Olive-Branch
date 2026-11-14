// The guardian-only "Server address" screen: PIN-gated and fail closed, https
// only, with a reset to the built-in address; and it is reachable from the
// guardian's More hub and nowhere on the child side.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/server_address.dart';
import 'package:olive_client/server_address_screen.dart';

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(500, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

Future<void> _fill(WidgetTester t, {String address = '', String pin = ''}) async {
  if (address.isNotEmpty) await t.enterText(find.byKey(const Key('serverAddressField')), address);
  if (pin.isNotEmpty) await t.enterText(find.byKey(const Key('serverAddressPin')), pin);
  await t.pump();
}

void main() {
  late LocalServices services;

  setUp(() {
    ServerAddress.resetInMemory();
    services = LocalServices.memory(childId: 'ivy');
    LocalServices.install(services);
  });
  tearDown(ServerAddress.resetInMemory);

  Future<bool> goodPin(String p) async => p == '1234';

  testWidgets('shows the built-in address and, plainly, that it is not pinned', (t) async {
    await _pump(t, ServerAddressScreen(verifyPin: goodPin));
    expect(find.byKey(const Key('serverAddressCurrent')), findsOneWidget);
    expect(find.text(kBuiltInBaseUrl), findsOneWidget);
    expect(find.text('The address this copy of Olive was built with.'), findsOneWidget);
    expect(find.textContaining('not pinned'), findsOneWidget);
    // Nothing to reset while the built-in one is in use.
    expect(t.widget<OutlinedButton>(find.byKey(const Key('serverAddressReset'))).onPressed, isNull);
  });

  testWidgets('a correct PIN and an https address saves it', (t) async {
    await _pump(t, ServerAddressScreen(verifyPin: goodPin));
    await _fill(t, address: 'https://new.example.com/', pin: '1234');
    await t.tap(find.byKey(const Key('serverAddressSave')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('serverAddressSaved')), findsOneWidget);
    expect(ServerAddress.current, 'https://new.example.com');
    expect(await services.area(kServerAddressArea).get('url'), 'https://new.example.com');
  });

  testWidgets('a wrong PIN saves nothing', (t) async {
    await _pump(t, ServerAddressScreen(verifyPin: goodPin));
    await _fill(t, address: 'https://new.example.com', pin: '0000');
    await t.tap(find.byKey(const Key('serverAddressSave')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('serverAddressWrongPin')), findsOneWidget);
    expect(ServerAddress.override, isNull);
    expect(await services.area(kServerAddressArea).get('url'), isNull);
  });

  testWidgets('a PIN check that throws counts as wrong (fail closed)', (t) async {
    await _pump(t, ServerAddressScreen(verifyPin: (_) async => throw StateError('offline')));
    await _fill(t, address: 'https://new.example.com', pin: '1234');
    await t.tap(find.byKey(const Key('serverAddressSave')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('serverAddressWrongPin')), findsOneWidget);
    expect(ServerAddress.override, isNull);
  });

  testWidgets('with no way to check a PIN, the screen offers no change at all', (t) async {
    await _pump(t, ServerAddressScreen(verifyPin: null));
    expect(find.byKey(const Key('serverAddressUnavailable')), findsOneWidget);
    expect(find.byKey(const Key('serverAddressField')), findsNothing);
    expect(find.byKey(const Key('serverAddressSave')), findsNothing);
  });

  testWidgets('http and other bad addresses are refused with a reason, before the PIN is used',
      (t) async {
    var pinChecks = 0;
    await _pump(t, ServerAddressScreen(verifyPin: (p) async {
      pinChecks++;
      return true;
    }));
    for (final bad in <String>['http://192.168.1.5:8123', 'example.com', 'https://a.com/x']) {
      await _fill(t, address: bad, pin: '1234');
      await t.tap(find.byKey(const Key('serverAddressSave')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('serverAddressBad')), findsOneWidget, reason: bad);
    }
    expect(pinChecks, 0);
    expect(ServerAddress.override, isNull);
  });

  testWidgets('"Use the built-in address" needs the PIN and then removes the saved one', (t) async {
    await ServerAddress.save(services.area(kServerAddressArea), 'https://old.example.com');
    await _pump(t, ServerAddressScreen(verifyPin: goodPin));
    expect(find.text('An address you typed here.'), findsOneWidget);
    expect(find.textContaining('Built-in: '), findsOneWidget);

    await _fill(t, pin: '9999');
    await t.tap(find.byKey(const Key('serverAddressReset')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('serverAddressWrongPin')), findsOneWidget);
    expect(ServerAddress.current, 'https://old.example.com');

    await _fill(t, pin: '1234');
    await t.tap(find.byKey(const Key('serverAddressReset')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('serverAddressWasReset')), findsOneWidget);
    expect(ServerAddress.current, kBuiltInBaseUrl);
    expect(await services.area(kServerAddressArea).get('url'), isNull);
  });
}
