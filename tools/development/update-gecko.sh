#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h:h}"
SUBMODULE_PATH="engine/firefox"
FIREFOX_URL="https://github.com/mozilla-firefox/firefox"

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

if git -C "$SUBMODULE_PATH" rev-parse -q --verify "$RELEASE_TAG^{commit}" >/dev/null 2>&1; then
	echo "Tag $RELEASE_TAG is already present in $SUBMODULE_PATH. Skipping network fetch."
	git -C "$SUBMODULE_PATH" checkout --detach "$RELEASE_TAG^{commit}" || true
	exit 0
fi

if ! git ls-remote --exit-code --tags "$FIREFOX_URL" "refs/tags/$RELEASE_TAG" >/dev/null 2>&1; then
	echo "Release tag $RELEASE_TAG does not exist in $FIREFOX_URL."
	exit 1
fi

TAG_REF="refs/tags/$RELEASE_TAG"

echo "Fetching and checking out tag $RELEASE_TAG..."
git -C "$SUBMODULE_PATH" config http.postBuffer 524288000
git -C "$SUBMODULE_PATH" config http.lowSpeedLimit 0
git -C "$SUBMODULE_PATH" config http.lowSpeedTime 999999

n=0
until (( n >= 5 )); do
	if git -C "$SUBMODULE_PATH" fetch --depth 1 origin tag "$RELEASE_TAG"; then
		break
	fi
	n=$((n + 1))
	if (( n >= 5 )); then
		echo "Failed to fetch tag $RELEASE_TAG after 5 attempts."
		exit 1
	fi
	echo "Git fetch failed (attempt $n/5). Retrying in 5 seconds..."
	sleep 5
done

git -C "$SUBMODULE_PATH" checkout --detach "$TAG_REF^{commit}"

EXPECTED_COMMIT="$(git -C "$SUBMODULE_PATH" rev-parse "$TAG_REF^{commit}")"
HEAD_COMMIT="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"

if [[ "$HEAD_COMMIT" != "$EXPECTED_COMMIT" ]]; then
	echo "Failed to checkout the expected commit for $RELEASE_TAG."
	echo "Expected: $EXPECTED_COMMIT"
	echo "Actual:   $HEAD_COMMIT"
	exit 1
fi
