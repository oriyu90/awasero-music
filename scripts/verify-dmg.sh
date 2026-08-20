#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="1.1.0"
dmg_path="${1:-$project_dir/.build/合わせろMusic-$version.dmg}"
checksum_path="$dmg_path.sha256"
mount_dir="$(mktemp -d /tmp/awasero-dmg-XXXXXX)"
is_mounted=false

cleanup() {
    if [[ "$is_mounted" == true ]]; then
        hdiutil detach "$mount_dir" >/dev/null
    fi
    rmdir "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil verify "$dmg_path"
shasum -a 256 -c "$checksum_path"
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg_path" >/dev/null
is_mounted=true

test -d "$mount_dir/合わせろMusic.app"
test -L "$mount_dir/Applications"
test -f "$mount_dir/LICENSE.txt"
test -f "$mount_dir/README.md"
grep -q "Copyright (c) 2026 Yuki_Orita" "$mount_dir/LICENSE.txt"
codesign --verify --deep --strict "$mount_dir/合わせろMusic.app"
codesign -d --entitlements :- "$mount_dir/合わせろMusic.app" | grep -q "com.apple.security.device.audio-input"
plutil -lint "$mount_dir/合わせろMusic.app/Contents/Info.plist"
test -f "$mount_dir/合わせろMusic.app/Contents/Resources/LICENSE.txt"

echo "DMG verification passed"
