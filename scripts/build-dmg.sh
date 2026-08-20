#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build"
version="1.1.0"
volume_name="合わせろMusic"
app_dir="$build_dir/合わせろMusic.app"
dmg_path="$build_dir/合わせろMusic-$version.dmg"
checksum_path="$dmg_path.sha256"
staging_dir="$(mktemp -d "$build_dir/dmg-staging.XXXXXX")"

cleanup() {
    /bin/rm -rf "$staging_dir"
}
trap cleanup EXIT

"$project_dir/scripts/build-app.sh"
cp -R "$app_dir" "$staging_dir/合わせろMusic.app"
cp "$project_dir/LICENSE" "$staging_dir/LICENSE.txt"
cp "$project_dir/README.md" "$staging_dir/README.md"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov "$dmg_path"

sign_identity="${AWASERO_SIGN_IDENTITY:--}"
if [[ "$sign_identity" != "-" ]]; then
    codesign --force --sign "$sign_identity" "$dmg_path"
fi

notary_profile="${AWASERO_NOTARY_PROFILE:-}"
if [[ -n "$notary_profile" ]]; then
    if [[ "$sign_identity" == "-" ]]; then
        echo "AWASERO_NOTARY_PROFILEを使う場合はAWASERO_SIGN_IDENTITYも設定してください。" >&2
        exit 1
    fi
    xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
fi

shasum -a 256 "$dmg_path" > "$checksum_path"
echo "$dmg_path"
echo "$checksum_path"
