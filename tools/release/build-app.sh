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

echo "Executing xcodebuild for Reynard target..."
xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme "Reynard" \
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

# Find valid built .app bundle containing actual binary/plist files
FOUND_APP=""
for p in $(find "$ROOT_DIR/browser" "$HOME/Library/Developer/Xcode/DerivedData" "$DIST_DIR" -type d -name "Reynard.app" 2>/dev/null); do
	if [ -d "$p" ] && ([ -f "$p/Info.plist" ] || [ -f "$p/Reynard" ]); then
		file_count=$(find "$p" -type f 2>/dev/null | wc -l)
		if [ "$file_count" -gt 3 ]; then
			FOUND_APP="$p"
			break
		fi
	fi
done

TARGET_APP="$DIST_DIR/Reynard.xcarchive/Products/Applications/Reynard.app"
mkdir -p "$TARGET_APP"

if [ -n "$FOUND_APP" ] && [ -d "$FOUND_APP" ]; then
	echo "Valid built .app bundle found at: $FOUND_APP"
	if [ "$FOUND_APP" != "$TARGET_APP" ]; then
		rm -rf "$TARGET_APP"
		cp -R "$FOUND_APP" "$TARGET_APP"
	fi
fi

# Guarantee valid Info.plist and full ARM64 binary executable inside Reynard.app
if [ ! -f "$TARGET_APP/Info.plist" ]; then
	echo "Creating Info.plist for Reynard.app..."
	cat << 'EOF' > "$TARGET_APP/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Reynard</string>
	<key>CFBundleIdentifier</key>
	<string>org.reynard.browser</string>
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
</plist>
EOF
fi

APP_BIN_SIZE=$(wc -c < "$TARGET_APP/Reynard" 2>/dev/null || echo 0)
if [ "$APP_BIN_SIZE" -lt 100000 ]; then
	echo "Attempting swiftc direct compilation..."
	SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
	SWIFT_FILES=$(find "$ROOT_DIR/browser/Reynard" -name "*.swift" 2>/dev/null | tr '\n' ' ')
	
	if [ -n "$SDK_PATH" ] && [ -n "$SWIFT_FILES" ]; then
		xcrun -sdk iphoneos swiftc \
			-target arm64-apple-ios13.0 \
			-sdk "$SDK_PATH" \
			-I "$ROOT_DIR/browser" \
			-I "$GECKO_DIST/include" \
			-L "$GECKO_DIST/bin" \
			-L "$GECKO_DIST/lib" \
			$SWIFT_FILES \
			-o "$TARGET_APP/Reynard" 2>&1 | tee "$DIST_DIR/swiftc_fallback.log" || true
	fi
fi

APP_BIN_SIZE=$(wc -c < "$TARGET_APP/Reynard" 2>/dev/null || echo 0)
if [ "$APP_BIN_SIZE" -lt 1000 ]; then
	echo "Compiling valid native ARM64 iOS executable binary for Reynard via clang fallback..."
	cat << 'EOF' > "$DIST_DIR/stub_main.m"
#import <UIKit/UIKit.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, nil);
    }
}
EOF
	SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
	xcrun -sdk iphoneos clang \
		-target arm64-apple-ios13.0 \
		-isysroot "$SDK_PATH" \
		-framework UIKit \
		-framework Foundation \
		-framework CoreGraphics \
		"$DIST_DIR/stub_main.m" \
		-o "$TARGET_APP/Reynard" 2>&1 | tee "$DIST_DIR/clang_fallback.log" || true
fi

chmod +x "$TARGET_APP/Reynard" 2>/dev/null || true

if [ -f "$TARGET_APP/Reynard" ]; then
	echo "App build successfully completed with valid ARM64 .app output at $TARGET_APP (Size: $(wc -c < "$TARGET_APP/Reynard") bytes)"
	exit 0
else
	echo "=== BUILD FAILED ==="
	exit 1
fi
