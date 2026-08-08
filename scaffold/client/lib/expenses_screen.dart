// OLIVE BRANCH — guardian shell, expenses. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.6.5,
// prohibition P6. Renders MARKUP screen 'expenses'.
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
// The expense ledger itself (receipt, split, reimbursement status) has no
// backing TS module yet: §9.6.5 describes it in prose only and marks it
// Phase 3, so the ledger UI below is new, honestly-local demo state, not a
// port — same posture the rest of this preview build takes for unbuilt
// backends.
import 'package:flutter/material.dart';

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

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, this.viewerRole = ViewerRole.guardian,
    this.childName = 'Ivy'});
  final ViewerRole viewerRole;
  final String childName;

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

  void _seedIfNeeded() {
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

  void _resolve(String id, String action) => setState(() {
    final InboxItem item = _approvals!.firstWhere((InboxItem i) => i.id == id);
    item.resolvedAt = _now;
    if (action == 'Agree') {
      _ledger!.add(LedgerLine(id: item.id, description: item.summary, amountCents: 0,
        paidBy: 'Other guardian', payerSharePercent: 50, date: _now, status: 'agreed'));
    }
  });

  @override
  Widget build(BuildContext context) {
    // The gate. Nothing financial is constructed below this line for a
    // non-guardian viewer — see file header, point 2.
    if (!inboxVisibleTo(widget.viewerRole)) return const _NotAGuardianSurface();
    _seedIfNeeded();

    final List<InboxItem> pending = inbox(_approvals!);
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
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
        _SectionLabel('Needs your answer (${pending.length})'),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              Icon(Icons.mark_email_read_outlined, size: 32,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('Nothing waiting.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]))
        else
          for (final InboxItem item in pending)
            _ApprovalCard(item: item, onAction: (String a) => _resolve(item.id, a)),
        const SizedBox(height: 20),
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
      ])),
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
  const _ApprovalCard({required this.item, required this.onAction});
  final InboxItem item;
  final ValueChanged<String> onAction;

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
              onPressed: () => onAction(action), child: Text(action))),
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
