import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/guidance_map.dart';
import 'package:jnu_wheel_nav/main.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/store.dart';
import 'package:jnu_wheel_nav/survey_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<void> open(
  WidgetTester t, {
  Campus? campus,
  List<SurveyRecord> bundled = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(
    App(
      campus: campus ?? tinyCampus(),
      bundled: bundled,
      local: const [],
      tileProvider: BlankTiles(),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> pick(WidgetTester t, String name) async {
  await t.tap(find.text(name).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('탭 두 개와 조사 종류 다섯 개가 보인다', (t) async {
    await open(t);
    expect(find.text('지도'), findsOneWidget);
    await t.tap(find.text('조사'));
    await t.pumpAndSettle();
    for (final k in surveyKinds) {
      expect(find.widgetWithText(ChoiceChip, k.label), findsOneWidget);
    }
    expect(find.text('내보내기'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('지도를 두 번 누르면 기록이 저장되고, 지울 수 있다', (t) async {
    await open(t);
    await t.tap(find.text('조사'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, '새 길'));
    final c = t.getCenter(find.byType(FlutterMap));
    await t.tapAt(c + const Offset(-60, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('끝점을 누르세요'), findsOneWidget);
    await t.tapAt(c + const Offset(60, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('기록 1건'), findsOneWidget);
    expect((await loadRecords()).single.kind, Kind.newPath);
    await t.tap(
      find.descendant(
        of: find.byType(MarkerLayer),
        matching: find.byIcon(Icons.add_road),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('삭제'));
    await t.pumpAndSettle();
    expect(find.textContaining('기록 0건'), findsOneWidget);
    expect(await loadRecords(), isEmpty);
  });

  testWidgets('탭을 바꿔도 지도가 새로 만들어지지 않는다 (보던 위치가 유지된다)', (t) async {
    await open(t);
    final map = t.state(find.byType(FlutterMap));
    await t.tap(find.text('조사'));
    await t.pumpAndSettle();
    expect(t.state(find.byType(FlutterMap)), same(map));
    await t.tap(find.text('지도'));
    await t.pumpAndSettle();
    expect(t.state(find.byType(FlutterMap)), same(map));
  });

  testWidgets('길에 반영되지 않은 계단 기록은 다르게 보이고 개수가 표시된다', (t) async {
    await open(t);
    await t.tap(find.text('조사'));
    await t.pumpAndSettle();
    // 종류는 처음부터 '계단'. 길에서 먼 두 점을 누른다.
    final c = t.getCenter(find.byType(FlutterMap));
    await t.tapAt(c + const Offset(-60, 0));
    await t.pumpAndSettle();
    await t.tapAt(c + const Offset(60, 0));
    await t.pumpAndSettle();
    expect(find.byTooltip('계단 기록 (길에 반영되지 않음)'), findsOneWidget);
    expect(find.textContaining('반영 안 됨 1건'), findsOneWidget);
  });

  // Review Focus 4: 테스트에는 위치 기능이 없다 → 앱이 멈추지 않아야 한다
  testWidgets('위치를 모르면 출발지를 고르게 하고, 고르면 경로 요약이 나온다', (t) async {
    await open(t);
    await t.tap(find.textContaining('어디로 갈까요'));
    await t.pumpAndSettle();
    await pick(t, '도서관');
    expect(find.text('출발지를 골라 주세요'), findsOneWidget);
    await t.tap(find.text('출발지 고르기'));
    await t.pumpAndSettle();
    await pick(t, '정문');
    expect(find.textContaining('500m'), findsOneWidget); // 100 + 300 + 100
    expect(find.textContaining('계단 없음'), findsOneWidget);
    expect(find.text('기울기는 추정값입니다'), findsOneWidget);
    expect(find.text('수동 휠체어'), findsOneWidget);
    expect(find.text('전동 휠체어'), findsOneWidget);
  });

  testWidgets('지도 탭은 그림 조각 없이 그리고, 조사 탭만 그림 조각을 쓴다', (t) async {
    await open(t);
    expect(find.byType(TileLayer), findsNothing);
    expect(find.text('정문'), findsOneWidget); // 건물 이름 층
    final map = MapCamera.of(t.element(find.byType(MarkerLayer)));
    final center = map.center;
    await t.tap(find.text('조사'));
    await t.pumpAndSettle();
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.text('정문'), findsNothing);
    await t.tap(find.text('지도'));
    await t.pumpAndSettle();
    expect(find.byType(TileLayer), findsNothing);
    expect(MapCamera.of(t.element(find.byType(MarkerLayer))).center, center);
  });

  testWidgets('계단 표시는 길보다 위에 그린다', (t) async {
    await open(t, bundled: [rec(Kind.stairs, m(40, 0), m(60, 0))]);
    final kids = t.widget<FlutterMap>(find.byType(FlutterMap)).children;
    int at(bool Function(Polyline) f) =>
        kids.indexWhere((w) => w is PolylineLayer && w.polylines.any(f));
    final roads = at((p) => p.borderStrokeWidth > 0);
    final stairs = at((p) => p.color == kindStyle(Kind.stairs).color);
    expect(roads, greaterThanOrEqualTo(0));
    expect(stairs, greaterThan(roads));
  });

  testWidgets('목적지를 고르면 핀에 이름이 나오고 출발점은 동그라미다', (t) async {
    await open(t);
    await t.tap(find.textContaining('어디로 갈까요'));
    await t.pumpAndSettle();
    await pick(t, '도서관');
    await t.tap(find.text('출발지 고르기'));
    await t.pumpAndSettle();
    await pick(t, '정문');
    expect(
      find.descendant(of: find.byType(DestPin), matching: find.text('도서관')),
      findsOneWidget,
    );
    expect(find.byType(StartDot), findsOneWidget);
  });

  testWidgets('갈 수 있는 길이 없으면 알려 준다', (t) async {
    await open(t, campus: tinyCampus(connected: false));
    await t.tap(find.textContaining('어디로 갈까요'));
    await t.pumpAndSettle();
    await pick(t, '도서관');
    await t.tap(find.text('출발지 고르기'));
    await t.pumpAndSettle();
    await pick(t, '정문');
    expect(find.text('휠체어로 갈 수 있는 길을 찾지 못했습니다'), findsOneWidget);
  });

  testWidgets('누르는 대상이 충분히 크고 이름이 붙어 있다', (t) async {
    final handle = t.ensureSemantics();
    Future<void> check() async {
      // 48×48 이상인지, 화면 읽기 프로그램용 이름이 있는지
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    }

    await open(t);
    await check(); // 지도 탭: 검색 칸, 지도 버튼
    await t.tap(find.textContaining('어디로 갈까요'));
    await t.pumpAndSettle();
    await check(); // 장소 고르기 창
    await pick(t, '도서관');
    await check(); // 출발지 고르기 안내
    await t.tap(find.text('출발지 고르기'));
    await t.pumpAndSettle();
    await pick(t, '정문');
    await check(); // 경로 요약, 수동/전동 전환
    await t.tap(find.text('조사'));
    await t.pumpAndSettle();
    final c = t.getCenter(find.byType(FlutterMap));
    await t.tapAt(c + const Offset(-60, 0));
    await t.pumpAndSettle();
    await check(); // 끝점 기다리는 중: 취소 버튼
    await t.tapAt(c + const Offset(60, 0));
    await t.pumpAndSettle();
    await check(); // 기록 아이콘, 종류 칩, 내보내기
    handle.dispose();
  });
}
