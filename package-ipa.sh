#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="build/DerivedData/Build/Products/Release-iphoneos/Polytes.app"
if [ ! -d "$APP" ]; then
  echo "ERROR: no existe $APP — ejecuta primero ./build.sh"
  exit 1
fi

rm -rf build/Payload build/Polytes.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
cd build
zip -qry Polytes.ipa Payload
cd ..

echo "==> IPA creada:"
ls -la build/Polytes.ipa
