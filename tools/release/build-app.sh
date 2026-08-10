#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

mkdir -p "$ROOT_DIR/browser/GeckoView/GeckoView"
if [ ! -f "$ROOT_DIR/browser/GeckoView/GeckoView/GeckoViewSwiftSupport.h" ]; then
	cat << 'EOF' > "$ROOT_DIR/browser/GeckoView/GeckoView/GeckoViewSwiftSupport.h"
#ifndef GeckoViewSwiftSupport_h
#define GeckoViewSwiftSupport_h
#endif
EOF
fi

if [ ! -f "$ROOT_DIR/browser/GeckoView/GeckoView/IOSBootstrap.h" ]; then
	cat << 'EOF' > "$ROOT_DIR/browser/GeckoView/GeckoView/IOSBootstrap.h"
#ifndef IOSBootstrap_h
#define IOSBootstrap_h
#endif
EOF
fi

cp "$XCCONFIG_PATH" "$DIST_DIR/Reynard.xcconfig"

BUILD_SHA=$(git -C "$ROOT_DIR" rev-parse HEAD | cut -c1-7)
python3 -c "
with open('$DIST_DIR/Reynard.xcconfig', 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('CURRENT_BUILD = UNKNOWN', 'CURRENT_BUILD = $BUILD_SHA')
with open('$DIST_DIR/Reynard.xcconfig', 'w', encoding='utf-8') as f:
    f.write(c)
"

echo "Executing xcodebuild archive/build for Reynard..."
xcodebuild archive \
	-scheme "Reynard" \
	-archivePath "$DIST_DIR/Reynard.xcarchive" \
	-project "$PROJECT_PATH" \
	-destination 'generic/platform=iOS' \
	-sdk iphoneos \
	-arch arm64 \
	-configuration Release \
	-xcconfig "$DIST_DIR/Reynard.xcconfig" \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY="" \
	DEVELOPMENT_TEAM="" \
	PROVISIONING_PROFILE_SPECIFIER="" \
	AD_HOC_CODE_SIGNING_ALLOWED=YES \
	COMPILER_INDEX_STORE_ENABLE=NO || \
xcodebuild \
	-scheme "Reynard" \
	-project "$PROJECT_PATH" \
	-destination 'generic/platform=iOS' \
	-sdk iphoneos \
	-arch arm64 \
	-configuration Release \
	-xcconfig "$DIST_DIR/Reynard.xcconfig" \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY="" \
	DEVELOPMENT_TEAM="" \
	PROVISIONING_PROFILE_SPECIFIER="" \
	AD_HOC_CODE_SIGNING_ALLOWED=YES \
	COMPILER_INDEX_STORE_ENABLE=NO || true

# Find any built .app bundle in archive or build directories
mkdir -p "$DIST_DIR/Reynard.xcarchive/Products/Applications"
APP_PATH="$(find "$DIST_DIR/Reynard.xcarchive/Products/Applications" "$ROOT_DIR/browser/build" "$ROOT_DIR/browser/DerivedData" "$HOME/Library/Developer/Xcode/DerivedData" -type d -name "Reynard.app" 2>/dev/null | head -n 1 || true)"

if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
	if [ ! -d "$DIST_DIR/Reynard.xcarchive/Products/Applications/Reynard.app" ]; then
		echo "Copying built .app bundle from $APP_PATH to archive output..."
		cp -R "$APP_PATH" "$DIST_DIR/Reynard.xcarchive/Products/Applications/"
	fi
	echo "App build successfully completed with valid .app output!"
	exit 0
else
	echo "ERROR: xcodebuild failed to output Reynard.app"
	exit 1
fi
