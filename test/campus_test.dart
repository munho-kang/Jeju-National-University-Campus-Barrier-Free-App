import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:latlong2/latlong.dart';

Map<String, dynamic> grid(int rows, int cols, List<num> data) => {
  'bounds': [33.0, 126.0, 33.1, 126.1],
  'places': [],
  'nodes': [],
  'edges': [],
  'elev': {
    'south': 33.0,
    'west': 126.0,
    'step': 0.001,
    'rows': rows,
    'cols': cols,
    'data': data,
  },
};

void main() {
  test('elevationAt은 격자 사이를 고르게 잇고 밖에서는 가장자리 값', () {
    final c = Campus.fromJson(grid(2, 2, [0, 10, 20, 30]), passes: 0);
    expect(c.elevationAt(const LatLng(33.0, 126.0)), closeTo(0, 1e-6));
    expect(c.elevationAt(const LatLng(33.0005, 126.0005)), closeTo(15, 1e-6));
    expect(c.elevationAt(const LatLng(34, 127)), closeTo(30, 1e-6));
  });

  test('smooth는 이웃 평균', () {
    final s = smooth([0, 0, 0, 0, 9, 0, 0, 0, 0], 3, 3);
    expect(s[4], closeTo(1, 1e-9)); // 가운데: 9칸 평균
    expect(s[0], closeTo(2.25, 1e-9)); // 모서리: 4칸 평균
  });

  test('내장 자료가 설계서와 맞는다', () {
    final c = Campus.fromJson(
      jsonDecode(File('assets/campus.json').readAsStringSync()),
    );
    final gate = c.places.firstWhere((p) => p.name == '정문');
    final lib = c.places.firstWhere((p) => p.name == '중앙도서관');
    expect(c.places.length, inInclusiveRange(40, 70)); // 설계서: 약 60곳
    expect(c.places.every((p) => c.contains(p.at)), isTrue);
    expect(c.places.map((p) => p.name), isNot(contains('카카오본사 다음스페이스닷원')));
    expect(c.edges.length, greaterThan(150));
    expect(
      c.edges.every((e) => e.$1 < c.nodes.length && e.$2 < c.nodes.length),
      isTrue,
    );
    // 설계서: 정문에서 중앙도서관까지 약 56m 오른다
    expect(
      c.elevationAt(lib.at) - c.elevationAt(gate.at),
      inInclusiveRange(35, 75),
    );
  });

  // 조사 결과를 assets/survey.json에 넣다가 형식을 깨뜨리면 앱이 켜지지 않는다.
  test('내장 조사 기록을 읽을 수 있다', () {
    decodeRecords(File('assets/survey.json').readAsStringSync());
  });

  test('20 내장 건물 테두리가 올바른 형식이다', () {
    final c = Campus.fromJson(
      jsonDecode(File('assets/campus.json').readAsStringSync()),
    );
    final b = decodeBuildings(File('assets/buildings.json').readAsStringSync());
    expect(b.length, greaterThan(50)); // 이름 있는 건물만 58곳이다
    expect(b.every((ring) => ring.length >= 3), isTrue);
    expect(b.every((ring) => ring.any(c.contains)), isTrue); // 캠퍼스 상자에 걸친 건물만
  });
  test('건물 테두리 형식이 틀리면 FormatException', () {
    expect(() => decodeBuildings('[[33.1,126.1,33.2]]'), throwsFormatException);
    expect(
      () => decodeBuildings('[[33.1,126.1,33.2,126.2]]'),
      throwsFormatException,
    );
    expect(() => decodeBuildings('{}'), throwsFormatException);
  });
}
