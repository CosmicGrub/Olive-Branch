// OLIVE BRANCH — guardian shell, expenses. No longer UNVERIFIED — verified by CI (a Flutter
// toolchain now runs for real in tools/verify.sh's automated pipeline —
// also manually built and run via `flutter analyze` / `flutter test` this
// session; CHANGELOG v0.49.61). MASTERFILE §9.6.5, prohibition P6. Renders
// MARKUP screen 'expenses'.
//
// P6: "Any financial or expense surface visible to a child role. No totals,
// no summaries, no notifications, no 'Dad paid for this.'" §9.6.5 says this
// is "invisible to the child at every depth, enforced by RLS, not by
// navigation" — the database is the real lock. This file is the second one,
// same posture as family-graph/authorize.ts's own doc comment ("this layer
// is the second lock, not the only one"):
//
//   1. No child-facing file in this codebase imports or references
//      ExpensesScreen — see expenses_screen_test.dart, which reads
//      child_home.dart's actual source text and asserts the string
//      'ExpensesScreen' never appears in it, so this is checked against
//      reality rather than assumed.
//   2. ExpensesScreen itself takes a `viewerRole` and, for anything other
//      than `ViewerRole.guardian`, renders a neutral screen that never
//      constructs, holds, or displays a single figure — the financial data
//      and the `_pending`/`_ledger` lists are never even built for a
//      non-guardian viewer. Fail closed, not fail open.
//
// The approval list below is a real port of guardian.ts's §12.7 coordination
// inbox — `InboxItem`, `INBOX_ACTIONS`, `inbox()`, `resolve()`,
// `isActionable()`, `admitToInbox()`, `inboxVisibleTo()` — filtered to the
// `expense_approval` kind, which is the one that already existed there.
//
// LIVE WIRING (baseUrl/guardianId/childId/httpClient, all optional and
// additive — same convention handover_notes.dart already establishes for a
// guardian_more.dart screen): when supplied, this screen fetches the real
// `expense` table via OliveApi.fetchExpenses() on init and resolves
// (Agree/Decline) via OliveApi.resolveExpense(), minting a fresh
// devLoginFor() session per call — same reasoning that file's own header
// gives. The P6 gate below runs FIRST, unconditionally, exactly as it
// always has — live wiring changes nothing about "fail closed, not fail
// open": `_load()` is never even called for a non-guardian viewerRole (see
// initState()), and the real server-side P6_child_financial check is a
// second, independent lock regardless. A real expense's `status` is one of
// `proposed|accepted|disputed|reimbursed` (expense.status's own CHECK
// constraint) — `proposed` entries populate the pending-approval pane,
// everything else populates the ledger; `Agree` maps to `'accept'`,
// `Decline` to `'dispute'` (there is no real `declined` status —
// resolveExpense()'s own doc comment, packages/db/src/pool.ts, explains why
// `disputed` is the honest closest fit). `Query it` has no server route
// at all yet — stays an honest, undisguised "not built" snackbar on the
// live path, never silently mapped to accept/dispute. The demo's own
// `_resolve()` bug (hardcoding `amountCents: 0` on Agree) does not carry
// over here — the live path always renders the real amount the server
// returns.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'form_factors.dart' as ff;

enum ViewerRole { guardian, child }

// ===================================================== guardian.ts §12.7 ===
enum InboxKind {
  expenseApproval, scheduleChange, invitation, documentRequest,
  medicationChange, coordinatorQuestion,
}

class InboxItem {
  InboxItem({required this.id, required this.kind, required this.summary,
    required this.fromUserId, required this.at, required this.actions,
    this.resolvedAt});
  final String id;
  final InboxKind kind;
  final String summary;
  final String fromUserId;
  final DateTime at;
  final List<String> actions;
  DateTime? resolvedAt;
}

const Map<InboxKind, List<String>> inboxActions = <InboxKind, List<String>>{
  InboxKind.expenseApproval: <String>['Agree', 'Query it', 'Decline'],
  InboxKind.scheduleChange: <String>['Accept', 'Propose another time', 'Decline'],
  InboxKind.invitation: <String>['Accept', 'Not now'],
  InboxKind.documentRequest: <String>['Send it', 'I do not have it'],
  InboxKind.medicationChange: <String>['Acknowledge', 'Query it'],
  InboxKind.coordinatorQuestion: <String>['Answer'],
};

