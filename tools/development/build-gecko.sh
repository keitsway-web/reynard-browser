#!/bin/sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"

TARGET="aarch64-apple-ios"

cd "$ROOT_DIR"

if [ ! -d "$FIREFOX_DIR" ]; then
	echo "Missing firefox source at $FIREFOX_DIR"
	echo "Add the submodule, then run tools/development/update-gecko.sh."
	exit 1
fi

if [ -f "$FIREFOX_DIR/.mozconfig" ]; then
	mv "$FIREFOX_DIR/.mozconfig" "$FIREFOX_DIR/.mozconfig.bak"
fi

export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"

{
	echo "ac_add_options --enable-application=mobile/ios"
	echo "ac_add_options --target=$TARGET"
	echo "ac_add_options --enable-ios-target=13.0"
	if [ -n "$SDK_PATH" ]; then
		echo "ac_add_options --with-macos-sdk=$SDK_PATH"
	fi
	if command -v ccache >/dev/null 2>&1; then
		echo "ac_add_options --with-ccache=ccache"
	fi
	if command -v lld >/dev/null 2>&1 || command -v ld.lld >/dev/null 2>&1; then
		echo "ac_add_options --enable-linker=lld"
	fi
	echo "ac_add_options --without-wasm-sandboxed-libraries"
	echo "ac_add_options --enable-webrtc"
	echo "ac_add_options --enable-optimize"
	echo "ac_add_options --enable-release"
	echo "ac_add_options --enable-rust-simd"
	echo "ac_add_options --disable-lto"
	echo "ac_add_options --disable-debug"
	echo "ac_add_options --disable-tests"
	echo "mk_add_options MOZ_MAKE_FLAGS=\"-j3\""
} > "$FIREFOX_DIR/.mozconfig"

if ! rustup target list | grep -q "^$TARGET (installed)"; then
	rustup target add "$TARGET"
fi

cd "$FIREFOX_DIR"
if [ -n "$SDK_PATH" ]; then
	export SDKROOT="$SDK_PATH"
fi
./mach build

rm -f "$FIREFOX_DIR/.mozconfig"
if [ -f "$FIREFOX_DIR/.mozconfig.bak" ]; then
	mv "$FIREFOX_DIR/.mozconfig.bak" "$FIREFOX_DIR/.mozconfig"
fi
