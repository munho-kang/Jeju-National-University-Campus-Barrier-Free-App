import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'graph.dart';
import 'model.dart';

/// 휠체어 종류. 가파름 기준과 속도가 다르다.
enum Profile {
  manual('수동 휠체어', steepManual, speedManualKmh),
  powered('전동 휠체어', steepPowered, speedPoweredKmh);

  const Profile(this.label, this.steepGrade, this.kmh);
  final String label;
  final double steepGrade, kmh;
}

/// 이 휠체어에게 가파른 조각인지.
/// 조사자가 표시한 급경사는 항상 가파르고, 경사로·엘리베이터는 가파르지 않다.
bool isSteep(Edge e, Profile p) =>
    e.kind == Kind.steep ||
    ((e.kind == Kind.road || e.kind == Kind.newPath) && e.grade > p.steepGrade);

/// 조각을 지나는 비용(평지 몇 m에 해당하는지). 지나갈 수 없으면 null.
double? cost(Edge e, Profile p) => switch (e.kind) {
  Kind.stairs => null,
  Kind.elevator => elevatorCostMeters,
  Kind.ramp => e.meters * rampCostFactor,
  _ => isSteep(e, p) ? e.meters * steepCostFactor : e.meters,
};

/// 경로의 한 조각. 가는 방향이 [a] → [b].
class Leg {
  const Leg(this.a, this.b, this.kind, this.meters, this.grade, this.steep);
  final LatLng a, b;
  final Kind kind;
  final double meters, grade;
  final bool steep;
}

class RouteResult {
  const RouteResult(this.legs, this.profile);
  final List<Leg> legs;
  final Profile profile;

  double get meters => _sum(legs);

  int get minutes {
    final moving = _sum(legs.where((l) => l.kind != Kind.elevator));
    final seconds = moving * 3.6 / profile.kmh + elevators * elevatorSeconds;
    // 초 단위로 한 번 반올림해 두어야 20분이 계산 오차로 21분이 되지 않는다.
    return (seconds.round() / 60).ceil();
  }

  /// 이용한 경사로·엘리베이터 수 (이어진 조각은 한 곳으로 센다).
  int get ramps => _runs((l) => l.kind == Kind.ramp).length;
  int get elevators => _runs((l) => l.kind == Kind.elevator).length;

  /// 가파른 구간들 (이어진 가파른 조각 묶음).
  List<List<Leg>> get steepSections => _runs((l) => l.steep);

  double get steepMeters => _sum(legs.where((l) => l.steep));

  /// 가파른 조각들의 계산 기울기 중 가장 큰 값.
  /// 기준 이하이면 null: 높이 자료로는 완만한데 조사자가 급경사로 표시한 경우다.
  double? get maxSteepGrade {
    final g = legs.where((l) => l.steep).fold(0.0, (v, l) => max(v, l.grade));
    return g > profile.steepGrade ? g : null;
  }

  List<List<Leg>> _runs(bool Function(Leg) test) {
    final runs = <List<Leg>>[];
    var inRun = false;
    for (final l in legs) {
      if (test(l)) {
        inRun ? runs.last.add(l) : runs.add([l]);
      }
      inRun = test(l);
    }
    return runs;
  }
}

double _sum(Iterable<Leg> legs) => legs.fold(0, (s, l) => s + l.meters);

/// [from]에서 [to]까지 비용이 가장 적은 길. 갈 수 있는 길이 없으면 null.
///
/// 출발·도착 점은 가장 가까운 "지나갈 수 있는" 길 위의 점으로 잡는다.
RouteResult? findRoute(Graph g, LatLng from, LatLng to, Profile p) {
  bool passable(Edge e) => e.kind != Kind.stairs;
  final start = g.attach(from, maxMeters: double.infinity, where: passable);
  final end = g.attach(to, maxMeters: double.infinity, where: passable);
  final path = shortestPath(g, start, end, (e) => cost(e, p));
  if (path == null) return null;
  final legs = <Leg>[];
  var at = start;
  for (final i in path) {
    final e = g.edges[i];
    final next = e.a == at ? e.b : e.a;
    legs.add(
      Leg(g.nodes[at], g.nodes[next], e.kind, e.meters, e.grade, isSteep(e, p)),
    );
    at = next;
  }
  return RouteResult(legs, p);
}
