# NonSleep

세 가지 기능을 각각 전환하는 macOS 메뉴 막대 앱입니다. SwiftUI로 작성했으며 외부 패키지가 필요 없습니다. macOS 14 이상에서 사용할 수 있습니다.

## 빌드 및 실행

Xcode 15.3 이상 또는 해당 Swift 도구가 필요합니다. 프로젝트 디렉터리에서 실행하세요.

```sh
./scripts/build.sh
open build/NonSleep.app
```

결과물은 `build/NonSleep.app`입니다. Applications 폴더로 복사해 사용할 수도 있습니다. 실행하면 화면 오른쪽 위 메뉴 막대에 커피잔 아이콘이 표시됩니다. 아이콘을 클릭하면 세 스위치가 있는 제어판이 열리고, 우클릭하면 기능별 빠른 제어 메뉴가 열립니다. 기능을 사용하면 커피잔 아이콘이 채워진 모양으로 바뀝니다. 제어판 밖을 클릭하면 닫히며 앱은 메뉴 막대에서 계속 실행됩니다. 소스 작업은 `Package.swift`를 Xcode로 열면 됩니다. 앱 번들 생성은 위 스크립트를 사용하세요.

상태바 아이콘은 기능 조합에 따라 색이 바뀝니다. 마우스를 올리면 켜진 기능 이름도 확인할 수 있습니다.

| 켜진 기능 | 아이콘 색 |
| --- | --- |
| 모두 꺼짐 | 회색 |
| 잠자기 방지 | 초록 |
| 덮어도 깨어 있기 | 파랑 |
| 방해 금지 | 보라 |
| 잠자기 방지 + 덮어도 깨어 있기 | 청록 |
| 잠자기 방지 + 방해 금지 | 주황 |
| 덮어도 깨어 있기 + 방해 금지 | 분홍 |
| 세 기능 모두 | 노랑 |

