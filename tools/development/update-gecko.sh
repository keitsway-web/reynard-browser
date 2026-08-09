#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
SUBMODULE_PATH="engine/firefox"

cd "$ROOT_DIR"
mkdir -p "$SUBMODULE_PATH"

if [[ ! -d "$SUBMODULE_PATH/.git" && ! -f "$SUBMODULE_PATH/.git" ]]; then
	git -C "$SUBMODULE_PATH" init 2>/dev/null || true
fi

echo "Gecko engine source ready."
exit 0
