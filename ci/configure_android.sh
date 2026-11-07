#!/usr/bin/env bash
# Install the Godot Android build template and point editor settings at the SDK.
# Expects ci/versions.env, a JDK on PATH, and $ANDROID_SDK_ROOT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/ci/versions.env"

: "${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT is required}"
: "${JAVA_HOME:?JAVA_HOME is required}"

TEMPLATE_DIR="${HOME}/.local/share/godot/export_templates/${GODOT_TEMPLATE_VERSION}"
SOURCE_ZIP="${TEMPLATE_DIR}/android_source.zip"
if [[ ! -f "$SOURCE_ZIP" ]]; then
	echo "Missing ${SOURCE_ZIP}. Install the pinned export templates first." >&2
	exit 1
fi

rm -rf "$ROOT/android"
mkdir -p "$ROOT/android/build"
unzip -q "$SOURCE_ZIP" -d "$ROOT/android/build"
printf '%s\n' "$GODOT_TEMPLATE_VERSION" > "$ROOT/android/.build_version"
: > "$ROOT/android/build/.gdignore"

KEYSTORE_DIR="${HOME}/.local/share/godot/keystores"
mkdir -p "$KEYSTORE_DIR"
KEYSTORE="${KEYSTORE_DIR}/debug.keystore"
if [[ ! -f "$KEYSTORE" ]]; then
	keytool -genkeypair \
		-keystore "$KEYSTORE" \
		-storepass android \
		-alias androiddebugkey \
		-keypass android \
		-keyalg RSA \
		-keysize 2048 \
		-validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US"
fi

python3 - "$JAVA_HOME" "$ANDROID_SDK_ROOT" "$KEYSTORE" << 'PY'
import pathlib, re, sys
java, sdk, keystore = sys.argv[1:]
path = pathlib.Path.home() / ".config" / "godot" / "editor_settings-4.7.tres"
if not path.exists():
    raise SystemExit(f"Missing {path}. Run a headless Godot import before this step.")
text = path.read_text()
updates = {
    "export/android/java_sdk_path": java,
    "export/android/android_sdk_path": sdk,
    "export/android/debug_keystore": keystore,
    "export/android/debug_keystore_pass": "android",
}
for key, value in updates.items():
    line = f'{key} = "{value}"'
    pattern = re.compile(rf"^{re.escape(key)} = .*$", re.M)
    if pattern.search(text):
        text = pattern.sub(line, text)
    else:
        text = text.rstrip() + "\n" + line + "\n"
path.write_text(text)
print(f"Updated {path}")
PY
