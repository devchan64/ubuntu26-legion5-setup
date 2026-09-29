# AGENTS.md

> SSOT for agent instructions in this repository.

Use the root `AGENTS.md` as the shared instruction source for VS Code and Codex-style agents.

## 1) Goal

Reproduce Ubuntu 24.04 LTS (noble, GNOME on Xorg) and 26.04 LTS (resolute, GNOME on Wayland) development environments with bash scripts.

Core principles:
- fail-fast, no fallback
- explicit contract checks
- resumable execution
- enforced reboot barrier

## 2) Execution Model

- Entry point: `scripts/install-all.sh`
- Commands: `dev | codex | sys | net | ops | security | media | ml | all`
- Execution order: `dev → sys → net → ops → security → media → ml`
- Global options: `--yes`, `--debug`, `--reset`

Important environment variables:
- `LEGION_SETUP_ROOT`
- `LEGION_ASSUME_YES`
- `LEGION_DEBUG`
- `RESUME_SCOPE_KEY`

## 3) Shared Contracts

- Bash scripts should use `set -Eeuo pipefail`
- `lib/common.sh` is the SSOT for shared utilities and contracts
- Do not introduce alias APIs or fallback paths for shared contracts
- Run entrypoint scripts as the normal user; do not instruct users to start them with sudo
- Privileged work must use explicit sudo only for commands that require elevated privileges, and let sudo prompt for authentication at that point

Resume / reboot barrier:
- Resume state: `~/.local/state/ubuntu26-legion5-setup/resume.<scope>.done`
- Reboot barrier state: `~/.local/state/ubuntu26-legion5-setup/reboot.required`
- Steps that require reboot must stop via `require_reboot_or_throw`
- If a reboot barrier exists, later steps must not continue
- Changing a `stepKey` is a breaking change

## 4) Domain Notes

- `sys`: 버전별 Xorg/Wayland 세션 및 재부팅 경계를 준수한다. xrandr 자동 배치는 폐기하며 화면 배치는 GNOME 설정에서 관리한다.
- `codex`: Codex CLI와 Codex Desktop을 설치한다
- `media`: standardize on ai-virtual-cam (`scripts/media/camera`, Linux v4l2loopback path, video+audio integrated, OBS-independent)
- `ml`: includes CUDA/TensorRT and TensorFlow utilities
- `security`: covers install, scan, schedule, and summary

See `README.md` and the target scripts for detailed procedures.

## 5) Writing Rules

- Use Conventional Commits
- Keep the commit type/prefix in Conventional Commits format
- Write commit titles and bodies in Korean
- Write code comments in Korean unless there is a strong reason not to
- Write docstrings in Korean unless there is a strong reason not to
- Write user-visible system output (`log`, `warn`, `err`, `echo`, etc.) in Korean

Examples:
- `feat: Continue 인라인 자동완성 설치 추가`
- `docs: 릴리즈 노트 목록 추가`

## 6) AGENTS.md Maintenance

- Keep only rules that an agent must follow immediately
- Avoid long background explanations, duplicated rules, and verbose examples
- If another document is the SSOT, reference its path instead of copying details
- Prefer merging new rules into existing ones over adding near-duplicates
- Keep detailed operational history out of this file

## 7) Release Notes

- Write a release note under `docs/release-notes/` for user-visible changes, workflow changes, policy changes, and agent-rule changes
- Use the filename format `YYYY-MM-DD-<slug>.md`
- Always update `docs/release-notes/README.md` when adding a new note
- Default sections:
  - `변경 요약`
  - `주요 변경사항`
  - `적용 설정` or `영향 범위`
  - `기대 효과`
  - `검증`
- Write release note titles, body text, and index labels in Korean
- Changes to `AGENTS.md` should also get a release note when they affect users or collaboration rules

Official change history is managed in `docs/release-notes/README.md` and `docs/release-notes/*.md`, not in this file.
