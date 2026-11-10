import 'dart:convert';

import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model.dart';

// 이 열쇠와 기록 형식은 바꾸지 않는다. 바꾸면 조사자 휴대폰의 기록을 못 읽는다.
const _key = 'survey_records';

Future<List<SurveyRecord>> loadRecords() async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getString(_key);
  if (raw == null) return [];
  try {
    return decodeRecords(raw);
  } on FormatException {
    // 읽지 못한 기록을 다음 저장이 덮어쓰지 않도록 다른 열쇠로 옮겨 둔다.
    await p.setString(
      '${_key}_corrupt_${DateTime.now().millisecondsSinceEpoch}',
      raw,
    );
    await p.remove(_key);
    return [];
  }
}

Future<void> saveRecords(List<SurveyRecord> r) async {
  final p = await SharedPreferences.getInstance();
  if (!await p.setString(_key, encodeRecords(r))) {
    throw StateError('조사 기록을 저장하지 못했습니다');
  }
}

/// 모든 기록을 파일 하나로 만들어 휴대폰의 공유 기능(카카오톡, 메일, 에어드롭 등)으로 보낸다.
Future<void> exportRecords(List<SurveyRecord> r) async {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final name =
      'jnu-survey-${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}.json';
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          utf8.encode(encodeRecords(r)),
          mimeType: 'application/json',
          name: name,
        ),
      ],
      fileNameOverrides: [name],
    ),
  );
}
