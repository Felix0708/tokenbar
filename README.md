# TokenBar

Claude Code, Codex CLI, Gemini CLI의 사용량과 한도 정보를 **메뉴바 + 알림 센터 위젯**으로 보여주는 macOS 앱.

현재 기능과 변경 이유는 [DEVELOPMENT_HISTORY.md](DEVELOPMENT_HISTORY.md)에 문제 해결 흐름과 함께 기록해두었습니다.

## 보여주는 정보

| 항목 | Claude | Codex | Gemini |
|---|---|---|---|
| 한도 사용률 | OAuth usage API (5시간/주간) | 세션 로그의 `rate_limits` (5시간/주간) | 요청 수 ÷ 일일 한도 추정 |
| 구독 플랜 | `claude auth status --json` | 세션 로그의 `plan_type` | quota 정보가 있을 때만 자동 감지 |
| 오늘 사용 토큰 | `~/.claude/projects` 로그 | `~/.codex/sessions` 로그 | `~/.gemini/tmp` 로그 |
| 총 사용 토큰 | 〃 | 〃 | 〃 |
| 예상 비용 ($) | API 단가로 환산 (추정치) | 〃 | 〃 |

메뉴바에는 각 서비스의 한도 사용률이 압축 표시되고, 클릭하면 상세 패널이 열립니다.

## 현재 기능

- Claude: 로컬 로그의 토큰/비용 + Anthropic OAuth 사용률 API의 5시간·주간 한도
- Codex: 세션 로그의 토큰/비용 + 마지막 `rate_limits` 기록의 5시간·주간 한도
- Gemini: 로컬 CLI 로그의 토큰/비용 + 기록된 요청 수 기반 일일 한도 추정
- 모델별 사용량: 실제 로그에 기록된 모델을 자동 수집해 접었다 펼 수 있는 목록으로 표시
- 모델 자동 갱신: 새 모델은 사용 후 다음 자동 갱신에 나타나며, 로그가 삭제되면 목록에서도 사라짐
- 구독 플랜: Claude `subscriptionType`, Codex `plan_type`을 읽어 서비스 옆에 표시
- Gemini 플랜: 구조화된 quota 정보가 발견될 때만 AI Pro/AI Ultra 등을 확정하고, 없으면 수동 한도 선택
- 인증 보조: Claude 로그인이 없으면 메뉴에서 `claude auth login` 터미널 실행
- 안전한 실패 표시: 조회할 수 없는 값을 임의의 0%나 0토큰으로 꾸미지 않음
- 자동 갱신: 앱 데이터는 1분마다, 위젯은 15분마다 갱신

## 데이터가 갱신되는 방식

TokenBar는 모델 목록이나 플랜 목록을 코드에 고정하지 않습니다. 각 실행 시 다음 로컬 데이터를 다시 읽습니다.

| 공급자 | 읽는 위치 | 모델 목록 | 한도/플랜 |
|---|---|---|---|
| Claude | `~/.claude/projects` | 로그에 실제 등장한 모델 | OAuth API, `claude auth status --json` |
| Codex | `~/.codex/sessions` | 세션에 실제 등장한 모델 | 최신 `rate_limits`, `plan_type` |
| Gemini | `~/.gemini/tmp` 및 계정 설정 | CLI 기록에 실제 등장한 모델 | 요청 수 추정, 구조화된 quota 정보 |

새 모델이 공급자에 추가되어도 별도 코드 수정은 필요하지 않습니다. 해당 모델을 실제로 사용하고 로그가 생기면 1분 이내 또는 앱 재시작 후 자동 반영됩니다. 공급자가 모델을 더 이상 제공해도 과거 로그가 남아 있으면 과거 사용 모델로 계속 보이며, 로그까지 삭제된 뒤 다음 갱신에서 사라집니다.

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
- 모델별 목록은 로컬 로그에서 실제로 사용된 모델을 전부 표시하며, 항목이 많으면 목록을 스크롤할 수 있음
- Claude/Codex에서 확인된 구독 플랜은 서비스 이름 옆에 배지로 표시됨 (예: `Pro`, `Plus`)
- Gemini는 공식 CLI quota 정보가 로컬 기록에 남아 있을 때만 `AI Pro`/`AI Ultra` 등을 자동 확정함
- Gemini 계정 파일에 이메일만 있고 quota/플랜 정보가 없으면 잘못된 플랜을 표시하지 않고 수동 일일 한도를 유지함
- 진행 바 색: 정상 → **노랑(70%↑)** → **빨강(90%↑)**
- 모델 이름 옆의 `모델별 보기 (N)`을 누르면 전체 모델 목록을 확인할 수 있음

