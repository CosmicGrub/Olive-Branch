// A reader for the REAL server route table, for contract tests. It parses server/routes.mjs and
// packages/db/src/pool.ts as text (the test runs in the client directory; the server is a sibling), so a client
// test can hold the app to what the server actually registers and answers, not to a copy of it that can drift.
//
// What it extracts for every top-level `api.register({ ... })` block: the method, the path, whether it needs no
// session (`noSessionRequired`), the body keys the handler reads, and every error reason the block (and the db
// function it calls) can return.
import 'dart:io';

class RealRoute {
  RealRoute({
    required this.method,
    required this.path,
    required this.noSession,
    required this.bodyKeys,
    required this.reasons,
    required this.source,
  });

  final String method;
  final String path;

  /// `noSessionRequired: true` on the registration: the route is open to a caller with no session.
  final bool noSession;

  /// Body fields the handler reads.
  final Set<String> bodyKeys;

  /// Every error reason the route can answer with.
  final Set<String> reasons;
  final String source;
}

/// The error unions in pool.ts, by the db function that returns them.
const Map<String, String> _functionToErrorType = <String, String>{
  'acceptGuardianInvite': 'AcceptInviteError',
  'revokeGuardianInvite': 'RevokeInviteError',
  'bootstrapGuardianInvite': 'BootstrapInviteError',
  'signUpWithAllowance': 'SignupError',
  'precheckSignup': 'SignupError',
  'createChildForGuardian': 'CreateChildError',
  'claimGuardianInvite': 'ClaimInviteError',
  'confirmGuardianInvite': 'ConfirmInviteError',
  'declineGuardianInvite': 'DeclineInviteError',
};

/// The reasons `requireOwnPin` can answer with (server/routes.mjs).
const Set<String> _ownPinReasons = <String>{'pin_required', 'pin_locked', 'pin_not_set', 'pin_incorrect'};

String _read(String relative) => File(relative).readAsStringSync().replaceAll('\r\n', '\n');

Set<String> _union(String poolSource, String typeName) {
  final RegExpMatch? m = RegExp('export type $typeName\\s*=([^;]+);').firstMatch(poolSource);
  if (m == null) throw StateError('pool.ts has no type $typeName');
  return <String>{for (final RegExpMatch q in RegExp(r"'([a-z_]+)'").allMatches(m.group(1)!)) q.group(1)!};
}

/// The fields of an exported TS interface in pool.ts (names only).
Set<String> poolInterfaceFields(String name) {
  final RegExpMatch? m = RegExp('export interface $name\\s*\\{([^}]*)\\}').firstMatch(_read('../packages/db/src/pool.ts'));
  if (m == null) throw StateError('pool.ts has no interface $name');
  return <String>{
    for (final RegExpMatch f in RegExp(r'([A-Za-z_]\w*)\??\s*:').allMatches(m.group(1)!)) f.group(1)!,
  };
}

/// The values of `export const NAME = [ 'a', 'b' ] as const;` in pool.ts.
List<String> poolConstList(String name) {
  final RegExpMatch? m = RegExp('export const $name = \\[([^\\]]*)\\]').firstMatch(_read('../packages/db/src/pool.ts'));
  if (m == null) throw StateError('pool.ts has no const $name');
  return <String>[for (final RegExpMatch q in RegExp(r"'([a-z_]+)'").allMatches(m.group(1)!)) q.group(1)!];
}

List<RealRoute> loadRealRoutes() {
  final String routes = _read('../server/routes.mjs');
  final String pool = _read('../packages/db/src/pool.ts');
  final List<RealRoute> out = <RealRoute>[];
  // A top-level registration runs from `\n  api.register({` to the first `\n  });` (nested closers are indented deeper).
  for (final RegExpMatch m in RegExp(r'\n  api\.register\(\{([\s\S]*?)\n  \}\);').allMatches(routes)) {
    final String block = m.group(1)!;
    final RegExpMatch? head = RegExp(r"method:\s*'([A-Z]+)',\s*path:\s*'([^']+)'").firstMatch(block);
    if (head == null) continue;
    final Set<String> keys = <String>{};
    for (final RegExpMatch k in RegExp(r'\bb\.(\w+)').allMatches(block)) {
      if (block.contains('const b = c.body')) keys.add(k.group(1)!);
    }
    for (final RegExpMatch k in RegExp(r'c\.body\?\.(\w+)').allMatches(block)) {
      keys.add(k.group(1)!);
    }
    for (final RegExpMatch k in RegExp(r'const \{([^}]+)\} = c\.body \?\? \{\}').allMatches(block)) {
      keys.addAll(k.group(1)!.split(',').map((String s) => s.trim()).where((String s) => s.isNotEmpty));
    }
    final Set<String> reasons = <String>{
      for (final RegExpMatch e in RegExp(r"error: '([a-z_]+)'").allMatches(block)) e.group(1)!,
    };
    if (block.contains('requireOwnPin(')) reasons.addAll(_ownPinReasons);
    for (final MapEntry<String, String> f in _functionToErrorType.entries) {
      if (block.contains('${f.key}(')) reasons.addAll(_union(pool, f.value));
    }
    if (block.contains('createGuardianInvite(')) reasons.add('invalid_role');
    out.add(RealRoute(
      method: head.group(1)!,
      path: head.group(2)!,
      noSession: block.contains('noSessionRequired: true'),
      bodyKeys: keys,
      reasons: reasons,
      source: block,
    ));
  }
  if (out.length < 40) throw StateError('parsed only ${out.length} routes; the parser no longer matches routes.mjs');
  return out;
}

RealRoute? findRoute(List<RealRoute> all, String method, String path) {
  for (final RealRoute r in all) {
    if (r.method == method && r.path == path) return r;
  }
  return null;
}
