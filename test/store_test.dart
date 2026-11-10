import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/model.dart';
import 'package:jnu_wheel_nav/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  final r = rec(Kind.newPath, m(0, 0), m(10, 0));

  test('저장한 기록을 다시 읽는다', () async {
    SharedPreferences.setMockInitialValues({});
    await saveRecords([r]);
    expect(await loadRecords(), [r]);
  });

  // Review Focus 1
  test('깨진 저장값은 지우지 않고 옮겨 둔다', () async {
    SharedPreferences.setMockInitialValues({'survey_records': 'not json'});
    expect(await loadRecords(), isEmpty);
    final p = await SharedPreferences.getInstance();
    final kept = p.getKeys().where(
      (k) => k.startsWith('survey_records_corrupt_'),
    );
    expect(kept.map(p.getString), ['not json']);
  });
}
