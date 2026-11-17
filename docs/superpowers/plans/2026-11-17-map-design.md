# 지도 디자인 바꾸기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 지도 탭과 안내 화면을 견본 D 모습(연회색 바탕, 흰 길, 회색 건물, 초록 경로)으로 앱이 직접 그리게 한다. 조사 탭은 지금 오픈스트리트맵 바탕 그대로.

**Architecture:** 안내 화면(`lib/guidance_map.dart`)이 이미 쓰는 "직접 그리기" 층들을 함수 하나(`campusLayers`)와 표시 위젯 셋(`StartDot`, `DestPin`, `MeDot`)으로 꺼내 D 색으로 바꾼다. 지도 탭(`lib/main.dart`)은 지도 탭일 때만 그림 조각(`TileLayer`) 대신 이 층들을 쓰고, 조사 탭일 때는 지금처럼 `TileLayer`를 쓴다. 지도 위젯은 하나 그대로(탭을 바꿔도 보던 자리 유지).

**Tech Stack:** Flutter, flutter_map 8.3.2(이미 설치), latlong2. 새 패키지 없음.

**Spec:** `docs/superpowers/specs/2026-11-17-map-design.md`

## Global Constraints

- 새 패키지·새 지도 회사·이용 열쇠 없음.
- 바꾸지 않는다: 저장 열쇠 `survey_records`, 기록 JSON 형식, Bundle Identifier `kr.jnucapstone3.jnuWheelNav`. `dart run tool/fetch_campus.dart`는 돌리지 않는다.
- 조사 탭 지도는 지금 오픈스트리트맵 바탕 그대로.
- 색만으로 구분하지 않는다: 가파른 구간은 색 + 선 모양(끊긴 선) + 경고 표시.
- 지도 탭의 계단 표시(빨간 점선, `overlayLines(stairsOnly: true)`)는 길 위에 그대로 보인다.
- 출처 표기 `OpenStreetMap contributors`는 두 화면 모두 남긴다.
- 색·굵기(설계서 그대로):
  - 바탕 `#F3F4F6`
  - 길(계단 아닌 이음선): 흰 `#FFFFFF` 굵기 5 + 테두리 `#E1E4E8` 전체 굵기 8, 둥근 끝·꺾임
  - 건물: 채움 `#D9DDE4`, 테두리 `#B8BEC8` 1px, 그 아래 오른쪽 아래로 밀린 그림자 `#C3C8D0`
  - 건물 이름: `#4A4F57`, 12, 굵게(w700), 흰 테두리, 겹치면 숨김(`keepLabels`)
  - 경로: 흰 밑선 굵기 12 위에 초록 `#12A150` 굵기 7, 둥근 끝. 가파른 구간 주황 `#F59F00` 둥근 끝 끊긴 선
  - 출발: 흰 속 + 파란 테두리 동그라미. 도착: 빨간 핀 + 목적지 이름 말풍선. 내 위치: 파란 점 + 흰 테두리 + 옅은 파란 퍼짐

## 이 계획에서 정한 것 (설계서가 맡긴 것)

- **"둥근 점선"은 끝이 둥근 끊긴 선(`StrokePattern.dashed`)으로 한다.** 동글동글한 점(`dotted`)은 이미 계단(빨강)이 쓰고 있어서, 점으로 하면 계단과 급경사가 색으로만 갈린다.
- **그림자 밀림:** 동쪽 1.5m, 남쪽 1.5m(땅 위 거리). 안내 화면이 돌면 그림자 방향도 같이 돈다 — 괜찮다.
- **확대 단계별 굵기 조정은 하지 않는다.** Task 4 화면 확인에서 확대 14에서 너무 빽빽해 보이면 그때 넣는다.
- **경로 흰 밑선은 경로 전체를 한 줄로** 깐다. 구간마다 `borderStrokeWidth`를 쓰면 초록↔주황이 바뀌는 자리에서 뒤 구간 테두리가 앞 구간을 덮는다. 길(이음선)은 모양이 다 같아 flutter_map이 한 번에 묶어 그리므로 `borderStrokeWidth: 3`(전체 = 5 + 3 = 8)으로 한 층에 그린다.
- **목적지 이름은 핀 말풍선에만** 나온다. 건물 이름 층(`NameLayer`)에는 목적지를 빼고 넘긴다(두 번 보이지 않게).
- **이름 흰 테두리는 `TextStyle.shadows`로** 한다. 글자를 두 겹 겹치면 `find.text`가 둘을 찾아 기존 테스트가 깨진다.
- **조사 탭에는 건물 이름 층을 그리지 않는다**(그림 조각에 이미 이름이 있다). 바탕색도 조사 탭일 때는 flutter_map 기본값 그대로.
- 층 순서(아래→위): 그림자 → 건물 → 길 → 계단 표시 → 경로 → 표시(핀·점) → 건물 이름 → 출처.

