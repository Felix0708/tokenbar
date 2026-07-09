#!/bin/bash
# TokenBar 원클릭 빌드 & 설치 스크립트
set -e
cd "$(dirname "$0")"

echo "==> TokenBar 빌드를 시작합니다."

# 1. Xcode 확인
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "오류: Xcode가 필요합니다. App Store에서 Xcode를 설치한 뒤 다시 실행하세요."
    exit 1
fi

# 2. xcodegen 확인 (프로젝트 파일 생성 도구)
# Apple Silicon인데 터미널이 Rosetta(x86)로 돌면 brew가 거부하므로 arch -arm64 강제
BREW="brew"
if [ "$(sysctl -in hw.optional.arm64 2>/dev/null)" = "1" ] && [ "$(uname -m)" != "arm64" ]; then
    BREW="arch -arm64 brew"
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "==> xcodegen 설치 중 (Homebrew)..."
        $BREW install xcodegen
    else
        echo "오류: xcodegen이 필요합니다."
        echo "  Homebrew 설치 후:  brew install xcodegen"
        echo "  또는 Xcode에서 직접 프로젝트를 만들어도 됩니다 (README.md 참고)."
        exit 1
    fi
fi

# 3. 앱 아이콘 (없으면 iconset에서 생성)
if [ ! -f "App/Resources/AppIcon.icns" ] && [ -d "assets/AppIcon.iconset" ]; then
    mkdir -p App/Resources
    iconutil -c icns assets/AppIcon.iconset -o App/Resources/AppIcon.icns
fi

# 4. 프로젝트 생성
echo "==> Xcode 프로젝트 생성 중..."
xcodegen generate

# 5. 서명 방식 결정
# Apple Development 인증서가 있으면 사용 — 위젯이 위젯 갤러리에 확실히 등록됨.
# 없으면 임시(ad-hoc) 서명 — 앱은 작동하지만 위젯 등록이 불안정할 수 있음.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | sed 's/.*"\(.*\)".*/\1/')
if [ -n "$IDENTITY" ]; then
    echo "==> 서명: $IDENTITY"
    SIGN_ID="$IDENTITY"
else
    echo "==> 서명: 임시(ad-hoc)"
    echo "    ⚠️ 위젯이 갤러리에 안 나오면: Xcode → Settings → Accounts → Apple ID 추가"
    echo "       → Manage Certificates → + → Apple Development 생성 후 ./setup.sh 재실행"
    SIGN_ID="-"
fi

# 6. 빌드
echo "==> 빌드 중... (1~2분 걸릴 수 있습니다)"
xcodebuild -project TokenBar.xcodeproj \
    -scheme TokenBar \
    -configuration Release \
    -derivedDataPath build \
    build \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    CODE_SIGNING_REQUIRED=YES \
    | grep -E "^\*\*|error:" || true

APP="build/Build/Products/Release/TokenBar.app"
if [ ! -d "$APP" ]; then
    echo "빌드 실패. Xcode에서 TokenBar.xcodeproj를 열어 직접 빌드해 보세요."
    exit 1
fi

# 7. 설치
echo "==> /Applications 에 설치 중..."
osascript -e 'quit app "TokenBar"' 2>/dev/null || true
rm -rf /Applications/TokenBar.app
cp -R "$APP" /Applications/

# 8. 위젯을 시스템에 강제 등록하고 위젯 갤러리 새로고침
pluginkit -a /Applications/TokenBar.app/Contents/PlugIns/TokenBarWidget.appex 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true

# 9. 실행
open /Applications/TokenBar.app

# 10. 위젯 등록 확인
sleep 3
if pluginkit -m 2>/dev/null | grep -qi "tokenbar"; then
    echo "==> 위젯 등록 확인 ✓"
else
    echo "==> ⚠️ 위젯이 아직 시스템에 등록되지 않았습니다."
    echo "    ad-hoc 서명이면 위 안내대로 Apple Development 인증서를 만들어 재실행하거나,"
    echo "    Mac을 재시동한 뒤 위젯 검색을 다시 해보세요."
fi

echo ""
echo "✅ 완료! 메뉴바 오른쪽 위에 도토리 아이콘이 나타납니다."
echo ""
echo "위젯 추가 방법:"
echo "  1. 바탕화면 우클릭 → '위젯 편집' (또는 메뉴바 시계 클릭 → 알림 센터 하단 '위젯 편집')"
echo "  2. 'TokenBar' 검색 → 위젯 추가"
echo "  ※ 위젯이 목록에 안 보이면 Mac을 재시동하거나, README.md의 문제 해결 참고"
