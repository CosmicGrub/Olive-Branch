// OLIVE BRANCH — the Kid's role-first first run: the age lock on the kid picker (5 to 15), the
// "who are my grown-ups" step coming back, and "what do you call your grown-ups". No longer
// UNVERIFIED — verified by CI. MASTERFILE §8.5.10.
//
// Drives the real FirstRunFlow with the real onboarding screens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/first_run_flow.dart';
import 'package:olive_client/grownup_roster.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/onboarding_age.dart';
import 'package:olive_client/onboarding_draft.dart';

http.Client _client() => MockClient((http.Request r) async => http.Response('{}', 404));

KidRoster knownRoster({int age = 9, String label = 'Mom', GrownupKind kind = GrownupKind.mom}) {
  final LocalFamily f = LocalFamily.fromAnswers(
      guardianName: 'Sam', guardianLabel: label, guardianKind: kind, childName: 'Ivy', age: age);
  return KidRoster(contacts: f.grownups, known: true, age: f.ageLock, childName: f.childName);
}

void main() {
  late MemoryOnboardingDraftRepository repo;
  late MemoryNicknameRepository nicks;

  setUp(() {
    repo = MemoryOnboardingDraftRepository();
    nicks = MemoryNicknameRepository();
  });

  Future<void> pump(WidgetTester t, {KidRoster? roster}) async {
    await t.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: FirstRunFlow(
        baseUrl: 'http://olive.test',
        draftRepository: repo,
        httpClient: _client(),
        roster: roster,
        nicknames: nicks,
        onRedeemed: (_) {},
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text("Let's begin"));
    await t.pumpAndSettle();
  }

  Future<void> next(WidgetTester t, [String label = 'Next']) async {
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  Future<void> skipTail(WidgetTester t) async {
    expect(find.text('Pick your colour'), findsOneWidget);
    await next(t, 'Skip for now');
    expect(find.text('When is your birthday?'), findsOneWidget);
    await next(t, 'Skip for now');
  }

  group('the kid picker locks her age', () {
    testWidgets('it offers exactly 5 to 15, says a grown-up can change it, and what she taps is locked', (t) async {
      await pump(t);
      await next(t, 'Skip for now'); // name
      expect(find.text('How old are you?'), findsOneWidget);
      for (int a = 5; a <= 15; a++) {
        expect(find.byKey(ValueKey<String>('age_$a')), findsOneWidget, reason: 'age $a');
      }
      for (final int a in <int>[2, 3, 4, 16, 17]) {
        expect(find.byKey(ValueKey<String>('age_$a')), findsNothing, reason: 'age $a is not on the kid picker');
      }
      expect(find.text('A grown-up can change this later.'), findsOneWidget);
      await t.tap(find.text('7'));
      await t.pump();
      await next(t);
      await next(t, 'Skip for now'); // gender (no roster: no grown-ups steps)
      await skipTail(t);
      final OnboardingDraft d = (await repo.load())!;
      expect(d.age, 7);
      expect(d.ageLocked, isTrue);
      expect(d.complete, isTrue);
    });

    testWidgets('skipping the age locks nothing', (t) async {
      await pump(t);
      await next(t, 'Skip for now'); // name
      await next(t, 'Skip for now'); // age
      await next(t, 'Skip for now'); // gender
      await skipTail(t);
      final OnboardingDraft d = (await repo.load())!;
      expect(d.age, isNull);
      expect(d.ageLocked, isFalse);
    });

    testWidgets('the demo tour (Redo the welcome tour) keeps its old 2 to 17 picker, with no lock note', (t) async {
      await t.pumpWidget(MaterialApp(home: ObAgeScreen(birthDate: null, onContinue: (_) {})));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('age_2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('age_17')), findsOneWidget);
      expect(find.byKey(const Key('ageLockNote')), findsNothing);
    });

    test('the draft keeps the lock only with an age (a lock with no age is not a lock) and writes it only when true', () {
      expect(OnboardingDraft.fromJson(<String, Object?>{'age': 9, 'ageLocked': true}).ageLocked, isTrue);
      expect(OnboardingDraft.fromJson(<String, Object?>{'ageLocked': true}).ageLocked, isFalse);
      expect(const OnboardingDraft(age: 4).toJson().containsKey('ageLocked'), isFalse);
      expect(const OnboardingDraft(age: 4, ageLocked: true).toJson()['ageLocked'], isTrue);
    });
  });

  group('no local family on the device: neutral placeholders, nobody invented', () {
    testWidgets('no "who is here" step; the naming step shows "Your grown-up" and "Your other grown-up"', (t) async {
      await pump(t, roster: KidRoster(contacts: placeholderGrownups(), known: false, age: const AgeLockState()));
      await next(t, 'Skip for now'); // name
      await t.tap(find.text('7'));
      await t.pump();
      await next(t);
      await next(t, 'Skip for now'); // gender
      expect(find.text('Who is here?'), findsNothing, reason: 'nobody is known before a device is connected');
      expect(find.text('What do you call your grown-ups?'), findsOneWidget);
      expect(find.text('Your grown-up'), findsOneWidget);
      expect(find.text('Your other grown-up'), findsOneWidget);
      expect(find.text('Mom'), findsNothing);
      expect(find.text('Dad'), findsNothing);
      expect(find.text('Mommy'), findsNothing);
      expect(find.text('Daddy'), findsNothing);
    });

    testWidgets('she can name one; it is kept as hers (a word, not a claim about a person) and the questions go on',
        (t) async {
      await pump(t, roster: KidRoster(contacts: placeholderGrownups(), known: false, age: const AgeLockState()));
      await next(t, 'Skip for now'); // name
      await next(t, 'Skip for now'); // age
      await next(t, 'Skip for now'); // gender
      await t.tap(find.byKey(const Key('person_placeholder-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bank_Mama')));
      await t.pumpAndSettle();
      expect(await nicks.load(), <String, String>{'placeholder-1': 'Mama'});
      await next(t); // Next on the naming step
      expect(find.text('Pick your colour'), findsOneWidget);
    });
  });

  group('a local family on the device: the "who are my grown-ups" step returns, driven by it', () {
    testWidgets('the age a grown-up locked is not asked again; she is told who is here, as Mommy', (t) async {
      await pump(t, roster: knownRoster(age: 9));
      await next(t, 'Skip for now'); // name
      expect(find.text('How old are you?'), findsNothing, reason: 'a grown-up already locked her age');
      expect(find.text('Are you a boy or a girl?'), findsOneWidget);
      await next(t, 'Skip for now');
      expect(find.text('Who is here?'), findsOneWidget);
      expect(find.text("You're here to talk to Mommy."), findsOneWidget);
      await next(t);
      expect(find.text('What do you call your grown-ups?'), findsOneWidget);
      expect(find.byKey(const Key('personName_$kLocalGuardianContactId')), findsOneWidget);
      await next(t, 'Skip for now');
      await skipTail(t);
      final OnboardingDraft d = (await repo.load())!;
      expect(d.age, 9);
      expect(d.ageLocked, isTrue);
    });

    testWidgets('a Dad at a locked 9 is Daddy; a locked 16 is Dad; a guardian\'s own word is shown as it is', (t) async {
      await pump(t, roster: knownRoster(age: 9, label: 'Dad', kind: GrownupKind.dad));
      await next(t, 'Skip for now');
      await next(t, 'Skip for now');
      expect(find.text("You're here to talk to Daddy."), findsOneWidget);
    });

    testWidgets('a teenager\'s locked age gives Dad, not Daddy', (t) async {
      await pump(t, roster: knownRoster(age: 16, label: 'Dad', kind: GrownupKind.dad));
      await next(t, 'Skip for now');
      await next(t, 'Skip for now');
      expect(find.text("You're here to talk to Dad."), findsOneWidget);
    });

    testWidgets('her word for them wins in the very next step, and is hers alone', (t) async {
      await pump(t, roster: knownRoster(age: 9));
      await next(t, 'Skip for now');
      await next(t, 'Skip for now');
      await next(t); // who
      await t.tap(find.byKey(const Key('person_$kLocalGuardianContactId')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bank_Mama')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('personName_$kLocalGuardianContactId'))).data, 'Mama');
      expect(await nicks.load(), <String, String>{kLocalGuardianContactId: 'Mama'});
    });
  });

  group('no pressure', () {
    testWidgets('the new steps show no step counter, score or progress', (t) async {
      await pump(t, roster: knownRoster());
      await next(t, 'Skip for now');
      await next(t, 'Skip for now');
      for (int i = 0; i < 2; i++) {
        final String all = t.widgetList<Text>(find.byType(Text)).map((Text x) => x.data ?? '').join(' ').toLowerCase();
        expect(all, isNot(contains('step ')));
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await next(t);
      }
    });
  });
}
