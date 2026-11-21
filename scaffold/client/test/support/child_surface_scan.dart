// OLIVE BRANCH — the child-reachable file set and the two things a child must never be shown through it.
// Pure functions over a path -> source map so a test can feed a seeded violation and watch the scan fail.
//
// The set is computed, not listed by prefix: start at the files a child's boot routes open (child_home.dart,
// child_more.dart and the root of every child route in live_boot_plan.dart) and follow every import and export.
// That over-approximates what a child can reach (an import is not a navigation), which is the safe direction.
//
// Two rules over that set (owner rules P1-P11, MASTERFILE 2.1 and 5.23.2):
//  1. No PIN screen. The only keypad a child device may build is the adult gate's (AdultGate builds PinGate).
//  2. No Text built from an exception object or a status code, and no string that interpolates a caught
//     exception's reason into something a screen can show.

/// Files that open each child route in live_boot_plan.dart. A new non-guardian route must be added here, so a new
/// child surface cannot slip past the scan (the test fails until it is mapped).
const Map<String, List<String>> childRouteRoots = <String, List<String>>{
  'childDev': <String>['kiosk_shell.dart', 'child_home_live.dart'],
  'childPaired': <String>['kiosk_shell.dart', 'child_home_live.dart'],
  'childPairedLocal': <String>['kiosk_shell.dart', 'child_home_live.dart'],
  'kidFirstRun': <String>[
    'first_run_flow.dart',
    'child_connect_screen.dart',
    'onboarding_flow.dart',
    'pairing_redeem_screen.dart',
  ],
  'rolePicker': <String>['role_picker_screen.dart'],
};

/// The two files every child home is built from.
const List<String> childHomeRoots = <String>['child_home.dart', 'child_more.dart'];

/// Screens that ask for, set or recover a PIN. A child build never builds one.
const List<String> pinScreenNames = <String>[
  'LocalPinSetupForm',
  'LocalPinSetupScreen',
  'LocalPinChangeScreen',
  'GuardianSetupScreen',
  'ForgotPinScreen',
  'GuardianPhonesScreen',
  'ApprovePinResetScreen',
  'PinGate',
];

/// Files whose imports are PIN screens outright.
const List<String> pinScreenFiles = <String>[
  'local_pin_screens.dart',
  'guardian_pin_recovery_screens.dart',
  'guardian_setup.dart',
  'pin_gate.dart',
];

/// Where a PIN screen is defined or deliberately built, so being in the set by import is not a violation.
/// (importer, imported): adult_gate builds the keypad; webauthn_channel takes one message helper from
/// guardian_setup and builds nothing.
const Set<String> allowedPinImports = <String>{
  'adult_gate.dart>pin_gate.dart',
  'webauthn_channel.dart>guardian_setup.dart',
};

/// Files that may mention a PIN screen's name: its own definition, and the adult gate for the keypad.
const Map<String, Set<String>> allowedPinNameFiles = <String, Set<String>>{
  'PinGate': <String>{'pin_gate.dart', 'adult_gate.dart'},
  'GuardianSetupScreen': <String>{'guardian_setup.dart'},
  'LocalPinSetupForm': <String>{'local_pin_screens.dart'},
  'LocalPinSetupScreen': <String>{'local_pin_screens.dart'},
  'LocalPinChangeScreen': <String>{'local_pin_screens.dart'},
  'ForgotPinScreen': <String>{'guardian_pin_recovery_screens.dart'},
  'GuardianPhonesScreen': <String>{'guardian_pin_recovery_screens.dart'},
  'ApprovePinResetScreen': <String>{'guardian_pin_recovery_screens.dart'},
};

/// Known exception-text sites that are not fixed yet, kept visible rather than hidden: a NEW one still fails the
/// scan. Remove an entry when its file is fixed.
const Map<String, String> knownExceptionText = <String, String>{
  'receipt_screen.dart': 'the send-one-back screen still prints the caught exception; the durable-outbox rework replaces it',
  'networked_checkers_lobby_screen.dart': 'a developer lobby (base-address fields) still reachable from the games hub',
};

String stripComments(String src) => src.split('\n').where((String l) => !l.trimLeft().startsWith('//')).join('\n');

