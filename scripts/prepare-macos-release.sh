#!/usr/bin/env bash
# Local trusted-machine path. The hosted action uses isolated build/sign jobs.
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:?Pass a release version such as 0.1.0-beta.3}
PYTHONPATH=scripts python3 -c 'from updates.common import version_info; import sys; version_info(sys.argv[1])' "$version"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]]
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit reviewed source first.' >&2; exit 1; }
sdk=$(python3 scripts/prepare-sparkle.py)
account=${SPARKLE_KEY_ACCOUNT:-io.github.lincolnaleixo.retrolife.sparkle}
"$sdk/bin/generate_keys" --account "$account"
public_key=$("$sdk/bin/generate_keys" --account "$account" -p)
scripts/build-macos-release.sh "$version" "$public_key"
app="$PWD/dist/unsigned/RetroLife.app"
scripts/sign-macos.sh "$app"
python3 scripts/prepare-update-metadata.py "$app" "$PWD/dist/unsigned/RetroLife-macos-arm64.zip" --account "$account"
(cd dist/unsigned && shasum -a 256 retrolife-update.json >> SHA256SUMS)
echo 'Prepared locally; verify the packaged updater and audit artifacts before publication.'