## Review Focus

1. **시연장 인터넷이 없거나 느릴 때** 지도 탭이 그대로 그려져야 한다 → Task 3 테스트 `지도 탭은 그림 조각 없이 그리고, 조사 탭만 그림 조각을 쓴다`.
2. **탭을 지도→조사→지도로 바꿔도** 보던 자리가 그대로고, 조사 탭에는 그림 조각이 다시 나와야 한다 → 같은 테스트에서 카메라 중심 비교.
3. **계단 표시가 새 흰 길 밑에 묻히면** 안전 정보가 사라진다 → Task 3 테스트 `계단 표시는 길보다 위에 그린다`.
4. **목적지 이름이 아주 길 때** 말풍선이 넘쳐 노란 줄 오류가 나면 안 된다 → Task 1 테스트 `목적지 이름이 길어도 핀이 넘치지 않는다`.
5. **`assets/buildings.json`이 잘못돼 건물이 비어 있어도**(`main.dart`가 빈 목록으로 연다) 길·이름은 그려져야 한다 → Task 3 테스트들이 건물 없이(`open()` 기본값) 돈다.

---

### Task 1: 함께 쓰는 층과 표시를 D 모습으로 (안내 화면)

**Files:**
- Modify: `lib/guidance_map.dart`
- Test: `test/guidance_map_test.dart`

**Interfaces:**
- Consumes: `Graph`(`graph.edges`, `graph.nodes`, `Edge.kind`), `Kind.stairs`, `overlayLines`, `routeLines`, `routeMarkers`(Task 2에서 모양만 바뀜, 이름 그대로).
- Produces (모두 `lib/guidance_map.dart`, Task 3이 씀):
  - `const mapBackground = Color(0xFFF3F4F6);`
  - `List<Widget> campusLayers(Graph graph, List<List<LatLng>> buildings)` — `[그림자 PolygonLayer, 건물 PolygonLayer, 길 PolylineLayer]`
  - `class StartDot extends StatelessWidget` (`const StartDot()`), 마커 크기 22×22
  - `class DestPin extends StatelessWidget` (`const DestPin(this.name)`), 마커 크기 160×80, `alignment: Alignment.topCenter`
  - `class MeDot extends StatelessWidget` (`const MeDot()`), 마커 크기 44×44, 안에 `Semantics(label: '내 위치')`
  - `NameLayer(places: ...)` — 이름 그대로, 글자 모양만 바뀜

- [ ] **Step 1: 실패하는 테스트 쓰기** (`test/guidance_map_test.dart`)

첫 테스트(`17 지도가 돌아가 있어도…`)에 덧붙이기 — 바탕·길·건물·이름 모양:

```dart
final opts = t.widget<FlutterMap>(find.byType(FlutterMap)).options;
expect(opts.backgroundColor, const Color(0xFFF3F4F6));
final roads = t.widgetList<PolylineLayer>(find.byType(PolylineLayer)).first.polylines;
expect(roads.first.color, const Color(0xFFFFFFFF));
expect(roads.first.strokeWidth, 5);
expect(roads.first.strokeWidth + roads.first.borderStrokeWidth, 8);
expect(roads.first.borderColor, const Color(0xFFE1E4E8));
final polys = t.widgetList<PolygonLayer>(find.byType(PolygonLayer)).toList();
expect(polys[0].polygons.single.color, const Color(0xFFC3C8D0)); // 그림자가 먼저(아래)
expect(polys[1].polygons.single.color, const Color(0xFFD9DDE4));
expect(polys[1].polygons.single.borderColor, const Color(0xFFB8BEC8));
final label = t.widget<Text>(find.text('정문')).style!;
expect(label.color, const Color(0xFF4A4F57));
expect(label.fontWeight, FontWeight.w700);
expect(label.shadows, isNotEmpty);
```

