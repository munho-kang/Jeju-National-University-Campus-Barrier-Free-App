import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

/// 기록 가운데에 놓는 종류 아이콘. 누르면 [onTap] (삭제 묻기).
List<Marker> recordMarkers(
  Iterable<SurveyRecord> records,
  void Function(SurveyRecord) onTap,
) => [
  for (final r in records)
    Marker(
      point: LatLng(
        (r.a.latitude + r.b.latitude) / 2,
        (r.a.longitude + r.b.longitude) / 2,
      ),
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: '${r.kind.label} 기록',
        onPressed: () => onTap(r),
        icon: Icon(kindStyle(r.kind).icon),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: kindStyle(r.kind).color,
          side: BorderSide(color: kindStyle(r.kind).color, width: 2),
        ),
      ),
    ),
];

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
    required this.waitingForEnd,
    required this.onExport,
    required this.onCancel,
  });

  final Kind kind;
  final int count;
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
            child: Text(waitingForEnd ? '끝점을 누르세요' : '기록 $count건 · $hint'),
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
