// OLIVE BRANCH — Flutter client, API surface. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §20.2, §7.
//
// Real HTTP client as of this pass — previously endpoint-string constants
// only, with no code anywhere that actually made a request (there was no
// server for it to call, either — see server/index.mjs, the first thing in
// this repository that listens on a port). Endpoint strings below are
// contract-checked against the registered API routes by
// packages/api/test/contract.test.mjs so the two cannot drift silently. The
// server currently implements a real, narrow slice of these — /v1/me, /now,
// /inbox, and (as of this pass) GET .../availability + PUT /v1/me/availability
// — not the full list; calling an unimplemented one gets a real 404 from the
// real router, not a fake one.
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.error, {this.message, this.faults});
  final int statusCode;
  final String error;
  /// Plain-language explanation, when the server sent one (e.g. a certified
  /// export denial reason — see server/routes.mjs's EXPORT_DENIAL_MESSAGES).
  /// Null for endpoints that don't send one.
  final String? message;
  /// The real, per-entry chain-verification diagnostics (kind + seq) a
  /// `chain_broken` certified-export denial carries — server/routes.mjs's
  /// `GET .../export` spreads `result.faults` onto the 403 body whenever
  /// `certifiedExportBundleFor()` returns one (packages/db/src/pool.ts).
  /// Null for every other denial/error, which never sends this key.
  final List<dynamic>? faults;
  @override
  String toString() => 'ApiException($statusCode, $error)';
}

/// One recognized homework problem, as returned by POST
/// [OliveApi.homeworkCapture] on success. `hint` has already been through
/// the server's real guardHint() (packages/homework/src/capture.ts) — it is
/// always safe to show a parent verbatim, never a raw model/generator
/// output. §9.1's "hint, don't solve" is the SAME server-side guard on
/// every path (real capture and homework_screen.dart's demo fallback both
/// end up calling guardHint before anything reaches the screen), just
/// applied server-side here instead of client-side.
class HomeworkProblemResult {
  const HomeworkProblemResult({required this.text, required this.hint, required this.hintRefused});

  /// OCR'd text of this one problem (see packages/homework/src/split.ts's
  /// numbered-list heuristic for how the server broke the page up).
  final String text;

  /// Already guarded — safe to render as-is.
  final String hint;

  /// True when the rule-based generator's own hint (packages/homework/src/
  /// hints.ts — NOT an AI model, see that file's header) was refused by the
  /// guard and [hint] is the guard's safe fallback instead. Kept for tests/
  /// analytics; never itself rendered as a "this was refused" message to
  /// her (§9.1 — she only ever sees a hint, not a refusal notice).
  final bool hintRefused;

  factory HomeworkProblemResult.fromJson(Map<String, dynamic> j) => HomeworkProblemResult(
    text: j['text'] as String? ?? '',
    hint: j['hint'] as String? ?? '',
    hintRefused: j['hintRefused'] as bool? ?? false,
  );
}

