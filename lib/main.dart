import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'graph.dart';
import 'model.dart';
import 'store.dart';
import 'survey_tab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final campus = Campus.fromJson(
    jsonDecode(await rootBundle.loadString('assets/campus.json')),
  );
  final bundled = decodeRecords(
    await rootBundle.loadString('assets/survey.json'),
  );
  runApp(App(campus: campus, bundled: bundled, local: await loadRecords()));
}

class App extends StatelessWidget {
  const App({
    super.key,
    required this.campus,
    required this.bundled,
    required this.local,
    this.tileProvider,
  });

  final Campus campus;

  /// 앱에 내장된 조사 기록(assets/survey.json)과 이 휴대폰에 저장된 기록.
  final List<SurveyRecord> bundled, local;

  /// 테스트에서 인터넷 없이 지도를 띄우려고 바꿔 끼우는 자리. 평소엔 비워 둔다.
  final TileProvider? tileProvider;

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
  });

  final Campus campus;
  final List<SurveyRecord> bundled, local;
  final TileProvider? tileProvider;

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
  StreamSubscription<Position>? _positions;

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
    super.dispose();
  }

  void _rebuild() => _graph = buildGraph(
    _campus.nodes,
    _campus.edges,
    _records,
    _campus.elevationAt,
  );

  Future<void> _startLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      _positions = Geolocator.getPositionStream().listen((p) {
        if (mounted) setState(() => _me = LatLng(p.latitude, p.longitude));
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
    if (_tab == 1) _surveyTap(p);
  }

  // ── 조사 탭 ──

  Future<void> _surveyTap(LatLng tapped) async {
    final p = _graph.snap(tapped, _kind);
    final first = _first;
    if (first == null) return setState(() => _first = p);
    if (meters(first, p) < 1) return _say('두 점이 너무 가깝습니다. 다시 눌러 주세요');
    final r = SurveyRecord(_kind, first, p, DateTime.now().toUtc());
    setState(() {
      _local.add(r);
      _first = null;
      _rebuild();
    });
    await _save();
    if (r.kind == Kind.stairs || r.kind == Kind.steep) {
      _say(
        _graph.unapplied.contains(r)
            ? "근처에 기록된 길이 없어 지도에만 표시합니다. 길이 있는 곳이면 먼저 '새 길'로 기록하세요"
            : r.kind == Kind.stairs
            ? '이 구간을 길 찾기에서 막았습니다'
            : '이 구간을 가파른 길로 표시했습니다',
      );
    }
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
    setState(() {
      _local.remove(r);
      _rebuild();
    });
    await _save();
  }

  Future<void> _save() async {
    try {
      await saveRecords(_local);
    } catch (_) {
      _say('저장하지 못했습니다. 내보내기로 사본을 남겨 주세요');
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (survey)
              KindBar(
                selected: _kind,
                onSelected: (k) => setState(() {
                  _kind = k;
                  _first = null;
                }),
              ),
            Expanded(
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
                      PolylineLayer(
                        polylines: recordLines(
                          survey
                              ? records
                              : records.where((r) => r.kind == Kind.stairs),
                        ),
                      ),
                      MarkerLayer(
                        markers: [
                          if (survey) ...recordMarkers(records, _delete),
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
            if (survey)
              SurveyBar(
                kind: _kind,
                count: records.length,
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
