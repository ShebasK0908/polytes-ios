#!/bin/bash
set -e
cd "$(dirname "$0")"

mkdir -p build

echo "==> Compilando Polytes.app (sin firmar)..."
xcodebuild \
  -project Polytes.xcodeproj \
  -scheme Polytes \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

echo "==> Compilación OK"
ls -la build/DerivedData/Build/Products/Release-iphoneos/
