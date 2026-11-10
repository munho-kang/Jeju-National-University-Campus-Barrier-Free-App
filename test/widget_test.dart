import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/main.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<void> open(WidgetTester t, {Campus? campus}) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(
    App(
      campus: campus ?? tinyCampus(),
      bundled: const [],
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
}
