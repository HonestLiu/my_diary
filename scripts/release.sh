#!/usr/bin/env bash
# 一键发版（bash 封装，内部调用跨平台的 node 实现）。
# Windows 用户可直接用：node scripts/release.mjs [patch|minor|major|x.y.z|--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."
exec node scripts/release.mjs "$@"
