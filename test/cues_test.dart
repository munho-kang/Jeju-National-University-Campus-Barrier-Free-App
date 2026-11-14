import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/cues.dart';
import 'package:jnu_wheel_nav/graph.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/route.dart';
import 'package:latlong2/latlong.dart';

import 'helpers.dart';

void main() {
  List<CueKind> kinds(RouteResult r) => [for (final c in cuesFor(r)) c.kind];
  double slope(LatLng p) => xy(p).x * 0.1; // 동쪽으로 10% 오르막

  test('1 ㄱ자로 꺾이면 왼쪽, 좌우를 뒤집으면 오른쪽', () {
    final c = cuesFor(walk([m(0, 0), m(100, 0), m(100, 100)]));
    expect([for (final x in c) x.kind], [CueKind.left, CueKind.arrive]);
    expect(c[0].at, closeTo(100, 0.5));
    expect(c[1].at, closeTo(200, 0.5));
    expect(kinds(walk([m(0, 0), m(100, 0), m(100, -100)])), [
      CueKind.right,
      CueKind.arrive,
    ]);
  });
  test('2 둥글게 그려진 모퉁이(3m마다 22.5°씩 네 번)는 꺾임 한 번', () {
    final pts = [m(0, 0), m(100, 0)];
    var x = 100.0, y = 0.0;
    for (final deg in [22.5, 45.0, 67.5]) {
      x += 3 * cos(deg * pi / 180);
      y += 3 * sin(deg * pi / 180);
      pts.add(m(x, y));
    }
    pts.add(m(x, y + 100));
    final c = cuesFor(walk(pts));
    expect([for (final x in c) x.kind], [CueKind.left, CueKind.arrive]);
    expect(c[0].at, closeTo(100, 10));
  });
  test('3 길게 완만히 굽는 길(20m마다 10°씩 아홉 번)에는 꺾임 안내가 없다', () {
    final pts = [m(0, 0)];
    var x = 0.0, y = 0.0;
    for (var k = 0; k <= 9; k++) {
      x += 20 * cos(k * 10 * pi / 180);
      y += 20 * sin(k * 10 * pi / 180);
      pts.add(m(x, y));
    }
    expect(kinds(walk(pts)), [CueKind.arrive]);
  });
  test('4 엘리베이터·경사로·가파른 구간이 순서대로 나오고 가파른 구간은 빠지지 않는다', () {
    final c = cuesFor(
      walk(
        [m(0, 0), m(400, 0)],
        records: [
          rec(Kind.steep, m(40, 0), m(60, 0)),
          rec(Kind.ramp, m(100, 0), m(130, 0)),
          rec(Kind.stairs, m(200, 0), m(220, 0)), // 계단을 엘리베이터로 넘는다
          rec(Kind.elevator, m(190, 0), m(230, 0)),
          rec(Kind.steep, m(300, 0), m(330, 0)),
        ],
      ),
    );
    expect(
      [for (final x in c) x.kind],
      [
        CueKind.steep,
        CueKind.ramp,
        CueKind.elevator,
        CueKind.steep,
        CueKind.arrive,
      ],
    );
    expect([for (final x in c) x.at.round()], [40, 100, 190, 300, 400]);
    expect([c[0].meters.round(), c[3].meters.round()], [20, 30]);
  });
  test('5 엘리베이터 조각의 양 끝에서는 왼쪽·오른쪽이 나오지 않는다', () {
    // 동쪽 100m → 엘리베이터(북쪽 40m) → 동쪽 100m. 선 모양으로는 왼쪽, 오른쪽으로 꺾인다.
    final (_, r) = net(
      [m(0, 0), m(100, 0), m(100, 40), m(200, 40)],
      [(0, 1), (2, 3)],
      m(0, 0),
      m(200, 40),
      records: [rec(Kind.elevator, m(100, 0), m(100, 40))],
    );
    expect(kinds(r), [CueKind.elevator, CueKind.arrive]);
  });
  test('6 수동과 전동에서 가파른 구간 안내가 달라진다', () {
    expect(kinds(walk([m(0, 0), m(100, 0)], h: slope)), [
      CueKind.steep,
      CueKind.arrive,
    ]);
    expect(kinds(walk([m(0, 0), m(100, 0)], h: slope, p: Profile.powered)), [
      CueKind.arrive,
    ]);
  });
  test('뒤로 돌기, 그리고 바로 이어지는 반대쪽 꺾임은 따로 나온다', () {
    expect(kinds(walk([m(0, 0), m(100, 0), m(100, 3), m(0, 3)])), [
      CueKind.uturn,
      CueKind.arrive,
    ]);
    expect(kinds(walk([m(0, 0), m(100, 0), m(100, 15), m(200, 15)])), [
      CueKind.left,
      CueKind.right,
      CueKind.arrive,
    ]);
  });
  test('문구', () {
    expect(bannerText(const Cue(CueKind.left, 0), 30, '중앙도서관'), '30m 앞에서 왼쪽');
    expect(
      bannerText(const Cue(CueKind.steep, 0, 60), 120, '중앙도서관'),
      '120m 앞부터 가파른 구간 60m',
    );
    expect(
      bannerText(const Cue(CueKind.arrive, 0), 80, '중앙도서관'),
      '80m 앞 중앙도서관 도착',
    );
    expect(cueTitle(const Cue(CueKind.elevator, 0), ''), '엘리베이터 타기');
    expect(cueSpeech(const Cue(CueKind.left, 0), 19), '20미터 앞에서 왼쪽입니다');
    expect(cueSpeech(const Cue(CueKind.right, 0), 4), '바로 앞에서 오른쪽입니다');
    expect(
      cueSpeech(const Cue(CueKind.steep, 0, 60), 20),
      '20미터 앞부터 가파른 구간입니다. 약 60미터. 도움이 필요할 수 있습니다',
    );
  });
  test('내장 자료: 정문 → 중앙도서관의 안내 목록이 경로와 맞는다', () {
    final campus = Campus.fromJson(
      jsonDecode(File('assets/campus.json').readAsStringSync()),
    );
    final records = decodeRecords(
      File('assets/survey.json').readAsStringSync(),
    );
    final g = buildGraph(
      campus.nodes,
      campus.edges,
      records,
      campus.elevationAt,
    );
    Place place(String n) => campus.places.firstWhere((p) => p.name == n);
    for (final p in Profile.values) {
      final r = findRoute(g, place('정문').at, place('중앙도서관').at, p)!;
      final c = cuesFor(r);
      int count(CueKind k) => c.where((x) => x.kind == k).length;
      expect(c.last.kind, CueKind.arrive);
      expect(count(CueKind.steep), r.steepSections.length);
      expect(count(CueKind.elevator), r.elevators);
      expect(count(CueKind.ramp), r.ramps);
      expect([for (final x in c) x.at], [for (final x in c) x.at]..sort());
    }
  });
  test('경로 맨 앞의 1m 조각 끝에서 꺾이는 것은 말하지 않고, 더 가서 꺾이는 것은 말한다', () {
    // 다시 찾은 길은 길 위에 붙인 점에서 시작해서 맨 앞 조각이 아주 짧을 수 있다.
    // 동쪽 1m → 왼쪽으로 꺾어 북쪽 100m → 오른쪽으로 꺾어 동쪽 100m
    final c = cuesFor(walk([m(0, 0), m(1, 0), m(1, 100), m(101, 100)]));
    expect([for (final x in c) x.kind], [CueKind.right, CueKind.arrive]);
    expect(c[0].at, closeTo(101, 0.5));
  });
}
