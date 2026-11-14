// 캠퍼스 건물 테두리를 내려받아 assets/buildings.json을 만든다.
//
// 실행:  dart run tool/fetch_buildings.dart
//
// 조사 기록과 무관해서 다시 돌려도 안전하다.
import 'dart:convert';
import 'dart:io';

import 'fetch_campus.dart' show fetch, overpassHosts, round7;

Future<List<Map<String, dynamic>>> fetchBuildings(String bbox) async {
  final query =
      '[out:json][timeout:90];\n'
      '(way[building]($bbox); relation[building]($bbox););\n'
      'out geom;\n';
  for (final host in overpassHosts) {
    try {
      stdout.writeln('건물 자료 요청: $host');
      final text = await fetch(
        Uri.parse(host),
        body: 'data=${Uri.encodeQueryComponent(query)}',
      );
      return (jsonDecode(text)['elements'] as List).cast();
    } catch (e) {
      stdout.writeln('  실패: $e');
    }
  }
  throw Exception('지도 자료 서버가 모두 응답하지 않습니다. 잠시 뒤 다시 실행하세요.');
}

Future<void> main() async {
  final bounds =
      (jsonDecode(File('assets/campus.json').readAsStringSync())['bounds']
              as List)
          .cast<num>(); // 남, 서, 북, 동
  final elements = await fetchBuildings(bounds.join(','));

  final rings = <List<double>>[];
  void add(dynamic geometry) {
    final g = geometry as List?;
    if (g == null || g.length < 3) return;
    rings.add([
      for (final p in g) ...[round7(p['lat']), round7(p['lon'])],
    ]);
  }

  for (final e in elements) {
    if (e['type'] == 'way') {
      add(e['geometry']);
    } else if (e['type'] == 'relation') {
      for (final m in e['members'] as List) {
        if (m['role'] == 'outer') add(m['geometry']);
      }
    }
  }

  File('assets/buildings.json').writeAsStringSync(jsonEncode(rings));
  stdout.writeln('건물 ${rings.length}개 → assets/buildings.json');
}