/// Oldest first among the unresolved — the oldest is the one that has been
/// making the other parent wait.
List<InboxItem> inbox(List<InboxItem> items) {
  final List<InboxItem> open = items.where((InboxItem i) => i.resolvedAt == null).toList();
  open.sort((InboxItem a, InboxItem b) => a.at.compareTo(b.at));
  return open;
}

/// The inbox is adult-only. It is the machinery of coordination — §2.4.
bool inboxVisibleTo(ViewerRole role) => role != ViewerRole.child;

// ============================================================== the demo ===
final DateTime _now = DateTime.utc(2026, 8, 4);

class LedgerLine {
  LedgerLine({required this.id, required this.description, required this.amountCents,
    required this.paidBy, required this.payerSharePercent, required this.date,
    this.status = 'pending'});
  final String id;
  final String description;
  final int amountCents;
  final String paidBy;
  /// What the payer keeps; the remainder is owed back to them.
  final int payerSharePercent;
  final DateTime date;
  String status; // pending | agreed | declined | reimbursed

  int get owedToPayerCents => (amountCents * (100 - payerSharePercent) / 100).round();
}

String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

enum _LoadState { ready, loading, error }

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    this.viewerRole = ViewerRole.guardian,
    this.childName = 'Ivy',
    this.baseUrl,
    this.guardianId,
    this.childId,
    this.httpClient,
  });
  final ViewerRole viewerRole;
  final String childName;
  final String? baseUrl;
  /// The signed-in guardian's own id — devLoginFor's `userId` AND the "You"
  /// comparison against a fetched expense's `paidById`, same double duty
  /// `handover_notes.dart`'s own `guardianId` already documents.
  final String? guardianId;
  final String? childId;
  /// Injectable for tests (package:http/testing.dart's MockClient) — matches
  /// handover_notes.dart/AvailabilityScreen's own convention.
  final http.Client? httpClient;

  bool get _isLive => baseUrl != null && guardianId != null && childId != null;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  // Deliberately built inside State, not as a `final` field initializer that
  // runs unconditionally — see build() below, which never reaches this for a
  // non-guardian viewer. (`late` + a getter would run at first access
  // regardless of role, which is the exact mistake P6 exists to prevent.)
  List<InboxItem>? _approvals;
  List<LedgerLine>? _ledger;
  _LoadState _loadState = _LoadState.ready;
  final Set<String> _resolving = <String>{};

  @override
  void initState() {
    super.initState();
    // Guarded on viewerRole too, not just widget._isLive — see this file's
    // own LIVE WIRING header: nothing financial is even ATTEMPTED for a
    // non-guardian viewer, matching the "fail closed, not fail open"
    // posture build() already enforces for the rendered tree.
    if (widget._isLive && widget.viewerRole == ViewerRole.guardian) _load();
  }

  void _seedIfNeeded() {
    if (widget._isLive) return; // live path populates these via _load()
    if (_approvals != null) return;
    _approvals = <InboxItem>[
      InboxItem(id: 'exp-1', kind: InboxKind.expenseApproval,
        summary: 'Orthodontist co-pay, ${widget.childName}\'s adjustment visit',
        fromUserId: 'other-guardian', at: _now.subtract(const Duration(days: 2)),
        actions: inboxActions[InboxKind.expenseApproval]!),
      InboxItem(id: 'exp-2', kind: InboxKind.expenseApproval,
        summary: 'Soccer cleats, size 2',
        fromUserId: 'other-guardian', at: _now.subtract(const Duration(days: 5)),
        actions: inboxActions[InboxKind.expenseApproval]!),
    ];
    _ledger = <LedgerLine>[
      LedgerLine(id: 'l1', description: 'Winter coat', amountCents: 8900,
        paidBy: 'You', payerSharePercent: 50, date: _now.subtract(const Duration(days: 20)),
        status: 'reimbursed'),
      LedgerLine(id: 'l2', description: 'Piano lesson book', amountCents: 1499,
        paidBy: 'Other guardian', payerSharePercent: 50,
        date: _now.subtract(const Duration(days: 9)), status: 'agreed'),
    ];
  }

  /// The ONLY place this screen calls the network to READ — mirrors
  /// handover_notes.dart's own self-fetching pattern exactly: a fresh
  /// devLoginFor() per load, `api.close()` only on the success path (see
  /// that file's own `_load()` doc comment for why). A failure here is a
  /// real, honest error state with a retry affordance, never a silent
  /// fall-back to the demo fixtures.
  Future<void> _load() async {
    setState(() => _loadState = _LoadState.loading);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> result = await api.fetchExpenses(widget.childId!);
      if (widget.httpClient == null) api.close();
      final List<dynamic> raw = result['entries'] as List<dynamic>? ?? <dynamic>[];
      final List<InboxItem> approvals = <InboxItem>[];
      final List<LedgerLine> ledger = <LedgerLine>[];
      for (final dynamic e in raw) {
        final Map<String, dynamic> row = e as Map<String, dynamic>;
        final String status = row['status'] as String? ?? 'proposed';
        final String paidById = row['paidById'] as String? ?? '';
        final String description = row['description'] as String? ?? '';
        final int amountCents = row['amountCents'] as int? ?? 0;
        final int payerSharePercent = row['payerSharePercent'] as int? ?? 50;
        final DateTime createdAt =
            DateTime.tryParse(row['createdAt'] as String? ?? '') ?? _now;
        if (status == 'proposed') {
          approvals.add(InboxItem(id: row['id'] as String, kind: InboxKind.expenseApproval,
            summary: description, fromUserId: paidById, at: createdAt,
            actions: inboxActions[InboxKind.expenseApproval]!));
        } else {
          ledger.add(LedgerLine(id: row['id'] as String, description: description,
            amountCents: amountCents,
            paidBy: paidById == widget.guardianId
              ? 'You' : (row['paidByName'] as String? ?? 'Other guardian'),
            payerSharePercent: payerSharePercent, date: createdAt, status: status));
        }
      }
      if (!mounted) return;
      setState(() {
        _approvals = approvals;
        _ledger = ledger;
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  Future<void> _resolve(String id, String action) async {
    if (!widget._isLive) {
      setState(() {
        final InboxItem item = _approvals!.firstWhere((InboxItem i) => i.id == id);
        item.resolvedAt = _now;
        if (action == 'Agree') {
          _ledger!.add(LedgerLine(id: item.id, description: item.summary, amountCents: 0,
            paidBy: 'Other guardian', payerSharePercent: 50, date: _now, status: 'agreed'));
        }
      });
      return;
    }
    // 'Query it' has no server route at all yet — see this file's own LIVE
    // WIRING header. An honest, undisguised "not built" message, matching
    // this codebase's established convention (e.g. handover_notes.dart's
    // own absent-speak-callback snackbar) rather than silently mapping it
    // to accept/dispute or doing nothing with no feedback at all.
    if (action == 'Query it') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Querying an expense isn\'t built yet.'),
        duration: Duration(seconds: 2)));
      return;
    }
    final String serverAction = action == 'Agree' ? 'accept' : 'dispute';
    setState(() => _resolving.add(id));
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> row =
          await api.resolveExpense(widget.childId!, id, serverAction);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      setState(() {
        final InboxItem item = _approvals!.firstWhere((InboxItem i) => i.id == id);
        item.resolvedAt = _now;
        // The real amount the server returns — never the demo's own
        // hardcoded `amountCents: 0` (see this file's own LIVE WIRING
        // header for the bug this fixes).
        final int amountCents = row['amountCents'] as int? ?? 0;
        final int payerSharePercent = row['payerSharePercent'] as int? ?? 50;
        final String status = row['status'] as String? ?? serverAction;
        _ledger!.add(LedgerLine(id: item.id, description: item.summary,
          amountCents: amountCents, paidBy: 'Other guardian',
          payerSharePercent: payerSharePercent, date: _now, status: status));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't send that response — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _resolving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    // The gate. Nothing financial is constructed below this line for a
    // non-guardian viewer — see file header, point 2. Runs FIRST,
    // unconditionally, before the loading/error states below too — live
    // wiring never gets a chance to construct or render a single financial
    // widget for a non-guardian viewer either.
    if (!inboxVisibleTo(widget.viewerRole)) return const _NotAGuardianSurface();

    // Loading/error UI mirrors handover_notes.dart's own established shape
    // — only ever reachable when this screen is live-wired AND the viewer
    // is a real guardian (see initState()'s own guard); the pure demo path
    // never enters either state.
    if (_loadState == _LoadState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadState == _LoadState.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expenses')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
              style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        )),
      );
    }
    _seedIfNeeded();

    final List<InboxItem> pending = inbox(_approvals!);

    // Pane A — "Needs your answer": the section label plus the
    // pending-approvals content itself, either the empty state or the real
    // cards. Same widgets, same order, as this screen always rendered — only
    // ever split out into a named list so the wide/narrow branches below can
    // share it verbatim rather than diverging.
    final List<Widget> approvalsChildren = <Widget>[
      _SectionLabel('Needs your answer (${pending.length})'),
      const SizedBox(height: 8),
      if (pending.isEmpty)
        // 40/12 matches the house "nothing pending" empty-state idiom used
        // throughout (journal_screen.dart, letters_screen.dart,
        // teach_me.dart, weeks_screen.dart, inbox_screen.dart, etc.) — was
        // 32/8, an unintentional one-off from before that idiom settled.
        Padding(padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            Icon(Icons.mark_email_read_outlined, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Nothing waiting.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]))
      else
        for (final InboxItem item in pending)
          _ApprovalCard(item: item, resolving: _resolving.contains(item.id),
            onAction: (String a) => _resolve(item.id, a)),
    ];

    // Pane B — the ledger: the section label plus the ledger Card. Same
    // discipline as above.
    final List<Widget> ledgerChildren = <Widget>[
      const _SectionLabel('Ledger'),
      const SizedBox(height: 8),
      Card(child: Column(children: [
        for (final LedgerLine l in _ledger!)
          ListTile(
            title: Text(l.description),
            subtitle: Text('${l.paidBy} paid ${_money(l.amountCents)} · '
              '${l.payerSharePercent}/${100 - l.payerSharePercent} split · ${l.status}'),
            trailing: l.amountCents == 0 ? null
              : Text(_money(l.owedToPayerCents), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
      ])),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        // Shared, unsplit header — orientation copy, not compose/list
        // content, so it renders once, full-width, above the two-pane
        // region in both wide and narrow layouts. (message_banking.dart, the
        // reference pattern this split otherwise follows, has no such
        // header to carry.)
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.visibility_off_outlined, size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text('Guardian ↔ guardian only. ${widget.childName} never sees '
              'this screen, a total, or a notification about it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ])),
        const SizedBox(height: 20),
        Expanded(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          // Real §8.11.1 posture logic (form_factors.dart), not a made-up
          // number — same threshold message_banking.dart uses for its own
          // two-pane split: pending approvals and the ledger sit side by
          // side once the viewport can genuinely afford two real columns at
          // the current text scale. Below that, this is byte-for-byte the
          // same single stacked column this screen always rendered.
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final bool wide = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
          // SingleChildScrollView + Column, NOT ListView — a sliver list
          // only realizes children near the viewport, which would silently
          // drop pending approvals or ledger lines scrolled below the fold
          // from the widget tree. Same fix message_banking.dart,
          // journal_screen.dart, and letters_screen.dart already document
          // for the same bug class.
          return SingleChildScrollView(
            child: wide
              ? Row(key: const Key('expensesTwoPaneRow'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: approvalsChildren)),
                    const SizedBox(width: 24),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: ledgerChildren)),
                  ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ...approvalsChildren,
                  const SizedBox(height: 20),
                  ...ledgerChildren,
                ]),
          );
        })),
      ]))),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700,
      letterSpacing: 0.5, color: Theme.of(context).colorScheme.primary));
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.item, required this.onAction, this.resolving = false});
  final InboxItem item;
  final ValueChanged<String> onAction;
  /// True while a real live resolve() request for this item is in flight —
  /// disables the buttons so a slow connection can't be double-tapped into
  /// two competing requests. Always false on the demo path.
  final bool resolving;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.summary, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        // 48dp minimum tap target — these were 44dp (finding #3).
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final String action in item.actions)
            SizedBox(height: 48, child: OutlinedButton(
              onPressed: resolving ? null : () => onAction(action), child: Text(action))),
        ]),
      ])));
}

/// What every non-guardian viewer of this widget gets, unconditionally. No
/// financial word or figure appears anywhere in this subtree.
class _NotAGuardianSurface extends StatelessWidget {
  const _NotAGuardianSurface();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24),
      child: Text("There's nothing on this screen for you.",
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)))),
  );
}
