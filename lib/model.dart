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
const endpointSnapMeters = 5.0; // 누른 점이 다른 기록의 끝점에 정확히 붙는 거리
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
Point<double> xy(LatLng p) =>
    Point((p.longitude - _lng0) * _metersPerLng, (p.latitude - _lat0) * 110574);

double meters(LatLng a, LatLng b) => xy(a).distanceTo(xy(b));

class Place {
  const Place(this.name, this.at);
  final String name;
  final LatLng at;
}

/// 앱에 내장된 캠퍼스 자료: 장소, 길(점과 조각), 높이 격자.
class Campus {
  Campus._(
    this.places,
    this.nodes,
    this.edges,
    this.south,
    this.west,
    this.north,
    this.east,
    this._elevSouth,
    this._elevWest,
    this._step,
    this._rows,
    this._cols,
    this._elev,
  );

  /// 높이 자료(30m 간격)는 거칠어서 이웃 평균으로 [passes]번 다듬어 쓴다.
  factory Campus.fromJson(Map<String, dynamic> j, {int passes = smoothPasses}) {
    final e = j['elev'] as Map<String, dynamic>;
    final rows = e['rows'] as int, cols = e['cols'] as int;
    var elev = [for (final v in e['data'] as List) (v as num).toDouble()];
    for (var i = 0; i < passes; i++) {
      elev = smooth(elev, rows, cols);
    }
    final b = [for (final v in j['bounds'] as List) (v as num).toDouble()];
    return Campus._(
      [
        for (final p in j['places'] as List)
          Place(p[0] as String, _point([p[1], p[2]])),
      ],
      [for (final n in j['nodes'] as List) _point(n)],
      [for (final x in j['edges'] as List) (x[0] as int, x[1] as int)],
      b[0],
      b[1],
      b[2],
      b[3],
      (e['south'] as num).toDouble(),
      (e['west'] as num).toDouble(),
      (e['step'] as num).toDouble(),
      rows,
      cols,
      elev,
    );
  }

  final List<Place> places;
  final List<LatLng> nodes;
  final List<(int, int)> edges;

  /// 캠퍼스 경계를 감싸는 상자.
  final double south, west, north, east;

  final double _elevSouth, _elevWest, _step;
  final int _rows, _cols;
  final List<double> _elev; // 남쪽 줄부터, 줄 안에서는 서쪽부터

  /// 격자 네 점 사이를 고르게 이은 높이(m). 격자 밖은 가장자리 값.
  double elevationAt(LatLng p) {
    final r = ((p.latitude - _elevSouth) / _step).clamp(0.0, _rows - 1.0);
    final c = ((p.longitude - _elevWest) / _step).clamp(0.0, _cols - 1.0);
    final r0 = min(r.floor(), _rows - 2), c0 = min(c.floor(), _cols - 2);
    final fr = r - r0, fc = c - c0;
    double at(int row, int col) => _elev[row * _cols + col];
    final lower = at(r0, c0) * (1 - fc) + at(r0, c0 + 1) * fc;
    final upper = at(r0 + 1, c0) * (1 - fc) + at(r0 + 1, c0 + 1) * fc;
    return lower * (1 - fr) + upper * fr;
  }

  // ponytail: 경계 다각형이 아니라 바깥 상자로 판단. 캠퍼스 바로 옆도 "안"으로 본다.
  bool contains(LatLng p) =>
      p.latitude >= south &&
      p.latitude <= north &&
      p.longitude >= west &&
      p.longitude <= east;
}

/// 각 칸을 자기와 이웃(격자 안에 있는 것만, 최대 9칸)의 평균으로 바꾼다.
List<double> smooth(List<double> data, int rows, int cols) => [
  for (var r = 0; r < rows; r++)
    for (var c = 0; c < cols; c++)
      _mean([
        for (var dr = -1; dr <= 1; dr++)
          for (var dc = -1; dc <= 1; dc++)
            if (r + dr >= 0 && r + dr < rows && c + dc >= 0 && c + dc < cols)
              data[(r + dr) * cols + c + dc],
      ]),
];

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
