#!/usr/bin/env bash
set -euo pipefail

command -v xcodegen >/dev/null
command -v xcodebuild >/dev/null
xcodegen generate --spec project.yml
