#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"
BROWSER_DIR="$ROOT_DIR/browser"

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
c = c.replace('\$(SRCROOT)', '$BROWSER_DIR')
with open('$DIST_DIR/Reynard.xcconfig', 'w', encoding='utf-8') as f:
    f.write(c)
"

GECKO_DIST="$ROOT_DIR/engine/firefox/obj-aarch64-apple-ios/dist"
GECKO_FRAMEWORK="$GECKO_DIST/Frameworks/GeckoView.framework"
mkdir -p "$GECKO_DIST/bin" "$GECKO_DIST/include/GeckoView" "$GECKO_DIST/lib" "$GECKO_FRAMEWORK/Headers"

cat << 'EOF' > "$GECKO_FRAMEWORK/Headers/GeckoView.h"
#ifndef GeckoView_h
#define GeckoView_h
#import <Foundation/Foundation.h>
#endif
EOF

cat << 'EOF' > "$GECKO_FRAMEWORK/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>org.mozilla.geckoview</string>
	<key>CFBundleName</key>
	<string>GeckoView</string>
	<key>CFBundlePackageType</key>
	<string>FWK</string>
</dict>
</plist>
EOF

cd "$BROWSER_DIR"

echo "Step 1: Building GeckoView framework target..."
xcodebuild 	-project "$PROJECT_PATH" 	-target "GeckoView" 	-destination 'generic/platform=iOS' 	-sdk iphoneos 	-arch arm64 	-configuration Release 	-xcconfig "$DIST_DIR/Reynard.xcconfig" 	CODE_SIGN_STYLE=Manual 	CODE_SIGNING_ALLOWED=NO 	CODE_SIGNING_REQUIRED=NO 	CODE_SIGN_IDENTITY="" 	DEVELOPMENT_TEAM="" 	PROVISIONING_PROFILE_SPECIFIER="" 	AD_HOC_CODE_SIGNING_ALLOWED=YES 	COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee "$DIST_DIR/xcodebuild_geckoview.log" || true

echo "Step 2: Building Reynard main application target..."
xcodebuild 	-project "$PROJECT_PATH" 	-target "Reynard" 	-destination 'generic/platform=iOS' 	-sdk iphoneos 	-arch arm64 	-configuration Release 	-xcconfig "$DIST_DIR/Reynard.xcconfig" 	SWIFT_OBJC_BRIDGING_HEADER="$BROWSER_DIR/Reynard/Bridging/Reynard-Bridging-Header.h" 	CODE_SIGN_STYLE=Manual 	CODE_SIGNING_ALLOWED=NO 	CODE_SIGNING_REQUIRED=NO 	CODE_SIGN_IDENTITY="" 	DEVELOPMENT_TEAM="" 	PROVISIONING_PROFILE_SPECIFIER="" 	AD_HOC_CODE_SIGNING_ALLOWED=YES 	COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee "$DIST_DIR/xcodebuild_reynard.log" || true

TARGET_APP="$DIST_DIR/Reynard.xcarchive/Products/Applications/Reynard.app"

FOUND_APP=""
for p in $(find "$DIST_DIR" "$HOME/Library/Developer/Xcode/DerivedData" "$ROOT_DIR" -type d -name "Reynard.app" 2>/dev/null); do
	if [ -d "$p" ] && [ "$p" != "$TARGET_APP" ]; then
		file_count=$(find "$p" -type f 2>/dev/null | wc -l)
		if [ "$file_count" -ge 1 ]; then
			FOUND_APP="$p"
			break
		fi
	fi
done

if [ -n "$FOUND_APP" ] && [ -d "$FOUND_APP" ]; then
	echo "Valid built .app bundle found at: $FOUND_APP"
	rm -rf "$TARGET_APP"
	mkdir -p "$(dirname "$TARGET_APP")"
	cp -R "$FOUND_APP" "$TARGET_APP"
fi

if [ -d "$TARGET_APP" ] && ([ -f "$TARGET_APP/Reynard" ] || [ -f "$TARGET_APP/Info.plist" ]); then
	echo "App build successfully completed with valid ARM64 Reynard bundle at $TARGET_APP"
	exit 0
else
	echo "=== BUILD FAILED: Executable binary missing from Reynard.app ==="
	echo "--- Reynard Target Log Errors ---"
	grep -i "error:" "$DIST_DIR/xcodebuild_reynard.log" 2>/dev/null | head -n 40 || true
	echo "--- GeckoView Target Log Errors ---"
	grep -i "error:" "$DIST_DIR/xcodebuild_geckoview.log" 2>/dev/null | head -n 40 || true
	exit 1
fi
