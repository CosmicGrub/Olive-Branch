// OLIVE BRANCH — the picture library for suites B and C: every picture has a
// name to speak and a drawing, and no name judges a feeling.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/picture_icons.dart';
import 'package:olive_client/picture_library.dart';

void main() {
  test('ids are unique and every picture has a spoken name', () {
    final List<String> ids = pictureLibrary.map((PictureDef p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final PictureDef p in pictureLibrary) {
      expect(p.label.trim(), isNotEmpty, reason: p.id);
      expect(pictureLabel(p.id), p.label);
    }
  });

  test('every library picture has its own drawing (no silent fallback)', () {
    for (final PictureDef p in pictureLibrary) {
      expect(pictureIconOrNull(p.id), isNotNull, reason: '${p.id} has no icon');
    }
    expect(pictureIconOrNull('nope'), isNull);
    expect(pictureIcon('nope'), isNotNull, reason: 'the widget falls back rather than crash');
  });

  test('lookups refuse anything that is not a library id', () {
    expect(pictureById('sunny')!.group, PictureGroup.weather);
    expect(pictureById('nope'), isNull);
    expect(pictureById(null), isNull);
    expect(pictureById(5), isNull);
    expect(pictureLabel('nope'), '');
    expect(isPictureIn('sunny', <PictureGroup>{PictureGroup.routine}), isFalse);
    expect(isPictureIn('bath', <PictureGroup>{PictureGroup.routine}), isTrue);
  });

  test('every group the features need is populated', () {
    for (final PictureGroup g in PictureGroup.values) {
      expect(picturesIn(g), isNotEmpty, reason: g.name);
    }
    expect(picturesIn(PictureGroup.weather).length, 6);
    expect(picturesIn(PictureGroup.symbolCore).length, 16);
  });

  test('weather and worry pictures name skies and things, never a feeling as good or bad', () {
    const List<String> verdicts = <String>[
      'good', 'bad', 'happy', 'sad', 'angry', 'mad', 'scared', 'naughty', 'wrong', 'best', 'worst', 'nice', 'horrible',
    ];
    for (final PictureDef p in <PictureDef>[...picturesIn(PictureGroup.weather), ...picturesIn(PictureGroup.worry)]) {
      final String l = p.label.toLowerCase();
      for (final String v in verdicts) {
        expect(RegExp('\\b$v\\b').hasMatch(l), isFalse, reason: '${p.id} "$l" judges with "$v"');
      }
    }
  });
}
