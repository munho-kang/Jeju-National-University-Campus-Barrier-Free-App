import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'model.dart';
import 'route.dart';

const _green = Color(0xFF1A8F3C), _orange = Color(0xFFE08A00);

/// 출발지 고르기에서 "내 위치"를 뜻하는 표식.
const myLocation = Place('내 위치', LatLng(0, 0));

// ── 경로 요약 문구 ──

String summaryLine(RouteResult r) => '${r.meters.round()}m · 약 ${r.minutes}분';

String detailLine(RouteResult r) =>
    '계단 없음 · 경사로 ${r.ramps}곳 · 엘리베이터 ${r.elevators}곳 이용';

/// 가파른 구간이 없으면 null.
String? warningLine(RouteResult r) {
  if (r.steepSections.isEmpty) return null;
  final grade = r.maxSteepGrade;
  final how = grade == null
      ? '조사자가 급경사로 표시'
      : '최대 기울기 ${(grade * 100).round()}%';
  return '가파른 구간 ${r.steepSections.length}곳 (${r.steepMeters.round()}m, $how)';
}

// ── 지도 위 경로 ──

/// 완만한 구간은 초록 실선, 가파른 구간은 주황 점선 (색만으로 구분하지 않는다).
List<Polyline> routeLines(RouteResult r) {
  final lines = <Polyline>[];
  var points = <LatLng>[];
  var steep = false;
  void flush() {
    if (points.length < 2) return;
    lines.add(
      Polyline(
        points: points,
        strokeWidth: 6,
        color: steep ? _orange : _green,
        pattern: steep
            ? StrokePattern.dashed(segments: const [14, 8])
            : const StrokePattern.solid(),
      ),
    );
  }

  for (final leg in r.legs) {
    if (points.isEmpty || leg.steep != steep) {
      flush();
      steep = leg.steep;
      points = [leg.a];
    }
    points.add(leg.b);
  }
  flush();
  return lines;
}

/// 가파른 구간마다 가운데에 경고 표시.
List<Marker> routeMarkers(RouteResult r) => [
  for (final section in r.steepSections)
    Marker(
      point: section[section.length ~/ 2].a,
      width: 32,
      height: 32,
      alignment: Alignment.topCenter, // 선을 가리지 않게 선 위쪽에 둔다
      child: IgnorePointer(
        child: Semantics(
          label: '가파른 구간',
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber, color: _orange, size: 24),
          ),
        ),
      ),
    ),
];

// ── 장소 고르기 ──

/// 아래에서 올라오는 창에서 장소를 고른다. 닫으면 null.
Future<Place?> pickPlace(
  BuildContext context,
  List<Place> places, {
  required String title,
  bool offerMyLocation = false,
}) => showModalBottomSheet<Place>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _PlacePicker(places, title, offerMyLocation),
);

class _PlacePicker extends StatefulWidget {
  const _PlacePicker(this.places, this.title, this.offerMyLocation);
  final List<Place> places;
  final String title;
  final bool offerMyLocation;

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    // 띄어쓰기를 다르게 써도 찾을 수 있게 빈칸을 빼고 비교한다.
    String plain(String s) => s.replaceAll(' ', '');
    final found = widget.places
        .where((p) => plain(p.name).contains(plain(_query)))
        .toList();
    return Padding(
      // 키보드가 올라와도 목록이 가려지지 않게
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.title,
                  hintText: '건물 이름 (예: 중앙도서관)',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.offerMyLocation)
                    ListTile(
                      leading: const Icon(Icons.my_location),
                      title: Text(myLocation.name),
                      onTap: () => Navigator.pop(context, myLocation),
                    ),
                  for (final p in found)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(p.name),
                      onTap: () => Navigator.pop(context, p),
                    ),
                  if (found.isEmpty) const ListTile(title: Text('찾는 건물이 없습니다')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 지도 탭 위쪽: 검색 칸 또는 "출발 → 도착" ──

class RouteHeader extends StatelessWidget {
  const RouteHeader({
    super.key,
    required this.start,
    required this.dest,
    required this.onPickDest,
    required this.onPickStart,
    required this.onClear,
  });

  /// 출발지 이름. 아직 정하지 못했으면 null.
  final String? start;

  /// 목적지 이름. 아직 고르지 않았으면 null.
  final String? dest;
  final VoidCallback onPickDest, onPickStart, onClear;

  @override
  Widget build(BuildContext context) {
    final dest = this.dest;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: dest == null
          ? ListTile(
              leading: const Icon(Icons.search),
              title: const Text('어디로 갈까요? (예: 중앙도서관)'),
              onTap: onPickDest,
            )
          : Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.trip_origin),
                  title: Text('출발  ${start ?? '고르기'}'),
                  onTap: onPickStart,
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on),
                  title: Text('도착  $dest'),
                  onTap: onPickDest,
                  trailing: IconButton(
                    tooltip: '길 안내 끝내기',
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── 지도 탭 아래쪽: 경로 요약, 경고, 휠체어 종류 ──

class RouteSheet extends StatelessWidget {
  const RouteSheet({
    super.key,
    required this.route,
    required this.needStart,
    required this.profile,
    required this.onProfile,
    required this.onPickStart,
  });

  /// 찾은 길. 갈 수 있는 길이 없으면 null.
  final RouteResult? route;

  /// 출발지를 아직 모른다 (내 위치를 모르거나 캠퍼스 밖).
  final bool needStart;
  final Profile profile;
  final ValueChanged<Profile> onProfile;
  final VoidCallback onPickStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final route = this.route;
    final warning = route == null ? null : warningLine(route);
    return Container(
      width: double.infinity, // 내용이 짧아도 왼쪽부터 채운다
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: needStart
            ? [
                Text('출발지를 골라 주세요', style: text.titleMedium),
                const Text('현재 위치를 알 수 없거나 캠퍼스 밖입니다'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: onPickStart,
                  child: const Text('출발지 고르기'),
                ),
              ]
            : route == null
            ? [Text('휠체어로 갈 수 있는 길을 찾지 못했습니다', style: text.titleMedium)]
            : [
                Row(
                  children: [
                    const Icon(Icons.accessible),
                    const SizedBox(width: 6),
                    Text(
                      summaryLine(route),
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(detailLine(route)),
                if (warning != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3DC),
                      border: Border.all(color: const Color(0xFFE0A030)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: Color(0xFF7A4A00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$warning\n도움이 필요할 수 있습니다',
                            style: const TextStyle(color: Color(0xFF7A4A00)),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text('기울기는 추정값입니다', style: text.bodySmall),
                const SizedBox(height: 6),
                SegmentedButton<Profile>(
                  showSelectedIcon: false,
                  segments: [
                    for (final p in Profile.values)
                      ButtonSegment(value: p, label: Text(p.label)),
                  ],
                  selected: {profile},
                  onSelectionChanged: (s) => onProfile(s.first),
                ),
              ],
      ),
    );
  }
}