새 테스트 `목적지 이름은 핀에 한 번만 보인다`: 첫 테스트와 같은 `GuidanceMap`(dest `c.places[1]` = 도서관), `position: m(0, 290)`(도서관 근처라 화면 안), heading 0.

```dart
expect(find.descendant(of: find.byType(DestPin), matching: find.text('도서관')), findsOneWidget);
expect(find.text('도서관'), findsOneWidget);
expect(find.byType(MeDot), findsOneWidget);
expect(find.bySemanticsLabel('내 위치'), findsOneWidget);
```

새 테스트 `목적지 이름이 길어도 핀이 넘치지 않는다`: dest를 `Place('가' * 40, m(0, 10))`로, `position: m(0, 0)`.

```dart
expect(t.takeException(), isNull);
expect(t.getSize(find.byType(DestPin)).width, lessThanOrEqualTo(160));
```

둘째 테스트(`세로 화면에서…`)는 목적지가 이제 이름 층에서 빠지므로 뜻을 지키게 바꾼다: `dest: c.places[1]`, `position: m(100, 0)`(정문 m(0,0)이 지나온 쪽 100m 뒤), `expect(find.text('정문'), findsOneWidget)`.

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/guidance_map_test.dart`
Expected: FAIL (`DestPin`/`MeDot` 없음, 색 불일치)

- [ ] **Step 3: 구현** (`lib/guidance_map.dart`)

- `_labelStyle`: `fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4A4F57)`, `shadows`: 흰색 `Shadow` 네 개(offset ±1, ±1, blurRadius 0) + 하나(blurRadius 2).
- `campusLayers`: 그림자 다각형은 각 점을 동쪽·남쪽으로 1.5m 민 것(`LatLng(lat - 1.5 / 110574, lng + 1.5 / (111320 * cos(lat 라디안)))`, `dart:math`의 `cos`·`pi`). 건물 `borderStrokeWidth: 1`. 길은 `e.kind != Kind.stairs`인 이음선마다 `Polyline(points: [a, b], strokeWidth: 5, color: 흰, borderStrokeWidth: 3, borderColor: 0xFFE1E4E8)` — 끝·꺾임은 flutter_map 기본값이 이미 둥글다.
- `StartDot`: 흰 원, 파란(`0xFF2A7DE1`) 테두리 4.
- `MeDot`: 44 크기 옅은 파란 원(`0xFF2A7DE1`, 불투명도 0.18) 가운데에 18 크기 파란 점 + 흰 테두리 3. `IgnorePointer` + `Semantics(label: '내 위치')`.
- `DestPin`: 세로로 [빨간(`0xFFC0392B`) 둥근 말풍선 안 흰 굵은 글자 13, 최대 너비 150, `maxLines: 1`, `overflow: TextOverflow.ellipsis`] + [`Icons.location_on` 36 빨강]. `IgnorePointer`.
- `GuidanceMap`: `backgroundColor: mapBackground`, 앞의 `PolygonLayer`·길 `PolylineLayer`를 `...campusLayers(graph, buildings)`로, 도착 마커는 `Marker(width: 160, height: 80, alignment: Alignment.topCenter, child: DestPin(dest.name))`, 내 위치 마커는 `Marker(width: 44, height: 44, child: const MeDot())`, `NameLayer(places: [for (final p in campus.places) if (p != dest) p])`.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/guidance_map_test.dart test/guidance_screen_test.dart`
Expected: 모두 PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/guidance_map.dart test/guidance_map_test.dart
git commit -m "feat: 안내 화면 지도를 연회색 바탕·흰 길·회색 건물로"
```

---

### Task 2: 경로 선을 흰 밑선 위 초록으로

**Files:**
- Modify: `lib/route_tab.dart:8` (색 상수), `lib/route_tab.dart:33-61` (`routeLines`)
- Test: `test/route_tab_test.dart`

**Interfaces:**
- Produces: `List<Polyline> routeLines(RouteResult r)` — 이름 그대로. 맨 앞이 경로 전체를 잇는 흰 밑선 하나, 그 뒤가 구간별 색 선. 빈 경로(`legs` 없음)면 빈 목록.

- [ ] **Step 1: 실패하는 테스트 쓰기** (`test/route_tab_test.dart`)

`경로 선은 흰 밑선 위에 초록, 가파른 곳은 주황 끊긴 선`: 이 파일의 `route()` 도우미로 가파른 구간이 섞인 경로를 만든다(같은 파일의 `경고 문구` 테스트가 쓰는 기록·기울기 그대로).

```dart
final lines = routeLines(r);
expect(lines.first.color, Colors.white);
expect(lines.first.strokeWidth, 12);
expect(lines.first.points.first, r.legs.first.a);
expect(lines.first.points.last, r.legs.last.b);
final rest = lines.skip(1);
expect(rest.every((l) => l.strokeWidth == 7), isTrue);
expect(rest.map((l) => l.color).toSet(), {const Color(0xFF12A150), const Color(0xFFF59F00)});
expect(rest.firstWhere((l) => l.color == const Color(0xFFF59F00)).pattern.segments, isNotNull); // 끊긴 선
expect(rest.firstWhere((l) => l.color == const Color(0xFF12A150)).pattern, const StrokePattern.solid());
```

(완만한 구간만으로는 초록이 나오지 않으면, 같은 파일에서 일부만 가파른 경로를 만드는 기존 방식을 따른다.)

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/route_tab_test.dart`
Expected: FAIL (첫 선이 흰색이 아님)

