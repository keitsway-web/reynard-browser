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

# Ensure archive directory exists with Reynard.app
mkdir -p "$DIST_DIR/Reynard.xcarchive/Products/Applications"
BUILT_APP="$(find "$ROOT_DIR/browser/build" "$ROOT_DIR/browser/DerivedData" "$HOME/Library/Developer/Xcode/DerivedData" -type d -name "Reynard.app" 2>/dev/null | head -n 1 || true)"

if [ -n "$BUILT_APP" ] && [ -d "$BUILT_APP" ] && [ ! -d "$DIST_DIR/Reynard.xcarchive/Products/Applications/Reynard.app" ]; then
	echo "Copying built .app bundle to archive destination: $BUILT_APP"
	cp -R "$BUILT_APP" "$DIST_DIR/Reynard.xcarchive/Products/Applications/"
fi

echo "App build step finished."
exit 0
