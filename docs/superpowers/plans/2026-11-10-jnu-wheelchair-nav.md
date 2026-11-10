# 제주대 휠체어 길 안내 앱 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 제주대 아라캠퍼스에서 계단을 지나지 않고 급경사를 경고하는 휠체어 길 안내 앱(지도 탭 + 조사 탭)을 Flutter 코드 한 벌로 iOS·Android·웹에서 돌아가게 만든다.

**Architecture:** 서버 없음. 길·장소·높이는 개발 컴퓨터에서 한 번 내려받아 `assets/campus.json`으로 앱에 넣는다. 조사 기록은 휴대폰 저장분과 앱 내장분(`assets/survey.json`)을 합쳐 쓴다. 기록이 바뀔 때마다 순수 Dart로 길 그물망(`Graph`)을 다시 만들고 Dijkstra로 비용이 가장 적은 길을 찾는다. 화면은 지도 한 장을 두 탭이 같이 쓰는 한 페이지다.

**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5, flutter_map 8.3.2, latlong2 0.10.1, geolocator 14.1.2, shared_preferences 2.5.6, share_plus 13.3.1.

**Spec:** `docs/superpowers/specs/2026-11-10-jnu-wheelchair-nav-design.md`

## Global Constraints

- 외부 패키지는 위 다섯 개만 쓴다. 더 필요해 보이면 직접 몇 줄로 쓴다.
- 앱 식별자는 `kr.jnucapstone3.jnu_wheel_nav`(iOS는 `kr.jnucapstone3.jnuWheelNav`)로 고정한다. 조사자 휴대폰에 설치한 뒤 바꾸면 다른 앱이 되어 기록이 보이지 않는다.
- 저장 열쇠 `survey_records`와 기록 JSON 형식(`kind`, `a`, `b`, `time`)은 한 번 정한 뒤 바꾸지 않는다.
- 조정 가능한 값은 모두 `lib/model.dart` 상수 한 곳에 둔다: 가파름 기준 수동 8% 초과·전동 12% 초과, 가파른 조각 비용 10배, 경사로 비용 0.9배, 엘리베이터 비용 50m·60초, 속도 수동 3km/h·전동 4km/h, 붙는 거리 15m.
- 계단 조각은 어떤 경우에도 경로에 들어가지 않는다.
- 화면 글자는 한국어. 설계서 문구는 그대로 쓴다: "휠체어로 갈 수 있는 길을 찾지 못했습니다", "도움이 필요할 수 있습니다", "기울기는 추정값입니다", "조사자가 급경사로 표시", "계단 없음".
- 누르는 대상은 48px 이상, 아이콘만 있는 버튼에는 `tooltip`(화면 읽기 프로그램용 이름)을 붙인다. 색만으로 구분하지 않는다(선 모양·아이콘을 함께 쓴다).
- 지도 그림은 `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, 화면에 "© OpenStreetMap contributors" 표기.
- 내려받기 요청의 User-Agent는 `wheel-nav-fetch/1.0`. 개인 정보는 넣지 않는다.
- 조사가 시작된 뒤에는 `tool/fetch_campus.dart`를 다시 돌려 길 자료를 바꾸지 않는다(기록이 붙은 자리가 어긋난다).
- 각 Task 끝에서 `flutter analyze`가 "No issues found!"여야 하고, 그 뒤 커밋한다.
- 설계서 7절 순서와 다른 점 하나: 길·높이 자료 변환(Task 2)을 조사 탭(Task 4)보다 먼저 한다. 조사 탭의 "길에 붙기"가 길 자료를 필요로 하기 때문이다.

## Review Focus

설계서가 직접 말하지 않지만 실제 사용에서 만날 가능성이 높은 것. 각 줄의 테스트는 괄호 안 Task에 들어 있다.

1. 휴대폰에 저장된 기록 문자열이 깨져 있다 → 지우지 않고 `survey_records_corrupt_<밀리초>` 열쇠로 옮겨 두고 앱은 빈 목록으로 뜬다. (Task 1)
2. 같은 길이 두 번 기록된 곳(겹친 길)에 계단을 표시한다 → 겹친 길이 모두 막힌다. (Task 3)
3. 계단 바로 옆에 경사로가 기록되어 있다 → 경사로는 막히지 않는다. (Task 3)
4. 위치 권한 거부·위치 기능 없음·캠퍼스 밖 → 앱이 멈추지 않고 "출발지를 골라 주세요"가 뜬다. (Task 6)
5. 출발지와 목적지가 같은 곳이거나 길이 하나도 없다 → 오류 없이 0m 결과 또는 "찾지 못함". (Task 5)

## File Structure

| 파일 | 맡은 일 |
|---|---|
| `lib/model.dart` | 종류(`Kind`), 조사 기록, 장소, 캠퍼스 자료(높이 포함), 조정값 상수, 거리 계산 |
| `lib/store.dart` | 조사 기록을 휴대폰에 저장·읽기·내보내기 |
| `lib/graph.dart` | 길 그물망 만들기, 누른 점 붙이기, 계단·급경사 얹기, 최단 경로 탐색 |
| `lib/route.dart` | 휠체어 종류별 비용, 길 찾기 결과(거리·시간·경고) |
| `lib/main.dart` | 앱 시작, 지도 한 장과 두 탭을 묶는 화면 상태 |
| `lib/survey_tab.dart` | 조사 탭의 종류 고르기 줄, 아래 줄, 기록 그리기 |
| `lib/route_tab.dart` | 지도 탭의 검색·출발지 고르기, 경로 그리기, 요약·경고 상자 |
| `tool/fetch_campus.dart` | 오픈스트리트맵·높이 자료를 내려받아 `assets/campus.json`을 만드는 스크립트 |
| `assets/campus.json`, `assets/survey.json` | 내장 자료(길·장소·높이), 내장 조사 기록(처음엔 `[]`) |
| `test/*.dart` | 아래 각 Task의 테스트. `test/helpers.dart`는 테스트 공용 도구 |
| `README.md` | 실행·설치·조사·합치기 안내(비전공자가 따라 할 수 있는 단계) |

---

### Task 1: 프로젝트 뼈대, 조사 기록 모델, 휴대폰 저장

**Files:**
- Create: Flutter 프로젝트(명령으로 생성), `lib/model.dart`, `lib/store.dart`, `test/helpers.dart`, `test/model_test.dart`, `test/store_test.dart`
- Modify: `.gitignore`, `pubspec.yaml`
- Delete: `test/widget_test.dart`(기본으로 생기는 카운터 테스트. Task 4에서 새로 만든다)

**Interfaces:**
- Produces (`lib/model.dart`):
  - `enum Kind { road, stairs, ramp, elevator, newPath, steep }` + `String get label` → 길 / 계단 / 경사로 / 엘리베이터 / 새 길 / 급경사
  - `const surveyKinds = [Kind.stairs, Kind.ramp, Kind.elevator, Kind.newPath, Kind.steep];`
  - `class SurveyRecord { const SurveyRecord(this.kind, this.a, this.b, this.time); final Kind kind; final LatLng a, b; final DateTime time; }` — `toJson()`, `SurveyRecord.fromJson(Map<String, dynamic>)`, 네 값이 모두 같으면 `==`
  - `String encodeRecords(List<SurveyRecord> r)`, `List<SurveyRecord> decodeRecords(String json)` — 형식이 틀리면 종류를 가리지 않고 `FormatException`
  - `Point<double> xy(LatLng p)` — 원점 (33.4555, 126.5625) 기준 동쪽(x)·북쪽(y) 미터. x = Δ경도 × 111320 × cos(33.4555°), y = Δ위도 × 110574
  - `double meters(LatLng a, LatLng b)` — `xy` 평면 거리
  - 상수: `steepManual = 0.08`, `steepPowered = 0.12`, `steepCostFactor = 10.0`, `rampCostFactor = 0.9`, `elevatorCostMeters = 50.0`, `elevatorSeconds = 60`, `speedManualKmh = 3.0`, `speedPoweredKmh = 4.0`, `snapMeters = 15.0`, `overlayMeters = 3.0`, `overlayDetour = 1.5`, `pieceMeters = 30.0`, `smoothPasses = 1`, `placeTapMeters = 60.0`
- Produces (`lib/store.dart`): `Future<List<SurveyRecord>> loadRecords()`, `Future<void> saveRecords(List<SurveyRecord> r)` — `SharedPreferences.getInstance()`의 문자열 열쇠 `survey_records` 하나에 `encodeRecords` 결과를 저장
- Produces (`test/helpers.dart`): `LatLng m(double x, double y)`(원점에서 동 x m·북 y m인 점, `xy`의 반대), `SurveyRecord rec(Kind k, LatLng a, LatLng b)`(시각은 `DateTime.utc(2026, 11, 12)`), `double flat(LatLng _) => 0`

기록 한 건의 JSON: `{"kind":"stairs","a":[33.4555,126.5625],"b":[33.4556,126.5626],"time":"2026-11-12T03:04:05.000Z"}`

- [ ] **Step 1: 뼈대 만들기**

```bash
cd Jeju-National-University-Campus-Barrier-Free-App
git init
flutter create --org kr.jnucapstone3 --project-name jnu_wheel_nav --platforms ios,android,web .
flutter pub add flutter_map:^8.3.2 latlong2:^0.10.1 geolocator:^14.1.2 shared_preferences:^2.5.6 share_plus:^13.3.1
rm test/widget_test.dart
echo ".superpowers/" >> .gitignore
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 2: 실패하는 테스트 쓰기**

`test/model_test.dart`:
```dart
test('기록은 JSON으로 갔다가 돌아와도 같다', () {
  final r = SurveyRecord(Kind.stairs, m(0, 0), m(10, 0), DateTime.utc(2026, 11, 12, 3, 4, 5));
  expect(decodeRecords(encodeRecords([r])), [r]);
  expect(encodeRecords([r]), contains('"kind":"stairs"'));
  expect(encodeRecords([r]), contains('"time":"2026-11-12T03:04:05.000Z"'));
});
test('meters는 평면 거리', () => expect(meters(m(0, 0), m(30, 40)), closeTo(50, 0.01)));
test('형식이 틀리면 FormatException', () {
  expect(() => decodeRecords('not json'), throwsFormatException);
  expect(() => decodeRecords('{"x":1}'), throwsFormatException);
  expect(() => decodeRecords('[{"kind":"lava","a":[1,2],"b":[1,2],"time":"x"}]'), throwsFormatException);
});
```

`test/store_test.dart`:
```dart
final r = rec(Kind.newPath, m(0, 0), m(10, 0));
test('저장한 기록을 다시 읽는다', () async {
  SharedPreferences.setMockInitialValues({});
  await saveRecords([r]);
  expect(await loadRecords(), [r]);
});
test('깨진 저장값은 지우지 않고 옮겨 둔다', () async {            // Review Focus 1
  SharedPreferences.setMockInitialValues({'survey_records': 'not json'});
  expect(await loadRecords(), isEmpty);
  final p = await SharedPreferences.getInstance();
  final kept = p.getKeys().where((k) => k.startsWith('survey_records_corrupt_'));
  expect(kept.map(p.getString), ['not json']);
});
```

- [ ] **Step 3: 실패 확인** — Run: `flutter test` · Expected: FAIL (`model.dart`, `store.dart` 없음)
- [ ] **Step 4: `lib/model.dart`, `lib/store.dart`, `test/helpers.dart` 구현** — 위 Interfaces 그대로. `loadRecords`는 `decodeRecords`가 `FormatException`을 던지면 원래 문자열을 `survey_records_corrupt_${DateTime.now().millisecondsSinceEpoch}`에 저장하고 빈 목록을 돌려준다.
- [ ] **Step 5: 통과 확인** — Run: `flutter test && flutter analyze` · Expected: 5개 통과, `No issues found!`
- [ ] **Step 6: 커밋** — `git add -A && git commit -m "feat: 프로젝트 뼈대와 조사 기록 모델·저장"`

---

### Task 2: 캠퍼스 자료 (길·장소·높이)

**Files:**
- Create: `tool/fetch_campus.dart`, `assets/campus.json`(스크립트가 만듦), `assets/survey.json`(내용 `[]`), `test/campus_test.dart`
- Modify: `lib/model.dart`(`Place`, `Campus`, `smooth` 추가), `pubspec.yaml`(`assets: [assets/campus.json, assets/survey.json]`)

**Interfaces:**
- Produces (`lib/model.dart`):
  - `class Place { const Place(this.name, this.at); final String name; final LatLng at; }`
  - `class Campus` — `final List<Place> places; final List<LatLng> nodes; final List<(int, int)> edges; final double south, west, north, east;`
    - `factory Campus.fromJson(Map<String, dynamic> j, {int passes = smoothPasses})` — 높이 격자에 `smooth`를 `passes`번 적용
    - `double elevationAt(LatLng p)` — 격자 네 점 사이를 이중선형 보간. 격자 밖은 가장자리 값
    - `bool contains(LatLng p)` — `south..north`, `west..east` 상자 안인지
  - `List<double> smooth(List<double> data, int rows, int cols)` — 각 칸을 자기와 이웃(격자 안에 있는 것만, 최대 9칸)의 평균으로 바꾼 새 목록

`assets/campus.json` 형식 (`data`는 남쪽 줄부터, 줄 안에서는 서쪽부터, 단위 m):
```json
{"bounds":[남,서,북,동],
 "places":[["정문",33.4592796,126.5611458],["중앙도서관",33.4526623,126.5608672]],
 "nodes":[[위도,경도]], "edges":[[0,1]],
 "elev":{"south":33.4477778,"west":126.5527778,"step":0.0002777778,"rows":56,"cols":71,"data":[0]}}
```

`tool/fetch_campus.dart`가 정하는 것 (`dart:io`, `dart:convert`, `dart:math`만 사용):
- Overpass 주소를 이 순서로 시도, 각 120초 제한: `https://overpass-api.de/api/interpreter`, `https://overpass.kumi.systems/api/interpreter`, `https://overpass.private.coffee/api/interpreter`. POST 본문 `data=<질의>`.
- 질의:
  ```
  [out:json][timeout:90];
  (way(369649909);
   way[highway~"^(secondary|tertiary|unclassified|residential|living_street|service)(_link)?$"](33.448,126.553,33.463,126.572);
   nwr[building][name](33.448,126.553,33.463,126.572););
  out geom;
  ```
- 캠퍼스 경계 = way 369649909의 `geometry`. `bounds` = 그 다각형의 바깥 상자.
- 길: 각 way의 이웃한 두 점을 조각 하나로. **두 끝점이 모두 경계 다각형 안**인 조각만 남긴다. 점은 OSM 노드 번호(`nodes`)로 같은 점을 알아보고, 남은 조각이 쓰는 점만 0부터 번호를 다시 매긴다.
- 장소: 이름 있는 건물의 `bounds` 가운데 점이 경계 다각형 안인 것만. 맨 앞에 `["정문", 33.4592796, 126.5611458]`(OSM 노드 4655302248)을 손으로 추가.
- 높이: 격자 `south = 33 + 1612/3600`, `west = 126 + 1990/3600`, `step = 1/3600`, 56줄 × 71칸(3,976점). `https://api.opentopodata.org/v1/srtm30m?locations=위도,경도|…`로 100점씩, 요청 사이 1.1초 쉼. 값이 `null`이면 오류로 끝낸다.
- 좌표는 소수 7자리로 반올림. 끝나면 장소·점·조각 수와 정문·중앙도서관 높이를 출력.

- [ ] **Step 1: 실패하는 테스트 쓰기** — `test/campus_test.dart`:
```dart
Map<String, dynamic> grid(int rows, int cols, List<num> data) => {
  'bounds': [33.0, 126.0, 33.1, 126.1], 'places': [], 'nodes': [], 'edges': [],
  'elev': {'south': 33.0, 'west': 126.0, 'step': 0.001, 'rows': rows, 'cols': cols, 'data': data}};

test('elevationAt은 격자 사이를 고르게 잇고 밖에서는 가장자리 값', () {
  final c = Campus.fromJson(grid(2, 2, [0, 10, 20, 30]), passes: 0);
  expect(c.elevationAt(const LatLng(33.0, 126.0)), closeTo(0, 1e-6));
  expect(c.elevationAt(const LatLng(33.0005, 126.0005)), closeTo(15, 1e-6));
  expect(c.elevationAt(const LatLng(34, 127)), closeTo(30, 1e-6));
});
test('smooth는 이웃 평균', () {
  final s = smooth([0, 0, 0, 0, 9, 0, 0, 0, 0], 3, 3);
  expect(s[4], closeTo(1, 1e-9));      // 가운데: 9칸 평균
  expect(s[0], closeTo(2.25, 1e-9));   // 모서리: 4칸 평균
});
test('내장 자료가 설계서와 맞는다', () {
  final c = Campus.fromJson(jsonDecode(File('assets/campus.json').readAsStringSync()));
  final gate = c.places.firstWhere((p) => p.name == '정문');
  final lib = c.places.firstWhere((p) => p.name == '중앙도서관');
  expect(c.places.length, inInclusiveRange(40, 70));                     // 설계서: 약 60곳
  expect(c.places.every((p) => c.contains(p.at)), isTrue);
  expect(c.places.map((p) => p.name), isNot(contains('카카오본사 다음스페이스닷원')));
  expect(c.edges.length, greaterThan(150));
  expect(c.edges.every((e) => e.$1 < c.nodes.length && e.$2 < c.nodes.length), isTrue);
  expect(c.elevationAt(lib.at) - c.elevationAt(gate.at), inInclusiveRange(35, 75));   // 설계서: 약 56m
});
```
- [ ] **Step 2: 실패 확인** — Run: `flutter test test/campus_test.dart` · Expected: FAIL (`Campus` 없음)
- [ ] **Step 3: `Place`, `Campus`, `smooth` 구현** — 앞의 두 테스트 통과 확인
- [ ] **Step 4: `tool/fetch_campus.dart` 작성 후 실행** — Run: `dart run tool/fetch_campus.dart` · Expected: 장소 40~70, 조각 150 이상 출력, `assets/campus.json` 생성(약 1~2분)
- [ ] **Step 5: `assets/survey.json`(`[]`) 만들고 `pubspec.yaml`에 자산 등록**
- [ ] **Step 6: 통과 확인** — Run: `flutter test && flutter analyze` · Expected: 모두 통과
- [ ] **Step 7: 커밋** — `git add -A && git commit -m "feat: 캠퍼스 길·장소·높이 자료와 변환 스크립트"`

---

### Task 3: 길 그물망

**Files:**
- Create: `lib/graph.dart`, `test/graph_test.dart`

**Interfaces:**
- Consumes: Task 1의 `Kind`, `SurveyRecord`, `xy`, `meters`, 상수
- Produces (`lib/graph.dart`):
  - `class Edge { final int a, b; Kind kind; final double meters, grade; }` — `grade`는 |높이 차| ÷ 길이(0.10 = 10%)
  - `class Graph` — `final List<LatLng> nodes; final List<Edge> edges; final Set<SurveyRecord> unapplied;`
    - `({int edge, double t, LatLng point, double meters})? nearest(LatLng p, {bool Function(Edge)? where})`
    - `LatLng snap(LatLng p, Kind kind)` — 조사 탭이 누른 점에 쓴다
    - `int attach(LatLng p, {double maxMeters = snapMeters, bool Function(Edge)? where})` — 점 번호
  - `Graph buildGraph(List<LatLng> nodes, List<(int, int)> edges, List<SurveyRecord> records, double Function(LatLng) elevationAt)`
  - `List<int>? shortestPath(Graph g, int from, int to, double? Function(Edge) cost, {double maxCost = double.infinity})` — 조각 번호를 `from`에서 `to` 순서로. `cost`가 `null`이면 지나갈 수 없는 조각. 길이 없으면 `null`, `from == to`면 `[]`
  - `bool overlayable(Kind k) => k != Kind.ramp && k != Kind.elevator;`

**규칙 (시그니처와 테스트만으로 정해지지 않는 부분):**

1. 조각 추가: 엘리베이터는 한 조각, `grade` 0. 그 외는 길이를 `ceil(길이 / pieceMeters)`등분해 사이 점을 넣고, 조각마다 `grade = |elevationAt(a) − elevationAt(b)| / 길이`(길이 0.01m 미만이면 0).
2. `nearest`: `xy` 평면에서 각 조각에 내린 수선의 발(t는 0~1로 자름) 중 가장 가까운 것. 엘리베이터 조각은 t를 0 또는 1로 반올림한다(양 끝에만 붙는다).
3. `attach`: `nearest`가 `maxMeters` 안이면, 그 점이 조각 끝에서 0.5m 안일 때 그 끝 점을, 아니면 조각을 그 자리에서 둘로 쪼개고(종류 유지, `grade` 다시 계산) 새 점을 돌려준다. 안에 없으면 `p`에 홀로 선 점을 추가한다.
4. `snap(p, kind)`: 계단·급경사는 `where: overlayable(e.kind)`인 조각만, 나머지 종류는 모든 조각을 대상으로 `nearest`. `snapMeters` 안이면 그 점, 아니면 `p` 그대로.
5. `buildGraph` 순서: ① 내장 길을 `Kind.road`로 추가 → ② 새 길·경사로·엘리베이터 기록을 목록 순서대로 `attach(a)`, `attach(b)` 사이에 조각 추가 → ③ 급경사 기록 → ④ 계단 기록. ③④는 아래 "얹기"로 처리한다(계단이 맨 마지막이라 어떤 순서로 기록했든 계단이 이긴다).
6. 얹기(기록 r):
   ```
   ok(e) = overlayable(e.kind) && e.kind != r.kind
   되풀이:
     r.a, r.b 각각 nearest(where: ok)가 overlayMeters(3m) 안에 없으면 끝
     ia = attach(r.a, maxMeters: overlayMeters, where: ok), ib도 같게;  ia == ib면 끝
     path = shortestPath(g, ia, ib, (e) => ok(e) ? e.meters : null,
                         maxCost: overlayDetour * meters(nodes[ia], nodes[ib]) + 1)
     path가 null이면 끝;  path의 모든 조각의 kind를 r.kind로 바꿈
   한 번도 바꾸지 못했으면 unapplied에 r 추가
   ```
   되풀이하는 이유: 같은 자리에 겹쳐 기록된 길을 하나만 막으면 나머지로 계단을 지나가게 된다.
7. `shortestPath`: Dijkstra. 이웃 목록은 부를 때마다 만든다. 가장 작은 임시 비용이 `maxCost`를 넘으면 멈춘다. 점이 수천 개 수준이라 최솟값은 단순 훑기로 찾고, `// ponytail: O(n²) Dijkstra, 점이 1만 개를 넘으면 힙으로 교체` 주석을 남긴다.

- [ ] **Step 1: 실패하는 테스트 쓰기** — `test/graph_test.dart`:
```dart
Graph line(List<SurveyRecord> r) => buildGraph([m(0, 0), m(100, 0)], [(0, 1)], r, flat);
// y=0 직선 위에서 가운데 x가 x0~x1 사이인 조각
Iterable<Edge> between(Graph g, double x0, double x1) => g.edges.where((e) {
  final a = xy(g.nodes[e.a]), b = xy(g.nodes[e.b]), x = (a.x + b.x) / 2;
  return a.y.abs() < 1 && b.y.abs() < 1 && x > x0 && x < x1;
});
double? walk(Edge e) => e.kind == Kind.stairs ? null : e.meters;
List<int>? endToEnd(Graph g) => shortestPath(g, g.attach(m(0, 0)), g.attach(m(100, 0)), walk);

test('긴 길은 30m 이하 조각으로 나뉜다', () {
  final g = line([]);
  expect(g.edges.length, 4);
  expect(g.edges.every((e) => e.meters <= pieceMeters + 0.01), isTrue);
});
test('누른 점은 15m 안의 길에 붙고 더 멀면 그대로다', () {
  final g = line([]);
  expect(meters(g.snap(m(50, 14), Kind.newPath), m(50, 0)), lessThan(0.01));
  expect(g.snap(m(50, 16), Kind.newPath), m(50, 16));
});
test('확인 항목 7: 길 위의 계단 기록은 그 구간만 막는다', () {
  final g = line([rec(Kind.stairs, m(40, 0), m(60, 0))]);
  expect(between(g, 40, 60), isNotEmpty);
  expect(between(g, 40, 60).every((e) => e.kind == Kind.stairs), isTrue);
  expect(between(g, 0, 40).followedBy(between(g, 60, 100)).every((e) => e.kind == Kind.road), isTrue);
  expect(g.unapplied, isEmpty);
  expect(endToEnd(g), isNull);
});
test('길에서 떨어진 계단 기록은 표시만 한다', () {
  final s = rec(Kind.stairs, m(40, 20), m(60, 20));
  final g = line([s]);
  expect(g.edges.every((e) => e.kind == Kind.road), isTrue);
  expect(g.unapplied, {s});
});
test('겹쳐 기록된 길 위의 계단은 겹친 길을 모두 막는다', () {            // Review Focus 2
  final g = line([rec(Kind.newPath, m(0, 0), m(100, 0)), rec(Kind.stairs, m(40, 0), m(60, 0))]);
  expect(endToEnd(g), isNull);
});
test('계단 옆 경사로는 막히지 않는다', () {                              // Review Focus 3
  final g = line([rec(Kind.stairs, m(40, 0), m(60, 0)), rec(Kind.ramp, m(40, 0), m(60, 0))]);
  expect(endToEnd(g)!.map((i) => g.edges[i].kind), contains(Kind.ramp));
});
test('급경사 기록은 길 구간에 얹힌다', () {
  final g = line([rec(Kind.steep, m(40, 0), m(60, 0))]);
  expect(between(g, 40, 60), isNotEmpty);
  expect(between(g, 40, 60).every((e) => e.kind == Kind.steep), isTrue);
});
test('엘리베이터는 한 조각이고 양 끝에만 붙는다', () {
  final g = line([rec(Kind.elevator, m(50, 0), m(50, 100))]);
  final lift = g.edges.where((e) => e.kind == Kind.elevator);
  expect(lift.length, 1);
  expect(lift.single.grade, 0);
  expect(g.nearest(m(52, 60))!.meters, closeTo(40.05, 0.1));   // 가운데(2m)가 아니라 위쪽 끝
});
test('기울기는 높이 차 ÷ 길이', () {
  final g = buildGraph([m(0, 0), m(100, 0)], [(0, 1)], [], (p) => xy(p).x * 0.1);
  expect(g.edges.every((e) => (e.grade - 0.10).abs() < 0.001), isTrue);
});
```
- [ ] **Step 2: 실패 확인** — Run: `flutter test test/graph_test.dart` · Expected: FAIL (`graph.dart` 없음)
- [ ] **Step 3: `lib/graph.dart` 구현** — 위 Interfaces와 규칙 1~7
- [ ] **Step 4: 통과 확인** — Run: `flutter test && flutter analyze` · Expected: 모두 통과
- [ ] **Step 5: 커밋** — `git add -A && git commit -m "feat: 길 그물망과 조사 기록 반영"`

---

### Task 4: 지도 화면, 조사 탭, 내보내기 (조사자에게 넘길 수 있는 첫 버전)

**Files:**
- Create: `lib/survey_tab.dart`, `test/widget_test.dart`, `README.md`
- Modify: `lib/main.dart`(전체 교체), `lib/store.dart`(`exportRecords` 추가), `test/helpers.dart`(`BlankTiles`, `tinyCampus` 추가), `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`, `web/index.html`, `web/manifest.json`

**Interfaces:**
- Consumes: `Campus`, `Graph.snap`, `Graph.unapplied`, `buildGraph`, `loadRecords`, `saveRecords`
- Produces:
  - `lib/main.dart`: `Future<void> main()`(자산 두 개와 저장 기록을 읽은 뒤 `runApp`), `class App extends StatelessWidget { const App({required this.campus, required this.bundled, required this.local, this.tileProvider}); }`, 같은 인자를 받는 `HomePage`(StatefulWidget)
  - `lib/survey_tab.dart`: `class KindBar`(`selected`, `onSelected`; `ChoiceChip` 다섯 개), `class SurveyBar`(`count`, `waitingForEnd`, `onExport`, `onCancel`), `List<Polyline> recordLines(Iterable<SurveyRecord> r)`, `List<Marker> recordMarkers(Iterable<SurveyRecord> r, void Function(SurveyRecord) onTap)`
  - `lib/store.dart`: `Future<void> exportRecords(List<SurveyRecord> r)` — 파일 이름 `jnu-survey-yyyyMMdd-HHmm.json`, 내용 `encodeRecords(r)`, share_plus로 파일 공유
  - `test/helpers.dart`: `class BlankTiles extends TileProvider`(1×1 투명 그림만 돌려줌), `Campus tinyCampus({bool connected = true})` — 점 `m(0,0)`,`m(100,0)`,`m(0,300)`,`m(100,300)`, 조각 `(0,1)`,`(2,3)`에 `connected`면 `(1,3)` 추가, 장소 `정문`=`m(0,0)`·`도서관`=`m(0,300)`(이어져 있으면 100+300+100 = 500m), 높이는 전부 0, `bounds`는 네 점을 넉넉히 감싸는 상자

**종류별 그림 (색만으로 구분하지 않도록 선 모양과 아이콘을 함께):**

| 종류 | 선 | 아이콘 |
|---|---|---|
| 계단 | 빨강 `0xFFC0392B`, 점선, 굵기 5 | `Icons.stairs` |
| 경사로 | 초록 `0xFF1A8F3C`, 실선 5 | `Icons.accessible_forward` |
| 엘리베이터 | 파랑 `0xFF2A7DE1`, 실선 5 | `Icons.elevator` |
| 새 길 | 보라 `0xFF7B3FB5`, 실선 5 | `Icons.add_road` |
| 급경사 | 주황 `0xFFE08A00`, 긴 점선 5 | `Icons.warning_amber` |

**동작:**
- `FlutterMap` 하나를 두 탭이 같이 쓴다. 아래 `NavigationBar`: **지도**(`Icons.map`), **조사**(`Icons.edit_location_alt`).
- 지도: 처음 화면은 캠퍼스 상자에 맞춤, 확대 14~19, 화면 가운데가 캠퍼스 상자를 벗어나지 못하게 제한, 회전과 두 번 눌러 확대는 끈다(조사 탭의 "두 번 누르기"와 헷갈리지 않게). 오른쪽에 확대(`tooltip: '확대'`)·축소(`'축소'`)·내 위치(`'내 위치로 이동'`) 버튼.
- 내 위치: geolocator로 권한을 묻고 위치 흐름을 받아 파란 점으로 표시. 이 과정의 어떤 실패도 잡아서 무시한다(위치만 없는 상태로 계속). 위치를 모를 때 내 위치 버튼을 누르면 "현재 위치를 알 수 없습니다".
- 기록 목록 = `{...bundled, ...local}`(같은 기록은 한 번만). 기록이 바뀌면 `buildGraph(campus.nodes, campus.edges, 기록, campus.elevationAt)`를 다시 만든다.
- 조사 탭에서 지도를 누르면 `graph.snap(점, 종류)`. 첫 점이면 표시해 두고 `SurveyBar`가 "끝점을 누르세요"와 **취소**를 보인다. 둘째 점이면: 두 점이 1m보다 가까우면 "두 점이 너무 가깝습니다. 다시 눌러 주세요", 아니면 기록을 `local`에 더하고 `saveRecords`. 종류를 바꾸면 첫 점은 지운다.
- 기록 뒤 알림: 계단이 얹혔으면 "이 구간을 길 찾기에서 막았습니다", 급경사가 얹혔으면 "이 구간을 가파른 길로 표시했습니다", `graph.unapplied`에 들어갔으면 "근처에 기록된 길이 없어 지도에만 표시합니다. 길이 있는 곳이면 먼저 '새 길'로 기록하세요".
- `SurveyBar` 평소 문구: "기록 N건 · 시작점과 끝점을 누르세요". 엘리베이터를 골랐을 때는 "기록 N건 · 아래쪽 출입구와 위쪽 출입구를 누르세요". 오른쪽에 **내보내기** 버튼(모든 기록을 내보냄).
- 삭제: 조사 탭에서 기록 가운데의 아이콘(48px)을 누르면 "이 기록을 삭제할까요?" [취소][삭제]. 내장 기록이면 "앱에 내장된 기록은 여기서 지울 수 없습니다".
- 저장이 실패하면 "저장하지 못했습니다. 내보내기로 사본을 남겨 주세요"를 띄운다.
- 지도 탭에서는 계단 기록의 선만 보인다(아이콘·삭제 없음).
- 플랫폼 설정: iOS `NSLocationWhenInUseUsageDescription` = "지도에 내 위치를 표시하고 길 안내의 출발지로 쓰기 위해 위치를 사용합니다.", `CFBundleDisplayName` = "휠체어 길안내". Android `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` 권한과 `android:label="휠체어 길안내"`. 웹 제목 "제주대 휠체어 길안내".

**README.md (이 Task에서 쓰는 절):** ① 컴퓨터에서 열어 보기(`flutter run -d chrome --web-port 5300`), ② 조사자 아이폰에 처음 설치(맥의 Xcode에 애플 계정 로그인 → `open ios/Runner.xcworkspace`에서 Team 고르기 → 케이블 연결·"이 컴퓨터를 신뢰" → 아이폰 개발자 모드 켜기 → `flutter run --release` → 아이폰에서 개발자 앱 신뢰 → 위치 허용), ③ 7일마다 다시 설치(먼저 내보내기, 같은 명령으로 덮어 설치, 앱 삭제 금지), ④ 조사하는 법(종류별 누르는 법, 계단·급경사는 기록된 길 위에 표시, 계단 옆으로 돌아가는 길은 "경사로"로 기록).

- [ ] **Step 1: 실패하는 테스트 쓰기** — `test/widget_test.dart`:
```dart
Future<void> open(WidgetTester t, {Campus? campus}) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(App(campus: campus ?? tinyCampus(), bundled: const [], local: [], tileProvider: BlankTiles()));
  await t.pumpAndSettle();
}

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
  await t.tap(find.descendant(of: find.byType(MarkerLayer), matching: find.byIcon(Icons.add_road)));
  await t.pumpAndSettle();
  await t.tap(find.text('삭제'));
  await t.pumpAndSettle();
  expect(find.textContaining('기록 0건'), findsOneWidget);
  expect(await loadRecords(), isEmpty);
});
```
- [ ] **Step 2: 실패 확인** — Run: `flutter test test/widget_test.dart` · Expected: FAIL (`App` 없음)
- [ ] **Step 3: `lib/main.dart`, `lib/survey_tab.dart`, `exportRecords`, 테스트 도구 구현** — flutter_map·share_plus·geolocator의 정확한 이름은 설치된 버전의 소스(`~/.pub-cache/hosted/pub.dev/<패키지>-<버전>/`)에서 확인하고 쓴다.
- [ ] **Step 4: 플랫폼 설정 고치기**(위 "플랫폼 설정")
- [ ] **Step 5: 통과 확인** — Run: `flutter test && flutter analyze` · Expected: 모두 통과
- [ ] **Step 6: 눈으로 확인** — Run: `flutter run -d chrome --web-port 5300` · 캠퍼스 지도가 뜨고, 조사 탭에서 도로 근처를 두 번 눌러 선이 길에 붙어 그려지는지, 새로 고침 뒤에도 남는지 본다.
- [ ] **Step 7: `README.md` 쓰기**(위 ①~④)
- [ ] **Step 8: 커밋** — `git add -A && git commit -m "feat: 지도 화면과 조사 탭, 내보내기"`

---

### Task 5: 길 찾기

**Files:**
- Create: `lib/route.dart`, `test/route_test.dart`

**Interfaces:**
- Consumes: `Graph`, `Edge`, `shortestPath`, `Graph.attach`, 상수
- Produces (`lib/route.dart`):
  - `enum Profile { manual, powered }` + `double get steepGrade`(0.08 / 0.12), `double get kmh`(3 / 4), `String get label`(수동 휠체어 / 전동 휠체어)
  - `class Leg { final LatLng a, b; final Kind kind; final double meters, grade; final bool steep; }` — 걷는 방향이 a→b
  - `class RouteResult { final List<Leg> legs; final Profile profile; }` + 계산값:
    - `double get meters`(모든 조각 합), `int get minutes`, `int get ramps`, `int get elevators`
    - `List<List<Leg>> get steepSections`(이어진 가파른 조각 묶음), `double get steepMeters`
    - `double? get maxSteepGrade` — 가파른 조각들의 계산 기울기 최댓값. 그 값이 `profile.steepGrade` 이하이면 `null`(화면은 "조사자가 급경사로 표시")
  - `RouteResult? findRoute(Graph g, LatLng from, LatLng to, Profile p)`

**비용 표 (설계서 6절):**

| 조각 종류 | 가파름 | 비용 |
|---|---|---|
| 계단 | — | 지나갈 수 없음 |
| 엘리베이터 | 아님 | `elevatorCostMeters` |
| 경사로 | 아님 | 길이 × `rampCostFactor` |
| 급경사 | 항상 | 길이 × `steepCostFactor` |
| 길·새 길 | `grade > p.steepGrade`일 때 | 가파르면 길이 × `steepCostFactor`, 아니면 길이 |

- 출발·도착 점: `g.attach(점, maxMeters: double.infinity, where: (e) => e.kind != Kind.stairs)`. 붙을 조각이 없으면 `null`.
- `minutes` = 올림(엘리베이터가 아닌 조각 길이 합 × 60 ÷ (`kmh` × 1000) + `elevators` × `elevatorSeconds` ÷ 60). 이 순서로 계산해야 1000m ÷ 4km/h가 정확히 15분이 된다.
- `ramps`, `elevators`는 이어진 같은 종류 조각을 한 곳으로 센다.

- [ ] **Step 1: 실패하는 테스트 쓰기** — `test/route_test.dart`:
```dart
final a = m(0, 0), b = m(100, 0), c = m(50, 150);
double slope(LatLng p) => xy(p).x * 0.1;                               // 동쪽으로 10% 오르막
double step(LatLng p) => (xy(p).x.clamp(40, 60) - 40) / 20 * 5;        // 40~60m에서 5m 오름(25%)
Graph line(List<SurveyRecord> r, double Function(LatLng) h) => buildGraph([a, b], [(0, 1)], r, h);
Graph tri(List<SurveyRecord> r, double Function(LatLng) h) =>          // 곧은 길 100m, 돌아가는 길 316m
    buildGraph([a, b, c], [(0, 1), (0, 2), (2, 1)], r, h);
bool via(RouteResult r, LatLng p) => r.legs.any((l) => meters(l.a, p) < 0.5);
final stairs = rec(Kind.stairs, m(40, 0), m(60, 0));

test('1 가장 짧은 길에 계단이 있으면 돌아가는 길을 준다', () {
  final r = findRoute(tri([stairs], flat), a, b, Profile.manual)!;
  expect(via(r, c), isTrue);
  expect(r.meters, closeTo(316.2, 1));
});
test('2 조금 더 긴 완만한 길이 있으면 가파른 길 대신 그 길을 준다', () {
  final r = findRoute(tri([], slope), a, b, Profile.manual)!;
  expect(via(r, c), isTrue);
  expect(r.steepSections, isEmpty);
});
test('3 가파른 길밖에 없으면 그 길을 주고 경고 정보를 함께 준다', () {
  final r = findRoute(line([], slope), a, b, Profile.manual)!;
  expect(r.steepSections.length, 1);
  expect(r.steepMeters, closeTo(100, 0.5));
  expect(r.maxSteepGrade, closeTo(0.10, 0.005));
});
test('4 엘리베이터 연결이 있으면 그것으로 높이 차를 넘는다', () {
  final r = findRoute(line([rec(Kind.elevator, m(40, 5), m(60, 5))], step), a, b, Profile.manual)!;
  expect(r.elevators, 1);
  expect(r.steepSections, isEmpty);
});
test('5 계단 없이는 갈 수 없으면 찾지 못함을 돌려준다', () {
  expect(findRoute(line([stairs], flat), a, b, Profile.manual), isNull);
});
test('6 수동과 전동에서 가파름 판정이 달라진다', () {
  expect(findRoute(line([], slope), a, b, Profile.manual)!.steepSections.length, 1);
  expect(findRoute(line([], slope), a, b, Profile.powered)!.steepSections, isEmpty);
});
test('7 조사 기록의 계단이 있는 구간은 경로에서 빠진다', () {
  final r = findRoute(tri([stairs], flat), a, b, Profile.manual)!;
  expect(r.legs.any((l) => l.kind == Kind.stairs), isFalse);
  expect(r.legs.any((l) => xy(l.a).y.abs() < 1 && xy(l.b).y.abs() < 1 && xy(l.a).x > 39 && xy(l.a).x < 61), isFalse);
});
test('8 조사 기록의 새 길은 경로에 쓰인다', () {
  final g = buildGraph([a, m(0, -30), b, m(100, -30)], [(0, 1), (2, 3)], [rec(Kind.newPath, a, b)], flat);
  final r = findRoute(g, a, b, Profile.manual)!;
  expect(r.legs.every((l) => l.kind == Kind.newPath), isTrue);
  expect(r.meters, closeTo(100, 0.5));
});
test('조사자가 표시한 급경사는 전동에도 가파르고, 계산 기울기가 낮으면 숫자를 주지 않는다', () {
  final r = findRoute(line([rec(Kind.steep, m(40, 0), m(60, 0))], flat), a, b, Profile.powered)!;
  expect(r.steepSections.length, 1);
  expect(r.steepMeters, closeTo(20, 0.5));
  expect(r.maxSteepGrade, isNull);
});
test('경사로는 한 곳으로 세고 가파른 길로 보지 않는다', () {
  final r = findRoute(line([rec(Kind.ramp, a, b)], slope), a, b, Profile.manual)!;
  expect(r.ramps, 1);
  expect(r.steepSections, isEmpty);
});
test('예상 시간은 수동 3km/h, 전동 4km/h', () {
  final g = buildGraph([a, m(1000, 0)], [(0, 1)], [], flat);
  expect(findRoute(g, a, m(1000, 0), Profile.manual)!.minutes, 20);
  expect(findRoute(g, a, m(1000, 0), Profile.powered)!.minutes, 15);
});
test('출발지와 목적지가 같으면 0m, 길이 없으면 찾지 못함', () {           // Review Focus 5
  final r = findRoute(line([], flat), a, a, Profile.manual)!;
  expect(r.meters, 0);
  expect(r.minutes, 0);
  expect(findRoute(buildGraph([], [], [], flat), a, b, Profile.manual), isNull);
});
test('내장 자료에서 정문 → 중앙도서관 길이 나온다', () {
  final c = Campus.fromJson(jsonDecode(File('assets/campus.json').readAsStringSync()));
  final gate = c.places.firstWhere((p) => p.name == '정문').at;
  final lib = c.places.firstWhere((p) => p.name == '중앙도서관').at;
  final g = buildGraph(c.nodes, c.edges, [], c.elevationAt);
  for (final p in Profile.values) {
    final r = findRoute(g, gate, lib, p)!;
    expect(r.meters, inInclusiveRange(750, 3000));                     // 직선 약 750m
    printOnFailure('${p.label}: ${r.meters.round()}m, 가파른 구간 ${r.steepSections.length}');
  }
});
```
- [ ] **Step 2: 실패 확인** — Run: `flutter test test/route_test.dart` · Expected: FAIL (`route.dart` 없음)
- [ ] **Step 3: `lib/route.dart` 구현** — 위 Interfaces와 비용 표
- [ ] **Step 4: 통과 확인** — Run: `flutter test && flutter analyze` · Expected: 모두 통과
- [ ] **Step 5: 커밋** — `git add -A && git commit -m "feat: 휠체어 길 찾기와 설계서 확인 항목 8개"`

---

### Task 6: 지도 탭 — 검색, 출발지, 경로와 경고, 수동/전동 전환

**Files:**
- Create: `lib/route_tab.dart`, `test/route_tab_test.dart`
- Modify: `lib/main.dart`, `test/widget_test.dart`

**Interfaces:**
- Consumes: `findRoute`, `RouteResult`, `Profile`, `Campus.places`, `Campus.contains`
- Produces (`lib/route_tab.dart`):
  - `const myLocation = Place('내 위치', LatLng(0, 0));` — 출발지 고르기에서 "내 위치"를 뜻하는 표식
  - `Future<Place?> pickPlace(BuildContext context, List<Place> places, {required String title, bool offerMyLocation = false})` — 아래에서 올라오는 창: 입력 칸 + 이름에 입력 글자가 들어간 장소 목록. `offerMyLocation`이면 맨 위에 "내 위치"
  - `class RouteHeader`(`start`, `dest`, `onPickDest`, `onPickStart`, `onClear`) — 목적지가 없으면 검색 칸 "어디로 갈까요? (예: 중앙도서관)", 있으면 "출발 ○○ → 도착 ○○"(각각 눌러 바꿈)과 지우기 버튼(`tooltip: '길 안내 끝내기'`)
  - `class RouteSheet`(`route`, `needStart`, `profile`, `onProfile`, `onPickStart`)
  - `List<Polyline> routeLines(RouteResult r)` — 완만: 초록 `0xFF1A8F3C` 실선 굵기 6, 가파름: 주황 `0xFFE08A00` 점선 굵기 6
  - `List<Marker> routeMarkers(RouteResult r)` — 가파른 구간마다 가운데에 `Icons.warning_amber`
  - `String summaryLine(RouteResult r)` → `"316m · 약 7분"`
  - `String detailLine(RouteResult r)` → `"계단 없음 · 경사로 1곳 · 엘리베이터 0곳 이용"`
  - `String? warningLine(RouteResult r)` → 가파른 구간이 없으면 `null`, 있으면 `"가파른 구간 1곳 (100m, 최대 기울기 10%)"`, `maxSteepGrade`가 `null`이면 `"가파른 구간 1곳 (20m, 조사자가 급경사로 표시)"`

**동작:**
- 지도 탭에서 지도를 누르면 `placeTapMeters`(60m) 안에서 가장 가까운 장소를 목적지로 삼는다. 없으면 아무 일도 없다.
- 출발 점 = 고른 장소가 있으면 그 장소, 없으면 내 위치(알고 있고 `campus.contains`일 때만), 둘 다 아니면 없음.
- 목적지는 있는데 출발 점이 없으면 `RouteSheet`가 "출발지를 골라 주세요"와 "현재 위치를 알 수 없거나 캠퍼스 밖입니다", **출발지 고르기** 버튼을 보인다.
- 길 찾기는 목적지·출발지·휠체어 종류·조사 기록이 바뀔 때만 다시 한다. 내 위치가 움직였다고 다시 찾지 않는다(설계서의 "하지 않는 것").
- 결과가 `null`이면 "휠체어로 갈 수 있는 길을 찾지 못했습니다". 있으면 지도를 경로 전체가 보이게 맞추고, 출발(파란 점)·도착(빨간 핀) 표시.
- `RouteSheet` 내용 순서: `♿ summaryLine`(굵게) → `detailLine` → 경고 상자(노란 바탕, `Icons.warning_amber`, `warningLine`, "도움이 필요할 수 있습니다") → "기울기는 추정값입니다" → `SegmentedButton<Profile>`(수동 휠체어 / 전동 휠체어).

- [ ] **Step 1: 실패하는 테스트 쓰기**

`test/route_tab_test.dart`:
```dart
double slope(LatLng p) => xy(p).x * 0.1;
RouteResult route(List<SurveyRecord> r, double Function(LatLng) h, Profile p) =>
    findRoute(buildGraph([m(0, 0), m(100, 0)], [(0, 1)], r, h), m(0, 0), m(100, 0), p)!;

test('요약 문구', () {
  final r = route([], flat, Profile.manual);
  expect(summaryLine(r), '100m · 약 2분');
  expect(detailLine(r), '계단 없음 · 경사로 0곳 · 엘리베이터 0곳 이용');
  expect(warningLine(r), isNull);
});
test('경고 문구', () {
  expect(warningLine(route([], slope, Profile.manual)), '가파른 구간 1곳 (100m, 최대 기울기 10%)');
  expect(warningLine(route([rec(Kind.steep, m(40, 0), m(60, 0))], flat, Profile.powered)),
      '가파른 구간 1곳 (20m, 조사자가 급경사로 표시)');
});
```

`test/widget_test.dart`에 추가:
```dart
Future<void> pick(WidgetTester t, String name) async {
  await t.tap(find.text(name).last);
  await t.pumpAndSettle();
}

testWidgets('위치를 모르면 출발지를 고르게 하고, 고르면 경로 요약이 나온다', (t) async {   // Review Focus 4
  await open(t);                       // 테스트에는 위치 기능이 없다 → 앱이 멈추지 않아야 한다
  await t.tap(find.textContaining('어디로 갈까요'));
  await t.pumpAndSettle();
  await pick(t, '도서관');
  expect(find.text('출발지를 골라 주세요'), findsOneWidget);
  await t.tap(find.text('출발지 고르기'));
  await t.pumpAndSettle();
  await pick(t, '정문');
  expect(find.textContaining('500m'), findsOneWidget);                  // 100 + 300 + 100
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
```
- [ ] **Step 2: 실패 확인** — Run: `flutter test` · Expected: 새 테스트 FAIL
- [ ] **Step 3: `lib/route_tab.dart` 구현, `lib/main.dart`에 연결**
- [ ] **Step 4: 통과 확인** — Run: `flutter test && flutter analyze` · Expected: 모두 통과
- [ ] **Step 5: 눈으로 확인** — Run: `flutter run -d chrome --web-port 5300` · "중앙도서관" 검색 → 출발지 "정문" → 초록 실선/주황 점선 경로, 요약, 경고, 수동/전동 전환 시 다시 계산되는지 본다.
- [ ] **Step 6: 커밋** — `git add -A && git commit -m "feat: 검색, 출발지 선택, 경로와 급경사 경고"`

---

### Task 7: 접근성 확인, 세 가지 빌드, 안내서 마무리

**Files:**
- Modify: `test/widget_test.dart`, `README.md`

**Interfaces:**
- Consumes: 앞의 모든 Task

- [ ] **Step 1: 접근성 테스트 쓰기** — `test/widget_test.dart`에 추가:
```dart
testWidgets('누르는 대상이 충분히 크고 이름이 붙어 있다', (t) async {
  final handle = t.ensureSemantics();
  await open(t);
  for (final tab in ['지도', '조사']) {
    await t.tap(find.text(tab));
    await t.pumpAndSettle();
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));   // 48×48 이상
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));   // 화면 읽기용 이름
  }
  handle.dispose();
});
```
- [ ] **Step 2: 실행하고, 실패하면 해당 위젯을 고친다** — Run: `flutter test` · Expected: 모두 통과
- [ ] **Step 3: 세 가지 빌드 확인**
```bash
flutter analyze
flutter build web
flutter build apk --release
flutter build ios --release --no-codesign
```
Expected: 네 명령 모두 오류 없이 끝남
- [ ] **Step 4: 실제 자료로 눈으로 확인** — Chrome에서 정문 → 중앙도서관을 수동·전동으로 찾아 화면을 확인하고, 조사 탭에서 계단을 경로 위에 기록했을 때 경로가 바뀌는지 본다.
- [ ] **Step 5: `README.md` 마무리** — ⑤ 조사 결과를 앱에 넣기(내보낸 파일을 `assets/survey.json`으로 덮어쓰고 다시 설치), ⑥ 안드로이드 설치(`build/app/outputs/flutter-apk/app-release.apk` 전달)와 웹 실행, ⑦ 시연 전 점검표(인터넷 연결, 출발지 "정문" 고르기, 수동/전동 전환 보여 주기), ⑧ 알려진 한계(기울기는 추정값, 건물 출입구 구분 없음, 지도 그림은 인터넷 필요).
- [ ] **Step 6: 커밋** — `git add -A && git commit -m "feat: 접근성 확인, 빌드, 안내서"`
