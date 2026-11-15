// OLIVE BRANCH — care guide models (guardian shell only). UNVERIFIED — not yet checked by CI's Flutter run.
//
// The parent-facing half of docs/care-guides/SCHEMA.md as plain Dart classes. Pure Dart (no Flutter), so the
// structural tests and the loader can use it anywhere.
//
// What is deliberately NOT here: the schema's `reviewOnly` object (disagreements, unverified items, reviewer
// questions, change log, clinician-only blocks) and the helplines' reviewer `note`. [CareGuide.fromJson] never reads
// them, and the bundled assets do not contain them either. A block flagged displayToParents:false, clinicianOnly or
// unverified therefore has no model to render from: it cannot reach a screen even by mistake.
//
// Everything is parsed strictly. A guide that does not match the schema throws [CareGuideFormatException] and the
// loader drops it (fail closed).

class CareGuideFormatException implements Exception {
  CareGuideFormatException(this.message);
  final String message;
  @override
  String toString() => 'CareGuideFormatException: $message';
}

T _need<T>(Map<String, Object?> m, String key, String where) {
  final Object? v = m[key];
  if (v is! T) throw CareGuideFormatException('$where.$key missing or wrong type');
  return v;
}

T? _opt<T>(Map<String, Object?> m, String key, String where) {
  final Object? v = m[key];
  if (v == null) return null;
  if (v is T) return v as T;
  throw CareGuideFormatException('$where.$key wrong type');
}

Map<String, Object?> _map(Object? v, String where) {
  if (v is! Map<String, Object?>) throw CareGuideFormatException('$where is not an object');
  return v;
}

List<Object?> _list(Object? v, String where) {
  if (v is! List<Object?>) throw CareGuideFormatException('$where is not a list');
  return v;
}

List<int> _ints(Object? v, String where) =>
    _list(v, where).map((Object? e) {
      if (e is! int) throw CareGuideFormatException('$where has a non-integer');
      return e;
    }).toList(growable: false);

List<String> _strings(Object? v, String where) =>
    _list(v, where).map((Object? e) {
      if (e is! String) throw CareGuideFormatException('$where has a non-string');
      return e;
    }).toList(growable: false);

/// The only status the gate treats as publishable. Anything else is not shown in a release build.
const String kStatusReviewed = 'REVIEWED';
const String kStatusDraft = 'DRAFT_UNREVIEWED';

/// Block kinds in the order the screens show them: emergency first, always.
const List<String> kBlockOrder = <String>[
  'emergency', 'urgent', 'poison', 'nurseLine', 'sameDay', 'afterEpisode',
  'firstSteps', 'doNow', 'dispatcherScript', 'haveReady', 'recognition', 'coolDown', 'howToMeasure',
  'doNot', 'watchFor', 'note', 'consent',
  'topHazards', 'room', 'arrivalChecklist', 'prevention',
];

class GuideReview {
  const GuideReview({this.reviewedOn, this.reviewedBy, this.regions = const <String>[]});
  factory GuideReview.fromJson(Object? raw) {
    final Map<String, Object?> m = _map(raw, 'review');
    return GuideReview(
      reviewedOn: _opt<String>(m, 'reviewedOn', 'review'),
      reviewedBy: _opt<String>(m, 'reviewedBy', 'review'),
      regions: _strings(m['regions'] ?? const <Object?>[], 'review.regions'),
    );
  }
  final String? reviewedOn; // YYYY-MM-DD
  final String? reviewedBy; // a role, never a name
  final List<String> regions;
}

class GuideSource {
  const GuideSource({required this.id, required this.org, required this.title, required this.url, required this.retrieved});
  factory GuideSource.fromJson(Object? raw) {
    final Map<String, Object?> m = _map(raw, 'source');
    return GuideSource(
      id: _need<int>(m, 'id', 'source'),
      org: _need<String>(m, 'org', 'source'),
      title: _need<String>(m, 'title', 'source'),
      url: _need<String>(m, 'url', 'source'),
      retrieved: _need<String>(m, 'retrieved', 'source'),
    );
  }
  final int id;
  final String org;
  final String title;
  final String url;
  final String retrieved; // YYYY-MM-DD
}

