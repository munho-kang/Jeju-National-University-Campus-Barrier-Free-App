import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/guidance_map.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:latlong2/latlong.dart';

import 'helpers.dart';

void main() {
  test('겹치는 이름은 뒤의 것을 숨긴다', () {
    expect(
      keepLabels(const [
        Rect.fromLTWH(0, 0, 50, 20),
        Rect.fromLTWH(40, 10, 50, 20),
        Rect.fromLTWH(100, 0, 50, 20),
      ]),
      [0, 2],
    );
  });
  testWidgets('17 지도가 돌아가 있어도 건물 이름은 바로 서 있고, 가는 방향이 위·왼쪽이 왼쪽이다', (t) async {
    final c = tinyCampus();
    final (graph, route) = net(c.nodes, c.edges, m(0, 0), m(0, 300));
    final map = MapController();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuidanceMap(
            controller: map,
            campus: c,
            graph: graph,
            buildings: [
              [m(10, 10), m(30, 10), m(30, 30)],
            ],
            route: route,
            dest: c.places[1],
            position: m(0, 0),
            heading: 90, // 동쪽으로 가는 중
          ),
        ),
      ),
    );
    await t.pump();
    expect(map.camera.rotation, closeTo(-90, 0.01));
    final here = map.camera.latLngToScreenOffset(m(0, 0));
    final ahead = map.camera.latLngToScreenOffset(m(50, 0)); // 가는 쪽(동쪽)
    final left = map.camera.latLngToScreenOffset(m(0, 50)); // 가는 쪽의 왼쪽(북쪽)
    expect(ahead.dy, lessThan(here.dy - 50)); // 화면 위쪽
    expect(ahead.dx, closeTo(here.dx, 1));
    expect(left.dx, lessThan(here.dx - 50)); // 화면 왼쪽
    final name = find.text('정문');
    expect(
      t.getTopRight(name).dy,
      closeTo(t.getTopLeft(name).dy, 0.01),
    ); // 눕지 않았다
    expect(t.getTopRight(name).dx, greaterThan(t.getTopLeft(name).dx));
    expect(find.byType(TileLayer), findsNothing); // 인터넷 없이 보인다
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    final opts = t.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(opts.backgroundColor, const Color(0xFFF3F4F6));
    final roads = t
        .widgetList<PolylineLayer>(find.byType(PolylineLayer))
        .first
        .polylines;
    expect(roads.first.color, const Color(0xFFFFFFFF));
    expect(roads.first.strokeWidth, 5);
    expect(roads.first.strokeWidth + roads.first.borderStrokeWidth, 8);
    expect(roads.first.borderColor, const Color(0xFFE1E4E8));
    final polys = t
        .widgetList<PolygonLayer>(find.byType(PolygonLayer))
        .toList();
    expect(
      polys[0].polygons.single.color,
      const Color(0xFFC3C8D0),
    ); // 그림자가 먼저(아래)
    expect(polys[1].polygons.single.color, const Color(0xFFD9DDE4));
    expect(polys[1].polygons.single.borderColor, const Color(0xFFB8BEC8));
    final label = t.widget<Text>(find.text('정문')).style!;
    expect(label.color, const Color(0xFF4A4F57));
    expect(label.fontWeight, FontWeight.w700);
    expect(label.shadows, isNotEmpty);
  });

  Future<void> pumpDest(
    WidgetTester t,
    Place Function(Campus) dest,
    LatLng position,
  ) async {
    final c = tinyCampus();
    final (graph, route) = net(c.nodes, c.edges, m(0, 0), m(0, 300));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuidanceMap(
            controller: MapController(),
            campus: c,
            graph: graph,
            buildings: const [],
            route: route,
            dest: dest(c),
            position: position,
            heading: 0,
          ),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('목적지 이름은 핀에 한 번만 보인다', (t) async {
    final sem = t.ensureSemantics();
    await pumpDest(t, (c) => c.places[1], m(0, 290));
    expect(
      find.descendant(of: find.byType(DestPin), matching: find.text('도서관')),
      findsOneWidget,
    );
    expect(find.text('도서관'), findsOneWidget);
    expect(find.byType(MeDot), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('내 위치')), findsOneWidget);
    sem.dispose();
  });

  testWidgets('목적지 이름이 길어도 핀이 넘치지 않는다', (t) async {
    await pumpDest(t, (_) => Place('가' * 40, m(0, 10)), m(0, 0));
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(DestPin)).width, lessThanOrEqualTo(160));
  });

  testWidgets('세로 화면에서 돌아가 있어도 아래쪽(지나온 쪽) 건물 이름이 남는다', (t) async {
    t.view.physicalSize = const Size(800, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = tinyCampus();
    final (graph, route) = net(c.nodes, c.edges, m(0, 0), m(0, 300));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuidanceMap(
            controller: MapController(),
            campus: c,
            graph: graph,
            buildings: const [],
            route: route,
            dest: c.places[1],
            position: m(100, 0), // 정문(0,0)은 동쪽으로 가는 중이라 화면 아래
            heading: 90,
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.text('정문'), findsOneWidget);
  });

  Future<void> pumpNames(
    WidgetTester t,
    List<Place> places, {
    LatLng? pin,
    double scale = 1,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: FlutterMap(
              options: MapOptions(initialCenter: m(0, 0), initialZoom: 18),
              children: [NameLayer(places: places, pin: pin)],
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('F1 글자를 키우면 이름 폭도 그만큼 재서, 겹치게 된 이름을 숨긴다', (t) async {
    // 글자 4개(테스트 글꼴은 12px씩)가 60px 간격: 1배에서는 안 겹치고 2배에서는 겹친다.
    final places = [Place('가나다라', m(-15, 0)), Place('마바사아', m(15, 0))];
    await pumpNames(t, places);
    expect(find.byType(Text), findsNWidgets(2));
    await pumpNames(t, places, scale: 2);
    expect(find.byType(Text), findsOneWidget);
    // 글꼴이 늦게 도착해 다시 재는 부분(systemFonts 알림)은 테스트에서 재현하지 않는다.
  });

  testWidgets('F2 목적지 핀이 있는 자리의 건물 이름은 숨긴다', (t) async {
    final near = Place('옆건물', m(0, 0));
    await pumpNames(t, [near]);
    expect(find.text('옆건물'), findsOneWidget);
    await pumpNames(t, [near], pin: m(0, 0)); // 핀이 그 자리를 덮는다
    expect(find.text('옆건물'), findsNothing);
  });
}
