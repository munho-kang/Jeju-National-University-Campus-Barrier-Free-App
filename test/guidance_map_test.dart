import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/guidance_map.dart';
import 'package:jnu_wheel_nav/model.dart';

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
  });

  testWidgets('세로 화면에서 돌아가 있어도 아래쪽(지나온 쪽) 건물 이름이 남는다', (t) async {
    t.view.physicalSize = const Size(400, 800);
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
            dest: Place('뒤쪽', m(-100, 0)), // 동쪽으로 가는 중이라 화면 아래
            position: m(0, 0),
            heading: 90,
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.text('뒤쪽'), findsOneWidget);
  });
}
