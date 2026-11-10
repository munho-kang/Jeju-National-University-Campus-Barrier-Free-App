import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'model.dart';

/// 길 조각 하나. 두 점([a], [b])을 잇는다.
class Edge {
  Edge(this.a, this.b, this.kind, this.meters, this.grade);
  final int a, b;
  Kind kind; // 계단·급경사 기록이 얹히면 바뀐다
  final double meters;
  final double grade; // 높이 차 ÷ 길이 (0.10 = 10%)
}

/// 계단·급경사 기록을 얹을 수 있는 조각인지.
/// 경사로와 엘리베이터는 조사자가 "갈 수 있다"고 확인한 것이라 덮지 않는다.
bool overlayable(Kind k) => k != Kind.ramp && k != Kind.elevator;

typedef Near = ({int edge, double t, LatLng point, double meters});

LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
  a.latitude + (b.latitude - a.latitude) * t,
  a.longitude + (b.longitude - a.longitude) * t,
);

/// 길 찾기에 쓰는 그물망: 점([nodes])과 조각([edges]).
class Graph {
  Graph(this.elevationAt);

  final double Function(LatLng) elevationAt;
  final List<LatLng> nodes = [];
  final List<Edge> edges = [];

  /// 길 위에 얹히지 못해 지도에만 표시되는 계단·급경사 기록.
  final Set<SurveyRecord> unapplied = {};

  /// 모든 조사 기록의 양 끝점. 새로 누른 점이 가까우면 정확히 여기에 붙는다.
  List<LatLng> _recordEnds = const [];

  Edge _piece(int a, int b, Kind kind) {
    final len = meters(nodes[a], nodes[b]);
    final grade = kind == Kind.elevator || len < 0.01
        ? 0.0
        : (elevationAt(nodes[a]) - elevationAt(nodes[b])).abs() / len;
    return Edge(a, b, kind, len, grade);
  }

  /// 긴 길은 [pieceMeters] 이하 조각으로 나눠 넣는다 (조각마다 기울기를 따로 보려고).
  void _addEdge(int a, int b, Kind kind) {
    if (a == b) return;
    final from = nodes[a], to = nodes[b];
    final n = kind == Kind.elevator
        ? 1
        : max(1, (meters(from, to) / pieceMeters).ceil());
    var prev = a;
    for (var i = 1; i <= n; i++) {
      var next = b;
      if (i < n) {
        nodes.add(_lerp(from, to, i / n));
        next = nodes.length - 1;
      }
      edges.add(_piece(prev, next, kind));
      prev = next;
    }
  }

  /// 점 q에서 조각 i에 내린 수선의 발 위치(t)와 거리.
  (double t, double meters) _project(Point<double> q, int i) {
    final e = edges[i];
    final a = xy(nodes[e.a]), d = xy(nodes[e.b]) - a;
    final len2 = d.x * d.x + d.y * d.y;
    var t = len2 == 0
        ? 0.0
        : (((q.x - a.x) * d.x + (q.y - a.y) * d.y) / len2).clamp(0.0, 1.0);
    // 엘리베이터는 양 끝(출입구)에만 붙을 수 있다.
    if (e.kind == Kind.elevator) t = t.roundToDouble();
    return (t, q.distanceTo(a + d * t));
  }

  /// [p]에서 가장 가까운 길 위의 점.
  Near? nearest(LatLng p, {bool Function(Edge)? where}) {
    final q = xy(p);
    var best = -1, bestT = 0.0, bestMeters = double.infinity;
    for (var i = 0; i < edges.length; i++) {
      if (where != null && !where(edges[i])) continue;
      final (t, dist) = _project(q, i);
      if (dist < bestMeters) (best, bestT, bestMeters) = (i, t, dist);
    }
    if (best < 0) return null;
    final e = edges[best];
    return (
      edge: best,
      t: bestT,
      point: _lerp(nodes[e.a], nodes[e.b], bestT),
      meters: bestMeters,
    );
  }

