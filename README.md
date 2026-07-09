# TokenBar

Claude Code와 Codex CLI의 토큰 사용량을 **메뉴바 + 알림 센터 위젯**으로 보여주는 macOS 앱.

## 보여주는 정보

| 항목 | Claude | Codex |
|---|---|---|
| 5시간 한도 사용률 (%) | OAuth usage API | 세션 로그의 rate_limits |
| 주간 한도 사용률 (%) | OAuth usage API | 세션 로그의 rate_limits |
| 오늘 사용 토큰 | `~/.claude/projects` 로그 | `~/.codex/sessions` 로그 |
| 총 사용 토큰 | 〃 | 〃 |
| 예상 비용 ($) | API 단가로 환산 (추정치) | 〃 |

메뉴바에는 `C37 X12` 처럼 두 서비스의 5시간 사용률이 압축 표시되고, 클릭하면 상세 패널이 열립니다.

## 설치 (Xcode 필요)

터미널에서:

```bash
cd "이 폴더 경로"
chmod +x setup.sh
./setup.sh
```

스크립트가 자동으로: xcodegen 설치(brew) → 프로젝트 생성 → 빌드 → `/Applications/TokenBar.app` 설치 → 실행.

### 위젯 추가

1. 바탕화면 우클릭 → **위젯 편집** (또는 알림 센터 하단 '위젯 편집')
2. **TokenBar** 검색 → 원하는 크기(소형/중형) 추가

### 첫 실행 시 키체인 허용

Claude 남은 한도(%)를 읽으려면 Claude Code의 로그인 토큰이 필요합니다.
첫 실행 때 **"TokenBar가 'Claude Code-credentials'에 접근하려고 합니다"** 창이 뜨면 **항상 허용**을 누르세요.
(거부해도 토큰 수·비용은 정상 표시되고, 한도 %만 빠집니다)

## 사용 팁

- 상세 패널 하단: 🔄 새로고침 / ⭕ 로그인 시 자동 시작 / ⏻ 종료
- 데이터는 1분마다 자동 갱신, 위젯은 15분마다 + 앱 갱신 시 함께 갱신
- 진행 바 색: 정상 → **노랑(70%↑)** → **빨강(90%↑)**

## 문제 해결

**위젯이 목록에 안 보임**
- 앱을 한 번 실행한 뒤 몇 분 기다리거나 Mac 재시동
- 그래도 안 되면: Xcode로 `TokenBar.xcodeproj`를 열고 두 타겟(TokenBar, TokenBarWidget)의 Signing & Capabilities에서 본인 Apple ID 팀으로 서명 설정 후 다시 빌드 (`./setup.sh` 재실행 전에 `CODE_SIGN_IDENTITY` 부분 제거)

**Claude 한도 %가 안 나옴**
- Claude Code를 터미널에서 한 번 실행 (토큰 갱신됨)
- 키체인 접근을 거부했다면: 키체인 접근 앱에서 'Claude Code-credentials' 항목 → 접근 제어에 TokenBar 추가

**Codex 한도 %가 안 나옴**
- Codex CLI를 대화형(TUI)으로 한 번 실행하면 세션 로그에 rate_limits가 기록됩니다 (`codex exec` 모드는 기록 안 됨)

**빌드 실패**
- `xcode-select --install` 후 재시도
- Xcode에서 직접 열어 빌드: `xcodegen generate` → `open TokenBar.xcodeproj` → ▶ 실행

## 정확도에 대해

- 토큰 수·비용은 **로컬 로그 기반 추정치**입니다. 실제 청구/한도 계산과 다를 수 있습니다.
- 비용은 API 정가 기준 환산이므로 구독 요금제(Pro/Max/Plus) 사용자에게는 "API로 썼다면 이만큼" 수준의 참고치입니다.
- Codex의 오늘 사용량은 세션 시작 날짜 기준으로 집계됩니다 (자정을 넘긴 세션은 시작일에 포함).

## 폴더 구조

```
TokenBar/
├── project.yml          # xcodegen 프로젝트 정의
├── setup.sh             # 원클릭 빌드·설치
├── App/                 # 메뉴바 앱
│   ├── TokenBarApp.swift
│   ├── UsageModel.swift        # 1분 주기 갱신, 스냅샷 저장
│   ├── ClaudeLogParser.swift   # ~/.claude/projects 파싱 (증분 캐시)
│   ├── CodexLogParser.swift    # ~/.codex/sessions 파싱 (증분 캐시)
│   ├── ClaudeOAuthClient.swift # 남은 한도 API (5분 캐시, 429 백오프)
│   ├── Pricing.swift           # 모델별 단가표
│   └── MenuContentView.swift   # 메뉴바 패널 UI
├── Shared/              # 앱·위젯 공용
│   └── UsageTypes.swift        # 데이터 모델 + 스냅샷 파일 저장소
└── Widget/
    └── TokenBarWidget.swift    # 알림 센터 위젯
```
