#!/bin/bash
#
# Xcode Cloud post-clone hook.
#
# Trump.xcframework and MoltenVK.xcframework are gitignored (~440 MB raw)
# and produced locally by Godot's iOS export. Xcode Cloud clones a fresh
# repo for every build, so we materialize them here from a GitHub Release.
#
# When Godot is upgraded, re-export, re-zip the two xcframeworks, cut a new
# release with a fresh tag, and bump RELEASE_TAG below.

set -euo pipefail

if [ -z "${CI:-}" ]; then
    echo "[ci_post_clone] \$CI not set — skipping (this script only runs in Xcode Cloud)"
    exit 0
fi

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
RELEASE_TAG="ios-deps-godot-4.6"
RELEASE_BASE="https://github.com/randyramsaywack/trump-mobile-card-game/releases/download/${RELEASE_TAG}"

cd "$REPO_ROOT"

for asset in Trump.xcframework MoltenVK.xcframework; do
    if [ -d "${asset}" ]; then
        echo "[ci_post_clone] ${asset} already present — skipping"
        continue
    fi
    echo "[ci_post_clone] Fetching ${asset}.zip from ${RELEASE_TAG}"
    curl -fL --retry 3 --retry-delay 2 -o "${asset}.zip" "${RELEASE_BASE}/${asset}.zip"
    echo "[ci_post_clone] Extracting ${asset}.zip"
    unzip -q "${asset}.zip"
    rm "${asset}.zip"
done

echo "[ci_post_clone] iOS deps ready in ${REPO_ROOT}"
