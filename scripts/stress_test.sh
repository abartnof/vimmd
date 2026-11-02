#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
MODULE_CACHE="/tmp/clang-module-cache"

# Ensure libraries and modules are built first
"${ROOT_DIR}/scripts/build.sh"

echo ""
echo "========================================="
echo " Compiling & Running Stress Test Suite"
echo "========================================="

echo "[TEST] Compiling StressTestSuite..."
swiftc -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -L "${BUILD_DIR}" \
    -lApp -lViews -lEngine -lCBridge \
    "${ROOT_DIR}/Tests/StressTests/StressTestSuite.swift" \
    -o "${BUILD_DIR}/StressTestSuite"

echo "[TEST] Executing StressTestSuite..."
"${BUILD_DIR}/StressTestSuite"
echo "[TEST] StressTestSuite execution finished."