class CareItem {
  const CareItem({
    required this.text, this.sources = const <int>[], this.ages, this.group, this.n, this.detail, this.signs = const <String>[],
  });
  factory CareItem.fromJson(Object? raw, String where) {
    final Map<String, Object?> m = _map(raw, where);
    return CareItem(
      text: _need<String>(m, 'text', where),
      sources: _ints(m['sources'] ?? const <Object?>[], '$where.sources'),
      ages: _opt<String>(m, 'ages', where),
      group: _opt<String>(m, 'group', where),
      n: _opt<int>(m, 'n', where),
      detail: _opt<String>(m, 'detail', where),
      signs: m['signs'] == null ? const <String>[] : _strings(m['signs'], '$where.signs'),
    );
  }
  final String text;
  final List<int> sources;
  final String? ages;
  final String? group;
  final int? n;
  final String? detail;
  final List<String> signs;
}

class CareBlock {
  const CareBlock({required this.kind, required this.items, this.title});
  factory CareBlock.fromJson(Object? raw, String where) {
    final Map<String, Object?> m = _map(raw, where);
    final String kind = _need<String>(m, 'kind', where);
    if (!kBlockOrder.contains(kind)) throw CareGuideFormatException('$where.kind "$kind" is not a known kind');
    final List<Object?> items = _list(m['items'], '$where.items');
    return CareBlock(
      kind: kind,
      title: _opt<String>(m, 'title', where),
      items: <CareItem>[for (int i = 0; i < items.length; i++) CareItem.fromJson(items[i], '$where.items[$i]')],
    );
  }
  final String kind;
  final String? title;
  final List<CareItem> items;
}

class AgeBand {
  const AgeBand({required this.key, this.label, this.text, this.items = const <CareItem>[], this.note});
  factory AgeBand.fromJson(Object? raw, String where) {
    final Map<String, Object?> m = _map(raw, where);
    final List<Object?> items = m['items'] == null ? const <Object?>[] : _list(m['items'], '$where.items');
    return AgeBand(
      key: _need<String>(m, 'key', where),
      label: _opt<String>(m, 'label', where),
      text: _opt<String>(m, 'text', where),
      items: <CareItem>[for (int i = 0; i < items.length; i++) CareItem.fromJson(items[i], '$where.items[$i]')],
      note: _opt<String>(m, 'note', where),
    );
  }
  final String key; // as written in the draft, e.g. "0-3m"
  final String? label; // only where the draft has one
  final String? text;
  final List<CareItem> items;
  final String? note;
  String get display => label ?? key;
}

class Helpline {
  const Helpline({required this.region, required this.name, required this.number, this.sources = const <int>[]});
  factory Helpline.fromJson(Object? raw, String where) {
    final Map<String, Object?> m = _map(raw, where);
    return Helpline(
      region: _need<String>(m, 'region', where),
      name: _need<String>(m, 'name', where),
      number: _need<String>(m, 'number', where),
      sources: _ints(m['sources'] ?? const <Object?>[], '$where.sources'),
    );
  }
  final String region;
  final String name;
  /// The only place a phone number comes from. No screen or logic file carries a number of its own.
  final String number;
  final List<int> sources;
}

class GuideNote {
  const GuideNote({required this.kind, required this.text});
  final String kind; // "ages" | "tier"
  final String text;
}

class CareGuide {
  const CareGuide({
    required this.id, required this.title, required this.category, required this.region, required this.status,
    required this.revision, required this.lastResearched, required this.review, required this.blocks,
    required this.ageBands, required this.helplines, required this.sources,
    this.lastRevised, this.disclaimer, this.notes = const <GuideNote>[], this.emergencyFirstLine,
  });