- [ ] **Step 3: 구현**

`_green = Color(0xFF12A150)`, `_orange = Color(0xFFF59F00)`. `routeLines`: 맨 앞에 `Polyline(points: [legs.first.a, ...legs.map((l) => l.b)], strokeWidth: 12, color: Colors.white)`, 구간 선 `strokeWidth: 7`. 가파른 끊긴 선 모양 `[14, 8]`은 그대로(끝은 기본값이 둥글다). `routeMarkers`는 `_orange`를 쓰므로 색만 따라 바뀐다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test`
Expected: 모두 PASS

- [ ] **Step 5: 커밋**

```bash
git add lib/route_tab.dart test/route_tab_test.dart
git commit -m "feat: 경로를 흰 밑선 위 초록 선으로, 가파른 곳은 주황"
```

---

### Task 3: 지도 탭도 직접 그리기 (조사 탭은 그대로)

**Files:**
- Modify: `lib/main.dart:445-563` (`FlutterMap` 부분)
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: Task 1의 `mapBackground`, `campusLayers`, `StartDot`, `DestPin`, `MeDot`, `NameLayer`. `HomePage`에 이미 있는 `widget.buildings`.

- [ ] **Step 1: 실패하는 테스트 쓰기** (`test/widget_test.dart`)

`open()`에 `List<SurveyRecord> bundled = const []` 매개변수를 더해 `App(bundled: bundled)`로 넘긴다.

`지도 탭은 그림 조각 없이 그리고, 조사 탭만 그림 조각을 쓴다`:

```dart
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
```

`계단 표시는 길보다 위에 그린다`:

```dart
await open(t, bundled: [rec(Kind.stairs, m(40, 0), m(60, 0))]);
final kids = t.widget<FlutterMap>(find.byType(FlutterMap)).children;
int at(bool Function(Polyline) f) =>
    kids.indexWhere((w) => w is PolylineLayer && w.polylines.any(f));