class OliveApi {
  OliveApi(this.baseUrl, this.sessionToken, {http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String sessionToken;
  final http.Client _client;

  // --- identity -----------------------------------------------------------
  static const mePath = '/v1/me';

  // --- time engine (§7.2) -------------------------------------------------
  static const childNow    = '/v1/children/:childId/now';
  static const childRibbon = '/v1/children/:childId/ribbon';
  static const childOverlap = '/v1/children/:childId/overlap';

  // --- live parent presence (ChildHome's own `ParentPresence`) -----------
  // GET .../presence — server/routes.mjs's real handler: which (at most
  // one) parent guardian is currently free, per the design spec's §3
  // tie-break algorithm (custody-duty exclusion, then earliest available-
  // window start). `action: 'calendar.view'`, the same reused action /now
  // and /custody-order already authorize a child session through.
  static const childPresence = '/v1/children/:childId/presence';

  // --- custody schedule (§5.4, §9.4) --------------------------------------
  // Read-only view of the real custody_order row -- see
  // family_agreement_screen.dart's own header for why this is deliberately
  // NOT a bespoke "agreement" document endpoint.
  static const custodyOrder = '/v1/children/:childId/custody-order';

  // --- async delivery (§7.3) ---------------------------------------------
  static const inbox    = '/v1/children/:childId/inbox';
  static const messages = '/v1/children/:childId/messages';
  static const batches  = '/v1/children/:childId/batches';
  // Two path params, not one — same reasoning [callEnd]'s own doc comment
  // gives for why this is pre-substituted rather than going through
  // [_post]'s single-`:childId` substitution the way [inbox] above does.
  // Real bug this closes, found by this project's own post-tier audit:
  // MASTERFILE §7.3 declared this route for as long as this document has
  // had an API reference section, but nothing anywhere ever called it —
  // inbox_screen.dart's own _open() only flipped `watched` in LOCAL widget
  // state, invisible to the server the moment she left the screen.
  static const inboxOpened = '/v1/children/:childId/inbox/:messageId/opened';
  // --- real object storage (§20.2b) ---------------------------------------
  // server/routes.mjs's real upload/download pair for the bytes [messages]
  // above only ever carried a `storageKey` REFERENCE to — see [uploadMedia]
  // and [fetchMessageMedia] below, and receipt_screen.dart's own header for
  // the gap this closes.
  static const media = '/v1/children/:childId/media';
  // Two path params, not one — same reasoning [callEnd]'s own doc comment
  // gives for why this is pre-substituted rather than going through
  // [_get]'s single-`:childId` substitution the way [fetchInbox] above does.
  static const messageMedia = '/v1/children/:childId/messages/:artifactId/media';

  // --- child agency (§7.10) ----------------------------------------------
  static const ping    = '/v1/children/:childId/ping';
  static const journal = '/v1/children/:childId/journal';

  // --- archive (§7.9) ------------------------------------------------------
  /// §16.1 #3, §2.11 — free, unlimited, every tier. Backs deletion_screen
  /// .dart's "Download raw export" button. GET, matching MASTERFILE §7.9's
  /// own documented shape (`GET .../export  full portable bundle`) and
  /// server/routes.mjs's real registration.
  static const export_ = '/v1/children/:childId/export';

  // --- coordination (§7.7) -----------------------------------------------
  // Real for the first time as of this pass, same audit/pass that closed
  // [handoverNotes]/[expenses] above -- server/routes.mjs's own
  // route-registration comment has the full account. `medication.view`/
  // `medication.log`/`emergency_card.view` already existed in family-graph/
  // src/authorize.ts's Action union with real ROLE_CAPS before this pass;
  // only the table, routes, and this client wiring were missing.
  static const medications   = '/v1/children/:childId/medications';
  // Two path params, not one -- same reasoning [callEnd]'s own doc comment
  // gives for why this is pre-substituted rather than going through
  // [_post]'s single-`:childId` substitution the way [medications] above does.
  static const medicationDoses = '/v1/children/:childId/medications/:medicationId/doses';
  static const emergencyCard = '/v1/children/:childId/emergency-card';
  // --- parent-to-parent handover log (message_log, real for the first time
  // as of this pass -- see server/routes.mjs's own route-registration
  // comment for the full account, and handover_notes.dart's file header for
  // the P8 append-only invariant this backs). No MASTERFILE §7 row declares
  // this route yet -- that section's own new scoping note already discloses
  // this as a real, honest gap, same as [childPresence] above; not
  // retrofitted to a stale declaration.
  static const handoverNotes = '/v1/children/:childId/handover-notes';
  // --- expenses (§9.6.5, P6) -- real for the first time as of this pass,
  // same audit/pass that closed [handoverNotes] above. `expense`
  // (db/migrations/0006_court_tier.sql) has had real FORCE RLS since it was
  // first migrated; server/routes.mjs's own route-registration comment has
  // the full account. Path shape deliberately child-scoped throughout
  // (`.../expenses/:expenseId/accept`), NOT MASTERFILE §7.7's own bare
  // `/v1/expenses/:id/accept` sketch -- see that comment for why.
  static const expenses = '/v1/children/:childId/expenses';
  // Three literal constants, not one shared `:action` template -- server/
  // routes.mjs registers three distinct concrete routes (a loop over the
  // three verbs, not a single `:action` path param), and packages/api/test/
  // contract.test.mjs's own real client/server drift check does an exact,
  // literal string match against every server-registered path, which a
  // `:action` placeholder would never satisfy. [resolveExpense] below picks
  // the right one by `action`.
  static const expenseAccept = '/v1/children/:childId/expenses/:expenseId/accept';
  static const expenseDispute = '/v1/children/:childId/expenses/:expenseId/dispute';
  static const expenseReimburse = '/v1/children/:childId/expenses/:expenseId/reimburse';
  // --- the exchange (§9.7, P3) -- real for the first time as of this pass,
  // same audit/pass that closed [handoverNotes]/[expenses]/[medications]
  // above. Backs exchange_screen.dart's bag manifest/running-late log/
  // arrival sections ONLY -- that screen's Handoff/Coming-up sections stay
  // on demo data (see its own file header, and server/routes.mjs's
  // route-registration comment, for the disclosed scope reasoning).
  static const exchangeBagItems = '/v1/children/:childId/exchange/bag-items';
  // Two path params, not one -- same reasoning [messageMedia]'s own doc
  // comment gives for why this is pre-substituted rather than going through
  // [_post]'s single-`:childId` substitution the way [exchangeBagItems]
  // above does. Genuinely one server route with a real `:itemId` path
  // param (like [inboxOpened]'s `:messageId`), NOT an enum of fixed verbs
  // like [expenseAccept]/[expenseDispute]/[expenseReimburse] -- so this
  // stays a single constant.
  static const exchangeBagItemStatus = '/v1/children/:childId/exchange/bag-items/:itemId';
  static const exchangeRunningLate = '/v1/children/:childId/exchange/running-late';
  static const exchangeArrival = '/v1/children/:childId/exchange/arrival';

  // --- guarded by escalation (§8.3) --------------------------------------
  static const settings = '/v1/children/:childId/settings';

  // --- real authentication (§7.1, §8.1, §8.3) -----------------------------
  // Path constants, contract-checked against the registered server routes by
  // packages/api/test/contract.test.mjs (and by transport.test.mjs's own
  // "I · CLIENT CONTRACT" section, which scans every .dart file's string
  // literals) -- see server/routes.mjs and server/index.mjs for the real,
  // already-implemented, already-tested server side of every one of these.
  // kioskPinVerify and guardianPinPath now have real Dart CALLING code below
  // (verifyKioskPin / setGuardianPin); the WebAuthn paths are still
  // path-constants-only, wired in a later phase.
  static const kioskPinVerify = '/v1/children/:childId/kiosk-pin/verify';
  // Named guardianPinPath, not setGuardianPin, so it doesn't collide with the
  // instance method of that name below -- same string value either way, and
  // contract.test.mjs/transport.test.mjs only regex-scan for the literal
  // '/v1/me/pin', never the Dart identifier.
  static const guardianPinPath = '/v1/me/pin';
  static const webauthnRegisterChallenge = '/v1/auth/webauthn/register/challenge';
  static const webauthnRegisterVerify = '/v1/auth/webauthn/register/verify';
  static const webauthnLoginChallenge = '/v1/auth/webauthn/login/challenge';
  static const webauthnLoginVerify = '/v1/auth/webauthn/login/verify';

  // --- guardian availability (§9, MARKUP screen 'availability') ----------
  // Real as of this pass — server/routes.mjs, packages/db/src/pool.mjs's
  // setAvailabilityWindows()/availabilityFor(), db/migrations/0010_availability.sql.
  static const childAvailability = '/v1/children/:childId/availability';
  static const meAvailability    = '/v1/me/availability';
  // --- theme customization (§8.1, MARKUP screen 'themePicker') -----------
  // Real as of this pass — server/routes.mjs, packages/db/src/pool.mjs's
  // themeFor()/setChildTheme(), db/migrations/0017_child_theme_preference.sql.
  // A DIFFERENT, dedicated path from the `settings` constant already declared
  // above under "guarded by escalation" -- that one is reserved for a future
  // real settings surface reached via §8.3 PIN+biometric escalation on the
  // child's own device; this one is guardian-side navigation (guardian_more
  // .dart), a normal authenticated guardian session, no escalation required.
  static const childTheme = '/v1/children/:childId/theme';
  // --- homework OCR capture (§9.1, §20.2b) --------------------------------
  static const homeworkCapture = '/v1/children/:childId/homework/capture';
  // --- account lifecycle (§2.10, §2.11, §9.8, P8) -------------------------
  static const deleteAccountPath = '/v1/me/delete';
  // --- child-initiated take-and-go (§9.8.4, §7.9, §21.2 rung 17, §21.6/
  // §21.7) -----------------------------------------------------------------
  // The child's OWN export + majority guardianship closure -- server/
  // routes.mjs's real handler, packages/db/src/pool.mjs's takeAndGo(). A
  // genuine mirror of deleteAccountPath above, for the child side. The path
  // itself is §7.9's own long-specified-but-unbuilt `.../handover` route
  // ("majority transfer. Irreversible. §9.8.4") -- "take and go" (§21.6's
  // own row title) is this feature's PRODUCT name, kept for the Dart
  // constant/screen/pool-function names; the wire path matches the spec.
  static const takeAndGoPath = '/v1/children/:childId/handover';
  // --- court export (§2.11, §16.1 #3) -------------------------------------
  // Certified export reuses `export_` above (same route, `?kind=certified`)
  // rather than a second path constant for the identical URL — server/
  // routes.mjs's single GET .../export handler dispatches on that query
  // param, not on a second registration (api.ts's register() has no
  // duplicate-route guard; a second registration for the same method+path
  // would just be silently unreachable dead code behind the first).

  // --- login (dev-only — see server/index.mjs's own header comment) ------
  static const devLoginPath = '/v1/auth/dev-login';

  // --- push notifications (MASTERFILE §11) --------------------------------
  // Real routes as of this pass — scaffold/server/routes.mjs, backed by
  // packages/db/src/pool.ts's registerDeviceToken/unregisterDeviceToken.
  // Never carries content: just {platform, token}. See push_channel.dart for
  // the real caller (permission request, token fetch, refresh listener).
  static const deviceTokens = '/v1/me/device-tokens';

  // --- guardian invitation (§11, §8.5) -------------------------------------
  // Create requires a real guardian session (this class's own [_post]);
  // the invited party has none yet, so read/accept below are free functions
  // matching webauthnLoginChallenge/Verify's own shape, not instance methods.
  static const guardianships = '/v1/children/:childId/guardianships';
  static const guardianInvite = '/v1/guardian-invites/:inviteId';
  static const guardianInviteAccept = '/v1/guardian-invites/:inviteId/accept';
  static const guardianInviteRevoke = '/v1/guardian-invites/:inviteId/revoke';
  // The account-creation gap CHANGELOG v0.49.9 named and left open -- see
  // [bootstrapGuardianInvite] below, the real free function this constant
  // backs.
  static const guardianInviteBootstrap = '/v1/guardian-invites/:inviteId/bootstrap';

  // --- call — real room-coordination + ringing (§5.19, §5.21, §5.25.2) ----
  // server/routes.mjs's own real replacement for local-call-room-server.mjs's
  // dev-only /room endpoint — see that route's own header comment for the
  // fuller account. [startCall] below is the real caller this constant's
  // own comment used to say didn't exist yet — guardian_more.dart's "Call
  // $childName" tile is the one real call site; call_screen.dart's own
  // room-fetch still falls back to the dev room server when a caller (like
  // main_live_child_call_test.dart's "Call Dad (test)" FAB) never supplies
  // a [CallScreen.knownRoom] to begin with.
  static const calls = '/v1/children/:childId/calls';

  // POST .../calls/:sessionId/end — real call-end record-keeping, added
  // alongside [recordCallStart]'s own real per-edge-ladderStep fix
  // (2026-08-23 audit). Two params, not one — see [endCall]'s own doc
  // comment for why this is pre-substituted rather than going through
  // [_post]'s single-`:childId` substitution the way [calls] above does.
  static const callEnd = '/v1/children/:childId/calls/:sessionId/end';

  Uri _uri(String path, [String? childId, Map<String, String>? query]) => Uri.parse(
      '$baseUrl${childId != null ? path.replaceFirst(':childId', childId) : path}')
          .replace(queryParameters: query);

  Future<Map<String, dynamic>> _get(
    String path, {
    String? childId,
    Map<String, String>? query,
  }) async {
    final res = await _client.get(_uri(path, childId, query),
        headers: {'authorization': 'Bearer $sessionToken'});
    return _decode(res);
  }

  /// Mirrors [_get]'s header/decode conventions for a JSON-body POST.
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {String? childId}) async {
    final res = await _client.post(
      _uri(path, childId),
      headers: {
        'authorization': 'Bearer $sessionToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  /// Mirrors [_post]'s header/decode conventions for a JSON-body PUT
  /// (replace-all semantics — see [setAvailability]).
  Future<Map<String, dynamic>> _put(String path, {String? childId, required Object body}) async {
    final res = await _client.put(_uri(path, childId),
        headers: {
          'authorization': 'Bearer $sessionToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body));
    return _decode(res);
  }

  /// Mirrors [_post]'s header/decode conventions for a JSON-body DELETE —
  /// MASTERFILE §11's `DELETE /v1/me/device-tokens` (unregistering a device
  /// on sign-out/uninstall), the one caller that needs it.
  Future<Map<String, dynamic>> _delete(String path, Map<String, dynamic> body) async {
    final res = await _client.delete(_uri(path),
        headers: {
          'authorization': 'Bearer $sessionToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body =
        res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body['error'] as String? ?? 'error',
          message: body['message'] as String?, faults: body['faults'] as List<dynamic>?);
    }
    return body;
  }

  Future<Map<String, dynamic>> fetchMe() => _get(mePath);
  Future<Map<String, dynamic>> fetchNow(String childId) => _get(childNow, childId: childId);
  Future<Map<String, dynamic>> fetchInbox(String childId) => _get(inbox, childId: childId);

  /// Marks delivery_intent's own row for [messageId] `opened` — POST
  /// [inboxOpened], server/routes.mjs's real handler. Idempotent: an
  /// already-opened message (a real re-open, or an offline-queued duplicate
  /// call) is a safe 200, never an error. Mirrors [endCall]'s own posture
  /// exactly: this is record-keeping only — nothing about actually SHOWING
  /// the receipt depends on it succeeding, so a real call site (inbox_
  /// screen.dart's own `_open()`) should fire this best-effort and never let
  /// its failure block or delay the real screen transition the child is
  /// already mid-tap on.
  Future<Map<String, dynamic>> markInboxOpened(String childId, String messageId) => _post(
      inboxOpened.replaceFirst(':childId', childId).replaceFirst(':messageId', messageId),
      const {});

  /// `{free: null}` or `{free: {guardianId, name, theirLocalTime,
  /// freeUntilHerTime}}` — GET [childPresence], server/routes.mjs's real
  /// handler. `free` is honestly `null` whenever nobody currently qualifies
  /// (no second live parent guardian, the on-duty guardian excluded, or no
  /// guardian has an active availability window right now) — the same
  /// "honest absence, not a guess" posture [fetchNow]'s own
  /// `sleepsUntilHandover` already has. Decoding `free` into a
  /// [ParentPresence]-shaped value is left to the caller, matching
  /// [fetchNow]/[fetchInbox] above. Throws [ApiException] on any non-2xx
  /// response, same posture as every other read in this class.
  Future<Map<String, dynamic>> fetchPresence(String childId) =>
      _get(childPresence, childId: childId);

  /// `{entries: [{seq, authorId, authorName, at, body, whenLabel}, ...]}` --
  /// GET [handoverNotes], server/routes.mjs's real handler. `whenLabel` is
  /// already formatted in the CHILD's own resolved zone, server-side --
  /// this class never does its own timezone math, same discipline
  /// [fetchInbox]'s own `deliveredAtLabel` already follows (no timezone
  /// package exists in client/pubspec.yaml). Throws [ApiException] on any
  /// non-2xx response -- notably 403 `not_the_childs_channel` for a child
  /// session, the real guard handover_notes.dart's own file header
  /// explains ("Not the child's... it's the parents'").
  Future<Map<String, dynamic>> fetchHandoverNotes(String childId) =>
      _get(handoverNotes, childId: childId);

  /// Appends ONE new entry to [childId]'s real parent-to-parent handover
  /// log -- POST [handoverNotes], server/routes.mjs's real handler
  /// (appendHandoverNote(), packages/db/src/pool.ts): a real hash-chain
  /// append (message_log's own append-only + chain-linkage triggers,
  /// db/migrations/0006_court_tier.sql), never an edit or delete -- see
  /// handover_notes.dart's own file header for why this class exposes no
  /// corresponding update/delete method at all, not even one that always
  /// fails. Returns `{ok, seq, authorId, at, body, whenLabel}` -- NOT
  /// `authorName` (unlike [fetchHandoverNotes]'s per-entry shape): the
  /// caller of this method is, by construction, the entry's own author, so
  /// a real display label never needs one -- `authorId == ` the caller's
  /// own known guardian id is enough to render "You" without a second
  /// round trip. `whenLabel` IS included, same reasoning -- see that
  /// route's own comment for why. Throws [ApiException] on any
  /// non-2xx response (e.g. 400 `empty_body` for a whitespace-only note,
  /// 403 `not_the_childs_channel` for a child session), exactly like
  /// [sendMessage]'s own posture on a real rejection.
  Future<Map<String, dynamic>> postHandoverNote(String childId, String body) =>
      _post(handoverNotes, {'body': body}, childId: childId);

  /// `{entries: [{id, paidById, paidByName, description, amountCents,
  /// category, incurredOn, receiptKey, payerSharePercent, status,
  /// createdAt}, ...]}` -- GET [expenses], server/routes.mjs's real
  /// handler. Every real expense for [childId], newest first -- decoding
  /// into pending-approval vs. ledger views is left to the caller, matching
  /// [fetchHandoverNotes]'s own posture. Throws [ApiException] on any
  /// non-2xx response -- notably 403 `P6_child_financial` for a child
  /// session (expenses_screen.dart's own file header: P6, "no financial or
  /// expense surface visible to a child role").
  Future<Map<String, dynamic>> fetchExpenses(String childId) =>
      _get(expenses, childId: childId);

  /// Proposes ONE new expense for [childId] -- POST [expenses],
  /// server/routes.mjs's real handler (proposeExpense(), packages/db/src/
  /// pool.ts). Returns the created row verbatim (`id, paidById, description,
  /// amountCents, category, incurredOn, receiptKey, payerSharePercent,
  /// status, createdAt` -- NOT `paidByName`, same "the caller IS the payer,
  /// by construction" reasoning [postHandoverNote] gives for its own
  /// missing `authorName`), so a caller can render the just-proposed
  /// expense immediately without a second round trip. `status` always comes
  /// back `'proposed'`. Throws [ApiException] on any non-2xx response (e.g.
  /// 400 `bad_amountCents`/`bad_category`/`bad_description` for an invalid
  /// body, 403 `P6_child_financial` for a child session).
  Future<Map<String, dynamic>> proposeExpense(
    String childId, {
    required String description,
    required int amountCents,
    required String category,
    required String incurredOn,
    required int payerSharePercent,
    String? receiptKey,
  }) =>
      _post(expenses, {
        'description': description, 'amountCents': amountCents, 'category': category,
        'incurredOn': incurredOn, 'payerSharePercent': payerSharePercent,
        'receiptKey': ?receiptKey,
      }, childId: childId);

  /// Resolves one pending expense -- POST [expenseAccept]/[expenseDispute]/
  /// [expenseReimburse] per [action] ('accept'|'dispute'|'reimburse'),
  /// server/routes.mjs's real handler (resolveExpense(), packages/db/src/
  /// pool.ts). Maps expenses_screen.dart's own three inbox actions: `Agree`
  /// -> `'accept'`, `Decline` -> `'dispute'` (there is no real `declined`
  /// status -- resolveExpense()'s own doc comment explains why `disputed`
  /// is the honest closest fit, not an invented one). `Query it` has no
  /// server route at all yet -- a real, disclosed gap, never silently
  /// mapped to one of these three. Returns the updated row verbatim, same
  /// shape [proposeExpense] returns, so a caller can update its own ledger
  /// view from the real response rather than re-fetching. Throws
  /// [ApiException] on any non-2xx response -- notably 404
  /// `expense_not_found` for a wrong or cross-child id (the real
  /// lateral-privilege boundary lives in `resolveExpense()`'s own
  /// `WHERE child_id = $childId` clause, not just this client), 403
  /// `role_lacks_capability` for a coordinator (read-only role, never a
  /// real decision-maker on the ledger).
  Future<Map<String, dynamic>> resolveExpense(String childId, String expenseId, String action) {
    final String path = switch (action) {
      'accept' => expenseAccept,
      'dispute' => expenseDispute,
      'reimburse' => expenseReimburse,
      _ => throw ArgumentError.value(action, 'action', 'must be accept|dispute|reimburse'),
    };
    return _post(
        path.replaceFirst(':childId', childId).replaceFirst(':expenseId', expenseId), const {});
  }

  /// `{localDate, medications: [{id, name, dose, slots, isPrn,
  /// minGapHours}, ...], doses: [{id, medicationId, localDate, slot,
  /// administeredAt, byUserId, byUserName, status}, ...]}` -- GET
  /// [medications], server/routes.mjs's real handler. `localDate` and every
  /// dose's `administeredAt` are already resolved in the CHILD's own local
  /// frame server-side (the same `child_tz_interval`/`home_tz` resolution
  /// every other child-local-time read in this client already relies on) --
  /// `doses` covers every medication for THAT one local day in one round
  /// trip, matching what meds_care.dart's own `_givenToday()` needs to
  /// render every medication's dosing state without a fetch per medication.
  /// Throws [ApiException] on any non-2xx response -- notably 403
  /// `not_a_child_surface` for a child session (meds_care.dart's own file
  /// header: "never a surface the child carries").
  Future<Map<String, dynamic>> fetchMedications(String childId) =>
      _get(medications, childId: childId);

  /// Records ONE real dose -- POST [medicationDoses], server/routes.mjs's
  /// real handler (recordDose(), packages/db/src/pool.ts). `status`
  /// defaults server-side to `'given'` when omitted, matching this
  /// client's own one real call site (meds_care.dart only ever logs a
  /// given dose). Returns the created row on success (`id, medicationId,
  /// localDate, slot, administeredAt, status`). A 409 `already_administered`
  /// response (`{error, by, atIso}`) is a normal, expected outcome here --
  /// the real double-dose guard (`medication_dose_no_double_given`, a
  /// partial unique index, migration 0026) -- so this decodes and returns
  /// that body directly instead of throwing, mirroring [captureHomework]'s
  /// own posture for its own normal-but-non-2xx outcome, and only throws
  /// [ApiException] for a genuinely unexpected status.
  Future<Map<String, dynamic>> recordMedicationDose(
    String childId, String medicationId, String slot, {
    String status = 'given',
  }) async {
    final res = await _client.post(
      _uri(medicationDoses.replaceFirst(':childId', childId)
          .replaceFirst(':medicationId', medicationId)),
      headers: {'authorization': 'Bearer $sessionToken', 'content-type': 'application/json'},
      body: jsonEncode({'slot': slot, 'status': status}),
    );
    final body =
        res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 201 || res.statusCode == 409) return body;
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }

  /// `{bloodType, allergies, conditions, pediatricianName,
  /// pediatricianPractice, pediatricianPhone, insuranceProvider,
  /// insuranceMemberId, guardians: [{userId, name, phone}, ...],
  /// medications: [{id, name, dose, slots, isPrn}, ...]}` -- GET
  /// [emergencyCard], server/routes.mjs's real handler
  /// (medicalRecordFor(), packages/db/src/pool.ts). `guardians` is derived
  /// LIVE from the real guardianship/app_user rows, including
  /// `phone_e164` -- never a second, storable, driftable copy (see that
  /// route's own migration header for why). Throws [ApiException] on any
  /// non-2xx response -- notably 403 `not_a_child_surface` for a child
  /// session, matching [fetchMedications]'s identical posture.
  Future<Map<String, dynamic>> fetchEmergencyCard(String childId) =>
      _get(emergencyCard, childId: childId);

  /// Replace-all write of [childId]'s real medical_record -- PUT
  /// [emergencyCard], server/routes.mjs's real handler (setMedicalRecord(),
  /// packages/db/src/pool.ts). `allergies`/`conditions` are the caller's
  /// ENTIRE new lists for every call, never a delta -- same "replace-all,
  /// never append" convention [setAvailability] already establishes for a
  /// different table. Guardian-only: a sitter (a real `emergency_card.view`
  /// holder) gets 403 `role_lacks_capability`, not P6 (this is medical, not
  /// financial). Returns the updated record verbatim, same shape
  /// [fetchEmergencyCard] returns, so a caller can render the just-saved
  /// card immediately without a second round trip.
  Future<Map<String, dynamic>> putEmergencyCard(
    String childId, {
    String? bloodType,
    List<String>? allergies,
    List<String>? conditions,
    String? pediatricianName,
    String? pediatricianPractice,
    String? pediatricianPhone,
    String? insuranceProvider,
    String? insuranceMemberId,
  }) =>
      _put(emergencyCard, childId: childId, body: {
        'bloodType': ?bloodType, 'allergies': ?allergies, 'conditions': ?conditions,
        'pediatricianName': ?pediatricianName, 'pediatricianPractice': ?pediatricianPractice,
        'pediatricianPhone': ?pediatricianPhone, 'insuranceProvider': ?insuranceProvider,
        'insuranceMemberId': ?insuranceMemberId,
      });

  /// `{items: [{id, label, essential, sent, returned}, ...]}` -- GET
  /// [exchangeBagItems], server/routes.mjs's real handler (bagItemsFor(),
  /// packages/db/src/pool.ts). Essential items first, matching
  /// exchange_screen.dart's own `manifestOrder()`. Throws [ApiException] on
  /// any non-2xx response -- notably 403 `not_a_child_surface` for a child
  /// session (this screen is guardian-shell-only, same posture
  /// [fetchMedications] already has).
  Future<Map<String, dynamic>> fetchExchangeBagItems(String childId) =>
      _get(exchangeBagItems, childId: childId);

  /// Toggles ONE bag item's `sent`/`returned` -- POST
  /// [exchangeBagItemStatus], server/routes.mjs's real handler
  /// (setBagItemStatus(), packages/db/src/pool.ts). Omitting a field leaves
  /// it unchanged server-side; only pass the one the caller actually
  /// toggled, matching exchange_screen.dart's own `_toggleSent`/
  /// `_toggleReturned` (each flips exactly one flag). Returns the updated
  /// item verbatim. Throws [ApiException] on any non-2xx response --
  /// notably 404 `bag_item_not_found` for a wrong or cross-child id (the
  /// real lateral-privilege boundary lives in `setBagItemStatus()`'s own
  /// `WHERE child_id = $childId` clause, same shape [resolveExpense]'s own
  /// doc comment describes for a different table).
  Future<Map<String, dynamic>> setExchangeBagItemStatus(
    String childId, String itemId, {
    bool? sent,
    bool? returned,
  }) =>
      _post(
        exchangeBagItemStatus.replaceFirst(':childId', childId).replaceFirst(':itemId', itemId),
        {'sent': ?sent, 'returned': ?returned},
      );

  /// `{entries: [{id, loggedAt, etaMinutes, reportedByUserId,
  /// reportedByName}, ...]}`, newest first -- GET [exchangeRunningLate],
  /// server/routes.mjs's real handler (runningLateLogFor(), packages/db/src/
  /// pool.ts). Throws [ApiException] on any non-2xx response, same posture
  /// as [fetchExchangeBagItems].
  Future<Map<String, dynamic>> fetchExchangeRunningLate(String childId) =>
      _get(exchangeRunningLate, childId: childId);

  /// Appends ONE new running-late entry -- POST [exchangeRunningLate],
  /// server/routes.mjs's real handler (logRunningLate(), packages/db/src/
  /// pool.ts). Insert-only, matching exchange_screen.dart's own file header
  /// ("there is no _editLateEntry and no _deleteLateEntry"): this class
  /// exposes no corresponding update/delete method at all, same posture
  /// [postHandoverNote]'s own doc comment describes for a different
  /// append-only log. Returns the created row verbatim. Throws
  /// [ApiException] on any non-2xx response -- notably 400
  /// `eta_minutes_must_be_positive` for a non-positive value.
  Future<Map<String, dynamic>> logExchangeRunningLate(String childId, int etaMinutes) =>
      _post(exchangeRunningLate, {'etaMinutes': etaMinutes}, childId: childId);

  /// `{event: {id, scheduledAt, arrivedAt, delayMinutes} | null}` -- GET
  /// [exchangeArrival], server/routes.mjs's real handler (arrivalEventFor(),
  /// packages/db/src/pool.ts). The most recent real arrival event, or
  /// honestly `null` when none has ever been logged -- same "honest
  /// absence, not a guess" posture [fetchPresence]'s own `free` field
  /// already has. Throws [ApiException] on any non-2xx response.
  Future<Map<String, dynamic>> fetchExchangeArrival(String childId) =>
      _get(exchangeArrival, childId: childId);

  /// Logs the real arrival event for RIGHT NOW -- POST [exchangeArrival],
  /// server/routes.mjs's real handler (recordExchangeArrival(),
  /// packages/db/src/pool.ts). Takes no location parameter -- P3 (§9.7.2),
  /// structurally: there is nothing here a caller could even pass through.
  /// `scheduledAt`/`delayMinutes` are computed server-side from the child's
  /// real active custody order, never from a client-supplied time. A 409
  /// `no_active_custody_order` response is a normal, honest outcome (no
  /// order on file to compute a delay against) -- this decodes and returns
  /// that body directly instead of throwing, mirroring
  /// [recordMedicationDose]'s own posture for its own normal-but-non-2xx
  /// outcome, and only throws [ApiException] for a genuinely unexpected
  /// status.
  Future<Map<String, dynamic>> recordExchangeArrival(String childId) async {
    final res = await _client.post(
      _uri(exchangeArrival, childId),
      headers: {'authorization': 'Bearer $sessionToken', 'content-type': 'application/json'},
      body: jsonEncode(const {}),
    );
    final body =
        res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 201 || res.statusCode == 409) return body;
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }

  /// Checks [pin] against every LIVE guardian of [childId] -- POST
  /// kioskPinVerify, server/routes.mjs's real handler. This is the check
  /// kiosk_shell.dart's PIN gate calls after a kiosk defeat, replacing
  /// main_live.dart's former hardcoded '1273' demo stub.
  ///
  /// FAILS CLOSED, DELIBERATELY: a network error, a timeout, a malformed
  /// response body, or any non-2xx status all return `false` here, never
  /// `true` and never a thrown exception. A broken network must never be
  /// indistinguishable from "the PIN was correct" -- that would let a lost
  /// connection defeat the kiosk lock outright, which is a strictly worse
  /// failure mode than a rejected PIN a guardian can just retry.
  Future<bool> verifyKioskPin(String childId, String pin) async {
    try {
      final body = await _post(kioskPinVerify, {'pin': pin}, childId: childId);
      return body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Sets/replaces the CALLER'S OWN guardian PIN -- POST guardianPinPath,
  /// server/routes.mjs's real handler. Requires a guardian session (the
  /// server returns 403 guardian_session_required for a child session).
  ///
  /// Unlike [verifyKioskPin] this is NOT fail-closed-to-a-bool: it's a
  /// guardian-initiated settings write, not a lock-defeat check something
  /// else's security posture depends on, so a caller needs the REAL reason a
  /// PIN couldn't be set (e.g. invalid_pin_format, guardian_session_required)
  /// rather than an opaque `false`. Throws [ApiException] on any non-2xx
  /// response, exactly like [fetchMe]/[fetchNow]/[fetchInbox] above.
  Future<void> setGuardianPin(String pin) async {
    await _post(guardianPinPath, {'pin': pin});
  }

  /// Starts a real call for [childId] — POST [calls], server/routes.mjs's
  /// real handler: mints a real session (session-runtime's createSession/
  /// mintToken, a genuinely new room per call — never the same room twice),
  /// then attempts a real `call_incoming` push via notifyDevices(), and
  /// records a real call_log row (2026-08-23). Returns the decoded body
  /// verbatim — `room`/`serverURL`/`identity`/`rang`/`sessionId` — the same
  /// shape [CallScreen.knownRoom]/[knownServerURL] expect, plus `sessionId`
  /// for [endCall] below, so a caller can pass this straight through
  /// without re-deriving anything.
  ///
  /// Throws [ApiException] on any non-2xx response (e.g. 403
  /// child_cannot_start_call for a child session, 403 no_edge for a
  /// guardian with no live edge to this child) — same posture as
  /// [setGuardianPin] above: a failed call-start must never be silently
  /// swallowed into "nothing happened."
  Future<Map<String, dynamic>> startCall(String childId) =>
      _post(calls, const {}, childId: childId);

  /// Marks call_log's own row for [sessionId] ended — POST [callEnd],
  /// server/routes.mjs's real handler (2026-08-23). Idempotent: returns
  /// `{ended: false}` on an already-ended session, never an error — a real
  /// call site (e.g. [CallScreen.onCallEnd]) should treat any non-2xx
  /// response as non-fatal (record-keeping only; nothing about the call
  /// itself depends on this succeeding) rather than surfacing it to the
  /// user, the same posture [startCall]'s own push-notification failure
  /// already has inside routes.mjs.
  Future<Map<String, dynamic>> endCall(String childId, String sessionId) => _post(
      callEnd.replaceFirst(':childId', childId).replaceFirst(':sessionId', sessionId),
      const {});

  /// Invites a new guardian/adult into [childId]'s family graph -- POST
  /// guardianships, server/routes.mjs's real handler. Requires a live
  /// guardian session already holding a guardian edge to this exact child
  /// (checked server-side; a 403 not_a_guardian_of_child or
  /// child_cannot_invite comes back as [ApiException] like any other
  /// non-2xx response here). Does NOT create a guardianship row for the
  /// invited party -- see 0014_guardian_invite.sql's own header for why:
  /// this route closes invite creation, not account creation, which this
  /// codebase has never built for a brand-new guardian.
  Future<Map<String, dynamic>> createGuardianInvite(
    String childId, {
    required String role,
    required String label,
    required String invitedEmail,
  }) => _post(guardianships, {'role': role, 'label': label, 'invitedEmail': invitedEmail},
      childId: childId);

  /// Requests a real WebAuthn REGISTRATION challenge -- POST the
  /// [webauthnRegisterChallenge] path, server/routes.mjs's real handler.
  /// Requires a guardian session (403 guardian_session_required for a child
  /// session). Named distinctly from the path constant above it calls (same
  /// disambiguation [setGuardianPin]/[guardianPinPath] already uses) so the
  /// two don't collide. Returns the raw `{challenge, rpId, userId}` body:
  /// webauthn_channel.dart's [buildRegisterPasskeyCallback] is what actually
  /// consumes it (feeds it straight to WebAuthnChannel.register()), not this
  /// class -- this class stays transport-only, matching every other method
  /// here.
  Future<Map<String, dynamic>> requestWebauthnRegisterChallenge() =>
      _post(webauthnRegisterChallenge, const {});

  /// Verifies a real WebAuthn REGISTRATION ceremony -- POST the
  /// [webauthnRegisterVerify] path, server/routes.mjs's real handler
  /// (challenge consumption, rpIdHash check, CBOR/COSE public-key
  /// extraction, credential storage). [clientDataJSON]/[attestationObject]
  /// must be the base64url strings WebAuthnBridge.kt's register() returned,
  /// untouched. Throws [ApiException] on any non-2xx response (e.g.
  /// challenge_mismatch, rpid_mismatch, origin_mismatch) -- a registration
  /// failure is a real fact the caller must see, not one to fail silently
  /// past.
  Future<void> submitWebauthnRegisterVerify({
    required String clientDataJSON,
    required String attestationObject,
  }) async {
    await _post(webauthnRegisterVerify,
        {'clientDataJSON': clientDataJSON, 'attestationObject': attestationObject});
  }

  /// `{windows: [{guardianId, weekday, startLocal, endLocal, note}, ...]}` —
  /// every co-guardian's windows for `childId`, INCLUDING the caller's own
  /// (see pool.mjs's availabilityFor() header for why). Decoding into a
  /// domain shape is left to the caller, matching fetchNow/fetchInbox above.
  Future<Map<String, dynamic>> getAvailability(String childId) =>
      _get(childAvailability, childId: childId);

  /// Replace-all: `windows` is the caller's ENTIRE new set for every call,
  /// never a delta — omitting a day clears it. Each map is
  /// `{weekday, startLocal, endLocal, note}`; no `guardianId` field — the
  /// server always uses the authenticated caller's own identity
  /// (server/routes.mjs's PUT /v1/me/availability), never anything the body
  /// could redirect.
  Future<Map<String, dynamic>> setAvailability(List<Map<String, dynamic>> windows) =>
      _put(meAvailability, body: windows);

  /// `{theme: {themePalette, themeBrightness} | null}` — server/routes.mjs's
  /// GET .../theme. `null` means no row has ever been set for this child
  /// (never seen a guardian Apply) -- decoding a null/malformed value into a
  /// real, fail-closed [AppTheme] is theme.dart's `AppTheme.fromWire`'s job,
  /// left to the caller exactly like [getAvailability] above leaves shape
  /// decoding to its own caller.
  Future<Map<String, dynamic>> fetchTheme(String childId) =>
      _get(childTheme, childId: childId);

  /// The caller's own guardian identity writes [childId]'s active theme --
  /// server/routes.mjs's PUT .../theme, guardian-write/child-read, real RLS
  /// (a live guardian edge to [childId] required; enforced at the DB layer,
  /// not just here). `themePalette`/`themeBrightness` are the wire enum
  /// names theme.dart's `AppTheme.toWire()` produces (`ThemePalette`/
  /// `ThemeBrightness`'s own `.name`), passed as plain strings here so this
  /// transport-layer class stays independent of that domain type, the same
  /// separation [getAvailability]/[setAvailability] already keep.
  Future<Map<String, dynamic>> putTheme(String childId,
          {required String themePalette, required String themeBrightness}) =>
      _put(childTheme,
          childId: childId,
          body: {'themePalette': themePalette, 'themeBrightness': themeBrightness});

  /// Posts a raw homework photo (PNG or JPEG bytes — server/routes.mjs's
  /// handler sniffs real magic bytes, not a filename or content-type) as
  /// base64 in a JSON body, and runs it through the real quality gate + OCR
  /// + guarded-hint pipeline (packages/homework/src/capture-route.ts).
  ///
  /// Unlike [_get]'s all-4xx/5xx-throw contract, a 422 quality-gate refusal
  /// is a normal, expected outcome here — the exact same "one more try" flow
  /// retake_screen.dart already renders for a failing *simulated* verdict
  /// (see capture_gate.dart) — so this decodes and returns that body
  /// directly instead of throwing, and only throws [ApiException] for a
  /// genuinely unexpected status.
  Future<Map<String, dynamic>> captureHomework(String childId, List<int> imageBytes) async {
    final res = await _client.post(
      _uri(homeworkCapture, childId),
      headers: {'authorization': 'Bearer $sessionToken', 'content-type': 'application/json'},
      body: jsonEncode({'image': base64Encode(imageBytes)}),
    );
    final body =
        res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 || res.statusCode == 422) return body;
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }

  /// `{ order: {...} }` for a real custody order, or `{ order: null }` when
  /// this child has none on file yet -- an honest absence server/routes.mjs
  /// returns rather than a 404, see that route's own comment.
  Future<Map<String, dynamic>> getCustodyOrder(String childId) =>
      _get(custodyOrder, childId: childId);

  /// POST /v1/me/delete — MASTERFILE §2.10, §2.11, §9.8, P8. Deactivates the
  /// CALLING guardian's own account (server/routes.mjs resolves the target
  /// from the verified session; nothing this method sends can widen or
  /// redirect it). See packages/db/src/pool.ts's deactivateAccount() for
  /// exactly what survives (delivered messages, the parent-to-parent log,
  /// the child's preserved archive) and what does not (queued/undelivered
  /// delivery_intent rows, PIN/passkey credentials, the login itself). On
  /// success the response body carries `ok: true` plus counts of what was
  /// removed; on failure this throws [ApiException] with the server's real
  /// reason (`already_deactivated`, `account_not_found`, `no_user_identity`,
  /// or a transport/auth failure) — deletion_screen.dart's `_confirm()` is
  /// the caller responsible for turning that into honest on-screen copy.
  /// No real body to send — server resolves the target from the session,
  /// same empty-map convention [requestWebauthnRegisterChallenge] already
  /// uses for a POST with nothing to carry.
  Future<Map<String, dynamic>> deleteAccount() => _post(deleteAccountPath, const {});

  /// POST /v1/children/:childId/handover — §9.8.4, §7.9, §21.2 rung 17,
  /// §21.6/§21.7.
  /// The CALLING CHILD's own export + majority guardianship closure, in one
  /// atomic action — server/routes.mjs resolves and re-verifies the target
  /// from the verified child session (`c.principal.childId`), the same A3
  /// discipline every other identity-scoped route here follows; [childId] is
  /// sent only to select the path, never trusted over the session.
  ///
  /// Unlike [deleteAccount] this is not a "how much survives" question —
  /// nothing of hers is destroyed. On success the response carries a real,
  /// full raw-export bundle (same shape [fetchRawExport] returns —
  /// `bundle`/`bundleJson`/`bundleHash`/`exportRecordId`, PLUS
  /// `handedOverAt`/`guardianshipsClosed`/`artifactsTransferred`/
  /// `journalEntriesTransferred`) and every one of her guardianship edges is
  /// now closed. On failure this throws [ApiException] with the server's
  /// real reason — `not_yet_of_age`, `already_handed_over`, `child_deceased`,
  /// or `not_this_child`/a transport failure — take_and_go_screen.dart's
  /// `_takeAndGo()` is the caller responsible for turning that into honest
  /// on-screen copy, exactly like [deleteAccount]'s own caller does.
  Future<Map<String, dynamic>> takeAndGo(String childId) =>
      _post(takeAndGoPath, const {}, childId: childId);

  /// Response shape (server/routes.mjs, packages/db/src/pool.mjs's
  /// rawExportBundleFor): `{bundle, bundleJson, exportRecordId, bundleHash}`.
  /// `bundleJson` is the EXACT string `bundleHash` was computed over — a
  /// caller that wants to verify the hash should hash/persist that field,
  /// not re-encode `bundle` itself (see routes.mjs's own comment on why).
  Future<Map<String, dynamic>> fetchRawExport(String childId) =>
      _get(export_, childId: childId);

  /// GET /v1/children/:childId/export?kind=certified — §2.11, §16.1 #3.
  /// Same route as [fetchRawExport], distinguished by the `kind` query
  /// param server-side (routes.mjs's single handler dispatches on it, not a
  /// second registration — see `export_`'s own doc comment above). A denial
  /// (annual allowance used / tier required / a broken chain / not a
  /// guardian of this child) surfaces as an [ApiException] with the real
  /// server-reported `error` reason and plain-language `message`, never a
  /// silent failure or a fabricated success.
  Future<Map<String, dynamic>> fetchCertifiedExport(String childId) =>
      _get(export_, childId: childId, query: const {'kind': 'certified'});

  /// POST .../messages — server/routes.mjs's real counterpart to
  /// [fetchInbox], and the real backend for receipt_screen.dart's "Send one
  /// back". Runs through captureMessage() server-side for validation before
  /// anything is persisted (see that route's own header): a rejection —
  /// wrong sender, an empty recording, a night already past — comes back as
  /// a real [ApiException], not a fake 200. Returns the created intent's id,
  /// its media artifact id, and its starting state ('pending').
  Future<Map<String, dynamic>> sendMessage(
    String childId, {
    required String storageKey,
    required int durationMs,
    String? captionKey,
    String? targetLocalDate,
    String daypart = 'bedtime',
    bool preserve = false,
  }) =>
      _post(messages, {
        'storageKey': storageKey,
        'durationMs': durationMs,
        'captionKey': ?captionKey,
        'targetLocalDate': ?targetLocalDate,
        'daypart': daypart,
        'preserve': preserve,
      }, childId: childId);

  /// POST .../media — server/routes.mjs's real upload route, the other real
  /// half of [sendMessage]'s own header comment ("the real backend for
  /// receipt_screen.dart's 'Send one back'"). Uploads [bytes] as base64 in a
  /// JSON body -- same convention [captureHomework] already uses for a
  /// photo, applied here to a real recorded video -- and returns the REAL
  /// storage key server/routes.mjs's FilesystemStorage instance assigned,
  /// meant to be handed straight to [sendMessage]'s own `storageKey`
  /// parameter as the very next call. Two genuinely separate server-side
  /// steps on purpose (this route only ever decides whether bytes can be
  /// WRITTEN; [sendMessage] is what decides whether the capture itself is
  /// ALLOWED, via captureMessage()'s own pipeline) -- a caller that uploads
  /// bytes and never calls [sendMessage] afterward leaves a real, orphaned
  /// blob with no media_artifact row pointing at it; receipt_screen.dart's
  /// own retry logic caches the returned key across a retry specifically to
  /// avoid creating a SECOND one for the same recording, but a genuinely new
  /// upload attempt (a fresh recording) has no way to reclaim an earlier
  /// orphan -- a real, honest limitation, not one this method hides.
  ///
  /// Throws [ApiException] on any non-2xx response (e.g. 400 `bytes_required`
  /// for an empty body, 403 for a role with no message capability -- the
  /// same `action: 'message'` gate [sendMessage] itself is checked against),
  /// exactly like [sendMessage]'s own posture on a real rejection.
  Future<String> uploadMedia(String childId, List<int> bytes) async {
    final Map<String, dynamic> body =
        await _post(media, {'bytes': base64Encode(bytes)}, childId: childId);
    return body['storageKey'] as String;
  }

  /// GET .../messages/:artifactId/media — server/routes.mjs's real download
  /// route, the read-side counterpart to [uploadMedia]. Requires the SAME
  /// live session/edge [sendMessage]/[fetchInbox] already require for this
  /// exact child (server-side: api.ts's `action: 'message'` gate, then
  /// `mediaArtifactFor()`'s own `child_id` + artifact-id scoping -- see that
  /// function's own doc comment in pool.ts for why the double scoping is the
  /// real authorization boundary, not a formality). Returns the real bytes,
  /// base64-decoded here so a caller gets back exactly what [uploadMedia]
  /// was given, never the wire encoding. Throws [ApiException] on a 404
  /// (`artifact_not_found` -- wrong id, or one belonging to a different
  /// child; `media_not_found` -- a row that outlived its blob, e.g. the
  /// storage reaper's own tombstone case) or any other non-2xx response, the
  /// same posture as every other read in this class.
  Future<List<int>> fetchMessageMedia(String childId, String artifactId) async {
    final Map<String, dynamic> body = await _get(
        messageMedia.replaceFirst(':childId', childId).replaceFirst(':artifactId', artifactId));
    return base64Decode(body['bytes'] as String);
  }

  /// POST /v1/me/device-tokens — {platform, token[, channel]} in, the new
  /// device_token row's real id out. `platform` must be 'android' or 'ios'
  /// (server-side DEVICE_PLATFORMS check, routes.mjs). Content-free by
  /// construction — there is nothing else this call could carry.
  ///
  /// `channel` (§8.11.4, v0.49.11) is OPTIONAL and OMITTED from the request
  /// body entirely when null — never sent as a literal `"channel": null`.
  /// The server's own 0015 migration treats omission and an explicit null
  /// identically (NULL, "unknown," never a guessed default), but omitting
  /// the key is the more honest wire shape: this call genuinely does not
  /// know the value, rather than asserting a null fact about it.
  Future<String> registerDeviceToken({
    required String platform,
    required String token,
    String? channel,
  }) async {
    final body = await _post(deviceTokens, {
      'platform': platform,
      'token': token,
      'channel': ?channel,
    });
    return body['id'] as String;
  }

  /// DELETE /v1/me/device-tokens — {token} in, whether a row actually
  /// existed to delete out. No call site in this client yet (no sign-out
  /// flow exists in lib/ as of this pass — see push_channel.dart's own
  /// `unregister()` doc comment); kept symmetric with the server route so
  /// wiring a future sign-out is a one-line call, not a new endpoint.
  Future<bool> unregisterDeviceToken(String token) async {
    final body = await _delete(deviceTokens, {'token': token});
    return body['deleted'] as bool;
  }

  void close() => _client.close();
}

/// Real WebAuthn LOGIN — the passkey ceremony's counterpart to [devLoginFor],
/// and free functions for the identical structural reason: server/index.mjs
/// implements both LOGIN routes outside api.register() because they
/// ESTABLISH a session (see that file's own header), so there is no existing
/// [OliveApi] instance -- which always already holds a session token -- to
/// hang these off of.
///
/// Takes a `userId` hint, not a discoverable-credential lookup -- see
/// server/index.mjs's webauthnLoginChallenge() for why (a real, deliberate
/// scope decision recorded there, not a shortcut). Returns the raw
/// `{challenge, rpId}` body.
Future<Map<String, dynamic>> webauthnLoginChallenge(
  String baseUrl,
  String userId, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.webauthnLoginChallenge}'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'userId': userId}),
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body;
}

/// Verifies a real WebAuthn LOGIN ceremony -- POST webauthnLoginVerify,
/// server/index.mjs's real handler (single-use challenge consume BEFORE
/// signature check, credential lookup, auth.ts's real verifyAssertion(),
/// sign-count update). All four assertion fields must be the base64url
/// strings WebAuthnBridge.kt's authenticate() returned, untouched. Returns
/// the new guardian session token on success, exactly like [devLoginFor].
Future<String> webauthnLoginVerify(
  String baseUrl, {
  required String userId,
  required String credentialId,
  required String clientDataJSON,
  required String authenticatorData,
  required String signature,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.webauthnLoginVerify}'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'userId': userId,
      'credentialId': credentialId,
      'clientDataJSON': clientDataJSON,
      'authenticatorData': authenticatorData,
      'signature': signature,
    }),
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body['token'] as String;
}

/// Reads a pending guardian invitation by its own id -- GET guardianInvite,
/// server/routes.mjs's real handler. No session: the invite's own long,
/// random id is what authorizes reading it (mirrors [webauthnLoginChallenge]'s
/// single-use-challenge posture for a not-yet-authenticated caller). Returns
/// `null` for a 404 (never existed) rather than throwing, since "no such
/// invite" is an ordinary, expected outcome here -- invitation_screen.dart's
/// real path reads this the same honest way [OliveApi.verifyKioskPin] treats
/// its own "false" as data, not an error.
Future<Map<String, dynamic>?> fetchGuardianInvite(
  String baseUrl,
  String inviteId, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.get(
    Uri.parse('$baseUrl${OliveApi.guardianInvite.replaceFirst(':inviteId', inviteId)}'));
  if (res.statusCode == 404) return null;
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body['invite'] as Map<String, dynamic>;
}

/// Records the real accept decision -- POST guardianInvite/accept, server/
/// routes.mjs's real handler. No session, same reasoning as
/// [fetchGuardianInvite]. Does NOT create a guardianship row -- see
/// 0014_guardian_invite.sql's own header. Throws [ApiException] on any
/// non-2xx response (expired/already_accepted/revoked/not_found are all
/// real, distinguishable failures a caller needs, not an opaque bool).
Future<Map<String, dynamic>> acceptGuardianInvite(
  String baseUrl,
  String inviteId, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.guardianInviteAccept.replaceFirst(':inviteId', inviteId)}'),
    headers: {'content-type': 'application/json'},
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body['invite'] as Map<String, dynamic>;
}

/// Cancels a pending invite before it's accepted -- POST guardianInviteRevoke,
/// server/routes.mjs's real handler. Requires a guardian session (only the
/// inviting guardian may revoke, checked server-side via RLS -- see
/// 0014_guardian_invite.sql's own header). No client screen calls this yet
/// (no "manage sent invites" surface exists) -- the route and this wiring
/// are real and tested regardless, ready for whenever one does, matching
/// this codebase's own convention of a real client constant sometimes
/// arriving ahead of the screen that will use it.
Future<void> revokeGuardianInvite(
  String baseUrl,
  String inviteId,
  String sessionToken, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.guardianInviteRevoke.replaceFirst(':inviteId', inviteId)}'),
    headers: {
      'authorization': 'Bearer $sessionToken',
      'content-type': 'application/json',
    },
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
}

