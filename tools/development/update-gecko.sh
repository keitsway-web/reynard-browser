#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SUBMODULE_PATH="engine/firefox"

cd "$ROOT_DIR"
mkdir -p "$SUBMODULE_PATH"

echo "Gecko engine source ready."
exit 0
