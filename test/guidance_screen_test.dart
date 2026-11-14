import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/guidance_screen.dart';
import 'package:jnu_wheel_nav/main.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/voice.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  /// '원래 화면' 위에 안내 화면을 띄운다. [fixes]가 없으면 미리 보기.
  Future<void> show(
    WidgetTester t, {
    Stream<Fix>? fixes,
    Voice? voice,
    Campus? campus,
  }) async {
    final c = campus ?? tinyCampus();
    final dest = c.places.firstWhere((p) => p.name == '도서관');
    final (graph, route) = net(c.nodes, c.edges, m(0, 0), dest.at);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('원래 화면'))));
    t
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<bool>(
            builder: (_) => GuidanceScreen(
              campus: c,
              graph: graph,
              buildings: const [],
              route: route,
              dest: dest,
              voice: voice ?? FakeVoice(),
              fixes: fixes,
            ),
          ),
        );
    await t.pump();
    await t.pump(const Duration(seconds: 1)); // 화면이 넘어오는 1초 (미리 보기는 5m 나아간다)
  }

  testWidgets('16 다음 안내와 남은 거리가 보이고, 끝내면 원래 화면으로 돌아간다', (t) async {
    final voice = FakeVoice();
    final fixes = StreamController<Fix>();
    addTearDown(fixes.close);
    await show(t, fixes: fixes.stream, voice: voice);
    expect(find.text('100m 앞에서 왼쪽'), findsOneWidget);
    expect(find.text('그다음: 왼쪽'), findsOneWidget);
    expect(find.text('남은 거리 500m · 약 10분'), findsOneWidget);
    expect(find.text('미리 보기 중'), findsNothing);
    expect(voice.said, ['안내를 시작합니다. 전체 500미터, 약 10분입니다']);
    fixes.add((at: m(40, 0), accuracy: 5));
    await t.pump(Duration.zero); // 위치가 전달된 뒤에 한 프레임을 그리게 한다
    expect(find.text('60m 앞에서 왼쪽'), findsOneWidget);
    expect(find.text('남은 거리 460m · 약 10분'), findsOneWidget);
    await t.tap(find.text('안내 끝내기'));
    await t.pumpAndSettle();
    expect(find.text('원래 화면'), findsOneWidget);
    expect(find.byType(GuidanceScreen), findsNothing);
    expect(voice.stops, 1); // 하던 말을 끊는다
  });
  testWidgets('19 소리를 끄면 목소리로는 전달되지 않고 글자로는 나온다', (t) async {
    final voice = FakeVoice();
    final fixes = StreamController<Fix>();
    addTearDown(fixes.close);
    await show(t, fixes: fixes.stream, voice: voice);
    await t.tap(find.byTooltip('소리 끄기'));
    await t.pump();
    fixes.add((at: m(40, 0), accuracy: 5));
    fixes.add((at: m(81, 0), accuracy: 5));
    await t.pump(Duration.zero);
    expect(voice.said.length, 1); // 시작할 때 한 번뿐
    expect(find.text('20미터 앞에서 왼쪽입니다'), findsOneWidget); // 자막
    expect(find.byTooltip('소리 켜기'), findsOneWidget);
  });
  testWidgets('19 목소리 기능이 없어도 화면 안내는 나온다', (t) async {
    await show(t, voice: Voice()); // 진짜 Voice. 테스트 환경에는 목소리 기능이 없다
    expect(find.text('95m 앞에서 왼쪽'), findsOneWidget);
    expect(find.text('미리 보기 중'), findsOneWidget);
  });
  testWidgets('18·19 미리 보기를 끝까지 돌리면 문장이 순서대로 나오고 도착하면 닫힌다', (t) async {
    final voice = FakeVoice();
    await show(t, voice: voice);
    for (var i = 0; i < 105; i++) {
      await t.pump(const Duration(seconds: 1)); // 500m ÷ 초속 5m = 100초
    }
    expect(voice.said, [
      '안내를 시작합니다. 전체 500미터, 약 10분입니다',
      '20미터 앞에서 왼쪽입니다',
      '20미터 앞에서 왼쪽입니다',
      '목적지에 도착했습니다. 안내를 마칩니다',
    ]);
    expect(find.text('원래 화면'), findsOneWidget);
    expect(voice.stops, 0); // Review Focus 4: 도착 음성을 끊지 않는다
  });
  testWidgets('18 미리 보기 중에 지도를 눌러 길에서 벗어나면 다시 찾는다', (t) async {
    final voice = FakeVoice();
    await show(t, voice: voice, campus: tinyCampus(spur: true));
    await t.pump(const Duration(seconds: 17)); // 90m 지점. 10m 앞에서 왼쪽으로 꺾을 차례
    // 화면 위쪽이 가는 방향(동쪽)이고 확대 18에서 100px ≈ 50m → 꺾지 않고 곧장 간 (140, 0)
    await t.tapAt(t.getCenter(find.byType(FlutterMap)) + const Offset(0, -100));
    await t.pump(const Duration(seconds: 1));
    expect(voice.said.last, '경로를 다시 찾았습니다. 뒤로 돌아서 가세요');
  });
  testWidgets('누르는 대상이 충분히 크고 이름이 붙어 있다', (t) async {
    final handle = t.ensureSemantics();
    final fixes = StreamController<Fix>();
    addTearDown(fixes.close);
    await show(t, fixes: fixes.stream);
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  /// 앱을 열고, 테스트가 위치를 넣을 수 있는 통로를 돌려준다.
  Future<StreamController<Fix>> openApp(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({});
    final fixes = StreamController<Fix>();
    addTearDown(fixes.close);
    await t.pumpWidget(
      App(
        campus: tinyCampus(),
        bundled: const [],
        local: const [],
        tileProvider: BlankTiles(),
        voice: FakeVoice(),
        fixes: fixes.stream,
      ),
    );
    await t.pumpAndSettle();
    return fixes;
  }

  /// [opener] 글자가 든 칸을 눌러 장소 고르기를 열고 [name]을 고른다.
  Future<void> choose(WidgetTester t, String opener, String name) async {
    await t.tap(find.textContaining(opener));
    await t.pumpAndSettle();
    await t.tap(find.text(name).last);
    await t.pumpAndSettle();
  }

  Future<void> iAmAt(
    WidgetTester t,
    StreamController<Fix> fixes,
    double x,
    double y,
  ) async {
    fixes.add((at: m(x, y), accuracy: 5));
    await t.pump(Duration.zero);
  }

  testWidgets('15 출발이 내 위치일 때만 안내 시작이 보이고, 미리 보기는 경로가 있으면 늘 보인다', (t) async {
    final fixes = await openApp(t);
    await iAmAt(t, fixes, 0, 0);
    await choose(t, '어디로 갈까요', '도서관');
    expect(find.text('안내 시작'), findsOneWidget);
    expect(find.text('미리 보기'), findsOneWidget);
    await choose(t, '출발', '정문'); // 출발지를 직접 고른다
    expect(find.text('안내 시작'), findsNothing);
    expect(find.text('미리 보기'), findsOneWidget);
    await choose(t, '도착', '정문'); // 출발지와 목적지가 같다(0m)
    expect(find.text('미리 보기'), findsNothing);
  });
  testWidgets('16 안내 화면에서는 아래 탭이 숨고, 끝내면 경로 요약과 북쪽 위로 돌아온다', (t) async {
    final fixes = await openApp(t);
    await iAmAt(t, fixes, 0, 0);
    await choose(t, '어디로 갈까요', '도서관');
    await t.tap(find.text('안내 시작'));
    await t.pumpAndSettle();
    expect(find.text('100m 앞에서 왼쪽'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('수동 휠체어'), findsNothing); // 휠체어 종류 버튼도 숨는다
    expect(find.byTooltip('내 위치로 이동'), findsNothing);
    await t.tap(find.text('안내 끝내기'));
    await t.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining('500m · 약 10분'), findsOneWidget);
    expect(
      t
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .camera
          .rotation,
      0,
    );
  });
  testWidgets('안내 시작을 누르면 지금 위치에서 길을 다시 찾고 시작한다', (t) async {
    // Review Focus 5
    final fixes = await openApp(t);
    await iAmAt(t, fixes, 0, 0);
    await choose(t, '어디로 갈까요', '도서관');
    await iAmAt(t, fixes, 50, 0); // 목적지를 고른 뒤 50m 이동
    await t.tap(find.text('안내 시작'));
    await t.pumpAndSettle();
    expect(find.text('남은 거리 450m · 약 9분'), findsOneWidget);
  });
  testWidgets('미리 보기가 끝나면 원래 화면에서 도착을 알린다', (t) async {
    await openApp(t);
    await choose(t, '어디로 갈까요', '도서관');
    await choose(t, '출발지 고르기', '정문'); // 위치를 모를 때 나오는 버튼
    await t.tap(find.text('미리 보기'));
    final arrived = find.text('도서관에 도착했습니다');
    // 약 100초 뒤에 도착한다. 알림은 몇 초 뒤 사라지므로 보이는 순간 멈춘다.
    for (var i = 0; i < 110 && arrived.evaluate().isEmpty; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(arrived, findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