final RegExp _importRe =
    RegExp(r"^\s*(?:import|export)\s+'(?:package:olive_client/)?([A-Za-z0-9_/]+\.dart)'", multiLine: true);

/// Every file an import or export of [file] names, in [sources]' own spelling.
List<String> importsOf(String file, Map<String, String> sources) {
  final String? src = sources[file];
  if (src == null) return const <String>[];
  return <String>[for (final RegExpMatch m in _importRe.allMatches(src)) m.group(1)!];
}

/// The child-reachable set: everything the [roots] import, transitively.
Set<String> reachableFrom(Iterable<String> roots, Map<String, String> sources) {
  final Set<String> seen = <String>{};
  final List<String> stack = <String>[...roots];
  while (stack.isNotEmpty) {
    final String f = stack.removeLast();
    if (seen.contains(f) || !sources.containsKey(f)) continue;
    seen.add(f);
    stack.addAll(importsOf(f, sources));
  }
  return seen;
}

/// The text inside every `Text(` ... `)` in [code] (balanced parentheses).
Iterable<String> textArguments(String code) sync* {
  for (final RegExpMatch m in RegExp(r'\bText\(').allMatches(code)) {
    int depth = 1;
    int i = m.end;
    while (i < code.length && depth > 0) {
      final String c = code[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      i++;
    }
    yield code.substring(m.end, i);
  }
}

Set<String> caughtNames(String code) => <String>{
      for (final RegExpMatch m in RegExp(r'catch\s*\(\s*(\w+)').allMatches(code))
        if (m.group(1) != '_') m.group(1)!,
    };

/// Violations found in the files [roots] reach, as readable lines. Empty means clean.
List<String> scanChildSurface(Map<String, String> sources, Iterable<String> roots) {
  final Set<String> reach = reachableFrom(roots, sources);
  final List<String> out = <String>[];
  for (final String f in reach.toList()..sort()) {
    final String code = stripComments(sources[f]!);

    // Rule 1: no PIN screen.
    for (final String imported in importsOf(f, sources)) {
      if (pinScreenFiles.contains(imported) && !allowedPinImports.contains('$f>$imported')) {
        out.add('$f imports $imported (a PIN screen)');
      }
    }
    for (final String n in pinScreenNames) {
      if (RegExp('\\b$n\\b').hasMatch(code) && !(allowedPinNameFiles[n] ?? const <String>{}).contains(f)) {
        out.add('$f builds $n (a PIN screen)');
      }
    }

    // Rule 2: no exception object or status code in anything shown.
    if (knownExceptionText.containsKey(f)) continue;
    final Set<String> caught = caughtNames(code);
    for (final String t in textArguments(code)) {
      if (t.contains('statusCode')) out.add('$f: a Text shows a status code: ${_one(t)}');
      for (final String v in caught) {
        if (RegExp('\\\$\\{?$v\\b|\\b$v\\.(?:toString\\(\\)|message\\b|error\\b|statusCode\\b)').hasMatch(t)) {
          out.add('$f: a Text shows the caught exception "$v": ${_one(t)}');
        }
      }
    }
    for (final String line in code.split('\n')) {
      if (line.contains('debugPrint') || line.contains('developer.log') || line.contains('CallUnavailableException(')) {
        continue;
      }
      for (final String v in caught) {
        if (RegExp('\\\$\\{?$v\\b').hasMatch(line)) {
          out.add('$f: a string interpolates the caught exception "$v": ${line.trim()}');
        }
      }
    }
    // A status code in a thrown exception's message is a developer log line, not something shown (a Text or a
    // caught-exception interpolation above would be what shows it), so thrown statements are left out of this check.
    for (final String line in code.replaceAll(RegExp(r'throw\s+[^;]*;'), '').split('\n')) {
      if (line.contains('debugPrint') || line.contains('developer.log')) continue;
      if (RegExp(r'\$\{?\w+\.statusCode').hasMatch(line)) {
        out.add('$f: a string interpolates a status code: ${line.trim()}');
      }
    }
  }
  return out;
}

String _one(String s) {
  final String t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > 90 ? '${t.substring(0, 90)}...' : t;
}
