# Ubuntu 26 Legion5 Setup

Ubuntu 26.04 대응 작업을 [ubuntu24-legion5-setup](https://github.com/devchan64/ubuntu24-legion5-setup)에서 분리한 독립 저장소입니다.
26.04 전용이며, 상태 파일은 `~/.local/state/ubuntu26-legion5-setup/`에 별도로 저장합니다.

```bash
git clone https://github.com/devchan64/ubuntu26-legion5-setup.git
cd ubuntu26-legion5-setup
./scripts/install-all.sh help
```

Ubuntu **26.04 LTS (resolute, Wayland)** 환경에서
**개발 / Codex / AI / 미디어(ai-virtual-cam) / 네트워크 / 운영 / 보안** 설정을
**Fail-Fast · 멱등(resumable) · 무폴백** 원칙으로 자동화합니다.

> 철학
>
> - 폴백 없음 (전제 불충족 시 즉시 실패)
> - 실패 즉시 종료 (`set -Eeuo pipefail`)
> - 단계 단위 멱등성(resume)
> - 재부팅 경계(reboot barrier) 계약 강제
> - 로그는 원인 추적 가능해야 함

본 레포는 **ChatGPT와 에이전트 협업 규약을 공유**하며 발전시키기 위해
설계/규약을 `AGENTS.md`에 **SSOT**로 유지합니다.

---

## 대상 환경 (Reference)

- **OS**: Ubuntu 26.04 LTS (`resolute`) 전용
- **세션**: Wayland
- **검증 범위**: 26.04 분기와 Bash 정적 검증. 26.04 실기기 전체 설치 검증은 별도 필요
- 26.04에서는 CUDA를 Ubuntu 공식 `cuda-toolkit`으로 설치합니다. 24.04 전용 CUDA 로컬 저장소 변수는 사용할 수 없습니다.
- 26.04 실행 재개 기록은 `.ubuntu-26.04` 접미사로 분리합니다. 기존 상태 디렉터리는 유지합니다.
- Nord 터미널 팔레트는 별도로 설치하는 GNOME Terminal에 적용됩니다. 기본 Ptyxis 테마는 변경하지 않습니다.
- **쉘**: **bash 전용**
- **하드웨어(참고)**: Lenovo Legion 5 15IAX10
  (Intel iGPU + NVIDIA dGPU Hybrid)

---

## 핵심 문서

- 📘 **[AGENTS.md](./AGENTS.md)**
  프로젝트 철학, 구조, 실행 계약, resume 및 reboot barrier 규칙의 **SSOT**
- 📝 **[docs/release-notes/README.md](./docs/release-notes/README.md)**
  사용자 영향이 있는 변경사항과 릴리즈 노트 목록

---

## 디렉터리 구조

```text
.
├── lib/
│   └── common.sh           # 공통 유틸 / 로깅 / resume / reboot barrier 관리
├── scripts/
│   ├── install-all.sh      # 최상위 디스패처 (SSOT)
│   ├── cmd/                # 진입점 커맨드 (dev/codex/sys/media/...)
│   │   ├── dev.sh
│   │   ├── codex.sh
│   │   ├── sys.sh
│   │   ├── net.sh
│   │   ├── ops.sh
│   │   ├── security.sh
│   │   ├── media.sh
│   │   └── ml.sh
│   ├── codex/
│   ├── dev/
│   ├── sys/
│   ├── net/
│   ├── ops/
│   ├── security/
│   ├── media/
│   └── ml/
└── background/
```

---

## 실행 방식

모든 진입점은 일반 사용자로 실행합니다. 시스템 변경 권한이 필요한 하위 명령만 실행 중 인증 프롬프트를 사용합니다.

### 1. 전체 실행

```bash
./scripts/install-all.sh all
```

### 2. 단일 도메인 실행

```bash
./scripts/install-all.sh dev
./scripts/install-all.sh codex
./scripts/install-all.sh sys
./scripts/install-all.sh media
```

### 3. 실행 순서 (코드 기준, SSOT)

`all` 실행 시 **아래 순서로 고정**됩니다:

```
dev → sys → net → ops → security → media → ml
```

> 순서는 의존성을 반영하며 임의 변경 불가 (Breaking)

---

## 도메인별 가이드

각 도메인은 **독립 실행 가능**하지만, 전체 실행 시에는 정해진 순서를 따릅니다.
아래 가이드는 _단독 실행_ 및 _문제 발생 시 재실행_ 기준입니다.

---

### dev (개발 환경)

**목적**

- 개발자 기본 도구 체인 구성
- 컨테이너/에디터/빌드 환경 준비

**포함 예시**

- Docker / NVIDIA Container Toolkit
- 코드 에디터 및 확장
- VS Code Continue 인라인 자동완성

```bash
./scripts/install-all.sh dev
```

**계약**

- 이후 단계(sys, ml)에서 GPU 설정을 참조
- 실패 시 전체 실행 중단이 정상 동작

---

### codex (Codex CLI / Desktop)

**목적**

- Codex CLI 설치
- Codex Desktop 설치
- ChatGPT Desktop 비정상 종료 시 자동 재시작 사용자 서비스 설정

**포함 예시**

- Codex standalone installer 실행
- OpenAI Codex App 저장소의 `chatgpt` 패키지 설치
- `chatgpt-restart.service` 활성화 및 시작

```bash
./scripts/install-all.sh codex
```

**계약**

- 일반 사용자로 실행하며, 권한이 필요한 시스템 변경은 실행 중 인증 프롬프트 사용
- `curl`, `sh`, `apt-get`, 네트워크 연결이 필요
- Codex Desktop은 amd64 환경에서 설치하며, 패키지 설치 시 인증 프롬프트가 표시됨
- `CODEX_INSTALL_DIR` 미지정 시 `${HOME}/.local/bin/codex`에 설치
- ChatGPT Desktop이 종료되면 5초 뒤 다시 시작함. 완전히 종료하려면 먼저 서비스를 중지해야 함
- 서비스 시작 시 기존 ChatGPT 프로세스를 종료한 뒤 서비스가 직접 실행하므로, 이미 열려 있던 앱 창은 한 번 다시 열림

---

### sys (시스템 / GNOME / NVIDIA)

**목적**

- OS 레벨 설정 및 하드웨어 의존 구성

**포함 예시**

- 26.04 Wayland 세션 준비
- GNOME 튜닝
- NVIDIA 드라이버 설치
- 커널/디스플레이 스택 설정

```bash
./scripts/install-all.sh sys
```

**계약**

- 일반 사용자로 실행하며, 시스템 변경 명령에서 sudo 인증 프롬프트 사용
- NVIDIA 설치 또는 Wayland 전환 시 **reboot barrier 발생 가능**
- 재부팅 전에는 다음 단계 진행 불가
- xrandr 자동 배치와 수동 복구 스크립트 배포는 폐기했습니다. 화면 확장, 위치, 해상도, 주사율은 **설정 → 디스플레이**에서 관리합니다.
- 과거 배포된 `~/.local/bin/monitor-hotplug-apply.sh`는 더 이상 사용하지 마세요. 기존 파일과 사용자 모니터 설정은 자동 삭제하지 않습니다.

**외부 모니터 미검출 점검**

재부팅 후에도 HDMI/DP 외부 모니터가 잡히지 않으면 다음 순서로 확인합니다.

```bash
nvidia-smi
modinfo -k "$(uname -r)" nvidia
for s in /sys/class/drm/*/status; do printf "%s=%s\n" "$s" "$(cat "$s")"; done
```

- `nvidia-smi`가 실패하면 현재 커널용 NVIDIA 모듈 설치 여부를 먼저 확인합니다.
- `590`, `595` 등 NVIDIA 드라이버 계열이 섞여 있으면 실제 사용 계열 하나로 정리합니다.
- `/sys/class/drm/*/status`에서 외부 출력이 모두 `disconnected`이면 커널/드라이버 또는 물리 연결부터 점검합니다.
- GNOME 캐시가 오래된 경우 `~/.config/monitors.xml`을 백업한 뒤 재로그인합니다.
- NVIDIA Runtime PM 영향이 의심되면 dGPU `power/control`을 `on`으로 고정한 뒤 재부팅합니다.

---

### net (네트워크)

**목적**

- 네트워크 안정성 및 외부 연결 확보

**포함 예시**

- Wi-Fi 드라이버
- VPN / 네트워크 유틸

```bash
./scripts/install-all.sh net
```

**계약**

- 네트워크 단절 상태 → 즉시 실패
- 드라이버 설치 시 reboot barrier 가능

---

### ops (운영)

**목적**

- 시스템 운영 편의성 및 모니터링 기반 마련

```bash
./scripts/install-all.sh ops
```

---

### security (보안)

**목적**

- 기본 보안 정책 적용 및 하드닝

```bash
./scripts/install-all.sh security
```

**주의사항**

- 네트워크 정책 변경 후 재접속 필요 가능

---

### media (미디어 / ai-virtual-cam)

**목적**

- 스트리밍/녹화 환경 구성

```bash
./scripts/install-all.sh media
```

**계약**

- `ai-virtual-cam` 저장소를 기준으로 설치/업데이트 수행
- Linux 카메라 경로는 `v4l2loopback` 기반으로 구성됨
- OBS 실행/연동 동작은 수행하지 않음

---

### ml (AI / ML)

**목적**

- GPU 기반 AI/ML 실행 환경 구축

```bash
./scripts/install-all.sh ml
```

**계약**

- Secure Boot 비활성 권장
- 드라이버 설치 후 **reboot barrier 필수 발생 가능**

---

## 전역 옵션

| 옵션      | 설명                         |
| --------- | ---------------------------- |
| `--yes`   | 모든 동의 프롬프트 자동 승인 |
| `--debug` | `set -x` 기반 상세 로그      |
| `--reset` | resume 상태 초기화 후 재실행 |

예시:

```bash
./scripts/install-all.sh media --yes --debug
```

---

## Resume (이어하기) 메커니즘

- 상태 파일:

```
~/.local/state/ubuntu26-legion5-setup/resume.<scope>.ubuntu-26.04.done
```

- 완료된 step은 자동 skip
- **Step Key 변경 = Breaking Change**

---

## Reboot Barrier (재부팅 경계)

재부팅이 필요한 단계는 다음 규칙을 따릅니다:

1. `require_reboot_or_throw <reason>` 호출
2. `reboot.required` 상태파일 생성
3. 즉시 종료 (Fail-Fast)
4. 재부팅 후 dispatcher 재실행
5. boot_id 변경 감지 시 barrier 자동 해제

> 재부팅 전에는 어떤 도메인도 진행되지 않음.

---

## 실패 처리 규칙

- 전제조건 불충족 → 즉시 `err`
- 부분 성공 허용 ❌
- 롤백 없음
- 사용자는 원인 수정 후 재실행

---

## 설계 원칙 요약

- SSOT: `scripts/install-all.sh` + `AGENTS.md`
- 계약은 코드로 강제
- 문서와 코드 불일치 = 버그
- 사람보다 스크립트가 항상 옳다

---

## 라이선스 / 사용

- 개인 환경 자동화 목적
- 팀/조직 사용 시 fork 후 정책 확장 권장
