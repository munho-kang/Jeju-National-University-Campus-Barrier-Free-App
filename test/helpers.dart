import 'dart:math';

import 'package:jnu_wheel_nav/model.dart';
import 'package:latlong2/latlong.dart';

/// 원점(33.4555, 126.5625)에서 동쪽 x m, 북쪽 y m인 점. `xy`의 반대.
LatLng m(double x, double y) => LatLng(
  33.4555 + y / 110574,
  126.5625 + x / (111320 * cos(33.4555 * pi / 180)),
);

SurveyRecord rec(Kind k, LatLng a, LatLng b) =>
    SurveyRecord(k, a, b, DateTime.utc(2026, 11, 12));

double flat(LatLng _) => 0;
