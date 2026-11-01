#!/usr/bin/env bash
# Publish the web export to gh-pages and the debug APK as a public prerelease.
# Runs in GitHub Actions on push. GITHUB_TOKEN must be able to write contents.
set -euo pipefail

: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_SHA:?}"
: "${GITHUB_REF:?}"
: "${GH_TOKEN:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="${ROOT}/build/web"
APK="${ROOT}/build/android/dockside-sort-debug.apk"
[[ -f "$WEB/index.html" ]] || { echo "Missing web export" >&2; exit 1; }
[[ -f "$APK" ]] || { echo "Missing APK" >&2; exit 1; }
grep -q "const GODOT_THREADS_ENABLED = false;" "$WEB/index.html"

if [[ "$GITHUB_REF" == "refs/heads/main" ]]; then
	DEST=""
	TAG="main-debug"
else
	PR="$(gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls" --jq '.[0].number // empty' || true)"
	if [[ -n "${PR}" ]]; then
		DEST="pr-${PR}"
		TAG="pr-${PR}"
	else
		SAFE="$(printf '%s' "${GITHUB_REF_NAME}" | tr -c 'A-Za-z0-9._-' '-')"
		DEST="branch-${SAFE}"
		TAG="branch-${SAFE}"
		echo "No open pull request for ${GITHUB_SHA} yet. Publishing under /${DEST}/ and release ${TAG}."
	fi
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

AUTH_HEADER="AUTHORIZATION: bearer ${GH_TOKEN}"
if git ls-remote --heads "https://github.com/${GITHUB_REPOSITORY}.git" gh-pages | grep -q gh-pages; then
	git -c "http.extraheader=${AUTH_HEADER}" clone --branch gh-pages --single-branch --depth 1 \
		"https://github.com/${GITHUB_REPOSITORY}.git" "$WORK"
else
	git -C "$WORK" init -b gh-pages
	git -C "$WORK" remote add origin "https://github.com/${GITHUB_REPOSITORY}.git"
fi

touch "$WORK/.nojekyll"
if [[ -z "$DEST" ]]; then
	find "$WORK" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name '.nojekyll' ! -name 'pr-*' ! -name 'branch-*' -exec rm -rf {} +
	cp -a "$WEB"/. "$WORK"/
else
	rm -rf "$WORK/$DEST"
	mkdir -p "$WORK/$DEST"
	cp -a "$WEB"/. "$WORK/$DEST"/
fi

git -C "$WORK" add -A
if git -C "$WORK" diff --cached --quiet; then
	echo "Web export matches the existing gh-pages tree."
else
	git -C "$WORK" \
		-c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
		-c user.name="github-actions[bot]" \
		commit -m "Playtest web build ${TAG} (${GITHUB_SHA})"
	for attempt in 1 2 3 4; do
		if git -C "$WORK" -c "http.extraheader=${AUTH_HEADER}" push origin gh-pages; then
			break
		fi
		if [[ "$attempt" -eq 4 ]]; then
			echo "Failed to push gh-pages" >&2
			exit 1
		fi
		git -C "$WORK" -c "http.extraheader=${AUTH_HEADER}" pull --rebase origin gh-pages || true
		sleep $((2 ** attempt))
	done
fi

NOTES="Debug APK for phone playtesting. Signed with a CI debug keystore, not a store key. Android will ask you to allow installs from the browser."
if gh release view "$TAG" >/dev/null 2>&1; then
	gh release upload "$TAG" "$APK" --clobber
else
	gh release create "$TAG" --prerelease --title "Dockside Sort playtest ${TAG}" --notes "$NOTES" "$APK"
fi

if [[ -z "$DEST" ]]; then
	echo "WEB_URL=https://tscook93-dev.github.io/dockside-sort/"
else
	echo "WEB_URL=https://tscook93-dev.github.io/dockside-sort/${DEST}/"
fi
echo "APK_URL=https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG}/dockside-sort-debug.apk"

# Enabling Pages needs repo admin, which the Actions token often does not have.
# A failed call must not fail the build; the log says what is still manual.
PAGES_BODY='{"build_type":"legacy","source":{"branch":"gh-pages","path":"/"}}'
gh api --method POST "repos/${GITHUB_REPOSITORY}/pages" --input - <<<"$PAGES_BODY" >/dev/null 2>&1 \
	|| gh api --method PUT "repos/${GITHUB_REPOSITORY}/pages" --input - <<<"$PAGES_BODY" >/dev/null 2>&1 \
	|| echo "GitHub Pages was not enabled from Actions. Turn it on under Settings, Pages, Deploy from branch gh-pages, folder / (root)."