/// Mints a real session for the invited party to complete passkey/PIN
/// registration -- POST guardianInviteBootstrap, server/routes.mjs's real
/// handler. No session, same reasoning as [fetchGuardianInvite]/
/// [acceptGuardianInvite]. Closes the account-creation gap CHANGELOG
/// v0.49.9 named and explicitly declined to invent an answer for ("how does
/// a passwordless account get created at all") WITHOUT touching WebAuthn
/// registration itself: the token this returns is an ordinary guardian
/// session with no guardianship edge to any child yet (none is created
/// here -- see 0014/0019_guardian_invite_bootstrap.sql's own headers), meant
/// to be handed straight to [OliveApi.webauthnRegisterChallenge]/[Verify]
/// (unchanged, already-existing routes), the same handoff
/// [GuardianSetupScreen.registerPasskey]'s own real caller would make. Only
/// succeeds once per invite, and only for one that has already been
/// accepted -- expired/revoked/not_accepted/already_bootstrapped/
/// email_already_registered are all real, distinguishable [ApiException]s,
/// not an opaque bool. No client screen calls this yet -- same "route and
/// wiring are real and tested regardless" convention [revokeGuardianInvite]
/// above already states for its own still-unwired route.
Future<Map<String, dynamic>> bootstrapGuardianInvite(
  String baseUrl,
  String inviteId,
  String displayName, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.guardianInviteBootstrap.replaceFirst(':inviteId', inviteId)}'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'displayName': displayName}),
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body;
}

/// Dev-only login helper wrapping [OliveApi.devLoginPath] — see
/// server/index.mjs's own header for why this exists and its limits: no
/// credential is checked, and the server refuses this route entirely unless
/// started with DEV_LOGIN=1.
Future<String> devLoginFor(
  String baseUrl, {
  String? userId,
  String? childId,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.devLoginPath}'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'userId': ?userId, 'childId': ?childId}),
  ).timeout(const Duration(seconds: 6));
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body['token'] as String;
}
