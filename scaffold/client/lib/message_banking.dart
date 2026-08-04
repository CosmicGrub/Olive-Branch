// OLIVE BRANCH — guardian-side message banking. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). §9.5, §6.5, §8.2.8.
//
// A deploying parent records goodnight messages ahead of time; each queues
// to deliver on one future night, at the child's bedtime, in the child's
// timezone. Three invariants this widget tree enforces:
//   - Every banked entry is archive-tier (preserved = true), no exceptions.
//   - Revocation only ever touches the queued remainder. A delivered entry
//     has no delete affordance anywhere in its subtree — not disabled, not
//     hidden behind a confirm step, structurally absent — because "delivered
//     messages are the child's" (§9.5).
//   - If the queue outgrows the delivery window, that repeat is disclosed to
//     the guardian in plain language, not left implicit.
// The child-facing mechanism (cycling, counters, "42 of 180") never appears
// here at all — this screen only exists on the guardian side of the app.
import 'package:flutter/material.dart';

enum _BankStatus { queued, delivered }

class _BankedMessage {
  _BankedMessage({required this.id, required this.text, required this.night, required this.status});
  final int id;
  final String text;
  final int night;
  final _BankStatus status;
  // Archive-tier by default (§9.5) — nothing in this file ever constructs
  // one of these with preserved == false.
  bool get preserved => true;
}

class MessageBankingScreen extends StatefulWidget {
  const MessageBankingScreen({super.key});
  @override
  State<MessageBankingScreen> createState() => _MessageBankingScreenState();
}

class _MessageBankingScreenState extends State<MessageBankingScreen> {
  static const int _minWindow = 1;
  static const int _maxWindow = 10;

  final TextEditingController _controller = TextEditingController();
  final List<_BankedMessage> _messages = <_BankedMessage>[];
  int _nextId = 1;
  int _windowNights = 5;

  @override
  void initState() {
    super.initState();
    // Seed data so the screen reads like mid-use, not a blank first-run —
    // a mix of what's already gone out and what's still waiting.
    _messages.addAll(<_BankedMessage>[
      _seed('Good night, sleep tight — love you to the moon.', 1, _BankStatus.delivered),
      _seed('Sweet dreams, my brave girl. Proud of you today.', 2, _BankStatus.delivered),
      _seed('Missing you already. See you in your dreams tonight.', 3, _BankStatus.queued),
    ]);
    _controller.addListener(_onTextChanged);
  }

  _BankedMessage _seed(String text, int night, _BankStatus status) =>
      _BankedMessage(id: _nextId++, text: text, night: night, status: status);

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  int get _queuedCount => _messages.where((m) => m.status == _BankStatus.queued).length;
  int get _deliveredCount => _messages.length - _queuedCount;
  // "more than the chosen delivery-night count" — §9.5's disclosure rule.
  bool get _willCycle => _queuedCount > _windowNights;

  void _bank() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    final int night = (_messages.length % _windowNights) + 1;
    setState(() {
      _messages
          .add(_BankedMessage(id: _nextId++, text: text, night: night, status: _BankStatus.queued));
      _controller.clear();
    });
  }

  void _revokeOne(int id) =>
      setState(() => _messages.removeWhere((m) => m.id == id && m.status == _BankStatus.queued));

  void _revokeAllQueued() =>
      setState(() => _messages.removeWhere((m) => m.status == _BankStatus.queued));

  void _changeWindow(int delta) =>
      setState(() => _windowNights = (_windowNights + delta).clamp(_minWindow, _maxWindow));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Message banking')),
        // A bounded, small list — SingleChildScrollView over Column, NOT
        // ListView, so every banked entry genuinely exists in the tree rather
        // than being sliver-virtualized away outside the current viewport.
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Record tonight, deliver on her night',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                      "Each message lands at her bedtime, in her timezone, on the night you pick below.",
                      style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _controller,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: "Tonight's goodnight message...")),
                  const SizedBox(height: 12),
                  Row(children: [
                    // Expanded, not a bare Text + Spacer: on a narrow physical
                    // screen (confirmed on-device, not caught by the default
                    // test surface size) the label plus both fixed-width
                    // stepper controls overflowed the row by a few pixels.
                    // Expanded lets the label wrap instead of overflowing.
                    const Expanded(child: Text('Deliver over the next',
                      style: TextStyle(fontSize: 13))),
                    IconButton(
                        onPressed: () => _changeWindow(-1),
                        icon: const Icon(Icons.remove_circle_outline)),
                    SizedBox(
                        width: 64,
                        child: Text('$_windowNights nights',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                    IconButton(
                        onPressed: () => _changeWindow(1),
                        icon: const Icon(Icons.add_circle_outline)),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                          onPressed: _controller.text.trim().isEmpty ? null : _bank,
                          child: const Text('Bank this message'))),
                  if (_willCycle)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(10)),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Icon(Icons.repeat, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      'This will repeat: $_queuedCount messages queued for a '
                                      '$_windowNights-night window. Record more, or shorten the '
                                      'window, so nights stop reusing a message.',
                                      style: const TextStyle(fontSize: 12.5))),
                            ]))),
                  const SizedBox(height: 20),
                  const Divider(),
                  Text(
                      '${_messages.length} nights banked · $_deliveredCount delivered · '
                      '$_queuedCount queued',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (_queuedCount > 0)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                            onPressed: _revokeAllQueued,
                            icon: const Icon(Icons.cancel_outlined),
                            label: Text('Revoke remaining ($_queuedCount)'))),
                  const SizedBox(height: 8),
                  for (final _BankedMessage m in _messages)
                    _BankedTile(
                        message: m,
                        onRevoke: m.status == _BankStatus.queued ? () => _revokeOne(m.id) : null),
                ]))),
      );
}

class _BankedTile extends StatelessWidget {
  const _BankedTile({required this.message, required this.onRevoke});
  final _BankedMessage message;
  // Null, not disabled, for a delivered entry — there is no control to
  // disable. See the class doc for why that distinction matters.
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final bool delivered = message.status == _BankStatus.delivered;
    return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Tooltip(
              message: 'Preserved — archive tier',
              child: Icon(Icons.archive_outlined, color: Theme.of(context).colorScheme.primary)),
          title: Text(message.text),
          subtitle: Text('Night ${message.night} · '
              '${delivered ? 'Delivered' : 'Queued'}'),
          trailing: onRevoke == null
              ? null
              : IconButton(
                  tooltip: 'Revoke this message',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRevoke),
        ));
  }
}
