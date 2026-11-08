// OLIVE BRANCH — Parent Learn storage seam.
// No longer UNVERIFIED — verified by CI (client/test/parent_learn_screens_test.dart).
//
// The screens depend on this interface, never on a socket. [MemoryLearnStore]
// is the real in-process implementation (used by tests, the demo and the app
// before a session exists). A server-backed implementation talks to the
// /v1/learn/... routes (db/migrations/0035_parent_learn.sql) and enforces the
// same rules a second time, in the database, with RLS.
//
// The privacy rules live HERE as well as in the UI, so a screen that forgot to
// check cannot write a reflection the guardian did not opt in to:
//  - saveReflection throws unless settings.reflection == 'saved'
//  - setMyRules keeps only what shareableRules allows, and nothing at all
//    unless settings.rulesList is on
//  - there is no export or share method for reflections, by design (L2).
import 'parent_learn_logic.dart';

class Reflection {
  const Reflection({required this.day, required this.warmth, required this.expectations});
  final String day; // yyyy-mm-dd
  final int warmth;
  final int expectations;
}

class OtherGuardianRules {
  const OtherGuardianRules({required this.guardianName, required this.rules});
  final String guardianName;
  final List<RuleItem> rules;
}

class LearnStoreRefused implements Exception {
  const LearnStoreRefused(this.reason);
  final String reason;
  @override
  String toString() => 'LearnStoreRefused($reason)';
}

abstract class LearnStore {
  Future<LearnSettings> loadSettings();
  Future<void> saveSettings(LearnSettings s);
  Future<void> saveReflection(Reflection r);
  Future<List<Reflection>> reflections();
  Future<void> deleteReflection(String day);
  Future<List<RuleItem>> myRules();
  Future<void> setMyRules(List<RuleItem> rules);
  Future<List<OtherGuardianRules>> othersRules();
}

class MemoryLearnStore implements LearnStore {
  MemoryLearnStore({this.principal = const LearnPrincipal('guardian', 'g1'), List<OtherGuardianRules>? others})
      : _others = others ?? <OtherGuardianRules>[];

  final LearnPrincipal principal;
  final List<OtherGuardianRules> _others;
  LearnSettings _settings = defaultLearnSettings;
  final Map<String, Reflection> _reflections = <String, Reflection>{};
  List<RuleItem> _rules = <RuleItem>[];

  void _guard() {
    if (!canReadLearn(principal)) throw const LearnStoreRefused('not_a_guardian');
  }

  @override
  Future<LearnSettings> loadSettings() async {
    _guard();
    return _settings;
  }

  @override
  Future<void> saveSettings(LearnSettings s) async {
    _guard();
    _settings = parseLearnSettings(s.toJson());
    // Turning the features off also forgets what they stored.
    if (!mayStoreReflection(_settings)) _reflections.clear();
    if (!_settings.rulesList) _rules = <RuleItem>[];
  }

  @override
  Future<void> saveReflection(Reflection r) async {
    _guard();
    if (!mayStoreReflection(_settings)) throw const LearnStoreRefused('reflection_not_saved_mode');
    final RegExp day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!day.hasMatch(r.day)) throw const LearnStoreRefused('bad_day');
    _reflections[r.day] = Reflection(
        day: r.day, warmth: r.warmth.clamp(0, 100), expectations: r.expectations.clamp(0, 100));
  }

  @override
  Future<List<Reflection>> reflections() async {
    _guard();
    final List<String> days = _reflections.keys.toList()..sort((String a, String b) => b.compareTo(a));
    return <Reflection>[for (final String d in days) _reflections[d]!];
  }

  @override
  Future<void> deleteReflection(String day) async {
    _guard();
    _reflections.remove(day);
  }

  @override
  Future<List<RuleItem>> myRules() async {
    _guard();
    return List<RuleItem>.of(_rules);
  }

  @override
  Future<void> setMyRules(List<RuleItem> rules) async {
    _guard();
    if (!_settings.rulesList) throw const LearnStoreRefused('rules_list_off');
    _rules = shareableRules(principal, _settings, <Object?>[
      for (final RuleItem r in rules) <String, Object?>{'category': r.category, 'text': r.text}
    ]);
  }

  @override
  Future<List<OtherGuardianRules>> othersRules() async {
    _guard();
    return _settings.rulesList ? List<OtherGuardianRules>.of(_others) : <OtherGuardianRules>[];
  }
}
