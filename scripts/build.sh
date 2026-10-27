#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
MODULE_CACHE="/tmp/clang-module-cache"

mkdir -p "${BUILD_DIR}"
mkdir -p "${MODULE_CACHE}"

echo "[BUILD] Compiling CBridge..."
clang -Wall -Wextra -Werror -I "${ROOT_DIR}/Sources/CBridge" \
    -c "${ROOT_DIR}/Sources/CBridge/libvim_bridge.c" \
    -o "${BUILD_DIR}/libvim_bridge.o"
ar rcs "${BUILD_DIR}/libCBridge.a" "${BUILD_DIR}/libvim_bridge.o"

echo "[BUILD] Compiling Engine..."
swiftc -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -emit-module -emit-module-path "${BUILD_DIR}/Engine.swiftmodule" \
    -emit-library -static -o "${BUILD_DIR}/libEngine.a" \
    -module-name Engine \
    ${ROOT_DIR}/Sources/Engine/*.swift

echo "[BUILD] Compiling Views..."
swiftc -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -emit-module -emit-module-path "${BUILD_DIR}/Views.swiftmodule" \
    -emit-library -static -o "${BUILD_DIR}/libViews.a" \
    -module-name Views \
    ${ROOT_DIR}/Sources/Views/*.swift

echo "[BUILD] Compiling App..."
swiftc -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -L "${BUILD_DIR}" \
    -lViews -lEngine -lCBridge \
    ${ROOT_DIR}/Sources/App/*.swift \
    -o "${BUILD_DIR}/VimMD"

echo "[BUILD] Build complete: ${BUILD_DIR}/VimMD"
