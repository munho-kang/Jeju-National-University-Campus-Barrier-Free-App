import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'graph.dart';
import 'guidance_screen.dart';
import 'model.dart';
import 'route.dart';
import 'route_tab.dart';
import 'store.dart';
import 'survey_tab.dart';
import 'voice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final campus = Campus.fromJson(
    jsonDecode(await rootBundle.loadString('assets/campus.json')),
  );
  final bundled = decodeRecords(
    await rootBundle.loadString('assets/survey.json'),
  );
  final buildings = decodeBuildings(
    await rootBundle.loadString('assets/buildings.json'),
  );
  runApp(
    App(
      campus: campus,
      bundled: bundled,
      local: await loadRecords(),
      buildings: buildings,
    ),
  );
}

class App extends StatelessWidget {
  const App({
    super.key,
    required this.campus,
    required this.bundled,
    required this.local,
    this.tileProvider,
    this.buildings = const [],
    this.voice,
    this.fixes,
  });

  final Campus campus;

  /// 앱에 내장된 조사 기록(assets/survey.json)과 이 휴대폰에 저장된 기록.
  final List<SurveyRecord> bundled, local;

  /// 테스트에서 인터넷 없이 지도를 띄우려고 바꿔 끼우는 자리. 평소엔 비워 둔다.
  final TileProvider? tileProvider;

  /// 안내 화면에 그리는 건물 윤곽(assets/buildings.json).
  final List<List<LatLng>> buildings;

  /// 안내 음성. 비우면 `Voice()`.
  final Voice? voice;

  /// 테스트에서 위치를 흉내 내려고 바꿔 끼우는 자리. 평소엔 비워 둔다.
  final Stream<Fix>? fixes;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '제주대 휠체어 길안내',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0060C0)),
    home: HomePage(
      campus: campus,
      bundled: bundled,
      local: local,
      tileProvider: tileProvider,
      buildings: buildings,
      voice: voice,
      fixes: fixes,
    ),
  );
}

