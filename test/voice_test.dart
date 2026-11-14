import 'package:flutter_test/flutter_test.dart';
import 'package:jnu_wheel_nav/voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 테스트 환경에는 목소리 기능도 화면 켜 두기 기능도 없다. 그래도 오류 없이 끝나야 한다.
  test('목소리 기능이 없어도 speak와 stop이 오류 없이 끝난다', () async {
    final v = Voice();
    await v.speak('20미터 앞에서 왼쪽입니다');
    await v.stop();
  });
  test('화면 켜 두기 기능이 없어도 오류 없이 끝난다', () async {
    await keepAwake(true);
    await keepAwake(false);
  });
}