  /// [p]를 가까운 길([snapMeters] 이내) 위의 점으로 옮긴다. 없으면 그대로.
  /// 계단·급경사는 얹을 수 있는 길에만 붙는다.
  LatLng _snapToPath(LatLng p, Kind kind) {
    final n = nearest(
      p,
      where: kind == Kind.stairs || kind == Kind.steep
          ? (e) => overlayable(e.kind)
          : null,
    );
    return n != null && n.meters <= snapMeters ? n.point : p;
  }

  /// 조사 탭에서 누른 점을 붙인다. 끝점을 누를 때는 [from]에 시작점을 준다.
  LatLng snap(LatLng p, Kind kind, {LatLng? from}) {
    // 1) 다른 기록의 끝점이 아주 가까우면 정확히 그 점에 붙는다. 그래야 계단
    //    옆 경사로의 끝이 손가락 오차로 계단 구간 "안쪽"에 떨어지지 않는다.
    LatLng? end;
    var best = endpointSnapMeters;
    for (final e in _recordEnds) {
      final d = meters(p, e);
      if (d <= best && (from == null || meters(from, e) >= 1)) {
        (end, best) = (e, d);
      }
    }
    if (end != null) return end;
    // 2) 가까운 길에 붙는다.
    final onPath = _snapToPath(p, kind);
    // 길을 잇는 종류(새 길·경사로·엘리베이터)의 끝점이 시작점 쪽으로 되돌아가
    // 붙으면 선이 접혀 버린다(예: 찻길에서 8m 떨어진 출입구로 가는 경사로).
    // 그럴 때는 누른 자리를 그대로 쓴다.
    final marksPath = kind == Kind.stairs || kind == Kind.steep;
    if (from != null &&
        !marksPath &&
        meters(from, onPath) < meters(from, p) / 2) {
      return p;
    }
    return onPath;
  }

  /// 조각 [edge]의 t 위치에 있는 점 번호. 끝에서 0.5m 안이면 끝 점, 아니면 쪼갠다.
  int _splitAt(int edge, double t) {
    final e = edges[edge];
    final point = _lerp(nodes[e.a], nodes[e.b], t);
    if (meters(point, nodes[e.a]) < 0.5) return e.a;
    if (meters(point, nodes[e.b]) < 0.5) return e.b;
    nodes.add(point);
    final mid = nodes.length - 1;
    edges[edge] = _piece(e.a, mid, e.kind);
    edges.add(_piece(mid, e.b, e.kind));
    return mid;
  }

  /// [p]를 가장 가까운 길에 이은 점 번호. [maxMeters] 안에 길이 없으면 홀로 선 점.
  int attach(
    LatLng p, {
    double maxMeters = snapMeters,
    bool Function(Edge)? where,
  }) {
    final n = nearest(p, where: where);
    if (n == null || n.meters > maxMeters) {
      nodes.add(p);
      return nodes.length - 1;
    }
    return _splitAt(n.edge, n.t);
  }

  /// [p]에서 [overlayMeters] 안에 있는 모든 조각에 이은 점 번호들.
  Set<int> _attachAll(LatLng p, bool Function(Edge) where) {
    final q = xy(p);
    final count = edges.length; // 쪼개면서 뒤에 붙는 조각은 다시 보지 않는다
    return {
      for (var i = 0; i < count; i++)
        if (where(edges[i]))
          if (_project(q, i) case (final t, final dist)
              when dist <= overlayMeters)
            _splitAt(i, t),
    };
  }

