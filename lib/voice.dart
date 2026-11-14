import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 안내 문구를 소리로 읽는다. 어떤 경우에도 오류를 던지지 않는다.
class Voice {
  final FlutterTts _tts = FlutterTts();
  bool _iosReady = false;
  int _latest = 0;

  Future<void> speak(String text) async {
    final mine = ++_latest;
    try {
      // 웹은 목소리 목록이 늦게 준비되므로 말할 때마다 확인한다.
      var ok = await _tts.isLanguageAvailable('ko-KR') == true;
      if (!ok && kIsWeb) {
        // 페이지를 연 뒤 처음 물으면 목록이 비어 있을 수 있어 잠깐 뒤 한 번 더 묻는다.
        // ponytail: 300ms 고정 대기 후 한 번만 다시 묻는다. 그래도 빠지면 voiceschanged 신호를 기다리게 바꾼다
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mine != _latest) return;
        ok = await _tts.isLanguageAvailable('ko-KR') == true;
      }
      if (!ok) return;
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          !_iosReady) {
        _iosReady = true;
        // 무음 모드에서도 소리가 나게 한다.
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ]);
      }
      await _tts.setLanguage('ko-KR');
      await _tts.stop();
      if (kIsWeb) {
        // ponytail: 150ms 고정 대기. 새 말이 버려지면 완료 신호(setCompletionHandler)를 기다리게 바꾼다
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (mine != _latest) return; // 기다리는 사이 새 말이나 stop이 왔다
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    _latest++; // 아직 말하기 전인 speak도 취소한다
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// 화면이 저절로 꺼지지 않게 한다(true)/푼다(false). 오류를 던지지 않는다.
Future<void> keepAwake(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (_) {}
}
