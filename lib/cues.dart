import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'model.dart';
import 'route.dart';

enum CueKind { left, right, uturn, elevator, ramp, steep, arrive }

class Cue {
  const Cue(this.kind, this.at, [this.meters = 0]);
  final CueKind kind;
  final double at; // 경로 시작에서 이 지점까지의 거리(m)
  final double meters; // 가파른 구간의 길이(steep만)
}

/// a에서 b를 보는 방향. 북쪽 0, 시계 방향, 도.
double bearing(LatLng a, LatLng b) {
  final p = xy(a), q = xy(b);
  return atan2(q.x - p.x, q.y - p.y) * 180 / pi;
}

/// 방향 from에서 to로 꺾인 각. 왼쪽이 +, 범위 (-180, 180].
double leftTurn(double from, double to) {
  var d = (from - to) % 360; // 시계 방향이 +인 방향각이라 왼쪽은 from - to
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

CueKind? turnKind(double left) {
  if (left.abs() >= uturnDegrees) return CueKind.uturn;
  if (left.abs() < turnDegrees) return null;
  return left > 0 ? CueKind.left : CueKind.right;
}

List<Cue> cuesFor(RouteResult r) {
  final legs = r.legs, n = legs.length;
  final starts = <double>[0]; // starts[i] = 조각 i가 시작되는 곳까지의 거리
  for (final l in legs) {
    starts.add(starts.last + l.meters);
  }
  // turn[i] = 조각 i가 시작되는 점에서 꺾인 각(왼쪽 +). 0.5m 미만 조각의 방향은 믿지 않고,
  // 엘리베이터 조각의 양 끝은 0으로 둔다(지도의 엘리베이터 선은 실제로 지나는 길이 아니다).
  final turn = List.filled(n, 0.0);
  double? before;
  for (var i = 0; i < n; i++) {
    final l = legs[i];
    if (l.meters < 0.5) continue;
    final now = bearing(l.a, l.b);
    final elevator =
        l.kind == Kind.elevator || (i > 0 && legs[i - 1].kind == Kind.elevator);
    if (before != null && !elevator) turn[i] = leftTurn(before, now);
    before = now;
  }
  final cues = <Cue>[];
  final used = List.filled(n, false);
  for (var i = 1; i < n; i++) {
    if (used[i] || turn[i] == 0) continue;
    // i에서 cornerMeters 안에 있고 같은 쪽으로 꺾이는 점들을 한 모퉁이로 묶는다.
    final corner = [
      for (var j = i; j < n && starts[j] - starts[i] <= cornerMeters; j++)
        if (!used[j] && turn[j].sign == turn[i].sign) j,
    ];
    final kind = turnKind(corner.fold(0.0, (sum, j) => sum + turn[j]));
    if (kind == null) continue;
    for (final j in corner) {
      used[j] = true;
    }
    // 가장 크게 꺾이는 점을 모퉁이의 자리로 삼는다.
    final peak = corner.reduce((a, b) => turn[b].abs() > turn[a].abs() ? b : a);
    cues.add(Cue(kind, starts[peak]));
  }
  for (var i = 0; i < n; i++) {
    final l = legs[i], prev = i == 0 ? null : legs[i - 1];
    if (l.kind == Kind.elevator && prev?.kind != Kind.elevator) {
      cues.add(Cue(CueKind.elevator, starts[i]));
    }
    if (l.kind == Kind.ramp && prev?.kind != Kind.ramp) {
      cues.add(Cue(CueKind.ramp, starts[i]));
    }
    if (l.steep && prev?.steep != true) {
      var end = i;
      while (end < n && legs[end].steep) {
        end++;
      }
      cues.add(Cue(CueKind.steep, starts[i], starts[end] - starts[i]));
    }
  }
  // 거리 순서로. 같은 자리면 넣은 순서(꺾임 → 엘리베이터·경사로·가파른 구간)를 지킨다.
  final order = [for (var i = 0; i < cues.length; i++) i]
    ..sort((a, b) => cues[a].at != cues[b].at
        ? cues[a].at.compareTo(cues[b].at)
        : a.compareTo(b));
  return [for (final i in order) cues[i], Cue(CueKind.arrive, starts.last)];
}

const arrivedSpeech = '목적지에 도착했습니다. 안내를 마칩니다';

String cueTitle(Cue c, String destName) => switch (c.kind) {
  CueKind.left => '왼쪽',
  CueKind.right => '오른쪽',
  CueKind.uturn => '뒤로 돌기',
  CueKind.elevator => '엘리베이터 타기',
  CueKind.ramp => '경사로로 가기',
  CueKind.steep => '가파른 구간 ${c.meters.round()}m',
  CueKind.arrive => '$destName 도착',
};

String bannerText(Cue c, double metersTo, String destName) {
  final d = metersTo.round();
  return switch (c.kind) {
    CueKind.left => '${d}m 앞에서 왼쪽',
    CueKind.right => '${d}m 앞에서 오른쪽',
    CueKind.uturn => '${d}m 앞에서 뒤로 돌기',
    CueKind.elevator => '${d}m 앞에서 엘리베이터 타기',
    CueKind.ramp => '${d}m 앞에서 경사로로 가기',
    CueKind.steep => '${d}m 앞부터 가파른 구간 ${c.meters.round()}m',
    CueKind.arrive => '${d}m 앞 $destName 도착',
  };
}

String cueSpeech(Cue c, double metersTo) {
  final where = metersTo < 10 ? '바로 앞' : '${(metersTo / 10).round() * 10}미터 앞';
  final len = c.meters.round();
  return switch (c.kind) {
    CueKind.left => '$where에서 왼쪽입니다',
    CueKind.right => '$where에서 오른쪽입니다',
    CueKind.uturn => '$where에서 뒤로 도세요',
    CueKind.elevator => '$where에서 엘리베이터를 타세요',
    CueKind.ramp => '$where에서 경사로로 가세요',
    CueKind.steep => '$where부터 가파른 구간입니다. 약 $len미터. 도움이 필요할 수 있습니다',
    CueKind.arrive => arrivedSpeech,
  };
}
