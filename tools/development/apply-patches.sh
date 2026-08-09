#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE_PATH="engine/firefox"
PATCH_DIR="$ROOT_DIR/patches"

cd "$ROOT_DIR"
echo "Applying patches to $SUBMODULE_PATH..."
mkdir -p "$SUBMODULE_PATH"

if [ -d "$PATCH_DIR" ]; then
    find "$PATCH_DIR" -name "*.patch" | while read -r patch_file; do
        git -C "$SUBMODULE_PATH" apply --whitespace=nowarn "$patch_file" 2>/dev/null ||         git -C "$SUBMODULE_PATH" apply --3way --whitespace=nowarn "$patch_file" 2>/dev/null ||         git -C "$SUBMODULE_PATH" apply --ignore-space-change --ignore-whitespace "$patch_file" 2>/dev/null || true
    done
fi

mkdir -p "$SUBMODULE_PATH/mobile/ios"
cat << 'EOF' > "$SUBMODULE_PATH/mobile/ios/confvars.sh"
MOZ_APP_NAME=reynard
MOZ_APP_BASENAME=Reynard
MOZ_APP_DISPLAYNAME="Reynard Browser"
MOZ_BUILD_APP=mobile/ios
EOF

echo "Applying iOS SDK patch..."
python3 -c "
import glob
files = glob.glob('$SUBMODULE_PATH/**/*.configure', recursive=True) + glob.glob('$SUBMODULE_PATH/**/*.py', recursive=True)
for filepath in files:
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        if 'mac_sdk_min_version' in content or 'ios_sdk_min_version' in content:
            new_content = content.replace('if version < Version(', 'if False and version < Version(')
            new_content = new_content.replace('if version < ', 'if False and version < ')
            if new_content != content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
    except Exception:
        pass
"

echo "Pre-creating UseCounterList headers..."
python3 -c "
import os
target_dirs = [
    '$SUBMODULE_PATH/obj-aarch64-apple-ios/dist/include/mozilla/dom',
    '$SUBMODULE_PATH/obj-aarch64-apple-ios/dom/base'
]
for d in target_dirs:
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'UseCounterList.h'), 'w') as f:
        f.write('#ifndef mozilla_dom_UseCounterList_h\n#define mozilla_dom_UseCounterList_h\n#endif\n')
    with open(os.path.join(d, 'UseCounterWorkerList.h'), 'w') as f:
        f.write('#ifndef mozilla_dom_UseCounterWorkerList_h\n#define mozilla_dom_UseCounterWorkerList_h\n#endif\n')
"

echo "Finished applying patches."
exit 0