  /// Parses ONLY the parent-facing fields. `reviewOnly` (if a file carried it) is never read.
  factory CareGuide.fromJson(Map<String, Object?> m) {
    const String w = 'guide';
    if (_need<int>(m, 'schemaVersion', w) != 1) throw CareGuideFormatException('unsupported schemaVersion');
    final List<Object?> blocks = _list(m['blocks'], '$w.blocks');
    final List<Object?> bands = _list(m['ageBands'], '$w.ageBands');
    final List<Object?> helps = _list(m['helplines'], '$w.helplines');
    final List<Object?> srcs = _list(m['sources'], '$w.sources');
    final List<Object?> notes = m['notes'] == null ? const <Object?>[] : _list(m['notes'], '$w.notes');
    final Object? first = m['emergencyFirstLine'];
    CareItem? firstLine;
    if (first != null) {
      final Map<String, Object?> fm = _map(first, '$w.emergencyFirstLine');
      firstLine = CareItem(
        text: _need<String>(fm, 'text', '$w.emergencyFirstLine'),
        sources: _ints(fm['sources'] ?? const <Object?>[], '$w.emergencyFirstLine.sources'),
      );
    }
    final String id = _need<String>(m, 'id', w);
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(id)) throw CareGuideFormatException('bad guide id');
    return CareGuide(
      id: id,
      title: _need<String>(m, 'title', w),
      category: _need<String>(m, 'category', w),
      region: _need<String>(m, 'region', w),
      status: _need<String>(m, 'status', w),
      revision: _need<int>(m, 'revision', w),
      lastResearched: _need<String>(m, 'lastResearched', w),
      lastRevised: _opt<String>(m, 'lastRevised', w),
      disclaimer: _opt<String>(m, 'disclaimer', w),
      review: GuideReview.fromJson(m['review']),
      notes: <GuideNote>[
        for (final Object? n in notes)
          GuideNote(kind: _need<String>(_map(n, '$w.notes'), 'kind', '$w.notes'), text: _need<String>(_map(n, '$w.notes'), 'text', '$w.notes')),
      ],
      emergencyFirstLine: firstLine,
      blocks: <CareBlock>[for (int i = 0; i < blocks.length; i++) CareBlock.fromJson(blocks[i], '$w.blocks[$i]')],
      ageBands: <AgeBand>[for (int i = 0; i < bands.length; i++) AgeBand.fromJson(bands[i], '$w.ageBands[$i]')],
      helplines: <Helpline>[for (int i = 0; i < helps.length; i++) Helpline.fromJson(helps[i], '$w.helplines[$i]')],
      sources: <GuideSource>[for (final Object? s in srcs) GuideSource.fromJson(s)],
    );
  }

  final String id;
  final String title;
  final String category;
  final String region;
  final String status;
  final int revision;
  final String lastResearched;
  final String? lastRevised;
  final String? disclaimer;
  final GuideReview review;
  final List<GuideNote> notes;
  final CareItem? emergencyFirstLine;
  final List<CareBlock> blocks;
  final List<AgeBand> ageBands;
  final List<Helpline> helplines;
  final List<GuideSource> sources;

  bool get isReviewed => status == kStatusReviewed;

  /// True for a guide that can be read in an emergency (category emergency, or it has an emergency block). Screens add
  /// no app-written advice to such a guide: any extra sentence could delay a call for help.
  bool get isEmergencyTier => category == 'emergency' || blocks.any((CareBlock b) => b.kind == 'emergency');

  /// Blocks in display order: emergency first, then the fixed order of [kBlockOrder]. Stable inside a kind.
  List<CareBlock> get orderedBlocks {
    final List<CareBlock> out = List<CareBlock>.of(blocks);
    final Map<CareBlock, int> idx = <CareBlock, int>{for (int i = 0; i < out.length; i++) out[i]: i};
    out.sort((CareBlock a, CareBlock b) {
      final int c = kBlockOrder.indexOf(a.kind).compareTo(kBlockOrder.indexOf(b.kind));
      return c != 0 ? c : (idx[a]!).compareTo(idx[b]!);
    });
    return out;
  }

  /// The most recent source retrieval date (ISO strings sort), shown beside "last reviewed".
  String? get latestRetrieved {
    String? best;
    for (final GuideSource s in sources) {
      if (best == null || s.retrieved.compareTo(best) > 0) best = s.retrieved;
    }
    return best;
  }

  GuideSource? sourceById(int id) {
    for (final GuideSource s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }
}
