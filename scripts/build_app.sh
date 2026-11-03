#!/bin/bash
# Build Phụ đề Việt Live.app + DMG (chạy trên macOS)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Phu de Viet Live"
NAME="Phụ đề Việt Live"
VERSION="${VERSION:-1.0.0}"

swift build -c release --arch arm64
BIN=".build/arm64-apple-macosx/release/PhuDeLive"

rm -rf dist && mkdir -p "dist/$APP.app/Contents/MacOS" "dist/$APP.app/Contents/Resources"
cp "$BIN" "dist/$APP.app/Contents/MacOS/PhuDeLive"
iconutil -c icns Resources/AppIcon.iconset -o "dist/$APP.app/Contents/Resources/AppIcon.icns"

cat > "dist/$APP.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.thayphong.phudelive</string>
  <key>CFBundleExecutable</key><string>PhuDeLive</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>vi</string>
  <key>NSScreenCaptureUsageDescription</key><string>Cần quyền ghi màn hình để đọc phụ đề tiếng Anh trên video.</string>
</dict></plist>
EOF

codesign --force --deep --sign - "dist/$APP.app"

mkdir -p dist/dmg
cp -R "dist/$APP.app" dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "$NAME" -srcfolder dist/dmg -ov -format UDZO "dist/PhuDeVietLive.dmg"
echo "OK: dist/PhuDeVietLive.dmg"
