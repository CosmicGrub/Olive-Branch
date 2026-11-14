// LiveKit engine pure helpers (moved out of call_screen.dart unchanged).
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:olive_client/degradation_banner.dart';
import 'package:olive_client/livekit_call_provider.dart';

void main() {
  test('videoQualityFor maps the ladder in the same direction, never inverted', () {
    expect(videoQualityFor(Quality.q720), lk.VideoQuality.HIGH);
    expect(videoQualityFor(Quality.q360), lk.VideoQuality.MEDIUM);
    expect(videoQualityFor(Quality.q180), lk.VideoQuality.LOW);
  });
  test('conditionFor: only poor and lost are strained; unknown never blames', () {
    expect(conditionFor(lk.ConnectionQuality.poor), Condition.strained);
    expect(conditionFor(lk.ConnectionQuality.lost), Condition.strained);
    expect(conditionFor(lk.ConnectionQuality.good), Condition.good);
    expect(conditionFor(lk.ConnectionQuality.excellent), Condition.good);
    expect(conditionFor(lk.ConnectionQuality.unknown), Condition.good);
  });
}