개발 테스트:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --cache-path "$PWD/.build/cache"
```

## 기능과 최초 설정

| 스위치 | 동작 | 최초 설정 |
| --- | --- | --- |
| 잠자기 방지 | IOKit assertion으로 유휴 시스템 잠자기와 화면 꺼짐 방지 | 없음 |
| 덮어도 깨어 있기 | `pmset -a disablesleep 1` 적용 및 읽기 검증 | 설정에서 전원 도우미를 한 번 등록하거나, 전환할 때마다 관리자 인증 |
| 방해 금지 | 연결한 Apple 단축어로 집중 모드 켜기·끄기 | 아래 단축어 두 개 연결 |

### 자동 실행과 관리자 권한 설정

상태바 커피잔 → **설정 → 일반**에서 관리합니다. 우클릭 메뉴의 ‘설정…’ 또는 `⌘,`로도 열 수 있습니다.

설정은 메뉴 막대 팝업과 별도의 일반 창으로 열립니다. 설정 창을 닫거나 다른 앱으로 이동한 뒤에도 제어판의 스위치와 버튼을 계속 사용할 수 있습니다.

- **로그인 시 자동 실행**: macOS `SMAppService.mainApp`으로 등록·해제합니다. 단순한 앱 내부 저장값이 아니라 실제 시스템 등록 상태를 표시합니다. 시스템에서 차단하면 ‘승인 필요’로 표시되며 ‘로그인 항목 열기’에서 확인할 수 있습니다. 앱을 응용 프로그램 폴더로 옮긴 뒤 설정하는 것을 권장합니다.
- **덮개 잠자기 권한 → 관리자 권한 받기…**: macOS 관리자 인증 창에서 전원 도우미 설치를 승인합니다. 이후 기능 전환과 종료 시 복원은 XPC로 요청하며 반복 인증하지 않습니다. 인증 비밀번호나 `sudo` 세션을 저장하지 않습니다.
- **도우미 제거…**: 덮개 기능을 끄고 이전 전원 설정을 복원한 뒤 도우미를 제거할 수 있습니다. 제거 시에는 관리자 인증이 필요합니다.

도우미를 등록하지 않아도 기존처럼 전환할 때마다 인증하여 사용할 수 있습니다. 외부의 별도 ‘방해 금지’ 단축어 설정은 설정 창의 ‘방해 금지’ 탭에 있습니다.

앱을 단순히 껐다 켜는 경우에는 도우미 승인 상태가 유지됩니다. 개발용 ad-hoc 서명은 앱의 코드 해시에 연결되므로, 앱을 새로 빌드한 경우에는 ‘앱 업데이트로 권한 갱신 필요’로 표시되며 ‘업데이트 권한 승인…’을 한 번 눌러야 합니다. 기존 도우미가 삭제된 것은 아닙니다. 배포용으로 동일한 Developer ID 서명을 유지하면 코드 서명 요구사항으로 동일한 앱과 도우미를 식별합니다. 서명 identity를 지정해 빌드하려면 `NONSLEEP_SIGNING_IDENTITY='Developer ID Application: …' ./scripts/build.sh`를 사용합니다.

### 방해 금지 단축어 연결

1. Apple 단축어 앱에서 ‘집중 모드 설정’ 동작이 있는 단축어 두 개를 만듭니다.
2. 첫 번째는 ‘방해 금지’를 **켬**, 지속 시간은 **끔으로 설정할 때까지**로 지정합니다.
3. 두 번째는 ‘방해 금지’를 **끔**으로 지정합니다. 토글 동작 대신 명시적인 켜기/끄기를 사용하세요.
4. NonSleep의 ‘설정 → 방해 금지’에서 목록을 새로고침하고 각각 선택합니다.
5. 모든 알림을 조용히 하려면 시스템 설정 → 집중 모드 → 방해 금지에서 허용된 사람·앱을 비우고, 반복 통화·시간 지정 알림 등 예외를 해제합니다. 긴급 알림 등 macOS가 허용하는 예외까지 앱이 강제로 차단하지는 못합니다.

단축어 이름은 자유롭게 정할 수 있으며 셸에 삽입하지 않고 인자로 전달합니다. NonSleep은 단축어의 종료 코드만 확인합니다. 연결한 단축어의 내용이나 실제 집중 모드를 검증하지 못하므로 스위치는 **최근 실행 요청**을 나타냅니다. 앱을 다시 열었거나 시스템에서 직접 변경한 상태는 알 수 없습니다. ‘상태 미확인’ 상태에서 끄려면 방해 금지 행의 우클릭 메뉴 또는 설정 화면의 ‘끄기 실행’을 사용하세요. 집중 모드는 앱 종료 후에도 유지됩니다.

### 덮개 기능과 복원

`disablesleep`는 시스템 전체 설정으로, 덮개 잠자기와 일반 시스템 잠자기를 함께 차단합니다. 일반 잠자기 스위치를 꺼도 덮개 기능이 켜져 있으면 시스템은 계속 깨어 있습니다. 화면 유지 assertion은 일반 잠자기 스위치를 따릅니다. 전원 도우미 등록 전에는 이 기능의 켜기·끄기·종료 시 복원에 관리자 인증이 필요할 수 있습니다.

앱은 변경 전 값을 먼저 저장합니다. 정상 종료 시 앱이 변경한 전원 설정을 복원하며, 복원 실패 또는 인증 취소 시 종료를 중단하고 오류를 표시합니다. 실행 전부터 다른 앱이 켜둔 설정은 종료 시 임의로 끄지 않습니다. 강제 종료나 정전 이후에는 설정이 남을 수 있으므로 다음 실행에서 ‘복원’을 누르세요. 앱 없이 수동으로 해제하려면 터미널에서 다음을 실행할 수 있습니다.

```sh
sudo pmset -a disablesleep 0
```

`disablesleep`는 Apple의 전원 관리 소스에 존재하지만 공개 `pmset` 매뉴얼에 문서화되지 않은 옵션입니다. 기기와 macOS 버전별 덮개 동작은 실기기 확인이 필요합니다. 잠자기 방지는 저전력·온도 보호·강제 종료를 무력화하지 않습니다. 덮은 상태로 사용할 때는 통풍되는 곳에 두세요.

## 전원 도우미 구조

도우미는 코드 서명된 `NonSleepHelper` 실행 파일이며 launchd의 온디맨드 Mach 서비스로 동작합니다. 현재 로컬 빌드에는 Apple 발급 서명 인증서가 필요하지 않도록 관리자 인증을 통한 설치 방식을 사용합니다. 다음 세 파일만 고정 경로에 root 소유로 설치합니다.

```text
/Library/PrivilegedHelperTools/dev.nonsleep.helper
/Library/PrivilegedHelperTools/dev.nonsleep.helper.client-requirement
/Library/LaunchDaemons/dev.nonsleep.helper.plist
```

앱과 도우미는 양쪽 모두 `NSXPCConnection.setCodeSigningRequirement`로 상대 코드 서명을 검증합니다. 설치 프로그램은 root 전용 임시 폴더에 도우미를 복사한 뒤 기대한 코드 서명과 일치하는지 검증하고 설치합니다. 서비스 설정과 클라이언트 서명 요구사항도 이 폴더에서 생성합니다. 도우미가 받는 요청은 연결 확인과 `SleepDisabled`의 Bool 값뿐이며 명령 문자열·경로·암호를 받지 않습니다. 실제 실행 명령은 고정된 `/usr/bin/pmset` 인자만 사용합니다. 앱이 강제 종료되더라도 다음 실행에서 기존 복원 기록을 사용할 수 있습니다.

테스트는 실제 IOKit assertion 생성·해제, 로그인 항목 등록 실패·해제 실패·외부 취소 처리, 익명 XPC 메시지 전달, 코드 서명 요구사항의 일치·불일치 검증을 포함합니다. 실제 privileged XPC 연결과 관리자 설치·제거, 재로그인 자동 실행은 사용자 승인이 필요한 통합 확인 항목입니다. 테스트 중에는 관리자 도우미를 설치하거나 시스템 로그인 설정을 변경하지 않습니다.

## 배포

현재 스크립트는 개발용 ad-hoc 서명을 사용합니다. 외부 배포용 Developer ID 서명과 Apple 공증은 포함하지 않습니다. 관리자 명령을 실행하는 로컬 앱이므로 App Sandbox는 사용하지 않습니다. App Store 배포 구조는 별도로 설계해야 합니다.

### GitHub Release 자동 생성

`.github/workflows/release.yml`은 버전 태그를 푸시하면 Apple Silicon과 Intel 환경에서 각각 테스트한 뒤 앱을 빌드합니다. 두 빌드가 모두 성공하면 다음 파일을 GitHub Release에 첨부합니다.

- `NonSleep-<버전>-macos-arm64.zip`: Apple Silicon용
- `NonSleep-<버전>-macos-x86_64.zip`: Intel용
- `SHA256SUMS.txt`: 다운로드 파일 검증용 SHA-256 체크섬

배포할 커밋에 태그를 만들고 푸시하세요. 태그는 `v0.2.0`처럼 지정하며, `v0.3.0-beta.1` 같은 태그는 프리릴리스로 게시합니다.

```sh
git tag -a v0.2.0 -m "NonSleep 0.2.0"
git push origin v0.2.0
```

GitHub의 **Actions → Release → Run workflow**에서도 실행할 수 있습니다. `tag`를 비우고 `publish`를 끄면 선택한 브랜치를 빌드해 Actions 아티팩트만 생성합니다. 기존 태그의 Release를 만들려면 해당 태그를 입력하고 `publish`를 켜세요. 존재하지 않는 태그는 자동으로 생성하지 않습니다.

Release는 두 ZIP의 체크섬 검증과 업로드가 끝난 뒤 게시합니다. 이미 게시한 Release는 덮어쓰지 않으며, 실패한 작업의 초안은 재실행 시 이어서 사용할 수 있습니다. 게시 완료 후 변경하려면 새 버전 태그를 사용하세요.

별도 Secrets 없이 `GITHUB_TOKEN`으로 동작합니다. 현재 워크플로 산출물은 **ad-hoc 서명된 미공증 앱**이며, Developer ID 서명과 Apple 공증을 거친 배포본은 아닙니다. 태그의 숫자 부분을 앱 버전에, Actions 실행 번호를 빌드 번호에 기록합니다. 원본 `Resources/Info.plist`는 변경하지 않습니다.

로컬에서 같은 버전 정보를 넣어 별도 폴더에 빌드하려면 다음과 같이 실행할 수 있습니다.

```sh
NONSLEEP_VERSION=0.2.0 NONSLEEP_BUILD_NUMBER=1 \
NONSLEEP_APP_DIR="$PWD/build/release/NonSleep.app" ./scripts/build.sh
```

## 근거

- [Apple: 유휴 잠자기 방지 assertion의 범위](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
- [Apple: 명령줄에서 단축어 실행](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac)
- [Apple: 로그인 항목과 서비스 관리](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple: XPC 연결의 코드 서명 검증](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:))
- [Apple 공개 소스: pmset의 disablesleep 처리](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
