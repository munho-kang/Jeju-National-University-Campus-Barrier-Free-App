import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'cues.dart';
import 'graph.dart';
import 'model.dart';
import 'route.dart';

/// 경로 위의 거리 계산. s는 경로 시작에서 잰 거리(m).
class Track {
  Track(this.route) {
    starts = [0];
    for (final l in route.legs) {
      starts.add(starts.last + l.meters);
    }
  }
  final RouteResult route;
  late final List<double>
  starts; // starts[i] = 조각 i가 시작되는 s, starts.last = 전체 길이

  double get meters => starts.last;

  /// s가 놓인 조각 번호. 경계에서는 뒤 조각, 끝에서는 마지막 조각.
  int legAt(double s) {
    var i = 0;
    while (i < route.legs.length - 1 && starts[i + 1] <= s) {
      i++;
    }
    return i;
  }

  LatLng pointAt(double s) {
    s = s.clamp(0.0, meters);
    final i = legAt(s), l = route.legs[i];
    final t = l.meters <= 0
        ? 0.0
        : ((s - starts[i]) / l.meters).clamp(0.0, 1.0);
    return LatLng(
      l.a.latitude + (l.b.latitude - l.a.latitude) * t,
      l.a.longitude + (l.b.longitude - l.a.longitude) * t,
    );
  }

  /// [from]~[to] 구간에서 p와 가장 가까운 경로 위의 점.
  ({double s, double meters, LatLng point}) nearest(
    LatLng p, {
    double from = 0,
    double to = double.infinity,
  }) {
    final q = xy(p);
    var best = (s: from.clamp(0.0, meters), meters: double.infinity, point: p);
    for (var i = 0; i < route.legs.length; i++) {
      final l = route.legs[i];
      final lo = max(from, starts[i]), hi = min(to, starts[i + 1]);
      if (lo > hi) continue;
      final a = xy(l.a), b = xy(l.b);
      final dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy;
      final t = len2 == 0
          ? 0.0
          : (((q.x - a.x) * dx + (q.y - a.y) * dy) / len2).clamp(0.0, 1.0);
      final s = (starts[i] + t * l.meters).clamp(lo, hi);
      final point = pointAt(s), d = apart(p, point);
      if (d < best.meters) best = (s: s, meters: d, point: point);
    }
    return best;
  }

  /// 지도의 위쪽으로 둘 방향.
  double heading(double s) {
    final a = pointAt(s - headingSpanMeters / 2);
    final b = pointAt(s + headingSpanMeters / 2);
    if (apart(a, b) >= 1) return bearing(a, b);
    final l = route.legs[legAt(s)];
    return bearing(l.a, l.b);
  }
}

/// Track 안에서는 meters가 전체 길이를 가리키므로 두 점 사이 거리는 이 이름으로 부른다.
double apart(LatLng a, LatLng b) => meters(a, b);

class Guidance {
  Guidance(this.graph, RouteResult route, this.destination)
    : track = Track(route),
      cues = cuesFor(route),
      position = route.legs.first.a;
  final Graph graph; // 다시 찾을 때 쓴다 (Task 3)
  final LatLng destination; // 다시 찾을 때의 목적지 (Task 3)
  Track track;
  List<Cue> cues;
  double along = 0;
  LatLng position;
  bool arrived = false;
  bool offRoute = false;
  int _said = 0; // cues[_said]부터 아직 말하지 않았다
  int _offCount = 0; // 연속으로 길 밖이었던 횟수
  DateTime? _lastReroute;
  bool _lostSaid = false; // 못 찾음 알림을 이미 했다

  RouteResult get route => track.route;

  int get _nextIndex {
    final i = cues.indexWhere((c) => c.at > along);
    return i < 0 ? cues.length - 1 : i;
  }

  Cue get next => cues[_nextIndex];
  Cue? get afterNext =>
      _nextIndex + 1 < cues.length ? cues[_nextIndex + 1] : null;

  double metersTo(Cue c) => max(0, c.at - along);

