#!/usr/bin/env bash
# 打包：./build.sh            → 默认（保守）版 zip
#       ./build.sh thermal    → 温控表全放开版 zip
#       ./build.sh all        → 两个都打
set -euo pipefail
cd "$(dirname "$0")"
exec python3 tools/pack.py "${1:-normal}"
