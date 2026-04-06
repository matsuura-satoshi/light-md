#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

VERSION="${1:-1.0.0}"
APP_NAME="LightMD"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "==> Building ${APP_NAME} v${VERSION} (release)..."
xcodebuild -project LightMD.xcodeproj -scheme LightMD -configuration Release -destination 'platform=macOS' -derivedDataPath "${BUILD_DIR}/DerivedData" build

echo "==> Copying app bundle..."
BUILT_APP="${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"
rm -rf "${APP_BUNDLE}"
cp -R "${BUILT_APP}" "${APP_BUNDLE}"

echo "==> Creating zip..."
cd "${BUILD_DIR}"
rm -f "${APP_NAME}-v${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "${APP_NAME}-v${VERSION}.zip"

echo "==> Done: ${BUILD_DIR}/${APP_NAME}-v${VERSION}.zip"
