import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:jnu_wheel_nav/graph.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/route.dart';
import 'package:jnu_wheel_nav/voice.dart';
import 'package:latlong2/latlong.dart';

/// 원점(33.4555, 126.5625)에서 동쪽 x m, 북쪽 y m인 점. `xy`의 반대.
LatLng m(double x, double y) => LatLng(
  33.4555 + y / 110574,
  126.5625 + x / (111320 * cos(33.4555 * pi / 180)),
);

SurveyRecord rec(Kind k, LatLng a, LatLng b) =>
    SurveyRecord(k, a, b, DateTime.utc(2026, 11, 12));

double flat(LatLng _) => 0;

/// 점들과 이음선으로 길을 만들고 from → to 경로를 찾는다.
(Graph, RouteResult) net(
  List<LatLng> nodes,
  List<(int, int)> edges,
  LatLng from,
  LatLng to, {
  List<SurveyRecord> records = const [],
  double Function(LatLng) h = flat,
  Profile p = Profile.manual,
}) {
  final g = buildGraph(nodes, edges, records, h);
  return (g, findRoute(g, from, to, p)!);
}

/// 점들을 차례로 이은 길을 처음부터 끝까지 가는 경로.
RouteResult walk(
  List<LatLng> pts, {
  List<SurveyRecord> records = const [],
  double Function(LatLng) h = flat,
  Profile p = Profile.manual,
}) => net(
  pts,
  [for (var i = 0; i + 1 < pts.length; i++) (i, i + 1)],
  pts.first,
  pts.last,
  records: records,
  h: h,
  p: p,
).$2;

/// 인터넷 없이 테스트하려고 지도 그림 대신 투명한 1×1 그림만 주는 공급자.
class BlankTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_blankPng);
}

final _blankPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// 아주 작은 가짜 캠퍼스: 아래 길(정문 쪽) 100m, 위 길(도서관 쪽) 100m,
/// [connected]이면 둘을 잇는 300m 길. 정문 → 도서관은 100 + 300 + 100 = 500m.
/// [spur]면 아래 길을 동쪽으로 100m 더 잇는다(점 `m(200, 0)`).
Campus tinyCampus({bool connected = true, bool spur = false}) {
  final pts = [m(0, 0), m(100, 0), m(0, 300), m(100, 300), if (spur) m(200, 0)];
  final sw = m(-200, -200), ne = m(300, 500);
  return Campus.fromJson({
    'bounds': [sw.latitude, sw.longitude, ne.latitude, ne.longitude],
    'places': [
      ['정문', pts[0].latitude, pts[0].longitude],
      ['도서관', pts[2].latitude, pts[2].longitude],
    ],
    'nodes': [
      for (final p in pts) [p.latitude, p.longitude],
    ],
    'edges': [
      [0, 1],
      [2, 3],
      if (connected) [1, 3],
      if (spur) [1, 4],
    ],
    'elev': {
      'south': 33.0,
      'west': 126.0,
      'step': 1.0,
      'rows': 2,
      'cols': 2,
      'data': [0, 0, 0, 0],
    },
  });
}

/// 말한 것을 모아 두기만 하는 목소리.
class FakeVoice implements Voice {
  final said = <String>[];
  var stops = 0;

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> stop() async => stops++;
}
