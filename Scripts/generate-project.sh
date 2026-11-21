#!/usr/bin/env bash
set -euo pipefail

command -v xcodegen >/dev/null
command -v xcodebuild >/dev/null
bash "$(dirname "$0")/prepare-readium.sh"
xcodegen generate --spec project.yml
