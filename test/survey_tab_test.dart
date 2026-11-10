import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/graph.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/survey_tab.dart';

import 'helpers.dart';

Graph line(List<SurveyRecord> r) =>
    buildGraph([m(0, 0), m(100, 0)], [(0, 1)], r, flat);

void main() {
  test('overlayLines는 실제로 막히거나 가파르다고 표시된 구간만 그린다', () {
    double total(Graph g, {bool stairsOnly = false}) => overlayLines(
      g,
      stairsOnly: stairsOnly,
    ).fold(0, (s, l) => s + meters(l.points.first, l.points.last));

    final g = line([
      rec(Kind.stairs, m(40, 0), m(60, 0)),
      rec(Kind.steep, m(70, 0), m(80, 0)),
    ]);
    expect(total(g), closeTo(30, 0.5));
    expect(total(g, stairsOnly: true), closeTo(20, 0.5));
    // 길에서 떨어져 반영되지 않은 계단은 막힌 구간으로 그리지 않는다
    expect(
      overlayLines(line([rec(Kind.stairs, m(40, 30), m(60, 30))])),
      isEmpty,
    );
  });

  group('surveyNotice', () {
    final stairs = rec(Kind.stairs, m(40, 0), m(60, 0));
    final steep = rec(Kind.steep, m(40, 0), m(60, 0));
    final path = rec(Kind.newPath, m(40, 0), m(60, 0));

    String? notice({
      bool saved = true,
      SurveyRecord? created,
      bool createdApplied = true,
      int newlyApplied = 0,
      int newlyUnapplied = 0,
    }) => surveyNotice(
      saved: saved,
      created: created,
      createdApplied: createdApplied,
      newlyApplied: newlyApplied,
      newlyUnapplied: newlyUnapplied,
    );

    test('알릴 것이 없으면 null', () {
      expect(notice(), isNull);
      expect(notice(created: path), isNull);
    });

    test('저장 실패는 계단·급경사를 기록했을 때도 가려지지 않는다', () {
      expect(notice(saved: false, created: stairs), startsWith('저장하지 못했습니다'));
      expect(notice(saved: false, created: steep), startsWith('저장하지 못했습니다'));
    });

    test('방금 기록한 계단·급경사가 반영됐는지 알려 준다', () {
      expect(notice(created: stairs), '이 구간을 길 찾기에서 막았습니다');
      expect(notice(created: steep), '이 구간을 가파른 길로 표시했습니다');
      expect(
        notice(created: stairs, createdApplied: false),
        contains('지도에만 표시합니다'),
      );
    });

    test('다른 기록 때문에 계단·급경사의 반영 여부가 바뀌면 알려 준다', () {
      expect(
        notice(created: path, newlyApplied: 1),
        contains('1건이 이제 길에 반영됩니다'),
      );
      expect(notice(newlyUnapplied: 2), contains('2건이 길에 반영되지 않게 되었습니다'));
    });
  });
}
