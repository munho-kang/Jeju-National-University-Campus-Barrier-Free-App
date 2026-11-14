import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'graph.dart';
import 'model.dart';
import 'route.dart';
import 'route_tab.dart';
import 'survey_tab.dart';

const _labelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: Color(0xFF333333),
);

/// 앞에서부터 보며, 이미 남긴 것과 겹치지 않는 것의 번호만 남긴다.
List<int> keepLabels(List<Rect> rects) {
  final kept = <int>[];
  for (var i = 0; i < rects.length; i++) {
    if (kept.every((k) => !rects[k].overlaps(rects[i]))) kept.add(i);
  }
  return kept;
}

/// 건물 이름. 지도가 돌아도 글자는 바로 선다(돌리는 층으로 감싸지 않는다).
class NameLayer extends StatelessWidget {
  const NameLayer({super.key, required this.places});
  final List<Place> places;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final screen = Offset.zero & camera.nonRotatedSize;
    final centers = <Offset>[];
    final rects = <Rect>[];
    final shown = <Place>[];
    for (final p in places) {
      final c = camera.latLngToScreenOffset(p.at);
      if (!screen.contains(c)) continue;
      final tp = TextPainter(
        text: TextSpan(text: p.name, style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      shown.add(p);
      centers.add(c);
      rects.add(Rect.fromCenter(center: c, width: tp.width, height: tp.height));
      tp.dispose();
    }
    return IgnorePointer(
      child: Stack(
        children: [
          for (final i in keepLabels(rects))
            Positioned(
              left: rects[i].left,
              top: rects[i].top,
              child: Text(shown[i].name, style: _labelStyle),
            ),
        ],
      ),
    );
  }
}

/// 안내 화면 지도: 그림 조각 없이 건물·길·경로를 직접 그린다.
/// 그 뒤 움직임은 [controller]를 가진 쪽이 맡는다.
class GuidanceMap extends StatelessWidget {
  const GuidanceMap({
    super.key,
    required this.controller,
    required this.campus,
    required this.graph,
    required this.buildings,
    required this.route,
    required this.dest,
    required this.position,
    required this.heading,
    this.onTap,
  });

  final MapController controller;
  final Campus campus;
  final Graph graph;
  final List<List<LatLng>> buildings;
  final RouteResult route;
  final Place dest;
  final LatLng position;
  final double heading;
  final void Function(LatLng)? onTap;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: position,
        initialZoom: guidanceZoom,
        initialRotation: -heading,
        minZoom: 15,
        maxZoom: 20,
        backgroundColor: const Color(0xFFF4F1EA),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.scrollWheelZoom,
        ),
        onTap: (_, p) => onTap?.call(p),
      ),
      children: [
        PolygonLayer(
          polygons: [
            for (final b in buildings)
              Polygon(
                points: b,
                color: const Color(0xFFE2DDD0),
                borderColor: const Color(0xFF9A9384),
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        PolylineLayer(
          polylines: [
            for (final e in graph.edges)
              if (e.kind != Kind.stairs)
                Polyline(
                  points: [graph.nodes[e.a], graph.nodes[e.b]],
                  strokeWidth: 4,
                  color: const Color(0xFFBDB8AC),
                ),
          ],
        ),
        PolylineLayer(polylines: overlayLines(graph, stairsOnly: true)),
        PolylineLayer(polylines: routeLines(route)),
        MarkerLayer(
          rotate: true,
          markers: [
            ...routeMarkers(route),
            Marker(
              point: dest.at,
              width: 40,
              height: 40,
              alignment: Alignment.topCenter, // 핀 끝이 건물을 가리키게
              child: const IgnorePointer(
                child: Icon(
                  Icons.location_on,
                  size: 40,
                  color: Color(0xFFC0392B),
                ),
              ),
            ),
            Marker(
              point: position,
              width: 22,
              height: 22,
              child: IgnorePointer(
                child: Semantics(
                  label: '내 위치',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A7DE1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        NameLayer(
          places: [
            dest,
            for (final p in campus.places)
              if (p != dest) p,
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
      ],
    );
  }
}
