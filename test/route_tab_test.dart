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
}
