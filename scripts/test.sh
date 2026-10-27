#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
MODULE_CACHE="/tmp/clang-module-cache"

# Ensure libraries and modules are built first
"${ROOT_DIR}/scripts/build.sh"

echo ""
echo "========================================="
echo " Compiling & Running Test Suites"
echo "========================================="

# 1. CBridge Tests
echo "[TEST] Building CBridge unit tests..."
clang -Wall -Wextra -Werror -I "${ROOT_DIR}/Sources/CBridge" \
    "${ROOT_DIR}/Tests/CBridgeTests/cbridge_test.c" \
    "${BUILD_DIR}/libCBridge.a" \
    -o "${BUILD_DIR}/cbridge_test"

echo "[TEST] Running CBridge unit tests..."
"${BUILD_DIR}/cbridge_test"
echo "[TEST] CBridge unit tests passed."
echo ""

# 2. Engine Tests
echo "[TEST] Building Engine unit tests..."
swiftc -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -L "${BUILD_DIR}" \
    -lEngine -lCBridge \
    ${ROOT_DIR}/Tests/EngineTests/*.swift \
    -o "${BUILD_DIR}/engine_test"

echo "[TEST] Running Engine unit tests..."
"${BUILD_DIR}/engine_test"
echo "[TEST] Engine unit tests passed."
echo ""

echo "========================================="
echo " All test suites PASSED successfully! "
echo "========================================="
