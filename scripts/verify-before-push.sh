#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

cargo_bin="${CARGO_BIN:-cargo}"
python_bin="${PYTHON_BIN:-python3}"
gitleaks_bin="${GITLEAKS_BIN:-gitleaks}"
godot_bin="${GODOT_BIN:-godot}"

for command in "$cargo_bin" "$python_bin" "$gitleaks_bin" "$godot_bin"; do
  if ! command -v "$command" >/dev/null 2>&1 && [[ ! -x "$command" ]]; then
    echo "Required verification tool is unavailable: $command" >&2
    exit 2
  fi
done

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "The tracked working tree must be clean before the pre-push gate." >&2
  git status --short >&2
  exit 2
fi

"$cargo_bin" fmt --all -- --check
"$cargo_bin" test --workspace --locked

"$python_bin" scripts/verify-m1-snes-contract.py
"$python_bin" scripts/verify-m2-snes-reference.py
"$python_bin" scripts/generate-m2-2-snes-front.py --check --skip-renders
"$python_bin" scripts/verify-m2-2-snes-front.py --skip-regeneration

"$gitleaks_bin" git --no-banner --redact .
"$gitleaks_bin" dir --no-banner --redact .

./scripts/build-phase4-launch.sh debug
export GODOT_SILENCE_ROOT_WARNING=1
"$godot_bin" --headless --path frontend/godot-ui --editor --quit-after 20
for smoke in smoke_test.gd ui_smoke_test.gd m2_2_snes_front_smoke_test.gd; do
  "$godot_bin" --headless --path frontend/godot-ui --script "res://scripts/$smoke"
done

git diff --check
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Verification changed tracked files." >&2
  git status --short >&2
  exit 1
fi

printf '%s\n' 'RETROLIFE_PRE_PUSH_OK rust=true m1=true m2_1=true m2_2_cad=true gitleaks=true godot=true'
