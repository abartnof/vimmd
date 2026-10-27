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
echo "[TEST] Building & running Engine unit tests..."
for test_file in "${ROOT_DIR}"/Tests/EngineTests/*Tests.swift; do
    test_name="$(basename "${test_file}" .swift)"
    bin_name="${BUILD_DIR}/${test_name}"
    echo "[TEST] Compiling ${test_name}..."
    swiftc -module-cache-path "${MODULE_CACHE}" \
        -I "${ROOT_DIR}/Sources/CBridge" \
        -I "${BUILD_DIR}" \
        -L "${BUILD_DIR}" \
        -lEngine -lCBridge \
        "${test_file}" \
        -o "${bin_name}"
    
    echo "[TEST] Executing ${test_name}..."
    "${bin_name}"
    echo "[TEST] ${test_name} passed."
    echo ""
done

# 3. Views Tests
echo "[TEST] Building & running Views unit tests..."
for test_file in "${ROOT_DIR}"/Tests/ViewsTests/*Tests.swift; do
    test_name="$(basename "${test_file}" .swift)"
    bin_name="${BUILD_DIR}/${test_name}"
    echo "[TEST] Compiling ${test_name}..."
    swiftc -module-cache-path "${MODULE_CACHE}" \
        -I "${ROOT_DIR}/Sources/CBridge" \
        -I "${BUILD_DIR}" \
        -L "${BUILD_DIR}" \
        -lViews -lEngine -lCBridge \
        "${test_file}" \
        -o "${bin_name}"
    
    echo "[TEST] Executing ${test_name}..."
    "${bin_name}"
    echo "[TEST] ${test_name} passed."
    echo ""
done

# 4. App Tests
echo "[TEST] Building & running App unit tests..."
for test_file in "${ROOT_DIR}"/Tests/AppTests/*Tests.swift; do
    test_name="$(basename "${test_file}" .swift)"
    bin_name="${BUILD_DIR}/${test_name}"
    echo "[TEST] Compiling ${test_name}..."
    swiftc -module-cache-path "${MODULE_CACHE}" \
        -I "${ROOT_DIR}/Sources/CBridge" \
        -I "${BUILD_DIR}" \
        -L "${BUILD_DIR}" \
        -lApp -lViews -lEngine -lCBridge \
        "${test_file}" \
        -o "${bin_name}"
    
    echo "[TEST] Executing ${test_name}..."
    "${bin_name}"
    echo "[TEST] ${test_name} passed."
    echo ""
done

# 5. Integration / End-to-End User Trial
echo "[TEST] Building & running End-to-End Demo Trial..."
echo "[TEST] Compiling demo_trial..."
swiftc -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -L "${BUILD_DIR}" \
    -lApp -lViews -lEngine -lCBridge \
    "${ROOT_DIR}/scripts/demo_trial.swift" \
    -o "${BUILD_DIR}/demo_trial"

echo "[TEST] Executing demo_trial..."
"${BUILD_DIR}/demo_trial"
echo "[TEST] demo_trial passed."
echo ""

# 6. Critical User Journey (CUJ) Trial
echo "[TEST] Building & running Critical User Journey (CUJ) Trial..."
echo "[TEST] Compiling cuj_trial..."
swiftc -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -L "${BUILD_DIR}" \
    -lApp -lViews -lEngine -lCBridge \
    "${ROOT_DIR}/scripts/cuj_trial.swift" \
    -o "${BUILD_DIR}/cuj_trial"

echo "[TEST] Executing cuj_trial..."
"${BUILD_DIR}/cuj_trial"
echo "[TEST] cuj_trial passed."
echo ""

echo "========================================="
echo " All test suites PASSED successfully! "
echo "========================================="
