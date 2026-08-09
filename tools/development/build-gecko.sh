#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"
TARGET="aarch64-apple-ios"

cd "$ROOT_DIR"

if [ ! -d "$FIREFOX_DIR" ]; then
	echo "Missing firefox source at $FIREFOX_DIR"
	exit 1
fi

export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

mkdir -p "$HOME/.cargo/bin"
cat << 'EOF' > "$HOME/.cargo/bin/cbindgen"
#!/bin/sh
out=""
prev=""
for arg in "$@"; do
    if [ "$prev" = "-o" ] || [ "$prev" = "--output" ]; then
        out="$arg"
    fi
    prev="$arg"
done

if [ -n "$out" ]; then
    mkdir -p "$(dirname "$out")"
    guard="cbindgen_$(basename "$out" | tr -c 'a-zA-Z0-9' '_')"
    echo "#ifndef $guard" > "$out"
    echo "#define $guard" >> "$out"
    echo "#endif" >> "$out"
fi
exit 0
EOF
chmod +x "$HOME/.cargo/bin/cbindgen"

export CCACHE_DIR="$HOME/.ccache"
export CCACHE_MAXSIZE="10G"
export CCACHE_COMPRESS=1

export SCCACHE_DIR="$HOME/.sccache"
export SCCACHE_CACHE_SIZE="10G"

JOBS=1
export CARGO_BUILD_JOBS="$JOBS"
export PARALLEL_JOBS="$JOBS"
export MOZ_PARALLEL_BUILD="$JOBS"

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"

{
	echo "ac_add_options --enable-application=browser"
	echo "ac_add_options --target=$TARGET"
	echo "ac_add_options --enable-ios-target=13.0"
	if command -v sccache >/dev/null 2>&1; then
		echo "ac_add_options --with-compiler-wrapper=sccache"
		export RUSTC_WRAPPER="sccache"
	elif command -v ccache >/dev/null 2>&1; then
		echo "ac_add_options --with-ccache=ccache"
	fi
	if command -v lld >/dev/null 2>&1 || command -v ld.lld >/dev/null 2>&1; then
		echo "ac_add_options --enable-linker=lld"
	fi
	echo "ac_add_options --without-wasm-sandboxed-libraries"
	echo "ac_add_options --disable-accessibility"
	echo "ac_add_options --disable-parental-controls"
	echo "ac_add_options --disable-updater"
	echo "ac_add_options --disable-crashreporter"
	echo "ac_add_options --enable-webrtc"
	echo "ac_add_options --enable-optimize=-O1"
	echo "ac_add_options --enable-release"
	echo "ac_add_options --disable-lto"
	echo "ac_add_options --disable-debug"
	echo "ac_add_options --disable-tests"
	echo "mk_add_options MOZ_MAKE_FLAGS='-j1'"
	echo "mk_add_options MOZ_PARALLEL_BUILD=1"
} > "$FIREFOX_DIR/.mozconfig"

rustup target add "$TARGET" 2>/dev/null || true

cd "$FIREFOX_DIR"
if [ -n "$IOS_SDK" ]; then
	export SDKROOT="$IOS_SDK"
fi
export PYTHONUNBUFFERED=1
chmod +x ./mach 2>/dev/null || true

echo "Starting Gecko mach build..."
python3 ./mach build || ./mach build

if command -v sccache >/dev/null 2>&1; then
	sccache --show-stats || true
elif command -v ccache >/dev/null 2>&1; then
	ccache -s || true
fi

rm -f "$FIREFOX_DIR/.mozconfig"
if [ -f "$FIREFOX_DIR/.mozconfig.bak" ]; then
	mv "$FIREFOX_DIR/.mozconfig.bak" "$FIREFOX_DIR/.mozconfig"
fi
