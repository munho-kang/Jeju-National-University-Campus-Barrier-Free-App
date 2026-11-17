import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'graph.dart';
import 'model.dart';
import 'route.dart';
import 'route_tab.dart';
import 'survey_tab.dart';

const mapBackground = Color(0xFFF3F4F6);

const _labelStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: Color(0xFF4A4F57),
  shadows: [
    Shadow(offset: Offset(1, 1), color: Colors.white),
    Shadow(offset: Offset(-1, 1), color: Colors.white),
    Shadow(offset: Offset(1, -1), color: Colors.white),
    Shadow(offset: Offset(-1, -1), color: Colors.white),
    Shadow(blurRadius: 2, color: Colors.white),
  ],
);

LatLng _shifted(LatLng p) => LatLng(
  p.latitude - 1.5 / 110574,
  p.longitude + 1.5 / (111320 * cos(p.latitude * pi / 180)),
);

/// 안내 화면과 지도 탭이 함께 쓰는 층: [건물 그림자, 건물, 길].
List<Widget> campusLayers(Graph graph, List<List<LatLng>> buildings) => [
  PolygonLayer(
    polygons: [
      for (final b in buildings)
        Polygon(
          points: [for (final p in b) _shifted(p)],
          color: const Color(0xFFC3C8D0),
        ),
    ],
  ),
  PolygonLayer(
    polygons: [
      for (final b in buildings)
        Polygon(
          points: b,
          color: const Color(0xFFD9DDE4),
          borderColor: const Color(0xFFB8BEC8),
          borderStrokeWidth: 1,
        ),
    ],
  ),
  PolylineLayer(
    polylines: [
      for (final e in graph.edges)
        if (e.kind != Kind.stairs)
          Polyline(
            points: [graph.nodes[e.a], graph.nodes[e.b]],
            strokeWidth: 5,
            color: Colors.white,
            borderStrokeWidth: 3,
            borderColor: const Color(0xFFE1E4E8),
          ),
    ],
  ),
];

const _blue = Color(0xFF2A7DE1);

class StartDot extends StatelessWidget {
  const StartDot({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.fromBorderSide(BorderSide(color: _blue, width: 4)),
    ),
  );
}

class MeDot extends StatelessWidget {
  const MeDot({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Semantics(
      label: '내 위치',
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const SizedBox.square(
            dimension: 44,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _blue,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: Colors.white, width: 3),
                  ),
                ),
                child: SizedBox.square(dimension: 18),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class DestPin extends StatelessWidget {
  const DestPin(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFC0392B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Icon(Icons.location_on, size: 36, color: Color(0xFFC0392B)),
      ],
    ),
  );
}

/// 앞에서부터 보며, 이미 남긴 것과 겹치지 않는 것의 번호만 남긴다.
List<int> keepLabels(List<Rect> rects) {
  final kept = <int>[];
  for (var i = 0; i < rects.length; i++) {
    if (kept.every((k) => !rects[k].overlaps(rects[i]))) kept.add(i);
  }
  return kept;
}

/// 건물 이름. 지도가 돌아도 글자는 바로 선다(돌리는 층으로 감싸지 않는다).
/// [pin]이 있으면 목적지 핀(160x80, 위 가운데 기준)이 차지한 자리를 먼저 비워 둔다.
class NameLayer extends StatefulWidget {
  const NameLayer({super.key, required this.places, this.pin});
  final List<Place> places;
  final LatLng? pin;

  @override
  State<NameLayer> createState() => _NameLayerState();
}

class _NameLayerState extends State<NameLayer> {
  @override
  void initState() {
    super.initState();
    // 웹에서는 글꼴이 늦게 도착한다. 도착하면 글자 크기를 다시 잰다.
    PaintingBinding.instance.systemFonts.addListener(_refresh);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final style = DefaultTextStyle.of(context).style.merge(_labelStyle);
    final scaler = MediaQuery.textScalerOf(context);
    final screen = Offset.zero & camera.nonRotatedSize;
    final rects = <Rect>[];
    final shown = <Place>[];
    final pin = widget.pin;
    if (pin != null) {
      final c = camera.latLngToScreenOffset(pin);
      rects.add(Rect.fromLTRB(c.dx - 80, c.dy - 80, c.dx + 80, c.dy));
    }
    final offset = rects.length;
    for (final p in widget.places) {
      final c = camera.latLngToScreenOffset(p.at);
      if (!screen.contains(c)) continue;
      final tp = TextPainter(
        text: TextSpan(text: p.name, style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      shown.add(p);
      rects.add(Rect.fromCenter(center: c, width: tp.width, height: tp.height));
      tp.dispose();
    }
    return IgnorePointer(
      child: Stack(
        children: [
          for (final i in keepLabels(rects))
            if (i >= offset)
              Positioned(
                left: rects[i].left,
                top: rects[i].top,
                child: Text(shown[i - offset].name, style: style),
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
        backgroundColor: mapBackground,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.scrollWheelZoom,
        ),
        onTap: (_, p) => onTap?.call(p),
      ),
      children: [
        ...campusLayers(graph, buildings),
        PolylineLayer(polylines: overlayLines(graph, stairsOnly: true)),
        PolylineLayer(polylines: routeLines(route)),
        MarkerLayer(
          rotate: true,
          markers: [
            ...routeMarkers(route),
            Marker(
              point: dest.at,
              width: 160,
              height: 80,
              alignment: Alignment.topCenter, // 핀 끝이 건물을 가리키게
              child: DestPin(dest.name),
            ),
            Marker(
              point: position,
              width: 44,
              height: 44,
              child: const MeDot(),
            ),
          ],
        ),
        NameLayer(
          places: [
            for (final p in campus.places)
              if (p != dest) p,
          ],
          pin: dest.at,
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
      ],
    );
  }
}
