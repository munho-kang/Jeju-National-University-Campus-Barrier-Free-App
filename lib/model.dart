import 'dart:convert';
import 'dart:math';

import 'package:latlong2/latlong.dart';

// ── 조정 가능한 값 (설계서 6절). 현장과 맞지 않으면 여기만 고친다. ──
const steepManual = 0.08; // 수동 휠체어: 기울기가 이 값을 넘으면 가파른 길
const steepPowered = 0.12; // 전동 휠체어
const steepCostFactor = 10.0; // 가파른 조각은 길이의 몇 배로 칠지
const rampCostFactor = 0.9; // 경사로는 약간 우대
const elevatorCostMeters = 50.0; // 엘리베이터 한 번 = 평지 몇 m로 칠지
const elevatorSeconds = 60; // 엘리베이터 기다리는 시간
const speedManualKmh = 3.0;
const speedPoweredKmh = 4.0;
const snapMeters = 15.0; // 누른 점이 길에 붙는 거리
const overlayMeters = 3.0; // 계단·급경사 기록이 "길 위"라고 보는 거리
const overlayDetour = 1.5; // 계단·급경사 구간이 직선 거리의 몇 배까지 굽어도 되는지
const pieceMeters = 30.0; // 길을 나누는 조각의 최대 길이 (높이 자료 간격과 같다)
const smoothPasses = 1; // 높이 자료를 다듬는 횟수
const placeTapMeters = 60.0; // 지도에서 건물을 눌렀다고 보는 거리

enum Kind {
  road('길'),
  stairs('계단'),
  ramp('경사로'),
  elevator('엘리베이터'),
  newPath('새 길'),
  steep('급경사');

  const Kind(this.label);
  final String label;
}

/// 조사자가 고를 수 있는 종류 (화면에 보이는 순서).
const surveyKinds = [
  Kind.stairs,
  Kind.ramp,
  Kind.elevator,
  Kind.newPath,
  Kind.steep,
];

/// 조사 기록 한 건: 종류, 시작점, 끝점, 기록 시각.
class SurveyRecord {
  const SurveyRecord(this.kind, this.a, this.b, this.time);

  factory SurveyRecord.fromJson(Map<String, dynamic> j) => SurveyRecord(
    Kind.values.byName(j['kind'] as String),
    _point(j['a']),
    _point(j['b']),
    DateTime.parse(j['time'] as String),
  );

  final Kind kind;
  final LatLng a, b;
  final DateTime time;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'a': [a.latitude, a.longitude],
    'b': [b.latitude, b.longitude],
    'time': time.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is SurveyRecord &&
      other.kind == kind &&
      other.a == a &&
      other.b == b &&
      other.time.isAtSameMomentAs(time);

  @override
  int get hashCode => Object.hash(kind, a, b, time.microsecondsSinceEpoch);
}

LatLng _point(dynamic v) =>
    LatLng((v[0] as num).toDouble(), (v[1] as num).toDouble());

String encodeRecords(List<SurveyRecord> r) => jsonEncode(r);

/// 형식이 틀리면 어떤 경우든 [FormatException]을 던진다.
List<SurveyRecord> decodeRecords(String json) {
  try {
    return [
      for (final j in jsonDecode(json) as List)
        SurveyRecord.fromJson(j as Map<String, dynamic>),
    ];
  } catch (e) {
    throw FormatException('조사 기록 형식이 아닙니다: $e');
  }
}

// 캠퍼스가 작아서(약 2km) 지구를 평평하다고 보고 계산한다. 오차는 몇 cm 수준.
const _lat0 = 33.4555, _lng0 = 126.5625;
final _metersPerLng = 111320 * cos(_lat0 * pi / 180);

/// 캠퍼스 가운데를 원점으로 한 동쪽(x)·북쪽(y) 미터.
Point<double> xy(LatLng p) => Point(
  (p.longitude - _lng0) * _metersPerLng,
  (p.latitude - _lat0) * 110574,
);

double meters(LatLng a, LatLng b) => xy(a).distanceTo(xy(b));
