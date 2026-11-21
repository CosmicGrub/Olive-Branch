// OLIVE BRANCH — small pieces the backup screens share. UNVERIFIED on a device. Design: docs/planning/BACKUP-AND-RESTORE.md.
import 'package:flutter/material.dart';

/// The line printed on every screen that shows or takes the sheet.
const String kNeverAskWords = 'Only type these words on this screen. Olive will never ask for them by call, text or email. '
    'If someone does, say no, and tell the other grown-up.';

/// What it means to a family that has the sheet, said once and plainly.
const String kSheetHouseKeyWords = 'Anyone who has this paper and a copy of your backup can read your family\'s records, '
    'so keep it like the key to a safe. Olive cannot see it or get it back for you.';

String agoWords(int nowMs, int thenMs) {
  final int mins = (nowMs - thenMs) ~/ 60000;
  if (mins < 2) return 'just now';
  if (mins < 60) return '$mins minutes ago';
  final int hours = mins ~/ 60;
  if (hours < 24) return hours == 1 ? 'an hour ago' : '$hours hours ago';
  final int days = hours ~/ 24;
  return days == 1 ? 'yesterday' : '$days days ago';
}

class NeverAskCard extends StatelessWidget {
  const NeverAskCard({super.key});
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Container(
      key: const Key('neverAskCard'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Icon(Icons.shield_outlined, color: c.onSecondaryContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(kNeverAskWords, style: TextStyle(color: c.onSecondaryContainer))),
      ]),
    );
  }
}

class WordGrid extends StatelessWidget {
  const WordGrid(this.words, {super.key});
  final List<String> words;
  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Wrap(spacing: 10, runSpacing: 8, children: <Widget>[
      for (int i = 0; i < words.length; i++)
        Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline), borderRadius: BorderRadius.circular(8)),
          child: Text('${i + 1}  ${words[i]}', style: t.titleMedium),
        ),
    ]);
  }
}

