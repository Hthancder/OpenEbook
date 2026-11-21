#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT/build/Readium"
REVISION=9a8c094b72245fd27043c9d298005e5c78b32a01
PATCH="$ROOT/Scripts/Patches/readium-3.11.1-offline.patch"

test -s "$PATCH"
mkdir -p "$ROOT/build"
if [ ! -e "$SOURCE" ]; then
  git clone --config core.autocrlf=false --depth 1 --branch 3.11.1 https://github.com/readium/swift-toolkit.git "$SOURCE"
fi
test -d "$SOURCE/.git"
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$REVISION"
git -C "$SOURCE" diff --quiet --cached
UNTRACKED=$(git -C "$SOURCE" ls-files --others)
test -z "$UNTRACKED"
if git -C "$SOURCE" apply --reverse --check "$PATCH" 2>/dev/null; then
  echo 'Pinned Readium offline patch is already applied.'
else
  git -C "$SOURCE" diff --exit-code
  git -C "$SOURCE" apply --check "$PATCH"
  git -C "$SOURCE" apply "$PATCH"
fi
git -C "$SOURCE" apply --reverse --check "$PATCH"
git -C "$SOURCE" diff --exit-code HEAD -- . \
  ':(exclude)Sources/Navigator/EPUB/EPUBNavigatorViewController.swift' \
  ':(exclude)Sources/Navigator/EPUB/EPUBNavigatorViewModel.swift' \
  ':(exclude)Sources/Navigator/EPUB/EPUBSpreadView.swift' \
  ':(exclude)Sources/Navigator/EPUB/WebViewServer.swift' \
  ':(exclude)Sources/Navigator/EPUB/EPUBFixedSpreadView.swift' \
  ':(exclude)Sources/Navigator/EPUB/Scripts/src/fixed-page.js' \
  ':(exclude)Sources/Navigator/EPUB/Scripts/src/decorator.js' \
  ':(exclude)Sources/Navigator/EPUB/Scripts/src/index-fixed-wrapper-one.js' \
  ':(exclude)Sources/Navigator/EPUB/Scripts/src/index-fixed-wrapper-two.js' \
  ':(exclude)Sources/Navigator/EPUB/Assets/Static/scripts/readium-fixed-wrapper-one.js' \
  ':(exclude)Sources/Navigator/EPUB/Assets/Static/scripts/readium-fixed-wrapper-two.js' \
  ':(exclude)Sources/Navigator/EPUB/Assets/Static/scripts/readium-fixed.js' \
  ':(exclude)Sources/Navigator/EPUB/Assets/Static/scripts/readium-reflowable.js'
(cd "$SOURCE" && shasum -a 256 -c "$ROOT/Scripts/Patches/readium-3.11.1-offline.sha256")
test -s "$SOURCE/LICENSE"
printf 'Readium %s with reviewed offline patch\n' "$REVISION"
