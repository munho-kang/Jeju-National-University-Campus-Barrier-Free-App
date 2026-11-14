import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/cues.dart';
import 'package:jnu_wheel_nav/guidance.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:latlong2/latlong.dart';

import 'helpers.dart';

void main() {
  var clock = DateTime.utc(2026, 11, 14);
  late Guidance g;

  /// [sec]초 뒤에 (x, y)에서 위치가 들어온다. 진행 위치는 한 번에 50m까지만 따라가므로
  /// 테스트에서도 50m 안쪽으로 나눠 걷는다.
  List<String> at(double x, double y, {double acc = 5, int sec = 1}) {
    clock = clock.add(Duration(seconds: sec));
    return g.update(m(x, y), accuracy: acc, now: clock);
  }

  Guidance guide(
    List<LatLng> nodes,
    List<(int, int)> edges,
    LatLng to, {
    List<SurveyRecord> records = const [],
  }) {
    final (graph, route) = net(nodes, edges, nodes.first, to, records: records);
    return Guidance(graph, route, to);
  }

  /// ㄱ자 길: 동쪽 100m, 왼쪽으로 꺾어 북쪽 100m.
  Guidance corner() =>
      guide([m(0, 0), m(100, 0), m(100, 100)], [(0, 1), (1, 2)], m(100, 100));

  /// 동쪽 100m → 엘리베이터(북쪽 40m) → 동쪽 100m. 따로 떨어진 길 (−50,150)–(50,150)도 있다.
  Guidance lift() => guide(
    [m(0, 0), m(100, 0), m(100, 40), m(200, 40), m(-50, 150), m(50, 150)],
    [(0, 1), (2, 3), (4, 5)],
    m(200, 40),
    records: [rec(Kind.elevator, m(100, 0), m(100, 40))],
  );

  test('7 남은 거리가 줄고, 미리 알리는 거리에 들어설 때 딱 한 번 말한다', () {
    g = corner();
    expect(g.start(), ['안내를 시작합니다', '전체 200미터, 약 4분입니다']);
    expect(at(40, 8), isEmpty); // 길에서 8m 떨어진 위치
    expect(g.along, closeTo(40, 0.5));
    expect(meters(g.position, m(40, 0)), lessThan(0.5)); // 위치 표시는 경로 선 위
    expect(g.remainingMeters, closeTo(160, 0.5));
    expect(g.remainingMinutes, 4);
    expect(g.next.kind, CueKind.left);
    expect(g.metersTo(g.next), closeTo(60, 0.5));
    expect(g.afterNext?.kind, CueKind.arrive);
    expect(at(79, 0), isEmpty);
    expect(at(81, 0), ['20미터 앞에서 왼쪽입니다']);
    expect(at(85, 0), isEmpty);
    expect(at(100, 30), isEmpty);
    expect(g.next.kind, CueKind.arrive);
    expect(g.remainingMeters, closeTo(70, 0.5));
    expect(g.remainingMinutes, 2);
  });
  test('14 경로 끝 가까이 오면 도착을 알리고 안내가 끝난다', () {
    g = corner();
    at(45, 0);
    at(90, 0);
    at(100, 35);
    expect(at(100, 84), isEmpty); // 16m 남음
    expect(g.arrived, isFalse);
    expect(at(100, 86), [arrivedSpeech]); // 14m 남음
    expect(g.arrived, isTrue);
    expect(at(100, 90), isEmpty);
  });
  test('같은 자리의 안내 두 개는 한 번에 나온다', () {
    // Review Focus 1
    // 동쪽 100m → 왼쪽으로 꺾자마자 경사로 30m → 북쪽 100m
    g = guide(
      [m(0, 0), m(100, 0), m(100, 30), m(100, 130)],
      [(0, 1), (2, 3)],
      m(100, 130),
      records: [rec(Kind.ramp, m(100, 0), m(100, 30))],
    );
    at(45, 0);
    expect(at(81, 0), ['20미터 앞에서 왼쪽입니다', '20미터 앞에서 경사로로 가세요']);
  });
  test('가파른 구간은 시작점을 건너뛰어 들어서도 알린다', () {
    g = guide(
      [m(0, 0), m(200, 0)],
      [(0, 1)],
      m(200, 0),
      records: [rec(Kind.steep, m(100, 0), m(130, 0))],
    );
    expect(g.start().last, '가파른 구간이 1곳 있습니다');
    at(40, 0);
    expect(g.metersToSteep, closeTo(60, 0.5));
    expect(at(75, 0), isEmpty); // 25m 앞
    expect(at(120, 0), ['바로 앞부터 가파른 구간입니다. 약 30미터. 도움이 필요할 수 있습니다']);
    expect(g.metersToSteep, 0);
    at(150, 0);
    expect(g.metersToSteep, isNull);
  });
  test('지도 방향은 모퉁이에서 부드럽게 바뀐다', () {
    final t = corner().track;
    expect(t.heading(50), closeTo(90, 0.1)); // 동쪽
    expect(t.heading(100), closeTo(45, 0.1)); // 모퉁이 한가운데
    expect(t.heading(150), closeTo(0, 0.1)); // 북쪽
  });
  test('남은 시간에는 남은 엘리베이터 기다리는 시간이 들어간다', () {
    g = lift(); // 전체 240m: 길 200m(240초) + 엘리베이터 60초 = 5분
    at(45, 0);
    expect(g.remainingMinutes, 5); // 길 155m(186초) + 60초
    at(81, 0);
    at(100, 20); // 엘리베이터 위
    expect(g.along, closeTo(120, 0.5));
    expect(g.remainingMinutes, 3); // 길 100m(120초) + 60초
  });
}