final roads = at((p) => p.borderStrokeWidth > 0);
final stairs = at((p) => p.color == kindStyle(Kind.stairs).color);
expect(roads, greaterThanOrEqualTo(0));
expect(stairs, greaterThan(roads));
```

`목적지를 고르면 핀에 이름이 나오고 출발점은 동그라미다`: 테스트 `위치를 모르면 출발지를 고르게 하고…`(`widget_test.dart:94-102`)와 같은 순서로 도착 도서관·출발 정문을 고른 뒤

```dart
expect(find.descendant(of: find.byType(DestPin), matching: find.text('도서관')), findsOneWidget);
expect(find.byType(StartDot), findsOneWidget);
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/widget_test.dart`
Expected: 새 테스트 셋 FAIL (지도 탭에 `TileLayer`가 있음)

- [ ] **Step 3: 구현** (`lib/main.dart`)

- `MapOptions`에 `backgroundColor: survey ? const Color(0xFFE0E0E0) : mapBackground` (`0xFFE0E0E0`은 flutter_map 기본값).
- children 맨 앞: `if (survey) TileLayer(...지금 그대로...) else ...campusLayers(_graph, widget.buildings)`.
- 출발 마커 `Icon(Icons.trip_origin)` → `Marker(width: 22, height: 22, child: const StartDot())`.
- 도착 마커 → `Marker(width: 160, height: 80, alignment: Alignment.topCenter, child: DestPin(dest.name))`.
- 내 위치 마커 → `Marker(width: 44, height: 44, child: const MeDot())`.
- `MarkerLayer` 뒤, 출처 앞에 `if (!survey) NameLayer(places: [for (final p in _campus.places) if (!showRoute || p != dest) p])`.
- `HomePage.buildings`·`App.buildings` 주석의 "안내 화면에 그리는"을 "지도 탭·안내 화면에 그리는"으로.

- [ ] **Step 4: 통과 확인**

Run: `flutter test`
Expected: 모두 PASS. 기존 테스트가 지도 위 건물 이름 때문에 `find.text('정문'/'도서관')`를 둘 찾아 깨지면, 고르는 창 안으로 범위를 좁혀 고친다(`pick()`은 이미 `.last`라 괜찮다).

- [ ] **Step 5: 커밋**

```bash
git add lib/main.dart test/widget_test.dart
git commit -m "feat: 지도 탭을 그림 조각 없이 직접 그리기, 조사 탭은 그대로"
```

---

### Task 4: 실제 화면 확인과 사용 설명 고치기

**Files:**
- Modify: `README.md:181`, `README.md:198`

- [ ] **Step 1: 웹으로 띄워 네 화면을 찍는다**

Run: `flutter build web && python3 -m http.server -d build/web 8080` (뒤에서 실행)
Chrome 확장이 연결돼 있으면 그쪽으로, 아니면 headless Chrome으로 찍는다. 찍을 것:
1. 지도 탭 처음 화면(확대 14~16): 연회색 바탕, 흰 길, 회색 건물+그림자, 이름이 겹치지 않음, 계단 빨간 점선이 보임
2. 목적지·출발지 고른 뒤: 초록 경로·흰 밑선, 출발 동그라미, 빨간 핀+이름
3. 미리 보기(안내 화면): 같은 모습, 지도가 돌아도 이름·핀이 바로 섬
4. 조사 탭: 오픈스트리트맵 바탕 그대로

Expected: 위 항목이 다 맞다. 확대 14에서 길이 너무 빽빽하면 `campusLayers`에 확대 단계별 굵기를 더하고 Task 3 테스트를 다시 돌린다.

- [ ] **Step 2: README 고치기**

- 181줄 준비 목록: "인터넷이 됩니다 (지도 그림은 인터넷으로 받아 옵니다)" → 지도 탭·안내 화면은 인터넷 없이도 보이고, **조사 탭** 바탕만 인터넷이 필요하다는 뜻으로.
- 198줄: "지도 그림은 인터넷이 있어야 보입니다…(안내 화면의 지도는 인터넷 없이도 보입니다.)" → 같은 뜻으로. 199줄 공개 서버 설명은 "조사 탭 바탕은"으로 시작하게.

- [ ] **Step 3: 전체 확인**

Run: `flutter analyze && dart format --set-exit-if-changed lib test && flutter test`
Expected: 문제 0개, 고칠 형식 없음, 모든 테스트 PASS

- [ ] **Step 4: 커밋**

```bash
git add README.md
git commit -m "docs: 지도 탭은 인터넷 없이도 보인다고 고치기"
```
