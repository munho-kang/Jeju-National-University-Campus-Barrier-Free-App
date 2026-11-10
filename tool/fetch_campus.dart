// 캠퍼스의 길·장소·높이를 내려받아 assets/campus.json을 만든다.
//
// 실행:  dart run tool/fetch_campus.dart     (1~2분 걸린다)
//
// 주의: 조사가 시작된 뒤에는 다시 돌리지 않는다. 길 자료가 조금이라도 바뀌면
// 조사 기록이 붙어 있던 자리가 어긋난다.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const userAgent = 'wheel-nav-fetch/1.0';

// 공개 서버라 자주 느리거나 막힌다. 위에서부터 차례로 시도한다.
const overpassHosts = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

// 캠퍼스 경계(way 369649909), 차도, 이름 있는 건물.
// 보행로(footway·path·steps)는 계단 여부를 알 수 없어 받지 않는다.
const query = '''
[out:json][timeout:90];
(way(369649909);
 way[highway~"^(secondary|tertiary|unclassified|residential|living_street|service)(_link)?\$"](33.448,126.553,33.463,126.572);
 nwr[building][name](33.448,126.553,33.463,126.572););
out geom;
''';
const boundaryWay = 369649909;

// 정문은 건물이 아니라서 손으로 넣는다 (OSM 노드 4655302248).
const gate = ['정문', 33.4592796, 126.5611458];

// 높이 격자: SRTM 30m 자료의 원래 눈금(1초 = 1/3600도)에 맞춘다.
const elevSouth = 33 + 1612 / 3600, elevWest = 126 + 1990 / 3600;
const elevStep = 1 / 3600, elevRows = 56, elevCols = 71;

Future<String> fetch(Uri url, {String? body}) async {
  final client = HttpClient()
    ..userAgent = userAgent
    ..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = body == null
        ? await client.getUrl(url)
        : await client.postUrl(url);
    if (body != null) {
      req.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      req.write(body);
    }
    final res = await req.close().timeout(const Duration(seconds: 120));
    final text = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 120));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    return text;
  } finally {
    client.close(force: true);
  }
}

Future<List<Map<String, dynamic>>> fetchOsm() async {
  for (final host in overpassHosts) {
    try {
      stdout.writeln('지도 자료 요청: $host');
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

Future<List<num>> fetchElevations() async {
  final points = [
    for (var r = 0; r < elevRows; r++)
      for (var c = 0; c < elevCols; c++)
        '${(elevSouth + r * elevStep).toStringAsFixed(6)},'
            '${(elevWest + c * elevStep).toStringAsFixed(6)}',
  ];
  final data = <num>[];
  stdout.write('높이 자료 요청 (${points.length}점)');
  for (var i = 0; i < points.length; i += 100) {
    final locations = points.sublist(i, min(i + 100, points.length)).join('|');
    final url = Uri.parse(
      'https://api.opentopodata.org/v1/srtm30m?locations=$locations',
    );
    for (var attempt = 1; ; attempt++) {
      try {
        for (final r in jsonDecode(await fetch(url))['results'] as List) {
          data.add(r['elevation'] as num); // null이면 여기서 멈춘다
        }
        break;
      } catch (e) {
        if (attempt == 3) rethrow;
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    stdout.write('.');
    // 이 서버는 1초에 한 번만 요청을 받는다.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
  }
  stdout.writeln();
  return data;
}

double round7(num v) => (v * 1e7).round() / 1e7;

/// 점이 다각형 안에 있는지 (점에서 동쪽으로 그은 선이 변을 홀수 번 만나면 안).
bool inside(List<(double, double)> poly, double lat, double lon) {
  var result = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final (lat1, lon1) = poly[i];
    final (lat2, lon2) = poly[j];
    if ((lat1 > lat) != (lat2 > lat) &&
        lon < (lon2 - lon1) * (lat - lat1) / (lat2 - lat1) + lon1) {
      result = !result;
    }
  }
  return result;
}

Future<void> main() async {
  final elements = await fetchOsm();
  double num_(dynamic v) => (v as num).toDouble();

  final boundary = elements.firstWhere(
    (e) => e['type'] == 'way' && e['id'] == boundaryWay,
  );
  final poly = [
    for (final g in boundary['geometry'] as List)
      (num_(g['lat']), num_(g['lon'])),
  ];
  final lats = poly.map((p) => p.$1), lons = poly.map((p) => p.$2);

  // 길: 두 끝점이 모두 캠퍼스 안인 조각만. 같은 OSM 노드는 같은 점으로 쓴다.
  final nodeIndex = <int, int>{};
  final nodes = <List<double>>[];
  final edges = <List<int>>[];
  for (final way in elements) {
    if (way['type'] != 'way' || way['tags']?['highway'] == null) continue;
    final ids = (way['nodes'] as List).cast<int>();
    final geom = way['geometry'] as List;
    int index(int i) => nodeIndex.putIfAbsent(ids[i], () {
      nodes.add([round7(geom[i]['lat']), round7(geom[i]['lon'])]);
      return nodes.length - 1;
    });
    bool ok(int i) => inside(poly, num_(geom[i]['lat']), num_(geom[i]['lon']));
    for (var i = 0; i + 1 < ids.length; i++) {
      if (ok(i) && ok(i + 1)) edges.add([index(i), index(i + 1)]);
    }
  }

  // 장소: 이름 있는 건물의 가운데 점이 캠퍼스 안인 것만.
  final places = <List<Object>>[];
  for (final e in elements) {
    final tags = e['tags'];
    if (tags?['building'] == null || tags?['name'] == null) continue;
    final b = e['bounds'];
    final lat = b == null
        ? num_(e['lat'])
        : (num_(b['minlat']) + num_(b['maxlat'])) / 2;
    final lon = b == null
        ? num_(e['lon'])
        : (num_(b['minlon']) + num_(b['maxlon'])) / 2;
    if (inside(poly, lat, lon)) {
      places.add([tags['name'] as String, round7(lat), round7(lon)]);
    }
  }
  places.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  places.insert(0, gate);

  final elev = await fetchElevations();

  File('assets/campus.json').writeAsStringSync(
    jsonEncode({
      'bounds': [
        round7(lats.reduce(min)),
        round7(lons.reduce(min)),
        round7(lats.reduce(max)),
        round7(lons.reduce(max)),
      ],
      'places': places,
      'nodes': nodes,
      'edges': edges,
      'elev': {
        'south': elevSouth,
        'west': elevWest,
        'step': elevStep,
        'rows': elevRows,
        'cols': elevCols,
        'data': elev,
      },
    }),
  );

  num heightAt(String name) {
    final p = places.firstWhere((p) => p[0] == name);
    final r = ((num_(p[1]) - elevSouth) / elevStep).round();
    final c = ((num_(p[2]) - elevWest) / elevStep).round();
    return elev[r * elevCols + c];
  }

  stdout.writeln(
    '장소 ${places.length}곳, 점 ${nodes.length}개, 조각 ${edges.length}개 → '
    'assets/campus.json',
  );
  stdout.writeln('정문 ${heightAt('정문')}m, 중앙도서관 ${heightAt('중앙도서관')}m');
}
