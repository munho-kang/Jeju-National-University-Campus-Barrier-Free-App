import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/graph.dart';
import 'package:jnu_wheel_nav/model.dart';

import 'helpers.dart';

/// 동서로 뻗은 100m 길 하나.
Graph line(List<SurveyRecord> r) =>
    buildGraph([m(0, 0), m(100, 0)], [(0, 1)], r, flat);

/// y=0 직선 위에서 가운데 x가 x0~x1 사이인 조각.
Iterable<Edge> between(Graph g, double x0, double x1) => g.edges.where((e) {
  final a = xy(g.nodes[e.a]), b = xy(g.nodes[e.b]), x = (a.x + b.x) / 2;
  return a.y.abs() < 1 && b.y.abs() < 1 && x > x0 && x < x1;
});

double? walk(Edge e) => e.kind == Kind.stairs ? null : e.meters;

List<int>? endToEnd(Graph g) =>
    shortestPath(g, g.attach(m(0, 0)), g.attach(m(100, 0)), walk);

void main() {
  test('긴 길은 30m 이하 조각으로 나뉜다', () {
    final g = line([]);
    expect(g.edges.length, 4);
    expect(g.edges.every((e) => e.meters <= pieceMeters + 0.01), isTrue);
  });

  test('누른 점은 15m 안의 길에 붙고 더 멀면 그대로다', () {
    final g = line([]);
    expect(meters(g.snap(m(50, 14), Kind.newPath), m(50, 0)), lessThan(0.01));
    expect(g.snap(m(50, 16), Kind.newPath), m(50, 16));
  });

  test('확인 항목 7: 길 위의 계단 기록은 그 구간만 막는다', () {
    final g = line([rec(Kind.stairs, m(40, 0), m(60, 0))]);
    expect(between(g, 40, 60), isNotEmpty);
    expect(between(g, 40, 60).every((e) => e.kind == Kind.stairs), isTrue);
    expect(
      between(
        g,
        0,
        40,
      ).followedBy(between(g, 60, 100)).every((e) => e.kind == Kind.road),
      isTrue,
    );
    expect(g.unapplied, isEmpty);
    expect(endToEnd(g), isNull);
  });

  test('길에서 떨어진 계단 기록은 표시만 한다', () {
    final s = rec(Kind.stairs, m(40, 20), m(60, 20));
    final g = line([s]);
    expect(g.edges.every((e) => e.kind == Kind.road), isTrue);
    expect(g.unapplied, {s});
  });

  // Review Focus 2
  test('겹쳐 기록된 길 위의 계단은 겹친 길을 모두 막는다', () {
    final g = line([
      rec(Kind.newPath, m(0, 0), m(100, 0)),
      rec(Kind.stairs, m(40, 0), m(60, 0)),
    ]);
    expect(endToEnd(g), isNull);
  });

  test('같은 두 점 사이에 두 번 기록된 짧은 길도 계단이 모두 막는다', () {
    final path = rec(Kind.newPath, m(0, 50), m(20, 50));
    final g = line([path, path, rec(Kind.stairs, m(5, 50), m(15, 50))]);
    expect(
      shortestPath(g, g.attach(m(0, 50)), g.attach(m(20, 50)), walk),
      isNull,
    );
  });

  // Review Focus 3
  test('계단 옆 경사로는 막히지 않는다', () {
    final g = line([
      rec(Kind.stairs, m(40, 0), m(60, 0)),
      rec(Kind.ramp, m(40, 0), m(60, 0)),
    ]);
    expect(endToEnd(g)!.map((i) => g.edges[i].kind), contains(Kind.ramp));
  });

  test('급경사 기록은 길 구간에 얹힌다', () {
    final g = line([rec(Kind.steep, m(40, 0), m(60, 0))]);
    expect(between(g, 40, 60), isNotEmpty);
    expect(between(g, 40, 60).every((e) => e.kind == Kind.steep), isTrue);
  });

  test('엘리베이터는 한 조각이고 양 끝에만 붙는다', () {
    final g = line([rec(Kind.elevator, m(50, 0), m(50, 100))]);
    final lift = g.edges.where((e) => e.kind == Kind.elevator);
    expect(lift.length, 1);
    expect(lift.single.grade, 0);
    // 가운데(2m 거리)가 아니라 위쪽 끝(40m 거리)에 붙는다
    expect(g.nearest(m(52, 60))!.meters, closeTo(40.05, 0.1));
  });

  test('기울기는 높이 차 ÷ 길이', () {
    final g = buildGraph(
      [m(0, 0), m(100, 0)],
      [(0, 1)],
      [],
      (p) => xy(p).x * 0.1,
    );
    expect(g.edges.every((e) => (e.grade - 0.10).abs() < 0.001), isTrue);
  });
}
