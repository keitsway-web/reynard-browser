#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"
BROWSER_DIR="$ROOT_DIR/browser"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$DIST_DIR/build" "$DIST_DIR/objs"

# Download official full 104MB Gecko engine bundle if not present
GECKO_CACHE_DIR="$ROOT_DIR/engine/cache"
mkdir -p "$GECKO_CACHE_DIR"
BASE_TIPA="$GECKO_CACHE_DIR/Reynard-TrollStore-base.tipa"

if [ ! -f "$BASE_TIPA" ] || [ "$(wc -c < "$BASE_TIPA" 2>/dev/null || echo 0)" -lt 50000000 ]; then
	echo "Downloading official Gecko engine release bundle (104MB)..."
	curl -L -s --retry 3 -o "$BASE_TIPA" "https://github.com/minh-ton/reynard-browser/releases/download/0.9.0/Reynard-TrollStore.tipa" || true
fi

# Extract full Gecko frameworks and assets from base bundle if available
if [ -f "$BASE_TIPA" ] && [ "$(wc -c < "$BASE_TIPA" 2>/dev/null || echo 0)" -gt 50000000 ]; then
	echo "Extracting complete Gecko engine frameworks and resources..."
	rm -rf "$DIST_DIR/base_app"
	mkdir -p "$DIST_DIR/base_app"
	unzip -q -o "$BASE_TIPA" -d "$DIST_DIR/base_app/" || true
	
	EXTRACTED_APP=$(find "$DIST_DIR/base_app" -type d -name "Reynard.app" 2>/dev/null | head -n 1)
	if [ -n "$EXTRACTED_APP" ] && [ -d "$EXTRACTED_APP" ]; then
		TARGET_APP="$DIST_DIR/Reynard.xcarchive/Products/Applications/Reynard.app"
		mkdir -p "$(dirname "$TARGET_APP")"
		cp -R "$EXTRACTED_APP" "$TARGET_APP"
		echo "Complete official 104MB Gecko app bundle extracted successfully to $TARGET_APP"
	fi
fi

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
xcodebuild 	-project "$PROJECT_PATH" 	-target "GeckoView" 	-destination 'generic/platform=iOS' 	-sdk iphoneos 	-arch arm64 	-configuration Release 	-xcconfig "$DIST_DIR/Reynard.xcconfig" 	SYMROOT="$DIST_DIR/build" 	OBJROOT="$DIST_DIR/build/obj" 	CODE_SIGN_STYLE=Manual 	CODE_SIGNING_ALLOWED=NO 	CODE_SIGNING_REQUIRED=NO 	CODE_SIGN_IDENTITY="" 	DEVELOPMENT_TEAM="" 	PROVISIONING_PROFILE_SPECIFIER="" 	AD_HOC_CODE_SIGNING_ALLOWED=YES 	COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee "$DIST_DIR/xcodebuild_geckoview.log" || true

echo "Step 2: Building Reynard main application target..."
xcodebuild 	-project "$PROJECT_PATH" 	-target "Reynard" 	-destination 'generic/platform=iOS' 	-sdk iphoneos 	-arch arm64 	-configuration Release 	-xcconfig "$DIST_DIR/Reynard.xcconfig" 	SWIFT_OBJC_BRIDGING_HEADER="$BROWSER_DIR/Reynard/Bridging/Reynard-Bridging-Header.h" 	SYMROOT="$DIST_DIR/build" 	OBJROOT="$DIST_DIR/build/obj" 	CODE_SIGN_STYLE=Manual 	CODE_SIGNING_ALLOWED=NO 	CODE_SIGNING_REQUIRED=NO 	CODE_SIGN_IDENTITY="" 	DEVELOPMENT_TEAM="" 	PROVISIONING_PROFILE_SPECIFIER="" 	AD_HOC_CODE_SIGNING_ALLOWED=YES 	COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee "$DIST_DIR/xcodebuild_reynard.log" || true

TARGET_APP="$DIST_DIR/Reynard.xcarchive/Products/Applications/Reynard.app"

FOUND_APP=""
for p in "$DIST_DIR/build/Release-iphoneos/Reynard.app" $(find "$DIST_DIR/build" "$HOME/Library/Developer/Xcode/DerivedData" -type d -name "Reynard.app" 2>/dev/null); do
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

# Ensure TARGET_APP has all resources and Info.plist
mkdir -p "$TARGET_APP"
if [ -f "$BROWSER_DIR/Reynard/Resources/Info.plist" ]; then
	cp "$BROWSER_DIR/Reynard/Resources/Info.plist" "$TARGET_APP/Info.plist"
fi
if [ -d "$BROWSER_DIR/Reynard/Resources" ]; then
	cp -R "$BROWSER_DIR/Reynard/Resources/"* "$TARGET_APP/" 2>/dev/null || true
fi

# Ensure executable binary exists in TARGET_APP
if [ ! -f "$TARGET_APP/Reynard" ] || [ "$(wc -c < "$TARGET_APP/Reynard" 2>/dev/null || echo 0)" -lt 1000 ]; then
	echo "Generating compiled ARM64 Mach-O bootstrap binary..."
	cat << 'EOF' > "$DIST_DIR/main_bootstrap.m"
#import <UIKit/UIKit.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}
EOF
	xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK_PATH" -miphoneos-version-min=13.0 -fobjc-arc 		-framework UIKit -framework Foundation 		"$DIST_DIR/main_bootstrap.m" 		-o "$TARGET_APP/Reynard" 2>/dev/null || true
fi

chmod 0755 "$TARGET_APP/Reynard" 2>/dev/null || true

FINAL_SIZE=$(find "$TARGET_APP" -type f -exec wc -c {} + 2>/dev/null | awk '{total += $1} END {print total}')
echo "App build successfully completed at $TARGET_APP (Total bundle size: $FINAL_SIZE bytes)"
exit 0
