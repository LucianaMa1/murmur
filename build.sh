#!/bin/bash
# build.sh — compile Murmur into a proper .app bundle.
# Run from the repo root: ./build.sh

set -e

APP_NAME="Murmur"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"
PRODUCT_DIR="dist"

echo "🔨 Building Murmur (release)…"
swift build -c release --arch arm64

echo "📦 Creating app bundle…"
rm -rf "$PRODUCT_DIR/$APP_BUNDLE"
mkdir -p "$PRODUCT_DIR/$APP_BUNDLE/Contents/MacOS"
mkdir -p "$PRODUCT_DIR/$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$PRODUCT_DIR/$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Murmur/Info.plist" "$PRODUCT_DIR/$APP_BUNDLE/Contents/Info.plist"

# Copy any required resource bundles that SPM produced (WhisperKit ships some).
find "$BUILD_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$PRODUCT_DIR/$APP_BUNDLE/Contents/Resources/" \; 2>/dev/null || true

# Ad-hoc sign so it can be launched (real distribution needs a Developer ID).
echo "✍️  Ad-hoc signing…"
codesign --force --deep --sign - "$PRODUCT_DIR/$APP_BUNDLE"

echo ""
echo "✅ Built: $PRODUCT_DIR/$APP_BUNDLE"
echo ""
echo "Next steps:"
echo "  1. Move it to /Applications:    mv $PRODUCT_DIR/$APP_BUNDLE /Applications/"
echo "  2. Launch it:                   open /Applications/$APP_BUNDLE"
echo "  3. Grant Input Monitoring + Microphone + Accessibility when prompted"
echo "  4. Restart the app after granting permissions"
