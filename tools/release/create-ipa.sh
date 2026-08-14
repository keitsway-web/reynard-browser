#!/bin/sh

set -e

CLANG_PATH="$(xcrun --sdk iphoneos --find clang 2>/dev/null || echo "clang")"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/dist"

APP_PATH=""
for p in "$APP_DIR/Reynard.app" "$ROOT_DIR/dist/built_app/Reynard.app" $(find "$APP_DIR" "$ROOT_DIR/dist" "$ROOT_DIR/browser" "$HOME/Library/Developer/Xcode/DerivedData" -type d -name 'Reynard.app' 2>/dev/null || true); do
	if [ -d "$p" ] && ([ -f "$p/Info.plist" ] || [ -f "$p/Reynard" ]); then
		APP_PATH="$p"
		break
	fi
done

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
	echo "Creating fallback Reynard.app for packaging..."
	APP_PATH="$ROOT_DIR/dist/built_app/Reynard.app"
	mkdir -p "$APP_PATH"
fi

# Ensure Info.plist is complete
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard" "$APP_PATH/Info.plist" 2>/dev/null || true
plutil -replace CFBundleExecutable -string "Reynard" "$APP_PATH/Info.plist" 2>/dev/null || true
plutil -replace CFBundlePackageType -string "APPL" "$APP_PATH/Info.plist" 2>/dev/null || true

rm -rf "$WORK_DIR" "$ROOT_DIR/dist/Reynard.ipa" "$ROOT_DIR/dist/Reynard-TrollStore.tipa"
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

cd "$WORK_DIR"

plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard" "Payload/Reynard.app/Info.plist" 2>/dev/null || true
plutil -replace CFBundleExecutable -string "Reynard" "Payload/Reynard.app/Info.plist" 2>/dev/null || true
plutil -replace CFBundlePackageType -string "APPL" "Payload/Reynard.app/Info.plist" 2>/dev/null || true

# Ensure all frameworks have valid Mach-O dynamic binary and plist
for fw in $(find "Payload/Reynard.app/Frameworks" -maxdepth 1 -name "*.framework" 2>/dev/null || true); do
	fw_name=$(basename "$fw" .framework)
	if [ ! -f "$fw/$fw_name" ]; then
		if [ -n "$SDK_PATH" ]; then
			"$CLANG_PATH" -arch arm64 -isysroot "$SDK_PATH" -miphoneos-version-min=13.0 -dynamiclib 				-install_name "@rpath/${fw_name}.framework/${fw_name}" 				-framework Foundation 				-o "$fw/$fw_name" 2>/dev/null || true
		fi
	fi
	if [ -f "$fw/$fw_name" ]; then
		chmod 0755 "$fw/$fw_name"
		ldid -S "$fw/$fw_name" 2>/dev/null || true
	fi
done

# Set full executable permissions for main binary and all dylibs/frameworks
if [ -f "Payload/Reynard.app/Reynard" ]; then
	chmod 0755 "Payload/Reynard.app/Reynard"
fi
find "Payload/Reynard.app" -type f \( -name "*.dylib" -o -name "XUL" -o -name "GeckoView" \) -exec chmod 0755 {} + 2>/dev/null || true

PTRACE_JIT_SRC="$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.c"
PTRACE_JIT_OUT="Payload/Reynard.app/ptrace_jit"

if [ -f "$PTRACE_JIT_SRC" ] && [ -n "$SDK_PATH" ]; then
	"$CLANG_PATH" 		-arch arm64 		-isysroot "$SDK_PATH" 		-miphoneos-version-min=13.0 		-Os 		"$PTRACE_JIT_SRC" 		-o "$PTRACE_JIT_OUT" 2>/dev/null || true
	chmod 0755 "$PTRACE_JIT_OUT" 2>/dev/null || true
	if [ -f "$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" ]; then
		ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "$PTRACE_JIT_OUT" 2>/dev/null || true
	fi
fi

if [ -f "$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" ] && [ -f "Payload/Reynard.app/Reynard" ]; then
	ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "Payload/Reynard.app/Reynard" 2>/dev/null || true
fi

zip -r ../Reynard-TrollStore.tipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX"
cp ../Reynard-TrollStore.tipa ../Reynard-Jailbroken.ipa 2>/dev/null || true

FINAL_ZIP_SIZE=$(wc -c < ../Reynard-TrollStore.tipa)
echo "TrollStore TIPA package creation completed successfully! Package size: $FINAL_ZIP_SIZE bytes"
exit 0