## 문제 해결

**위젯이 목록에 안 보임**
- 앱을 한 번 실행한 뒤 몇 분 기다리거나 Mac 재시동
- 그래도 안 되면: Xcode로 `TokenBar.xcodeproj`를 열고 두 타겟(TokenBar, TokenBarWidget)의 Signing & Capabilities에서 본인 Apple ID 팀으로 서명 설정 후 다시 빌드 (`./setup.sh` 재실행 전에 `CODE_SIGN_IDENTITY` 부분 제거)

**Claude 한도 %가 안 나옴**
- `claude auth status`가 `loggedIn: false`면 `claude auth login` 실행
- 로그인 후 Claude Code를 한 번 실행해 키체인 토큰을 생성
- 키체인 접근을 거부했다면: 키체인 접근 앱에서 'Claude Code-credentials' 항목 → 접근 제어에 TokenBar 추가
- Anthropic usage API가 429로 차단되면 마지막 성공값을 유지하고 조회 시각을 표시함
- 앱에 `로그인` 버튼이 표시되면 버튼으로 터미널 로그인 실행 가능 (브라우저 인증은 직접 완료 필요)

**Codex 한도 %가 안 나옴**
- Codex CLI를 대화형(TUI)으로 한 번 실행하면 세션 로그에 rate_limits가 기록됩니다 (`codex exec` 모드는 기록 안 됨)
- 한도 퍼센트는 마지막 Codex 세션 로그 기준이며, 새 세션 전에는 최신 서버값이 아닐 수 있음

**Gemini 오늘 사용량이 안 나옴**
- Gemini CLI에서 `/stats model`로 실제 토큰/쿼터를 확인할 수 있음
- 현재 로그에 토큰 필드가 없으면 앱은 임의로 0으로 계산하지 않고 '확인할 수 없음'으로 표시함
- Gemini의 무료/Pro/Ultra 구분은 계정 이메일이나 `oauth-personal`만으로는 판별할 수 없음. 공식 CLI quota 응답이 필요함

**새 모델이 바로 안 보임**
- 모델을 실제로 한 번 사용했는지 확인
- 공급자 CLI가 로그를 기록한 뒤 TokenBar 새로고침 버튼을 누르거나 1분 대기
- 과거 모델이 계속 보이면 과거 로그가 남아 있기 때문이며, 이는 사용 이력 보존을 위한 정상 동작

**빌드 실패**
- `xcode-select --install` 후 재시도
- Xcode에서 직접 열어 빌드: `xcodegen generate` → `open TokenBar.xcodeproj` → ▶ 실행

## 정확도에 대해

- 토큰 수·비용은 **로컬 로그 기반 추정치**입니다. 실제 청구/한도 계산과 다를 수 있습니다.
- 비용은 API 정가 기준 환산이므로 구독 요금제(Pro/Max/Plus) 사용자에게는 "API로 썼다면 이만큼" 수준의 참고치입니다.
- Codex의 오늘 사용량은 세션 시작 날짜 기준으로 집계됩니다 (자정을 넘긴 세션은 시작일에 포함).
- 새 모델은 별도 등록 없이 로그에 기록되는 이름 그대로 모델 목록에 표시됩니다. 아직 사용하지 않은 모델은 표시되지 않습니다.

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
│   ├── GeminiLogParser.swift    # ~/.gemini/tmp 파싱 (증분 캐시)
│   ├── ClaudeOAuthClient.swift # 남은 한도 API (5분 캐시, 429 백오프)
│   ├── Pricing.swift           # 모델별 단가표
│   └── MenuContentView.swift   # 메뉴바 패널 UI
├── Shared/              # 앱·위젯 공용
│   └── UsageTypes.swift        # 데이터 모델 + 스냅샷 파일 저장소
├── README.md             # 설치·사용법·현재 기능
├── DEVELOPMENT_HISTORY.md # 변경 이유와 아이디어 확장 기록
└── Widget/
    └── TokenBarWidget.swift    # 알림 센터 위젯
```