  /// 계단·급경사 기록을 그 아래 길 구간에 얹는다 (구간 조각의 종류를 바꾼다).
  ///
  /// 양 끝점 가까이의 "모든" 길을 대상으로 한다. 같은 자리에 겹쳐 기록된 길을
  /// 하나만 막으면 나머지로 계단을 지나가게 되기 때문이다.
  void _overlay(SurveyRecord r) {
    // 이 기록이 이미 표시한 조각은 다시 찾지 않는다. (같은 종류로 이미 표시된
    // 조각은 지나갈 수 있어야 한다. 겹쳐 기록한 두 계단이 하나로 이어지도록.)
    final marked = <Edge>{};
    bool ok(Edge e) => overlayable(e.kind) && !marked.contains(e);
    var applied = false;
    // 기록할 때와 똑같이 가까운 길에 다시 붙여 본다. 계단을 먼저 기록하고 길을
    // 나중에 기록해도(또는 길을 지웠다 다시 기록해도) 결과가 같아야 한다.
    final starts = _attachAll(_snapToPath(r.a, r.kind), ok);
    final ends = _attachAll(_snapToPath(r.b, r.kind), ok);
    for (final ia in starts) {
      for (final ib in ends) {
        if (ia == ib) continue;
        // 두 점 사이를 길 따라 간 거리가 직선 거리와 비슷할 때만 "그 구간"으로 본다.
        final limit = overlayDetour * meters(nodes[ia], nodes[ib]) + 1;
        while (true) {
          final path = shortestPath(
            this,
            ia,
            ib,
            (e) => ok(e) ? e.meters : null,
            maxCost: limit,
          );
          if (path == null) break;
          for (final i in path) {
            edges[i].kind = r.kind;
            marked.add(edges[i]);
          }
          applied = true;
        }
      }
    }
    if (!applied) unapplied.add(r);
  }
}

/// 내장 길과 조사 기록으로 그물망을 만든다.
///
/// 순서가 중요하다: 길을 잇는 기록(새 길·경사로·엘리베이터)을 먼저 넣고,
/// 급경사를 얹고, 계단을 맨 마지막에 얹는다. 그래야 어떤 순서로 기록했든
/// 계단이 있는 구간은 반드시 막힌다.
Graph buildGraph(
  List<LatLng> nodes,
  List<(int, int)> edges,
  List<SurveyRecord> records,
  double Function(LatLng) elevationAt,
) {
  final g = Graph(elevationAt)
    ..nodes.addAll(nodes)
    .._recordEnds = [
      for (final r in records) ...[r.a, r.b],
    ];
  for (final (a, b) in edges) {
    g._addEdge(a, b, Kind.road);
  }
  for (final r in records) {
    if (r.kind == Kind.newPath ||
        r.kind == Kind.ramp ||
        r.kind == Kind.elevator) {
      g._addEdge(g.attach(r.a), g.attach(r.b), r.kind);
    }
  }
  for (final kind in [Kind.steep, Kind.stairs]) {
    for (final r in records.where((r) => r.kind == kind)) {
      g._overlay(r);
    }
  }
  return g;
}

/// 비용이 가장 적은 길(Dijkstra). 조각 번호를 [from]에서 [to] 순서로 돌려준다.
///
/// [cost]가 null을 주면 지나갈 수 없는 조각이다. 길이 없으면 null.
List<int>? shortestPath(
  Graph g,
  int from,
  int to,
  double? Function(Edge) cost, {
  double maxCost = double.infinity,
}) {
  if (from == to) return [];
  final n = g.nodes.length;
  final near = List.generate(n, (_) => <int>[]); // 점마다 닿아 있는 조각
  for (var i = 0; i < g.edges.length; i++) {
    near[g.edges[i].a].add(i);
    near[g.edges[i].b].add(i);
  }
  final dist = List.filled(n, double.infinity)..[from] = 0;
  final via = List.filled(n, -1); // 이 점에 올 때 지난 조각
  final done = List.filled(n, false);
  // ponytail: O(n²) Dijkstra. 점이 1만 개를 넘으면 힙(우선순위 큐)으로 교체.
  while (true) {
    var u = -1;
    for (var i = 0; i < n; i++) {
      if (done[i] || dist[i] == double.infinity || dist[i] > maxCost) continue;
      if (u < 0 || dist[i] < dist[u]) u = i;
    }
    if (u < 0) return null;
    if (u == to) break;
    done[u] = true;
    for (final i in near[u]) {
      final e = g.edges[i], c = cost(e);
      if (c == null) continue;
      final v = e.a == u ? e.b : e.a;
      if (dist[u] + c < dist[v]) {
        dist[v] = dist[u] + c;
        via[v] = i;
      }
    }
  }
  final path = <int>[];
  for (var v = to; v != from;) {
    final e = g.edges[via[v]];
    path.add(via[v]);
    v = e.a == v ? e.b : e.a;
  }
  return path.reversed.toList();
}
