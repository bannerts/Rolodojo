#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-.}"

ANDROID_MANIFEST="$ROOT_DIR/android/app/src/main/AndroidManifest.xml"
IOS_PLIST="$ROOT_DIR/ios/Runner/Info.plist"

ensure_android_permission() {
  local manifest_path="$1"
  local permission_name="$2"

  if grep -q "android:name=\"$permission_name\"" "$manifest_path"; then
    return
  fi

  sed -i "/<manifest/a\\    <uses-permission android:name=\"$permission_name\"/>" "$manifest_path"
}

configure_android_permissions() {
  local manifest_path="$1"

  if [[ ! -f "$manifest_path" ]]; then
    echo "Android manifest not found at $manifest_path (skipping)."
    return
  fi

  ensure_android_permission "$manifest_path" "android.permission.USE_BIOMETRIC"
  ensure_android_permission "$manifest_path" "android.permission.USE_FINGERPRINT"
  ensure_android_permission "$manifest_path" "android.permission.ACCESS_FINE_LOCATION"
  ensure_android_permission "$manifest_path" "android.permission.ACCESS_COARSE_LOCATION"

  echo "Configured Android permissions in $manifest_path"
}

configure_ios_permissions() {
  local plist_path="$1"

  if [[ ! -f "$plist_path" ]]; then
    echo "iOS Info.plist not found at $plist_path (skipping)."
    return
  fi

  python3 - "$plist_path" <<'PY'
from pathlib import Path
import sys

plist_path = Path(sys.argv[1])
text = plist_path.read_text(encoding="utf-8")

def ensure_key_value(payload: str, key: str, value: str) -> str:
    if key in payload:
        return payload

    insertion = (
        f"\t<key>{key}</key>\n"
        f"\t<string>{value}</string>\n"
    )
    marker = "</dict>"
    idx = payload.find(marker)
    if idx == -1:
        raise RuntimeError(f"Unable to find </dict> in {plist_path}")
    return payload[:idx] + insertion + payload[idx:]

updated = ensure_key_value(
    text,
    "NSLocationWhenInUseUsageDescription",
    "ROLODOJO uses your location to attach GPS coordinates to each ledger entry.",
)
updated = ensure_key_value(
    updated,
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "ROLODOJO uses your location to attach GPS coordinates to each ledger entry.",
)

if updated != text:
    plist_path.write_text(updated, encoding="utf-8")
    print(f"Configured iOS location usage descriptions in {plist_path}")
else:
    print(f"iOS location usage descriptions already configured in {plist_path}")
PY
}

configure_android_permissions "$ANDROID_MANIFEST"
configure_ios_permissions "$IOS_PLIST"
