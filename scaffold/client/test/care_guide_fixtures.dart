// Test helpers for the care guide suites: a synthetic guide builder and an in-memory asset bundle.
// Synthetic text only: no real medical content is written here.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:olive_client/care_guide_models.dart';

Map<String, Object?> fixtureGuide({
  String id = 'sample-guide',
  String status = 'REVIEWED',
  String region = 'XX',
  String? reviewedOn = '2030-01-02',
  String? reviewedBy = 'test reviewer role',
  List<String>? regions,
  String extraText = '',
  List<Map<String, Object?>>? helplines,
  String category = 'general',
  bool withEmergencyBlock = true,
}) =>
    <String, Object?>{
      'schemaVersion': 1,
      'id': id,
      'title': 'Sample guide $id',
      'category': category,
      'region': region,
      'status': status,
      'revision': 1,
      'lastResearched': '2030-01-01',
      'review': <String, Object?>{'reviewedOn': reviewedOn, 'reviewedBy': reviewedBy, 'regions': regions ?? <String>[region]},
      'notes': <Object?>[],
      'blocks': <Object?>[
        <String, Object?>{
          'kind': 'doNow',
          'items': <Object?>[
            <String, Object?>{'text': 'Sample step one$extraText', 'n': 1, 'sources': <int>[1]},
          ],
        },
        if (withEmergencyBlock)
          <String, Object?>{
            'kind': 'emergency',
            'items': <Object?>[
              <String, Object?>{'text': 'Sample emergency sign', 'sources': <int>[1]},
            ],
          },
      ],
      'ageBands': <Object?>[
        <String, Object?>{'key': 'a-band', 'text': 'Sample band text'},
        <String, Object?>{'key': 'b-band', 'label': 'Second band', 'text': 'Other band text'},
      ],
      'helplines': helplines ??
          <Map<String, Object?>>[
            <String, Object?>{'region': region, 'name': 'Sample line', 'number': '555-0100', 'sources': <int>[1]},
          ],
      'sources': <Object?>[
        <String, Object?>{'id': 1, 'org': 'Sample Org', 'title': 'Sample page', 'url': 'https://example.org/p', 'retrieved': '2030-01-01'},
      ],
    };

CareGuide fixtureCareGuide({
  String id = 'sample-guide',
  String status = 'REVIEWED',
  List<Map<String, Object?>>? helplines,
  List<String>? regions,
  String category = 'general',
  bool withEmergencyBlock = true,
}) =>
    CareGuide.fromJson(fixtureGuide(
        id: id, status: status, helplines: helplines, regions: regions, category: category, withEmergencyBlock: withEmergencyBlock));

/// An in-memory bundle. A missing key throws, like a missing asset.
class MapBundle extends CachingAssetBundle {
  MapBundle(Map<String, String> files) : _files = files;
  final Map<String, String> _files;
  @override
  Future<ByteData> load(String key) async {
    final String? s = _files[key];
    if (s == null) throw FlutterError('Unable to load asset: $key');
    final Uint8List b = Uint8List.fromList(utf8.encode(s));
    return ByteData.view(b.buffer);
  }
}

MapBundle bundleOf(List<Map<String, Object?>> guides) => MapBundle(<String, String>{
      'assets/care_guides/index.json': jsonEncode(<String, Object?>{'schemaVersion': 1, 'guides': <Object?>[for (final Map<String, Object?> g in guides) g['id']]}),
      for (final Map<String, Object?> g in guides) 'assets/care_guides/${g['id']}.json': jsonEncode(g),
    });

/// Where the app-format drafts live. They are NOT bundled (see assets/care_guides/index.json): tests read them from disk.
const String kDraftDir = '../../docs/care-guides/app-draft';

/// The five real drafts, in an in-memory bundle laid out like the real asset directory.
MapBundle realDraftBundle() {
  final List<String> ids = <String>['who-to-call', 'choking', 'head-injury', 'high-fever', 'childproofing-home'];
  return MapBundle(<String, String>{
    'assets/care_guides/index.json': jsonEncode(<String, Object?>{'schemaVersion': 1, 'guides': ids}),
    for (final String id in ids) 'assets/care_guides/$id.json': File('$kDraftDir/$id.json').readAsStringSync(),
  });
}
