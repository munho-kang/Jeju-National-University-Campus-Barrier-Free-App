# 제주대 휠체어 길안내

제주대학교 아라캠퍼스에서 계단을 피하고, 가파른 길은 미리 알려 주는 길 안내 앱입니다.
아이폰·안드로이드·웹에서 같은 코드로 돌아갑니다.

- 설계서: `docs/superpowers/specs/2026-11-10-jnu-wheelchair-nav-design.md`, 이동 중 길 안내는 `docs/superpowers/specs/2026-11-14-guidance-design.md`
- 지도 자료(길·장소·건물 테두리): © OpenStreetMap contributors, [ODbL](https://opendatacommons.org/licenses/odbl/) 라이선스. 높이 자료: SRTM(미국 지질조사국 공개 자료).
- 명령어는 모두 **터미널**(맥의 "터미널" 앱)에서, 이 폴더로 이동한 뒤 입력합니다.
  ```
  cd Jeju-National-University-Campus-Barrier-Free-App
  ```

---

## 만든 것이 맞는지 확인하기

```
flutter test
```

설계서의 확인 항목 8개(계단을 피하는지, 완만한 길을 고르는지, 급경사를 경고하는지 등)와 길 안내 설계서의 확인 항목(꺾기 전에 알리는지, 길을 벗어나면 다시 찾는지, 도착을 알리는지, 지도가 돌아가도 건물 이름이 바로 서는지 등)을 포함한 자동 검사 98개가 모두 통과하면 "All tests passed!"가 나옵니다.