  double get remainingMeters => track.meters - along;

  int get remainingMinutes {
    final i = track.legAt(along), l = route.legs[i];
    final rest = Leg(
      position,
      l.b,
      l.kind,
      track.starts[i + 1] - along,
      l.grade,
      l.steep,
    );
    return RouteResult([
      rest,
      ...route.legs.skip(i + 1),
    ], route.profile).minutes;
  }

  double? get metersToSteep {
    for (final c in cues) {
      if (c.kind == CueKind.steep && along < c.at + c.meters) {
        return metersTo(c);
      }
    }
    return null;
  }

  double get heading => track.heading(along);

  List<String> start() => [
    '안내를 시작합니다',
    '전체 ${track.meters.round()}미터, 약 ${route.minutes}분입니다',
    if (route.steepSections.isNotEmpty)
      '가파른 구간이 ${route.steepSections.length}곳 있습니다',
    ..._announce(),
  ];

  List<String> update(LatLng p, {double accuracy = 0, required DateTime now}) {
    if (arrived) return [];
    final n = track.nearest(
      p,
      from: along - progressWindowMeters,
      to: along + progressWindowMeters,
    );
    if (n.meters <= offRouteMeters) {
      along = n.s;
      position = n.point;
      _offCount = 0;
      offRoute = false;
      _lostSaid = false;
    } else {
      final onLift = route.legs[track.legAt(along)].kind == Kind.elevator;
      if (accuracy > distrustMeters ||
          (onLift && n.meters <= elevatorTrustMeters)) {
        return _announce();
      }
      position = p;
      offRoute = true;
      _offCount++;
    }
    if (remainingMeters <= arriveMeters) {
      arrived = true;
      return [arrivedSpeech];
    }
    final last = _lastReroute;
    if (_offCount < offRouteCount ||
        (last != null && now.difference(last).inSeconds < rerouteSeconds)) {
      return _announce();
    }
    _lastReroute = now;
    final found = findRoute(graph, p, destination, route.profile);
    if (found == null) {
      if (_lostSaid) return _announce();
      _lostSaid = true;
      return ['길에서 벗어났습니다. 표시된 길로 돌아가 주세요', ..._announce()];
    }
    if (found.legs.isEmpty) {
      arrived = true;
      return [arrivedSpeech];
    }
    final start = track.nearest(found.legs.first.a);
    final same =
        found.legs.every(
          (l) =>
              track.nearest(l.a).meters <= 1 && track.nearest(l.b).meters <= 1,
        ) &&
        (found.meters - (track.meters - start.s)).abs() <= 2;
    if (same) {
      along = start.s;
      _offCount = 0;
      offRoute = false;
      return _announce();
    }
    final going = bearing(track.pointAt(along), p);
    final fresh = Track(found);
    final turn = turnKind(leftTurn(going, fresh.heading(0)));
    track = fresh;
    cues = cuesFor(found);
    along = 0;
    _said = 0;
    _offCount = 0;
    offRoute = false;
    position = found.legs.first.a;
    return [
      '경로를 다시 찾았습니다',
      if (turn == CueKind.uturn) '뒤로 돌아서 가세요',
      if (turn == CueKind.left) '왼쪽으로 가세요',
      if (turn == CueKind.right) '오른쪽으로 가세요',
      if (found.steepSections.isNotEmpty)
        '가파른 구간이 ${found.steepSections.length}곳 있습니다',
      ..._announce(),
    ];
  }

  /// 아직 말하지 않은 안내 중 알릴 때가 된 것의 문장. 한 번 꺼낸 것은 다시 꺼내지 않는다.
  List<String> _announce() {
    final out = <String>[];
    while (_said < cues.length - 1 &&
        cues[_said].at - along <= announceMeters) {
      final c = cues[_said++];
      if (c.at >= along) {
        out.add(cueSpeech(c, c.at - along));
      } else if (c.kind == CueKind.steep && along < c.at + c.meters) {
        out.add(cueSpeech(c, 0));
      }
    }
    return out;
  }
}
