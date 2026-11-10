import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/graph.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/route.dart';
import 'package:latlong2/latlong.dart';

import 'helpers.dart';

final a = m(0, 0), b = m(100, 0), c = m(50, 150);

/// 동쪽으로 10% 오르막.
double slope(LatLng p) => xy(p).x * 0.1;

/// 40~60m 구간에서만 5m 오르는 턱 (25%).
double step(LatLng p) => (xy(p).x.clamp(40, 60) - 40) / 20 * 5;

/// 곧은 길 100m 하나.
Graph line(List<SurveyRecord> r, double Function(LatLng) h) =>
    buildGraph([a, b], [(0, 1)], r, h);

/// 곧은 길 100m와, c를 거쳐 돌아가는 길 316m.
Graph tri(List<SurveyRecord> r, double Function(LatLng) h) =>
    buildGraph([a, b, c], [(0, 1), (0, 2), (2, 1)], r, h);

bool via(RouteResult r, LatLng p) => r.legs.any((l) => meters(l.a, p) < 0.5);

final stairs = rec(Kind.stairs, m(40, 0), m(60, 0));

void main() {
  // ── 설계서 6절 "반드시 통과해야 하는 확인 항목" 1~8 ──

  test('1 가장 짧은 길에 계단이 있으면 돌아가는 길을 준다', () {
    final r = findRoute(tri([stairs], flat), a, b, Profile.manual)!;
    expect(via(r, c), isTrue);
    expect(r.meters, closeTo(316.2, 1));
  });

  test('2 조금 더 긴 완만한 길이 있으면 가파른 길 대신 그 길을 준다', () {
    final r = findRoute(tri([], slope), a, b, Profile.manual)!;
    expect(via(r, c), isTrue);
    expect(r.steepSections, isEmpty);
  });

  test('3 가파른 길밖에 없으면 그 길을 주고 경고 정보를 함께 준다', () {
    final r = findRoute(line([], slope), a, b, Profile.manual)!;
    expect(r.steepSections.length, 1);
    expect(r.steepMeters, closeTo(100, 0.5));
    expect(r.maxSteepGrade, closeTo(0.10, 0.005));
  });

  test('4 엘리베이터 연결이 있으면 그것으로 높이 차를 넘는다', () {
    final r = findRoute(
      line([rec(Kind.elevator, m(40, 5), m(60, 5))], step),
      a,
      b,
      Profile.manual,
    )!;
    expect(r.elevators, 1);
    expect(r.steepSections, isEmpty);
  });

  test('5 계단 없이는 갈 수 없으면 찾지 못함을 돌려준다', () {
    expect(findRoute(line([stairs], flat), a, b, Profile.manual), isNull);
  });

  test('6 수동과 전동에서 가파름 판정이 달라진다', () {
    expect(
      findRoute(line([], slope), a, b, Profile.manual)!.steepSections.length,
      1,
    );
    expect(
      findRoute(line([], slope), a, b, Profile.powered)!.steepSections,
      isEmpty,
    );
  });

  test('7 조사 기록의 계단이 있는 구간은 경로에서 빠진다', () {
    final r = findRoute(tri([stairs], flat), a, b, Profile.manual)!;
    expect(r.legs.any((l) => l.kind == Kind.stairs), isFalse);
    expect(
      r.legs.any(
        (l) =>
            xy(l.a).y.abs() < 1 &&
            xy(l.b).y.abs() < 1 &&
            xy(l.a).x > 39 &&
            xy(l.a).x < 61,
      ),
      isFalse,
    );
  });

  test('8 조사 기록의 새 길은 경로에 쓰인다', () {
    final g = buildGraph([a, m(0, -30), b, m(100, -30)], [(0, 1), (2, 3)], [
      rec(Kind.newPath, a, b),
    ], flat);
    final r = findRoute(g, a, b, Profile.manual)!;
    expect(r.legs.every((l) => l.kind == Kind.newPath), isTrue);
    expect(r.meters, closeTo(100, 0.5));
  });

  // ── 그 밖의 규칙 ──

  test('조사자가 표시한 급경사는 전동에도 가파르고, 계산 기울기가 낮으면 숫자를 주지 않는다', () {
    final r = findRoute(
      line([rec(Kind.steep, m(40, 0), m(60, 0))], flat),
      a,
      b,
      Profile.powered,
    )!;
    expect(r.steepSections.length, 1);
    expect(r.steepMeters, closeTo(20, 0.5));
    expect(r.maxSteepGrade, isNull);
  });

  test('경사로는 한 곳으로 세고 가파른 길로 보지 않는다', () {
    final r = findRoute(
      line([rec(Kind.ramp, a, b)], slope),
      a,
      b,
      Profile.manual,
    )!;
    expect(r.ramps, 1);
    expect(r.steepSections, isEmpty);
  });

  test('예상 시간은 수동 3km/h, 전동 4km/h', () {
    final far = m(1000, 0);
    final g = buildGraph([a, far], [(0, 1)], [], flat);
    expect(findRoute(g, a, far, Profile.manual)!.minutes, 20);
    expect(findRoute(g, a, far, Profile.powered)!.minutes, 15);
  });

  // Review Focus 5
  test('출발지와 목적지가 같으면 0m, 길이 없으면 찾지 못함', () {
    final r = findRoute(line([], flat), a, a, Profile.manual)!;
    expect(r.meters, 0);
    expect(r.minutes, 0);
    expect(
      findRoute(buildGraph([], [], [], flat), a, b, Profile.manual),
      isNull,
    );
  });

  test('내장 자료에서 정문 → 중앙도서관 길이 나온다', () {
    final campus = Campus.fromJson(
      jsonDecode(File('assets/campus.json').readAsStringSync()),
    );
    final gate = campus.places.firstWhere((p) => p.name == '정문').at;
    final lib = campus.places.firstWhere((p) => p.name == '중앙도서관').at;
    final g = buildGraph(campus.nodes, campus.edges, [], campus.elevationAt);
    for (final p in Profile.values) {
      final r = findRoute(g, gate, lib, p)!;
      printOnFailure(
        '${p.label}: ${r.meters.round()}m, 가파른 구간 ${r.steepSections.length}',
      );
      expect(r.meters, inInclusiveRange(750, 3000)); // 직선 약 750m
    }
  });
}
