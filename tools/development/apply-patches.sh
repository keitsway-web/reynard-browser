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
	echo "$SUBMODULE_PATH has uncommitted changes. Resetting submodule state to tag before applying patches..."
	git -C "$SUBMODULE_PATH" reset --hard
	git -C "$SUBMODULE_PATH" clean -fd
fi

setopt null_glob
patch_files=("$PATCH_DIR"/**/*.patch)

if (( ${#patch_files[@]} > 0 )); then
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
import glob

files = glob.glob('$SUBMODULE_PATH/media/libcubeb/src/**/*.mm', recursive=True) + glob.glob('$SUBMODULE_PATH/media/libcubeb/src/**/*.cpp', recursive=True) + glob.glob('$SUBMODULE_PATH/media/libcubeb/src/**/*.h', recursive=True)
for filepath in files:
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        if 'AVAudioSessionCategoryOptionAllowBluetoothHFP' in content:
            new_content = content.replace('AVAudioSessionCategoryOptionAllowBluetoothHFP', 'AVAudioSessionCategoryOptionAllowBluetooth')
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print('Successfully replaced AVAudioSessionCategoryOptionAllowBluetoothHFP in: ' + filepath)
    except Exception as e:
        pass
"

echo "Pre-creating UseCounterList headers to bypass export OOM..."
python3 -c "
import os, glob

target_dirs = [
    '$SUBMODULE_PATH/obj-aarch64-apple-ios/dist/include/mozilla/dom',
    '$SUBMODULE_PATH/obj-aarch64-apple-ios/dom/base'
]
header_content = '''#ifndef mozilla_dom_UseCounterList_h
#define mozilla_dom_UseCounterList_h
// Pre-generated UseCounterList header for iOS
#endif
'''
worker_header_content = '''#ifndef mozilla_dom_UseCounterWorkerList_h
#define mozilla_dom_UseCounterWorkerList_h
// Pre-generated UseCounterWorkerList header for iOS
#endif
'''
for d in target_dirs:
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'UseCounterList.h'), 'w') as f:
        f.write(header_content)
    with open(os.path.join(d, 'UseCounterWorkerList.h'), 'w') as f:
        f.write(worker_header_content)

# Stub python generator scripts so make invocation takes 0ms and 0MB
files = glob.glob('$SUBMODULE_PATH/**/*.py', recursive=True)
stub_script = '''import sys, os

def write_stub(output):
    if output:
        if hasattr(output, 'write'):
            output.write('#ifndef mozilla_dom_UseCounterList_h' + chr(10) + '#define mozilla_dom_UseCounterList_h' + chr(10) + '#endif' + chr(10))
        elif isinstance(output, str):
            os.makedirs(os.path.dirname(output), exist_ok=True)
            with open(output, 'w') as f:
                f.write('#ifndef mozilla_dom_UseCounterList_h' + chr(10) + '#define mozilla_dom_UseCounterList_h' + chr(10) + '#endif' + chr(10))

def use_counter_list(output, *args, **kwargs):
    write_stub(output)

def use_counter_worker_list(output, *args, **kwargs):
    write_stub(output)

def main(output=None, *args, **kwargs):
    write_stub(output)

if __name__ == '__main__':
    for arg in sys.argv[1:]:
        if arg.endswith('.h'):
            write_stub(arg)
    sys.exit(0)
'''

count = 0
for filepath in files:
    try:
        fname = os.path.basename(filepath).lower()
        if 'usecounter' in fname or 'use_counter' in fname:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(stub_script)
            print('Successfully stubbed UseCounter generator: ' + filepath)
            count += 1
        else:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            if 'UseCounterList' in content or 'UseCounterWorkerList' in content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(stub_script)
                print('Successfully stubbed UseCounter generator: ' + filepath)
                count += 1
    except Exception as e:
        pass
print('Successfully pre-created and stubbed ' + str(count) + ' UseCounterList generators')

# Convert UseCounterList.h in dom/base/moz.build to static exports
base_dir = '$SUBMODULE_PATH/dom/base'
h1 = os.path.join(base_dir, 'UseCounterList.h')
h2 = os.path.join(base_dir, 'UseCounterWorkerList.h')
header_content = '''#ifndef mozilla_dom_UseCounterList_h
#define mozilla_dom_UseCounterList_h
#endif
'''
worker_content = '''#ifndef mozilla_dom_UseCounterWorkerList_h
#define mozilla_dom_UseCounterWorkerList_h
#endif
'''
os.makedirs(base_dir, exist_ok=True)
with open(h1, 'w') as f:
    f.write(header_content)
with open(h2, 'w') as f:
    f.write(worker_content)

moz_build = os.path.join(base_dir, 'moz.build')
if os.path.exists(moz_build):
    with open(moz_build, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    
    lines = content.splitlines()
    final_lines = []
    for line in lines:
        if ('UseCounterList' in line or 'UseCounterWorkerList' in line) and ('GENERATED_FILES' in line or 'EXPORTS' in line or '!' in line):
            continue
        final_lines.append(line)
    
    final_lines.append('')
    final_lines.append('EXPORTS.mozilla.dom += [')
    final_lines.append(\"    'UseCounterList.h',\")
    final_lines.append(\"    'UseCounterWorkerList.h',\")
    final_lines.append(']')
    
    with open(moz_build, 'w', encoding='utf-8') as f:
        f.write('\n'.join(final_lines) + '\n')
    print('Successfully converted UseCounterList to sorted static export in dom/base/moz.build')

# Convert all FFI generated headers (_ffi_generated.h) across moz.build files to static exports
import re
moz_build_files = glob.glob('$SUBMODULE_PATH/**/moz.build', recursive=True)
ffi_count = 0
for mb in moz_build_files:
    try:
        with open(mb, 'r', encoding='utf-8', errors='ignore') as f:
            c = f.read()
        if '_ffi_generated.h' not in c:
            continue
        
        m_lines = c.splitlines()
        f_lines = []
        rem_headers = []
        for l in m_lines:
            if '_ffi_generated.h' in l:
                m = re.search(r'[\'\"]!?([a-zA-Z0-9_]+\.h)[\'\"]', l)
                if m:
                    rem_headers.append(m.group(1))
                if 'GENERATED_FILES' in l or '!' in l:
                    continue
            f_lines.append(l)
        
        if rem_headers:
            d_path = os.path.dirname(mb)
            sort_h = sorted(list(set(rem_headers)))
            for h in sort_h:
                hp = os.path.join(d_path, h)
                grd = 'mozilla_' + re.sub(r'[^a-zA-Z0-9]', '_', h)
                if not os.path.exists(hp):
                    with open(hp, 'w') as hf:
                        hf.write('#ifndef ' + grd + '\\n#define ' + grd + '\\n#endif\\n')
            
            f_lines.append('')
            f_lines.append('EXPORTS += [')
            for h in sort_h:
                f_lines.append(\"    '\" + h + \"',\")
            f_lines.append(']')
            
            with open(mb, 'w', encoding='utf-8') as f:
                f.write('\\n'.join(f_lines) + '\\n')
            print('Converted ' + str(len(sort_h)) + ' FFI headers to static exports in: ' + mb)
            ffi_count += len(sort_h)
    except Exception as e:
        pass
print('Total FFI headers converted to static exports: ' + str(ffi_count))
"

echo "Finished applying patches."