/// 지도 한 장을 "지도" 탭과 "조사" 탭이 같이 쓰는 화면.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.campus,
    required this.bundled,
    required this.local,
    this.tileProvider,
    this.buildings = const [],
    this.voice,
    this.fixes,
  });

  final Campus campus;
  final List<SurveyRecord> bundled, local;
  final TileProvider? tileProvider;
  final List<List<LatLng>> buildings;
  final Voice? voice;
  final Stream<Fix>? fixes;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _minZoom = 14.0, _maxZoom = 19.0;

  final _map = MapController();
  late final List<SurveyRecord> _local = [...widget.local];
  late Graph _graph;
  int _tab = 0; // 0 지도, 1 조사

  LatLng? _me;
  StreamSubscription<Fix>? _positions;

  /// 들어온 위치를 안내 화면에 그대로 넘겨 주는 통로.
  final _fixes = StreamController<Fix>.broadcast();
  late final Voice _voice = widget.voice ?? Voice();

  // 지도 탭
  Place? _dest; // 목적지
  Place? _startPlace; // 직접 고른 출발지. null이면 내 위치에서 출발
  Profile _profile = Profile.manual;
  RouteResult? _route;

  // 조사 탭
  Kind _kind = Kind.stairs;
  LatLng? _first; // 시작점을 누르고 끝점을 기다리는 중이면 그 시작점

  Campus get _campus => widget.campus;

  /// 내장 기록 + 이 휴대폰의 기록 (같은 기록은 한 번만).
  List<SurveyRecord> get _records => {...widget.bundled, ..._local}.toList();

  @override
  void initState() {
    super.initState();
    _rebuild();
    _startLocation();
  }

  @override
  void dispose() {
    _positions?.cancel();
    _fixes.close();
    super.dispose();
  }

  /// 조사 기록이 바뀌면 그물망을 다시 만들고, 보고 있던 경로도 다시 찾는다.
  void _rebuild() {
    _graph = buildGraph(
      _campus.nodes,
      _campus.edges,
      _records,
      _campus.elevationAt,
    );
    _findRoute(fit: false);
  }

  Future<void> _startLocation() async {
    try {
      var fixes = widget.fixes;
      if (fixes == null) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }
        fixes = Geolocator.getPositionStream().map(
          (p) => (at: LatLng(p.latitude, p.longitude), accuracy: p.accuracy),
        );
      }
      _positions = fixes.listen((f) {
        if (!mounted) return;
        setState(() {
          final waiting = _dest != null && _startPoint == null;
          _me = f.at;
          // 출발지를 기다리던 중에 위치를 처음 알게 되면 바로 길을 찾는다.
          // 그 뒤로는 위치가 움직여도 다시 찾지 않는다 (설계서: 자동 재탐색 안 함).
          if (waiting) _findRoute();
        });
        _fixes.add(f);
      }, onError: (_) {});
    } catch (_) {
      // 위치를 쓸 수 없어도 앱은 계속 쓸 수 있다 (출발지를 직접 고르면 된다).
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _zoom(double delta) => _map.move(
    _map.camera.center,
    (_map.camera.zoom + delta).clamp(_minZoom, _maxZoom),
  );

  void _goToMe() {
    final me = _me;
    if (me == null) return _say('현재 위치를 알 수 없습니다');
    _map.move(me, 18);
  }

  void _onMapTap(LatLng p) {
    if (_tab == 1) {
      _surveyTap(p);
    } else if (_dest == null) {
      _tapPlace(p);
    }
  }

  // ── 지도 탭 ──

  /// 출발 점: 고른 장소, 없으면 내 위치(캠퍼스 안일 때만), 둘 다 없으면 null.
  LatLng? get _startPoint {
    final me = _me;
    return _startPlace?.at ?? (me != null && _campus.contains(me) ? me : null);
  }

  void _findRoute({bool fit = true}) {
    final dest = _dest, start = _startPoint;
    final route = dest == null || start == null
        ? null
        : findRoute(_graph, start, dest.at, _profile);
    _route = route;
    if (!fit || route == null) return;
    // 요약 창이 뜨면서 지도 크기가 바뀌므로, 다 그려진 뒤에 경로 전체가 보이게 맞춘다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: [start!, dest!.at, for (final l in route.legs) l.b],
          padding: const EdgeInsets.all(48),
          maxZoom: 18,
        ),
      );
    });
  }

  /// 안내 화면을 띄운다. [preview]가 아니면 지금 위치에서 길을 다시 찾고 시작한다.
  Future<void> _guide({required bool preview}) async {
    if (!preview) setState(() => _findRoute(fit: false));
    final route = _route, dest = _dest;
    if (route == null || route.legs.isEmpty || dest == null) return;
    final arrived = await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        // 따로 둔 알림 통로: 닫히는 동안 아래 도착 알림이 이 화면에도 겹쳐 뜨지 않게.
        builder: (_) => ScaffoldMessenger(
          child: GuidanceScreen(
            campus: _campus,
            graph: _graph,
            buildings: widget.buildings,
            route: route,
            dest: dest,
            voice: _voice,
            fixes: preview ? null : _fixes.stream,
          ),
        ),
      ),
    );
    if (arrived == true) _say('${dest.name}에 도착했습니다');
  }

  /// 지도에서 건물을 눌러 목적지로 고른다 (목적지가 아직 없을 때만).
  void _tapPlace(LatLng p) {
    Place? best;
    var bestMeters = placeTapMeters;
    for (final place in _campus.places) {
      final d = meters(p, place.at);
      if (d <= bestMeters) (best, bestMeters) = (place, d);
    }
    if (best == null) return;
    setState(() {
      _dest = best;
      _findRoute();
    });
  }

  Future<void> _pickDest() async {
    final place = await pickPlace(context, _campus.places, title: '어디로 갈까요?');
    if (place == null || !mounted) return;
    setState(() {
      _dest = place;
      _findRoute();
    });
  }

  Future<void> _pickStart() async {
    final me = _me;
    final place = await pickPlace(
      context,
      _campus.places,
      title: '어디에서 출발하나요?',
      offerMyLocation: me != null && _campus.contains(me),
    );
    if (place == null || !mounted) return;
    setState(() {
      _startPlace = place == myLocation ? null : place;
      _findRoute();
    });
  }

  // ── 조사 탭 ──

  Future<void> _surveyTap(LatLng tapped) async {
    final first = _first;
    final p = _graph.snap(tapped, _kind, from: first);
    if (first == null) return setState(() => _first = p);
    if (meters(first, p) < 1) return _say('두 점이 너무 가깝습니다. 다시 눌러 주세요');
    final r = SurveyRecord(_kind, first, p, DateTime.now().toUtc());
    await _changeRecords(() => _local.add(r), created: r);
  }

  /// 기록을 더하거나 지우고, 저장하고, 조사자가 알아야 할 변화를 알린다.
  ///
  /// 계단·급경사 기록이 길 찾기에 반영되는지는 다른 기록(길)이 생기거나 사라질
  /// 때도 바뀐다. 말없이 바뀌면 계단이 막히지 않은 채 남을 수 있어 매번 비교한다.
  Future<void> _changeRecords(
    void Function() change, {
    SurveyRecord? created,
  }) async {
    final before = _graph.unapplied;
    setState(() {
      change();
      _first = null;
      _rebuild();
    });
    final saved = await _save();
    final after = _graph.unapplied, now = _records.toSet();
    final notice = surveyNotice(
      saved: saved,
      created: created,
      createdApplied: !after.contains(created),
      newlyApplied: before
          .where((r) => now.contains(r) && !after.contains(r))
          .length,
      newlyUnapplied: after
          .where((r) => r != created && !before.contains(r))
          .length,
    );
    if (notice != null) _say(notice);
  }

  Future<void> _delete(SurveyRecord r) async {
    if (widget.bundled.contains(r)) {
      return _say('앱에 내장된 기록은 여기서 지울 수 없습니다');
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('이 기록을 삭제할까요?'),
        content: Text('${r.kind.label} · ${meters(r.a, r.b).round()}m'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _changeRecords(() => _local.remove(r));
  }

  /// 저장에 성공했는지 돌려준다.
  Future<bool> _save() async {
    try {
      await saveRecords(_local);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _export() async {
    try {
      await exportRecords(_records);
    } catch (_) {
      _say('내보내지 못했습니다. 다시 시도해 주세요');
    }
  }

  // ── 화면 ──

  @override
  Widget build(BuildContext context) {
    final survey = _tab == 1;
    final records = _records;
    final bounds = LatLngBounds(
      LatLng(_campus.south, _campus.west),
      LatLng(_campus.north, _campus.east),
    );
    final me = _me, first = _first;
    final dest = _dest, start = _startPoint, route = _route;
    final showRoute = !survey && dest != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (!survey)
              RouteHeader(
                start: _startPlace?.name ?? (start == null ? null : '내 위치'),
                dest: dest?.name,
                onPickDest: _pickDest,
                onPickStart: _pickStart,
                onClear: () => setState(() {
                  _dest = _startPlace = _route = null;
                }),
              ),
            if (survey)
              KindBar(
                selected: _kind,
                onSelected: (k) => setState(() {
                  _kind = k;
                  _first = null;
                }),
              ),
            Expanded(
              // 위아래 막대가 탭마다 달라져도 지도는 같은 것으로 알아보게 한다.
              // 이 표식이 없으면 탭을 바꿀 때마다 지도가 처음 위치로 돌아간다.
              key: const ValueKey('map'),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      // 화면 크기를 알기 전의 첫 위치. 곧바로 아래 맞춤이 적용된다.
                      initialCenter: bounds.center,
                      initialZoom: 16,
                      initialCameraFit: CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(24),
                      ),
                      cameraConstraint: CameraConstraint.containCenter(
                        bounds: bounds,
                      ),
                      minZoom: _minZoom,
                      maxZoom: _maxZoom,
                      // 회전은 헷갈리고, 두 번 눌러 확대는 조사 탭의
                      // "두 번 누르기"와 겹쳐서 끈다.
                      interactionOptions: const InteractionOptions(
                        flags:
                            InteractiveFlag.all &
                            ~InteractiveFlag.rotate &
                            ~InteractiveFlag.doubleTapZoom &
                            ~InteractiveFlag.doubleTapDragZoom,
                      ),
                      onTap: (_, p) => _onMapTap(p),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'kr.jnucapstone3.jnu_wheel_nav',
                        tileProvider: widget.tileProvider,
                      ),
                      // 굵은 선: 길 찾기가 실제로 막거나(계단) 가파르다고 보는 구간.
                      // 지도 탭에는 막힌 구간만, 조사 탭에는 기록한 선도 함께 보인다.
                      PolylineLayer(
                        polylines: [
                          ...overlayLines(_graph, stairsOnly: !survey),
                          if (survey) ...recordLines(records),
                        ],
                      ),
                      if (showRoute && route != null)
                        PolylineLayer(polylines: routeLines(route)),
                      MarkerLayer(
                        markers: [
                          if (showRoute && route != null)
                            ...routeMarkers(route),
                          if (showRoute && start != null)
                            Marker(
                              point: start,
                              width: 28,
                              height: 28,
                              child: const IgnorePointer(
                                child: Icon(
                                  Icons.trip_origin,
                                  size: 28,
                                  color: Color(0xFF2A7DE1),
                                ),
                              ),
                            ),
                          if (showRoute)
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
                          if (survey)
                            ...recordMarkers(
                              records,
                              _delete,
                              unapplied: _graph.unapplied,
                            ),
                          if (survey && first != null)
                            Marker(
                              point: first,
                              width: 28,
                              height: 28,
                              child: IgnorePointer(
                                child: Icon(
                                  Icons.radio_button_checked,
                                  size: 28,
                                  color: kindStyle(_kind).color,
                                ),
                              ),
                            ),
                          if (me != null)
                            Marker(
                              point: me,
                              width: 22,
                              height: 22,
                              child: IgnorePointer(
                                child: Semantics(
                                  label: '내 위치',
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2A7DE1),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SimpleAttributionWidget(
                        source: Text('OpenStreetMap contributors'),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Column(
                      children: [
                        IconButton.filledTonal(
                          tooltip: '확대',
                          onPressed: () => _zoom(1),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton.filledTonal(
                          tooltip: '축소',
                          onPressed: () => _zoom(-1),
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton.filledTonal(
                          tooltip: '내 위치로 이동',
                          onPressed: _goToMe,
                          icon: const Icon(Icons.my_location),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showRoute)
              RouteSheet(
                route: route,
                needStart: start == null,
                profile: _profile,
                onProfile: (p) => setState(() {
                  _profile = p;
                  _findRoute(fit: false);
                }),
                onPickStart: _pickStart,
                onPreview: () => _guide(preview: true),
                onGuide: _startPlace == null
                    ? () => _guide(preview: false)
                    : null,
              ),
            if (survey)
              SurveyBar(
                kind: _kind,
                count: records.length,
                unapplied: _graph.unapplied.length,
                waitingForEnd: first != null,
                onExport: _export,
                onCancel: () => setState(() => _first = null),
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _first = null;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: '지도'),
          NavigationDestination(
            icon: Icon(Icons.edit_location_alt),
            label: '조사',
          ),
        ],
      ),
    );
  }
}
