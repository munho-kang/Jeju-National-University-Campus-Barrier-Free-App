import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_map/flutter_map.dart' show StrokePattern;
import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/graph.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/route.dart';
import 'package:jnu_wheel_nav/route_tab.dart';
import 'package:latlong2/latlong.dart';

import 'helpers.dart';

double slope(LatLng p) => xy(p).x * 0.1;

/// 곧은 길 100m를 끝에서 끝까지 간 결과.
RouteResult route(List<SurveyRecord> r, double Function(LatLng) h, Profile p) =>
    findRoute(
      buildGraph([m(0, 0), m(100, 0)], [(0, 1)], r, h),
      m(0, 0),
      m(100, 0),
      p,
    )!;

void main() {
  test('요약 문구', () {
    final r = route([], flat, Profile.manual);
    expect(summaryLine(r), '100m · 약 2분');
    expect(detailLine(r), '계단 없음 · 경사로 0곳 · 엘리베이터 0곳 이용');
    expect(warningLine(r), isNull);
  });

  test('경고 문구', () {
    expect(
      warningLine(route([], slope, Profile.manual)),
      '가파른 구간 1곳 (100m, 최대 기울기 10%)',
    );
    expect(
      warningLine(
        route([rec(Kind.steep, m(40, 0), m(60, 0))], flat, Profile.powered),
      ),
      '가파른 구간 1곳 (20m, 조사자가 급경사로 표시)',
    );
  });

  test('경로 선은 흰 밑선 위에 초록, 가파른 곳은 주황 끊긴 선', () {
    final r = route(
      [rec(Kind.steep, m(40, 0), m(60, 0))],
      flat,
      Profile.powered,
    );
    final lines = routeLines(r);
    expect(lines.first.color, Colors.white);
    expect(lines.first.strokeWidth, 12);
    expect(lines.first.points.first, r.legs.first.a);
    expect(lines.first.points.last, r.legs.last.b);
    final rest = lines.skip(1);
    expect(rest.every((l) => l.strokeWidth == 7), isTrue);
    expect(rest.map((l) => l.color).toSet(), {
      const Color(0xFF12A150),
      const Color(0xFFF59F00),
    });
    expect(
      rest
          .firstWhere((l) => l.color == const Color(0xFFF59F00))
          .pattern
          .segments,
      isNotNull,
    );
    expect(
      rest.firstWhere((l) => l.color == const Color(0xFF12A150)).pattern,
      const StrokePattern.solid(),
    );
  });
}
