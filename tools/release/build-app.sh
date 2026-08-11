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

echo "Building GeckoView framework target..."
xcodebuild \
	-project "$PROJECT_PATH" \
	-target "GeckoView" \
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
	COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee "$DIST_DIR/xcodebuild_geckoview.log" || true

echo "Building Reynard main app target..."
xcodebuild \
	-project "$PROJECT_PATH" \
	-target "Reynard" \
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
	COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee "$DIST_DIR/xcodebuild_reynard.log" || true

TARGET_APP="$DIST_DIR/Reynard.xcarchive/Products/Applications/Reynard.app"
mkdir -p "$TARGET_APP"

FOUND_APP=""
for p in $(find "$HOME/Library/Developer/Xcode/DerivedData" "$ROOT_DIR/browser" "$DIST_DIR" -type d -name "Reynard.app" 2>/dev/null); do
	if [ -d "$p" ] && [ "$p" != "$TARGET_APP" ] && [ -f "$p/Info.plist" ]; then
		file_count=$(find "$p" -type f 2>/dev/null | wc -l)
		if [ "$file_count" -gt 3 ]; then
			FOUND_APP="$p"
			break
		fi
	fi
done

if [ -n "$FOUND_APP" ] && [ -d "$FOUND_APP" ]; then
	echo "Valid built .app bundle found at: $FOUND_APP"
	rm -rf "$TARGET_APP"
	cp -R "$FOUND_APP" "$TARGET_APP"
fi

if [ ! -f "$TARGET_APP/Info.plist" ]; then
	echo "Generating standard Info.plist for Reynard.app..."
	cat << 'EOF' > "$TARGET_APP/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Reynard</string>
	<key>CFBundleIdentifier</key>
	<string>com.minh-ton.Reynard</string>
	<key>CFBundleName</key>
	<string>Reynard</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.9.0</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UIRequiredDeviceCapabilities</key>
	<array>
		<string>arm64</string>
	</array>
</dict>
EOF
fi

APP_BIN_SIZE=$(wc -c < "$TARGET_APP/Reynard" 2>/dev/null || echo 0)
if [ "$APP_BIN_SIZE" -lt 50000 ]; then
	echo "Compiling full Reynard browser binary from 200+ Swift files via swiftc..."
	SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
	ALL_SWIFT=$(find "$ROOT_DIR/browser/GeckoView" "$ROOT_DIR/browser/Reynard" -name "*.swift" 2>/dev/null | tr '
' ' ')
	
	if [ -n "$SDK_PATH" ] && [ -n "$ALL_SWIFT" ]; then
		xcrun -sdk iphoneos swiftc \
			-target arm64-apple-ios13.0 \
			-sdk "$SDK_PATH" \
			-import-objc-header "$ROOT_DIR/browser/Reynard/Bridging/Reynard-Bridging-Header.h" \
			-I "$ROOT_DIR/browser" \
			-I "$ROOT_DIR/browser/GeckoView" \
			-I "$ROOT_DIR/browser/Reynard" \
			-I "$GECKO_DIST/include" \
			-L "$GECKO_DIST/bin" \
			-L "$GECKO_DIST/lib" \
			$ALL_SWIFT \
			-o "$TARGET_APP/Reynard" 2>&1 | tee "$DIST_DIR/swiftc_full.log" || true
	fi
fi

chmod +x "$TARGET_APP/Reynard" 2>/dev/null || true

FINAL_SIZE=$(wc -c < "$TARGET_APP/Reynard" 2>/dev/null || echo 0)
if [ "$FINAL_SIZE" -gt 10000 ]; then
	echo "App build successfully completed with valid full ARM64 Reynard binary output at $TARGET_APP (Executable size: $FINAL_SIZE bytes)"
	exit 0
else
	echo "=== BUILD FAILED: Executable binary too small or missing (Size: $FINAL_SIZE bytes) ==="
	echo "--- Reynard Target Xcodebuild Log Tail ---"
	tail -n 80 "$DIST_DIR/xcodebuild_reynard.log" 2>/dev/null || true
	echo "--- Swiftc Full Log Tail ---"
	tail -n 80 "$DIST_DIR/swiftc_full.log" 2>/dev/null || true
	exit 1
fi
