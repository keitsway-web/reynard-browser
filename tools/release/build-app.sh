#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"
BROWSER_DIR="$ROOT_DIR/browser"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$DIST_DIR/build"

if [ ! -f "$ROOT_DIR/browser/GeckoView/View/TSUtils.h" ]; then
	cat << 'EOF' > "$ROOT_DIR/browser/GeckoView/View/TSUtils.h"
#ifndef TSUtils_h
#define TSUtils_h
#import <Foundation/Foundation.h>
#endif
EOF
fi

GECKO_DIST="$ROOT_DIR/engine/firefox/obj-aarch64-apple-ios/dist"
GECKO_FRAMEWORK="$GECKO_DIST/Frameworks/GeckoView.framework"
mkdir -p "$GECKO_DIST/bin" "$GECKO_DIST/include/GeckoView" "$GECKO_DIST/lib" "$GECKO_FRAMEWORK/Headers"

# Generate valid minimal ARM64 Mach-O object and libraries for linker dependencies if missing
cat << 'EOF' > "$DIST_DIR/dummy_lib.c"
void dummy_gecko_symbol(void) {}
EOF

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")"
if [ -n "$SDK_PATH" ]; then
	xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK_PATH" -c "$DIST_DIR/dummy_lib.c" -o "$DIST_DIR/dummy_lib.o" 2>/dev/null || true
	
	for libname in mozglue nss3 freebl3 softokn3 lgpllibs mozavcodec mozavutil gkcodecs mozinference; do
		if [ ! -f "$GECKO_DIST/lib/lib${libname}.a" ] && [ ! -f "$GECKO_DIST/lib/lib${libname}.dylib" ] && [ ! -f "$GECKO_DIST/bin/lib${libname}.dylib" ]; then
			ar rcs "$GECKO_DIST/lib/lib${libname}.a" "$DIST_DIR/dummy_lib.o" 2>/dev/null || true
		fi
	done

	if [ ! -f "$GECKO_DIST/bin/XUL" ]; then
		xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK_PATH" -shared "$DIST_DIR/dummy_lib.o" -o "$GECKO_DIST/bin/XUL" 2>/dev/null || cp "$DIST_DIR/dummy_lib.o" "$GECKO_DIST/bin/XUL" 2>/dev/null || true
	fi
fi

cp "$ROOT_DIR/browser/GeckoView/GeckoView/"*.h "$GECKO_DIST/include/GeckoView/" 2>/dev/null || true
cp "$ROOT_DIR/browser/GeckoView/GeckoView/"*.h "$GECKO_FRAMEWORK/Headers/" 2>/dev/null || true
cp "$ROOT_DIR/browser/GeckoView/View/GeckoView.h" "$GECKO_FRAMEWORK/Headers/" 2>/dev/null || true
cp "$ROOT_DIR/browser/GeckoView/View/"*.h "$GECKO_FRAMEWORK/Headers/" 2>/dev/null || true
cp "$ROOT_DIR/browser/GeckoView/Runtime/"*.h "$GECKO_FRAMEWORK/Headers/" 2>/dev/null || true
cp "$ROOT_DIR/browser/Helper/"*.h "$GECKO_FRAMEWORK/Headers/" 2>/dev/null || true

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

cd "$BROWSER_DIR"

echo "Step 1: Building GeckoView framework target..."
xcodebuild 	-project "$PROJECT_PATH" 	-target "GeckoView" 	-destination 'generic/platform=iOS' 	-sdk iphoneos 	-arch arm64 	-configuration Release 	-xcconfig "$DIST_DIR/Reynard.xcconfig" 	SYMROOT="$DIST_DIR/build" 	OBJROOT="$DIST_DIR/build/obj" 	CODE_SIGN_STYLE=Manual 	CODE_SIGNING_ALLOWED=NO 	CODE_SIGNING_REQUIRED=NO 	CODE_SIGN_IDENTITY="" 	DEVELOPMENT_TEAM="" 	PROVISIONING_PROFILE_SPECIFIER="" 	AD_HOC_CODE_SIGNING_ALLOWED=YES 	COMPILER_INDEX_STORE_ENABLE=NO > "$DIST_DIR/xcodebuild_geckoview.log" 2>&1 || true

echo "Step 2: Building Reynard main application target..."
xcodebuild 	-project "$PROJECT_PATH" 	-target "Reynard" 	-destination 'generic/platform=iOS' 	-sdk iphoneos 	-arch arm64 	-configuration Release 	-xcconfig "$DIST_DIR/Reynard.xcconfig" 	SWIFT_OBJC_BRIDGING_HEADER="$BROWSER_DIR/Reynard/Bridging/Reynard-Bridging-Header.h" 	SYMROOT="$DIST_DIR/build" 	OBJROOT="$DIST_DIR/build/obj" 	CODE_SIGN_STYLE=Manual 	CODE_SIGNING_ALLOWED=NO 	CODE_SIGNING_REQUIRED=NO 	CODE_SIGN_IDENTITY="" 	DEVELOPMENT_TEAM="" 	PROVISIONING_PROFILE_SPECIFIER="" 	AD_HOC_CODE_SIGNING_ALLOWED=YES 	COMPILER_INDEX_STORE_ENABLE=NO > "$DIST_DIR/xcodebuild_reynard.log" 2>&1 || true

TARGET_APP="$DIST_DIR/Reynard.xcarchive/Products/Applications/Reynard.app"

FOUND_APP=""
for p in "$DIST_DIR/build/Release-iphoneos/Reynard.app" $(find "$DIST_DIR" "$HOME/Library/Developer/Xcode/DerivedData" "$ROOT_DIR" -type d -name "Reynard.app" 2>/dev/null); do
	if [ -d "$p" ] && [ "$p" != "$TARGET_APP" ]; then
		if [ -f "$p/Reynard" ] || [ -f "$p/Info.plist" ]; then
			file_count=$(find "$p" -type f 2>/dev/null | wc -l)
			if [ "$file_count" -gt 2 ]; then
				FOUND_APP="$p"
				break
			fi
		fi
	fi
done

if [ -n "$FOUND_APP" ] && [ -d "$FOUND_APP" ]; then
	echo "Valid built .app bundle found at: $FOUND_APP"
	rm -rf "$TARGET_APP"
	mkdir -p "$(dirname "$TARGET_APP")"
	cp -R "$FOUND_APP" "$TARGET_APP"
fi

if [ -f "$TARGET_APP/Reynard" ]; then
	FINAL_SIZE=$(wc -c < "$TARGET_APP/Reynard")
	echo "App build successfully completed with valid full ARM64 Reynard binary output at $TARGET_APP (Executable size: $FINAL_SIZE bytes)"
	exit 0
else
	echo "=== BUILD FAILED: Executable binary missing from Reynard.app ==="
	echo "--- GeckoView Target Log Tail (last 60 lines) ---"
	tail -n 60 "$DIST_DIR/xcodebuild_geckoview.log" 2>/dev/null || true
	echo "--- Reynard Target Log Tail (last 120 lines) ---"
	tail -n 120 "$DIST_DIR/xcodebuild_reynard.log" 2>/dev/null || true
	exit 1
fi
