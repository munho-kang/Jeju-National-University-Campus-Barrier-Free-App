import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'graph.dart';
import 'model.dart';

/// 종류별 그림. 색만으로 구분하지 않도록 선 모양과 아이콘을 함께 쓴다.
({Color color, IconData icon, StrokePattern pattern}) kindStyle(Kind k) =>
    switch (k) {
      Kind.stairs => (
        color: const Color(0xFFC0392B),
        icon: Icons.stairs,
        pattern: const StrokePattern.dotted(),
      ),
      Kind.ramp => (
        color: const Color(0xFF1A8F3C),
        icon: Icons.accessible_forward,
        pattern: const StrokePattern.solid(),
      ),
      Kind.elevator => (
        color: const Color(0xFF2A7DE1),
        icon: Icons.elevator,
        pattern: const StrokePattern.solid(),
      ),
      Kind.newPath || Kind.road => (
        color: const Color(0xFF7B3FB5),
        icon: Icons.add_road,
        pattern: const StrokePattern.solid(),
      ),
      Kind.steep => (
        color: const Color(0xFFE08A00),
        icon: Icons.warning_amber,
        pattern: StrokePattern.dashed(segments: const [14, 8]),
      ),
    };

List<Polyline> recordLines(Iterable<SurveyRecord> records) => [
  for (final r in records)
    Polyline(
      points: [r.a, r.b],
      strokeWidth: 5,
      color: kindStyle(r.kind).color,
      pattern: kindStyle(r.kind).pattern,
    ),
];

/// 길 찾기가 실제로 쓰는 표시: 막힌(계단) 조각과 가파르다고 표시된 조각.
///
/// 조사 기록의 선은 "누른 자리"이고, 이 선은 "그래서 실제로 막힌 곳"이다.
/// 둘이 다르면(엉뚱한 길이 막혔거나 아무것도 안 막혔으면) 조사자가 바로 알 수 있다.
List<Polyline> overlayLines(Graph g, {bool stairsOnly = false}) => [
  for (final e in g.edges)
    if (e.kind == Kind.stairs || (e.kind == Kind.steep && !stairsOnly))
      Polyline(
        points: [g.nodes[e.a], g.nodes[e.b]],
        strokeWidth: 8,
        color: kindStyle(e.kind).color,
        pattern: kindStyle(e.kind).pattern,
      ),
];

/// 기록 가운데에 놓는 종류 아이콘. 누르면 [onTap] (삭제 묻기).
/// [unapplied]에 든 기록(길에 반영되지 않은 계단·급경사)은 물음표를 달아 구분한다.
List<Marker> recordMarkers(
  Iterable<SurveyRecord> records,
  void Function(SurveyRecord) onTap, {
  Set<SurveyRecord> unapplied = const {},
}) => [
  for (final r in records)
    Marker(
      point: LatLng(
        (r.a.latitude + r.b.latitude) / 2,
        (r.a.longitude + r.b.longitude) / 2,
      ),
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: unapplied.contains(r)
            ? '${r.kind.label} 기록 (길에 반영되지 않음)'
            : '${r.kind.label} 기록',
        onPressed: () => onTap(r),
        icon: unapplied.contains(r)
            ? Badge(label: const Text('?'), child: Icon(kindStyle(r.kind).icon))
            : Icon(kindStyle(r.kind).icon),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: kindStyle(r.kind).color,
          side: BorderSide(
            color: unapplied.contains(r)
                ? Colors.grey
                : kindStyle(r.kind).color,
            width: 2,
          ),
        ),
      ),
    ),
];

/// 기록을 더하거나 지운 뒤 조사자에게 알릴 말. 알릴 것이 없으면 null.
///
/// 계단·급경사 기록은 "길 위"에 있어야 길 찾기에 반영된다. 반영 여부는 다른
/// 기록(길)을 더하거나 지울 때도 바뀌므로, 바뀔 때마다 알려야 한다.
String? surveyNotice({
  required bool saved,
  SurveyRecord? created,
  required bool createdApplied,
  required int newlyApplied,
  required int newlyUnapplied,
}) {
  final marksPath = created?.kind == Kind.stairs || created?.kind == Kind.steep;
  final lines = [
    if (!saved) '저장하지 못했습니다. 내보내기로 사본을 남겨 주세요',
    if (marksPath && !createdApplied)
      "길 위의 구간으로 인식하지 못해 지도에만 표시합니다(? 표시). "
          "길이 없는 곳이면 '새 길'을 먼저 기록하고, 굽은 구간은 곧은 조각으로 나눠 기록하세요",
    if (marksPath && createdApplied)
      created!.kind == Kind.stairs
          ? '이 구간을 길 찾기에서 막았습니다'
          : '이 구간을 가파른 길로 표시했습니다',
    if (newlyApplied > 0) '계단·급경사 기록 $newlyApplied건이 이제 길에 반영됩니다',
    if (newlyUnapplied > 0)
      '계단·급경사 기록 $newlyUnapplied건이 길에 반영되지 않게 되었습니다 (? 표시를 확인하세요)',
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

/// 조사 탭 위쪽: 기록할 종류 고르기.
class KindBar extends StatelessWidget {
  const KindBar({super.key, required this.selected, required this.onSelected});

  final Kind selected;
  final ValueChanged<Kind> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Wrap(
      spacing: 8,
      children: [
        for (final k in surveyKinds)
          ChoiceChip(
            avatar: Icon(kindStyle(k).icon, color: kindStyle(k).color),
            label: Text(k.label),
            selected: k == selected,
            showCheckmark: false,
            onSelected: (_) => onSelected(k),
          ),
      ],
    ),
  );
}

/// 조사 탭 아래쪽: 안내 문구, 취소, 내보내기.
class SurveyBar extends StatelessWidget {
  const SurveyBar({
    super.key,
    required this.kind,
    required this.count,
    required this.unapplied,
    required this.waitingForEnd,
    required this.onExport,
    required this.onCancel,
  });

  final Kind kind;
  final int count;

  /// 길에 반영되지 않은 계단·급경사 기록 수.
  final int unapplied;
  final bool waitingForEnd;
  final VoidCallback onExport;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final hint = kind == Kind.elevator
        ? '아래쪽 출입구와 위쪽 출입구를 누르세요'
        : '시작점과 끝점을 누르세요';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              waitingForEnd
                  ? '끝점을 누르세요'
                  : unapplied > 0
                  ? '기록 $count건 (길에 반영 안 됨 $unapplied건) · $hint'
                  : '기록 $count건 · $hint',
            ),
          ),
          if (waitingForEnd)
            TextButton(onPressed: onCancel, child: const Text('취소')),
          FilledButton.tonalIcon(
            onPressed: onExport,
            icon: const Icon(Icons.ios_share),
            label: const Text('내보내기'),
          ),
        ],
      ),
    );
  }
}
