import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'cues.dart';
import 'graph.dart';
import 'guidance.dart';
import 'guidance_map.dart';
import 'model.dart';
import 'route.dart';
import 'voice.dart';

/// 이동 중 길 안내 화면. [fixes]가 없으면 경로를 따라 저절로 움직이는 미리 보기.
/// 도착해서 닫히면 `true`를 돌려준다.
class GuidanceScreen extends StatefulWidget {
  const GuidanceScreen({
    super.key,
    required this.campus,
    required this.graph,
    required this.buildings,
    required this.route,
    required this.dest,
    required this.voice,
    this.fixes,
  });

  final Campus campus;
  final Graph graph;
  final List<List<LatLng>> buildings;
  final RouteResult route;
  final Place dest;
  final Voice voice;
  final Stream<Fix>? fixes;

  @override
  State<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends State<GuidanceScreen> {
  late final Guidance g = Guidance(widget.graph, widget.route, widget.dest.at);
  final _map = MapController();
  Timer? _timer;
  StreamSubscription<Fix>? _sub;
  bool _sound = true;
  String _caption = '';
  LatLng? _grab; // 미리 보기에서 지도를 눌러 잡아 둔 자리

  bool get _preview => widget.fixes == null;

  @override
  void initState() {
    super.initState();
    keepAwake(true);
    _say(g.start());
    if (_preview) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _step(_grab ?? g.track.pointAt(g.along + previewSpeed * 0.1));
        if (!g.offRoute) _grab = null;
      });
    } else {
      _sub = widget.fixes!.listen((f) => _step(f.at, f.accuracy));
    }
  }

  @override
  void dispose() {
    _stopListening();
    keepAwake(false);
    if (!g.arrived) widget.voice.stop(); // 도착 음성은 끊지 않는다
    _map.dispose();
    super.dispose();
  }

  void _stopListening() {
    _timer?.cancel();
    _sub?.cancel();
  }

  /// 문장들을 한 문장으로 이어 자막에 넣고, 소리가 켜져 있으면 읽는다.
  void _say(List<String> sentences) {
    if (sentences.isEmpty) return;
    _caption = sentences.join('. ');
    if (_sound) widget.voice.speak(_caption);
  }

  void _step(LatLng p, [double accuracy = 0]) {
    if (g.arrived || !mounted) return;
    final said = g.update(p, accuracy: accuracy, now: DateTime.now());
    _map.moveAndRotate(g.position, _map.camera.zoom, -g.heading);
    setState(() => _say(said));
    if (g.arrived) {
      _stopListening();
      Navigator.pop(context, true);
    }
  }

  void _zoom(double delta) =>
      _map.move(_map.camera.center, _map.camera.zoom + delta);

  void _toggleSound() {
    setState(() => _sound = !_sound);
    if (!_sound) widget.voice.stop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = g.next, after = g.afterNext, steep = g.metersToSteep;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(_icons[next.kind], size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_preview)
                            Text('미리 보기 중', style: theme.textTheme.labelLarge),
                          Text(
                            bannerText(
                              next,
                              g.metersTo(next),
                              widget.dest.name,
                            ),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (after != null)
                            Text(
                              '그다음: ${cueTitle(after, widget.dest.name)}',
                              style: theme.textTheme.titleMedium,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _sound ? '소리 끄기' : '소리 켜기',
                      onPressed: _toggleSound,
                      icon: Icon(_sound ? Icons.volume_up : Icons.volume_off),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  GuidanceMap(
                    controller: _map,
                    campus: widget.campus,
                    graph: widget.graph,
                    buildings: widget.buildings,
                    route: g.route,
                    dest: widget.dest,
                    position: g.position,
                    heading: g.heading,
                    onTap: _preview ? (p) => _grab = p : null,
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '남은 거리 ${g.remainingMeters.round()}m · 약 ${g.remainingMinutes}분',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (steep != null)
                    Row(
                      children: [
                        const Icon(Icons.warning_amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            steep == 0
                                ? '가파른 구간을 지나는 중'
                                : '${steep.round()}m 앞 가파른 구간',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  if (_caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('안내 끝내기'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _icons = {
  CueKind.left: Icons.turn_left,
  CueKind.right: Icons.turn_right,
  CueKind.uturn: Icons.u_turn_left,
  CueKind.elevator: Icons.elevator,
  CueKind.ramp: Icons.accessible_forward,
  CueKind.steep: Icons.warning_amber,
  CueKind.arrive: Icons.flag,
};
