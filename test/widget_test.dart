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
}
