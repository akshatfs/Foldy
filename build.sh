#!/bin/bash
set -e

# Configuration
SCHEME="Prvw"
ARCHIVE_PATH="./build/Prvw.xcarchive"
EXPORT_PATH="./build/PrvwDist"
DMG_NAME="Prvw.dmg"
DMG_TEMP="./build/DMGTemp"
TEAM_ID="G44GLW27US"

# 1. Clean and Archive for universal binary (arm64 + x86_64)
echo -e "Step 1: Building universal binary (arm64 + x86_64)..."
xcodebuild -scheme "$SCHEME" -configuration Release -destination 'generic/platform=macOS' -archivePath "$ARCHIVE_PATH" \
  ARCHS="arm64 x86_64" \
  CODE_SIGN_STYLE="Automatic" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  clean archive

# 2. Extract App from Archive
echo -e "Step 2: Extracting app..."
mkdir -p "$EXPORT_PATH"
rm -rf "$EXPORT_PATH/Prvw.app"
cp -R "$ARCHIVE_PATH/Products/Applications/Prvw.app" "$EXPORT_PATH/Prvw.app"

# 3. Verify universal architecture
echo -e "Step 3: Verifying universal binary architecture..."
APP_EXECUTABLE="$EXPORT_PATH/Prvw.app/Contents/MacOS/Prvw"
if [ -f "$APP_EXECUTABLE" ]; then
  ARCHS_FOUND=$(lipo -archs "$APP_EXECUTABLE" 2>/dev/null || echo "unknown")
  echo -e "App executable architectures: $ARCHS_FOUND"

  # Verify both architectures are present
  if echo "$ARCHS_FOUND" | grep -q "arm64" && echo "$ARCHS_FOUND" | grep -q "x86_64"; then
    echo -e "Universal binary verified (supports Apple Silicon and Intel)"
  else
    echo -e "Note: App contains: $ARCHS_FOUND"
  fi
else
  echo -e "Warning: Could not find app executable at $APP_EXECUTABLE"
fi

# 4. Create DMG with proper layout
echo -e "Step 4: Creating DMG with drag-to-Applications layout..."
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$EXPORT_PATH/Prvw.app" "$DMG_TEMP/Prvw.app"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_TEMP/Applications"

# Clean up any old DMG
rm -f "$DMG_NAME"

# Create DMG with UDZO compression
hdiutil create -volname "Prvw" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_NAME" -quiet

# Clean up temp directory
rm -rf "$DMG_TEMP"

echo -e "Done! DMG created at $DMG_NAME"