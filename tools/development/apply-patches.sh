#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
SUBMODULE_PATH="engine/firefox"
PATCH_DIR="${ROOT_DIR}/patches"

cd "$ROOT_DIR"

if [[ ! -f "engine/release.txt" ]]; then
	echo "Cannot get Firefox release tag: Missing engine/release.txt."
	exit 1
fi

RELEASE_TAG="$(tr -d '\000\r' < "engine/release.txt" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

if [[ -z "$RELEASE_TAG" ]]; then
	echo "Cannot get Firefox release tag: engine/release.txt is empty."
	exit 1
fi

if [[ ! -d "$SUBMODULE_PATH" ]]; then
	echo "Missing $SUBMODULE_PATH directory. Run tools/development/update-gecko.sh first."
	exit 1
fi

if ! git -C "$SUBMODULE_PATH" rev-parse -q --verify "$RELEASE_TAG^{commit}" >/dev/null 2>&1; then
	echo "Tag $RELEASE_TAG does not exist in $SUBMODULE_PATH."
	echo "Run tools/development/update-gecko.sh to fetch and checkout the release tag."
	exit 1
fi

RELEASE_COMMIT="$(git -C "$SUBMODULE_PATH" rev-parse "$RELEASE_TAG^{commit}")"
HEAD_COMMIT="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"

if [[ "$HEAD_COMMIT" != "$RELEASE_COMMIT" ]]; then
	CURRENT_TAG="$(git -C "$SUBMODULE_PATH" describe --tags --exact-match HEAD 2>/dev/null || echo "no-exact-tag")"
	echo "Submodule HEAD ($HEAD_COMMIT, tag: $CURRENT_TAG) does not match engine/release.txt ($RELEASE_TAG -> $RELEASE_COMMIT)."
	echo "Run tools/development/update-gecko.sh to sync the submodule commit before applying patches."
	exit 1
fi

if [[ ! -d "$PATCH_DIR" ]]; then
	echo "Missing patches directory: $PATCH_DIR."
	exit 1
fi

if [[ -n "$(git -C "$SUBMODULE_PATH" status --porcelain)" ]]; then
	echo "$SUBMODULE_PATH has uncommitted changes. Commit, stash, or reset before applying patches."
	exit 1
fi

echo "Applying iOS SDK patch to moz.configure files..."
python3 -c "
import glob

files = glob.glob('$SUBMODULE_PATH/**/*.configure', recursive=True) + glob.glob('$SUBMODULE_PATH/**/*.py', recursive=True)
for filepath in files:
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        if 'mac_sdk_min_version' in content or 'ios_sdk_min_version' in content or 'is too old. Please upgrade to at least' in content or 'SDK version' in content:
            new_content = content.replace('if version < Version(', 'if False and version < Version(')
            new_content = new_content.replace('if version < ', 'if False and version < ')
            if new_content != content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print('Successfully patched SDK version check in: ' + filepath)
    except Exception as e:
        pass
"

echo "Patching sys/fileport.h for iOS compatibility..."
python3 -c "
import glob

files = glob.glob('$SUBMODULE_PATH/**/*.cpp', recursive=True) + glob.glob('$SUBMODULE_PATH/**/*.cc', recursive=True) + glob.glob('$SUBMODULE_PATH/**/*.h', recursive=True) + glob.glob('$SUBMODULE_PATH/**/*.mm', recursive=True)
for filepath in files:
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        if '#include <sys/fileport.h>' in content and 'TARGET_OS_IPHONE' not in content:
            replacement = '''#include <TargetConditionals.h>
#if !TARGET_OS_IPHONE
#include <sys/fileport.h>
#else
#include <mach/mach.h>
extern \"C\" {
int fileport_makeport(int fd, mach_port_t* portname);
int fileport_makefd(mach_port_t portname);
}
#endif'''
            new_content = content.replace('#include <sys/fileport.h>', replacement)
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print('Successfully patched sys/fileport.h in: ' + filepath)
    except Exception as e:
        pass
"

echo "Patching AVAudioSessionCategoryOptionAllowBluetoothHFP for libcubeb iOS..."
python3 -c "
import os
audiounit_file = '$SUBMODULE_PATH/media/libcubeb/src/cubeb_audiounit_ios.mm'
if os.path.exists(audiounit_file):
    with open(audiounit_file, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    if 'AVAudioSessionCategoryOptionAllowBluetoothHFP' in content and '#define AVAudioSessionCategoryOptionAllowBluetoothHFP' not in content:
        header = '''#import <AVFoundation/AVFoundation.h>
#ifndef AVAudioSessionCategoryOptionAllowBluetoothHFP
#define AVAudioSessionCategoryOptionAllowBluetoothHFP (1U << 5)
#endif
'''
        content = header + content
        with open(audiounit_file, 'w', encoding='utf-8') as f:
            f.write(content)
        print('Successfully patched AVAudioSessionCategoryOptionAllowBluetoothHFP in cubeb_audiounit_ios.mm')
"

setopt null_glob
patch_files=("$PATCH_DIR"/**/*.patch)

if (( ${#patch_files[@]} == 0 )); then
	echo "No patch files found in $PATCH_DIR."
	echo "Finished applying patches."
	exit 0
fi

echo "Applying patches to $SUBMODULE_PATH..."
for patch_file in $patch_files; do
	rel_path="${patch_file#$PATCH_DIR/}"
	if [[ "$rel_path" == *"toolchain.configure"* ]]; then
		continue
	fi
	echo "Applying $rel_path..."

	if ! git -C "$SUBMODULE_PATH" apply --whitespace=nowarn "$patch_file" 2>/dev/null && \
	   ! git -C "$SUBMODULE_PATH" apply --3way --whitespace=nowarn "$patch_file" 2>/dev/null && \
	   ! git -C "$SUBMODULE_PATH" apply --ignore-space-change --ignore-whitespace "$patch_file"; then
		echo "Failed to apply $rel_path."
		if [[ -t 0 ]]; then
			echo "Resolve conflicts in $SUBMODULE_PATH, then press Enter to continue or type q to stop."
			read -r response
			if [[ "$response" == "q" || "$response" == "Q" ]]; then
				exit 1
			fi
		else
			exit 1
		fi
	fi
done

echo "Finished applying patches."
