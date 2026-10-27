#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
MODULE_CACHE="/tmp/clang-module-cache"

mkdir -p "${BUILD_DIR}"
mkdir -p "${MODULE_CACHE}"

OPTIMIZE_SIZE="${OPTIMIZE_SIZE:-1}"
if [ "${OPTIMIZE_SIZE}" = "1" ]; then
    echo "[BUILD] Space optimization enabled (DESIGN.md §5: -Oz, -flto, -Osize, -dead_strip, strip)"
    C_SIZE_FLAGS="-Oz -flto"
    SWIFT_SIZE_FLAGS="-Osize"
    LINK_SIZE_FLAGS="-Xlinker -dead_strip"
else
    C_SIZE_FLAGS=""
    SWIFT_SIZE_FLAGS=""
    LINK_SIZE_FLAGS=""
fi

echo "[BUILD] Compiling CBridge..."
clang -Wall -Wextra -Werror ${C_SIZE_FLAGS} -I "${ROOT_DIR}/Sources/CBridge" \
    -c "${ROOT_DIR}/Sources/CBridge/libvim_bridge.c" \
    -o "${BUILD_DIR}/libvim_bridge.o"
ar rcs "${BUILD_DIR}/libCBridge.a" "${BUILD_DIR}/libvim_bridge.o"

echo "[BUILD] Compiling Engine..."
swiftc ${SWIFT_SIZE_FLAGS} -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -emit-module -emit-module-path "${BUILD_DIR}/Engine.swiftmodule" \
    -emit-library -static -o "${BUILD_DIR}/libEngine.a" \
    -module-name Engine \
    ${ROOT_DIR}/Sources/Engine/*.swift

echo "[BUILD] Compiling Views..."
swiftc ${SWIFT_SIZE_FLAGS} -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -emit-module -emit-module-path "${BUILD_DIR}/Views.swiftmodule" \
    -emit-library -static -o "${BUILD_DIR}/libViews.a" \
    -module-name Views \
    ${ROOT_DIR}/Sources/Views/*.swift

echo "[BUILD] Compiling App library..."
swiftc ${SWIFT_SIZE_FLAGS} -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -emit-module -emit-module-path "${BUILD_DIR}/App.swiftmodule" \
    -emit-library -static -o "${BUILD_DIR}/libApp.a" \
    -module-name App \
    -parse-as-library \
    "${ROOT_DIR}/Sources/App/AppDelegate.swift" \
    "${ROOT_DIR}/Sources/App/VimMDDocument.swift"

echo "[BUILD] Compiling App executable..."
swiftc ${SWIFT_SIZE_FLAGS} -module-cache-path "${MODULE_CACHE}" \
    -I "${ROOT_DIR}/Sources/CBridge" \
    -I "${BUILD_DIR}" \
    -L "${BUILD_DIR}" \
    -lApp -lViews -lEngine -lCBridge \
    ${LINK_SIZE_FLAGS} \
    "${ROOT_DIR}/Sources/App/main.swift" \
    -o "${BUILD_DIR}/VimMD"

echo "[BUILD] Packaging VimMD.app bundle..."
APP_BUNDLE="${BUILD_DIR}/VimMD.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BUILD_DIR}/VimMD" "${MACOS_DIR}/VimMD"

if [ "${OPTIMIZE_SIZE}" = "1" ]; then
    echo "[BUILD] Stripping debug and local symbols from ${MACOS_DIR}/VimMD..."
    strip -u -r "${MACOS_DIR}/VimMD"
fi

cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VimMD</string>
    <key>CFBundleIdentifier</key>
    <string>com.vimmd.VimMD</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>VimMD</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
            <key>NSDocumentClass</key>
            <string>VimMDDocument</string>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "[BUILD] Build complete: ${APP_BUNDLE}"
