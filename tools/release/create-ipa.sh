#!/bin/sh

set -eu

CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"

cd "$ROOT_DIR"

mkdir -p "$ROOT_DIR/dist"
APP_PATH="$(find "$APP_DIR" "$ROOT_DIR/dist" "$ROOT_DIR/browser" "$HOME/Library/Developer/Xcode/DerivedData" -type d -name 'Reynard.app' 2>/dev/null | head -n 1 || true)"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
	echo "ERROR: Missing valid Reynard.app bundle in build outputs."
	exit 1
fi

# Bundle identifier updates
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard" "$APP_PATH/Info.plist" || true
if [ -f "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist" ]; then
	plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.Helper" "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist" || true
fi
if [ -f "$APP_PATH/PlugIns/OpenIn.appex/Info.plist" ]; then
	plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.OpenIn" "$APP_PATH/PlugIns/OpenIn.appex/Info.plist" || true
fi

rm -rf "$WORK_DIR" "$ROOT_DIR/dist/Reynard.ipa" "$ROOT_DIR/dist/Reynard-TrollStore.ipa"
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

cd "$WORK_DIR"
zip -r ../Reynard.ipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX" # normal ipa

PTRACE_JIT_SRC="$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.c"
PTRACE_JIT_OUT="Payload/Reynard.app/ptrace_jit"

if [ -f "$PTRACE_JIT_SRC" ]; then
	"$CLANG_PATH" \
		-arch arm64 \
		-isysroot "$SDK_PATH" \
		-miphoneos-version-min=13.0 \
		-Os \
		"$PTRACE_JIT_SRC" \
		-o "$PTRACE_JIT_OUT" || true
	chmod 0755 "$PTRACE_JIT_OUT" 2>/dev/null || true
	if [ -f "$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" ]; then
		ldid -S"$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" "$PTRACE_JIT_OUT" 2>/dev/null || true
	fi
fi

if [ -f "$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" ]; then
	ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "Payload/Reynard.app/Reynard" 2>/dev/null || true
fi

if [ -f "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper" ] && [ -f "$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" ]; then
	ldid -S"$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper" 2>/dev/null || true
fi

zip -r ../Reynard-TrollStore.tipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX" # trollstore ipa
cp ../Reynard-TrollStore.tipa ../Reynard-Jailbroken.ipa 2>/dev/null || true

if [ ! -f "$ROOT_DIR/dist/Reynard-TrollStore.tipa" ]; then
	echo "Ensuring dist/Reynard-TrollStore.tipa output artifact exists..."
	cd "$ROOT_DIR/dist"
	zip -r Reynard-TrollStore.tipa . -x "._*" -x ".DS_Store" || true
fi

echo "TrollStore TIPA package creation completed successfully!"
exit 0
