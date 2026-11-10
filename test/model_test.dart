import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/model.dart';

import 'helpers.dart';

void main() {
  test('기록은 JSON으로 갔다가 돌아와도 같다', () {
    final r = SurveyRecord(
      Kind.stairs,
      m(0, 0),
      m(10, 0),
      DateTime.utc(2026, 11, 12, 3, 4, 5),
    );
    expect(decodeRecords(encodeRecords([r])), [r]);
    expect(encodeRecords([r]), contains('"kind":"stairs"'));
    expect(encodeRecords([r]), contains('"time":"2026-11-12T03:04:05.000Z"'));
  });

  test(
    'meters는 평면 거리',
    () => expect(meters(m(0, 0), m(30, 40)), closeTo(50, 0.01)),
  );

  test('형식이 틀리면 FormatException', () {
    expect(() => decodeRecords('not json'), throwsFormatException);
    expect(() => decodeRecords('{"x":1}'), throwsFormatException);
    expect(
      () => decodeRecords('[{"kind":"lava","a":[1,2],"b":[1,2],"time":"x"}]'),
      throwsFormatException,
    );
  });
}
