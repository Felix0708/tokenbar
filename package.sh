#!/bin/bash
# 배포용 zip 패키징 스크립트 (무료 배포 — 공증 없음)
# 결과물: dist/TokenBar-mac.zip  (TokenBar.app + 설치방법.txt)
set -e
cd "$(dirname "$0")"

APP="build/Build/Products/Release/TokenBar.app"

# 빌드가 없으면 먼저 빌드
if [ ! -d "$APP" ]; then
    echo "==> 빌드된 앱이 없어 setup.sh를 먼저 실행합니다."
    ./setup.sh
fi

echo "==> 배포 패키지 생성 중..."
rm -rf dist
mkdir -p dist/TokenBar
cp -R "$APP" dist/TokenBar/

cat > "dist/TokenBar/설치방법.txt" <<'EOF'
TokenBar 설치 방법
==================

Claude Code / Codex CLI의 토큰 사용량을 메뉴바와 위젯으로 보여주는 앱입니다.
(Claude Code 또는 Codex CLI를 사용하는 Mac에서만 데이터가 표시됩니다)

1. TokenBar.app 을 '응용 프로그램' 폴더로 드래그하세요.

2. 처음 열 때 "확인되지 않은 개발자" 경고가 뜹니다.
   (개인이 만든 앱이라 Apple 공증이 없어서 그렇습니다)

   해결 방법:
   - TokenBar.app 더블클릭 → "열 수 없음" 창에서 [완료]
   - 시스템 설정 → 개인정보 보호 및 보안 → 아래로 스크롤
     → "TokenBar은(는) 차단되었습니다" 옆 [그래도 열기] 클릭

   또는 터미널에서 한 줄:
   xattr -d com.apple.quarantine /Applications/TokenBar.app

3. 실행하면 메뉴바 오른쪽 위에 "C.. X.." 표시가 나타납니다. 클릭하면 상세 정보.

4. 키체인 접근 창("Claude Code-credentials")이 뜨면 [항상 허용]을 누르세요.
   → Claude 남은 한도(%)를 표시하는 데 필요합니다. 거부해도 토큰 수는 나옵니다.

5. 위젯 추가: 바탕화면 우클릭 → 위젯 편집 → "TokenBar" 검색
   ※ 위젯이 목록에 안 보이면 로그아웃 후 재로그인 또는 Mac 재시동

문제가 있으면 앱을 재실행해 보세요.
EOF

cd dist
ditto -c -k --sequesterRsrc --keepParent TokenBar TokenBar-mac.zip
rm -rf TokenBar
cd ..

echo ""
echo "✅ 완료: dist/TokenBar-mac.zip"
echo ""
echo "공유 방법:"
echo "  - 카톡/메일/드라이브로 zip 그대로 전달하거나"
echo "  - GitHub 저장소 → Releases → 'Draft a new release' → zip 업로드"
echo "  (자세한 건 배포안내.md 참고)"
